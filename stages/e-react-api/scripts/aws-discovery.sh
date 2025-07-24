#!/bin/bash

# aws-discovery.sh
# AWS account discovery and resource validation for Stage D React deployment
# Validates AWS profiles, captures account IDs, and checks for existing resources

set -euo pipefail

# Script directory and data directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

echo "=== Stage D React Deployment - AWS Discovery ==="
echo "This script will validate AWS profiles and discover existing React deployment resources."
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

# Function to check CloudFront distribution status
check_cloudfront_distribution() {
    local profile="$1"
    local distribution_id="$2"
    
    echo "Checking CloudFront distribution: $distribution_id"
    
    # Get distribution details
    local distribution_info
    distribution_info=$(aws cloudfront get-distribution --id "$distribution_id" --profile "$profile" --output json 2>/dev/null || echo "{}")
    
    if [[ "$distribution_info" == "{}" ]]; then
        echo "❌ Error: CloudFront distribution $distribution_id not found"
        return 1
    fi
    
    local distribution_status
    distribution_status=$(echo "$distribution_info" | jq -r '.Distribution.Status')
    
    if [[ "$distribution_status" != "Deployed" ]]; then
        echo "⚠️  Warning: CloudFront distribution status is '$distribution_status' (not 'Deployed')"
        echo "   This may affect deployment performance"
    else
        echo "✅ CloudFront distribution is deployed and ready"
    fi
    
    # Get distribution domain name
    local distribution_domain
    distribution_domain=$(echo "$distribution_info" | jq -r '.Distribution.DomainName')
    echo "   Distribution Domain: $distribution_domain"
    
    return 0
}

# Function to check S3 bucket accessibility and contents
check_s3_bucket() {
    local profile="$1"
    local bucket_name="$2"
    
    echo "Checking S3 bucket: $bucket_name"
    
    # Test bucket access
    if ! aws s3 ls "s3://$bucket_name" --profile "$profile" > /dev/null 2>&1; then
        echo "❌ Error: Cannot access S3 bucket '$bucket_name'"
        echo "   Please check bucket permissions for profile '$profile'"
        return 1
    fi
    
    # Check bucket contents
    local object_count
    object_count=$(aws s3 ls "s3://$bucket_name" --profile "$profile" --recursive 2>/dev/null | wc -l)
    
    echo "✅ S3 bucket accessible"
    echo "   Current object count: $object_count"
    
    # Check for existing React build artifacts
    local existing_react_files
    existing_react_files=$(aws s3 ls "s3://$bucket_name" --profile "$profile" --recursive 2>/dev/null | grep -E '\.(js|css|html)$' | wc -l || echo "0")
    
    if [[ "$existing_react_files" -gt 0 ]]; then
        echo "   Existing React files detected: $existing_react_files"
        echo "   These will be replaced during deployment"
    else
        echo "   No existing React files detected"
    fi
    
    return 0
}

# Function to validate SSL certificate
check_ssl_certificate() {
    local profile="$1"
    local certificate_arn="$2"
    
    echo "Checking SSL certificate: ${certificate_arn##*/}"
    
    # Get certificate details
    local cert_info
    cert_info=$(aws acm describe-certificate --certificate-arn "$certificate_arn" --profile "$profile" --region us-east-1 --output json 2>/dev/null || echo "{}")
    
    if [[ "$cert_info" == "{}" ]]; then
        echo "❌ Error: SSL certificate not found: $certificate_arn"
        return 1
    fi
    
    local cert_status
    cert_status=$(echo "$cert_info" | jq -r '.Certificate.Status')
    
    if [[ "$cert_status" != "ISSUED" ]]; then
        echo "❌ Error: SSL certificate status is '$cert_status' (expected 'ISSUED')"
        return 1
    fi
    
    local domain_name
    domain_name=$(echo "$cert_info" | jq -r '.Certificate.DomainName')
    
    echo "✅ SSL certificate is valid and issued"
    echo "   Primary Domain: $domain_name"
    
    return 0
}

# Function to check Lambda function accessibility
check_lambda_function() {
    local profile="$1"
    local function_name="$2"
    local function_url="$3"
    local region="$4"
    
    echo "Checking Lambda function: $function_name"
    
    # Get function configuration
    local function_info
    function_info=$(aws lambda get-function --function-name "$function_name" --profile "$profile" --region "$region" --output json 2>/dev/null || echo "{}")
    
    if [[ "$function_info" == "{}" ]]; then
        echo "❌ Error: Lambda function not found: $function_name"
        return 1
    fi
    
    local function_state
    function_state=$(echo "$function_info" | jq -r '.Configuration.State')
    
    if [[ "$function_state" != "Active" ]]; then
        echo "⚠️  Warning: Lambda function state is '$function_state' (not 'Active')"
        echo "   This may affect API functionality"
    else
        echo "✅ Lambda function is active and ready"
    fi
    
    # Test function URL if provided
    if [[ -n "$function_url" ]] && command -v curl > /dev/null 2>&1; then
        echo "   Testing Function URL accessibility..."
        local http_status
        http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$function_url" || echo "000")
        
        if [[ "$http_status" =~ ^[2-3][0-9][0-9]$ ]]; then
            echo "   ✅ Function URL is accessible (HTTP $http_status)"
        else
            echo "   ⚠️  Function URL test returned HTTP $http_status"
        fi
    fi
    
    return 0
}

# Function to check for potential resource conflicts
check_resource_conflicts() {
    local profile="$1"
    local prefix="$2"
    local region="$3"
    
    echo "Checking for potential resource conflicts with prefix '$prefix'..."
    
    # Check for existing IAM roles that might conflict
    local conflicting_roles
    conflicting_roles=$(aws iam list-roles --profile "$profile" --query "Roles[?starts_with(RoleName, '${prefix}-react')].RoleName" --output text 2>/dev/null || true)
    
    if [[ -n "$conflicting_roles" ]]; then
        echo "⚠️  Found potential IAM role conflicts:"
        echo "$conflicting_roles"
    else
        echo "✅ No IAM role conflicts found"
    fi
    
    # Check for existing Lambda functions that might interfere
    local conflicting_functions
    conflicting_functions=$(aws lambda list-functions --profile "$profile" --region "$region" --query "Functions[?starts_with(FunctionName, '${prefix}-react')].FunctionName" --output text 2>/dev/null || true)
    
    if [[ -n "$conflicting_functions" ]]; then
        echo "⚠️  Found potential Lambda function conflicts:"
        echo "$conflicting_functions"
    else
        echo "✅ No Lambda function conflicts found"
    fi
    
    return 0
}

# Function to save discovery results
save_discovery_results() {
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    
    echo "💾 Saving discovery results..."
    
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    # Read configuration from inputs.json
    local target_profile infrastructure_profile
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    infrastructure_profile=$(jq -r '.infrastructureProfile' "$inputs_file")
    
    # Get account IDs
    local target_account_id infrastructure_account_id
    target_account_id=$(get_account_id "$target_profile")
    infrastructure_account_id=$(get_account_id "$infrastructure_profile")
    
    # Create discovery.json with current timestamp
    cat > "$discovery_file" << EOF
{
  "targetAccountId": "$target_account_id",
  "infrastructureAccountId": "$infrastructure_account_id",
  "targetProfile": "$target_profile",
  "infrastructureProfile": "$infrastructure_profile",
  "discoveryTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "validationResults": {
    "credentialsValid": true,
    "cloudfrontAccessible": true,
    "s3BucketAccessible": true,
    "sslCertificateValid": true,
    "lambdaFunctionAccessible": true,
    "resourceConflictsChecked": true
  },
  "discoveryStatus": "completed",
  "readyForDeployment": true
}
EOF
    
    echo "✅ Discovery results saved to: $discovery_file"
    echo
}

# Main discovery execution
main() {
    local inputs_file="$DATA_DIR/inputs.json"
    
    echo "Loading configuration from inputs.json..."
    
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found at: $inputs_file"
        echo "   Please run gather-inputs.sh first to generate the configuration file."
        exit 1
    fi
    
    # Extract configuration values
    local target_profile infrastructure_profile distribution_id bucket_name
    local certificate_arn lambda_function_name lambda_function_url target_region distribution_prefix
    
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    infrastructure_profile=$(jq -r '.infrastructureProfile' "$inputs_file")
    distribution_id=$(jq -r '.distributionId' "$inputs_file")
    bucket_name=$(jq -r '.bucketName' "$inputs_file")
    certificate_arn=$(jq -r '.certificateArn' "$inputs_file")
    lambda_function_name=$(jq -r '.stageC.lambdaFunctionName' "$inputs_file")
    lambda_function_url=$(jq -r '.stageC.lambdaFunctionUrl' "$inputs_file")
    target_region=$(jq -r '.targetRegion' "$inputs_file")
    distribution_prefix=$(jq -r '.distributionPrefix' "$inputs_file")
    
    echo "Configuration loaded:"
    echo "   Target Profile: $target_profile"
    echo "   Infrastructure Profile: $infrastructure_profile"
    echo "   Distribution ID: $distribution_id"
    echo "   Bucket Name: $bucket_name"
    echo "   Certificate ARN: ${certificate_arn##*/}"
    echo "   Lambda Function: $lambda_function_name"
    echo "   Target Region: $target_region"
    echo
    
    # Validate AWS credentials
    echo "🔐 Validating AWS credentials..."
    validate_aws_credentials "$target_profile" "target"
    validate_aws_credentials "$infrastructure_profile" "infrastructure"
    echo
    
    # Check existing AWS resources
    echo "🔍 Checking existing AWS resources..."
    check_cloudfront_distribution "$target_profile" "$distribution_id"
    echo
    
    check_s3_bucket "$target_profile" "$bucket_name"
    echo
    
    check_ssl_certificate "$target_profile" "$certificate_arn"
    echo
    
    check_lambda_function "$target_profile" "$lambda_function_name" "$lambda_function_url" "$target_region"
    echo
    
    check_resource_conflicts "$target_profile" "$distribution_prefix" "$target_region"
    echo
    
    # Save discovery results
    save_discovery_results
    
    echo "🎉 AWS discovery completed successfully!"
    echo
    echo "📋 Summary:"
    echo "   ✅ AWS credentials validated"
    echo "   ✅ CloudFront distribution accessible"
    echo "   ✅ S3 bucket accessible"
    echo "   ✅ SSL certificate validated"
    echo "   ✅ Lambda function accessible"
    echo "   ✅ Resource conflicts checked"
    echo "   ✅ Discovery results saved"
    echo
    echo "Next steps:"
    echo "   1. Run: scripts/deploy-infrastructure.sh"
    echo "   2. Run: scripts/validate-deployment.sh"
    echo
}

# Execute main function
main 