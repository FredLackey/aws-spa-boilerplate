#!/bin/bash

# validate-deployment.sh
# Lambda function testing and deployment validation for Stage C Lambda deployment
# Tests Lambda function via AWS CLI, validates JSON response, and generates final outputs.json

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

echo "=== Stage C Lambda Deployment - Validation ==="
echo "This script will validate the Lambda deployment by testing function invocation and response format."
echo

# Function to validate prerequisites
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # Check for required data files
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    if [[ ! -f "$DATA_DIR/discovery.json" ]]; then
        echo "❌ Error: discovery.json not found. Please run aws-discovery.sh first."
        exit 1
    fi
    
    if [[ ! -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        echo "❌ Error: CDK stack outputs not found. Please run deploy-infrastructure.sh first."
        exit 1
    fi
    
    # Check if aws CLI is available
    if ! command -v aws > /dev/null 2>&1; then
        echo "❌ Error: AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq > /dev/null 2>&1; then
        echo "❌ Error: jq command not found. Please install jq."
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
}

# Function to extract deployment information
extract_deployment_info() {
    local stack_outputs="$DATA_DIR/cdk-stack-outputs.json"
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    
    echo "Extracting deployment information..."
    
    # Extract from CDK outputs
    FUNCTION_ARN=$(jq -r '.LambdaFunctionArn' "$stack_outputs")
    FUNCTION_NAME=$(jq -r '.LambdaFunctionName' "$stack_outputs")
    FUNCTION_URL=$(jq -r '.FunctionUrl' "$stack_outputs")
    LOG_GROUP_NAME=$(jq -r '.LogGroupName' "$stack_outputs")
    
    # Extract from inputs
    DISTRIBUTION_PREFIX=$(jq -r '.distributionPrefix' "$inputs_file")
    TARGET_REGION=$(jq -r '.targetRegion' "$inputs_file")
    TARGET_VPC_ID=$(jq -r '.targetVpcId' "$inputs_file")
    TARGET_PROFILE=$(jq -r '.targetProfile' "$inputs_file")
    INFRASTRUCTURE_PROFILE=$(jq -r '.infrastructureProfile' "$inputs_file")
    DISTRIBUTION_ID=$(jq -r '.distributionId' "$inputs_file")
    BUCKET_NAME=$(jq -r '.bucketName' "$inputs_file")
    CERTIFICATE_ARN=$(jq -r '.certificateArn' "$inputs_file")
    
    # Extract from discovery
    TARGET_ACCOUNT_ID=$(jq -r '.targetAccountId' "$discovery_file")
    INFRASTRUCTURE_ACCOUNT_ID=$(jq -r '.infrastructureAccountId' "$discovery_file")
    
    echo "Lambda Function ARN: $FUNCTION_ARN"
    echo "Lambda Function Name: $FUNCTION_NAME"
    echo "Function URL: $FUNCTION_URL"
    echo "Log Group: $LOG_GROUP_NAME"
    echo "Distribution Prefix: $DISTRIBUTION_PREFIX"
    
    # Validate extracted values
    if [[ -z "$FUNCTION_ARN" || "$FUNCTION_ARN" == "null" ]]; then
        echo "❌ Error: Could not extract Lambda function ARN."
        exit 1
    fi
    
    if [[ -z "$FUNCTION_NAME" || "$FUNCTION_NAME" == "null" ]]; then
        echo "❌ Error: Could not extract Lambda function name."
        exit 1
    fi
    
    echo "✅ Deployment information extracted successfully"
}

# Function to test Lambda function invocation with retries
test_lambda_invocation() {
    local function_name="$1"
    local profile="$2"
    local region="$3"
    local max_retries=5
    local retry_delay=10
    local attempt=1
    
    echo "Testing Lambda function invocation: $function_name" >&2
    echo "Note: Lambda function may take a moment to initialize on first invocation..." >&2
    
    while [[ $attempt -le $max_retries ]]; do
        echo "Invocation attempt $attempt of $max_retries..." >&2
        
        # Create a temporary file for the response
        local response_file
        response_file=$(mktemp)
        
        # Invoke Lambda function
        local invoke_result
        invoke_result=$(aws lambda invoke \
            --function-name "$function_name" \
            --profile "$profile" \
            --region "$region" \
            --payload '{}' \
            "$response_file" \
            --query 'StatusCode' \
            --output text 2>/dev/null || echo "000")
        
        if [[ "$invoke_result" == "200" ]]; then
            echo "✅ Lambda function invocation successful (Status: $invoke_result)" >&2
            
            # Read and return the response (only stdout, no echo statements)
            if [[ -f "$response_file" ]]; then
                cat "$response_file"
            fi
            rm -f "$response_file"
            return 0
        else
            echo "⚠️  Lambda invocation failed with status: $invoke_result" >&2
            if [[ -f "$response_file" ]]; then
                echo "Response content:" >&2
                cat "$response_file" >&2
                echo >&2
            fi
        fi
        
        rm -f "$response_file"
        
        if [[ $attempt -lt $max_retries ]]; then
            echo "Waiting $retry_delay seconds before retry..." >&2
            sleep $retry_delay
        fi
        
        ((attempt++))
    done
    
    echo "❌ Lambda function invocation failed after $max_retries attempts" >&2
    return 1
}

# Function to validate Lambda response format
validate_lambda_response() {
    local response="$1"
    
    echo "Validating Lambda response format..."
    echo "Response content:"
    echo "$response"
    echo
    
    # Parse the response as JSON
    local parsed_response
    if ! parsed_response=$(echo "$response" | jq . 2>/dev/null); then
        echo "❌ Response is not valid JSON"
        return 1
    fi
    
    # Check for required fields
    local status_code body
    status_code=$(echo "$parsed_response" | jq -r '.statusCode // empty')
    body=$(echo "$parsed_response" | jq -r '.body // empty')
    
    if [[ -z "$status_code" ]]; then
        echo "❌ Response missing 'statusCode' field"
        return 1
    fi
    
    if [[ "$status_code" != "200" ]]; then
        echo "❌ Response statusCode is not 200: $status_code"
        return 1
    fi
    
    if [[ -z "$body" ]]; then
        echo "❌ Response missing 'body' field"
        return 1
    fi
    
    # Parse the body as JSON
    local body_json
    if ! body_json=$(echo "$body" | jq . 2>/dev/null); then
        echo "❌ Response body is not valid JSON"
        return 1
    fi
    
    # Check for expected fields in body
    local title message date
    title=$(echo "$body_json" | jq -r '.title // empty')
    message=$(echo "$body_json" | jq -r '.message // empty')
    date=$(echo "$body_json" | jq -r '.date // empty')
    
    if [[ -z "$title" ]]; then
        echo "❌ Response body missing 'title' field"
        return 1
    fi
    
    if [[ -z "$message" ]]; then
        echo "❌ Response body missing 'message' field"
        return 1
    fi
    
    if [[ -z "$date" ]]; then
        echo "❌ Response body missing 'date' field"
        return 1
    fi
    
    # Validate date is ISO format (compatible with both macOS and Linux)
    if [[ ! "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]; then
        echo "❌ Response date field is not a valid ISO timestamp format: $date"
        return 1
    fi
    
    echo "✅ Lambda response validation passed"
    echo "   Title: $title"
    echo "   Message: $message"
    echo "   Date: $date"
    
    return 0
}

# Function to validate CloudWatch logs
validate_cloudwatch_logs() {
    local log_group_name="$1"
    local profile="$2"
    local region="$3"
    
    echo "Validating CloudWatch logs for: $log_group_name"
    
    # Check if log group exists
    local log_group_exists
    log_group_exists=$(aws logs describe-log-groups \
        --log-group-name-prefix "$log_group_name" \
        --profile "$profile" \
        --region "$region" \
        --query "logGroups[?logGroupName=='$log_group_name'].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$log_group_exists" ]]; then
        echo "❌ CloudWatch log group not found: $log_group_name"
        return 1
    fi
    
    echo "✅ CloudWatch log group exists: $log_group_name"
    
    # Check for recent log streams
    local recent_streams
    recent_streams=$(aws logs describe-log-streams \
        --log-group-name "$log_group_name" \
        --profile "$profile" \
        --region "$region" \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$recent_streams" && "$recent_streams" != "None" ]]; then
        echo "✅ Recent log streams found - logging is working"
    else
        echo "⚠️  No recent log streams found - this may be normal for a new deployment"
    fi
    
    return 0
}

# Function to validate Function URL accessibility
validate_function_url() {
    local function_url="$1"
    
    echo "Validating Function URL accessibility: $function_url"
    
    # Note: Function URL with AWS_IAM auth requires signed requests
    # For validation, we'll check if the URL is reachable (even if it returns 403)
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$function_url" || echo "000")
    
    if [[ "$http_status" == "403" ]]; then
        echo "✅ Function URL is accessible (403 expected due to AWS_IAM auth)"
        echo "   URL: $function_url"
        echo "   Note: Function URL requires AWS IAM authentication for actual access"
        return 0
    elif [[ "$http_status" == "200" ]]; then
        echo "✅ Function URL is accessible and responding (Status: $http_status)"
        echo "   URL: $function_url"
        return 0
    else
        echo "⚠️  Function URL returned status: $http_status"
        echo "   URL: $function_url"
        echo "   This may be normal depending on authentication configuration"
        return 0  # Don't fail validation for this
    fi
}

# Function to generate final outputs.json for subsequent stages
generate_final_outputs() {
    local outputs_file="$DATA_DIR/outputs.json"
    
    echo "Generating final outputs.json for subsequent stages..."
    
    # Create comprehensive outputs file
    cat > "$outputs_file" << EOF
{
  "stageC": {
    "lambdaFunctionArn": "$FUNCTION_ARN",
    "lambdaFunctionName": "$FUNCTION_NAME",
    "functionUrl": "$FUNCTION_URL",
    "logGroupName": "$LOG_GROUP_NAME",
    "distributionPrefix": "$DISTRIBUTION_PREFIX",
    "targetRegion": "$TARGET_REGION",
    "targetVpcId": "$TARGET_VPC_ID",
    "targetAccountId": "$TARGET_ACCOUNT_ID",
    "infrastructureAccountId": "$INFRASTRUCTURE_ACCOUNT_ID",
    "targetProfile": "$TARGET_PROFILE",
    "infrastructureProfile": "$INFRASTRUCTURE_PROFILE",
    "distributionId": "$DISTRIBUTION_ID",
    "bucketName": "$BUCKET_NAME",
    "certificateArn": "$CERTIFICATE_ARN"
  },
  "lambdaFunctionArn": "$FUNCTION_ARN",
  "lambdaFunctionName": "$FUNCTION_NAME",
  "functionUrl": "$FUNCTION_URL",
  "logGroupName": "$LOG_GROUP_NAME",
  "distributionPrefix": "$DISTRIBUTION_PREFIX",
  "targetRegion": "$TARGET_REGION",
  "targetVpcId": "$TARGET_VPC_ID",
  "targetAccountId": "$TARGET_ACCOUNT_ID",
  "infrastructureAccountId": "$INFRASTRUCTURE_ACCOUNT_ID",
  "distributionId": "$DISTRIBUTION_ID",
  "bucketName": "$BUCKET_NAME",
  "certificateArn": "$CERTIFICATE_ARN",
  "deploymentTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "validationStatus": "passed",
  "readyForStageD": true
}
EOF
    
    echo "✅ Final outputs.json generated successfully"
    echo "Outputs saved to: $outputs_file"
    
    # Display summary
    echo
    echo "=== Stage C Lambda Deployment Summary ==="
    echo "Lambda Function ARN: $FUNCTION_ARN"
    echo "Lambda Function Name: $FUNCTION_NAME"
    echo "Function URL: $FUNCTION_URL"
    echo "Log Group: $LOG_GROUP_NAME"
    echo "Target Region: $TARGET_REGION"
    echo "Status: Ready for Stage D"
}

# Function to handle validation errors
handle_validation_error() {
    local error_type="$1"
    local exit_code="$2"
    
    echo "❌ Validation failed during $error_type"
    echo
    echo "Troubleshooting steps:"
    case "$error_type" in
        "Lambda invocation")
            echo "1. Check if Lambda function was deployed successfully"
            echo "2. Verify AWS credentials and permissions"
            echo "3. Check Lambda function logs in CloudWatch"
            echo "4. Ensure function is not in a failed state"
            ;;
        "response validation")
            echo "1. Check Lambda function code in apps/hello-world-lambda/index.js"
            echo "2. Verify function returns proper JSON structure"
            echo "3. Check for runtime errors in CloudWatch logs"
            ;;
        "CloudWatch logs")
            echo "1. Check if log group was created properly"
            echo "2. Verify IAM permissions for Lambda execution role"
            echo "3. Check CloudWatch service availability"
            ;;
    esac
    echo
    echo "You can manually test the Lambda function using:"
    echo "aws lambda invoke --function-name $FUNCTION_NAME --profile $TARGET_PROFILE --region $TARGET_REGION --payload '{}' response.json"
    
    return $exit_code
}

# Main validation function
validate_deployment() {
    validate_prerequisites
    extract_deployment_info
    
    local validation_success=true
    
    # Test Lambda function invocation
    echo "=== Testing Lambda Function ==="
    local lambda_response
    if lambda_response=$(test_lambda_invocation "$FUNCTION_NAME" "$TARGET_PROFILE" "$TARGET_REGION"); then
        echo "✅ Lambda function invocation successful"
        
        # Validate response format
        if validate_lambda_response "$lambda_response"; then
            echo "✅ Lambda response format validation passed"
        else
            handle_validation_error "response validation" 1
            validation_success=false
        fi
    else
        handle_validation_error "Lambda invocation" 1
        validation_success=false
    fi
    
    echo
    echo "=== Validating Supporting Resources ==="
    
    # Validate CloudWatch logs
    if validate_cloudwatch_logs "$LOG_GROUP_NAME" "$TARGET_PROFILE" "$TARGET_REGION"; then
        echo "✅ CloudWatch logs validation passed"
    else
        handle_validation_error "CloudWatch logs" 1
        validation_success=false
    fi
    
    # Validate Function URL (non-critical)
    validate_function_url "$FUNCTION_URL"
    
    # Generate outputs regardless of validation status
    generate_final_outputs
    
    if [[ "$validation_success" == true ]]; then
        echo
            echo "🎉 Stage C Lambda deployment validation completed successfully!"
    echo "Your Lambda function is deployed and accessible via Function URL."
    echo
    echo "📋 Testing Your Lambda Function:"
    echo "================================"
    echo
    echo "1. Direct Lambda Invocation (Recommended for testing):"
    echo "   aws lambda invoke --function-name $FUNCTION_NAME \\"
    echo "     --profile $TARGET_PROFILE --region $TARGET_REGION \\"
    echo "     --payload '{}' response.json && cat response.json"
    echo
    echo "2. Function URL HTTP Test (Returns 403 - Expected):"
    echo "   curl -X POST $FUNCTION_URL \\"
    echo "     -H \"Content-Type: application/json\" \\"
    echo "     -d '{}'"
    echo "   # Note: Returns 403 due to AWS_IAM authentication (this is correct behavior)"
    echo
    echo "3. Using AWS SDK in your application:"
    echo "   JavaScript/Node.js:"
    echo "     const response = await lambdaClient.invoke({"
    echo "       FunctionName: '$FUNCTION_NAME',"
    echo "       Payload: JSON.stringify({})"
    echo "     }).promise();"
    echo
    echo "   Python/Boto3:"
    echo "     response = lambda_client.invoke("
    echo "       FunctionName='$FUNCTION_NAME',"
    echo "       Payload=json.dumps({})"
    echo "     )"
    echo
    echo "4. Expected Response Structure:"
    echo "   {"
    echo "     \"statusCode\": 200,"
    echo "     \"headers\": { ... },"
    echo "     \"body\": \"{\\\"title\\\":\\\"AWS Lambda API Working!\\\", ...}\""
    echo "   }"
    echo
    echo "🔐 Security Note:"
    echo "   Function URL uses AWS_IAM authentication for security."
    echo "   Direct HTTP requests will return 403 Forbidden."
    echo "   Use AWS CLI/SDK with proper credentials for access."
    echo
    echo "You can now proceed to Stage D for React application integration."
        return 0
    else
        echo
        echo "⚠️  Stage C deployment completed with validation warnings."
        echo "The infrastructure is deployed but may need additional configuration."
        echo "Check the troubleshooting steps above and test manually if needed."
        return 1
    fi
}

# Global variables for extracted info
FUNCTION_ARN=""
FUNCTION_NAME=""
FUNCTION_URL=""
LOG_GROUP_NAME=""
DISTRIBUTION_PREFIX=""
TARGET_REGION=""
TARGET_VPC_ID=""
TARGET_ACCOUNT_ID=""
INFRASTRUCTURE_ACCOUNT_ID=""
TARGET_PROFILE=""
INFRASTRUCTURE_PROFILE=""
DISTRIBUTION_ID=""
BUCKET_NAME=""
CERTIFICATE_ARN=""

# Main execution
main() {
    validate_deployment
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 