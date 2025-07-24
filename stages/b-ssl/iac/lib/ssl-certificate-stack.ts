import * as cdk from 'aws-cdk-lib';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as route53 from 'aws-cdk-lib/aws-route53';
import { Construct } from 'constructs';

export interface SslCertificateStackProps extends cdk.StackProps {
  // Props will be passed dynamically from the deployment script
}

export class SslCertificateStack extends cdk.Stack {
  public readonly certificate: acm.Certificate;
  public readonly distribution: cloudfront.Distribution;

  constructor(scope: Construct, id: string, props: SslCertificateStackProps) {
    super(scope, id, props);

    // Get context values from CDK context (set by deploy-infrastructure.sh)
    const domains = this.node.tryGetContext('stage-b-ssl:domains') as string[];
    const hostedZones = this.node.tryGetContext('stage-b-ssl:hostedZones') as Array<{
      domain: string;
      zoneId: string;
      zoneName: string;
    }>;
    const distributionId = this.node.tryGetContext('stage-b-ssl:distributionId') as string;
    const infraAccountId = this.node.tryGetContext('stage-b-ssl:infraAccountId') as string;
    const targetAccountId = this.node.tryGetContext('stage-b-ssl:targetAccountId') as string;

    // Validate required context
    if (!domains || !hostedZones || !distributionId) {
      throw new Error('Missing required context: domains, hostedZones, or distributionId');
    }

    // Sort domains alphabetically for consistent certificate creation
    const sortedDomains = [...domains].sort();
    
    // Create hosted zone references for DNS validation
    const hostedZoneMap = new Map<string, route53.IHostedZone>();
    
    for (const zoneInfo of hostedZones) {
      // Import existing hosted zone
      const hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, `HostedZone-${zoneInfo.zoneName}`, {
        hostedZoneId: zoneInfo.zoneId.replace('/hostedzone/', ''),
        zoneName: zoneInfo.zoneName,
      });
      
      hostedZoneMap.set(zoneInfo.domain, hostedZone);
    }

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
      const validationMap: { [domainName: string]: acm.CertificateValidation } = {};
      
      for (const domain of sortedDomains) {
        const hostedZone = hostedZoneMap.get(domain);
        if (hostedZone) {
          validationMap[domain] = acm.CertificateValidation.fromDns(hostedZone);
        }
      }

      this.certificate = new acm.Certificate(this, 'SslCertificate', {
        domainName: sortedDomains[0], // Primary domain
        subjectAlternativeNames: sortedDomains.slice(1), // Additional domains
        validation: acm.CertificateValidation.fromDnsMultiZone(validationMap),
        certificateName: `stage-b-ssl-${sortedDomains.join('-').replace(/\./g, '-')}`,
      });

      new cdk.CfnOutput(this, 'CertificateArnOutput', {
        value: this.certificate.certificateArn,
        description: 'SSL Certificate ARN (newly created)',
        exportName: 'StageBSslCertificateArn',
      });
    }

    // Import existing CloudFront distribution from Stage A
    this.distribution = cloudfront.Distribution.fromDistributionAttributes(this, 'ExistingDistribution', {
      distributionId: distributionId,
      domainName: `${distributionId}.cloudfront.net`, // Standard CloudFront domain format
    });

    // Note: CloudFront distribution updates require a more complex approach
    // We'll use a custom resource or AWS SDK calls in the deployment script
    // because CDK cannot directly modify imported distributions
    
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

    // Output validation status
    new cdk.CfnOutput(this, 'ValidationMethodOutput', {
      value: 'DNS',
      description: 'Certificate Validation Method',
      exportName: 'StageBValidationMethod',
    });

    // Output hosted zones information
    const hostedZoneInfo = hostedZones.map(zone => `${zone.domain}:${zone.zoneId}`).join(',');
    new cdk.CfnOutput(this, 'HostedZonesOutput', {
      value: hostedZoneInfo,
      description: 'Route53 Hosted Zones Used',
      exportName: 'StageBHostedZones',
    });

    // Tags for resource identification
    cdk.Tags.of(this).add('Stage', 'B-SSL');
    cdk.Tags.of(this).add('Component', 'SSL-Certificate');
    cdk.Tags.of(this).add('Domains', sortedDomains.join(','));
  }
} 