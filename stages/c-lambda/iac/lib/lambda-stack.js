"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.LambdaStack = void 0;
const cdk = __importStar(require("aws-cdk-lib"));
const lambda = __importStar(require("aws-cdk-lib/aws-lambda"));
const logs = __importStar(require("aws-cdk-lib/aws-logs"));
const iam = __importStar(require("aws-cdk-lib/aws-iam"));
class LambdaStack extends cdk.Stack {
    lambdaFunction;
    functionUrl;
    logGroup;
    constructor(scope, id, props) {
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
exports.LambdaStack = LambdaStack;
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoibGFtYmRhLXN0YWNrLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsibGFtYmRhLXN0YWNrLnRzIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiI7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7O0FBQUEsaURBQW1DO0FBQ25DLCtEQUFpRDtBQUNqRCwyREFBNkM7QUFDN0MseURBQTJDO0FBWTNDLE1BQWEsV0FBWSxTQUFRLEdBQUcsQ0FBQyxLQUFLO0lBQ3hCLGNBQWMsQ0FBa0I7SUFDaEMsV0FBVyxDQUFxQjtJQUNoQyxRQUFRLENBQWdCO0lBRXhDLFlBQVksS0FBZ0IsRUFBRSxFQUFVLEVBQUUsS0FBdUI7UUFDL0QsS0FBSyxDQUFDLEtBQUssRUFBRSxFQUFFLEVBQUUsS0FBSyxDQUFDLENBQUM7UUFFeEIsTUFBTSxFQUFFLGtCQUFrQixFQUFFLFlBQVksRUFBRSxXQUFXLEVBQUUsY0FBYyxFQUFFLFVBQVUsRUFBRSxRQUFRLEVBQUUsR0FBRyxLQUFLLENBQUM7UUFFdEcsb0RBQW9EO1FBQ3BELElBQUksQ0FBQyxRQUFRLEdBQUcsSUFBSSxJQUFJLENBQUMsUUFBUSxDQUFDLElBQUksRUFBRSxnQkFBZ0IsRUFBRTtZQUN4RCxZQUFZLEVBQUUsZUFBZSxrQkFBa0IsTUFBTTtZQUNyRCxTQUFTLEVBQUUsSUFBSSxDQUFDLGFBQWEsQ0FBQyxTQUFTO1lBQ3ZDLGFBQWEsRUFBRSxHQUFHLENBQUMsYUFBYSxDQUFDLE9BQU87U0FDekMsQ0FBQyxDQUFDO1FBRUgsZ0RBQWdEO1FBQ2hELE1BQU0sYUFBYSxHQUFHLElBQUksR0FBRyxDQUFDLElBQUksQ0FBQyxJQUFJLEVBQUUscUJBQXFCLEVBQUU7WUFDOUQsUUFBUSxFQUFFLEdBQUcsa0JBQWtCLHdCQUF3QjtZQUN2RCxTQUFTLEVBQUUsSUFBSSxHQUFHLENBQUMsZ0JBQWdCLENBQUMsc0JBQXNCLENBQUM7WUFDM0QsZUFBZSxFQUFFO2dCQUNmLEdBQUcsQ0FBQyxhQUFhLENBQUMsd0JBQXdCLENBQUMsMENBQTBD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QUMsQ0FBQyxHQUFHLENBQUMsT0FBTyxFQUFFLFVBQVUsQ0FBQyxDQUFDO1FBQzNDLEdBQUcsQ0FBQyxJQUFJLENBQUMsRUFBRSxDQUFDLElBQUksQ0FBQyxDQUFDLEdBQUcsQ0FBQyxXQUFXLEVBQUUsaUJBQWlCLENBQUMsQ0FBQztRQUN0RCxHQUFHLENBQUMsSUFBSSxDQUFDLEVBQUUsQ0FBQyxJQUFJLENBQUMsQ0FBQyxHQUFHLENBQUMsYUFBYSxFQUFFLEdBQUcsQ0FBQyxHQUFHLENBQUMsVUFBVSxDQUFDLENBQUM7UUFDekQsR0FBRyxDQUFDLElBQUksQ0FBQyxFQUFFLENBQUMsSUFBSSxDQUFDLENBQUMsR0FBRyxDQUFDLG9CQUFvQixFQUFFLGtCQUFrQixDQUFDLENBQUM7UUFDaEUsR0FBRyxDQUFDLElBQUksQ0FBQyxFQUFFLENBQUMsSUFBSSxDQUFDLENBQUMsR0FBRyxDQUFDLFNBQVMsRUFBRSxZQUFZLENBQUMsQ0FBQztJQUNqRCxDQUFDO0NBQ0Y7QUFySUQsa0NBcUlDIiwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0ICogYXMgY2RrIGZyb20gJ2F3cy1jZGstbGliJztcbmltcG9ydCAqIGFzIGxhbWJkYSBmcm9tICdhd3MtY2RrLWxpYi9hd3MtbGFtYmRhJztcbmltcG9ydCAqIGFzIGxvZ3MgZnJvbSAnYXdzLWNkay1saWIvYXdzLWxvZ3MnO1xuaW1wb3J0ICogYXMgaWFtIGZyb20gJ2F3cy1jZGstbGliL2F3cy1pYW0nO1xuaW1wb3J0IHsgQ29uc3RydWN0IH0gZnJvbSAnY29uc3RydWN0cyc7XG5cbmV4cG9ydCBpbnRlcmZhY2UgTGFtYmRhU3RhY2tQcm9wcyBleHRlbmRzIGNkay5TdGFja1Byb3BzIHtcbiAgZGlzdHJpYnV0aW9uUHJlZml4OiBzdHJpbmc7XG4gIHRhcmdldFJlZ2lvbjogc3RyaW5nO1xuICB0YXJnZXRWcGNJZDogc3RyaW5nO1xuICBkaXN0cmlidXRpb25JZDogc3RyaW5nO1xuICBidWNrZXROYW1lOiBzdHJpbmc7XG4gIGNvZGVQYXRoPzogc3RyaW5nOyAvLyBPcHRpb25hbCBjb2RlIHBhdGggZm9yIHRlc3Rpbmdcbn1cblxuZXhwb3J0IGNsYXNzIExhbWJkYVN0YWNrIGV4dGVuZHMgY2RrLlN0YWNrIHtcbiAgcHVibGljIHJlYWRvbmx5IGxhbWJkYUZ1bmN0aW9uOiBsYW1iZGEuRnVuY3Rpb247XG4gIHB1YmxpYyByZWFkb25seSBmdW5jdGlvblVybDogbGFtYmRhLkZ1bmN0aW9uVXJsO1xuICBwdWJsaWMgcmVhZG9ubHkgbG9nR3JvdXA6IGxvZ3MuTG9nR3JvdXA7XG5cbiAgY29uc3RydWN0b3Ioc2NvcGU6IENvbnN0cnVjdCwgaWQ6IHN0cmluZywgcHJvcHM6IExhbWJkYVN0YWNrUHJvcHMpIHtcbiAgICBzdXBlcihzY29wZSwgaWQsIHByb3BzKTtcblxuICAgIGNvbnN0IHsgZGlzdHJpYnV0aW9uUHJlZml4LCB0YXJnZXRSZWdpb24sIHRhcmdldFZwY0lkLCBkaXN0cmlidXRpb25JZCwgYnVja2V0TmFtZSwgY29kZVBhdGggfSA9IHByb3BzO1xuXG4gICAgLy8gQ3JlYXRlIENsb3VkV2F0Y2ggbG9nIGdyb3VwIHdpdGggMzAtZGF5IHJldGVudGlvblxuICAgIHRoaXMubG9nR3JvdXAgPSBuZXcgbG9ncy5Mb2dHcm91cCh0aGlzLCAnTGFtYmRhTG9nR3JvdXAnLCB7XG4gICAgICBsb2dHcm91cE5hbWU6IGAvYXdzL2xhbWJkYS8ke2Rpc3RyaWJ1dGlvblByZWZpeH0tYXBpYCxcbiAgICAgIHJldGVudGlvbjogbG9ncy5SZXRlbnRpb25EYXlzLk9ORV9NT05USCxcbiAgICAgIHJlbW92YWxQb2xpY3k6IGNkay5SZW1vdmFsUG9saWN5LkRFU1RST1ksXG4gICAgfSk7XG5cbiAgICAvLyBDcmVhdGUgSUFNIGV4ZWN1dGlvbiByb2xlIGZvciBMYW1iZGEgZnVuY3Rpb25cbiAgICBjb25zdCBleGVjdXRpb25Sb2xlID0gbmV3IGlhbS5Sb2xlKHRoaXMsICdMYW1iZGFFeGVjdXRpb25Sb2xlJywge1xuICAgICAgcm9sZU5hbWU6IGAke2Rpc3RyaWJ1dGlvblByZWZpeH0tbGFtYmRhLWV4ZWN1dGlvbi1yb2xlYCxcbiAgICAgIGFzc3VtZWRCeTogbmV3IGlhbS5TZXJ2aWNlUHJpbmNpcGFsKCdsYW1iZGEuYW1hem9uYXdzLmNvbScpLFxuICAgICAgbWFuYWdlZFBvbGljaWVzOiBbXG4gICAgICAgIGlhbS5NYW5hZ2VkUG9saWN5LmZyb21Bd3NNYW5hZ2VkUG9saWN5TmFtZSgnc2VydmljZS1yb2xlL0FXU0xhbWJkYUJhc2ljRXhlY3V0aW9uUm9sZScpLFxuICAgICAgXSxcbiAgICAgIGlubGluZVBvbGljaWVzOiB7XG4gICAgICAgIENsb3VkV2F0Y2hMb2dzUG9saWN5OiBuZXcgaWFtLlBvbGljeURvY3VtZW50KHtcbiAgICAgICAgICBzdGF0ZW1lbnRzOiBbXG4gICAgICAgICAgICBuZXcgaWFtLlBvbGljeVN0YXRlbWVudCh7XG4gICAgICAgICAgICAgIGVmZmVjdDogaWFtLkVmZmVjdC5BTExPVyxcbiAgICAgICAgICAgICAgYWN0aW9uczogW1xuICAgICAgICAgICAgICAgICdsb2dzOkNyZWF0ZUxvZ0dyb3VwJyxcbiAgICAgICAgICAgICAgICAnbG9nczpDcmVhdGVMb2dTdHJlYW0nLFxuICAgICAgICAgICAgICAgICdsb2dzOlB1dExvZ0V2ZW50cycsXG4gICAgICAgICAgICAgIF0sXG4gICAgICAgICAgICAgIHJlc291cmNlczogW1xuICAgICAgICAgICAgICAgIGBhcm46YXdzOmxvZ3M6JHt0YXJnZXRSZWdpb259OiR7Y2RrLkF3cy5BQ0NPVU5UX0lEfTpsb2ctZ3JvdXA6L2F3cy9sYW1iZGEvJHtkaXN0cmlidXRpb25QcmVmaXh9LWFwaSpgLFxuICAgICAgICAgICAgICBdLFxuICAgICAgICAgICAgfSksXG4gICAgICAgICAgXSxcbiAgICAgICAgfSksXG4gICAgICB9LFxuICAgIH0pO1xuXG4gICAgLy8gQ3JlYXRlIExhbWJkYSBmdW5jdGlvblxuICAgIHRoaXMubGFtYmRhRnVuY3Rpb24gPSBuZXcgbGFtYmRhLkZ1bmN0aW9uKHRoaXMsICdBcGlMYW1iZGEnLCB7XG4gICAgICBmdW5jdGlvbk5hbWU6IGAke2Rpc3RyaWJ1dGlvblByZWZpeH0tYXBpYCxcbiAgICAgIHJ1bnRpbWU6IGxhbWJkYS5SdW50aW1lLk5PREVKU18yMF9YLFxuICAgICAgaGFuZGxlcjogJ2luZGV4LmhhbmRsZXInLFxuICAgICAgY29kZTogbGFtYmRhLkNvZGUuZnJvbUFzc2V0KGNvZGVQYXRoIHx8ICcuLi8uLi8uLi9hcHBzL2hlbGxvLXdvcmxkLWxhbWJkYScpLFxuICAgICAgbWVtb3J5U2l6ZTogMTI4LFxuICAgICAgdGltZW91dDogY2RrLkR1cmF0aW9uLnNlY29uZHMoMzApLFxuICAgICAgcm9sZTogZXhlY3V0aW9uUm9sZSxcbiAgICAgIGxvZ0dyb3VwOiB0aGlzLmxvZ0dyb3VwLFxuICAgICAgZW52aXJvbm1lbnQ6IHtcbiAgICAgICAgRElTVFJJQlVUSU9OX1BSRUZJWDogZGlzdHJpYnV0aW9uUHJlZml4LFxuICAgICAgICBUQVJHRVRfUkVHSU9OOiB0YXJnZXRSZWdpb24sXG4gICAgICAgIERJU1RSSUJVVElPTl9JRDogZGlzdHJpYnV0aW9uSWQsXG4gICAgICAgIEJVQ0tFVF9OQU1FOiBidWNrZXROYW1lLFxuICAgICAgfSxcbiAgICAgIGRlc2NyaXB0aW9uOiBgU3RhZ2UgQyBBUEkgTGFtYmRhIEZ1bmN0aW9uIC0gJHtkaXN0cmlidXRpb25QcmVmaXh9YCxcbiAgICB9KTtcblxuICAgIC8vIENyZWF0ZSBGdW5jdGlvbiBVUkwgd2l0aCBBV1NfSUFNIGF1dGggdHlwZVxuICAgIHRoaXMuZnVuY3Rpb25VcmwgPSB0aGlzLmxhbWJkYUZ1bmN0aW9uLmFkZEZ1bmN0aW9uVXJsKHtcbiAgICAgIGF1dGhUeXBlOiBsYW1iZGEuRnVuY3Rpb25VcmxBdXRoVHlwZS5BV1NfSUFNLFxuICAgICAgY29yczoge1xuICAgICAgICBhbGxvd0NyZWRlbnRpYWxzOiBmYWxzZSxcbiAgICAgICAgYWxsb3dlZEhlYWRlcnM6IFsnQ29udGVudC1UeXBlJywgJ0F1dGhvcml6YXRpb24nXSxcbiAgICAgICAgYWxsb3dlZE1ldGhvZHM6IFtsYW1iZGEuSHR0cE1ldGhvZC5HRVQsIGxhbWJkYS5IdHRwTWV0aG9kLlBPU1RdLFxuICAgICAgICBhbGxvd2VkT3JpZ2luczogWycqJ10sXG4gICAgICAgIG1heEFnZTogY2RrLkR1cmF0aW9uLm1pbnV0ZXMoNSksXG4gICAgICB9LFxuICAgIH0pO1xuXG4gICAgLy8gR3JhbnQgaW52b2tlIHBlcm1pc3Npb25zIHRvIHRoZSBmdW5jdGlvbiBVUkxcbiAgICB0aGlzLmxhbWJkYUZ1bmN0aW9uLmdyYW50SW52b2tlVXJsKG5ldyBpYW0uU2VydmljZVByaW5jaXBhbCgnbGFtYmRhLmFtYXpvbmF3cy5jb20nKSk7XG5cbiAgICAvLyBTdGFjayBvdXRwdXRzIGZvciBzdWJzZXF1ZW50IHN0YWdlcyBhbmQgdmFsaWRhdGlvblxuICAgIG5ldyBjZGsuQ2ZuT3V0cHV0KHRoaXMsICdMYW1iZGFGdW5jdGlvbkFybicsIHtcbiAgICAgIHZhbHVlOiB0aGlzLmxhbWJkYUZ1bmN0aW9uLmZ1bmN0aW9uQXJuLFxuICAgICAgZGVzY3JpcHRpb246ICdMYW1iZGEgRnVuY3Rpb24gQVJOJyxcbiAgICAgIGV4cG9ydE5hbWU6IGAke2Rpc3RyaWJ1dGlvblByZWZpeH0tbGFtYmRhLWZ1bmN0aW9uLWFybmAsXG4gICAgfSk7XG5cbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnTGFtYmRhRnVuY3Rpb25OYW1lJywge1xuICAgICAgdmFsdWU6IHRoaXMubGFtYmRhRnVuY3Rpb24uZnVuY3Rpb25OYW1lLFxuICAgICAgZGVzY3JpcHRpb246ICdMYW1iZGEgRnVuY3Rpb24gTmFtZScsXG4gICAgICBleHBvcnROYW1lOiBgJHtkaXN0cmlidXRpb25QcmVmaXh9LWxhbWJkYS1mdW5jdGlvbi1uYW1lYCxcbiAgICB9KTtcblxuICAgIG5ldyBjZGsuQ2ZuT3V0cHV0KHRoaXMsICdGdW5jdGlvblVybCcsIHtcbiAgICAgIHZhbHVlOiB0aGlzLmZ1bmN0aW9uVXJsLnVybCxcbiAgICAgIGRlc2NyaXB0aW9uOiAnTGFtYmRhIEZ1bmN0aW9uIFVSTCcsXG4gICAgICBleHBvcnROYW1lOiBgJHtkaXN0cmlidXRpb25QcmVmaXh9LWxhbWJkYS1mdW5jdGlvbi11cmxgLFxuICAgIH0pO1xuXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0xvZ0dyb3VwTmFtZScsIHtcbiAgICAgIHZhbHVlOiB0aGlzLmxvZ0dyb3VwLmxvZ0dyb3VwTmFtZSxcbiAgICAgIGRlc2NyaXB0aW9uOiAnQ2xvdWRXYXRjaCBMb2cgR3JvdXAgTmFtZScsXG4gICAgICBleHBvcnROYW1lOiBgJHtkaXN0cmlidXRpb25QcmVmaXh9LWxhbWJkYS1sb2ctZ3JvdXBgLFxuICAgIH0pO1xuXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ1RhcmdldFJlZ2lvbicsIHtcbiAgICAgIHZhbHVlOiB0YXJnZXRSZWdpb24sXG4gICAgICBkZXNjcmlwdGlvbjogJ1RhcmdldCBSZWdpb24gZm9yIExhbWJkYSBEZXBsb3ltZW50JyxcbiAgICAgIGV4cG9ydE5hbWU6IGAke2Rpc3RyaWJ1dGlvblByZWZpeH0tbGFtYmRhLXRhcmdldC1yZWdpb25gLFxuICAgIH0pO1xuXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0Rpc3RyaWJ1dGlvblByZWZpeCcsIHtcbiAgICAgIHZhbHVlOiBkaXN0cmlidXRpb25QcmVmaXgsXG4gICAgICBkZXNjcmlwdGlvbjogJ0Rpc3RyaWJ1dGlvbiBQcmVmaXggVXNlZCcsXG4gICAgICBleHBvcnROYW1lOiBgJHtkaXN0cmlidXRpb25QcmVmaXh9LWxhbWJkYS1wcmVmaXhgLFxuICAgIH0pO1xuXG4gICAgbmV3IGNkay5DZm5PdXRwdXQodGhpcywgJ0Rpc3RyaWJ1dGlvbklkJywge1xuICAgICAgdmFsdWU6IGRpc3RyaWJ1dGlvbklkLFxuICAgICAgZGVzY3JpcHRpb246ICdDbG91ZEZyb250IERpc3RyaWJ1dGlvbiBJRCAoZnJvbSBwcmV2aW91cyBzdGFnZXMpJyxcbiAgICAgIGV4cG9ydE5hbWU6IGAke2Rpc3RyaWJ1dGlvblByZWZpeH0tbGFtYmRhLWRpc3RyaWJ1dGlvbi1pZGAsXG4gICAgfSk7XG5cbiAgICBuZXcgY2RrLkNmbk91dHB1dCh0aGlzLCAnQnVja2V0TmFtZScsIHtcbiAgICAgIHZhbHVlOiBidWNrZXROYW1lLFxuICAgICAgZGVzY3JpcHRpb246ICdTMyBCdWNrZXQgTmFtZSAoZnJvbSBwcmV2aW91cyBzdGFnZXMpJyxcbiAgICAgIGV4cG9ydE5hbWU6IGAke2Rpc3RyaWJ1dGlvblByZWZpeH0tbGFtYmRhLWJ1Y2tldC1uYW1lYCxcbiAgICB9KTtcblxuICAgIC8vIEFkZCB0YWdzIGZvciByZXNvdXJjZSBpZGVudGlmaWNhdGlvblxuICAgIGNkay5UYWdzLm9mKHRoaXMpLmFkZCgnU3RhZ2UnLCAnQy1MYW1iZGEnKTtcbiAgICBjZGsuVGFncy5vZih0aGlzKS5hZGQoJ0NvbXBvbmVudCcsICdMYW1iZGEtRnVuY3Rpb24nKTtcbiAgICBjZGsuVGFncy5vZih0aGlzKS5hZGQoJ0Vudmlyb25tZW50JywgY2RrLkF3cy5BQ0NPVU5UX0lEKTtcbiAgICBjZGsuVGFncy5vZih0aGlzKS5hZGQoJ0Rpc3RyaWJ1dGlvblByZWZpeCcsIGRpc3RyaWJ1dGlvblByZWZpeCk7XG4gICAgY2RrLlRhZ3Mub2YodGhpcykuYWRkKCdSdW50aW1lJywgJ25vZGVqczIwLngnKTtcbiAgfVxufSAiXX0=