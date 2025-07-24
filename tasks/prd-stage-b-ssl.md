# Product Requirements Document: Stage B SSL Certificate Deployment

## Introduction/Overview

Stage B builds upon Stage A's CloudFront distribution by adding SSL/TLS certificate management and Route53 DNS configuration. This stage enables HTTPS access to the application by provisioning SSL certificates through AWS Certificate Manager, configuring DNS validation records in Route53, and attaching the certificate to the existing CloudFront distribution.

**Problem**: Stage A provides HTTP access through CloudFront's default domain, but production applications require HTTPS access through custom domain names with valid SSL certificates.

**Goal**: Enable HTTPS access to the CloudFront distribution using custom fully qualified domain names (FQDNs) with AWS-managed SSL certificates validated through DNS.

**Testing Domains**: This stage will be tested using two specific FQDNs:
- `www.sbx.briskhaven.com`
- `sbx.briskhaven.com`

Both domains will be covered by a single SSL certificate and configured as alternate domain names on the CloudFront distribution.

## Goals

1. **SSL Certificate Provisioning**: Create SSL certificates in AWS Certificate Manager for one or more custom domains
2. **DNS Validation**: Configure Route53 DNS records to validate SSL certificate ownership
3. **CloudFront Integration**: Attach the validated SSL certificate to the existing CloudFront distribution from Stage A
4. **Multi-Domain Support**: Support single domain or multiple domains (no wildcards) based on user input
5. **Cross-Account Operation**: Manage Route53 resources in the infrastructure account while updating CloudFront in the target account
6. **HTTPS Validation**: Confirm HTTPS connectivity works correctly for all configured domains

## User Stories

**As a developer**, I want to add SSL certificates to my CloudFront distribution so that users can access my application securely over HTTPS using custom domains like `www.sbx.briskhaven.com` and `sbx.briskhaven.com`.

**As a DevOps engineer**, I want to manage SSL certificates across multiple AWS accounts so that I can maintain separation between infrastructure and application resources while supporting both apex and www subdomain configurations.

**As a system administrator**, I want to configure multiple domain names (`www.sbx.briskhaven.com` and `sbx.briskhaven.com`) for the same application so that I can support different environments or branding requirements.

**As a security professional**, I want DNS validation for SSL certificates so that I can prove domain ownership without email-based validation.

**As a deployment engineer**, I want to reuse the CloudFront distribution from Stage A so that I can add SSL functionality without recreating existing infrastructure.

## Functional Requirements

### Input Collection and Validation
1. The system must accept multiple `-d` (domain) parameters via command line arguments to specify fully qualified domain names (FQDNs)
2. The system must require at least one domain parameter and support unlimited additional domains
3. The system must validate that all provided domains follow proper FQDN format
4. **Testing Example**: The system will be tested with `-d www.sbx.briskhaven.com -d sbx.briskhaven.com` to validate multi-domain certificate creation
5. The system must load Stage A output data from `stages/a-cloudfront/data/outputs.json` to obtain CloudFront distribution details
6. The system must validate that Stage A completed successfully before proceeding (`readyForStageB: true`)

### AWS Account and Profile Management  
7. The system must use the infrastructure AWS profile (from Stage A data) to manage Route53 and Certificate Manager resources
8. The system must use the target AWS profile (from Stage A data) to update CloudFront distribution settings
9. The system must validate credentials for both AWS profiles before beginning deployment
10. The system must capture and store both infrastructure and target account IDs for cross-account operations

### Route53 Zone Discovery and Management
11. The system must discover existing Route53 hosted zones in the infrastructure account for each provided domain
12. The system must validate that hosted zones exist for all top-level domains before proceeding with certificate creation
13. The system must fail with a clear error message if any required hosted zone does not exist (no zone creation)
14. The system must create DNS validation records in the existing Route53 hosted zones
15. The system must handle subdomains by finding the appropriate parent hosted zone that already exists
16. **Testing Example**: The system must locate the `briskhaven.com` hosted zone for both `www.sbx.briskhaven.com` and `sbx.briskhaven.com` domains

### SSL Certificate Management
17. The system must create a single SSL certificate in AWS Certificate Manager that covers all provided domains
18. The system must use DNS validation method for certificate validation (not email validation)
19. The system must wait for certificate validation to complete before proceeding to CloudFront attachment
20. The system must handle certificate validation timeouts gracefully with appropriate error messages
21. The system must detect and report AWS Certificate Manager limit errors (e.g., certificate count limits) without attempting to validate limits proactively
22. **Testing Example**: The system must create a single certificate covering both `www.sbx.briskhaven.com` and `sbx.briskhaven.com`

### CloudFront Distribution Updates
23. The system must check for existing SSL certificates that match the exact set of provided domains and reuse them if found
24. The system must sort domain names alphabetically for consistent certificate identification and creation
25. The system must attach the validated SSL certificate to the existing CloudFront distribution from Stage A
26. The system must configure the CloudFront distribution to accept HTTPS traffic on the custom domains
27. The system must add all provided domains as alternate domain names (CNAMEs) to the CloudFront distribution
28. The system must configure CloudFront behaviors to require SSL/HTTPS after certificate attachment
29. The system must handle CloudFront distribution update propagation delays
30. **Testing Example**: The system must add both `sbx.briskhaven.com` and `www.sbx.briskhaven.com` (alphabetically sorted) as CNAMEs to the CloudFront distribution

### Data Management and Persistence
31. The system must save user inputs to `stages/b-ssl/data/inputs.json` following Stage A patterns
32. The system must save AWS discovery results to `stages/b-ssl/data/discovery.json` following Stage A patterns  
33. The system must save deployment outputs to `stages/b-ssl/data/outputs.json` including certificate ARN, domain names, and updated distribution details
34. The system must preserve Stage A outputs in the Stage B outputs file for downstream stages
35. The system must retain DNS validation records permanently (no automatic cleanup after certificate validation)

### Deployment Validation and Testing
36. The system must validate HTTPS connectivity for each configured domain using automated curl tests
37. The system must verify that SSL certificate details are correctly attached to the CloudFront distribution
38. The system must confirm that DNS resolution works correctly for all configured domains
39. The system must provide clear success/failure status for each validation step
40. **Testing Method**: Testing must be performed by executing the deployment command: `./go-b.sh -d www.sbx.briskhaven.com -d sbx.briskhaven.com`
41. **Testing Validation**: The system must validate HTTPS connectivity for both `https://www.sbx.briskhaven.com` and `https://sbx.briskhaven.com` after deployment

### Error Handling and Recovery
42. The system must provide clear error messages for common failure scenarios (invalid domains, missing hosted zones, certificate validation failures)
43. The system must support re-running the deployment script to continue from partial completion states
44. The system must detect and handle in-progress CloudFront distribution updates before attempting modifications
45. The system must provide rollback capabilities to remove SSL configuration and revert to Stage A state
46. **Fallback Rollback**: If Stage B cannot be rolled back gracefully, the system must use the existing `undo-a.sh` script from Stage A to completely remove the CloudFront distribution and all related resources

## Non-Goals (Out of Scope)

1. **Domain Registration**: This stage will not register new domains - all top-level domains must already exist as hosted zones in the infrastructure account
2. **Hosted Zone Creation**: Will not create new Route53 hosted zones - all required zones must already exist
3. **Wildcard Certificates**: Will not support wildcard SSL certificates (*.example.com) - only specific domain names
4. **Email Validation**: Will not support email-based certificate validation - only DNS validation
5. **Custom Certificate Authorities**: Will only use AWS Certificate Manager - no support for external or self-signed certificates
6. **Load Balancer Integration**: Will not configure Application Load Balancers or other load balancing services
7. **WAF Integration**: Will not configure AWS Web Application Firewall rules
8. **Custom SSL Policies**: Will use AWS default SSL policies - no custom cipher suites or TLS versions
9. **Certificate Renewal**: Will rely on AWS Certificate Manager automatic renewal - no manual renewal processes

## Design Considerations

### Script Architecture
- Follow Stage A patterns with `go-b.sh` as the main orchestration script
- Implement helper scripts in `stages/b-ssl/scripts/` directory:
  - `gather-inputs.sh` - Collect domain names and validate Stage A prerequisites  
  - `aws-discovery.sh` - Discover Route53 zones and validate account access
  - `deploy-infrastructure.sh` - Create certificate and update CloudFront via CDK
  - `deploy-dns.sh` - Configure Route53 DNS validation records
  - `validate-deployment.sh` - Test HTTPS connectivity and certificate attachment
  - `cleanup-rollback.sh` - Remove SSL configuration and revert to Stage A state
- **Fallback Cleanup**: If Stage B rollback fails, use `../a-cloudfront/undo-a.sh` to remove entire deployment

### Data File Structure
- `inputs.json`: Store domain list, AWS profiles, and Stage A dependency data
- `discovery.json`: Store Route53 zone information, account IDs, and resource validation results
- `outputs.json`: Store certificate ARN, updated CloudFront details, and Stage A passthrough data

### CDK Infrastructure
- Create SSL certificate construct that handles multiple domains
- Implement Route53 DNS validation record creation
- Update existing CloudFront distribution with certificate and alternate domain names
- Use cross-account IAM roles for Route53 operations in infrastructure account

## Technical Considerations

### Cross-Account Operations
- Certificate Manager operations occur in target account (where CloudFront exists)
- Route53 DNS validation records created in infrastructure account
- Both AWS profiles have admin-level access to their respective accounts

### Certificate Validation Timing
- DNS validation can take 5-30 minutes depending on DNS propagation
- Rely on AWS Certificate Manager's built-in retry logic for DNS propagation validation
- Implement polling mechanism to check validation status
- Provide progress indicators during validation wait periods

### CloudFront Propagation
- CloudFront distribution updates can take 15-45 minutes to propagate globally
- Implement checks for in-progress distributions before attempting updates
- Provide estimated completion times to users

### Domain Validation
- Validate FQDN format using regex patterns
- Check for subdomain relationships to find correct hosted zones
- Handle edge cases like multiple levels of subdomains

## Success Metrics

1. **Certificate Creation Success Rate**: 100% of certificates successfully created when valid domains and hosted zones are provided
2. **DNS Validation Success Rate**: 100% of certificates validated within 30 minutes when DNS records are properly configured
3. **HTTPS Connectivity**: 100% of configured domains respond correctly to HTTPS requests after deployment completion
4. **Deployment Time**: Complete SSL deployment (excluding propagation) within 5 minutes for up to 5 domains
5. **Error Recovery**: 100% of failed deployments can be re-run successfully after addressing the root cause
6. **Data Persistence**: 100% of deployment data correctly saved to JSON files for use by subsequent stages

## Implementation Notes

All previously open questions have been resolved and incorporated into the functional requirements above:

- **Certificate Limits**: Detect and report limit errors without proactive validation (Requirement 21)
- **DNS Propagation**: Rely on AWS Certificate Manager's built-in retry logic (Technical Considerations)
- **Multi-Region**: Use only the region identified in Stage A (Technical Considerations)
- **Hosted Zone Permissions**: Admin-level access assumed for both accounts (Technical Considerations)
- **Certificate Reuse**: Reuse existing certificates for matching domain sets (Requirement 23)
- **Domain Ordering**: Sort domains alphabetically for consistency (Requirement 24)
- **Validation Record Cleanup**: Retain DNS validation records permanently (Requirement 35)
- **CloudFront Behavior**: Configure behaviors to require SSL/HTTPS (Requirement 28)

## Testing and Rollback Strategy

- **Testing Method**: All testing must be performed using the actual deployment command: `./go-b.sh -d www.sbx.briskhaven.com -d sbx.briskhaven.com` (Requirement 40)
- **Graceful Rollback**: Stage B should provide its own rollback capabilities through `cleanup-rollback.sh` (Requirement 45)
- **Fallback Rollback**: If Stage B rollback fails, use Stage A's `undo-a.sh` script to completely remove the distribution and start over (Requirement 46) 