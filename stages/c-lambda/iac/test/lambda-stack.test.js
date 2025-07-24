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
const cdk = __importStar(require("aws-cdk-lib"));
const assertions_1 = require("aws-cdk-lib/assertions");
const lambda_stack_1 = require("../lib/lambda-stack");
describe('LambdaStack', () => {
    let app;
    let stack;
    let template;
    const defaultProps = {
        distributionPrefix: 'test-prefix',
        targetRegion: 'us-east-1',
        targetVpcId: 'vpc-12345678',
        distributionId: 'E1234567890ABC',
        bucketName: 'test-prefix-content-123456789012',
        codePath: './test/assets', // Use test assets for Lambda code
        env: {
            account: '123456789012',
            region: 'us-east-1',
        },
        description: 'Test Stage C Lambda Function Stack',
    };
    beforeEach(() => {
        app = new cdk.App();
        stack = new lambda_stack_1.LambdaStack(app, 'TestLambdaStack', defaultProps);
        template = assertions_1.Template.fromStack(stack);
    });
    describe('Stack Creation', () => {
        test('should create stack without errors', () => {
            expect(stack).toBeDefined();
            expect(template).toBeDefined();
        });
        test('should have correct stack description', () => {
            expect(stack.stackName).toBe('TestLambdaStack');
        });
    });
    describe('CloudWatch Log Group', () => {
        test('should create CloudWatch log group with correct configuration', () => {
            template.hasResourceProperties('AWS::Logs::LogGroup', {
                LogGroupName: '/aws/lambda/test-prefix-api',
                RetentionInDays: 30,
            });
        });
        test('should have removal policy destroy for log group', () => {
            template.hasResource('AWS::Logs::LogGroup', {
                DeletionPolicy: 'Delete',
                UpdateReplacePolicy: 'Delete',
            });
        });
    });
    describe('IAM Execution Role', () => {
        test('should create Lambda execution role with correct name', () => {
            template.hasResourceProperties('AWS::IAM::Role', {
                RoleName: 'test-prefix-lambda-execution-role',
                AssumeRolePolicyDocument: {
                    Statement: [
                        {
                            Action: 'sts:AssumeRole',
                            Effect: 'Allow',
                            Principal: {
                                Service: 'lambda.amazonaws.com',
                            },
                        },
                    ],
                    Version: '2012-10-17',
                },
            });
        });
        test('should attach AWS Lambda basic execution policy', () => {
            template.hasResourceProperties('AWS::IAM::Role', {
                ManagedPolicyArns: [
                    {
                        'Fn::Join': [
                            '',
                            [
                                'arn:',
                                { Ref: 'AWS::Partition' },
                                ':iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
                            ],
                        ],
                    },
                ],
            });
        });
        test('should have inline CloudWatch logs policy', () => {
            template.hasResourceProperties('AWS::IAM::Role', {
                Policies: [
                    {
                        PolicyName: 'CloudWatchLogsPolicy',
                        PolicyDocument: {
                            Statement: [
                                {
                                    Effect: 'Allow',
                                    Action: [
                                        'logs:CreateLogGroup',
                                        'logs:CreateLogStream',
                                        'logs:PutLogEvents',
                                    ],
                                    Resource: {
                                        'Fn::Join': [
                                            '',
                                            [
                                                'arn:aws:logs:us-east-1:',
                                                { Ref: 'AWS::AccountId' },
                                                ':log-group:/aws/lambda/test-prefix-api*',
                                            ],
                                        ],
                                    },
                                },
                            ],
                            Version: '2012-10-17',
                        },
                    },
                ],
            });
        });
    });
    describe('Lambda Function', () => {
        test('should create Lambda function with correct configuration', () => {
            template.hasResourceProperties('AWS::Lambda::Function', {
                FunctionName: 'test-prefix-api',
                Runtime: 'nodejs20.x',
                Handler: 'index.handler',
                MemorySize: 128,
                Timeout: 30,
                Description: 'Stage C API Lambda Function - test-prefix',
            });
        });
        test('should have correct environment variables', () => {
            template.hasResourceProperties('AWS::Lambda::Function', {
                Environment: {
                    Variables: {
                        DISTRIBUTION_PREFIX: 'test-prefix',
                        TARGET_REGION: 'us-east-1',
                        DISTRIBUTION_ID: 'E1234567890ABC',
                        BUCKET_NAME: 'test-prefix-content-123456789012',
                    },
                },
            });
        });
        test('should reference the correct IAM role', () => {
            const lambdaFunctions = template.findResources('AWS::Lambda::Function');
            const lambdaFunction = Object.values(lambdaFunctions)[0];
            expect(lambdaFunction.Properties.Role).toBeDefined();
            expect(lambdaFunction.Properties.Role['Fn::GetAtt']).toBeDefined();
            expect(lambdaFunction.Properties.Role['Fn::GetAtt'][0]).toContain('LambdaExecutionRole');
            expect(lambdaFunction.Properties.Role['Fn::GetAtt'][1]).toBe('Arn');
        });
        test('should reference the correct log group', () => {
            const lambdaFunctions = template.findResources('AWS::Lambda::Function');
            const lambdaFunction = Object.values(lambdaFunctions)[0];
            expect(lambdaFunction.Properties.LoggingConfig).toBeDefined();
            expect(lambdaFunction.Properties.LoggingConfig.LogGroup).toBeDefined();
            expect(lambdaFunction.Properties.LoggingConfig.LogGroup.Ref).toBeDefined();
            expect(lambdaFunction.Properties.LoggingConfig.LogGroup.Ref).toContain('LambdaLogGroup');
        });
    });
    describe('Function URL', () => {
        test('should create Function URL with AWS_IAM auth', () => {
            const functionUrls = template.findResources('AWS::Lambda::Url');
            const functionUrl = Object.values(functionUrls)[0];
            expect(functionUrl.Properties.AuthType).toBe('AWS_IAM');
            expect(functionUrl.Properties.TargetFunctionArn).toBeDefined();
            expect(functionUrl.Properties.TargetFunctionArn['Fn::GetAtt']).toBeDefined();
            expect(functionUrl.Properties.TargetFunctionArn['Fn::GetAtt'][0]).toContain('ApiLambda');
            expect(functionUrl.Properties.TargetFunctionArn['Fn::GetAtt'][1]).toBe('Arn');
        });
        test('should configure CORS for Function URL', () => {
            template.hasResourceProperties('AWS::Lambda::Url', {
                Cors: {
                    AllowCredentials: false,
                    AllowHeaders: ['Content-Type', 'Authorization'],
                    AllowMethods: ['GET', 'POST'],
                    AllowOrigins: ['*'],
                    MaxAge: 300,
                },
            });
        });
    });
    describe('Stack Outputs', () => {
        test('should export Lambda function ARN', () => {
            template.hasOutput('LambdaFunctionArn', {
                Description: 'Lambda Function ARN',
                Export: {
                    Name: 'test-prefix-lambda-function-arn',
                },
            });
        });
        test('should export Lambda function name', () => {
            template.hasOutput('LambdaFunctionName', {
                Description: 'Lambda Function Name',
                Export: {
                    Name: 'test-prefix-lambda-function-name',
                },
            });
        });
        test('should export Function URL', () => {
            template.hasOutput('FunctionUrl', {
                Description: 'Lambda Function URL',
                Export: {
                    Name: 'test-prefix-lambda-function-url',
                },
            });
        });
        test('should export CloudWatch log group name', () => {
            template.hasOutput('LogGroupName', {
                Description: 'CloudWatch Log Group Name',
                Export: {
                    Name: 'test-prefix-lambda-log-group',
                },
            });
        });
        test('should export target region', () => {
            template.hasOutput('TargetRegion', {
                Description: 'Target Region for Lambda Deployment',
                Export: {
                    Name: 'test-prefix-lambda-target-region',
                },
            });
        });
        test('should export distribution prefix', () => {
            template.hasOutput('DistributionPrefix', {
                Description: 'Distribution Prefix Used',
                Export: {
                    Name: 'test-prefix-lambda-prefix',
                },
            });
        });
        test('should export distribution ID from previous stages', () => {
            template.hasOutput('DistributionId', {
                Description: 'CloudFront Distribution ID (from previous stages)',
                Export: {
                    Name: 'test-prefix-lambda-distribution-id',
                },
            });
        });
        test('should export bucket name from previous stages', () => {
            template.hasOutput('BucketName', {
                Description: 'S3 Bucket Name (from previous stages)',
                Export: {
                    Name: 'test-prefix-lambda-bucket-name',
                },
            });
        });
    });
    describe('Resource Tags', () => {
        test('should apply correct tags to all resources', () => {
            // Check that resources have the expected tags
            const resources = template.findResources('AWS::Lambda::Function');
            const resourceKeys = Object.keys(resources);
            expect(resourceKeys.length).toBeGreaterThan(0);
            // CDK applies tags at the stack level, so we verify the stack has the correct tags
            const tagValues = stack.tags.tagValues();
            expect(tagValues).toEqual(expect.objectContaining({
                Stage: 'C-Lambda',
                Component: 'Lambda-Function',
                DistributionPrefix: 'test-prefix',
                Runtime: 'nodejs20.x',
            }));
            // Environment tag will be a CDK token, so check it exists
            expect(tagValues.Environment).toBeDefined();
        });
    });
    describe('Resource Dependencies', () => {
        test('should have proper dependency between Lambda function and log group', () => {
            const lambdaFunctions = template.findResources('AWS::Lambda::Function');
            const logGroups = template.findResources('AWS::Logs::LogGroup');
            expect(Object.keys(lambdaFunctions)).toHaveLength(1);
            expect(Object.keys(logGroups)).toHaveLength(1);
            // Lambda function should reference the log group
            const lambdaFunction = Object.values(lambdaFunctions)[0];
            expect(lambdaFunction.Properties.LoggingConfig.LogGroup.Ref).toBeDefined();
        });
        test('should have proper dependency between Lambda function and IAM role', () => {
            const lambdaFunctions = template.findResources('AWS::Lambda::Function');
            const iamRoles = template.findResources('AWS::IAM::Role');
            expect(Object.keys(lambdaFunctions)).toHaveLength(1);
            expect(Object.keys(iamRoles)).toHaveLength(1);
            // Lambda function should reference the IAM role
            const lambdaFunction = Object.values(lambdaFunctions)[0];
            expect(lambdaFunction.Properties.Role['Fn::GetAtt']).toBeDefined();
        });
        test('should have proper dependency between Function URL and Lambda function', () => {
            const functionUrls = template.findResources('AWS::Lambda::Url');
            const lambdaFunctions = template.findResources('AWS::Lambda::Function');
            expect(Object.keys(functionUrls)).toHaveLength(1);
            expect(Object.keys(lambdaFunctions)).toHaveLength(1);
            // Function URL should reference the Lambda function
            const functionUrl = Object.values(functionUrls)[0];
            expect(functionUrl.Properties.TargetFunctionArn['Fn::GetAtt']).toBeDefined();
        });
    });
    describe('Stack Synthesis', () => {
        test('should synthesize without errors', () => {
            expect(() => {
                app.synth();
            }).not.toThrow();
        });
        test('should produce valid CloudFormation template', () => {
            const synthesized = app.synth();
            const stackArtifact = synthesized.getStackByName('TestLambdaStack');
            expect(stackArtifact).toBeDefined();
            expect(stackArtifact.template).toBeDefined();
            expect(typeof stackArtifact.template).toBe('object');
        });
    });
    describe('Error Handling', () => {
        test('should handle missing required properties gracefully', () => {
            const incompleteProps = {
                ...defaultProps,
                distributionPrefix: '',
            };
            expect(() => {
                new lambda_stack_1.LambdaStack(app, 'IncompleteStack', incompleteProps);
            }).not.toThrow();
        });
    });
    describe('Resource Counts', () => {
        test('should create expected number of resources', () => {
            const resources = template.toJSON().Resources;
            const resourceTypes = Object.values(resources).map((r) => r.Type);
            // Count expected resource types
            expect(resourceTypes.filter(t => t === 'AWS::Lambda::Function')).toHaveLength(1);
            expect(resourceTypes.filter(t => t === 'AWS::Lambda::Url')).toHaveLength(1);
            expect(resourceTypes.filter(t => t === 'AWS::IAM::Role')).toHaveLength(1);
            expect(resourceTypes.filter(t => t === 'AWS::Logs::LogGroup')).toHaveLength(1);
            expect(resourceTypes.filter(t => t === 'AWS::Lambda::Permission')).toHaveLength(1);
        });
        test('should have correct number of outputs', () => {
            const outputs = template.toJSON().Outputs;
            expect(Object.keys(outputs)).toHaveLength(8);
        });
    });
    describe('Integration with Previous Stages', () => {
        test('should properly use Stage A and B outputs in environment variables', () => {
            template.hasResourceProperties('AWS::Lambda::Function', {
                Environment: {
                    Variables: {
                        DISTRIBUTION_ID: defaultProps.distributionId,
                        BUCKET_NAME: defaultProps.bucketName,
                    },
                },
            });
        });
        test('should export values needed for Stage D', () => {
            // These exports should be available for Stage D to consume
            template.hasOutput('LambdaFunctionArn', {});
            template.hasOutput('FunctionUrl', {});
            template.hasOutput('LambdaFunctionName', {});
        });
    });
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoibGFtYmRhLXN0YWNrLnRlc3QuanMiLCJzb3VyY2VSb290IjoiIiwic291cmNlcyI6WyJsYW1iZGEtc3RhY2sudGVzdC50cyJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7O0FBQUEsaURBQW1DO0FBQ25DLHVEQUFrRDtBQUNsRCxzREFBa0Q7QUFFbEQsUUFBUSxDQUFDLGFBQWEsRUFBRSxHQUFHLEVBQUU7SUFDM0IsSUFBSSxHQUFZLENBQUM7SUFDakIsSUFBSSxLQUFrQixDQUFDO0lBQ3ZCLElBQUksUUFBa0IsQ0FBQztJQUV2QixNQUFNLFlBQVksR0FBRztRQUNuQixrQkFBa0IsRUFBRSxhQUFhO1FBQ2pDLFlBQVksRUFBRSxXQUFXO1FBQ3pCLFdBQVcsRUFBRSxjQUFjO1FBQzNCLGNBQWMsRUFBRSxnQkFBZ0I7UUFDaEMsVUFBVSxFQUFFLGtDQUFrQztRQUM5QyxRQUFRLEVBQUUsZUFBZSxFQUFFLGtDQUFrQztRQUM3RCxHQUFHLEVBQUU7WUFDSCxPQUFPLEVBQUUsY0FBYztZQUN2QixNQUFNLEVBQUUsV0FBVztTQUNwQjtRQUNELFdBQVcsRUFBRSxvQ0FBb0M7S0FDbEQsQ0FBQztJQUVGLFVBQVUsQ0FBQyxHQUFHLEVBQUU7UUFDZCxHQUFHLEdBQUcsSUFBSSxHQUFHLENBQUMsR0FBRyxFQUFFLENBQUM7UUFDcEIsS0FBSyxHQUFHLElBQUksMEJBQVcsQ0FBQyxHQUFHLEVBQUUsaUJBQWlCLEVBQUUsWUFBWSxDQUFDLENBQUM7UUFDOUQsUUFBUSxHQUFHLHFCQUFRLENBQUMsU0FBUyxDQUFDLEtBQUssQ0FBQyxDQUFDO0lBQ3ZDLENBQUMsQ0FBQyxDQUFDO0lBRUgsUUFBUSxDQUFDLGdCQUFnQixFQUFFLEdBQUcsRUFBRTtRQUM5QixJQUFJLENBQUMsb0NBQW9DLEVBQUUsR0FBRyxFQUFFO1lBQzlDLE1BQU0sQ0FBQyxLQUFLLENBQUMsQ0FBQyxXQUFXLEVBQUUsQ0FBQztZQUM1QixNQUFNLENBQUMsUUFBUSxDQUFD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QUNoRCxJQUFJLENBQUMsb0VBQW9FLEVBQUUsR0FBRyxFQUFFO1lBQzlFLFFBQVEsQ0FBQyxxQkFBcUIsQ0FBQyx1QkFBdUIsRUFBRTtnQkFDdEQsV0FBVyxFQUFFO29CQUNYLFNBQVMsRUFBRTt3QkFDVCxlQUFlLEVBQUUsWUFBWSxDQUFDLGNBQWM7d0JBQzVDLFdBQVcsRUFBRSxZQUFZLENBQUMsVUFBVTtxQkFDckM7aUJBQ0Y7YUFDRixDQUFDLENBQUM7UUFDTCxDQUFDLENBQUMsQ0FBQztRQUVILElBQUksQ0FBQyx5Q0FBeUMsRUFBRSxHQUFHLEVBQUU7WUFDbkQsMkRBQTJEO1lBQzNELFFBQVEsQ0FBQyxTQUFTLENBQUMsbUJBQW1CLEVBQUUsRUFBRSxDQUFDLENBQUM7WUFDNUMsUUFBUSxDQUFDLFNBQVMsQ0FBQyxhQUFhLEVBQUUsRUFBRSxDQUFDLENBQUM7WUFDdEMsUUFBUSxDQUFDLFNBQVMsQ0FBQyxvQkFBb0IsRUFBRSxFQUFFLENBQUMsQ0FBQztRQUMvQyxDQUFDLENBQUMsQ0FBQztJQUNMLENBQUMsQ0FBQyxDQUFDO0FBQ0wsQ0FBQyxDQUFDLENBQUMiLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgKiBhcyBjZGsgZnJvbSAnYXdzLWNkay1saWInO1xuaW1wb3J0IHsgVGVtcGxhdGUgfSBmcm9tICdhd3MtY2RrLWxpYi9hc3NlcnRpb25zJztcbmltcG9ydCB7IExhbWJkYVN0YWNrIH0gZnJvbSAnLi4vbGliL2xhbWJkYS1zdGFjayc7XG5cbmRlc2NyaWJlKCdMYW1iZGFTdGFjaycsICgpID0+IHtcbiAgbGV0IGFwcDogY2RrLkFwcDtcbiAgbGV0IHN0YWNrOiBMYW1iZGFTdGFjaztcbiAgbGV0IHRlbXBsYXRlOiBUZW1wbGF0ZTtcblxuICBjb25zdCBkZWZhdWx0UHJvcHMgPSB7XG4gICAgZGlzdHJpYnV0aW9uUHJlZml4OiAndGVzdC1wcmVmaXgnLFxuICAgIHRhcmdldFJlZ2lvbjogJ3VzLWVhc3QtMScsXG4gICAgdGFyZ2V0VnBjSWQ6ICd2cGMtMTIzNDU2NzgnLFxuICAgIGRpc3RyaWJ1dGlvbklkOiAnRTEyMzQ1Njc4OTBBQkMnLFxuICAgIGJ1Y2tldE5hbWU6ICd0ZXN0LXByZWZpeC1jb250ZW50LTEyMzQ1Njc4OTAxMicsXG4gICAgY29kZVBhdGg6ICcuL3Rlc3QvYXNzZXRzJywgLy8gVXNlIHRlc3QgYXNzZXRzIGZvciBMYW1iZGEgY29kZVxuICAgIGVudjoge1xuICAgICAgYWNjb3VudDogJzEyMzQ1Njc4OTAxMicsXG4gICAgICByZWdpb246ICd1cy1lYXN0LTEnLFxuICAgIH0sXG4gICAgZGVzY3JpcHRpb246ICdUZXN0IFN0YWdlIEMgTGFtYmRhIEZ1bmN0aW9uIFN0YWNrJyxcbiAgfTtcblxuICBiZWZvcmVFYWNoKCgpID0+IHtcbiAgICBhcHAgPSBuZXcgY2RrLkFwcCgpO1xuICAgIHN0YWNrID0gbmV3IExhbWJkYVN0YWNrKGFwcCwgJ1Rlc3RMYW1iZGFTdGFjaycsIGRlZmF1bHRQcm9wcyk7XG4gICAgdGVtcGxhdGUgPSBUZW1wbGF0ZS5mcm9tU3RhY2soc3RhY2spO1xuICB9KTtcblxuICBkZXNjcmliZSgnU3RhY2sgQ3JlYXRpb24nLCAoKSA9PiB7XG4gICAgdGVzdCgnc2hvdWxkIGNyZWF0ZSBzdGFjayB3aXRob3V0IGVycm9ycycsICgpID0+IHtcbiAgICAgIGV4cGVjdChzdGFjaykudG9CZURlZmluZWQoKTtcbiAgICAgIGV4cGVjdCh0ZW1wbGF0ZSkudG9CZURlZmluZWQoKTtcbiAgICB9KTtcblxuICAgIHRlc3QoJ3Nob3VsZCBoYXZlIGNvcnJlY3Qgc3RhY2sgZGVzY3JpcHRpb24nLCAoKSA9PiB7XG4gICAgICBleHBlY3Qoc3RhY2suc3RhY2tOYW1lKS50b0JlKCdUZXN0TGFtYmRhU3RhY2snKTtcbiAgICB9KTtcbiAgfSk7XG5cbiAgZGVzY3JpYmUoJ0Nsb3VkV2F0Y2ggTG9nIEdyb3VwJywgKCkgPT4ge1xuICAgIHRlc3QoJ3Nob3VsZCBjcmVhdGUgQ2xvdWRXYXRjaCBsb2cgZ3JvdXAgd2l0aCBjb3JyZWN0IGNvbmZpZ3VyYXRpb24nLCAoKSA9PiB7XG4gICAgICB0ZW1wbGF0ZS5oYXNSZXNvdXJjZVByb3BlcnRpZXMoJ0FXUzo6TG9nczo6TG9nR3JvdXAnLCB7XG4gICAgICAgIExvZ0dyb3VwTmFtZTogJy9hd3MvbGFtYmRhL3Rlc3QtcHJlZml4LWFwaScsXG4gICAgICAgIFJldGVudGlvbkluRGF5czogMzAsXG4gICAgICB9KTtcbiAgICB9KTtcblxuICAgIHRlc3QoJ3Nob3VsZCBoYXZlIHJlbW92YWwgcG9saWN5IGRlc3Ryb3kgZm9yIGxvZyBncm91cCcsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc1Jlc291cmNlKCdBV1M6OkxvZ3M6OkxvZ0dyb3VwJywge1xuICAgICAgICBEZWxldGlvblBvbGljeTogJ0RlbGV0ZScsXG4gICAgICAgIFVwZGF0ZVJlcGxhY2VQb2xpY3k6ICdEZWxldGUnLFxuICAgICAgfSk7XG4gICAgfSk7XG4gIH0pO1xuXG4gIGRlc2NyaWJlKCdJQU0gRXhlY3V0aW9uIFJvbGUnLCAoKSA9PiB7XG4gICAgdGVzdCgnc2hvdWxkIGNyZWF0ZSBMYW1iZGEgZXhlY3V0aW9uIHJvbGUgd2l0aCBjb3JyZWN0IG5hbWUnLCAoKSA9PiB7XG4gICAgICB0ZW1wbGF0ZS5oYXNSZXNvdXJjZVByb3BlcnRpZXMoJ0FXUzo6SUFNOjpSb2xlJywge1xuICAgICAgICBSb2xlTmFtZTogJ3Rlc3QtcHJlZml4LWxhbWJkYS1leGVjdXRpb24tcm9sZScsXG4gICAgICAgIEFzc3VtZVJvbGVQb2xpY3lEb2N1bWVudDoge1xuICAgICAgICAgIFN0YXRlbWVudDogW1xuICAgICAgICAgICAge1xuICAgICAgICAgICAgICBBY3Rpb246ICdzdHM6QXNzdW1lUm9sZScsXG4gICAgICAgICAgICAgIEVmZmVjdDogJ0FsbG93JyxcbiAgICAgICAgICAgICAgUHJpbmNpcGFsOiB7XG4gICAgICAgICAgICAgICAgU2VydmljZTogJ2xhbWJkYS5hbWF6b25hd3MuY29tJyxcbiAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgIH0sXG4gICAgICAgICAgXSxcbiAgICAgICAgICBWZXJzaW9uOiAnMjAxMi0xMC0xNycsXG4gICAgICAgIH0sXG4gICAgICB9KTtcbiAgICB9KTtcblxuICAgIHRlc3QoJ3Nob3VsZCBhdHRhY2ggQVdTIExhbWJkYSBiYXNpYyBleGVjdXRpb24gcG9saWN5JywgKCkgPT4ge1xuICAgICAgdGVtcGxhdGUuaGFzUmVzb3VyY2VQcm9wZXJ0aWVzKCdBV1M6OklBTTo6Um9sZScsIHtcbiAgICAgICAgTWFuYWdlZFBvbGljeUFybnM6IFtcbiAgICAgICAgICB7XG4gICAgICAgICAgICAnRm46OkpvaW4nOiBbXG4gICAgICAgICAgICAgICcnLFxuICAgICAgICAgICAgICBbXG4gICAgICAgICAgICAgICAgJ2FybjonLFxuICAgICAgICAgICAgICAgIHsgUmVmOiAnQVdTOjpQYXJ0aXRpb24nIH0sXG4gICAgICAgICAgICAgICAgJzppYW06OmF3czpwb2xpY3kvc2VydmljZS1yb2xlL0FXU0xhbWJkYUJhc2ljRXhlY3V0aW9uUm9sZScsXG4gICAgICAgICAgICAgIF0sXG4gICAgICAgICAgICBdLFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICB9KTtcbiAgICB9KTtcblxuICAgIHRlc3QoJ3Nob3VsZCBoYXZlIGlubGluZSBDbG91ZFdhdGNoIGxvZ3MgcG9saWN5JywgKCkgPT4ge1xuICAgICAgdGVtcGxhdGUuaGFzUmVzb3VyY2VQcm9wZXJ0aWVzKCdBV1M6OklBTTo6Um9sZScsIHtcbiAgICAgICAgUG9saWNpZXM6IFtcbiAgICAgICAgICB7XG4gICAgICAgICAgICBQb2xpY3lOYW1lOiAnQ2xvdWRXYXRjaExvZ3NQb2xpY3knLFxuICAgICAgICAgICAgUG9saWN5RG9jdW1lbnQ6IHtcbiAgICAgICAgICAgICAgU3RhdGVtZW50OiBbXG4gICAgICAgICAgICAgICAge1xuICAgICAgICAgICAgICAgICAgRWZmZWN0OiAnQWxsb3cnLFxuICAgICAgICAgICAgICAgICAgQWN0aW9uOiBbXG4gICAgICAgICAgICAgICAgICAgICdsb2dzOkNyZWF0ZUxvZ0dyb3VwJyxcbiAgICAgICAgICAgICAgICAgICAgJ2xvZ3M6Q3JlYXRlTG9nU3RyZWFtJyxcbiAgICAgICAgICAgICAgICAgICAgJ2xvZ3M6UHV0TG9nRXZlbnRzJyxcbiAgICAgICAgICAgICAgICAgIF0sXG4gICAgICAgICAgICAgICAgICBSZXNvdXJjZToge1xuICAgICAgICAgICAgICAgICAgICAnRm46OkpvaW4nOiBbXG4gICAgICAgICAgICAgICAgICAgICAgJycsXG4gICAgICAgICAgICAgICAgICAgICAgW1xuICAgICAgICAgICAgICAgICAgICAgICAgJ2Fybjphd3M6bG9nczp1cy1lYXN0LTE6JyxcbiAgICAgICAgICAgICAgICAgICAgICAgIHsgUmVmOiAnQVdTOjpBY2NvdW50SWQnIH0sXG4gICAgICAgICAgICAgICAgICAgICAgICAnOmxvZy1ncm91cDovYXdzL2xhbWJkYS90ZXN0LXByZWZpeC1hcGkqJyxcbiAgICAgICAgICAgICAgICAgICAgICBdLFxuICAgICAgICAgICAgICAgICAgICBdLFxuICAgICAgICAgICAgICAgICAgfSxcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICBdLFxuICAgICAgICAgICAgICBWZXJzaW9uOiAnMjAxMi0xMC0xNycsXG4gICAgICAgICAgICB9LFxuICAgICAgICAgIH0sXG4gICAgICAgIF0sXG4gICAgICB9KTtcbiAgICB9KTtcbiAgfSk7XG5cbiAgZGVzY3JpYmUoJ0xhbWJkYSBGdW5jdGlvbicsICgpID0+IHtcbiAgICB0ZXN0KCdzaG91bGQgY3JlYXRlIExhbWJkYSBmdW5jdGlvbiB3aXRoIGNvcnJlY3QgY29uZmlndXJhdGlvbicsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc1Jlc291cmNlUHJvcGVydGllcygnQVdTOjpMYW1iZGE6OkZ1bmN0aW9uJywge1xuICAgICAgICBGdW5jdGlvbk5hbWU6ICd0ZXN0LXByZWZpeC1hcGknLFxuICAgICAgICBSdW50aW1lOiAnbm9kZWpzMjAueCcsXG4gICAgICAgIEhhbmRsZXI6ICdpbmRleC5oYW5kbGVyJyxcbiAgICAgICAgTWVtb3J5U2l6ZTogMTI4LFxuICAgICAgICBUaW1lb3V0OiAzMCxcbiAgICAgICAgRGVzY3JpcHRpb246ICdTdGFnZSBDIEFQSSBMYW1iZGEgRnVuY3Rpb24gLSB0ZXN0LXByZWZpeCcsXG4gICAgICB9KTtcbiAgICB9KTtcblxuICAgIHRlc3QoJ3Nob3VsZCBoYXZlIGNvcnJlY3QgZW52aXJvbm1lbnQgdmFyaWFibGVzJywgKCkgPT4ge1xuICAgICAgdGVtcGxhdGUuaGFzUmVzb3VyY2VQcm9wZXJ0aWVzKCdBV1M6OkxhbWJkYTo6RnVuY3Rpb24nLCB7XG4gICAgICAgIEVudmlyb25tZW50OiB7XG4gICAgICAgICAgVmFyaWFibGVzOiB7XG4gICAgICAgICAgICBESVNUUklCVVRJT05fUFJFRklYOiAndGVzdC1wcmVmaXgnLFxuICAgICAgICAgICAgVEFSR0VUX1JFR0lPTjogJ3VzLWVhc3QtMScsXG4gICAgICAgICAgICBESVNUUklCVVRJT05fSUQ6ICdFMTIzNDU2Nzg5MEFCQycsXG4gICAgICAgICAgICBCVUNLRVRfTkFNRTogJ3Rlc3QtcHJlZml4LWNvbnRlbnQtMTIzNDU2Nzg5MDEyJyxcbiAgICAgICAgICB9LFxuICAgICAgICB9LFxuICAgICAgfSk7XG4gICAgfSk7XG5cbiAgICB0ZXN0KCdzaG91bGQgcmVmZXJlbmNlIHRoZSBjb3JyZWN0IElBTSByb2xlJywgKCkgPT4ge1xuICAgICAgY29uc3QgbGFtYmRhRnVuY3Rpb25zID0gdGVtcGxhdGUuZmluZFJlc291cmNlcygnQVdTOjpMYW1iZGE6OkZ1bmN0aW9uJyk7XG4gICAgICBjb25zdCBsYW1iZGFGdW5jdGlvbiA9IE9iamVjdC52YWx1ZXMobGFtYmRhRnVuY3Rpb25zKVswXTtcbiAgICAgIFxuICAgICAgZXhwZWN0KGxhbWJkYUZ1bmN0aW9uLlByb3BlcnRpZXMuUm9sZSkudG9CZURlZmluZWQoKTtcbiAgICAgIGV4cGVjdChsYW1iZGFGdW5jdGlvbi5Qcm9wZXJ0aWVzLlJvbGVbJ0ZuOjpHZXRBdHQnXSkudG9CZURlZmluZWQoKTtcbiAgICAgIGV4cGVjdChsYW1iZGFGdW5jdGlvbi5Qcm9wZXJ0aWVzLlJvbGVbJ0ZuOjpHZXRBdHQnXVswXSkudG9Db250YWluKCdMYW1iZGFFeGVjdXRpb25Sb2xlJyk7XG4gICAgICBleHBlY3QobGFtYmRhRnVuY3Rpb24uUHJvcGVydGllcy5Sb2xlWydGbjo6R2V0QXR0J11bMV0pLnRvQmUoJ0FybicpO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIHJlZmVyZW5jZSB0aGUgY29ycmVjdCBsb2cgZ3JvdXAnLCAoKSA9PiB7XG4gICAgICBjb25zdCBsYW1iZGFGdW5jdGlvbnMgPSB0ZW1wbGF0ZS5maW5kUmVzb3VyY2VzKCdBV1M6OkxhbWJkYTo6RnVuY3Rpb24nKTtcbiAgICAgIGNvbnN0IGxhbWJkYUZ1bmN0aW9uID0gT2JqZWN0LnZhbHVlcyhsYW1iZGFGdW5jdGlvbnMpWzBdO1xuICAgICAgXG4gICAgICBleHBlY3QobGFtYmRhRnVuY3Rpb24uUHJvcGVydGllcy5Mb2dnaW5nQ29uZmlnKS50b0JlRGVmaW5lZCgpO1xuICAgICAgZXhwZWN0KGxhbWJkYUZ1bmN0aW9uLlByb3BlcnRpZXMuTG9nZ2luZ0NvbmZpZy5Mb2dHcm91cCkudG9CZURlZmluZWQoKTtcbiAgICAgIGV4cGVjdChsYW1iZGFGdW5jdGlvbi5Qcm9wZXJ0aWVzLkxvZ2dpbmdDb25maWcuTG9nR3JvdXAuUmVmKS50b0JlRGVmaW5lZCgpO1xuICAgICAgZXhwZWN0KGxhbWJkYUZ1bmN0aW9uLlByb3BlcnRpZXMuTG9nZ2luZ0NvbmZpZy5Mb2dHcm91cC5SZWYpLnRvQ29udGFpbignTGFtYmRhTG9nR3JvdXAnKTtcbiAgICB9KTtcbiAgfSk7XG5cbiAgZGVzY3JpYmUoJ0Z1bmN0aW9uIFVSTCcsICgpID0+IHtcbiAgICB0ZXN0KCdzaG91bGQgY3JlYXRlIEZ1bmN0aW9uIFVSTCB3aXRoIEFXU19JQU0gYXV0aCcsICgpID0+IHtcbiAgICAgIGNvbnN0IGZ1bmN0aW9uVXJscyA9IHRlbXBsYXRlLmZpbmRSZXNvdXJjZXMoJ0FXUzo6TGFtYmRhOjpVcmwnKTtcbiAgICAgIGNvbnN0IGZ1bmN0aW9uVXJsID0gT2JqZWN0LnZhbHVlcyhmdW5jdGlvblVybHMpWzBdO1xuICAgICAgXG4gICAgICBleHBlY3QoZnVuY3Rpb25VcmwuUHJvcGVydGllcy5BdXRoVHlwZSkudG9CZSgnQVdTX0lBTScpO1xuICAgICAgZXhwZWN0KGZ1bmN0aW9uVXJsLlByb3BlcnRpZXMuVGFyZ2V0RnVuY3Rpb25Bcm4pLnRvQmVEZWZpbmVkKCk7XG4gICAgICBleHBlY3QoZnVuY3Rpb25VcmwuUHJvcGVydGllcy5UYXJnZXRGdW5jdGlvbkFyblsnRm46OkdldEF0dCddKS50b0JlRGVmaW5lZCgpO1xuICAgICAgZXhwZWN0KGZ1bmN0aW9uVXJsLlByb3BlcnRpZXMuVGFyZ2V0RnVuY3Rpb25Bcm5bJ0ZuOjpHZXRBdHQnXVswXSkudG9Db250YWluKCdBcGlMYW1iZGEnKTtcbiAgICAgIGV4cGVjdChmdW5jdGlvblVybC5Qcm9wZXJ0aWVzLlRhcmdldEZ1bmN0aW9uQXJuWydGbjo6R2V0QXR0J11bMV0pLnRvQmUoJ0FybicpO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIGNvbmZpZ3VyZSBDT1JTIGZvciBGdW5jdGlvbiBVUkwnLCAoKSA9PiB7XG4gICAgICB0ZW1wbGF0ZS5oYXNSZXNvdXJjZVByb3BlcnRpZXMoJ0FXUzo6TGFtYmRhOjpVcmwnLCB7XG4gICAgICAgIENvcnM6IHtcbiAgICAgICAgICBBbGxvd0NyZWRlbnRpYWxzOiBmYWxzZSxcbiAgICAgICAgICBBbGxvd0hlYWRlcnM6IFsnQ29udGVudC1UeXBlJywgJ0F1dGhvcml6YXRpb24nXSxcbiAgICAgICAgICBBbGxvd01ldGhvZHM6IFsnR0VUJywgJ1BPU1QnXSxcbiAgICAgICAgICBBbGxvd09yaWdpbnM6IFsnKiddLFxuICAgICAgICAgIE1heEFnZTogMzAwLFxuICAgICAgICB9LFxuICAgICAgfSk7XG4gICAgfSk7XG4gIH0pO1xuXG4gIGRlc2NyaWJlKCdTdGFjayBPdXRwdXRzJywgKCkgPT4ge1xuICAgIHRlc3QoJ3Nob3VsZCBleHBvcnQgTGFtYmRhIGZ1bmN0aW9uIEFSTicsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc091dHB1dCgnTGFtYmRhRnVuY3Rpb25Bcm4nLCB7XG4gICAgICAgIERlc2NyaXB0aW9uOiAnTGFtYmRhIEZ1bmN0aW9uIEFSTicsXG4gICAgICAgIEV4cG9ydDoge1xuICAgICAgICAgIE5hbWU6ICd0ZXN0LXByZWZpeC1sYW1iZGEtZnVuY3Rpb24tYXJuJyxcbiAgICAgICAgfSxcbiAgICAgIH0pO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIGV4cG9ydCBMYW1iZGEgZnVuY3Rpb24gbmFtZScsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc091dHB1dCgnTGFtYmRhRnVuY3Rpb25OYW1lJywge1xuICAgICAgICBEZXNjcmlwdGlvbjogJ0xhbWJkYSBGdW5jdGlvbiBOYW1lJyxcbiAgICAgICAgRXhwb3J0OiB7XG4gICAgICAgICAgTmFtZTogJ3Rlc3QtcHJlZml4LWxhbWJkYS1mdW5jdGlvbi1uYW1lJyxcbiAgICAgICAgfSxcbiAgICAgIH0pO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIGV4cG9ydCBGdW5jdGlvbiBVUkwnLCAoKSA9PiB7XG4gICAgICB0ZW1wbGF0ZS5oYXNPdXRwdXQoJ0Z1bmN0aW9uVXJsJywge1xuICAgICAgICBEZXNjcmlwdGlvbjogJ0xhbWJkYSBGdW5jdGlvbiBVUkwnLFxuICAgICAgICBFeHBvcnQ6IHtcbiAgICAgICAgICBOYW1lOiAndGVzdC1wcmVmaXgtbGFtYmRhLWZ1bmN0aW9uLXVybCcsXG4gICAgICAgIH0sXG4gICAgICB9KTtcbiAgICB9KTtcblxuICAgIHRlc3QoJ3Nob3VsZCBleHBvcnQgQ2xvdWRXYXRjaCBsb2cgZ3JvdXAgbmFtZScsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc091dHB1dCgnTG9nR3JvdXBOYW1lJywge1xuICAgICAgICBEZXNjcmlwdGlvbjogJ0Nsb3VkV2F0Y2ggTG9nIEdyb3VwIE5hbWUnLFxuICAgICAgICBFeHBvcnQ6IHtcbiAgICAgICAgICBOYW1lOiAndGVzdC1wcmVmaXgtbGFtYmRhLWxvZy1ncm91cCcsXG4gICAgICAgIH0sXG4gICAgICB9KTtcbiAgICB9KTtcblxuICAgIHRlc3QoJ3Nob3VsZCBleHBvcnQgdGFyZ2V0IHJlZ2lvbicsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc091dHB1dCgnVGFyZ2V0UmVnaW9uJywge1xuICAgICAgICBEZXNjcmlwdGlvbjogJ1RhcmdldCBSZWdpb24gZm9yIExhbWJkYSBEZXBsb3ltZW50JyxcbiAgICAgICAgRXhwb3J0OiB7XG4gICAgICAgICAgTmFtZTogJ3Rlc3QtcHJlZml4LWxhbWJkYS10YXJnZXQtcmVnaW9uJyxcbiAgICAgICAgfSxcbiAgICAgIH0pO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIGV4cG9ydCBkaXN0cmlidXRpb24gcHJlZml4JywgKCkgPT4ge1xuICAgICAgdGVtcGxhdGUuaGFzT3V0cHV0KCdEaXN0cmlidXRpb25QcmVmaXgnLCB7XG4gICAgICAgIERlc2NyaXB0aW9uOiAnRGlzdHJpYnV0aW9uIFByZWZpeCBVc2VkJyxcbiAgICAgICAgRXhwb3J0OiB7XG4gICAgICAgICAgTmFtZTogJ3Rlc3QtcHJlZml4LWxhbWJkYS1wcmVmaXgnLFxuICAgICAgICB9LFxuICAgICAgfSk7XG4gICAgfSk7XG5cbiAgICB0ZXN0KCdzaG91bGQgZXhwb3J0IGRpc3RyaWJ1dGlvbiBJRCBmcm9tIHByZXZpb3VzIHN0YWdlcycsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc091dHB1dCgnRGlzdHJpYnV0aW9uSWQnLCB7XG4gICAgICAgIERlc2NyaXB0aW9uOiAnQ2xvdWRGcm9udCBEaXN0cmlidXRpb24gSUQgKGZyb20gcHJldmlvdXMgc3RhZ2VzKScsXG4gICAgICAgIEV4cG9ydDoge1xuICAgICAgICAgIE5hbWU6ICd0ZXN0LXByZWZpeC1sYW1iZGEtZGlzdHJpYnV0aW9uLWlkJyxcbiAgICAgICAgfSxcbiAgICAgIH0pO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIGV4cG9ydCBidWNrZXQgbmFtZSBmcm9tIHByZXZpb3VzIHN0YWdlcycsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc091dHB1dCgnQnVja2V0TmFtZScsIHtcbiAgICAgICAgRGVzY3JpcHRpb246ICdTMyBCdWNrZXQgTmFtZSAoZnJvbSBwcmV2aW91cyBzdGFnZXMpJyxcbiAgICAgICAgRXhwb3J0OiB7XG4gICAgICAgICAgTmFtZTogJ3Rlc3QtcHJlZml4LWxhbWJkYS1idWNrZXQtbmFtZScsXG4gICAgICAgIH0sXG4gICAgICB9KTtcbiAgICB9KTtcbiAgfSk7XG5cbiAgZGVzY3JpYmUoJ1Jlc291cmNlIFRhZ3MnLCAoKSA9PiB7XG4gICAgdGVzdCgnc2hvdWxkIGFwcGx5IGNvcnJlY3QgdGFncyB0byBhbGwgcmVzb3VyY2VzJywgKCkgPT4ge1xuICAgICAgLy8gQ2hlY2sgdGhhdCByZXNvdXJjZXMgaGF2ZSB0aGUgZXhwZWN0ZWQgdGFnc1xuICAgICAgY29uc3QgcmVzb3VyY2VzID0gdGVtcGxhdGUuZmluZFJlc291cmNlcygnQVdTOjpMYW1iZGE6OkZ1bmN0aW9uJyk7XG4gICAgICBjb25zdCByZXNvdXJjZUtleXMgPSBPYmplY3Qua2V5cyhyZXNvdXJjZXMpO1xuICAgICAgZXhwZWN0KHJlc291cmNlS2V5cy5sZW5ndGgpLnRvQmVHcmVhdGVyVGhhbigwKTtcblxuICAgICAgLy8gQ0RLIGFwcGxpZXMgdGFncyBhdCB0aGUgc3RhY2sgbGV2ZWwsIHNvIHdlIHZlcmlmeSB0aGUgc3RhY2sgaGFzIHRoZSBjb3JyZWN0IHRhZ3NcbiAgICAgIGNvbnN0IHRhZ1ZhbHVlcyA9IHN0YWNrLnRhZ3MudGFnVmFsdWVzKCk7XG4gICAgICBleHBlY3QodGFnVmFsdWVzKS50b0VxdWFsKFxuICAgICAgICBleHBlY3Qub2JqZWN0Q29udGFpbmluZyh7XG4gICAgICAgICAgU3RhZ2U6ICdDLUxhbWJkYScsXG4gICAgICAgICAgQ29tcG9uZW50OiAnTGFtYmRhLUZ1bmN0aW9uJyxcbiAgICAgICAgICBEaXN0cmlidXRpb25QcmVmaXg6ICd0ZXN0LXByZWZpeCcsXG4gICAgICAgICAgUnVudGltZTogJ25vZGVqczIwLngnLFxuICAgICAgICB9KVxuICAgICAgKTtcbiAgICAgIFxuICAgICAgLy8gRW52aXJvbm1lbnQgdGFnIHdpbGwgYmUgYSBDREsgdG9rZW4sIHNvIGNoZWNrIGl0IGV4aXN0c1xuICAgICAgZXhwZWN0KHRhZ1ZhbHVlcy5FbnZpcm9ubWVudCkudG9CZURlZmluZWQoKTtcbiAgICB9KTtcbiAgfSk7XG5cbiAgZGVzY3JpYmUoJ1Jlc291cmNlIERlcGVuZGVuY2llcycsICgpID0+IHtcbiAgICB0ZXN0KCdzaG91bGQgaGF2ZSBwcm9wZXIgZGVwZW5kZW5jeSBiZXR3ZWVuIExhbWJkYSBmdW5jdGlvbiBhbmQgbG9nIGdyb3VwJywgKCkgPT4ge1xuICAgICAgY29uc3QgbGFtYmRhRnVuY3Rpb25zID0gdGVtcGxhdGUuZmluZFJlc291cmNlcygnQVdTOjpMYW1iZGE6OkZ1bmN0aW9uJyk7XG4gICAgICBjb25zdCBsb2dHcm91cHMgPSB0ZW1wbGF0ZS5maW5kUmVzb3VyY2VzKCdBV1M6OkxvZ3M6OkxvZ0dyb3VwJyk7XG5cbiAgICAgIGV4cGVjdChPYmplY3Qua2V5cyhsYW1iZGFGdW5jdGlvbnMpKS50b0hhdmVMZW5ndGgoMSk7XG4gICAgICBleHBlY3QoT2JqZWN0LmtleXMobG9nR3JvdXBzKSkudG9IYXZlTGVuZ3RoKDEpO1xuXG4gICAgICAvLyBMYW1iZGEgZnVuY3Rpb24gc2hvdWxkIHJlZmVyZW5jZSB0aGUgbG9nIGdyb3VwXG4gICAgICBjb25zdCBsYW1iZGFGdW5jdGlvbiA9IE9iamVjdC52YWx1ZXMobGFtYmRhRnVuY3Rpb25zKVswXTtcbiAgICAgIGV4cGVjdChsYW1iZGFGdW5jdGlvbi5Qcm9wZXJ0aWVzLkxvZ2dpbmdDb25maWcuTG9nR3JvdXAuUmVmKS50b0JlRGVmaW5lZCgpO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIGhhdmUgcHJvcGVyIGRlcGVuZGVuY3kgYmV0d2VlbiBMYW1iZGEgZnVuY3Rpb24gYW5kIElBTSByb2xlJywgKCkgPT4ge1xuICAgICAgY29uc3QgbGFtYmRhRnVuY3Rpb25zID0gdGVtcGxhdGUuZmluZFJlc291cmNlcygnQVdTOjpMYW1iZGE6OkZ1bmN0aW9uJyk7XG4gICAgICBjb25zdCBpYW1Sb2xlcyA9IHRlbXBsYXRlLmZpbmRSZXNvdXJjZXMoJ0FXUzo6SUFNOjpSb2xlJyk7XG5cbiAgICAgIGV4cGVjdChPYmplY3Qua2V5cyhsYW1iZGFGdW5jdGlvbnMpKS50b0hhdmVMZW5ndGgoMSk7XG4gICAgICBleHBlY3QoT2JqZWN0LmtleXMoaWFtUm9sZXMpKS50b0hhdmVMZW5ndGgoMSk7XG5cbiAgICAgIC8vIExhbWJkYSBmdW5jdGlvbiBzaG91bGQgcmVmZXJlbmNlIHRoZSBJQU0gcm9sZVxuICAgICAgY29uc3QgbGFtYmRhRnVuY3Rpb24gPSBPYmplY3QudmFsdWVzKGxhbWJkYUZ1bmN0aW9ucylbMF07XG4gICAgICBleHBlY3QobGFtYmRhRnVuY3Rpb24uUHJvcGVydGllcy5Sb2xlWydGbjo6R2V0QXR0J10pLnRvQmVEZWZpbmVkKCk7XG4gICAgfSk7XG5cbiAgICB0ZXN0KCdzaG91bGQgaGF2ZSBwcm9wZXIgZGVwZW5kZW5jeSBiZXR3ZWVuIEZ1bmN0aW9uIFVSTCBhbmQgTGFtYmRhIGZ1bmN0aW9uJywgKCkgPT4ge1xuICAgICAgY29uc3QgZnVuY3Rpb25VcmxzID0gdGVtcGxhdGUuZmluZFJlc291cmNlcygnQVdTOjpMYW1iZGE6OlVybCcpO1xuICAgICAgY29uc3QgbGFtYmRhRnVuY3Rpb25zID0gdGVtcGxhdGUuZmluZFJlc291cmNlcygnQVdTOjpMYW1iZGE6OkZ1bmN0aW9uJyk7XG5cbiAgICAgIGV4cGVjdChPYmplY3Qua2V5cyhmdW5jdGlvblVybHMpKS50b0hhdmVMZW5ndGgoMSk7XG4gICAgICBleHBlY3QoT2JqZWN0LmtleXMobGFtYmRhRnVuY3Rpb25zKSkudG9IYXZlTGVuZ3RoKDEpO1xuXG4gICAgICAvLyBGdW5jdGlvbiBVUkwgc2hvdWxkIHJlZmVyZW5jZSB0aGUgTGFtYmRhIGZ1bmN0aW9uXG4gICAgICBjb25zdCBmdW5jdGlvblVybCA9IE9iamVjdC52YWx1ZXMoZnVuY3Rpb25VcmxzKVswXTtcbiAgICAgIGV4cGVjdChmdW5jdGlvblVybC5Qcm9wZXJ0aWVzLlRhcmdldEZ1bmN0aW9uQXJuWydGbjo6R2V0QXR0J10pLnRvQmVEZWZpbmVkKCk7XG4gICAgfSk7XG4gIH0pO1xuXG4gIGRlc2NyaWJlKCdTdGFjayBTeW50aGVzaXMnLCAoKSA9PiB7XG4gICAgdGVzdCgnc2hvdWxkIHN5bnRoZXNpemUgd2l0aG91dCBlcnJvcnMnLCAoKSA9PiB7XG4gICAgICBleHBlY3QoKCkgPT4ge1xuICAgICAgICBhcHAuc3ludGgoKTtcbiAgICAgIH0pLm5vdC50b1Rocm93KCk7XG4gICAgfSk7XG5cbiAgICB0ZXN0KCdzaG91bGQgcHJvZHVjZSB2YWxpZCBDbG91ZEZvcm1hdGlvbiB0ZW1wbGF0ZScsICgpID0+IHtcbiAgICAgIGNvbnN0IHN5bnRoZXNpemVkID0gYXBwLnN5bnRoKCk7XG4gICAgICBjb25zdCBzdGFja0FydGlmYWN0ID0gc3ludGhlc2l6ZWQuZ2V0U3RhY2tCeU5hbWUoJ1Rlc3RMYW1iZGFTdGFjaycpO1xuICAgICAgZXhwZWN0KHN0YWNrQXJ0aWZhY3QpLnRvQmVEZWZpbmVkKCk7XG4gICAgICBleHBlY3Qoc3RhY2tBcnRpZmFjdC50ZW1wbGF0ZSkudG9CZURlZmluZWQoKTtcbiAgICAgIGV4cGVjdCh0eXBlb2Ygc3RhY2tBcnRpZmFjdC50ZW1wbGF0ZSkudG9CZSgnb2JqZWN0Jyk7XG4gICAgfSk7XG4gIH0pO1xuXG4gIGRlc2NyaWJlKCdFcnJvciBIYW5kbGluZycsICgpID0+IHtcbiAgICB0ZXN0KCdzaG91bGQgaGFuZGxlIG1pc3NpbmcgcmVxdWlyZWQgcHJvcGVydGllcyBncmFjZWZ1bGx5JywgKCkgPT4ge1xuICAgICAgY29uc3QgaW5jb21wbGV0ZVByb3BzID0ge1xuICAgICAgICAuLi5kZWZhdWx0UHJvcHMsXG4gICAgICAgIGRpc3RyaWJ1dGlvblByZWZpeDogJycsXG4gICAgICB9O1xuXG4gICAgICBleHBlY3QoKCkgPT4ge1xuICAgICAgICBuZXcgTGFtYmRhU3RhY2soYXBwLCAnSW5jb21wbGV0ZVN0YWNrJywgaW5jb21wbGV0ZVByb3BzKTtcbiAgICAgIH0pLm5vdC50b1Rocm93KCk7XG4gICAgfSk7XG4gIH0pO1xuXG4gIGRlc2NyaWJlKCdSZXNvdXJjZSBDb3VudHMnLCAoKSA9PiB7XG4gICAgdGVzdCgnc2hvdWxkIGNyZWF0ZSBleHBlY3RlZCBudW1iZXIgb2YgcmVzb3VyY2VzJywgKCkgPT4ge1xuICAgICAgY29uc3QgcmVzb3VyY2VzID0gdGVtcGxhdGUudG9KU09OKCkuUmVzb3VyY2VzO1xuICAgICAgY29uc3QgcmVzb3VyY2VUeXBlcyA9IE9iamVjdC52YWx1ZXMocmVzb3VyY2VzKS5tYXAoKHI6IGFueSkgPT4gci5UeXBlKTtcblxuICAgICAgLy8gQ291bnQgZXhwZWN0ZWQgcmVzb3VyY2UgdHlwZXNcbiAgICAgIGV4cGVjdChyZXNvdXJjZVR5cGVzLmZpbHRlcih0ID0+IHQgPT09ICdBV1M6OkxhbWJkYTo6RnVuY3Rpb24nKSkudG9IYXZlTGVuZ3RoKDEpO1xuICAgICAgZXhwZWN0KHJlc291cmNlVHlwZXMuZmlsdGVyKHQgPT4gdCA9PT0gJ0FXUzo6TGFtYmRhOjpVcmwnKSkudG9IYXZlTGVuZ3RoKDEpO1xuICAgICAgZXhwZWN0KHJlc291cmNlVHlwZXMuZmlsdGVyKHQgPT4gdCA9PT0gJ0FXUzo6SUFNOjpSb2xlJykpLnRvSGF2ZUxlbmd0aCgxKTtcbiAgICAgIGV4cGVjdChyZXNvdXJjZVR5cGVzLmZpbHRlcih0ID0+IHQgPT09ICdBV1M6OkxvZ3M6OkxvZ0dyb3VwJykpLnRvSGF2ZUxlbmd0aCgxKTtcbiAgICAgIGV4cGVjdChyZXNvdXJjZVR5cGVzLmZpbHRlcih0ID0+IHQgPT09ICdBV1M6OkxhbWJkYTo6UGVybWlzc2lvbicpKS50b0hhdmVMZW5ndGgoMSk7XG4gICAgfSk7XG5cbiAgICB0ZXN0KCdzaG91bGQgaGF2ZSBjb3JyZWN0IG51bWJlciBvZiBvdXRwdXRzJywgKCkgPT4ge1xuICAgICAgY29uc3Qgb3V0cHV0cyA9IHRlbXBsYXRlLnRvSlNPTigpLk91dHB1dHM7XG4gICAgICBleHBlY3QoT2JqZWN0LmtleXMob3V0cHV0cykpLnRvSGF2ZUxlbmd0aCg4KTtcbiAgICB9KTtcbiAgfSk7XG5cbiAgZGVzY3JpYmUoJ0ludGVncmF0aW9uIHdpdGggUHJldmlvdXMgU3RhZ2VzJywgKCkgPT4ge1xuICAgIHRlc3QoJ3Nob3VsZCBwcm9wZXJseSB1c2UgU3RhZ2UgQSBhbmQgQiBvdXRwdXRzIGluIGVudmlyb25tZW50IHZhcmlhYmxlcycsICgpID0+IHtcbiAgICAgIHRlbXBsYXRlLmhhc1Jlc291cmNlUHJvcGVydGllcygnQVdTOjpMYW1iZGE6OkZ1bmN0aW9uJywge1xuICAgICAgICBFbnZpcm9ubWVudDoge1xuICAgICAgICAgIFZhcmlhYmxlczoge1xuICAgICAgICAgICAgRElTVFJJQlVUSU9OX0lEOiBkZWZhdWx0UHJvcHMuZGlzdHJpYnV0aW9uSWQsXG4gICAgICAgICAgICBCVUNLRVRfTkFNRTogZGVmYXVsdFByb3BzLmJ1Y2tldE5hbWUsXG4gICAgICAgICAgfSxcbiAgICAgICAgfSxcbiAgICAgIH0pO1xuICAgIH0pO1xuXG4gICAgdGVzdCgnc2hvdWxkIGV4cG9ydCB2YWx1ZXMgbmVlZGVkIGZvciBTdGFnZSBEJywgKCkgPT4ge1xuICAgICAgLy8gVGhlc2UgZXhwb3J0cyBzaG91bGQgYmUgYXZhaWxhYmxlIGZvciBTdGFnZSBEIHRvIGNvbnN1bWVcbiAgICAgIHRlbXBsYXRlLmhhc091dHB1dCgnTGFtYmRhRnVuY3Rpb25Bcm4nLCB7fSk7XG4gICAgICB0ZW1wbGF0ZS5oYXNPdXRwdXQoJ0Z1bmN0aW9uVXJsJywge30pO1xuICAgICAgdGVtcGxhdGUuaGFzT3V0cHV0KCdMYW1iZGFGdW5jdGlvbk5hbWUnLCB7fSk7XG4gICAgfSk7XG4gIH0pO1xufSk7ICJdfQ==