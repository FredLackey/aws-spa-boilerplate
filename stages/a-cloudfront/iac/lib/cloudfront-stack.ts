import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface CloudFrontStackProps extends cdk.StackProps {
  distributionPrefix: string;
  targetRegion: string;
  targetVpcId: string;
}

export class CloudFrontStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;

  constructor(scope: Construct, id: string, props: CloudFrontStackProps) {
    super(scope, id, props);

    const { distributionPrefix, targetRegion, targetVpcId } = props;

    // Create S3 bucket for static content storage
    this.bucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `${distributionPrefix}-content-${cdk.Aws.ACCOUNT_ID}`,
      publicReadAccess: true,
      blockPublicAccess: new s3.BlockPublicAccess({
        blockPublicAcls: false,
        blockPublicPolicy: false,
        ignorePublicAcls: false,
        restrictPublicBuckets: false,
      }),
      websiteIndexDocument: 'index.html',
      websiteErrorDocument: 'index.html',
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create CloudFront Origin Access Control for S3
    const originAccessControl = new cloudfront.S3OriginAccessControl(this, 'OriginAccessControl', {
      description: `OAC for ${distributionPrefix} S3 bucket`,
    });

    // Create CloudFront distribution
    this.distribution = new cloudfront.Distribution(this, 'Distribution', {
      comment: `${distributionPrefix} - Stage A CloudFront Distribution`,
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.bucket, {
          originAccessControl,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: new cloudfront.CachePolicy(this, 'CachePolicy', {
          cachePolicyName: `${distributionPrefix}-cache-policy`,
          comment: 'Cache policy with minimal TTL for development',
          defaultTtl: cdk.Duration.minutes(1),
          minTtl: cdk.Duration.minutes(1),
          maxTtl: cdk.Duration.minutes(1),
          cookieBehavior: cloudfront.CacheCookieBehavior.none(),
          headerBehavior: cloudfront.CacheHeaderBehavior.none(),
          queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
          enableAcceptEncodingBrotli: true,
          enableAcceptEncodingGzip: true,
        }),
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        compress: true,
      },
      defaultRootObject: 'index.html',
      errorResponses: [
        {
          httpStatus: 404,
          responsePagePath: '/index.html',
          responseHttpStatus: 200,
          ttl: cdk.Duration.minutes(1),
        },
        {
          httpStatus: 403,
          responsePagePath: '/index.html',
          responseHttpStatus: 200,
          ttl: cdk.Duration.minutes(1),
        },
      ],
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      enabled: true,
    });

    // Add bucket policy to allow CloudFront access
    this.bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [`${this.bucket.bucketArn}/*`],
        conditions: {
          StringEquals: {
            'AWS:SourceArn': `arn:aws:cloudfront::${cdk.Aws.ACCOUNT_ID}:distribution/${this.distribution.distributionId}`,
          },
        },
      })
    );

    // Stack outputs for subsequent stages
    new cdk.CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront Distribution ID',
      exportName: `${distributionPrefix}-distribution-id`,
    });

    new cdk.CfnOutput(this, 'DistributionDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront Distribution Domain Name',
      exportName: `${distributionPrefix}-distribution-domain`,
    });

    new cdk.CfnOutput(this, 'DistributionUrl', {
      value: `https://${this.distribution.distributionDomainName}`,
      description: 'CloudFront Distribution HTTPS URL',
      exportName: `${distributionPrefix}-distribution-url`,
    });

    new cdk.CfnOutput(this, 'BucketName', {
      value: this.bucket.bucketName,
      description: 'S3 Content Bucket Name',
      exportName: `${distributionPrefix}-bucket-name`,
    });

    new cdk.CfnOutput(this, 'BucketArn', {
      value: this.bucket.bucketArn,
      description: 'S3 Content Bucket ARN',
      exportName: `${distributionPrefix}-bucket-arn`,
    });

    new cdk.CfnOutput(this, 'DistributionPrefix', {
      value: distributionPrefix,
      description: 'Distribution Prefix Used',
      exportName: `${distributionPrefix}-prefix`,
    });

    new cdk.CfnOutput(this, 'TargetRegion', {
      value: targetRegion,
      description: 'Target Region for Deployment',
      exportName: `${distributionPrefix}-target-region`,
    });

    new cdk.CfnOutput(this, 'TargetVpcId', {
      value: targetVpcId,
      description: 'Target VPC ID for Deployment',
      exportName: `${distributionPrefix}-target-vpc-id`,
    });
  }
} 