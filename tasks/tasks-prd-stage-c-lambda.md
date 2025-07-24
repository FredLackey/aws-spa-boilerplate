# Task List: Stage C - Hello World API in Lambda

Based on PRD: `prd-stage-c-lambda.md`

## Relevant Files

- `stages/c-lambda/go-c.sh` - Main deployment script for Stage C following established patterns from Stage A and B
- `stages/c-lambda/status-c.sh` - Status checking script for Stage C deployment
- `stages/c-lambda/undo-c.sh` - Rollback script for Stage C resources
- `stages/c-lambda/data/inputs.json` - User-provided configuration data for Stage C
- `stages/c-lambda/data/discovery.json` - AWS account discovery results for Stage C
- `stages/c-lambda/data/outputs.json` - Stage C deployment outputs for subsequent stages
- `stages/c-lambda/data/pattern-analysis.json` - Documentation of discovered patterns from Stage A and B analysis
- `stages/c-lambda/iac/app.ts` - CDK application entry point for Stage C infrastructure
- `stages/c-lambda/iac/lib/lambda-stack.ts` - CDK stack definition for Lambda function and related resources
- `stages/c-lambda/iac/package.json` - CDK project dependencies
- `stages/c-lambda/iac/cdk.json` - CDK configuration file
- `stages/c-lambda/iac/tsconfig.json` - TypeScript configuration for CDK
- `stages/c-lambda/scripts/aws-discovery.sh` - AWS account and resource discovery script
- `stages/c-lambda/scripts/gather-inputs.sh` - Script to collect user inputs and validate prerequisites
- `stages/c-lambda/scripts/deploy-infrastructure.sh` - CDK deployment script for Lambda infrastructure
- `stages/c-lambda/scripts/validate-deployment.sh` - Script to test Lambda function and validate deployment
- `stages/c-lambda/scripts/cleanup-rollback.sh` - Cleanup script for failed deployments
- `apps/hello-world-lambda/index.js` - Lambda function implementation returning timestamp and completion message
- `stages/c-lambda/iac/test/lambda-stack.test.ts` - Unit tests for CDK stack
- `stages/c-lambda/TESTING.md` - Comprehensive testing guide for AWS_IAM authenticated Lambda function

### Notes

- Follow the established patterns from Stage A and Stage B for script structure, naming conventions, and data management
- Use AWS CLI for Lambda function testing rather than creating separate test files for the simple Lambda function
- CDK tests should validate stack synthesis and resource creation
- All scripts must handle AWS profile configuration consistently with previous stages

## Tasks

- [x] 1.0 Analyze Existing Stage Patterns and Create Pattern Documentation
  - [x] 1.1 Study `stages/a-cloudfront/go-a.sh` and `stages/b-ssl/go-b.sh` to understand main script structure and user interaction patterns
  - [x] 1.2 Analyze all child scripts in `stages/a-cloudfront/scripts/` and `stages/b-ssl/scripts/` folders to understand functionality, parameter passing, and error handling
  - [x] 1.3 Review existing CDK implementations in `stages/a-cloudfront/iac/` and `stages/b-ssl/iac/` to understand stack patterns and naming conventions
  - [x] 1.4 Examine `data/` folder structures and JSON file formats from Stage A and B to understand data management patterns
  - [x] 1.5 Document discovered patterns in `stages/c-lambda/data/pattern-analysis.json` including script structure, naming conventions, data management, and error handling approaches
  - [x] 1.6 Identify AWS profile usage patterns and resource tagging strategies from previous stages

- [x] 2.0 Set Up Stage C Infrastructure Foundation
  - [x] 2.1 Create `stages/c-lambda/` directory structure following established patterns
  - [x] 2.2 Create `stages/c-lambda/data/` folder for inputs, discovery, and outputs JSON files
  - [x] 2.3 Create `stages/c-lambda/scripts/` folder for child scripts
  - [x] 2.4 Initialize CDK project in `stages/c-lambda/iac/` with appropriate package.json, cdk.json, and tsconfig.json
  - [x] 2.5 Set up CDK dependencies matching Node.js 20 runtime and existing CDK versions from previous stages
  - [x] 2.6 Create basic CDK app.ts entry point following established patterns

- [x] 3.0 Implement Lambda Function with Function URL
  - [x] 3.1 Create `apps/hello-world-lambda/index.js` with Node.js 20 handler that returns JSON with ISO timestamp and completion message
  - [x] 3.2 Implement CDK Lambda stack in `stages/c-lambda/iac/lib/lambda-stack.ts` with Function URL enabled and AWS_IAM auth type
  - [x] 3.3 Configure CloudWatch log group with 30-day retention policy in CDK stack
  - [x] 3.4 Set up IAM execution role for Lambda function with appropriate CloudWatch logging permissions
  - [x] 3.5 Configure Lambda function properties (Node.js 20 runtime, 128MB memory, 30-second timeout)
  - [x] 3.6 Implement CDK context management to consume Stage A and B outputs for consistent naming and configuration
  - [x] 3.7 Export Lambda function ARN, name, region, and Function URL in CDK stack outputs

- [x] 4.0 Create Stage C Deployment Scripts Following Established Patterns
  - [x] 4.1 Create `stages/c-lambda/scripts/gather-inputs.sh` to collect user inputs and validate prerequisites from previous stages
  - [x] 4.2 Create `stages/c-lambda/scripts/aws-discovery.sh` to discover AWS account information and validate existing resources
  - [x] 4.3 Create `stages/c-lambda/scripts/deploy-infrastructure.sh` to execute CDK deployment with proper context and error handling
  - [x] 4.4 Create `stages/c-lambda/scripts/validate-deployment.sh` to test Lambda function via AWS CLI and validate JSON response format
  - [x] 4.5 Create `stages/c-lambda/scripts/cleanup-rollback.sh` for cleanup of failed deployments
  - [x] 4.6 Create main `stages/c-lambda/go-c.sh` script orchestrating all child scripts with user interaction and data management
  - [x] 4.7 Create `stages/c-lambda/status-c.sh` for checking deployment status and resource health
  - [x] 4.8 Create `stages/c-lambda/undo-c.sh` for complete rollback of Stage C resources

- [x] 5.0 Implement Testing and Validation Framework
  - [x] 5.1 Create CDK unit tests in `stages/c-lambda/iac/test/lambda-stack.test.ts` to validate stack synthesis and resource creation
  - [x] 5.2 Implement AWS CLI testing commands in validation script to invoke Lambda function and verify JSON response format
  - [x] 5.3 Add CloudWatch logs validation to ensure logging is working correctly with 30-day retention
  - [x] 5.4 Create comprehensive outputs.json generation with all identifiers needed for Stage D integration
  - [x] 5.5 Validate that Function URL is accessible and returns proper timestamp and completion message
  - [x] 5.6 Test integration with previous stage outputs to ensure consistency and proper resource referencing
  - [x] 5.7 Document testing procedures and success criteria in deployment scripts

### Implementation Notes

- [x] **Production Naming Correction**: Function name changed from `{prefix}-hello-world-api` to `{prefix}-api` to be production-ready
- [x] **Log Group Naming**: Log group name corrected from `/aws/lambda/{prefix}-hello-world-api` to `/aws/lambda/{prefix}-api`
- [x] **Testing Documentation**: Created comprehensive `TESTING.md` guide for AWS_IAM authenticated Lambda function
- [x] **Security Configuration**: Function URL uses AWS_IAM authentication for secure access (not public)
- [x] **Unit Tests**: All 32 unit tests pass with corrected naming conventions
- [x] **Deployment Validation**: Enhanced validation script provides clear testing instructions for developers 