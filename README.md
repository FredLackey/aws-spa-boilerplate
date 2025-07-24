# AWS SPA Boilerplate

A step-by-step monorepo for provisioning and deploying AWS infrastructure to host Single Page Applications (SPAs) using CloudFront, Lambda, and Route53.

## 🎯 Why Use This Boilerplate?

### The Problem with Traditional AWS Deployment Approaches

Most AWS deployment tutorials and tools follow an "all-at-once" approach that creates multiple problems:

#### **Overwhelming Complexity**
- New AWS users face 10+ services simultaneously (CloudFront, Lambda, Route53, Certificate Manager, S3, IAM, etc.)
- Configuration dependencies are unclear, leading to cryptic error messages
- Debugging requires deep knowledge of how services interact

#### **Deployment Race Conditions**  
- Scripts attempt to create SSL certificates before Route53 validation is ready
- CloudFront distributions reference Lambda functions that don't exist yet
- Certificate attachment fails because validation records aren't propagated

#### **All-or-Nothing Failures**
- When deployment fails, you don't know which specific component caused the issue
- Rollback becomes complex when multiple services are partially configured
- Learning becomes frustrating instead of educational

### 🚀 This Boilerplate's Solution: Progressive Deployment

This repository implements a **staged, sequential approach** that eliminates these problems:

#### **🔍 Isolated Learning & Validation**
- **Stage A**: Validate CloudFront works independently with simple HTML
- **Stage B**: Add SSL certificates and DNS without touching the application
- **Stage C**: Deploy Lambda API separately and test in isolation  
- **Stage D**: Upgrade to React SPA once foundation is proven
- **Stage E**: Connect everything together with confidence

#### **🛡️ Risk Mitigation Through Incremental Progress**
- Each stage has **clear success criteria** - you know exactly what's working
- **Precise error isolation** - failures point to specific components
- **Tested rollback procedures** for each stage independently
- **Configuration persistence** - previous stage outputs feed subsequent stages

#### **📚 Production-Ready Learning Path**
- Learn AWS services **one at a time** with practical examples
- Understand **real-world integration patterns** used by professional teams
- **Immediately usable infrastructure** - just replace demo apps with your code
- **Best practices baked in** - proper CORS, security headers, resource naming

#### **⚡ Automation Without Lock-in**
- **Human-readable bash scripts** - understand and modify every step
- **JSON configuration files** - easy to integrate with CI/CD pipelines
- **AWS CDK infrastructure** - professional Infrastructure as Code approach
- **No vendor lock-in** - standard AWS resources you can manage independently

## 📈 What You Get vs. Alternatives

| Approach | Learning Curve | Time to Working System | Debugging Difficulty | Production Ready |
|----------|----------------|------------------------|----------------------|------------------|
| **AWS Console Manually** | Steep | Hours-Days | Very Hard | Maybe |
| **Terraform/CDK All-at-Once** | Very Steep | Days-Weeks | Hard | Yes |
| **This Boilerplate** | **Gentle** | **30-60 minutes** | **Easy** | **Yes** |

## 🎯 Perfect For

- **AWS beginners** who want to learn without drowning in complexity
- **Experienced developers** who need a proven SPA hosting foundation quickly
- **Teams** establishing standardized deployment patterns
- **Educational environments** teaching modern serverless architecture
- **Anyone** tired of AWS deployment tutorials that don't actually work

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

## Technology Stack

This boilerplate uses modern infrastructure-as-code and deployment tools:

- **Infrastructure as Code**: AWS CDK (Cloud Development Kit) for all AWS resource provisioning
- **Deployment Automation**: Bash scripts for orchestration and user interaction
- **AWS Services**: CloudFront, Lambda, Route53, Certificate Manager, S3
- **Application Technologies**: HTML, CSS, React with Vite, Node.js
- **Configuration Management**: CDK context and environment variables for environment-specific settings

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

## 🚀 Deployment Stages

The deployment process is broken into 5 progressive stages, each building upon the previous ones. See [STAGES.md](./STAGES.md) for detailed stage-by-stage instructions.

### Stage A: CloudFront Distribution Foundation
**Goal**: Establish basic content delivery capability
**What it does**: Deploys the Hello World HTML app to a new CloudFront distribution
**Why it matters**: Proves CloudFront can serve content before adding complexity
**Success criteria**: Static HTML page loads via CloudFront URL
**Time required**: ~10 minutes
**Key learning**: How CloudFront distributions work and how to deploy static content

### Stage B: SSL Certificate & DNS
**Goal**: Add security and custom domain access  
**What it does**: Creates SSL certificates, configures Route53 DNS, enables HTTPS
**Why it matters**: Makes your site production-ready with proper security and branding
**Success criteria**: Same content now loads via HTTPS on your custom domain
**Time required**: ~15 minutes (plus DNS propagation)
**Key learning**: How SSL certificate validation works with Route53

### Stage C: Serverless API Backend
**Goal**: Add programmable server-side functionality
**What it does**: Deploys the Hello World Lambda function and makes it accessible via API Gateway
**Why it matters**: Establishes the backend API capability your SPA will eventually need
**Success criteria**: Lambda function returns JSON data when invoked via AWS CLI
**Time required**: ~10 minutes  
**Key learning**: How Lambda functions work and integrate with CloudFront

### Stage D: Modern SPA Frontend
**Goal**: Upgrade to a production-ready frontend framework
**What it does**: Replaces static HTML with the Hello World React application
**Why it matters**: Demonstrates how modern JavaScript SPAs are served through CloudFront
**Success criteria**: React app loads and displays properly via HTTPS
**Time required**: ~10 minutes
**Key learning**: How React apps are built and deployed to CloudFront

### Stage E: Full-Stack Integration  
**Goal**: Connect frontend and backend for complete application functionality
**What it does**: Deploys the Hello World JSON app that calls the Lambda API and displays results
**Why it matters**: Proves the complete architecture works end-to-end
**Success criteria**: React app successfully calls Lambda API and displays real-time data  
**Time required**: ~15 minutes
**Key learning**: How CloudFront behaviors route API calls to Lambda while serving SPA assets

**Total time investment**: 60-75 minutes for complete, production-ready AWS infrastructure

## Prerequisites

Before starting the deployment process, ensure you have the following tools and information ready:

### Technical Requirements
- **AWS CLI** installed and configured with appropriate profiles
- **Node.js and npm** (for React applications)
- **Domain name configured in Route53** (for SSL stages)

### Required Information to Gather

#### 🔑 AWS Profiles
You'll need **one or two AWS CLI profiles** depending on your account structure:

- **Single Account Setup**: One profile with permissions for all AWS services
- **Multi-Account Setup**: 
  - **Infrastructure Profile**: Access to the account managing Route53 and certificates
  - **Target Profile**: Access to the account where CloudFront and Lambda will be deployed

*Example profile names: `my-company-infra`, `my-company-sandbox`*

#### 🌐 Domain Information
Prepare a list of **Fully Qualified Domain Names (FQDNs)** you want to use:

- Primary domain: `example.com`
- WWW subdomain: `www.example.com` 
- Environment subdomains: `dev.example.com`, `staging.example.com`

*Note: These domains must already be configured in Route53 before starting Stage B*

#### 🏗️ Infrastructure Details
From your target AWS account, gather:

- **VPC ID**: The Virtual Private Cloud where resources will be deployed
  - Example: `vpc-0123456789abcdef0`
  - Find this in AWS Console: VPC → Your VPCs
- **AWS Region**: Where you want to deploy resources
  - Example: `us-east-1`, `us-west-2`

#### 📋 Information Usage by Stage
- **Stage A**: Uses AWS profiles, VPC ID, and region to establish CloudFront foundation
- **Stage B**: Uses infrastructure profile and domain names to configure SSL certificates and DNS
- **Stages C-E**: Use configuration from previous stages automatically

### 💡 Pro Tip
Gather all this information before running any deployment scripts. The staged approach will prompt you for these details when needed, but having them ready will make the process smooth and uninterrupted.

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
├── stages/
│   ├── a-cloudfront/          # Stage A deployment
│   ├── b-ssl/                 # Stage B deployment
│   ├── c-lambda/              # Stage C deployment
│   ├── d-react/               # Stage D deployment
│   └── e-react-api/           # Stage E deployment
├── STAGES.md                  # Detailed deployment guide
└── README.md                  # This file
```

## Stages Directory Structure

The `/stages` folder contains the deployment automation for each stage. Each stage follows a consistent structure:

```
stages/
├── a-cloudfront/
│   ├── go-a.sh               # Main deployment script for Stage A
│   ├── iac/                  # AWS CDK infrastructure code
│   ├── scripts/              # Helper scripts and utilities
│   └── data/                 # Stage data management
│       ├── inputs.json       # User-provided information
│       ├── discovery.json    # AWS account interrogation results
│       └── outputs.json      # Stage deployment results
├── b-ssl/
│   ├── go-b.sh               # Main deployment script for Stage B
│   ├── iac/                  # AWS CDK infrastructure code
│   ├── scripts/              # Helper scripts and utilities
│   └── data/                 # Stage data management
│       ├── inputs.json       # User-provided information
│       ├── discovery.json    # AWS account interrogation results
│       └── outputs.json      # Stage deployment results
├── c-lambda/
│   ├── go-c.sh               # Main deployment script for Stage C
│   ├── iac/                  # AWS CDK infrastructure code
│   ├── scripts/              # Helper scripts and utilities
│   └── data/                 # Stage data management
│       ├── inputs.json       # User-provided information
│       ├── discovery.json    # AWS account interrogation results
│       └── outputs.json      # Stage deployment results
├── d-react/
│   ├── go-d.sh               # Main deployment script for Stage D
│   ├── iac/                  # AWS CDK infrastructure code
│   ├── scripts/              # Helper scripts and utilities
│   └── data/                 # Stage data management
│       ├── inputs.json       # User-provided information
│       ├── discovery.json    # AWS account interrogation results
│       └── outputs.json      # Stage deployment results
└── e-react-api/
    ├── go-e.sh               # Main deployment script for Stage E
    ├── iac/                  # AWS CDK infrastructure code
    ├── scripts/              # Helper scripts and utilities
    └── data/                 # Stage data management
        ├── inputs.json       # User-provided information
        ├── discovery.json    # AWS account interrogation results
        └── outputs.json      # Stage deployment results
```

### Stage Components

Each stage directory contains four key components:

#### 1. Main Deployment Script (`go-{stage}.sh`)
The primary entry point for each stage deployment with specific responsibilities:

**User Interaction & Information Gathering**:
- Prompts for required information (AWS profiles, domain names, account IDs, etc.)
- Captures AWS profile to use for all subsequent operations
- Validates user inputs and prerequisites from previous stages

**AWS Discovery & Data Collection**:
- Performs AWS CLI lookups to discover existing resources
- Gathers account-specific information needed for deployment
- Retrieves outputs from previous stages for dependency management

**Data Management and CDK Configuration**:
- Saves user inputs to `data/inputs.json` file for persistence and reuse
- Stores AWS discovery results in `data/discovery.json` file for reference
- Creates CDK context files combining inputs, discovery data, and previous stage outputs
- Sets environment variables and context values for CDK deployment

**Deployment Orchestration**:
- Executes CDK commands with appropriate AWS profile and configuration
- Coordinates infrastructure deployment with application deployment
- Handles error conditions and rollback scenarios

**Output Generation**: 
- Captures CDK stack outputs and deployment results in `data/outputs.json` file
- Creates structured JSON data for subsequent stages
- Stores resource identifiers, URLs, and configuration details
- Validates successful deployment before completion

#### 2. Infrastructure as Code (`iac/` folder)
Contains AWS CDK applications and constructs:
- **Stack Definitions**: AWS resources specific to each stage defined in code
- **Context Management**: Input parameters and configuration through CDK context
- **State Management**: CDK metadata and CloudFormation stack state
- **Output Exports**: Infrastructure details exported from CDK stacks for other stages

#### 3. Helper Scripts (`scripts/` folder)
Utility scripts for stage-specific operations:
- **Build Scripts**: Application compilation and packaging
- **Deployment Utilities**: File uploads, cache invalidation, etc.
- **Configuration Helpers**: Environment setup and validation
- **Testing Scripts**: Automated verification of stage completion

#### 4. Data Management (`data/` folder)
Structured JSON data storage for stage lifecycle management:

**Inputs File** (`data/inputs.json`):
- Stores all user-provided information from prompts in JSON format
- Contains AWS profiles, account IDs, domain names, and configuration values
- Serves as the single source of truth for user-specified parameters
- Used by CDK and helper scripts for consistent configuration

**Discovery File** (`data/discovery.json`):
- Contains results from AWS account interrogation and resource discovery in JSON format
- Stores existing infrastructure details, account information, and region data
- Captures dependency information from previous stages
- Provides context for deployment decisions and resource naming

**Outputs File** (`data/outputs.json`):
- Records deployment results and created resource identifiers in JSON format
- Contains CDK stack outputs, resource ARNs, URLs, and configuration details
- Stores values needed by subsequent stages for dependency management
- Enables stage validation and rollback operations

### Deployment Workflow

1. **Execute Stage Script**: Run `./go-{stage}.sh` from the appropriate stage directory
2. **AWS Profile Setup**: Provide AWS CLI profile for account access
3. **Information Gathering & Data Management**: 
   - Answer prompts for required inputs (domain names, account IDs, etc.) → saved to `data/inputs.json`
   - Script discovers existing AWS resources and account information → saved to `data/discovery.json`
   - Previous stage outputs are loaded from `data/outputs.json` files for dependencies
4. **CDK Configuration**: Script sets CDK context and environment variables using data files
5. **Infrastructure Deployment**: CDK provisions AWS resources using the configured context
6. **Application Deployment**: Helper scripts deploy applications and content
7. **Validation & Testing**: Automated verification of stage completion
8. **Output Generation**: Results saved to `data/outputs.json` file for subsequent stages

### AWS Profile Management

Each stage requires an AWS CLI profile to be specified for:
- **Resource Discovery**: Looking up existing infrastructure and account details
- **CDK Deployment**: Provisioning new resources with appropriate permissions
- **Application Deployment**: Uploading content and configuring services
- **Validation Testing**: Verifying deployment success and functionality

The go scripts handle profile management consistently across all stages, ensuring proper AWS authentication and authorization throughout the deployment process.

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

This project is licensed under the Apache License 2.0. See [LICENSE](./LICENSE) for details.

## 📞 Need Help?

This boilerplate was created by **Fred Lackey** to help developers successfully deploy SPAs on AWS without the typical frustrations and complexity.

If you run into issues, have questions, or need assistance adapting this for your specific use case, please don't hesitate to reach out:

- **Email**: [fred.lackey@gmail.com](mailto:fred.lackey@gmail.com)
- **GitHub**: [@fredlackey](https://github.com/fredlackey)
- **LinkedIn**: [Fred Lackey](https://www.linkedin.com/in/fredlackey/)

I'm always happy to help fellow developers succeed with AWS deployments. Whether you're stuck on a particular stage, need guidance customizing the infrastructure for your project, or want to discuss best practices, feel free to get in touch!
