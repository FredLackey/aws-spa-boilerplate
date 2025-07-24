# Task List: Stage B SSL Certificate Deployment

Based on PRD: `prd-stage-b-ssl.md`

## Relevant Files

- `stages/b-ssl/go-b.sh` - Main orchestration script for Stage B SSL deployment (follows Stage A patterns)
- `stages/b-ssl/status-b.sh` - Status checking script for Stage B deployment
- `stages/b-ssl/undo-b.sh` - Rollback script for Stage B (with fallback to Stage A undo)
- `stages/b-ssl/scripts/gather-inputs.sh` - Collect domain names and validate Stage A prerequisites
- `stages/b-ssl/scripts/aws-discovery.sh` - Discover Route53 zones and validate account access
- `stages/b-ssl/scripts/deploy-infrastructure.sh` - Create certificate and update CloudFront via CDK
- `stages/b-ssl/scripts/deploy-dns.sh` - Configure Route53 DNS validation records
- `stages/b-ssl/scripts/validate-deployment.sh` - Test HTTPS connectivity and certificate attachment
- `stages/b-ssl/scripts/cleanup-rollback.sh` - Remove SSL configuration and revert to Stage A state
- `stages/b-ssl/data/inputs.json` - Store domain list, AWS profiles, and Stage A dependency data
- `stages/b-ssl/data/discovery.json` - Store Route53 zone information, account IDs, and resource validation results
- `stages/b-ssl/data/outputs.json` - Store certificate ARN, updated CloudFront details, and Stage A passthrough data
- `stages/b-ssl/data/cdk-outputs.json` - CDK stack outputs for certificate and CloudFront resources
- `stages/b-ssl/data/cdk-stack-outputs.json` - Raw CDK stack outputs from deployment
- `stages/b-ssl/iac/app.ts` - CDK application entry point for Stage B infrastructure
- `stages/b-ssl/iac/lib/ssl-certificate-stack.ts` - CDK stack for SSL certificate and CloudFront updates
- `stages/b-ssl/iac/lib/iac-stack.ts` - Main IAC stack definition following Stage A patterns
- `stages/b-ssl/iac/cdk.json` - CDK configuration with context for Stage B deployment
- `stages/b-ssl/iac/package.json` - NPM dependencies for CDK infrastructure
- `stages/b-ssl/iac/tsconfig.json` - TypeScript configuration for CDK code

### Notes

- All scripts should follow the established patterns from Stage A (`stages/a-cloudfront/`)
- Data files must maintain JSON structure compatibility with Stage A for downstream stages
- CDK infrastructure should reuse and extend existing CloudFront distribution from Stage A
- Testing must be performed using the actual deployment command: `./go-b.sh -d www.sbx.briskhaven.com -d sbx.briskhaven.com`

## Tasks

- [x] 1.0 Create Stage B Directory Structure and Main Orchestration Script
  - [x] 1.1 Create `stages/b-ssl/` directory structure matching Stage A patterns
  - [x] 1.2 Create `stages/b-ssl/data/` directory for JSON data files
  - [x] 1.3 Create `stages/b-ssl/scripts/` directory for helper scripts
  - [x] 1.4 Create `stages/b-ssl/iac/` directory for CDK infrastructure code
  - [x] 1.5 Implement `go-b.sh` main orchestration script following Stage A patterns
  - [x] 1.6 Add CloudFront in-progress distribution checking before deployment
  - [x] 1.7 Implement step-by-step progress tracking and error handling
  - [x] 1.8 Add support for continuing from partial completion states
  - [x] 1.9 Create `status-b.sh` script for deployment status checking
  - [x] 1.10 Create `undo-b.sh` script with fallback to Stage A's `undo-a.sh`

- [x] 2.0 Implement Input Collection and Validation System
  - [x] 2.1 Create `gather-inputs.sh` script to accept multiple `-d` domain parameters
  - [x] 2.2 Implement FQDN format validation for all provided domains
  - [x] 2.3 Require at least one domain parameter and support unlimited additional domains
  - [x] 2.4 Load and validate Stage A output data from `stages/a-cloudfront/data/outputs.json`
  - [x] 2.5 Verify Stage A completed successfully (`readyForStageB: true`)
  - [x] 2.6 Extract AWS profiles (infrastructure and target) from Stage A data
  - [x] 2.7 Sort domain names alphabetically for consistent processing
  - [x] 2.8 Save all inputs to `stages/b-ssl/data/inputs.json` following Stage A patterns
  - [x] 2.9 Add command-line usage help and examples
  - [x] 2.10 Implement input validation error messages with clear guidance

- [x] 3.0 Build AWS Discovery and Route53 Zone Management
  - [x] 3.1 Create `aws-discovery.sh` script following Stage A patterns
  - [x] 3.2 Validate credentials for both infrastructure and target AWS profiles
  - [x] 3.3 Capture and store both infrastructure and target account IDs
  - [x] 3.4 Discover existing Route53 hosted zones in infrastructure account for each domain
  - [x] 3.5 Validate that hosted zones exist for all top-level domains
  - [x] 3.6 Handle subdomains by finding appropriate parent hosted zones
  - [x] 3.7 Implement clear error messages for missing hosted zones (no zone creation)
  - [x] 3.8 Save discovery results to `stages/b-ssl/data/discovery.json`
  - [x] 3.9 Create `deploy-dns.sh` script for DNS validation record management
  - [x] 3.10 Implement DNS validation record creation in existing Route53 zones
  - [x] 3.11 Ensure DNS validation records are retained permanently (no cleanup)

- [x] 4.0 Develop SSL Certificate Management and CloudFront Integration
  - [x] 4.1 Set up CDK infrastructure directory with `package.json` and dependencies
  - [x] 4.2 Create CDK `app.ts` entry point for Stage B infrastructure
  - [x] 4.3 Implement `ssl-certificate-stack.ts` CDK stack for certificate management
  - [x] 4.4 Add logic to check for existing SSL certificates matching domain sets and reuse them
  - [x] 4.5 Create single SSL certificate covering all provided domains using DNS validation
  - [x] 4.6 Implement certificate validation polling with timeout handling
  - [x] 4.7 Detect and report AWS Certificate Manager limit errors without proactive validation
  - [x] 4.8 Update existing CloudFront distribution from Stage A with SSL certificate
  - [x] 4.9 Add all domains as alternate domain names (CNAMEs) to CloudFront distribution
  - [x] 4.10 Configure CloudFront behaviors to require SSL/HTTPS after certificate attachment
  - [x] 4.11 Handle CloudFront distribution update propagation delays
  - [x] 4.12 Create `deploy-infrastructure.sh` script to orchestrate CDK deployment
  - [x] 4.13 Generate CDK context from Stage A and Stage B data files
  - [x] 4.14 Save CDK outputs to `cdk-outputs.json` and `cdk-stack-outputs.json`

- [x] 5.0 Create Deployment Validation and Rollback Systems
  - [x] 5.1 Create `validate-deployment.sh` script for HTTPS connectivity testing
  - [x] 5.2 Implement automated curl tests for each configured domain
  - [x] 5.3 Verify SSL certificate details are correctly attached to CloudFront distribution
  - [x] 5.4 Confirm DNS resolution works correctly for all configured domains
  - [x] 5.5 Provide clear success/failure status for each validation step
  - [x] 5.6 Generate comprehensive `stages/b-ssl/data/outputs.json` with certificate ARN and distribution details
  - [x] 5.7 Preserve Stage A outputs in Stage B outputs file for downstream stages
  - [x] 5.8 Create `cleanup-rollback.sh` script for graceful Stage B rollback
  - [x] 5.9 Implement rollback to remove SSL configuration and revert to Stage A state
  - [x] 5.10 Add fallback rollback using Stage A's `undo-a.sh` for complete cleanup
  - [x] 5.11 Implement comprehensive error handling for common failure scenarios
  - [x] 5.12 Add support for re-running deployment script from partial completion states 