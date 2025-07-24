# Product Requirements Document: Stage A CloudFront Deployment

## Introduction/Overview

Stage A establishes the foundational CloudFront distribution infrastructure for the AWS SPA Boilerplate project. This stage deploys a simple HTML application through CloudFront to validate basic CDN functionality before adding complexity like SSL certificates, APIs, or React applications in subsequent stages.

The primary goal is to create a robust, interactive deployment system that provisions AWS CloudFront infrastructure, deploys static content, and validates successful deployment through automated testing.

## Goals

1. **Infrastructure Provisioning**: Deploy a CloudFront distribution using AWS CDK with proper configuration for static content delivery
2. **Interactive Deployment**: Provide a user-friendly interactive script that guides users through the deployment process step-by-step
3. **Data Management**: Implement structured JSON data management for inputs, discovery, and outputs to support subsequent stages
4. **Validation and Testing**: Automatically validate deployment success through HTTP connectivity testing
5. **Foundation for Sequential Stages**: Generate proper outputs required by Stage B (SSL) and later stages

## User Stories

- **As a developer**, I want to run a single script (`go-a.sh`) that guides me through deploying my first CloudFront distribution so that I can validate AWS hosting works before adding complexity
- **As a developer**, I want to specify AWS profiles for infrastructure and target resources so that I can deploy across different AWS accounts or environments
- **As a developer**, I want to provide a distribution prefix so that all my resources follow a consistent naming convention
- **As a developer**, I want the script to validate my inputs and check for existing resources so that I avoid naming conflicts and deployment failures
- **As a developer**, I want automated testing to confirm my deployment worked so that I can confidently proceed to Stage B
- **As a subsequent stage user**, I want Stage A to output structured data so that Stage B can automatically configure SSL certificates for my CloudFront distribution

## Functional Requirements

### 1. Interactive Deployment Script (`go-a.sh`)

1.1. The main script must orchestrate the deployment workflow by calling modular helper scripts
1.2. The main script must provide step-by-step progress updates throughout the deployment process
1.3. The main script must handle errors from helper scripts and coordinate rollback procedures
1.4. The main script must remain under 200 lines to ensure readability and maintainability

**Helper Scripts Requirements:**

**1.1a. Input Gathering Script (`gather-inputs.sh`)**
- Must prompt for and validate an **infrastructure AWS profile** for global resources
- Must prompt for and validate a **target AWS profile** for stage-specific resources  
- Must prompt for a **distribution prefix** in kebab-case format (lowercase, alphanumeric and hyphens only)
- Must prompt for the **target AWS region** for resource deployment
- Must save validated inputs to `data/inputs.json`

**1.1b. AWS Discovery Script (`aws-discovery.sh`)**
- Must validate both AWS profiles have valid credentials and capture account IDs
- Must check for existing resources with the same prefix and prompt for overwrite confirmation
- Must gather AWS account information needed for deployment
- Must save discovery results to `data/discovery.json`

**1.1c. Infrastructure Deployment Script (`deploy-infrastructure.sh`)**
- Must execute CDK deployment with proper configuration
- Must handle CDK deployment errors and provide meaningful feedback
- Must capture CDK outputs for subsequent processing

**1.1d. Content Deployment Script (`deploy-content.sh`)**
- Must upload hello-world-html files to the S3 bucket
- Must invalidate CloudFront cache after content upload
- Must verify content upload success

**1.1e. Validation Script (`validate-deployment.sh`)**
- Must perform HTTP connectivity testing using curl to validate deployment success
- Must verify specific known text content from the HTML page
- Must save validation results and deployment outputs to `data/outputs.json`

**1.1f. Cleanup/Rollback Script (`cleanup-rollback.sh`)**
- Must handle deployment failures with automatic rollback functionality
- Must clean up partial deployments and orphaned resources
- Must provide clear error reporting and recovery instructions

### 2. Data Management System

2.1. The script must save user inputs to `data/inputs.json` in human-readable format
2.2. The script must save AWS discovery results to `data/discovery.json` in human-readable format
2.3. The script must save deployment outputs to `data/outputs.json` in human-readable format
2.4. The discovery file must include account IDs for both infrastructure and target profiles
2.5. The outputs file must include CloudFront distribution ID, domain name, and HTTP endpoint URL
2.6. The outputs file must include all data required by Stage B for SSL certificate attachment

### 3. AWS CDK Infrastructure Code

3.1. The CDK application must create a CloudFront distribution with minimal cache timeout (1 minute)
3.2. The CDK application must create an S3 bucket for static content storage
3.3. The CDK application must configure CloudFront to serve content from the S3 bucket
3.4. The CDK application must use input parameters from the data management system
3.5. The CDK application must export distribution ID, domain name, and other required outputs
3.6. The CDK application must support deployment to a single specified AWS region

### 4. Application Deployment

4.1. The deployment process must upload the `hello-world-html` application files to the S3 bucket
4.2. The deployment process must invalidate CloudFront cache after content upload
4.3. The deployment process must verify content is accessible via the CloudFront endpoint

### 5. Testing and Validation

5.1. The script must test HTTP connectivity to the CloudFront distribution URL
5.2. The script must validate that the index.html content is returned correctly
5.3. The script must verify specific known text content from the HTML page
5.4. The CDK deployment must report success/failure status
5.5. All validation failures must trigger rollback procedures

## Non-Goals (Out of Scope)

- SSL/HTTPS configuration (handled in Stage B)
- Custom error pages or SPA routing support
- API integration or Lambda functions
- React application deployment
- Multiple region deployment
- Custom CloudFront cache behaviors beyond basic configuration
- Advanced CDK construct libraries or complex AWS service integrations
- Non-interactive or automated deployment modes
- Integration with CI/CD pipelines

## Design Considerations

### Directory Structure
The implementation must follow the established project structure:
```
stages/a-cloudfront/
├── go-a.sh                 # Main deployment script
├── iac/                    # AWS CDK infrastructure code
├── scripts/                # Helper scripts and utilities  
└── data/                   # JSON data management
    ├── inputs.json         # User-provided inputs
    ├── discovery.json      # AWS account discovery results
    └── outputs.json        # Stage deployment outputs
```

### User Interface Guidelines
- Use clear, descriptive prompts with examples
- Provide progress indicators for long-running operations
- Display validation results clearly
- Use consistent formatting for status messages
- Include helpful error messages with suggested actions

### Data Format Standards
All JSON files must be formatted for human readability with proper indentation and structure. The outputs.json file must be compatible with Stage B input requirements.

### Script Modularization
To maintain readability and maintainability, the main `go-a.sh` script must be kept minimal and delegate specific tasks to smaller, focused scripts stored in the `scripts/` directory. This modular approach ensures:

- **Main Script Simplicity**: The `go-a.sh` file should primarily orchestrate the deployment workflow
- **Single Responsibility**: Each helper script should handle one specific aspect of the deployment
- **Reusability**: Common functionality can be shared across stages
- **Testability**: Individual components can be tested independently
- **Maintainability**: Smaller files are easier to read, debug, and modify

**Recommended Script Structure:**
```
stages/a-cloudfront/
├── go-a.sh                     # Main orchestration script
└── scripts/
    ├── gather-inputs.sh        # Interactive user input collection and validation
    ├── aws-discovery.sh        # AWS account discovery and resource checking
    ├── deploy-infrastructure.sh # CDK deployment orchestration
    ├── deploy-content.sh       # Application file upload and cache invalidation
    ├── validate-deployment.sh  # Testing and validation procedures
    └── cleanup-rollback.sh     # Error handling and rollback procedures
```

**Implementation Guidelines:**
- Each script should accept parameters rather than relying on global variables
- Scripts should return meaningful exit codes (0 for success, non-zero for failure)
- All scripts should include proper error handling and logging
- Common functions should be extracted to shared utility scripts
- Each script should be executable independently for testing purposes

## Technical Considerations

### Dependencies
- AWS CLI must be configured with valid profiles
- AWS CDK must be installed and available
- Node.js runtime for CDK execution
- curl command for HTTP testing
- Standard Unix/Linux shell utilities

### AWS Permissions Required
The infrastructure and target AWS profiles must have permissions for:
- CloudFront distribution creation and management
- S3 bucket creation and content management
- IAM role creation for CloudFront
- CDK deployment operations (CloudFormation stack management)

### Integration Points
- Must output data compatible with Stage B SSL certificate attachment
- Must support Stage D content replacement workflow
- Must integrate with the hello-world-html application files

## Success Metrics

1. **Deployment Success Rate**: 100% success rate for valid input combinations
2. **User Experience**: Single-command deployment with clear feedback at each step
3. **Validation Accuracy**: Automated testing correctly identifies successful vs. failed deployments
4. **Data Integrity**: All required outputs generated in correct format for Stage B consumption
5. **Performance**: Complete deployment process completes within 10 minutes under normal conditions
6. **Rollback Effectiveness**: Failed deployments are completely rolled back without leaving orphaned resources

## Open Questions

1. Should the script support resuming from partial failures, or always start fresh?
2. What specific text content should be validated in the HTML response to confirm successful deployment?
3. Should there be size limits on the distribution prefix to ensure compatibility with AWS resource naming constraints?
4. How should the script handle AWS CLI credential expiration during long-running deployments?
5. Should deployment logs be preserved in a separate log file for debugging purposes? 