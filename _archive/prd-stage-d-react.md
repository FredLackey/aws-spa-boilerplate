# Product Requirements Document: Stage D - React SPA Deployment

## Introduction/Overview

Stage D replaces the basic HTML content from Stage A with a compiled React application built with Vite, while maintaining all infrastructure from the previous stages (CloudFront distribution from Stage A, SSL certificates and Route53 configuration from Stage B, and Lambda functions from Stage C). This stage demonstrates serving a modern Single Page Application through the existing CloudFront distribution using the same HTTPS URLs established in Stage B.

Additionally, Stage D introduces a pattern analysis system that evaluates the bash scripts, data structures, and deployment patterns from the first three stages to ensure consistency and identify best practices for Stage D implementation.

## Goals

1. **Content Replacement**: Replace the static HTML content in the existing CloudFront distribution with a compiled React application
2. **Pattern Consistency**: Analyze and document patterns from Stages A, B, and C to ensure Stage D follows established conventions
3. **Infrastructure Preservation**: Maintain all existing AWS resources (CloudFront distribution, SSL certificates, Route53 configuration, Lambda functions)
4. **Deployment Validation**: Verify React application loads successfully via HTTPS using the same URLs from Stage B
5. **Documentation Generation**: Create pattern analysis documentation to guide future stage development

## User Stories

**As a developer**, I want to replace the basic HTML content with a React application so that I can demonstrate modern SPA hosting capabilities while preserving the infrastructure investments from previous stages.

**As a developer**, I want to analyze patterns from previous stages so that Stage D follows the same naming conventions, script structures, and deployment approaches that made the first three stages successful.

**As a developer**, I want to build and deploy the React application automatically so that the deployment process is consistent with previous stages and doesn't require manual build steps.

**As a developer**, I want to validate the React deployment using the same testing approach from previous stages so that I can confirm the application loads correctly via HTTPS.

**As a system architect**, I want to preserve all existing AWS resources so that Stage D builds upon previous investments without requiring re-deployment of working infrastructure.

## Functional Requirements

### Pre-Development Pattern Analysis Requirements (MUST BE COMPLETED FIRST)

1. **Comprehensive File Analysis**: The system must recursively analyze all relevant files in stages/a-cloudfront, stages/b-ssl, and stages/c-lambda directories including:
   - Bash script files (*.sh)
   - CDK TypeScript files (*.ts)
   - CDK configuration files (cdk.json, package.json, tsconfig.json)
   - JSON data files (inputs.json, discovery.json, outputs.json)
   - CDK output files (cdk-outputs.json, cdk-stack-outputs.json)
2. **Pattern Documentation**: The system must create or update a pattern analysis document in markdown format in the stages/d-react/data/ directory
3. **Comprehensive Naming Convention Analysis**: The system must analyze and document:
   - Script file naming conventions (go-*.sh, undo-*.sh, status-*.sh patterns)
   - CDK stack naming patterns (e.g., StageACloudFrontStack, StageBSslCertificateStack, StageCLambdaStack)
   - AWS resource naming conventions (distributions, certificates, Lambda functions, S3 buckets)
   - CDK construct naming patterns and resource identifiers
   - Environment variable naming patterns
   - CDK context parameter naming conventions
   - Output file naming patterns (cdk-outputs.json vs outputs.json)
   - Asset and artifact naming conventions
4. **Structural Pattern Analysis**: The system must evaluate and document:
   - Variable naming patterns and structures across scripts and CDK code
   - Data file structures and JSON schema patterns
   - User interaction patterns and prompts
   - CDK app and stack organization patterns
   - Directory structure conventions
   - Import and dependency patterns in TypeScript files
5. **Resource Identification Patterns**: The system must analyze how resources are:
   - Named and tagged in CDK stacks
   - Referenced between stages
   - Exported from CDK stacks
   - Stored in output files
   - Retrieved and used by subsequent stages
6. **Incremental Improvement**: The system must update the pattern analysis document by comparing multiple files to identify similarities, differences, and consistencies across all file types and naming conventions
7. **Pattern Analysis Completion Gate**: The system must complete the pattern analysis and generate the markdown documentation BEFORE proceeding with any Stage D development work

### React Application Deployment Requirements (ONLY AFTER PATTERN ANALYSIS COMPLETION)

5. **Clean Build Process**: The system must clean any existing Vite build artifacts before creating a fresh build (no caching of build artifacts between deployments)
6. **Compilation**: The system must execute `npm run build` in the apps/hello-world-react directory to generate production-ready static files
7. **Content Deployment**: The system must replace the existing CloudFront distribution content with the compiled React application files
8. **File Structure Preservation**: The system must maintain proper file paths and asset references during deployment
9. **Cache Management**: The system must handle CloudFront cache invalidation to ensure new content is immediately available

### Infrastructure Integration Requirements

10. **CloudFront Update**: The system must update the existing CloudFront distribution in-place without creating new distributions
11. **SSL Preservation**: The system must maintain HTTPS functionality using existing SSL certificates from Stage B
12. **Route53 Preservation**: The system must continue using the same domain names and DNS configuration from Stage B
13. **Data Continuity**: The system must load and utilize outputs from previous stages (stages/a-cloudfront/data/outputs.json, stages/b-ssl/data/outputs.json, stages/c-lambda/data/outputs.json)

### Validation Requirements

14. **Immediate HTTPS Testing**: The system must test React application loading via curl over HTTPS using domain names from Stage B immediately after CloudFront distribution deployment completes
15. **Content Verification**: The system must verify that a unique text identifier from the React application appears in the HTTP response
16. **URL Compatibility**: The system must confirm that all URLs from Stage B continue to work with React content
17. **Asset Loading**: The system must verify that React assets (CSS, JS, images) load correctly through CloudFront

## Non-Goals (Out of Scope)

1. **Performance Optimization**: No bundle size analysis, performance metrics, or optimization requirements
2. **New Infrastructure**: No creation of additional AWS resources beyond what exists from previous stages
3. **API Integration**: No connection to Lambda functions from Stage C (reserved for Stage E)
4. **Advanced React Features**: No complex routing, state management, or advanced React functionality
5. **Custom Domain Changes**: No modifications to domain names or DNS configuration established in Stage B
6. **Certificate Management**: No changes to SSL certificates or certificate validation processes

## Design Considerations

### Pattern Analysis Format
- Use markdown format for human readability
- Structure analysis by category (naming conventions, script patterns, data structures)
- Include examples and counter-examples
- Provide recommendations for Stage D implementation

### React Application
- Use the existing hello-world-react application without modifications
- Maintain Vite build configuration and dependencies
- Preserve all React assets and static files in the build output

### Deployment Strategy
- **PHASE 1: Pattern Analysis** - Complete comprehensive analysis of all previous stages before any development
- **PHASE 2: Development** - Follow the same user interaction patterns from previous stages using insights from pattern analysis
- Use the same AWS profile management approach
- Maintain the same data file structure (inputs.json, discovery.json, outputs.json)
- Implement the same validation and testing patterns

## Technical Considerations

### Dependencies
- Must successfully complete Stages A, B, and C before Stage D execution
- Requires Node.js and npm for React application building
- Requires AWS CLI access with the same profiles used in previous stages
- Must integrate with existing CDK infrastructure code patterns

### File Structure
- Follow the established stages/d-react directory structure with iac/, scripts/, and data/ subdirectories
- Use the same go-d.sh, status-d.sh, undo-d.sh naming convention
- Maintain consistent CDK application structure with previous stages

### Error Handling
- Implement rollback to Stage B HTML content if React deployment fails
- Provide clear error messages following previous stage patterns
- Handle build failures gracefully with appropriate cleanup

## Success Metrics

1. **Pattern Analysis Completion**: Pattern analysis markdown document created with comprehensive analysis of Stages A, B, and C
2. **React Build Success**: Vite build completes successfully with no errors and generates static files
3. **Content Deployment**: React application files successfully replace CloudFront distribution content
4. **HTTPS Validation**: curl commands over HTTPS return React application content with unique text identifier
5. **URL Continuity**: All domain names from Stage B successfully serve React application content
6. **Asset Integrity**: All React assets (CSS, JavaScript, images) load correctly through CloudFront

## Implementation Decisions

Based on requirements clarification, the following decisions have been made:

1. **Pattern Analysis Execution**: Pattern analysis is a prerequisite step that must be completed during PRD development phase, before any Stage D scripts are created. The analysis guides the development team in creating Stage D files and scripts with consistent naming conventions and patterns, but the go-d.sh script itself has no knowledge of or reference to the analysis.

2. **Build Strategy**: Always perform clean builds - no caching of Vite build artifacts between deployments. Each deployment will start with a fresh build process.

3. **Content Backup**: No backup of existing CloudFront content needed since the original Stage A HTML content is already preserved in the repository and can be easily restored if needed.

4. **Validation Timing**: Validate deployment success immediately after CloudFront distribution deployment completes and is ready to serve content.

5. **Pattern Analysis Scope**: Focus on high-level naming conventions and consistency patterns from JSON files and shell scripts. For CDK files, analyze only naming conventions for files and resources created, not deep CDK construct properties or configurations. 