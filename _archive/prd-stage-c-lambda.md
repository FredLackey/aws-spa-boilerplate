# Product Requirements Document: Stage C - Hello World API in Lambda

## Introduction/Overview

Stage C introduces serverless API functionality to the AWS SPA boilerplate by deploying a simple Node.js Lambda function that returns a JSON object containing the current server timestamp and a confirmation message indicating Stage C completion. This stage builds upon the CloudFront distribution from Stage A and SSL certificate from Stage B, providing the foundation for API integration that will be consumed by CloudFront behaviors in subsequent stages.

The primary goal is to establish a working Lambda function that can be invoked via AWS CLI and is ready to be integrated with CloudFront for API routing in Stage D and Stage E.

## Goals

1. Deploy a minimal Node.js Lambda function that returns current server timestamp in ISO format and a Stage C completion message
2. Establish CloudWatch logging with 30-day retention policy
3. Validate Lambda functionality through AWS CLI invocation
4. Generate comprehensive outputs.json file with all identifiers needed for Stage D integration
5. Demonstrate serverless API capability without external dependencies
6. Prepare Lambda function for CloudFront behavior integration

## User Stories

1. **As a developer**, I want to deploy a simple Lambda function so that I can validate serverless API functionality in my AWS environment.

2. **As a developer**, I want the Lambda function to return a current timestamp and confirmation message so that I can verify no caching is occurring and confirm Stage C is working when testing API responses.

3. **As a developer**, I want to test the Lambda function via AWS CLI so that I can confirm it's working before integrating with CloudFront.

4. **As a developer**, I want CloudWatch logging enabled so that I can troubleshoot issues and monitor function execution.

5. **As a developer**, I want the stage to produce an outputs.json file so that Stage D can consume the Lambda function details for CloudFront integration.

6. **As a developer**, I want to leverage existing AWS profiles and previous stage outputs so that the deployment is consistent with the established infrastructure.

## Functional Requirements

1. **Lambda Function Implementation**
   - Create a Node.js 20 Lambda function handler that returns a JSON object
   - JSON response must contain current server timestamp in ISO 8601 format
   - JSON response must include a confirmation message indicating "Stage C is complete - if you can read this"
   - Function must have no external dependencies (Node.js built-ins only)
   - Function must be deployable via AWS CDK

2. **AWS Infrastructure Provisioning**
   - Deploy Lambda function using AWS CDK infrastructure as code
   - Configure appropriate IAM execution role for Lambda function
   - Set up CloudWatch log group with 30-day retention policy
   - Use consistent naming conventions with distribution prefix from Stage A

3. **Integration with Previous Stages**
   - **CRITICAL**: Thoroughly analyze and understand ALL existing scripts from Stage A (`stages/a-cloudfront/`) and Stage B (`stages/b-ssl/`) before implementation
   - Study the main orchestration scripts (`go-a.sh` and `go-b.sh`) to understand established patterns for user interaction, data management, and deployment orchestration
   - **Analyze ALL child scripts** in the `scripts/` folders from both stages:
     - Stage A: `aws-discovery.sh`, `cleanup-rollback.sh`, `deploy-content.sh`, `deploy-infrastructure.sh`, `gather-inputs.sh`, `validate-deployment.sh`
     - Stage B: `aws-discovery.sh`, `cleanup-rollback.sh`, `deploy-dns.sh`, `deploy-infrastructure.sh`, `gather-inputs.sh`, `manage-dns-validation.sh`, `validate-architecture.sh`, `validate-deployment.sh`
   - Understand how child scripts are called, what parameters they receive, and what outputs they generate
   - Review existing CDK stack implementations to understand naming conventions, resource tagging, and infrastructure patterns
   - Examine the `data/` folder structure and JSON file formats to maintain consistency
   - Read and utilize outputs from Stage A (`stages/a-cloudfront/data/outputs.json`)
   - Read and utilize outputs from Stage B (`stages/b-ssl/data/outputs.json`)
   - Use same AWS profile configuration as previous stages
   - Maintain consistent resource naming conventions established in previous stages
   - Follow established tagging and resource organization patterns

4. **Data Management**
   - Capture user inputs in `data/inputs.json` file
   - Perform AWS account discovery and save results to `data/discovery.json`
   - Generate comprehensive `data/outputs.json` with Lambda function details

5. **Testing and Validation**
   - Provide AWS CLI command to invoke Lambda function directly
   - Validate JSON response contains properly formatted ISO timestamp and Stage C completion message
   - Confirm CloudWatch logs are being generated
   - Verify function is ready for CloudFront integration

6. **Output Generation**
   - Lambda function ARN
   - Lambda function name
   - Lambda function region
   - CloudWatch log group name
   - IAM execution role ARN
   - Any other identifiers needed for Stage D CloudFront behavior configuration

## Non-Goals (Out of Scope)

1. **API Gateway Integration** - Direct Lambda invocation only; no HTTP endpoints at this stage
2. **Complex Error Handling** - Minimal error handling since function performs simple operations
3. **Performance Optimization** - No specific performance requirements or memory tuning
4. **External Dependencies** - No npm packages or external service calls
5. **Authentication/Authorization** - No security layers beyond basic Lambda execution role
6. **Database Integration** - No data persistence or external data sources
7. **Custom Domain Configuration** - Lambda will be accessed via CloudFront in later stages

## Recommended Architecture

Based on research into CloudFront Lambda integration capabilities, Stage C should implement:

### Lambda Function URL with CloudFront OAC Architecture
- **Lambda Function**: Node.js 20 function with Function URL enabled
- **CloudFront Integration**: Direct integration using Lambda Function URL as origin
- **Security**: Origin Access Control (OAC) to restrict access to CloudFront only
- **Authentication**: AWS_IAM auth type for Function URL (secured by OAC)
- **No API Gateway Required**: Direct CloudFront → Lambda Function URL integration

### Benefits of This Approach
- **Cost Effective**: Eliminates API Gateway costs while maintaining functionality
- **Simplified Architecture**: Fewer components to manage and configure
- **Enhanced Security**: OAC ensures Lambda is only accessible through CloudFront
- **Performance**: Direct integration reduces latency compared to API Gateway routing
- **Future Ready**: Prepared for CloudFront behaviors in Stage D and E

## Design Considerations

1. **Lambda Function Structure**
   - Simple handler function in `apps/hello-world-lambda/index.js`
   - Minimal code footprint for fast cold starts
   - Standard AWS Lambda event/context pattern

2. **CDK Stack Design**
   - Follow existing pattern from Stage A and Stage B
   - Use CDK context for configuration management
   - Export stack outputs for subsequent stages

3. **Resource Naming**
   - Use distribution prefix from Stage A for consistent naming
   - Follow AWS naming conventions for Lambda functions
   - Include stage identifier in resource names

## Technical Considerations

1. **Prerequisites Analysis**: Before beginning implementation, conduct thorough analysis of existing Stage A and Stage B implementations:
   - **Main Script Structure**: Understand the flow and organization of `go-a.sh` and `go-b.sh`
   - **Child Script Analysis**: Examine ALL scripts in `stages/a-cloudfront/scripts/` and `stages/b-ssl/scripts/` folders:
     - Understand the purpose and functionality of each child script
     - Analyze how they are invoked from the main scripts
     - Review parameter passing and return value patterns
     - Study error handling and validation approaches
     - Identify common utility functions and patterns
   - **Script Integration Patterns**: Understand how main scripts orchestrate child scripts
   - **Naming Conventions**: Identify resource naming patterns (distribution prefix usage, stack names, etc.)
   - **CDK Patterns**: Review existing CDK stack structures and context management approaches
   - **Data Management**: Understand inputs.json, discovery.json, and outputs.json file structures and content patterns
   - **AWS Profile Usage**: Identify how AWS profiles are selected and used consistently across stages

2. **Lambda Function URL Configuration**: Enable Function URL with AWS_IAM authentication for CloudFront OAC integration
3. **CloudFront OAC Setup**: Configure Origin Access Control for Lambda Function URL origin type (released April 2024)
4. **Node.js Runtime**: Use Node.js 20.x runtime for Lambda function
5. **Memory Configuration**: Use default Lambda memory allocation (128 MB should be sufficient)
6. **Timeout Configuration**: Set reasonable timeout (30 seconds should be more than adequate)
7. **CloudWatch Integration**: Automatic logging to CloudWatch with structured log retention
8. **CDK Dependencies**: Leverage existing CDK setup and context management from previous stages

## Success Metrics

1. **Deployment Success**: Lambda function deploys without errors via CDK
2. **Functional Validation**: AWS CLI invocation returns properly formatted JSON with ISO timestamp and Stage C completion message
3. **Logging Verification**: CloudWatch logs capture function execution details
4. **Output Generation**: Complete outputs.json file generated with all required identifiers
5. **Stage Integration**: Previous stage outputs successfully consumed and utilized
6. **Pattern Consistency**: Implementation follows established patterns from Stage A and Stage B for script structure, naming conventions, and data management
7. **Preparation for Next Stage**: All necessary information available for Stage D CloudFront behavior configuration

## Open Questions and Resolutions

### 1. Pattern Analysis Results
**Action Required**: Create a `data/pattern-analysis.json` artifact documenting discovered patterns from Stage A and Stage B analysis, including:
- Script structure and organization patterns
- Resource naming conventions
- Data management approaches
- Error handling patterns
- CDK context management

### 2. CloudFront Integration Method - **RESOLVED**
**Answer**: API Gateway is **NOT** required. CloudFront can integrate directly with Lambda functions through:
- **Lambda Function URLs** (recommended for Stage C): Direct HTTPS endpoints with Origin Access Control (OAC) for security
- **Direct Lambda integration**: CloudFront can invoke Lambda functions directly using behaviors

**Decision**: Use Lambda Function URLs with CloudFront OAC for Stage C, as this provides the simplest integration path while maintaining security.

### 3. Lambda Function URL - **RESOLVED** 
**Answer**: **YES**, enable Lambda Function URLs. This is the recommended approach because:
- Provides direct HTTPS endpoint for Lambda functions
- Supports CloudFront Origin Access Control (OAC) for security (released April 2024)
- Eliminates need for API Gateway in this stage
- Simplifies architecture while maintaining security
- Cost-effective solution

### 4. CORS Configuration - **RESOLVED**
**Answer**: CORS headers are **NOT** needed when CloudFront calls Lambda Function URLs directly. CORS is only required for browser-based cross-origin requests. Since CloudFront acts as a proxy/CDN, it handles the client-facing CORS requirements, and the Lambda function receives requests from CloudFront's infrastructure, not directly from browsers.

### 5. Response Format - **RESOLVED**
**Answer**: The JSON response should contain exactly:
```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "message": "Stage C is complete - if you can read this"
}
```
This provides the necessary validation for Stage C without over-engineering. Additional metadata can be added in later stages if needed. 