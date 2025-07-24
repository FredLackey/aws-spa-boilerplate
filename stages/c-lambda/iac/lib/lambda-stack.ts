import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface LambdaStackProps extends cdk.StackProps {
  distributionPrefix: string;
  targetRegion: string;
  targetVpcId: string;
  distributionId: string;
  bucketName: string;
  codePath?: string; // Optional code path for testing
}

export class LambdaStack extends cdk.Stack {
  public readonly lambdaFunction: lambda.Function;
  public readonly functionUrl: lambda.FunctionUrl;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: LambdaStackProps) {
    super(scope, id, props);

    const { distributionPrefix, targetRegion, targetVpcId, distributionId, bucketName, codePath } = props;

    // Create CloudWatch log group with 30-day retention
    this.logGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/${distributionPrefix}-api`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM execution role for Lambda function
    const executionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${distributionPrefix}-lambda-execution-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
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
                `arn:aws:logs:${targetRegion}:${cdk.Aws.ACCOUNT_ID}:log-group:/aws/lambda/${distributionPrefix}-api*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda function
    this.lambdaFunction = new lambda.Function(this, 'ApiLambda', {
      functionName: `${distributionPrefix}-api`,
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(codePath || '../../../apps/hello-world-lambda'),
      memorySize: 128,
      timeout: cdk.Duration.seconds(30),
      role: executionRole,
      logGroup: this.logGroup,
      environment: {
        DISTRIBUTION_PREFIX: distributionPrefix,
        TARGET_REGION: targetRegion,
        DISTRIBUTION_ID: distributionId,
        BUCKET_NAME: bucketName,
      },
      description: `Stage C API Lambda Function - ${distributionPrefix}`,
    });

    // Create Function URL with AWS_IAM auth type
    this.functionUrl = this.lambdaFunction.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.AWS_IAM,
      cors: {
        allowCredentials: false,
        allowedHeaders: ['Content-Type', 'Authorization'],
        allowedMethods: [lambda.HttpMethod.GET, lambda.HttpMethod.POST],
        allowedOrigins: ['*'],
        maxAge: cdk.Duration.minutes(5),
      },
    });

    // Grant invoke permissions to the function URL
    this.lambdaFunction.grantInvokeUrl(new iam.ServicePrincipal('lambda.amazonaws.com'));

    // Stack outputs for subsequent stages and validation
    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'Lambda Function ARN',
      exportName: `${distributionPrefix}-lambda-function-arn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Lambda Function Name',
      exportName: `${distributionPrefix}-lambda-function-name`,
    });

    new cdk.CfnOutput(this, 'FunctionUrl', {
      value: this.functionUrl.url,
      description: 'Lambda Function URL',
      exportName: `${distributionPrefix}-lambda-function-url`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group Name',
      exportName: `${distributionPrefix}-lambda-log-group`,
    });

    new cdk.CfnOutput(this, 'TargetRegion', {
      value: targetRegion,
      description: 'Target Region for Lambda Deployment',
      exportName: `${distributionPrefix}-lambda-target-region`,
    });

    new cdk.CfnOutput(this, 'DistributionPrefix', {
      value: distributionPrefix,
      description: 'Distribution Prefix Used',
      exportName: `${distributionPrefix}-lambda-prefix`,
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: distributionId,
      description: 'CloudFront Distribution ID (from previous stages)',
      exportName: `${distributionPrefix}-lambda-distribution-id`,
    });

    new cdk.CfnOutput(this, 'BucketName', {
      value: bucketName,
      description: 'S3 Bucket Name (from previous stages)',
      exportName: `${distributionPrefix}-lambda-bucket-name`,
    });

    // Add tags for resource identification
    cdk.Tags.of(this).add('Stage', 'C-Lambda');
    cdk.Tags.of(this).add('Component', 'Lambda-Function');
    cdk.Tags.of(this).add('Environment', cdk.Aws.ACCOUNT_ID);
    cdk.Tags.of(this).add('DistributionPrefix', distributionPrefix);
    cdk.Tags.of(this).add('Runtime', 'nodejs20.x');
  }
} 