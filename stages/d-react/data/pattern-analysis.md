# Stage D React Deployment - Pattern Analysis

## Overview

This document analyzes naming conventions, structural patterns, and architectural approaches used across Stages A (CloudFront), B (SSL), and C (Lambda) to ensure consistency in Stage D (React) implementation.

## 1. Bash Script File Naming Conventions

### Main Deployment Scripts (Root Level)
- **Pattern**: `go-{stage}.sh` - Main orchestration script for each stage
  - `go-a.sh` - Stage A CloudFront deployment
  - `go-b.sh` - Stage B SSL Certificate deployment  
  - `go-c.sh` - Stage C Lambda deployment
  - **Stage D**: `go-d.sh` - React deployment

### Status and Management Scripts (Root Level)
- **Pattern**: `status-{stage}.sh` - Deployment status checking
  - `status-a.sh`, `status-b.sh`, `status-c.sh`
  - **Stage D**: `status-d.sh`

- **Pattern**: `undo-{stage}.sh` - Rollback operations
  - `undo-a.sh`, `undo-b.sh`, `undo-c.sh`
  - **Stage D**: `undo-d.sh`

### Scripts Directory Structure
All stages have a consistent `scripts/` subdirectory containing:
- `gather-inputs.sh` - Collect user inputs and load previous stage outputs
- `aws-discovery.sh` - Discover existing AWS resources and validate environment
- `deploy-infrastructure.sh` - CDK deployment orchestration
- `cleanup-rollback.sh` - Comprehensive cleanup and rollback operations
- `validate-deployment.sh` - Post-deployment validation and testing

**Additional scripts per stage**:
- Stage A: `deploy-content.sh` - Static content deployment
- Stage B: `deploy-dns.sh`, `manage-dns-validation.sh`, `validate-architecture.sh` - SSL/DNS specific
- Stage C: No additional scripts

**Stage D specific scripts needed**:
- Focus on React build and content deployment integration

## 2. CDK Stack Naming Patterns

### Stack Class Names
- **Pattern**: `Stage{Letter}{Purpose}Stack`
  - Stage A: `CloudFrontStack` (simple name, no stage prefix)
  - Stage B: `SslCertificateStack` (simple name, no stage prefix)
  - Stage C: `LambdaStack` (simple name, no stage prefix)
  - **Stage D**: `ReactStack`

### CDK Stack IDs (for deployment)
- **Pattern**: `Stage{Letter}{Purpose}Stack`
  - Stage A: `StageACloudFrontStack`
  - Stage B: `StageBSslCertificateStack` 
  - Stage C: `StageCLambdaStack`
  - **Stage D**: `StageDReactStack`

### Stack Properties Interface
- **Pattern**: `{StackClass}Props extends cdk.StackProps`
  - `CloudFrontStackProps`, `SslCertificateStackProps`, `LambdaStackProps`
  - **Stage D**: `ReactStackProps`

## 3. CDK Configuration File Patterns

### package.json Structure
Consistent across all stages:
```json
{
  "name": "iac",
  "version": "0.1.0",
  "bin": { "iac": "bin/iac.js" },
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w", 
    "test": "jest",
    "cdk": "cdk"
  },
  "devDependencies": {
    "@types/jest": "^29.5.14",
    "@types/node": "22.7.9",
    "aws-cdk": "2.1021.0",
    "jest": "^29.7.0",
    "ts-jest": "^29.2.5",
    "ts-node": "^10.9.2",
    "typescript": "~5.6.3"
  },
  "dependencies": {
    "aws-cdk-lib": "^2.206.0",
    "constructs": "^10.0.0"
  }
}
```

### cdk.json Structure
- **app**: `"npx ts-node --prefer-ts-exts app.ts"`
- **watch**: Standard exclusion patterns
- **context**: Stage-specific configuration with pattern `stage-{letter}-{purpose}:{property}`

### app.ts Entry Point Pattern
- Import pattern: `import { {StackClass} } from './lib/{stack-file}'`
- Context reading: `app.node.tryGetContext('stage-{letter}-{purpose}:{property}')`
- Stack instantiation: `new {StackClass}(app, 'Stage{Letter}{Purpose}Stack', props)`

## 4. JSON Data File Schema Patterns

### inputs.json Schema
Common properties across stages:
```json
{
  "infrastructureProfile": "string",
  "targetProfile": "string", 
  "distributionPrefix": "string",
  "targetRegion": "string",
  "targetVpcId": "string"
}
```

### discovery.json Schema
Common properties:
```json
{
  "infrastructureProfile": "string",
  "targetProfile": "string",
  "infrastructureAccountId": "string", 
  "targetAccountId": "string",
  "targetRegion": "string",
  "distributionPrefix": "string",
  "targetVpcId": "string",
  "timestamp": "ISO8601",
  "{service}ServiceValidated": "boolean",
  "resourceConflictsChecked": "boolean",
  "quotasDiscovered": "boolean"
}
```

### outputs.json Schema
Two-level structure:
```json
{
  "stage{Letter}": {
    // Stage-specific outputs
    "deploymentTimestamp": "ISO8601",
    // ... other stage outputs
  },
  // Flattened important outputs for easy access
  "deploymentTimestamp": "ISO8601",
  "readyForStage{NextLetter}": "boolean"
}
```

## 5. AWS Resource Naming Conventions

### Resource Naming Pattern
- **Bucket Names**: `{distributionPrefix}-{purpose}-{accountId}`
- **Role Names**: `{distributionPrefix}-{service}-{purpose}-role`
- **Log Groups**: `/aws/{service}/{distributionPrefix}-{purpose}`
- **Stack Names**: `Stage{Letter}{Purpose}Stack`

### CDK Construct IDs
- PascalCase with descriptive names
- Examples: `ContentBucket`, `Distribution`, `LambdaExecutionRole`, `OriginAccessControl`

## 6. Variable Naming Patterns

### Script Variables
- **Directories**: `SCRIPT_DIR`, `SCRIPTS_DIR`, `DATA_DIR`, `IAC_DIR`
- **AWS Profiles**: `INFRA_PROFILE`, `TARGET_PROFILE`
- **Resource IDs**: `DISTRIBUTION_ID`, `CERTIFICATE_ARN`, `BUCKET_NAME`
- **Flags**: `SKIP_VALIDATION`, `FORCE_CLEANUP`, `DRY_RUN`

### CDK Context Keys
- **Pattern**: `stage-{letter}-{purpose}:{property}`
- Examples:
  - `stage-b-ssl:domains`
  - `stage-c-lambda:distributionPrefix`
  - `stage-b-ssl:existingCertificateArn`

## 7. User Interaction Approaches

### Command Line Arguments
- **Stage A**: Multiple required flags (--infraprofile, --targetprofile, --prefix, --region, --vpc)
- **Stage B**: Simple domain specification (-d domain, repeatable)
- **Stage C**: No arguments required (derives from previous stages)
- **Stage D**: Should follow Stage C pattern (no arguments, derive from previous stages)

### Help and Usage
- All scripts support `-h` and `--help` flags
- Usage functions show examples and explain requirements
- Clear error messages for missing arguments

### Progress and Feedback
- Consistent emoji usage: ✅ success, ❌ error, ⚠️ warning, 🔍 discovery, 📋 info
- Step-by-step progress reporting
- Clear section headers and logging

## 8. Cross-Stage Reference Patterns

### Data Flow Between Stages
- Each stage loads outputs from previous stages via JSON files
- Validation ensures required previous stage completion
- Context values passed to CDK via cdk.json updates

### Resource Dependencies
- Stage A: Creates CloudFront distribution and S3 bucket
- Stage B: Updates CloudFront with SSL certificate and custom domains
- Stage C: Creates Lambda with Function URL, references CloudFront/S3
- **Stage D**: Must integrate with existing CloudFront distribution from Stage A, preserve SSL from Stage B

### Integration Points
- **CloudFront Distribution ID**: Shared across stages B, C, D
- **S3 Bucket**: Created in A, used in D for React content deployment
- **SSL Certificate**: Created in B, must be preserved in D
- **Custom Domains**: Configured in B, must remain functional in D

## 9. Error Handling and Logging Patterns

### Script Error Handling
- `set -euo pipefail` in all bash scripts
- Consistent error message formatting
- Cleanup on failure with trap functions
- Validation before destructive operations

### CDK Error Handling
- Context validation with clear error messages
- Resource existence checks before creation
- Conditional logic for resource reuse vs creation

## 10. Stage D Specific Implementation Guidelines

### React Integration Requirements
1. **Preserve Stage B SSL Configuration**: Do not modify certificates or domain settings
2. **Update CloudFront Content**: Replace S3 bucket content with React build artifacts
3. **Clean Build Process**: Remove existing Vite dist/ directory before building
4. **Asset Path Preservation**: Ensure React router and asset paths work with CloudFront
5. **Cache Invalidation**: Immediate invalidation after content deployment

### Recommended Stage D Patterns
- **go-d.sh**: No command line arguments, derive configuration from Stages A & B
- **React Build**: Execute in apps/hello-world-react directory
- **Content Deployment**: Replace S3 bucket content atomically
- **CDK Stack**: `StageDReactStack` - minimal changes to existing infrastructure
- **Validation**: Test HTTPS URLs from Stage B with React content

### Files to Create for Stage D
- `go-d.sh` - Main deployment script
- `status-d.sh` - Status checking
- `undo-d.sh` - Rollback script  
- `scripts/gather-inputs.sh` - Input collection
- `scripts/aws-discovery.sh` - AWS discovery
- `scripts/deploy-infrastructure.sh` - CDK deployment
- `scripts/cleanup-rollback.sh` - Cleanup operations
- `scripts/validate-deployment.sh` - Deployment validation
- `iac/app.ts` - CDK app entry point
- `iac/lib/react-stack.ts` - CDK stack definition
- `iac/cdk.json` - CDK configuration
- `iac/package.json` - Dependencies
- `iac/tsconfig.json` - TypeScript config
- `data/inputs.json` - Input data
- `data/discovery.json` - Discovery results  
- `data/outputs.json` - Stage outputs

This pattern analysis ensures Stage D maintains consistency with established architectural patterns while implementing React-specific functionality. 