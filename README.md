# AWS SPA Boilerplate

A step-by-step monorepo for provisioning and deploying AWS infrastructure to host Single Page Applications (SPAs) using CloudFront, Lambda, and Route53.

## Overview

This monorepo provides a series of scripts and static content that allows you to provision the necessary AWS infrastructure step by step without requiring custom code. Each stage builds upon the previous one, demonstrating different aspects of AWS hosting for modern web applications.

## Problem Statement

When developers begin working on Single Page Applications targeting serverless technologies in AWS, they commonly attempt to build and deploy everything simultaneously. This "all-at-once" approach creates several critical issues:

### Common Deployment Problems
- **Race Conditions**: Scripts attempt to deploy interdependent resources before their dependencies exist
- **Deployment Failures**: CloudFront distributions referencing non-existent Lambda functions
- **Certificate Issues**: SSL certificates being applied before Route53 validation is complete
- **Configuration Complexity**: Managing multiple AWS services without understanding their interaction patterns
- **Debugging Difficulties**: When everything fails together, it's hard to isolate which component caused the issue

### Sequential Deployment Solution

This repository solves these problems by implementing a **staged, sequential deployment approach**:

1. **Isolated Component Testing**: Each stage validates one specific piece of the architecture
2. **Dependency Management**: Later stages only deploy after earlier dependencies are confirmed working
3. **Clear Error Isolation**: If a stage fails, you know exactly which component needs attention
4. **Production-Ready Patterns**: Each stage demonstrates real-world deployment scenarios
5. **Incremental Learning**: Developers understand how each AWS service works before adding complexity

### End Goal

After completing all stages, developers will have:
- **Fully Provisioned Infrastructure**: CloudFront, Lambda, Route53, and certificates all working together
- **Validated Deployment Patterns**: Proven scripts and configurations for each component
- **Ready-to-Use Foundation**: Simply replace Lambda code and CloudFront content for your actual application
- **Deep Understanding**: Knowledge of how each AWS service integrates with the others

The final result is a production-ready hosting environment where you only need to:
1. Replace the Lambda function contents with your API code
2. Replace the CloudFront distribution contents with your actual SPA build

## Architecture

The boilerplate demonstrates a complete AWS-based SPA hosting solution:

- **CloudFront Distribution** - Content delivery network for static assets
- **Route53** - DNS management and domain routing
- **AWS Certificate Manager** - SSL/TLS certificates for HTTPS
- **Lambda Functions** - Serverless API endpoints
- **S3 (implicit)** - Static file storage behind CloudFront

## Applications

This monorepo contains four progressive applications that demonstrate different deployment scenarios:

### A. Hello World HTML (`apps/hello-world-html/`)
A basic static HTML page that serves as the foundation for testing CloudFront distribution functionality. This proves that the CDN is working without any dependencies on certificates, APIs, or complex build processes.

**Purpose**: Validate basic CloudFront distribution setup

### B. Hello World React (`apps/hello-world-react/`)
A simple React application built with Vite that demonstrates serving a static SPA through CloudFront. This ensures that modern JavaScript applications can be properly served with correct routing and asset handling.

**Purpose**: Validate CloudFront distribution for React SPAs

### C. Hello World Lambda (`apps/hello-world-lambda/`)
An extremely simple Node.js Lambda function that returns a JSON response containing the current server timestamp. This minimal API endpoint validates that Lambda deployment and invocation are working correctly.

**Purpose**: Validate Lambda function deployment and API functionality

### D. Hello World JSON (`apps/hello-world-json/`)
A React application that consumes the Lambda API from application C, demonstrating full-stack connectivity. This app uses CloudFront behaviors to route API calls to Lambda while serving the React app from the same domain.

**Purpose**: Validate end-to-end SPA + API integration through CloudFront

## Deployment Stages

The deployment process is broken into 5 progressive stages, each building upon the previous ones. See [STAGES.md](./STAGES.md) for detailed stage-by-stage instructions.

### Stage A: CloudFront Distribution
Deploy the Hello World HTML app to establish basic CloudFront functionality.

### Stage B: SSL Certificate
Add SSL/TLS certificates and Route53 DNS configuration for HTTPS access.

### Stage C: Lambda API
Deploy the Hello World Lambda function to establish serverless API capability.

### Stage D: React SPA
Replace the HTML app with the Hello World React application.

### Stage E: Full-Stack Integration
Deploy the Hello World JSON app that demonstrates complete SPA + API integration.

## Prerequisites

- AWS CLI configured with appropriate profiles
- Node.js and npm (for React applications)
- Domain name configured in Route53 (for SSL stages)

## Getting Started

1. Clone this repository
2. Review the [STAGES.md](./STAGES.md) file for detailed deployment instructions
3. Start with Stage A and proceed sequentially through each stage
4. Each stage outputs configuration details needed for subsequent stages

## Project Structure

```
aws-spa-boilerplate/
├── apps/
│   ├── hello-world-html/      # Stage A: Basic HTML validation
│   ├── hello-world-react/     # Stage D: React SPA deployment  
│   ├── hello-world-lambda/    # Stage C: Serverless API
│   └── hello-world-json/      # Stage E: Full-stack integration
├── STAGES.md                  # Detailed deployment guide
└── README.md                  # This file
```

## Key Features

- **Progressive Deployment**: Each stage validates a specific aspect of the architecture
- **No Custom Code Required**: All applications are simple demonstrations
- **Infrastructure as Code Ready**: Outputs JSON configuration for automation
- **Production-Ready Patterns**: Demonstrates real-world AWS hosting scenarios
- **Cost-Effective**: Uses serverless and CDN services to minimize ongoing costs

## Output and Configuration

Each deployment stage generates JSON output containing configuration details needed for subsequent stages. This approach enables:

- Automated deployment pipelines
- Environment-specific configurations
- Infrastructure state tracking
- Easy rollback and troubleshooting

## Testing

Each stage includes specific testing instructions to validate functionality:

- **HTTP/HTTPS connectivity** tests using curl
- **API functionality** tests using AWS CLI
- **End-to-end integration** tests for full-stack scenarios

## Contributing

This boilerplate is designed to be a learning tool and foundation for AWS SPA deployments. Feel free to extend it with additional stages or modify the applications for your specific needs.

## License

See [LICENSE](./LICENSE) for details.
