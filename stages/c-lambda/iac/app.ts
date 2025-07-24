#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { LambdaStack } from './lib/lambda-stack';

const app = new cdk.App();

// Read context values from cdk.json
const distributionPrefix = app.node.tryGetContext('stage-c-lambda:distributionPrefix');
const targetRegion = app.node.tryGetContext('stage-c-lambda:targetRegion');
const targetProfile = app.node.tryGetContext('stage-c-lambda:targetProfile');
const targetAccountId = app.node.tryGetContext('stage-c-lambda:targetAccountId');
const targetVpcId = app.node.tryGetContext('stage-c-lambda:targetVpcId');
const distributionId = app.node.tryGetContext('stage-c-lambda:distributionId');
const bucketName = app.node.tryGetContext('stage-c-lambda:bucketName');

// Validate required context values
if (!distributionPrefix || !targetRegion || !targetAccountId || !targetVpcId || !distributionId || !bucketName) {
  throw new Error(
    'Missing required context values. Please ensure distributionPrefix, targetRegion, targetAccountId, targetVpcId, distributionId, and bucketName are set in cdk.json'
  );
}

// Create the Lambda stack
new LambdaStack(app, 'StageCLambdaStack', {
  distributionPrefix,
  targetRegion,
  targetVpcId,
  distributionId,
  bucketName,
  env: {
    account: targetAccountId,
    region: targetRegion,
  },
  description: `Stage C Lambda Function Stack - ${distributionPrefix}`,
}); 