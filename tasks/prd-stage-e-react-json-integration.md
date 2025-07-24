# Product Requirements Document: Stage E - React JSON Integration

## Introduction/Overview

Stage E represents the final stage of the AWS SPA Boilerplate deployment pipeline. This stage builds upon all previous stages (A-D) to deliver a complete full-stack application by deploying the `hello-world-json` React application and adding CloudFront behaviors to route API calls to the Lambda function created in Stage C.

**Problem Statement**: Stage D deployed a static React application, but modern SPAs require API integration. Stage E solves this by creating a unified distribution that serves both static React content and dynamic API responses through a single domain, eliminating CORS issues and providing a production-ready full-stack deployment pattern.

**Goal**: Deploy the `hello-world-json` React application to CloudFront with custom behaviors that route `/api` requests to the Lambda function from Stage C, creating a complete full-stack Single Page Application hosted on AWS.

## Goals

1. **Replace Static Content**: Completely replace the Stage D React content with the `hello-world-json` application build
2. **Enable API Integration**: Configure CloudFront behaviors to route `/api/*` requests to the Stage C Lambda function
3. **Maintain Zero-Cache API**: Ensure API responses are never cached by CloudFront for dynamic content
4. **Preserve HTTPS Access**: Maintain all SSL/TLS and domain configurations from previous stages
5. **Validate Full-Stack Integration**: Confirm the React app can successfully call the Lambda API through CloudFront
6. **Generate Stage Outputs**: Provide JSON outputs for future automation and validation

## User Stories

**As a developer completing the AWS SPA Boilerplate**, I want to deploy a full-stack React application so that I can see how SPAs and APIs work together in a production AWS environment.

**As a junior developer following this tutorial**, I want clear evidence that my API integration is working so that I can understand the complete request flow from React → CloudFront → Lambda.

**As a DevOps engineer**, I want the CloudFront distribution to handle both static content and API routing so that I can avoid CORS issues and maintain a single domain for the entire application.

**As a system administrator**, I want API responses to never be cached so that dynamic content always reflects the current server state.

## Functional Requirements

1. **React Application Deployment**
   1.1. The system must build the `apps/hello-world-json` React application using Vite
   1.2. The system must completely replace all content in the CloudFront distribution from Stage D
   1.3. The build output must be uploaded to the S3 bucket configured in Stage A
   1.4. The system must invalidate the CloudFront cache to ensure new content is served immediately

2. **CloudFront Behavior Configuration**  
   2.1. The system must create a new CloudFront behavior for the `/api/*` path pattern
   2.2. The `/api/*` behavior must route requests to the Lambda Function URL from Stage C
   2.3. The `/api/*` behavior must have caching disabled (TTL = 0)
   2.4. The `/api/*` behavior must have higher precedence than the default behavior
   2.5. The `/api/*` behavior must forward all HTTP methods (GET, POST, OPTIONS) to the Lambda function
   2.6. The `/api/*` behavior must forward all headers and query parameters to the Lambda function

3. **Lambda Integration**
   3.1. The system must use the Lambda Function ARN from Stage C outputs
   3.2. The system must preserve all CORS headers configured in the Lambda function
   3.3. The system must handle both `/api` and `/api/*` request patterns
   3.4. The Lambda function must continue to return JSON responses with current timestamp

4. **Infrastructure Management**
   4.1. The system must import existing resources from Stages A, B, C, and D
   4.2. The system must not create new S3 buckets or CloudFront distributions
   4.3. The system must update the existing CloudFront distribution configuration
   4.4. The system must maintain all SSL certificates and domain configurations from Stage B

5. **Data Management**
   5.1. The system must read inputs from `data/inputs.json` and previous stage outputs
   5.2. The system must perform AWS resource discovery and save to `data/discovery.json`  
   5.3. The system must save deployment results to `data/outputs.json`
   5.4. The system must include CloudFront behavior configuration in outputs

6. **Validation and Testing**
   6.1. The system must validate successful React application deployment via HTTPS
   6.2. The system must validate API functionality by calling the `/api` endpoint
   6.3. The system must provide manual browser testing instructions for UI validation
   6.4. The system must confirm the React app can fetch and display JSON data from the API

## Non-Goals (Out of Scope)

- **New Infrastructure Creation**: Stage E will not create new CloudFront distributions, S3 buckets, or Lambda functions
- **React Application Modifications**: The `hello-world-json` app is already prepared and requires no code changes
- **Lambda Function Changes**: The Stage C Lambda function requires no modifications for this integration
- **SSL Certificate Management**: All certificate and domain configurations remain unchanged from Stage B
- **Performance Optimization**: This stage focuses on functionality, not performance tuning
- **Error Handling in React**: The React app already includes comprehensive error handling
- **Multi-Region Deployment**: Stage E maintains single-region deployment pattern from previous stages

## Technical Considerations

**CDK Stack Requirements**:
- The Stack must extend the ReactStack pattern from Stage D with additional CloudFront behavior configuration
- Lambda Function ARN must be imported from Stage C outputs
- CloudFront distribution must be modified, not replaced
- All existing infrastructure must be imported using CDK import mechanisms

**CloudFront Behavior Priority**:
- The `/api/*` behavior must have a precedence value higher than the default behavior (lower numeric value)
- Cache policies for API behavior must be set to disable all caching
- Origin configuration must point to the Lambda Function URL from Stage C

**Build Process Integration**:
- Must use the same Vite build process as Stage D
- Build output location: `apps/hello-world-json/dist/`
- S3 sync must replace all existing content completely
- CloudFront invalidation must target `/*` to clear all cached content

**Dependency Requirements**:
- Requires successful completion of Stages A, B, C, and D
- Must read outputs from all previous stages' `data/outputs.json` files
- AWS CLI profile must have permissions for CloudFront, S3, and Lambda resource access

## Success Metrics

1. **Deployment Success**: CloudFront distribution successfully updated with new behaviors
2. **Build Success**: `hello-world-json` React app builds without errors and deploys to S3
3. **API Connectivity**: `/api` endpoint returns JSON response with current timestamp via CloudFront
4. **HTTPS Access**: Application accessible via the configured primary domain with valid SSL
5. **UI Integration**: React app successfully displays API data in the browser interface
6. **Cache Validation**: API responses are not cached (verified by multiple requests returning different timestamps)
7. **Output Generation**: All deployment details saved to `data/outputs.json` for automation

## Design Considerations

**CloudFront Behavior Configuration**:
```
Default Behavior: 
  - Path: /*
  - Origin: S3 Bucket (Stage A)
  - Cache: Enabled

API Behavior:
  - Path: /api/*
  - Origin: Lambda Function URL (Stage C)  
  - Precedence: 0 (highest)
  - Cache: Disabled
  - Methods: GET, POST, OPTIONS
```

**React App Integration**:
- The app uses `fetch('/api')` which will be routed through CloudFront to Lambda
- Error handling and loading states are already implemented
- JSON response display is pre-configured with monospace formatting

**S3 Content Replacement**:
- All files from Stage D build must be removed before uploading Stage E build
- Build assets maintain the same structure: `index.html`, CSS, JS, and asset files
- CloudFront invalidation ensures immediate content refresh

## Implementation Strategy

**Starting Point - Clone Stage D Foundation**:
Stage E implementation should begin by cloning the entire Stage D structure as the foundation:
- Copy `stages/d-react/iac/` directory to `stages/e-react-api/iac/` 
- Copy `stages/d-react/scripts/` directory to `stages/e-react-api/scripts/`
- Copy `stages/d-react/go-d.sh` to `stages/e-react-api/go-e.sh`
- Copy `stages/d-react/data/` structure to `stages/e-react-api/data/`

**Modification Areas**:
After cloning, modify the following components:
1. **CDK Stack**: Add CloudFront behavior configuration for `/api/*` routing
2. **Build Scripts**: Update to use `apps/hello-world-json` instead of `apps/hello-world-react`
3. **Go Script**: Update stage references and add Lambda Function URL discovery
4. **Stack Naming**: Update all stack names and resource IDs to reflect Stage E

## Resolved Design Decisions

**Rollback Strategy**: 
- If new resources are created during deployment, remove only the new resources and revert to Stage D state
- Rollback approach depends on the specific failure point during deployment
- Preserve existing infrastructure when possible, only roll back failed components

**Cache Configuration**:
- API routes (`/api/*`) will have zero caching (TTL = 0) 
- No additional cache headers needed from Lambda function beyond existing CORS headers
- Default CloudFront behavior maintains existing cache settings (likely 30-day cache)
- Lambda function responses are inherently dynamic and should never be cached

**Monitoring Requirements**:
- No additional CloudWatch monitoring or metrics required for Stage E
- Basic error logging from Lambda function and CloudFront is sufficient
- Standard AWS service logging covers operational needs

**API Versioning**:
- Out of scope for current implementation
- Future API versions will be handled through CI/CD deployment processes
- CloudFront behavior configuration remains simple (`/api/*` pattern)

---

**Target Implementation**: `stages/e-react-api/`
**Dependencies**: Stages A, B, C, D (all outputs required)
**Estimated Complexity**: Medium (builds on existing patterns with CloudFront behavior addition)
**Primary Validation**: Browser-based UI testing with visible API data display 