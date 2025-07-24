# Stage C Lambda Function Testing Guide

This guide explains how to test your deployed Lambda function with AWS_IAM authentication.

## Quick Test

The simplest way to test your Lambda function:

```bash
aws lambda invoke --function-name hellospa-api \
  --profile yourawsprofile-sandbox --region us-east-1 \
  --payload '{}' response.json && cat response.json
```

## Testing Methods

### 1. Direct Lambda Invocation (Recommended)

**Benefits**: Simple, direct, works with any AWS CLI setup
**Use case**: Development testing, validation, debugging

```bash
# Basic invocation
aws lambda invoke \
  --function-name <FUNCTION_NAME> \
  --profile <AWS_PROFILE> \
  --region <AWS_REGION> \
  --payload '{}' \
  response.json

# View response
cat response.json

# One-liner for quick testing
aws lambda invoke --function-name <FUNCTION_NAME> --profile <AWS_PROFILE> --region <AWS_REGION> --payload '{}' response.json && cat response.json
```

### 2. Function URL with HTTP Requests (Advanced)

**Benefits**: Tests the actual HTTP endpoint
**Use case**: Validating Function URL configuration
**Note**: Requires AWS signature v4 signing due to AWS_IAM authentication

```bash
# Function URL requires AWS signature v4 signing - not straightforward with curl
# For testing Function URLs with IAM auth, it's easier to use direct Lambda invocation
# or AWS SDK. Direct HTTP requests will return 403 without proper signing.

# Example of what WON'T work (will return 403):
# curl -X POST <FUNCTION_URL> -d '{}'

# For Function URL testing, use the direct Lambda invocation method instead
```

### 3. Programmatic Access with AWS SDK

#### JavaScript/Node.js

```javascript
const { LambdaClient, InvokeCommand } = require('@aws-sdk/client-lambda');

const client = new LambdaClient({
  region: 'us-east-1',
  credentials: {
    // Use your AWS credentials here
  }
});

async function testLambda() {
  try {
    const command = new InvokeCommand({
      FunctionName: 'hellospa-api',
      Payload: JSON.stringify({})
    });
    
    const response = await client.send(command);
    const payload = JSON.parse(new TextDecoder().decode(response.Payload));
    console.log('Lambda Response:', payload);
  } catch (error) {
    console.error('Error:', error);
  }
}

testLambda();
```

#### Python/Boto3

```python
import boto3
import json

def test_lambda():
    client = boto3.client('lambda', region_name='us-east-1')
    
    try:
        response = client.invoke(
            FunctionName='hellospa-api',
            Payload=json.dumps({})
        )
        
        payload = json.loads(response['Payload'].read())
        print('Lambda Response:', payload)
        
    except Exception as error:
        print('Error:', error)

test_lambda()
```

#### cURL with AWS Signature v4 (Advanced)

```bash
# Function URL with IAM auth requires complex AWS signature v4 signing
# This is NOT recommended for testing - use direct Lambda invocation instead

# Example that will NOT work without proper signing:
curl -X POST https://your-function-url.lambda-url.region.on.aws/ \
  -H "Content-Type: application/json" \
  -d '{}'
# Returns: 403 Forbidden (expected with AWS_IAM auth)

# For testing, use: aws lambda invoke (recommended)
```

## Expected Response Structure

Your Lambda function should return:

```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST",
    "Access-Control-Allow-Headers": "Content-Type"
  },
  "body": "{\"title\":\"AWS Lambda API Working!\",\"message\":\"If you can read this message, your Lambda function is deployed and functioning correctly. You can now proceed to Stage D to deploy the React application.\",\"date\":\"2025-01-24T12:00:00.000Z\"}"
}
```

The `body` field contains a JSON string that, when parsed, has:

```json
{
  "title": "AWS Lambda API Working!",
  "message": "If you can read this message, your Lambda function is deployed and functioning correctly. You can now proceed to Stage D to deploy the React application.",
  "date": "2025-01-24T12:00:00.000Z"
}
```

## Troubleshooting

### 403 Forbidden Errors

If you get 403 errors when testing the Function URL directly:

**This is expected behavior!** The Function URL uses AWS_IAM authentication.

**Solutions**:
1. Use `aws lambda invoke` instead (recommended)
2. Use AWS SDK with proper credentials
3. Use `aws lambda invoke-url` with proper signing

### Invalid Credentials

If you get credential errors:

1. Check your AWS profile configuration:
   ```bash
   aws sts get-caller-identity --profile <YOUR_PROFILE>
   ```

2. Ensure your profile has Lambda invoke permissions
3. Check if SSO token needs refresh (if using AWS SSO)

### Function Not Found

If the function can't be found:

1. Verify the function name and region
2. Check your AWS profile has access to the correct account
3. Ensure the function was deployed successfully

## Security Notes

🔐 **AWS_IAM Authentication**: The Function URL requires proper AWS credentials and request signing. This provides security but requires proper setup for testing.

🚫 **No Public Access**: Direct HTTP requests (curl, browser) will return 403 Forbidden.

✅ **Recommended**: Use AWS CLI or SDK for all testing and application integration.

## Integration with Stage D

When proceeding to Stage D (React application), the React app will need to:

1. Use AWS SDK for JavaScript
2. Configure proper AWS credentials
3. Use the Lambda `invoke` API or properly signed Function URL requests
4. Handle the nested JSON response structure (parse the `body` field)

## Quick Validation Checklist

- [ ] Function responds to `aws lambda invoke`
- [ ] Response has correct structure (statusCode, headers, body)
- [ ] Body contains valid JSON with title, message, and date
- [ ] Date is in ISO 8601 format
- [ ] Function URL returns 403 for unsigned requests (expected)
- [ ] CloudWatch logs show invocation records 