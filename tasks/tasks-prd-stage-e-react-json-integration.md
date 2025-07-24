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

- [ ] 1.0 Copy Stage D Directory and Files to Create Stage E Foundation
  - [ ] 1.1 Copy `stages/d-react/iac/` directory to `stages/e-react-api/iac/`
  - [ ] 1.2 Copy `stages/d-react/scripts/` directory to `stages/e-react-api/scripts/`
  - [ ] 1.3 Copy `stages/d-react/go-d.sh` to `stages/e-react-api/go-e.sh`
  - [ ] 1.4 Copy `stages/d-react/data/` structure to `stages/e-react-api/data/`
  - [ ] 1.5 Create empty `stages/e-react-api/status-e.sh` script file
- [ ] 2.0 Modify CDK Code to Add API Integration Support
  - [ ] 2.1 Update `iac/lib/react-stack.ts` filename to `react-api-stack.ts`
  - [ ] 2.2 Rename stack class from `ReactStack` to `ReactApiStack`
  - [ ] 2.3 Update stack name references to use "StagEReactApiStack"
  - [ ] 2.4 Add Lambda Function URL import from Stage C outputs
  - [ ] 2.5 Configure CloudFront behavior for `/api/*` path pattern
  - [ ] 2.6 Set API behavior precedence to 0 (highest priority)
  - [ ] 2.7 Configure API behavior to disable caching (TTL = 0)
  - [ ] 2.8 Set API behavior to forward all HTTP methods and headers
  - [ ] 2.9 Update `iac/app.ts` to import and use `ReactApiStack`
  - [ ] 2.10 Update `package.json` dependencies if needed
- [ ] 3.0 Implement Build and Deployment Scripts
  - [ ] 3.1 Update `scripts/deploy-content.sh` to use `apps/hello-world-json`
  - [ ] 3.2 Modify build command to run `npm run build` in hello-world-json directory
  - [ ] 3.3 Update S3 sync source path to `apps/hello-world-json/dist/`
  - [ ] 3.4 Ensure complete S3 content replacement (delete before sync)
  - [ ] 3.5 Update CloudFront invalidation to target `/*` pattern
  - [ ] 3.6 Update `scripts/gather-inputs.sh` to read from all stages A-D
  - [ ] 3.7 Update `scripts/aws-discovery.sh` to discover Lambda Function URL
  - [ ] 3.8 Update `scripts/deploy-infrastructure.sh` stack name references
  - [ ] 3.9 Update `scripts/validate-deployment.sh` to test API integration
- [ ] 4.0 Update Main Execution Script and JSON Data Files
  - [ ] 4.1 Update `go-e.sh` script with Stage E specific references
  - [ ] 4.2 Change all "Stage D" text references to "Stage E"
  - [ ] 4.3 Update script to call `react-api-stack` instead of `react-stack`
  - [ ] 4.4 Create `data/inputs.json` with Stage E configuration
  - [ ] 4.5 Ensure inputs include Lambda Function ARN from Stage C
  - [ ] 4.6 Update validation steps to include API endpoint testing
  - [ ] 4.7 Configure outputs to include CloudFront behavior details
- [ ] 5.0 Validate Full-Stack Integration and Generate Outputs
  - [ ] 5.1 Test React app builds successfully in `apps/hello-world-json`
  - [ ] 5.2 Validate CDK stack deploys without errors
  - [ ] 5.3 Confirm CloudFront distribution serves React app via HTTPS
  - [ ] 5.4 Test `/api` endpoint returns JSON response through CloudFront
  - [ ] 5.5 Verify API responses are not cached (different timestamps)
  - [ ] 5.6 Validate React app displays API data in browser
  - [ ] 5.7 Generate complete `data/outputs.json` with all deployment details
  - [ ] 5.8 Test manual browser workflow for UI and API integration 