#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CloudFrontStack } from './lib/cloudfront-stack';

const app = new cdk.App();

// Read context values from cdk.json
const distributionPrefix = app.node.tryGetContext('stage-a-cloudfront:distributionPrefix');
const targetRegion = app.node.tryGetContext('stage-a-cloudfront:targetRegion');
const targetProfile = app.node.tryGetContext('stage-a-cloudfront:targetProfile');
const targetAccountId = app.node.tryGetContext('stage-a-cloudfront:targetAccountId');
const targetVpcId = app.node.tryGetContext('stage-a-cloudfront:targetVpcId');

// Validate required context values
if (!distributionPrefix || !targetRegion || !targetAccountId || !targetVpcId) {
  throw new Error(
    'Missing required context values. Please ensure distributionPrefix, targetRegion, targetAccountId, and targetVpcId are set in cdk.json'
  );
}

// Create the CloudFront stack
new CloudFrontStack(app, 'StageACloudFrontStack', {
  distributionPrefix,
  targetRegion,
  targetVpcId,
  env: {
    account: targetAccountId,
    region: targetRegion,
  },
  description: `Stage A CloudFront Distribution Stack - ${distributionPrefix}`,
}); 