#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SslCertificateStack } from './lib/ssl-certificate-stack';

const app = new cdk.App();

// Context values will be dynamically set by deploy-infrastructure.sh
// These are placeholders that will be overridden at deployment time

// Create the SSL Certificate stack
new SslCertificateStack(app, 'StageBSslCertificateStack', {
  env: {
    // Account and region will be set dynamically
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: 'us-east-1', // SSL certificates for CloudFront must be in us-east-1
  },
  description: 'Stage B SSL Certificate and CloudFront Integration Stack',
}); 