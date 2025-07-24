import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
export interface LambdaStackProps extends cdk.StackProps {
    distributionPrefix: string;
    targetRegion: string;
    targetVpcId: string;
    distributionId: string;
    bucketName: string;
    codePath?: string;
}
export declare class LambdaStack extends cdk.Stack {
    readonly lambdaFunction: lambda.Function;
    readonly functionUrl: lambda.FunctionUrl;
    readonly logGroup: logs.LogGroup;
    constructor(scope: Construct, id: string, props: LambdaStackProps);
}
