import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export interface ReactStackProps extends cdk.StackProps {
  distributionPrefix: string;
  targetRegion: string;
  targetProfile?: string;
  infrastructureProfile?: string;
  targetVpcId: string;
  distributionId: string;
  bucketName: string;
  primaryDomain: string;
  certificateArn: string;
  lambdaFunctionUrl?: string;
}

export class ReactStack extends cdk.Stack {
  public readonly s3Bucket: s3.IBucket;
  public readonly cloudFrontDistribution: cloudfront.IDistribution;
  public readonly deploymentRole: iam.Role;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: ReactStackProps) {
    super(scope, id, props);

    const {
      distributionPrefix,
      targetRegion,
      targetVpcId,
      distributionId,
      bucketName,
      primaryDomain,
      certificateArn,
      lambdaFunctionUrl,
    } = props;

    // Create CloudWatch log group for React deployment activities
    this.logGroup = new logs.LogGroup(this, 'ReactDeploymentLogGroup', {
      logGroupName: `/aws/react-deployment/${distributionPrefix}`,
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

    // Create IAM role for React deployment automation (if needed for future automation)
    this.deploymentRole = new iam.Role(this, 'ReactDeploymentRole', {
      roleName: `${distributionPrefix}-react-deployment-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for automated React deployment tasks',
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

    // Create custom resource for deployment status tracking (optional)
    const deploymentStatus = new cdk.CustomResource(this, 'ReactDeploymentStatus', {
      serviceToken: this.createDeploymentStatusProvider().serviceToken,
      properties: {
        DistributionPrefix: distributionPrefix,
        BucketName: bucketName,
        DistributionId: distributionId,
        PrimaryDomain: primaryDomain,
        LambdaFunctionUrl: lambdaFunctionUrl || '',
        DeploymentTimestamp: new Date().toISOString(),
      },
    });

    // Output important values for reference
    new cdk.CfnOutput(this, 'ReactS3BucketName', {
      value: this.s3Bucket.bucketName,
      description: 'S3 bucket name for React application content',
      exportName: `${distributionPrefix}-react-s3-bucket`,
    });

    new cdk.CfnOutput(this, 'ReactCloudFrontDistributionId', {
      value: distributionId,
      description: 'CloudFront distribution ID serving React application',
      exportName: `${distributionPrefix}-react-cloudfront-id`,
    });

    new cdk.CfnOutput(this, 'ReactCloudFrontDomainName', {
      value: this.cloudFrontDistribution.domainName,
      description: 'CloudFront distribution domain name',
      exportName: `${distributionPrefix}-react-cloudfront-domain`,
    });

    new cdk.CfnOutput(this, 'ReactPrimaryDomain', {
      value: primaryDomain,
      description: 'Primary domain name for React application',
      exportName: `${distributionPrefix}-react-primary-domain`,
    });

    new cdk.CfnOutput(this, 'ReactDeploymentRoleArn', {
      value: this.deploymentRole.roleArn,
      description: 'IAM role ARN for React deployment automation',
      exportName: `${distributionPrefix}-react-deployment-role`,
    });

    new cdk.CfnOutput(this, 'ReactLogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch log group for React deployment',
      exportName: `${distributionPrefix}-react-log-group`,
    });

    // Add stack tags for better resource management
    cdk.Tags.of(this).add('Component', 'React-Deployment');
    cdk.Tags.of(this).add('Stage', 'D');
    cdk.Tags.of(this).add('IntegratesWithStageA', 'true');
    cdk.Tags.of(this).add('IntegratesWithStageB', 'true');
    cdk.Tags.of(this).add('IntegratesWithStageC', 'true');
  }

  /**
   * Creates a Lambda-backed custom resource provider for deployment status tracking
   */
  private createDeploymentStatusProvider(): cdk.custom_resources.Provider {
    // Create a simple Lambda function for the custom resource
    const statusLambda = new cdk.aws_lambda.Function(this, 'DeploymentStatusLambda', {
      runtime: cdk.aws_lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: cdk.aws_lambda.Code.fromInline(`
        exports.handler = async (event) => {
          console.log('Deployment Status Event:', JSON.stringify(event, null, 2));
          
          const response = {
            Status: 'SUCCESS',
            Reason: 'React deployment status recorded',
            PhysicalResourceId: 'react-deployment-' + Date.now(),
            Data: {
              DeploymentStatus: 'SUCCESS',
              Timestamp: new Date().toISOString(),
              DistributionPrefix: event.ResourceProperties.DistributionPrefix,
              BucketName: event.ResourceProperties.BucketName,
              DistributionId: event.ResourceProperties.DistributionId,
            }
          };
          
          return response;
        };
      `),
      description: 'Custom resource for React deployment status tracking',
      timeout: cdk.Duration.minutes(5),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Grant the Lambda function permissions to write to the log group
    this.logGroup.grantWrite(statusLambda);

    return new cdk.custom_resources.Provider(this, 'DeploymentStatusProvider', {
      onEventHandler: statusLambda,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });
  }
} 