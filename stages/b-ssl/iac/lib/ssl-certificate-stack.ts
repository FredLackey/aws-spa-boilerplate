import * as cdk from 'aws-cdk-lib';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import { Construct } from 'constructs';

export interface SslCertificateStackProps extends cdk.StackProps {
  // Props will be passed dynamically from the deployment script
}

export class SslCertificateStack extends cdk.Stack {
  public readonly certificate: acm.ICertificate;
  public readonly distribution: cloudfront.IDistribution;

  constructor(scope: Construct, id: string, props: SslCertificateStackProps) {
    super(scope, id, props);

    // Get context values from CDK context (set by deploy-infrastructure.sh)
    const domains = this.node.tryGetContext('stage-b-ssl:domains') as string[];
    const distributionId = this.node.tryGetContext('stage-b-ssl:distributionId') as string;
    const infraAccountId = this.node.tryGetContext('stage-b-ssl:infraAccountId') as string;
    const targetAccountId = this.node.tryGetContext('stage-b-ssl:targetAccountId') as string;

    // Validate required context
    if (!domains || !distributionId) {
      throw new Error('Missing required context: domains or distributionId');
    }

    if (!infraAccountId || !targetAccountId) {
      throw new Error('Missing required context: infraAccountId or targetAccountId');
    }

    // Sort domains alphabetically for consistent certificate creation
    const sortedDomains = [...domains].sort();
    
    // Check for existing certificate with the same domain set
    const certificateArn = this.node.tryGetContext('stage-b-ssl:existingCertificateArn') as string;
    
    if (certificateArn) {
      // Reuse existing certificate
      this.certificate = acm.Certificate.fromCertificateArn(this, 'ExistingCertificate', certificateArn);
      
      new cdk.CfnOutput(this, 'CertificateArnOutput', {
        value: this.certificate.certificateArn,
        description: 'SSL Certificate ARN (reused existing)',
        exportName: 'StageBSslCertificateArn',
      });
    } else {
      // Create new SSL certificate with DNS validation
      // Per architecture: Certificate created in environment-specific account (us-east-1)
      // DNS validation records will be managed separately in infrastructure account
      this.certificate = new acm.Certificate(this, 'SslCertificate', {
        domainName: sortedDomains[0], // Primary domain
        subjectAlternativeNames: sortedDomains.slice(1), // Additional domains
        validation: acm.CertificateValidation.fromDns(), // DNS validation without hosted zone reference
        certificateName: `stage-b-ssl-${sortedDomains.join('-').replace(/\./g, '-')}`,
      });

      new cdk.CfnOutput(this, 'CertificateArnOutput', {
        value: this.certificate.certificateArn,
        description: 'SSL Certificate ARN (newly created)',
        exportName: 'StageBSslCertificateArn',
      });

      // Output DNS validation records for infrastructure account Route53 management
      new cdk.CfnOutput(this, 'CertificateValidationRecordsOutput', {
        value: 'Check ACM console for DNS validation records to add to infrastructure account Route53',
        description: 'DNS validation records needed in infrastructure account',
        exportName: 'StageBValidationRecords',
      });
    }

    // Import existing CloudFront distribution from Stage A
    this.distribution = cloudfront.Distribution.fromDistributionAttributes(this, 'ExistingDistribution', {
      distributionId: distributionId,
      domainName: `${distributionId}.cloudfront.net`, // Standard CloudFront domain format
    });

    // Output the distribution information
    new cdk.CfnOutput(this, 'DistributionIdOutput', {
      value: this.distribution.distributionId,
      description: 'CloudFront Distribution ID',
      exportName: 'StageBDistributionId',
    });

    new cdk.CfnOutput(this, 'DistributionDomainNameOutput', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront Distribution Domain Name',
      exportName: 'StageBDistributionDomainName',
    });

    // Output domain information
    new cdk.CfnOutput(this, 'DomainsOutput', {
      value: sortedDomains.join(','),
      description: 'SSL Certificate Domains',
      exportName: 'StageBSslDomains',
    });

    // Output account information for cross-account operations
    new cdk.CfnOutput(this, 'InfraAccountIdOutput', {
      value: infraAccountId,
      description: 'Infrastructure Account ID (for Route53 DNS validation)',
      exportName: 'StageBInfraAccountId',
    });

    new cdk.CfnOutput(this, 'TargetAccountIdOutput', {
      value: targetAccountId,
      description: 'Target Account ID (where certificate is created)',
      exportName: 'StageBTargetAccountId',
    });

    // Output validation status
    new cdk.CfnOutput(this, 'ValidationMethodOutput', {
      value: 'DNS',
      description: 'Certificate Validation Method',
      exportName: 'StageBValidationMethod',
    });

    // Tags for resource identification
    cdk.Tags.of(this).add('Stage', 'B-SSL');
    cdk.Tags.of(this).add('Component', 'SSL-Certificate');
    cdk.Tags.of(this).add('Environment', targetAccountId);
    cdk.Tags.of(this).add('InfrastructureAccount', infraAccountId);
    cdk.Tags.of(this).add('DomainCount', sortedDomains.length.toString());
  }
} 