#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ReactApiStack } from './lib/react-api-stack';

const app = new cdk.App();

// Read context values from cdk.json
const distributionPrefix = app.node.tryGetContext('stage-e-react-api:distributionPrefix');
const targetRegion = app.node.tryGetContext('stage-e-react-api:targetRegion');
const targetProfile = app.node.tryGetContext('stage-e-react-api:targetProfile');
const infrastructureProfile = app.node.tryGetContext('stage-e-react-api:infrastructureProfile');
const targetAccountId = app.node.tryGetContext('stage-e-react-api:targetAccountId');
const infrastructureAccountId = app.node.tryGetContext('stage-e-react-api:infrastructureAccountId');
const targetVpcId = app.node.tryGetContext('stage-e-react-api:targetVpcId');
const distributionId = app.node.tryGetContext('stage-e-react-api:distributionId');
const bucketName = app.node.tryGetContext('stage-e-react-api:bucketName');
const primaryDomain = app.node.tryGetContext('stage-e-react-api:primaryDomain');
const certificateArn = app.node.tryGetContext('stage-e-react-api:certificateArn');
const lambdaFunctionArn = app.node.tryGetContext('stage-e-react-api:lambdaFunctionArn');
const lambdaFunctionUrl = app.node.tryGetContext('stage-e-react-api:lambdaFunctionUrl');

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

// Validate Stage C (Lambda) context values
if (!lambdaFunctionArn || !lambdaFunctionUrl) {
  throw new Error(
    'Missing Stage C Lambda context values. Please ensure lambdaFunctionArn and lambdaFunctionUrl are set in cdk.json'
  );
}

// Create the React API deployment stack
new ReactApiStack(app, 'StageEReactApiStack', {
  distributionPrefix,
  targetRegion,
  targetProfile,
  infrastructureProfile,
  targetVpcId,
  distributionId,
  bucketName,
  primaryDomain,
  certificateArn,
  lambdaFunctionArn,
  lambdaFunctionUrl,
  env: {
    account: targetAccountId,
    region: targetRegion,
  },
  description: `Stage E React API Deployment Stack - ${distributionPrefix}`,
  tags: {
    Project: 'AWS SPA Boilerplate',
    Stage: 'E - React API',
    DistributionPrefix: distributionPrefix,
    PrimaryDomain: primaryDomain,
  },
}); 