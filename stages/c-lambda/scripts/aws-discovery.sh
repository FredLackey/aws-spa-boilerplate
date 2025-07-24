#!/bin/bash

# aws-discovery.sh
# AWS account discovery and resource validation for Stage C Lambda deployment
# Validates AWS profiles, captures account IDs, and checks for Lambda resource conflicts

set -euo pipefail

# Script directory and data directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

echo "=== Stage C Lambda Deployment - AWS Discovery ==="
echo "This script will validate AWS profiles and discover existing Lambda resources."
echo

# Function to validate AWS profile credentials
validate_aws_credentials() {
    local profile="$1"
    local profile_type="$2"
    
    echo "Validating $profile_type profile: $profile"
    
    # Test AWS credentials by getting caller identity
    if ! aws sts get-caller-identity --profile "$profile" --output json > /dev/null 2>&1; then
        echo "❌ Error: Cannot authenticate with AWS profile '$profile'"
        echo "Please check your AWS credentials and try again."
        return 1
    fi
    
    echo "✅ AWS profile '$profile' credentials validated"
    return 0
}

# Function to get AWS account ID
get_account_id() {
    local profile="$1"
    aws sts get-caller-identity --profile "$profile" --query 'Account' --output text
}

# Function to check for existing Lambda functions with same prefix
check_lambda_conflicts() {
    local profile="$1"
    local prefix="$2"
    local region="$3"
    
    echo "Checking for existing Lambda functions with prefix '$prefix' in region '$region'..."
    
    # Get list of Lambda functions
    local functions
    functions=$(aws lambda list-functions --profile "$profile" --region "$region" --query 'Functions[].{Name:FunctionName,Arn:FunctionArn}' --output json 2>/dev/null || echo "[]")
    
    # Check if any function names contain our prefix
    local conflicts
    conflicts=$(echo "$functions" | jq -r --arg prefix "$prefix" '.[] | select(.Name and (.Name | contains($prefix))) | .Name' 2>/dev/null || true)
    
    if [[ -n "$conflicts" ]]; then
        echo "⚠️  Found existing Lambda functions with prefix '$prefix':"
        echo "$conflicts"
        return 1
    else
        echo "✅ No Lambda function conflicts found"
        return 0
    fi
}

# Function to check for existing IAM roles with same prefix
check_iam_role_conflicts() {
    local profile="$1"
    local prefix="$2"
    
    echo "Checking for existing IAM roles with prefix '$prefix'..."
    
    # List IAM roles and filter by prefix
    local roles
    roles=$(aws iam list-roles --profile "$profile" --query "Roles[?starts_with(RoleName, '${prefix}')].RoleName" --output text 2>/dev/null || true)
    
    if [[ -n "$roles" ]]; then
        echo "⚠️  Found existing IAM roles with prefix '$prefix':"
        echo "$roles"
        return 1
    else
        echo "✅ No IAM role conflicts found"
        return 0
    fi
}

# Function to check for existing CloudWatch log groups with same prefix
check_cloudwatch_log_conflicts() {
    local profile="$1"
    local prefix="$2"
    local region="$3"
    
    echo "Checking for existing CloudWatch log groups with prefix '$prefix' in region '$region'..."
    
    # List log groups and filter by prefix
    local log_groups
    log_groups=$(aws logs describe-log-groups --profile "$profile" --region "$region" --log-group-name-prefix "/aws/lambda/${prefix}" --query 'logGroups[].logGroupName' --output text 2>/dev/null || true)
    
    if [[ -n "$log_groups" ]]; then
        echo "⚠️  Found existing CloudWatch log groups with prefix '$prefix':"
        echo "$log_groups"
        return 1
    else
        echo "✅ No CloudWatch log group conflicts found"
        return 0
    fi
}

# Function to check region availability and Lambda service access
check_lambda_service_availability() {
    local profile="$1"
    local region="$2"
    
    echo "Validating Lambda service availability in region '$region'..."
    
    # Test region and Lambda service by listing functions (simple operation)
    if ! aws lambda list-functions --profile "$profile" --region "$region" --max-items 1 > /dev/null 2>&1; then
        echo "❌ Error: Lambda service is not accessible in region '$region' with profile '$profile'"
        return 1
    fi
    
    echo "✅ Lambda service is accessible in region '$region'"
    return 0
}

# Function to discover Lambda service limits and quotas
discover_lambda_quotas() {
    local profile="$1"
    local region="$2"
    
    echo "Discovering Lambda service quotas in region '$region'..."
    
    # Get account settings for Lambda
    local account_settings
    account_settings=$(aws lambda get-account-settings --profile "$profile" --region "$region" --output json 2>/dev/null || echo '{}')
    
    if [[ "$account_settings" != "{}" ]]; then
        local total_code_size concurrent_executions
        total_code_size=$(echo "$account_settings" | jq -r '.AccountLimit.TotalCodeSize // "Unknown"')
        concurrent_executions=$(echo "$account_settings" | jq -r '.AccountLimit.ConcurrentExecutions // "Unknown"')
        
        echo "✅ Lambda account limits discovered:"
        echo "   Total Code Size Limit: $total_code_size bytes"
        echo "   Concurrent Executions Limit: $concurrent_executions"
    else
        echo "⚠️  Could not retrieve Lambda account settings (may not have permissions)"
    fi
    
    return 0
}

# Function to prompt for overwrite confirmation
prompt_overwrite_confirmation() {
    local resource_type="$1"
    
    echo
    echo "⚠️  Existing $resource_type resources found with the same prefix."
    echo "Proceeding will potentially overwrite or conflict with these resources."
    echo "Do you want to continue? (y/n)"
    read -r confirmation
    
    if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
        echo "Deployment cancelled due to resource conflicts."
        echo "Please choose a different prefix or clean up existing resources."
        exit 1
    fi
    
    echo "✅ User confirmed to proceed despite conflicts"
}

# Function to discover AWS account information
discover_aws_info() {
    local inputs_file="$DATA_DIR/inputs.json"
    
    # Check if inputs file exists
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    # Read inputs from JSON file
    local infrastructure_profile target_profile distribution_prefix target_region target_vpc_id
    infrastructure_profile=$(jq -r '.infrastructureProfile' "$inputs_file")
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    distribution_prefix=$(jq -r '.distributionPrefix' "$inputs_file")
    target_region=$(jq -r '.targetRegion' "$inputs_file")
    target_vpc_id=$(jq -r '.targetVpcId' "$inputs_file")
    
    echo "Using inputs from: $inputs_file"
    echo "Infrastructure Profile: $infrastructure_profile"
    echo "Target Profile: $target_profile"
    echo "Distribution Prefix: $distribution_prefix"
    echo "Target Region: $target_region"
    echo "Target VPC ID: $target_vpc_id"
    echo
    
    # Validate AWS credentials for both profiles
    validate_aws_credentials "$infrastructure_profile" "infrastructure"
    validate_aws_credentials "$target_profile" "target"
    
    # Get account IDs
    local infrastructure_account_id target_account_id
    infrastructure_account_id=$(get_account_id "$infrastructure_profile")
    target_account_id=$(get_account_id "$target_profile")
    
    echo "Infrastructure Account ID: $infrastructure_account_id"
    echo "Target Account ID: $target_account_id"
    echo
    
    # Check Lambda service availability
    check_lambda_service_availability "$target_profile" "$target_region"
    
    # Discover Lambda quotas
    discover_lambda_quotas "$target_profile" "$target_region"
    
    echo
    
    # Check for resource conflicts
    local lambda_conflicts=false
    local iam_conflicts=false
    local log_conflicts=false
    
    if ! check_lambda_conflicts "$target_profile" "$distribution_prefix" "$target_region"; then
        lambda_conflicts=true
    fi
    
    if ! check_iam_role_conflicts "$target_profile" "$distribution_prefix"; then
        iam_conflicts=true
    fi
    
    if ! check_cloudwatch_log_conflicts "$target_profile" "$distribution_prefix" "$target_region"; then
        log_conflicts=true
    fi
    
    # Handle conflicts
    if [[ "$lambda_conflicts" == true ]] || [[ "$iam_conflicts" == true ]] || [[ "$log_conflicts" == true ]]; then
        prompt_overwrite_confirmation "Lambda"
    fi
    
    # Save discovery results
    save_discovery_json "$infrastructure_profile" "$target_profile" "$infrastructure_account_id" "$target_account_id" "$target_region" "$distribution_prefix" "$target_vpc_id"
}

# Function to save discovery results to JSON file
save_discovery_json() {
    local infrastructure_profile="$1"
    local target_profile="$2"
    local infrastructure_account_id="$3"
    local target_account_id="$4"
    local target_region="$5"
    local distribution_prefix="$6"
    local target_vpc_id="$7"
    
    local discovery_file="$DATA_DIR/discovery.json"
    
    cat > "$discovery_file" << EOF
{
  "infrastructureProfile": "$infrastructure_profile",
  "targetProfile": "$target_profile",
  "infrastructureAccountId": "$infrastructure_account_id",
  "targetAccountId": "$target_account_id",
  "targetRegion": "$target_region",
  "distributionPrefix": "$distribution_prefix",
  "targetVpcId": "$target_vpc_id",
  "lambdaServiceValidated": true,
  "resourceConflictsChecked": true,
  "quotasDiscovered": true,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    echo "Discovery results saved to: $discovery_file"
    echo "✅ AWS discovery completed successfully!"
}

# Main execution
main() {
    discover_aws_info
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 