#!/usr/bin/env node
"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
require("source-map-support/register");
const cdk = __importStar(require("aws-cdk-lib"));
const lambda_stack_1 = require("./lib/lambda-stack");
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
    throw new Error('Missing required context values. Please ensure distributionPrefix, targetRegion, targetAccountId, targetVpcId, distributionId, and bucketName are set in cdk.json');
}
// Create the Lambda stack
new lambda_stack_1.LambdaStack(app, 'StageCLambdaStack', {
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
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiYXBwLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiYXBwLnRzIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiI7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7O0FBQ0EsdUNBQXFDO0FBQ3JDLGlEQUFtQztBQUNuQyxxREFBaUQ7QUFFakQsTUFBTSxHQUFHLEdBQUcsSUFBSSxHQUFHLENBQUMsR0FBRyxFQUFFLENBQUM7QUFFMUIsb0NBQW9DO0FBQ3BDLE1BQU0sa0JBQWtCLEdBQUcsR0FBRyxDQUFDLElBQUksQ0FBQyxhQUFhLENBQUMsbUNBQW1DLENBQUMsQ0FBQztBQUN2RixNQUFNLFlBQVksR0FBRyxHQUFHLENBQUMsSUFBSSxDQUFDLGFBQWEsQ0FBQyw2QkFBNkIsQ0FBQyxDQUFDO0FBQzNFLE1BQU0sYUFBYSxHQUFHLEdBQUcsQ0FBQyxJQUFJLENBQUMsYUFBYSxDQUFDLDhCQUE4QixDQUFDLENBQUM7QUFDN0UsTUFBTSxlQUFlLEdBQUcsR0FBRyxDQUFDLElBQUksQ0FBQyxhQUFhLENBQUMsZ0NBQWdDLENBQUMsQ0FBQztBQUNqRixNQUFNLFdBQVcsR0FBRyxHQUFHLENBQUMsSUFBSSxDQUFDLGFBQWEsQ0FBQyw0QkFBNEIsQ0FBQyxDQUFDO0FBQ3pFLE1BQU0sY0FBYyxHQUFHLEdBQUcsQ0FBQyxJQUFJLENBQUMsYUFBYSxDQUFDLCtCQUErQixDQUFDLENBQUM7QUFDL0UsTUFBTSxVQUFVLEdBQUcsR0FBRyxDQUFDLElBQUksQ0FBQyxhQUFhLENBQUMsMkJBQTJCLENBQUMsQ0FBQztBQUV2RSxtQ0FBbUM7QUFDbkMsSUFBSSxDQUFDLGtCQUFrQixJQUFJLENBQUMsWUFBWSxJQUFJLENBQUMsZUFBZSxJQUFJLENBQUMsV0FBVyxJQUFJLENBQUMsY0FBYyxJQUFJLENBQUMsVUFBVSxFQUFFLENBQUM7SUFDL0csTUFBTSxJQUFJLEtBQUssQ0FDYixtS0FBbUssQ0FDcEssQ0FBQztBQUNKLENBQUM7QUFFRCwwQkFBMEI7QUFDMUIsSUFBSSwwQkFBVyxDQUFDLEdBQUcsRUFBRSxtQkFBbUIsRUFBRTtJQUN4QyxrQkFBa0I7SUFDbEIsWUFBWTtJQUNaLFdBQVc7SUFDWCxjQUFjO0lBQ2QsVUFBVTtJQUNWLEdBQUcsRUFBRTtRQUNILE9BQU8sRUFBRSxlQUFlO1FBQ3hCLE1BQU0sRUFBRSxZQUFZO0tBQ3JCO0lBQ0QsV0FBVyxFQUFFLG1DQUFtQyxrQkFBa0IsRUFBRTtDQUNyRSxDQUFDLENBQUMiLCJzb3VyY2VzQ29udGVudCI6WyIjIS91c3IvYmluL2VudiBub2RlXG5pbXBvcnQgJ3NvdXJjZS1tYXAtc3VwcG9ydC9yZWdpc3Rlcic7XG5pbXBvcnQgKiBhcyBjZGsgZnJvbSAnYXdzLWNkay1saWInO1xuaW1wb3J0IHsgTGFtYmRhU3RhY2sgfSBmcm9tICcuL2xpYi9sYW1iZGEtc3RhY2snO1xuXG5jb25zdCBhcHAgPSBuZXcgY2RrLkFwcCgpO1xuXG4vLyBSZWFkIGNvbnRleHQgdmFsdWVzIGZyb20gY2RrLmpzb25cbmNvbnN0IGRpc3RyaWJ1dGlvblByZWZpeCA9IGFwcC5ub2RlLnRyeUdldENvbnRleHQoJ3N0YWdlLWMtbGFtYmRhOmRpc3RyaWJ1dGlvblByZWZpeCcpO1xuY29uc3QgdGFyZ2V0UmVnaW9uID0gYXBwLm5vZGUudHJ5R2V0Q29udGV4dCgnc3RhZ2UtYy1sYW1iZGE6dGFyZ2V0UmVnaW9uJyk7XG5jb25zdCB0YXJnZXRQcm9maWxlID0gYXBwLm5vZGUudHJ5R2V0Q29udGV4dCgnc3RhZ2UtYy1sYW1iZGE6dGFyZ2V0UHJvZmlsZScpO1xuY29uc3QgdGFyZ2V0QWNjb3VudElkID0gYXBwLm5vZGUudHJ5R2V0Q29udGV4dCgnc3RhZ2UtYy1sYW1iZGE6dGFyZ2V0QWNjb3VudElkJyk7XG5jb25zdCB0YXJnZXRWcGNJZCA9IGFwcC5ub2RlLnRyeUdldENvbnRleHQoJ3N0YWdlLWMtbGFtYmRhOnRhcmdldFZwY0lkJyk7XG5jb25zdCBkaXN0cmlidXRpb25JZCA9IGFwcC5ub2RlLnRyeUdldENvbnRleHQoJ3N0YWdlLWMtbGFtYmRhOmRpc3RyaWJ1dGlvbklkJyk7XG5jb25zdCBidWNrZXROYW1lID0gYXBwLm5vZGUudHJ5R2V0Q29udGV4dCgnc3RhZ2UtYy1sYW1iZGE6YnVja2V0TmFtZScpO1xuXG4vLyBWYWxpZGF0ZSByZXF1aXJlZCBjb250ZXh0IHZhbHVlc1xuaWYgKCFkaXN0cmlidXRpb25QcmVmaXggfHwgIXRhcmdldFJlZ2lvbiB8fCAhdGFyZ2V0QWNjb3VudElkIHx8ICF0YXJnZXRWcGNJZCB8fCAhZGlzdHJpYnV0aW9uSWQgfHwgIWJ1Y2tldE5hbWUpIHtcbiAgdGhyb3cgbmV3IEVycm9yKFxuICAgICdNaXNzaW5nIHJlcXVpcmVkIGNvbnRleHQgdmFsdWVzLiBQbGVhc2UgZW5zdXJlIGRpc3RyaWJ1dGlvblByZWZpeCwgdGFyZ2V0UmVnaW9uLCB0YXJnZXRBY2NvdW50SWQsIHRhcmdldFZwY0lkLCBkaXN0cmlidXRpb25JZCwgYW5kIGJ1Y2tldE5hbWUgYXJlIHNldCBpbiBjZGsuanNvbidcbiAgKTtcbn1cblxuLy8gQ3JlYXRlIHRoZSBMYW1iZGEgc3RhY2tcbm5ldyBMYW1iZGFTdGFjayhhcHAsICdTdGFnZUNMYW1iZGFTdGFjaycsIHtcbiAgZGlzdHJpYnV0aW9uUHJlZml4LFxuICB0YXJnZXRSZWdpb24sXG4gIHRhcmdldFZwY0lkLFxuICBkaXN0cmlidXRpb25JZCxcbiAgYnVja2V0TmFtZSxcbiAgZW52OiB7XG4gICAgYWNjb3VudDogdGFyZ2V0QWNjb3VudElkLFxuICAgIHJlZ2lvbjogdGFyZ2V0UmVnaW9uLFxuICB9LFxuICBkZXNjcmlwdGlvbjogYFN0YWdlIEMgTGFtYmRhIEZ1bmN0aW9uIFN0YWNrIC0gJHtkaXN0cmlidXRpb25QcmVmaXh9YCxcbn0pOyAiXX0=