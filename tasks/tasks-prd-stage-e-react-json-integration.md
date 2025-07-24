# Task List: Stage E - React JSON Integration

## Relevant Files

- `stages/e-react-api/iac/app.ts` - CDK application entry point for Stage E infrastructure
- `stages/e-react-api/iac/lib/react-api-stack.ts` - Main CDK stack with CloudFront behavior configuration
- `stages/e-react-api/scripts/gather-inputs.sh` - Collect inputs from all previous stages (A-D)
- `stages/e-react-api/scripts/aws-discovery.sh` - Discover existing AWS resources
- `stages/e-react-api/scripts/deploy-infrastructure.sh` - Deploy CDK stack with CloudFront behaviors
- `stages/e-react-api/scripts/deploy-content.sh` - Build and deploy hello-world-json React app
- `stages/e-react-api/scripts/validate-deployment.sh` - Validate full-stack integration
- `stages/e-react-api/go-e.sh` - Main orchestration script for Stage E
- `stages/e-react-api/data/inputs.json` - Input configuration file
- `stages/e-react-api/data/discovery.json` - AWS resource discovery results
- `stages/e-react-api/data/outputs.json` - Stage E deployment outputs

### Notes

- This stage builds upon all previous stages (A-D) and requires their successful completion
- CloudFront behavior configuration adds API routing without creating new infrastructure
- The hello-world-json React app is pre-built and requires no code modifications
- Use `npm run build` in apps/hello-world-json to create production build
- Test API integration by accessing the deployed app and verifying JSON data display

## Tasks

- [x] 1.0 Copy Stage D Directory and Files to Create Stage E Foundation
  - [x] 1.1 Copy `stages/d-react/iac/` directory to `stages/e-react-api/iac/`
  - [x] 1.2 Copy `stages/d-react/scripts/` directory to `stages/e-react-api/scripts/`
  - [x] 1.3 Copy `stages/d-react/go-d.sh` to `stages/e-react-api/go-e.sh`
  - [x] 1.4 Copy `stages/d-react/data/` structure to `stages/e-react-api/data/`
  - [x] 1.5 Create empty `stages/e-react-api/status-e.sh` script file
- [x] 2.0 Modify CDK Code to Add API Integration Support
  - [x] 2.1 Update `iac/lib/react-stack.ts` filename to `react-api-stack.ts`
  - [x] 2.2 Rename stack class from `ReactStack` to `ReactApiStack`
  - [x] 2.3 Update stack name references to use "StageEReactApiStack"
  - [x] 2.4 Add Lambda Function URL import from Stage C outputs
  - [x] 2.5 Configure CloudFront behavior for `/api/*` path pattern
  - [x] 2.6 Set API behavior precedence to 0 (highest priority)
  - [x] 2.7 Configure API behavior to disable caching (TTL = 0)
  - [x] 2.8 Set API behavior to forward all HTTP methods and headers
  - [x] 2.9 Update `iac/app.ts` to import and use `ReactApiStack`
  - [x] 2.10 Update `package.json` dependencies if needed
- [x] 3.0 Implement Build and Deployment Scripts
  - [x] 3.1 Update `scripts/deploy-infrastructure.sh` to use `apps/hello-world-json`
  - [x] 3.2 Modify build command to run `npm run build` in hello-world-json directory
  - [x] 3.3 Update S3 sync source path to `apps/hello-world-json/dist/`
  - [x] 3.4 Ensure complete S3 content replacement (delete before sync)
  - [x] 3.5 Update CloudFront invalidation to target `/*` pattern
  - [x] 3.6 Update `scripts/gather-inputs.sh` to read from all stages A-D
  - [x] 3.7 Update `scripts/aws-discovery.sh` to discover Lambda Function URL
  - [x] 3.8 Update `scripts/deploy-infrastructure.sh` stack name references
  - [x] 3.9 Update `scripts/validate-deployment.sh` to test API integration
- [x] 4.0 Update Main Execution Script and JSON Data Files
  - [x] 4.1 Update `go-e.sh` script with Stage E specific references
  - [x] 4.2 Change all "Stage D" text references to "Stage E"
  - [x] 4.3 Update script to call `react-api-stack` instead of `react-stack`
  - [x] 4.4 Create `data/inputs.json` with Stage E configuration
  - [x] 4.5 Ensure inputs include Lambda Function ARN from Stage C
  - [x] 4.6 Update validation steps to include API endpoint testing
  - [x] 4.7 Configure outputs to include CloudFront behavior details
- [x] 5.0 Validate Full-Stack Integration and Generate Outputs
  - [x] 5.1 Test React app builds successfully in `apps/hello-world-json`
  - [x] 5.2 Validate CDK stack deploys without errors
  - [x] 5.3 Confirm CloudFront distribution serves React app via HTTPS
  - [x] 5.4 Test `/api` endpoint returns JSON response through CloudFront
  - [x] 5.5 Verify API responses are not cached (different timestamps)
  - [x] 5.6 Validate React app displays API data in browser
  - [x] 5.7 Generate complete `data/outputs.json` with all deployment details
  - [x] 5.8 Test manual browser workflow for UI and API integration 