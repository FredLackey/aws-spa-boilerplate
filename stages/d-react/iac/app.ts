#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ReactStack } from './lib/react-stack';

const app = new cdk.App();

// Read context values from cdk.json
const distributionPrefix = app.node.tryGetContext('stage-d-react:distributionPrefix');
const targetRegion = app.node.tryGetContext('stage-d-react:targetRegion');
const targetProfile = app.node.tryGetContext('stage-d-react:targetProfile');
const infrastructureProfile = app.node.tryGetContext('stage-d-react:infrastructureProfile');
const targetAccountId = app.node.tryGetContext('stage-d-react:targetAccountId');
const infrastructureAccountId = app.node.tryGetContext('stage-d-react:infrastructureAccountId');
const targetVpcId = app.node.tryGetContext('stage-d-react:targetVpcId');
const distributionId = app.node.tryGetContext('stage-d-react:distributionId');
const bucketName = app.node.tryGetContext('stage-d-react:bucketName');
const primaryDomain = app.node.tryGetContext('stage-d-react:primaryDomain');
const certificateArn = app.node.tryGetContext('stage-d-react:certificateArn');
const lambdaFunctionUrl = app.node.tryGetContext('stage-d-react:lambdaFunctionUrl');

// Validate required context values
if (!distributionPrefix || !targetRegion || !targetAccountId || !targetVpcId || !distributionId || !bucketName) {
  throw new Error(
    'Missing required context values. Please ensure distributionPrefix, targetRegion, targetAccountId, targetVpcId, distributionId, and bucketName are set in cdk.json'
  );
}

// Validate Stage B (SSL) context values
if (!primaryDomain || !certificateArn) {
  throw new Error(
    'Missing Stage B SSL context values. Please ensure primaryDomain and certificateArn are set in cdk.json'
  );
}

// Create the React deployment stack
new ReactStack(app, 'StageDReactStack', {
  distributionPrefix,
  targetRegion,
  targetProfile,
  infrastructureProfile,
  targetVpcId,
  distributionId,
  bucketName,
  primaryDomain,
  certificateArn,
  lambdaFunctionUrl,
  env: {
    account: targetAccountId,
    region: targetRegion,
  },
  description: `Stage D React Deployment Stack - ${distributionPrefix}`,
  tags: {
    Project: 'AWS SPA Boilerplate',
    Stage: 'D - React',
    DistributionPrefix: distributionPrefix,
    PrimaryDomain: primaryDomain,
  },
}); 