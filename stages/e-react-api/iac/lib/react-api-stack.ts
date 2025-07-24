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

    // Import existing S3 bucket from Stage A
    this.s3Bucket = s3.Bucket.fromBucketName(this, 'ImportedS3Bucket', bucketName);

    // Import existing CloudFront distribution from Stage A
    this.cloudFrontDistribution = cloudfront.Distribution.fromDistributionAttributes(this, 'ImportedCloudFrontDistribution', {
      distributionId: distributionId,
      domainName: `${distributionId}.cloudfront.net`,
    });
    
    // Store the domain name for outputs since IDistribution doesn't expose it
    const distributionDomainName = `${distributionId}.cloudfront.net`;

    // Create a simple custom resource to update cache behaviors using CloudFormation
    const cfnDistribution = new cloudfront.CfnDistribution(this, 'UpdatedDistribution', {
      distributionConfig: {
        aliases: [primaryDomain, `www.${primaryDomain}`],
        enabled: true,
        httpVersion: 'http2',
        ipv6Enabled: true,
        priceClass: 'PriceClass_100',
        origins: [
          {
            id: 'S3Origin',
            domainName: `${bucketName}.s3.${targetRegion}.amazonaws.com`,
            s3OriginConfig: {
              originAccessIdentity: '',
            },
            originAccessControlId: 'E12JBGQ3RC7J38', // From Stage A
          },
          {
            id: 'LambdaOrigin',
            domainName: lambdaFunctionUrl.replace('https://', '').split('/')[0],
            customOriginConfig: {
              httpPort: 443,
              httpsPort: 443,
              originProtocolPolicy: 'https-only',
              originSslProtocols: ['TLSv1.2'],
              originReadTimeout: 30,
              originKeepaliveTimeout: 5,
            },
          },
        ],
        defaultCacheBehavior: {
          targetOriginId: 'S3Origin',
          viewerProtocolPolicy: 'redirect-to-https',
          cachePolicyId: '658327ea-f89d-4fab-a63d-7e88639e58f6', // CachingOptimized
          originRequestPolicyId: '88a5eaf4-2fd4-4709-b370-b4c650ea3fcf', // CORS-S3Origin
          compress: true,
          allowedMethods: ['GET', 'HEAD'],
          cachedMethods: ['GET', 'HEAD'],
        },
        cacheBehaviors: [
          {
            pathPattern: '/api/*',
            targetOriginId: 'LambdaOrigin',
            viewerProtocolPolicy: 'redirect-to-https',
            cachePolicyId: '4135ea2d-6df8-44a3-9df3-4b5a84be39ad', // CachingDisabled
            originRequestPolicyId: '88a5eaf4-2fd4-4709-b370-b4c650ea3fcf', // CORS-S3Origin
            compress: true,
            allowedMethods: ['GET', 'HEAD', 'OPTIONS', 'PUT', 'POST', 'PATCH', 'DELETE'],
            cachedMethods: ['GET', 'HEAD'],
          },
        ],
        viewerCertificate: {
          acmCertificateArn: certificateArn,
          sslSupportMethod: 'sni-only',
          minimumProtocolVersion: 'TLSv1.2_2021',
        },
      },
    });

    // Override the physical ID to match the existing distribution
    cfnDistribution.overrideLogicalId('ExistingDistribution');

    // Create IAM role for React API deployment automation
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
} 