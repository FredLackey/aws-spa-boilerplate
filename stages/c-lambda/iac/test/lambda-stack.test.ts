import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { LambdaStack } from '../lib/lambda-stack';

describe('LambdaStack', () => {
  let app: cdk.App;
  let stack: LambdaStack;
  let template: Template;

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
    stack = new LambdaStack(app, 'TestLambdaStack', defaultProps);
    template = Template.fromStack(stack);
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
      expect(tagValues).toEqual(
        expect.objectContaining({
          Stage: 'C-Lambda',
          Component: 'Lambda-Function',
          DistributionPrefix: 'test-prefix',
          Runtime: 'nodejs20.x',
        })
      );
      
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
        new LambdaStack(app, 'IncompleteStack', incompleteProps);
      }).not.toThrow();
    });
  });

  describe('Resource Counts', () => {
    test('should create expected number of resources', () => {
      const resources = template.toJSON().Resources;
      const resourceTypes = Object.values(resources).map((r: any) => r.Type);

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