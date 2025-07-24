#!/bin/bash

# aws-discovery.sh
# AWS account discovery and resource validation for Stage A CloudFront deployment
# Validates AWS profiles, captures account IDs, and checks for resource conflicts

set -euo pipefail

# Script directory and data directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

echo "=== Stage A CloudFront Deployment - AWS Discovery ==="
echo "This script will validate AWS profiles and discover existing resources."
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

# Function to check for existing CloudFront distributions with same prefix
check_cloudfront_conflicts() {
    local profile="$1"
    local prefix="$2"
    
    echo "Checking for existing CloudFront distributions with prefix '$prefix'..."
    
    # Get list of CloudFront distributions
    local distributions
    distributions=$(aws cloudfront list-distributions --profile "$profile" --query 'DistributionList.Items[].{Id:Id,Comment:Comment}' --output json 2>/dev/null || echo "[]")
    
    # Check if any distribution comments contain our prefix
    local conflicts
    conflicts=$(echo "$distributions" | jq -r --arg prefix "$prefix" '.[] | select(.Comment and (.Comment | contains($prefix))) | .Id' 2>/dev/null || true)
    
    if [[ -n "$conflicts" ]]; then
        echo "⚠️  Found existing CloudFront distributions with prefix '$prefix':"
        echo "$conflicts"
        return 1
    else
        echo "✅ No CloudFront distribution conflicts found"
        return 0
    fi
}

# Function to check for existing S3 buckets with same prefix
check_s3_conflicts() {
    local profile="$1"
    local prefix="$2"
    local region="$3"
    
    echo "Checking for existing S3 buckets with prefix '$prefix' in region '$region'..."
    
    # List buckets and filter by prefix
    local buckets
    buckets=$(aws s3api list-buckets --profile "$profile" --query "Buckets[?starts_with(Name, '${prefix}')].Name" --output text 2>/dev/null || true)
    
    if [[ -n "$buckets" ]]; then
        echo "⚠️  Found existing S3 buckets with prefix '$prefix':"
        echo "$buckets"
        return 1
    else
        echo "✅ No S3 bucket conflicts found"
        return 0
    fi
}

# Function to check region availability
check_region_availability() {
    local profile="$1"
    local region="$2"
    
    echo "Validating region '$region' availability..."
    
    # Test region by listing S3 buckets (simple operation)
    if ! aws s3 ls --profile "$profile" --region "$region" > /dev/null 2>&1; then
        echo "❌ Error: Region '$region' is not accessible with profile '$profile'"
        return 1
    fi
    
    echo "✅ Region '$region' is accessible"
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
    local infrastructure_profile target_profile distribution_prefix target_region
    infrastructure_profile=$(jq -r '.infrastructureProfile' "$inputs_file")
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    distribution_prefix=$(jq -r '.distributionPrefix' "$inputs_file")
    target_region=$(jq -r '.targetRegion' "$inputs_file")
    
    echo "Using inputs from: $inputs_file"
    echo "Infrastructure Profile: $infrastructure_profile"
    echo "Target Profile: $target_profile"
    echo "Distribution Prefix: $distribution_prefix"
    echo "Target Region: $target_region"
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
    
    # Check region availability
    check_region_availability "$target_profile" "$target_region"
    
    # Check for resource conflicts
    local cloudfront_conflicts=false
    local s3_conflicts=false
    
    if ! check_cloudfront_conflicts "$target_profile" "$distribution_prefix"; then
        cloudfront_conflicts=true
    fi
    
    if ! check_s3_conflicts "$target_profile" "$distribution_prefix" "$target_region"; then
        s3_conflicts=true
    fi
    
    # Handle conflicts
    if [[ "$cloudfront_conflicts" == true ]] || [[ "$s3_conflicts" == true ]]; then
        prompt_overwrite_confirmation "AWS"
    fi
    
    # Save discovery results
    save_discovery_json "$infrastructure_profile" "$target_profile" "$infrastructure_account_id" "$target_account_id" "$target_region" "$distribution_prefix"
}

# Function to save discovery results to JSON file
save_discovery_json() {
    local infrastructure_profile="$1"
    local target_profile="$2"
    local infrastructure_account_id="$3"
    local target_account_id="$4"
    local target_region="$5"
    local distribution_prefix="$6"
    
    local discovery_file="$DATA_DIR/discovery.json"
    
    cat > "$discovery_file" << EOF
{
  "infrastructureProfile": "$infrastructure_profile",
  "targetProfile": "$target_profile",
  "infrastructureAccountId": "$infrastructure_account_id",
  "targetAccountId": "$target_account_id",
  "targetRegion": "$target_region",
  "distributionPrefix": "$distribution_prefix",
  "resourcesValidated": true,
  "conflictsChecked": true,
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