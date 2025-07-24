#!/bin/bash

# status-c.sh
# Status checking script for Stage C Lambda deployment
# Checks the health and status of deployed Lambda resources

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

echo "=== Stage C Lambda Deployment - Status Check ==="
echo "This script will check the status and health of your Lambda deployment."
echo

# Function to validate prerequisites
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # Check for required data files
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found. Lambda deployment may not be started."
        return 1
    fi
    
    if [[ ! -f "$DATA_DIR/outputs.json" ]]; then
        echo "⚠️  Warning: outputs.json not found. Deployment may not be complete."
        echo "   Will check what's available from other data files."
    fi
    
    # Check if aws CLI is available
    if ! command -v aws > /dev/null 2>&1; then
        echo "❌ Error: AWS CLI not found. Please install AWS CLI."
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq > /dev/null 2>&1; then
        echo "❌ Error: jq command not found. Please install jq."
        return 1
    fi
    
    echo "✅ Prerequisites validated"
    return 0
}

# Function to extract deployment information
extract_deployment_info() {
    echo "Extracting deployment information..."
    
    # Extract from inputs
    TARGET_PROFILE=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json")
    TARGET_REGION=$(jq -r '.targetRegion // empty' "$DATA_DIR/inputs.json")
    DISTRIBUTION_PREFIX=$(jq -r '.distributionPrefix // empty' "$DATA_DIR/inputs.json")
    
    # Try to extract from outputs if available
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        FUNCTION_NAME=$(jq -r '.lambdaFunctionName // empty' "$DATA_DIR/outputs.json")
        FUNCTION_ARN=$(jq -r '.lambdaFunctionArn // empty' "$DATA_DIR/outputs.json")
        FUNCTION_URL=$(jq -r '.functionUrl // empty' "$DATA_DIR/outputs.json")
        LOG_GROUP_NAME=$(jq -r '.logGroupName // empty' "$DATA_DIR/outputs.json")
    else
        # Try to extract from CDK stack outputs
        if [[ -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
            FUNCTION_NAME=$(jq -r '.LambdaFunctionName // empty' "$DATA_DIR/cdk-stack-outputs.json")
            FUNCTION_ARN=$(jq -r '.LambdaFunctionArn // empty' "$DATA_DIR/cdk-stack-outputs.json")
            FUNCTION_URL=$(jq -r '.FunctionUrl // empty' "$DATA_DIR/cdk-stack-outputs.json")
            LOG_GROUP_NAME=$(jq -r '.LogGroupName // empty' "$DATA_DIR/cdk-stack-outputs.json")
        else
            FUNCTION_NAME=""
            FUNCTION_ARN=""
            FUNCTION_URL=""
            LOG_GROUP_NAME=""
        fi
    fi
    
    echo "Target Profile: $TARGET_PROFILE"
    echo "Target Region: $TARGET_REGION"
    echo "Distribution Prefix: $DISTRIBUTION_PREFIX"
    echo "Function Name: ${FUNCTION_NAME:-'Not available'}"
    echo "Function ARN: ${FUNCTION_ARN:-'Not available'}"
    echo
}

# Function to check Lambda function status
check_lambda_function_status() {
    if [[ -z "$FUNCTION_NAME" || -z "$TARGET_PROFILE" || -z "$TARGET_REGION" ]]; then
        echo "⚠️  Insufficient information to check Lambda function status"
        return 1
    fi
    
    echo "🔍 Checking Lambda function status..."
    echo "Function Name: $FUNCTION_NAME"
    
    # Get function configuration
    local function_config
    function_config=$(aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --output json 2>/dev/null || echo '{}')
    
    if [[ "$function_config" == "{}" ]]; then
        echo "❌ Lambda function not found or inaccessible"
        return 1
    fi
    
    # Extract function details
    local state last_update_status runtime memory timeout
    state=$(echo "$function_config" | jq -r '.Configuration.State // "Unknown"')
    last_update_status=$(echo "$function_config" | jq -r '.Configuration.LastUpdateStatus // "Unknown"')
    runtime=$(echo "$function_config" | jq -r '.Configuration.Runtime // "Unknown"')
    memory=$(echo "$function_config" | jq -r '.Configuration.MemorySize // "Unknown"')
    timeout=$(echo "$function_config" | jq -r '.Configuration.Timeout // "Unknown"')
    
    echo "   State: $state"
    echo "   Last Update Status: $last_update_status"
    echo "   Runtime: $runtime"
    echo "   Memory: ${memory}MB"
    echo "   Timeout: ${timeout}s"
    
    # Check function health
    if [[ "$state" == "Active" && "$last_update_status" == "Successful" ]]; then
        echo "✅ Lambda function is healthy and active"
        return 0
    elif [[ "$state" == "Pending" ]]; then
        echo "⚠️  Lambda function is in pending state (may be updating)"
        return 1
    else
        echo "❌ Lambda function is not in a healthy state"
        return 1
    fi
}

# Function to check Function URL status
check_function_url_status() {
    if [[ -z "$FUNCTION_NAME" || -z "$TARGET_PROFILE" || -z "$TARGET_REGION" ]]; then
        echo "⚠️  Insufficient information to check Function URL status"
        return 1
    fi
    
    echo "🔍 Checking Function URL configuration..."
    
    # Get Function URL configuration
    local url_config
    url_config=$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --output json 2>/dev/null || echo '{}')
    
    if [[ "$url_config" == "{}" ]]; then
        echo "❌ Function URL not configured or inaccessible"
        return 1
    fi
    
    # Extract URL details
    local function_url auth_type creation_time
    function_url=$(echo "$url_config" | jq -r '.FunctionUrl // "Unknown"')
    auth_type=$(echo "$url_config" | jq -r '.AuthType // "Unknown"')
    creation_time=$(echo "$url_config" | jq -r '.CreationTime // "Unknown"')
    
    echo "   Function URL: $function_url"
    echo "   Auth Type: $auth_type"
    echo "   Created: $creation_time"
    
    # Test URL accessibility (expect 403 for AWS_IAM auth)
    if [[ "$function_url" != "Unknown" ]]; then
        local http_status
        http_status=$(curl -s -o /dev/null -w "%{http_code}" "$function_url" || echo "000")
        
        if [[ "$http_status" == "403" && "$auth_type" == "AWS_IAM" ]]; then
            echo "✅ Function URL is accessible (403 expected for AWS_IAM auth)"
        elif [[ "$http_status" == "200" ]]; then
            echo "✅ Function URL is accessible and responding"
        else
            echo "⚠️  Function URL returned status: $http_status"
        fi
    fi
    
    echo "✅ Function URL is configured"
    return 0
}

# Function to check CloudWatch logs status
check_cloudwatch_logs_status() {
    if [[ -z "$LOG_GROUP_NAME" || -z "$TARGET_PROFILE" || -z "$TARGET_REGION" ]]; then
        echo "⚠️  Insufficient information to check CloudWatch logs status"
        return 1
    fi
    
    echo "🔍 Checking CloudWatch logs status..."
    echo "Log Group: $LOG_GROUP_NAME"
    
    # Check if log group exists
    local log_group_info
    log_group_info=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output json 2>/dev/null || echo '[]')
    
    if [[ "$log_group_info" == "[]" ]]; then
        echo "❌ CloudWatch log group not found"
        return 1
    fi
    
    # Extract log group details
    local retention_days creation_time stored_bytes
    retention_days=$(echo "$log_group_info" | jq -r '.[0].retentionInDays // "Never expire"')
    creation_time=$(echo "$log_group_info" | jq -r '.[0].creationTime // "Unknown"')
    stored_bytes=$(echo "$log_group_info" | jq -r '.[0].storedBytes // 0')
    
    echo "   Retention: $retention_days days"
    echo "   Created: $(date -d "@$((creation_time/1000))" 2>/dev/null || echo "Unknown")"
    echo "   Stored Data: ${stored_bytes} bytes"
    
    # Check for recent log streams
    local recent_streams
    recent_streams=$(aws logs describe-log-streams --log-group-name "$LOG_GROUP_NAME" --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --order-by LastEventTime --descending --max-items 3 --query 'logStreams[].{name:logStreamName,lastEvent:lastEventTime}' --output json 2>/dev/null || echo '[]')
    
    local stream_count
    stream_count=$(echo "$recent_streams" | jq '. | length')
    
    if [[ "$stream_count" -gt 0 ]]; then
        echo "   Recent Log Streams: $stream_count"
        echo "$recent_streams" | jq -r '.[] | "     - \(.name) (last event: \(.lastEvent // "None"))"' | head -3
        echo "✅ CloudWatch logs are active"
    else
        echo "   No recent log streams found"
        echo "⚠️  CloudWatch logs exist but no recent activity"
    fi
    
    return 0
}

# Function to check IAM execution role status
check_iam_role_status() {
    if [[ -z "$DISTRIBUTION_PREFIX" || -z "$TARGET_PROFILE" ]]; then
        echo "⚠️  Insufficient information to check IAM role status"
        return 1
    fi
    
    local role_name="${DISTRIBUTION_PREFIX}-lambda-execution-role"
    
    echo "🔍 Checking IAM execution role status..."
    echo "Role Name: $role_name"
    
    # Get role information
    local role_info
    role_info=$(aws iam get-role --role-name "$role_name" --profile "$TARGET_PROFILE" --output json 2>/dev/null || echo '{}')
    
    if [[ "$role_info" == "{}" ]]; then
        echo "❌ IAM execution role not found"
        return 1
    fi
    
    # Extract role details
    local role_arn creation_date
    role_arn=$(echo "$role_info" | jq -r '.Role.Arn // "Unknown"')
    creation_date=$(echo "$role_info" | jq -r '.Role.CreateDate // "Unknown"')
    
    echo "   Role ARN: $role_arn"
    echo "   Created: $creation_date"
    
    # Check attached policies
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --profile "$TARGET_PROFILE" --query 'AttachedPolicies[].PolicyName' --output json 2>/dev/null || echo '[]')
    
    local policy_count
    policy_count=$(echo "$attached_policies" | jq '. | length')
    
    if [[ "$policy_count" -gt 0 ]]; then
        echo "   Attached Policies: $policy_count"
        echo "$attached_policies" | jq -r '.[] | "     - \(.)"'
    fi
    
    echo "✅ IAM execution role is configured"
    return 0
}

# Function to test Lambda function invocation
test_lambda_invocation() {
    if [[ -z "$FUNCTION_NAME" || -z "$TARGET_PROFILE" || -z "$TARGET_REGION" ]]; then
        echo "⚠️  Insufficient information to test Lambda invocation"
        return 1
    fi
    
    echo "🔍 Testing Lambda function invocation..."
    
    # Create a temporary file for the response
    local response_file
    response_file=$(mktemp)
    
    # Invoke Lambda function
    local invoke_result
    invoke_result=$(aws lambda invoke --function-name "$FUNCTION_NAME" --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --payload '{}' "$response_file" --query 'StatusCode' --output text 2>/dev/null || echo "000")
    
    if [[ "$invoke_result" == "200" ]]; then
        echo "✅ Lambda function invocation successful"
        
        # Show response preview
        if [[ -f "$response_file" ]]; then
            echo "   Response preview:"
            local response_content
            response_content=$(cat "$response_file" | jq . 2>/dev/null || cat "$response_file")
            echo "$response_content" | head -5 | sed 's/^/     /'
        fi
        
        rm -f "$response_file"
        return 0
    else
        echo "❌ Lambda function invocation failed (Status: $invoke_result)"
        if [[ -f "$response_file" ]]; then
            echo "   Error details:"
            cat "$response_file" | head -3 | sed 's/^/     /'
        fi
        rm -f "$response_file"
        return 1
    fi
}

# Function to display overall status summary
display_status_summary() {
    echo
    echo "🎯 Stage C Lambda Deployment Status Summary"
    echo "==========================================="
    
    local overall_status="✅ HEALTHY"
    local issues=()
    
    # Check Lambda function
    if ! check_lambda_function_status; then
        overall_status="⚠️  ISSUES DETECTED"
        issues+=("Lambda function status")
    fi
    
    echo
    
    # Check Function URL
    if ! check_function_url_status; then
        overall_status="⚠️  ISSUES DETECTED"
        issues+=("Function URL configuration")
    fi
    
    echo
    
    # Check CloudWatch logs
    if ! check_cloudwatch_logs_status; then
        overall_status="⚠️  ISSUES DETECTED"
        issues+=("CloudWatch logs")
    fi
    
    echo
    
    # Check IAM role
    if ! check_iam_role_status; then
        overall_status="⚠️  ISSUES DETECTED"
        issues+=("IAM execution role")
    fi
    
    echo
    
    # Test function invocation
    if ! test_lambda_invocation; then
        overall_status="⚠️  ISSUES DETECTED"
        issues+=("Lambda function invocation")
    fi
    
    echo
    echo "Overall Status: $overall_status"
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        echo
        echo "Issues detected in:"
        printf "  - %s\n" "${issues[@]}"
        echo
        echo "Recommendations:"
        echo "  1. Check AWS Console for detailed error messages"
        echo "  2. Review CloudWatch logs for function errors"
        echo "  3. Verify AWS credentials and permissions"
        echo "  4. Re-run deployment if issues persist: ./go-c.sh"
    else
        echo
        echo "🎉 All Lambda deployment components are healthy!"
        echo
        echo "Your Lambda function is ready for use:"
        if [[ -n "$FUNCTION_URL" ]]; then
            echo "  Function URL: $FUNCTION_URL"
        fi
        if [[ -n "$FUNCTION_NAME" ]]; then
            echo "  Function Name: $FUNCTION_NAME"
        fi
    fi
}

# Global variables for extracted info
TARGET_PROFILE=""
TARGET_REGION=""
DISTRIBUTION_PREFIX=""
FUNCTION_NAME=""
FUNCTION_ARN=""
FUNCTION_URL=""
LOG_GROUP_NAME=""

# Main execution
main() {
    if ! validate_prerequisites; then
        echo "Cannot perform status check due to missing prerequisites."
        exit 1
    fi
    
    extract_deployment_info
    display_status_summary
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 