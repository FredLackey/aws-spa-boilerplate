#!/bin/bash

# cleanup-rollback.sh
# Error recovery and rollback procedures for Stage C Lambda deployment
# Cleans up partial deployments and orphaned Lambda resources

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
IAC_DIR="$STAGE_DIR/iac"

echo "=== Stage C Lambda Deployment - Cleanup & Rollback ==="
echo "This script will clean up AWS Lambda resources and handle rollback procedures."
echo

# Function to validate cleanup prerequisites
validate_cleanup_prerequisites() {
    echo "Validating cleanup prerequisites..."
    
    # Check if we have any data files to work with
    if [[ ! -f "$DATA_DIR/inputs.json" ]] && [[ ! -f "$DATA_DIR/discovery.json" ]] && [[ ! -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        echo "⚠️  No deployment data files found. Nothing to clean up."
        return 1
    fi
    
    echo "✅ Cleanup prerequisites validated"
    return 0
}

# Function to extract cleanup information
extract_cleanup_info() {
    echo "Extracting cleanup information from available data files..."
    
    # Initialize variables
    TARGET_PROFILE=""
    INFRASTRUCTURE_PROFILE=""
    DISTRIBUTION_PREFIX=""
    TARGET_REGION=""
    FUNCTION_NAME=""
    FUNCTION_ARN=""
    LOG_GROUP_NAME=""
    EXECUTION_ROLE_NAME=""
    
    # Try to extract from inputs.json
    if [[ -f "$DATA_DIR/inputs.json" ]]; then
        TARGET_PROFILE=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json")
        INFRASTRUCTURE_PROFILE=$(jq -r '.infrastructureProfile // empty' "$DATA_DIR/inputs.json")
        DISTRIBUTION_PREFIX=$(jq -r '.distributionPrefix // empty' "$DATA_DIR/inputs.json")
        TARGET_REGION=$(jq -r '.targetRegion // empty' "$DATA_DIR/inputs.json")
        echo "Found inputs.json with prefix: $DISTRIBUTION_PREFIX"
    fi
    
    # Try to extract from CDK stack outputs
    if [[ -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        FUNCTION_NAME=$(jq -r '.LambdaFunctionName // empty' "$DATA_DIR/cdk-stack-outputs.json")
        FUNCTION_ARN=$(jq -r '.LambdaFunctionArn // empty' "$DATA_DIR/cdk-stack-outputs.json")
        LOG_GROUP_NAME=$(jq -r '.LogGroupName // empty' "$DATA_DIR/cdk-stack-outputs.json")
        echo "Found CDK outputs with function name: $FUNCTION_NAME"
        echo "Found function ARN: $FUNCTION_ARN"
        echo "Found log group: $LOG_GROUP_NAME"
        
        # Derive execution role name from prefix
        if [[ -n "$DISTRIBUTION_PREFIX" ]]; then
            EXECUTION_ROLE_NAME="${DISTRIBUTION_PREFIX}-lambda-execution-role"
        fi
    fi
    
    # Display what we found
    echo "=== Cleanup Information ==="
    echo "Target Profile: ${TARGET_PROFILE:-'Not found'}"
    echo "Infrastructure Profile: ${INFRASTRUCTURE_PROFILE:-'Not found'}"
    echo "Distribution Prefix: ${DISTRIBUTION_PREFIX:-'Not found'}"
    echo "Target Region: ${TARGET_REGION:-'Not found'}"
    echo "Function Name: ${FUNCTION_NAME:-'Not found'}"
    echo "Function ARN: ${FUNCTION_ARN:-'Not found'}"
    echo "Log Group Name: ${LOG_GROUP_NAME:-'Not found'}"
    echo "Execution Role Name: ${EXECUTION_ROLE_NAME:-'Not found'}"
    echo
}

# Function to prompt for cleanup confirmation
prompt_cleanup_confirmation() {
    local cleanup_type="$1"
    
    echo "⚠️  WARNING: This will $cleanup_type"
    echo "This action cannot be undone."
    echo
    echo "Do you want to proceed? (yes/no)"
    read -r confirmation
    
    if [[ "$confirmation" == "yes" ]]; then
        echo "✅ User confirmed cleanup procedure"
        return 0
    else
        echo "❌ Cleanup cancelled by user"
        return 1
    fi
}

# Function to delete Lambda function
cleanup_lambda_function() {
    local function_name="$1"
    local profile="$2"
    local region="$3"
    
    if [[ -z "$function_name" || -z "$profile" ]]; then
        echo "⚠️  Insufficient information to clean up Lambda function"
        return 1
    fi
    
    echo "Cleaning up Lambda function: $function_name"
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$function_name" --profile "$profile" --region "$region" > /dev/null 2>&1; then
        echo "✅ Lambda function does not exist or is already deleted"
        return 0
    fi
    
    # Delete the function
    echo "Deleting Lambda function..."
    if aws lambda delete-function --function-name "$function_name" --profile "$profile" --region "$region" 2>/dev/null; then
        echo "✅ Lambda function deleted successfully"
        return 0
    else
        echo "⚠️  Lambda function deletion failed - it may have been deleted already"
        return 1
    fi
}

# Function to delete IAM execution role
cleanup_iam_role() {
    local role_name="$1"
    local profile="$2"
    
    if [[ -z "$role_name" || -z "$profile" ]]; then
        echo "⚠️  Insufficient information to clean up IAM role"
        return 1
    fi
    
    echo "Cleaning up IAM execution role: $role_name"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" --profile "$profile" > /dev/null 2>&1; then
        echo "✅ IAM role does not exist or is already deleted"
        return 0
    fi
    
    # Detach managed policies first
    echo "Detaching managed policies from role..."
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --profile "$profile" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)
    
    if [[ -n "$attached_policies" ]]; then
        while read -r policy_arn; do
            [[ -z "$policy_arn" ]] && continue
            echo "Detaching policy: $policy_arn"
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" --profile "$profile" 2>/dev/null || true
        done <<< "$attached_policies"
    fi
    
    # Delete inline policies
    echo "Deleting inline policies from role..."
    local inline_policies
    inline_policies=$(aws iam list-role-policies --role-name "$role_name" --profile "$profile" --query 'PolicyNames' --output text 2>/dev/null || true)
    
    if [[ -n "$inline_policies" ]]; then
        while read -r policy_name; do
            [[ -z "$policy_name" ]] && continue
            echo "Deleting inline policy: $policy_name"
            aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" --profile "$profile" 2>/dev/null || true
        done <<< "$inline_policies"
    fi
    
    # Delete the role
    echo "Deleting IAM role..."
    if aws iam delete-role --role-name "$role_name" --profile "$profile" 2>/dev/null; then
        echo "✅ IAM role deleted successfully"
        return 0
    else
        echo "⚠️  IAM role deletion failed - it may have been deleted already"
        return 1
    fi
}

# Function to delete CloudWatch log group
cleanup_cloudwatch_log_group() {
    local log_group_name="$1"
    local profile="$2"
    local region="$3"
    
    if [[ -z "$log_group_name" || -z "$profile" ]]; then
        echo "⚠️  Insufficient information to clean up CloudWatch log group"
        return 1
    fi
    
    echo "Cleaning up CloudWatch log group: $log_group_name"
    
    # Check if log group exists
    if ! aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --profile "$profile" --region "$region" --query "logGroups[?logGroupName=='$log_group_name']" --output text 2>/dev/null | grep -q "$log_group_name"; then
        echo "✅ CloudWatch log group does not exist or is already deleted"
        return 0
    fi
    
    # Delete the log group
    echo "Deleting CloudWatch log group..."
    if aws logs delete-log-group --log-group-name "$log_group_name" --profile "$profile" --region "$region" 2>/dev/null; then
        echo "✅ CloudWatch log group deleted successfully"
        return 0
    else
        echo "⚠️  CloudWatch log group deletion failed - it may have been deleted already"
        return 1
    fi
}

# Function to destroy CDK stack
cleanup_cdk_stack() {
    local profile="$1"
    
    if [[ -z "$profile" ]]; then
        echo "⚠️  No AWS profile available for CDK cleanup"
        return 1
    fi
    
    echo "Cleaning up CDK stack..."
    
    # Change to IAC directory
    if [[ ! -d "$IAC_DIR" ]]; then
        echo "⚠️  IAC directory not found, skipping CDK cleanup"
        return 1
    fi
    
    cd "$IAC_DIR"
    
    # Check if CDK app exists
    if [[ ! -f "app.ts" ]] && [[ ! -f "cdk.json" ]]; then
        echo "⚠️  CDK app not found, skipping CDK cleanup"
        return 1
    fi
    
    # Install dependencies if needed
    if [[ ! -d "node_modules" ]]; then
        echo "Installing CDK dependencies for cleanup..."
        npm install > /dev/null 2>&1 || true
    fi
    
    # List stacks to see what exists
    echo "Listing CDK stacks..."
    local stacks
    stacks=$(npx cdk list --profile "$profile" 2>/dev/null || echo "")
    
    if [[ -z "$stacks" ]]; then
        echo "✅ No CDK stacks found to clean up"
        return 0
    fi
    
    echo "Found CDK stacks: $stacks"
    
    # Destroy all stacks
    echo "Destroying CDK stacks..."
    if npx cdk destroy --all --force --profile "$profile" 2>/dev/null; then
        echo "✅ CDK stack(s) destroyed successfully"
        return 0
    else
        echo "⚠️  CDK stack destruction failed or was partial"
        return 1
    fi
}

# Function to clean up data files
cleanup_data_files() {
    echo "Cleaning up deployment data files..."
    
    local files_to_remove=(
        "$DATA_DIR/inputs.json"
        "$DATA_DIR/discovery.json"
        "$DATA_DIR/cdk-outputs.json"
        "$DATA_DIR/cdk-stack-outputs.json"
        "$DATA_DIR/outputs.json"
    )
    
    local removed_count=0
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            echo "Removed: $(basename "$file")"
            ((removed_count++))
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        echo "✅ Cleaned up $removed_count data files"
    else
        echo "✅ No data files to clean up"
    fi
}

# Function to verify complete cleanup
verify_cleanup() {
    local function_name="$1"
    local role_name="$2"
    local log_group_name="$3"
    local profile="$4"
    local region="$5"
    
    echo "Verifying cleanup completion..."
    
    local cleanup_complete=true
    
    # Check Lambda function
    if [[ -n "$function_name" && -n "$profile" && -n "$region" ]]; then
        if aws lambda get-function --function-name "$function_name" --profile "$profile" --region "$region" > /dev/null 2>&1; then
            echo "⚠️  Lambda function still exists"
            cleanup_complete=false
        else
            echo "✅ Lambda function verified as deleted"
        fi
    fi
    
    # Check IAM role
    if [[ -n "$role_name" && -n "$profile" ]]; then
        if aws iam get-role --role-name "$role_name" --profile "$profile" > /dev/null 2>&1; then
            echo "⚠️  IAM execution role still exists"
            cleanup_complete=false
        else
            echo "✅ IAM execution role verified as deleted"
        fi
    fi
    
    # Check CloudWatch log group
    if [[ -n "$log_group_name" && -n "$profile" && -n "$region" ]]; then
        if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --profile "$profile" --region "$region" --query "logGroups[?logGroupName=='$log_group_name']" --output text 2>/dev/null | grep -q "$log_group_name"; then
            echo "⚠️  CloudWatch log group still exists"
            cleanup_complete=false
        else
            echo "✅ CloudWatch log group verified as deleted"
        fi
    fi
    
    # Check data files
    local remaining_files=0
    for file in "$DATA_DIR"/*.json; do
        if [[ -f "$file" ]]; then
            ((remaining_files++))
        fi
    done
    
    if [[ $remaining_files -eq 0 ]]; then
        echo "✅ All deployment data files cleaned up"
    else
        echo "⚠️  $remaining_files deployment data files remain"
    fi
    
    if [[ "$cleanup_complete" == true ]]; then
        echo "✅ Cleanup verification completed - no resources remain"
        return 0
    else
        echo "⚠️  Cleanup verification found remaining resources"
        return 1
    fi
}

# Function to provide recovery instructions
provide_recovery_instructions() {
    echo
    echo "=== Recovery Instructions ==="
    echo "If you need to restart Stage C deployment:"
    echo "1. Ensure all resources have been cleaned up"
    echo "2. Run ./gather-inputs.sh to collect deployment parameters"
    echo "3. Run ./aws-discovery.sh to validate AWS access"
    echo "4. Run ./deploy-infrastructure.sh to redeploy Lambda infrastructure"
    echo "5. Run ./validate-deployment.sh to test the Lambda function"
    echo
    echo "If cleanup was partial:"
    echo "1. Check AWS Console for remaining Lambda functions"
    echo "2. Check AWS Console for remaining IAM roles"
    echo "3. Check AWS Console for remaining CloudWatch log groups"
    echo "4. Manually clean up any remaining resources if needed"
    echo
}

# Main cleanup function with different modes
cleanup_deployment() {
    local cleanup_mode="${1:-full}"
    
    case "$cleanup_mode" in
        "full")
            if ! prompt_cleanup_confirmation "delete ALL Stage C Lambda resources and data files"; then
                exit 1
            fi
            ;;
        "resources")
            if ! prompt_cleanup_confirmation "delete AWS Lambda resources but keep data files"; then
                exit 1
            fi
            ;;
        "data")
            if ! prompt_cleanup_confirmation "delete data files but keep AWS Lambda resources"; then
                exit 1
            fi
            ;;
        *)
            echo "❌ Invalid cleanup mode: $cleanup_mode"
            echo "Valid modes: full, resources, data"
            exit 1
            ;;
    esac
    
    # Clean up AWS resources
    if [[ "$cleanup_mode" == "full" || "$cleanup_mode" == "resources" ]]; then
        echo "Starting AWS resource cleanup..."
        
        # Try CDK cleanup first (usually handles everything)
        if [[ -n "$TARGET_PROFILE" ]]; then
            cleanup_cdk_stack "$TARGET_PROFILE"
        fi
        
        # Manual cleanup as fallback
        if [[ -n "$FUNCTION_NAME" && -n "$TARGET_PROFILE" && -n "$TARGET_REGION" ]]; then
            cleanup_lambda_function "$FUNCTION_NAME" "$TARGET_PROFILE" "$TARGET_REGION"
        fi
        
        if [[ -n "$EXECUTION_ROLE_NAME" && -n "$TARGET_PROFILE" ]]; then
            cleanup_iam_role "$EXECUTION_ROLE_NAME" "$TARGET_PROFILE"
        fi
        
        if [[ -n "$LOG_GROUP_NAME" && -n "$TARGET_PROFILE" && -n "$TARGET_REGION" ]]; then
            cleanup_cloudwatch_log_group "$LOG_GROUP_NAME" "$TARGET_PROFILE" "$TARGET_REGION"
        fi
    fi
    
    # Clean up data files
    if [[ "$cleanup_mode" == "full" || "$cleanup_mode" == "data" ]]; then
        cleanup_data_files
    fi
    
    # Verify cleanup
    if [[ "$cleanup_mode" == "full" ]]; then
        if verify_cleanup "$FUNCTION_NAME" "$EXECUTION_ROLE_NAME" "$LOG_GROUP_NAME" "$TARGET_PROFILE" "$TARGET_REGION"; then
            echo "🎉 Complete cleanup verification passed!"
        else
            echo "⚠️  Cleanup completed with some remaining items"
        fi
    fi
    
    provide_recovery_instructions
}

# Global variables for cleanup info
TARGET_PROFILE=""
INFRASTRUCTURE_PROFILE=""
DISTRIBUTION_PREFIX=""
TARGET_REGION=""
FUNCTION_NAME=""
FUNCTION_ARN=""
LOG_GROUP_NAME=""
EXECUTION_ROLE_NAME=""

# Main execution
main() {
    local cleanup_mode="${1:-full}"
    
    echo "Cleanup mode: $cleanup_mode"
    echo
    
    if ! validate_cleanup_prerequisites; then
        echo "Nothing to clean up. Exiting."
        exit 0
    fi
    
    extract_cleanup_info
    cleanup_deployment "$cleanup_mode"
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 