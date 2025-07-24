It’s entirely possible to centralize all DNS records for your domains (briskhaven.com, www.briskhaven.com, sbx.briskhaven.com, www.sbx.briskhaven.com, dev.briskhaven.com, and www.dev.briskhaven.com) in the infrastructure account using Amazon Route 53, while keeping environment-specific resources like CloudFront distributions, Lambda functions, and SSL certificates in their respective accounts (production, sandbox, and development). This approach aligns with your goal of maintaining DNS records in the infrastructure account and avoids the need to use Route 53 in member accounts. Below, I’ll outline how to achieve this setup, address the SSL certificate storage, and clarify the configuration steps.

### Key Considerations
1. **Centralized DNS in Infrastructure Account**: Route 53 allows you to manage DNS records in a single AWS account (your infrastructure account) while resolving domains to resources in other AWS accounts (production, sandbox, development) using alias records or CNAME records.
2. **SSL Certificates**: Since your applications use CloudFront distributions, SSL certificates must be stored in the same AWS account as the CloudFront distribution and in the us-east-1 region (required by CloudFront for global distributions). This means certificates will be environment-specific and stored in the respective accounts (production, sandbox, development).
3. **Cross-Account Resource Resolution**: You can resolve domains to CloudFront distributions in other accounts by using Route 53 alias records or CNAME records, leveraging the CloudFront distribution’s domain name.
4. **Avoiding Route 53 in Member Accounts**: By centralizing DNS in the infrastructure account, you can avoid creating hosted zones in member accounts, simplifying management.

### Solution Architecture
- **Infrastructure Account**:
  - Hosts the Route 53 public hosted zone for briskhaven.com.
  - Contains DNS records (A records or CNAME records) for briskhaven.com, www.briskhaven.com, sbx.briskhaven.com, www.sbx.briskhaven.com, dev.briskhaven.com, and www.dev.briskhaven.com.
  - Uses alias records to point to CloudFront distributions in the respective environment accounts.
- **Production Account**:
  - Hosts the CloudFront distribution for briskhaven.com and www.briskhaven.com.
  - Stores the SSL certificate for *.briskhaven.com in AWS Certificate Manager (ACM) in us-east-1.
  - Hosts the Lambda function (or other backend) associated with the CloudFront distribution.
- **Sandbox Account**:
  - Hosts the CloudFront distribution for sbx.briskhaven.com and www.sbx.briskhaven.com.
  - Stores the SSL certificate for *.briskhaven.com in ACM in us-east-1.
  - Hosts the Lambda function for the sandbox environment.
- **Development Account**:
  - Hosts the CloudFront distribution for dev.briskhaven.com and www.dev.briskhaven.com.
  - Stores the SSL certificate for *.briskhaven.com in ACM in us-east-1.
  - Hosts the Lambda function for the development environment.

### Step-by-Step Configuration
#### 1. **Set Up SSL Certificates in Environment Accounts**
Since CloudFront requires SSL certificates to be in the same account and in us-east-1, you’ll need to create or import a wildcard certificate (*.briskhaven.com) in each environment account.

- **In Each Environment Account (Production, Sandbox, Development)**:
  - Go to AWS Certificate Manager (ACM) in the us-east-1 region.
  - Request a public certificate for *.briskhaven.com (this covers briskhaven.com, www.briskhaven.com, sbx.briskhaven.com, etc.).
  - Validate the certificate using DNS validation:
    - ACM will provide a CNAME record to add to your DNS.
    - Since DNS is managed in the infrastructure account, you’ll add these CNAME records to the Route 53 hosted zone in the infrastructure account (see step 2).
  - Alternatively, if you already have a wildcard certificate, import it into ACM in each account’s us-east-1 region.
  - Note: You’ll need one certificate per account, even though they cover the same domain (*.briskhaven.com). This is because CloudFront cannot reference certificates across accounts.

#### 2. **Create Route 53 Hosted Zone in Infrastructure Account**
- In the infrastructure account, create a public hosted zone for briskhaven.com in Route 53.
  - Go to Route 53 > Hosted zones > Create hosted zone.
  - Enter the domain name: briskhaven.com.
  - This will generate NS (Name Server) and SOA (Start of Authority) records.
- Update your domain registrar (e.g., GoDaddy, Namecheap) to use the Route 53 NS records for briskhaven.com to delegate DNS to AWS.
- Add the CNAME records provided by ACM (from each environment account) to the briskhaven.com hosted zone to validate the SSL certificates. For example:
  - For production: `_xxxxxxxxxxxxxxxx.briskhaven.com. CNAME _yyyyyyyyyyyy.acm-validations.aws.`
  - For sandbox: `_zzzzzzzzzzzz.briskhaven.com. CNAME _wwwwwwwwwwww.acm-validations.aws.`
  - For development: `_aaaaaaaaaaaa.briskhaven.com. CNAME _bbbbbbbbbbbb.acm-validations.aws.`
  - These records allow ACM to validate the certificates across accounts.

#### 3. **Set Up CloudFront Distributions in Environment Accounts**
In each environment account, create a CloudFront distribution for the respective domains.

- **Production Account** (for briskhaven.com and www.briskhaven.com):
  - Create a CloudFront distribution.
  - Set the Alternate Domain Names (CNAMEs) to briskhaven.com and www.briskhaven.com.
  - Select the ACM certificate for *.briskhaven.com (from the production account’s us-east-1 region).
  - Configure the origin to point to the Lambda function (or Lambda@Edge) in the production account.
  - Note the CloudFront distribution’s domain name (e.g., `d1234567890.cloudfront.net`).
- **Sandbox Account** (for sbx.briskhaven.com and www.sbx.briskhaven.com):
  - Create a CloudFront distribution.
  - Set the Alternate Domain Names to sbx.briskhaven.com and www.sbx.briskhaven.com.
  - Select the ACM certificate for *.briskhaven.com (from the sandbox account’s us-east-1 region).
  - Configure the origin to point to the Lambda function in the sandbox account.
  - Note the CloudFront distribution’s domain name (e.g., `d9876543210.cloudfront.net`).
- **Development Account** (for dev.briskhaven.com and www.dev.briskhaven.com):
  - Create a CloudFront distribution.
  - Set the Alternate Domain Names to dev.briskhaven.com and www.dev.briskhaven.com.
  - Select the ACM certificate for *.briskhaven.com (from the development account’s us-east-1 region).
  - Configure the origin to point to the Lambda function in the development account.
  - Note the CloudFront distribution’s domain name (e.g., `d5555555555.cloudfront.net`).

#### 4. **Configure Route 53 Records in Infrastructure Account**
In the infrastructure account’s Route 53 hosted zone for briskhaven.com, create records to resolve the domains to the CloudFront distributions in the respective accounts.

- **For briskhaven.com and www.briskhaven.com**:
  - Create an A record for briskhaven.com:
    - Record type: A – IPv4 address.
    - Alias: Yes.
    - Alias target: Select the CloudFront distribution from the production account (e.g., `d1234567890.cloudfront.net`).
    - Note: CloudFront distributions from other accounts will appear in the Route 53 console’s alias target dropdown if they have the correct Alternate Domain Names configured.
  - Create an A record for www.briskhaven.com:
    - Alias to the same CloudFront distribution as above.
- **For sbx.briskhaven.com and www.sbx.briskhaven.com**:
  - Create an A record for sbx.briskhaven.com:
    - Alias to the CloudFront distribution in the sandbox account (e.g., `d9876543210.cloudfront.net`).
  - Create an A record for www.sbx.briskhaven.com:
    - Alias to the same CloudFront distribution.
- **For dev.briskhaven.com and www.dev.briskhaven.com**:
  - Create an A record for dev.briskhaven.com:
    - Alias to the CloudFront distribution in the development account (e.g., `d5555555555.cloudfront.net`).
  - Create an A record for www.dev.briskhaven.com:
    - Alias to the same CloudFront distribution.

**Alternative (if alias records aren’t feasible)**:
- If the CloudFront distributions don’t appear in the Route 53 alias target dropdown (e.g., due to permissions or configuration issues), you can use CNAME records instead:
  - For briskhaven.com: `CNAME d1234567890.cloudfront.net`
  - For www.briskhaven.com: `CNAME d1234567890.cloudfront.net`
  - For sbx.briskhaven.com: `CNAME d9876543210.cloudfront.net`
  - For www.sbx.briskhaven.com: `CNAME d9876543210.cloudfront.net`
  - For dev.briskhaven.com: `CNAME d5555555555.cloudfront.net`
  - For www.dev.briskhaven.com: `CNAME d5555555555.cloudfront.net`
- Note: Alias records are preferred over CNAME records because they are more efficient (resolved at the Route 53 level) and don’t incur additional DNS query costs. However, CNAME records will work if alias records aren’t an option.

#### 5. **IAM Permissions for Cross-Account Access**
To allow Route 53 in the infrastructure account to resolve to CloudFront distributions in other accounts, ensure proper IAM permissions.

- **In Each Environment Account**:
  - Attach an IAM policy to allow Route 53 to access the CloudFront distribution. For example:
    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": "arn:aws:iam::<infrastructure-account-id>:root"
          },
          "Action": [
            "cloudfront:GetDistribution",
            "cloudfront:ListDistributions"
          ],
          "Resource": "arn:aws:cloudfront::<environment-account-id>:distribution/*"
        }
      ]
    }
    ```
  - Attach this policy to the CloudFront distribution or as a resource-based policy.
- **In the Infrastructure Account**:
  - Ensure the Route 53 service role or user has permissions to query CloudFront distributions in other accounts:
    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "cloudfront:GetDistribution",
            "cloudfront:ListDistributions"
          ],
          "Resource": [
            "arn:aws:cloudfront::<production-account-id>:distribution/*",
            "arn:aws:cloudfront::<sandbox-account-id>:distribution/*",
            "arn:aws:cloudfront::<development-account-id>:distribution/*"
          ]
        }
      ]
    }
    ```

#### 6. **Testing and Validation**
- After configuring the DNS records, test resolution using tools like `dig` or `nslookup`:
  - `dig briskhaven.com`
  - `dig sbx.briskhaven.com`
  - `dig dev.briskhaven.com`
  - Ensure they resolve to the correct CloudFront distribution domain names.
- Access the domains in a browser to verify that the CloudFront distributions serve the correct Lambda-backed content with SSL enabled.
- Check the ACM console in each account to ensure the certificates are issued and associated with the CloudFront distributions.

### Addressing Your Concerns
- **Centralized DNS**: By using Route 53 in the infrastructure account with alias or CNAME records, you avoid the need for hosted zones in member accounts. All DNS records are managed centrally, as desired.
- **SSL Certificate Storage**: Certificates must reside in the same account as the CloudFront distributions (in us-east-1). Using a wildcard certificate (*.briskhaven.com) in each account simplifies management, as it covers all subdomains.
- **Confusion Resolution**: The setup clarifies that:
  - DNS records (including ACM validation records) are stored in the infrastructure account’s Route 53 hosted zone.
  - SSL certificates and CloudFront distributions are stored in the environment-specific accounts.
- **Scalability**: This architecture scales well for additional environments (e.g., staging, testing) by replicating the setup: create a CloudFront distribution, ACM certificate, and Lambda function in the new account, then add corresponding DNS records in the infrastructure account.

### Additional Recommendations
- **Infrastructure as Code**: Use AWS CloudFormation or Terraform to manage the Route 53 records, CloudFront distributions, and ACM certificates. This ensures consistency and simplifies updates across accounts.
  - Example: Use AWS CloudFormation StackSets to deploy resources across multiple accounts.
- **DNS Validation Automation**: Use AWS SDK or CLI scripts to automate adding ACM validation CNAME records to the Route 53 hosted zone in the infrastructure account.
- **Monitoring and Logging**: Enable Route 53 query logging and CloudFront access logging to monitor DNS resolution and traffic patterns.
- **Security**: Restrict IAM permissions to the minimum required for cross-account access. Use AWS Organizations to enforce policies if needed.
- **Subdomain Consistency**: Ensure that www and non-www versions of each domain point to the same CloudFront distribution to avoid confusion (e.g., www.briskhaven.com and briskhaven.com use the same distribution).

### Why Route 53 in Member Accounts Isn’t Needed
You don’t need Route 53 hosted zones in the production, sandbox, or development accounts because:
- The infrastructure account’s Route 53 hosted zone for briskhaven.com can handle all subdomains (sbx, dev, www, etc.).
- Alias or CNAME records can point to CloudFront distributions in other accounts without requiring local hosted zones.
- ACM validation records can be added to the central hosted zone, avoiding the need for DNS management in member accounts.

### Final Answer
Yes, it’s possible to store all DNS records in the infrastructure account’s Route 53 hosted zone and keep environment-specific resources (CloudFront, Lambda, SSL certificates) in their respective accounts. Configure Route 53 in the infrastructure account to use alias records (or CNAME records) to resolve briskhaven.com and www.briskhaven.com to the production account’s CloudFront distribution, sbx.briskhaven.com and www.sbx.briskhaven.com to the sandbox account’s distribution, and dev.briskhaven.com and www.dev.briskhaven.com to the development account’s distribution. Store SSL certificates (*.briskhaven.com) in ACM in us-east-1 in each environment account. Ensure proper IAM permissions for cross-account access, and use the infrastructure account for ACM DNS validation records. This setup avoids using Route 53 in member accounts, meeting your requirements for centralized DNS management.

If you need further assistance with specific configurations, IAM policies, or automation scripts, let me know!