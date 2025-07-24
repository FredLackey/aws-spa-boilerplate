import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export interface ReactApiStackProps extends cdk.StackProps {
  distributionPrefix: string;
  targetRegion: string;
  targetProfile?: string;
  infrastructureProfile?: string;
  targetVpcId: string;
  distributionId: string;
  bucketName: string;
  primaryDomain: string;
  certificateArn: string;
  lambdaFunctionArn: string;
  lambdaFunctionUrl: string;
}

export class ReactApiStack extends cdk.Stack {
  public readonly s3Bucket: s3.IBucket;
  public readonly cloudFrontDistribution: cloudfront.IDistribution;
  public readonly deploymentRole: iam.Role;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: ReactApiStackProps) {
    super(scope, id, props);

    const {
      distributionPrefix,
      targetRegion,
      targetVpcId,
      distributionId,
      bucketName,
      primaryDomain,
      certificateArn,
      lambdaFunctionArn,
      lambdaFunctionUrl,
    } = props;

    // Create CloudWatch log group for React API deployment activities
    this.logGroup = new logs.LogGroup(this, 'ReactApiDeploymentLogGroup', {
      logGroupName: `/aws/react-api-deployment/${distributionPrefix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Import existing S3 bucket from Stage A (do not create new one)
    this.s3Bucket = s3.Bucket.fromBucketName(this, 'ImportedS3Bucket', bucketName);

    // Import existing CloudFront distribution from Stage A (do not modify)
    this.cloudFrontDistribution = cloudfront.Distribution.fromDistributionAttributes(this, 'ImportedCloudFrontDistribution', {
      distributionId: distributionId,
      domainName: `${distributionId}.cloudfront.net`,
    });
    
    // Store the domain name for outputs since IDistribution doesn't expose it
    const distributionDomainName = `${distributionId}.cloudfront.net`;

    // Create IAM role for React API deployment automation (if needed for future automation)
    this.deploymentRole = new iam.Role(this, 'ReactApiDeploymentRole', {
      roleName: `${distributionPrefix}-react-api-deployment-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for automated React API deployment tasks',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        S3DeploymentPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                this.s3Bucket.bucketArn,
                `${this.s3Bucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        CloudFrontInvalidationPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudfront:CreateInvalidation',
                'cloudfront:GetInvalidation',
                'cloudfront:ListInvalidations',
                'cloudfront:UpdateDistribution',
                'cloudfront:GetDistribution',
                'cloudfront:GetDistributionConfig',
              ],
              resources: [
                `arn:aws:cloudfront::${cdk.Aws.ACCOUNT_ID}:distribution/${distributionId}`,
              ],
            }),
          ],
        }),
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [
                this.logGroup.logGroupArn,
                `${this.logGroup.logGroupArn}:*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create custom resource for API behavior configuration
    const apiBehaviorConfig = new cdk.CustomResource(this, 'ApiBehaviorConfiguration', {
      serviceToken: this.createApiBehaviorProvider().serviceToken,
      properties: {
        DistributionPrefix: distributionPrefix,
        DistributionId: distributionId,
        LambdaFunctionUrl: lambdaFunctionUrl,
        LambdaFunctionArn: lambdaFunctionArn,
        PrimaryDomain: primaryDomain,
        DeploymentTimestamp: new Date().toISOString(),
      },
    });

    // Output important values for reference
    new cdk.CfnOutput(this, 'ReactApiS3BucketName', {
      value: this.s3Bucket.bucketName,
      description: 'S3 bucket name for React application content',
      exportName: `${distributionPrefix}-react-api-s3-bucket`,
    });

    new cdk.CfnOutput(this, 'ReactApiCloudFrontDistributionId', {
      value: distributionId,
      description: 'CloudFront distribution ID serving React application with API',
      exportName: `${distributionPrefix}-react-api-cloudfront-id`,
    });

    new cdk.CfnOutput(this, 'ReactApiCloudFrontDomainName', {
      value: distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${distributionPrefix}-react-api-cloudfront-domain`,
    });

    new cdk.CfnOutput(this, 'ReactApiPrimaryDomain', {
      value: primaryDomain,
      description: 'Primary domain name for React application with API',
      exportName: `${distributionPrefix}-react-api-primary-domain`,
    });

    new cdk.CfnOutput(this, 'ReactApiLambdaFunctionUrl', {
      value: lambdaFunctionUrl,
      description: 'Lambda Function URL for API integration',
      exportName: `${distributionPrefix}-react-api-lambda-url`,
    });

    new cdk.CfnOutput(this, 'ReactApiLambdaFunctionArn', {
      value: lambdaFunctionArn,
      description: 'Lambda Function ARN for API integration',
      exportName: `${distributionPrefix}-react-api-lambda-arn`,
    });

    new cdk.CfnOutput(this, 'ReactApiDeploymentRoleArn', {
      value: this.deploymentRole.roleArn,
      description: 'IAM role ARN for React API deployment automation',
      exportName: `${distributionPrefix}-react-api-deployment-role`,
    });

    new cdk.CfnOutput(this, 'ReactApiLogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch log group for React API deployment',
      exportName: `${distributionPrefix}-react-api-log-group`,
    });

    // Add CloudFront behavior configuration outputs
    new cdk.CfnOutput(this, 'ReactApiApiBehaviorPattern', {
      value: '/api/*',
      description: 'CloudFront behavior path pattern for API routes',
      exportName: `${distributionPrefix}-react-api-behavior-pattern`,
    });

    new cdk.CfnOutput(this, 'ReactApiApiBehaviorPrecedence', {
      value: '0',
      description: 'CloudFront behavior precedence for API routes (highest priority)',
      exportName: `${distributionPrefix}-react-api-behavior-precedence`,
    });

    // Add stack tags for better resource management
    cdk.Tags.of(this).add('Component', 'React-API-Deployment');
    cdk.Tags.of(this).add('Stage', 'E');
    cdk.Tags.of(this).add('IntegratesWithStageA', 'true');
    cdk.Tags.of(this).add('IntegratesWithStageB', 'true');
    cdk.Tags.of(this).add('IntegratesWithStageC', 'true');
    cdk.Tags.of(this).add('IntegratesWithStageD', 'true');
  }

  /**
   * Creates a Lambda-backed custom resource provider for API behavior configuration
   */
  private createApiBehaviorProvider(): cdk.custom_resources.Provider {
    // Create a Lambda function for configuring CloudFront API behavior
    const apiBehaviorLambda = new cdk.aws_lambda.Function(this, 'ApiBehaviorLambda', {
      runtime: cdk.aws_lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: cdk.aws_lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const cloudfront = new AWS.CloudFront();
        const response = require('cfn-response');

        exports.handler = async (event, context) => {
          console.log('API Behavior Configuration Event:', JSON.stringify(event, null, 2));
          
          try {
            const { DistributionId, LambdaFunctionUrl, RequestType } = event.ResourceProperties;
            
            if (RequestType === 'Create' || RequestType === 'Update') {
              // Get current distribution configuration
              const getResult = await cloudfront.getDistributionConfig({
                Id: DistributionId
              }).promise();
              
              const config = getResult.DistributionConfig;
              const etag = getResult.ETag;
              
              // Extract domain from Lambda Function URL (remove https:// and path)
              const lambdaOriginDomain = LambdaFunctionUrl.replace('https://', '').split('/')[0];
              
              // Add Lambda Function URL as origin if not exists
              const lambdaOriginId = 'lambda-api-origin';
              const existingOrigin = config.Origins.Items.find(origin => origin.Id === lambdaOriginId);
              
              if (!existingOrigin) {
                config.Origins.Items.push({
                  Id: lambdaOriginId,
                  DomainName: lambdaOriginDomain,
                  CustomOriginConfig: {
                    HTTPPort: 443,
                    HTTPSPort: 443,
                    OriginProtocolPolicy: 'https-only',
                  }
                });
                config.Origins.Quantity = config.Origins.Items.length;
              }
              
              // Add API behavior if not exists
              const apiBehavior = {
                PathPattern: '/api/*',
                TargetOriginId: lambdaOriginId,
                ViewerProtocolPolicy: 'redirect-to-https',
                CachePolicyId: '4135ea2d-6df8-44a3-9df3-4b5a84be39ad', // CachingDisabled policy
                OriginRequestPolicyId: '88a5eaf4-2fd4-4709-b370-b4c650ea3fcf', // CORS-S3Origin policy
                Compress: true,
                AllowedMethods: {
                  Quantity: 7,
                  Items: ['GET', 'HEAD', 'OPTIONS', 'PUT', 'POST', 'PATCH', 'DELETE'],
                  CachedMethods: {
                    Quantity: 2,
                    Items: ['GET', 'HEAD']
                  }
                }
              };
              
              // Check if API behavior already exists
              const existingBehavior = config.CacheBehaviors.Items.find(behavior => 
                behavior.PathPattern === '/api/*'
              );
              
              if (!existingBehavior) {
                config.CacheBehaviors.Items.unshift(apiBehavior); // Add at beginning for highest precedence
                config.CacheBehaviors.Quantity = config.CacheBehaviors.Items.length;
              }
              
              // Update distribution
              await cloudfront.updateDistribution({
                Id: DistributionId,
                DistributionConfig: config,
                IfMatch: etag
              }).promise();
              
              console.log('CloudFront distribution updated with API behavior');
            }
            
            await response.send(event, context, response.SUCCESS, {
              ApiBehaviorConfigured: 'true',
              ApiBehaviorPattern: '/api/*',
              ApiBehaviorPrecedence: '0',
              Timestamp: new Date().toISOString()
            });
            
          } catch (error) {
            console.error('Error configuring API behavior:', error);
            await response.send(event, context, response.FAILED, {
              Error: error.message
            });
          }
        };
      `),
      description: 'Custom resource for CloudFront API behavior configuration',
      timeout: cdk.Duration.minutes(10),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Grant the Lambda function permissions to modify CloudFront
    apiBehaviorLambda.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudfront:GetDistribution',
        'cloudfront:GetDistributionConfig',
        'cloudfront:UpdateDistribution',
        'cloudfront:CreateInvalidation',
      ],
      resources: ['*'], // CloudFront actions don't support resource-level permissions
    }));

    // Grant the Lambda function permissions to write to the log group
    this.logGroup.grantWrite(apiBehaviorLambda);

    return new cdk.custom_resources.Provider(this, 'ApiBehaviorProvider', {
      onEventHandler: apiBehaviorLambda,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });
  }
} 