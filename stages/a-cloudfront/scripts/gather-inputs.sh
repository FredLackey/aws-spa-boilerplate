#!/bin/bash

# gather-inputs.sh - Collect user inputs for Stage A CloudFront deployment
# This script gathers all necessary configuration inputs via command line arguments
# and saves them to inputs.json for use by other scripts.

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Default values
INFRASTRUCTURE_PROFILE=""
TARGET_PROFILE=""
DISTRIBUTION_PREFIX=""
TARGET_REGION=""
TARGET_VPC_ID=""

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Required Options:
  --infraprofile PROFILE    AWS CLI profile for infrastructure resources (Route53, certificates)
  --targetprofile PROFILE   AWS CLI profile for target resources (S3, CloudFront)
  --prefix PREFIX           Distribution prefix (kebab-case, lowercase, alphanumeric)
  --region REGION           Target AWS region
  --vpc VPC_ID              Target VPC ID

Example:
  $0 --infraprofile my-infra --targetprofile my-target --prefix hellospa --region us-east-1 --vpc vpc-0123456789abcdef0

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --infraprofile)
            INFRASTRUCTURE_PROFILE="$2"
            shift 2
            ;;
        --targetprofile)
            TARGET_PROFILE="$2"
            shift 2
            ;;
        --prefix)
            DISTRIBUTION_PREFIX="$2"
            shift 2
            ;;
        --region)
            TARGET_REGION="$2"
            shift 2
            ;;
        --vpc)
            TARGET_VPC_ID="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate all required arguments are provided
if [[ -z "$INFRASTRUCTURE_PROFILE" || -z "$TARGET_PROFILE" || -z "$DISTRIBUTION_PREFIX" || -z "$TARGET_REGION" || -z "$TARGET_VPC_ID" ]]; then
    echo "❌ Error: All required arguments must be provided."
    echo
    show_usage
    exit 1
fi

echo "=== Stage A CloudFront Deployment - Input Validation ==="
echo "Validating provided configuration inputs..."
echo

# Function to validate AWS profile exists and has valid credentials
validate_aws_profile() {
    local profile="$1"
    echo "Validating AWS profile: $profile"
    
    # Check if profile exists in AWS config
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo "❌ Error: AWS profile '$profile' not found"
        echo "Available profiles:"
        aws configure list-profiles | sed 's/^/  - /'
        return 1
    fi
    
    echo "✅ Profile '$profile' found in AWS configuration"
    return 0
}

# Function to validate AWS profile credentials and handle SSO login
validate_aws_profile_credentials() {
    local profile="$1"
    local profile_type="$2"
    
    echo "Validating $profile_type profile credentials: $profile"
    
    # Try to get account ID to test credentials
    local account_id
    account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ Profile '$profile' credentials are valid (Account: $account_id)"
        return 0
    fi
    
    # Check if the error is related to SSO
    if echo "$account_id" | grep -q -i "sso\|token.*expired\|session.*expired\|credentials.*expired"; then
        echo "🔑 SSO token appears to be expired for profile '$profile'"
        echo "Attempting to refresh SSO login..."
        
        # Attempt SSO login
        if aws sso login --profile "$profile"; then
            echo "✅ SSO login successful, re-validating credentials..."
            
            # Re-test credentials
            account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>&1)
            exit_code=$?
            
            if [[ $exit_code -eq 0 ]]; then
                echo "✅ Profile '$profile' credentials are now valid (Account: $account_id)"
                return 0
            else
                echo "❌ Credentials still invalid after SSO login: $account_id"
                return 1
            fi
        else
            echo "❌ SSO login failed for profile '$profile'"
            echo "Please run 'aws sso login --profile $profile' manually and try again"
            return 1
        fi
    else
        echo "❌ Profile '$profile' credentials are invalid: $account_id"
        echo "This doesn't appear to be an SSO issue. Please check your AWS configuration."
        return 1
    fi
}

# Function to validate kebab-case format
validate_kebab_case() {
    local input="$1"
    if [[ ! "$input" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        echo "❌ Error: '$input' is not in valid kebab-case format"
        echo "Must be lowercase, alphanumeric, with hyphens as separators (e.g., 'hello-world-123')"
        return 1
    fi
    echo "✅ Distribution prefix '$input' is valid kebab-case"
    return 0
}

# Function to validate AWS region
validate_aws_region() {
    local region="$1"
    local profile="$2"
    echo "Validating AWS region: $region"
    
    # Get list of available regions and check if provided region exists
    local region_check
    region_check=$(aws ec2 describe-regions --region-names "$region" --output text --query 'Regions[0].RegionName' --profile "$profile" 2>/dev/null || echo "")
    
    if [[ "$region_check" == "$region" ]]; then
        echo "✅ Region '$region' is valid"
        return 0
    else
        echo "❌ Error: '$region' is not a valid AWS region"
        echo "Available regions include: us-east-1, us-west-2, eu-west-1, ap-southeast-1, etc."
        echo "To see all available regions, run: aws ec2 describe-regions --query 'Regions[].RegionName' --output text --profile $profile"
        return 1
    fi
}

# Function to validate VPC ID format and existence
validate_vpc_id() {
    local vpc_id="$1"
    local profile="$2"
    local region="$3"
    
    echo "Validating VPC ID: $vpc_id"
    
    # Check VPC ID format
    if [[ ! "$vpc_id" =~ ^vpc-[0-9a-f]{8,17}$ ]]; then
        echo "❌ Error: '$vpc_id' is not a valid VPC ID format"
        echo "VPC IDs should start with 'vpc-' followed by 8-17 hexadecimal characters"
        return 1
    fi
    
    echo "✅ VPC ID format is valid"
    
    # Check if VPC exists in the specified account/region
    echo "Checking if VPC exists in account/region using profile '$profile'..."
    
    local aws_output
    local aws_exit_code
    
    aws_output=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --profile "$profile" --region "$region" --output text --query 'Vpcs[0].VpcId' 2>&1)
    aws_exit_code=$?
    
    if [[ $aws_exit_code -eq 0 && "$aws_output" == "$vpc_id" ]]; then
        echo "✅ VPC '$vpc_id' found and accessible"
        return 0
    else
        echo "❌ VPC validation failed"
        echo "AWS CLI output: $aws_output"
        echo "Exit code: $aws_exit_code"
        echo
        echo "Possible issues:"
        echo "1. VPC '$vpc_id' does not exist in account/region"
        echo "2. Insufficient permissions (need 'ec2:DescribeVpcs')"
        echo "3. VPC is in a different region than specified ($region)"
        echo "4. AWS credentials issue for profile '$profile'"
        echo
        echo "Troubleshooting steps:"
        echo "- Verify the VPC ID is correct"
        echo "- Check that you're using the right AWS profile and region"
        echo "- Ensure your AWS credentials have EC2 describe permissions"
        echo "- Try running: aws ec2 describe-vpcs --profile $profile --region $region"
        return 1
    fi
}

# Validate inputs
echo "Infrastructure Profile: $INFRASTRUCTURE_PROFILE"
echo "Target Profile: $TARGET_PROFILE"
echo "Distribution Prefix: $DISTRIBUTION_PREFIX"
echo "Target Region: $TARGET_REGION"
echo "Target VPC ID: $TARGET_VPC_ID"
echo

# Validate AWS profiles exist
if ! validate_aws_profile "$INFRASTRUCTURE_PROFILE"; then
    exit 1
fi

if ! validate_aws_profile "$TARGET_PROFILE"; then
    exit 1
fi

# Validate AWS credentials before proceeding to VPC validation
echo
echo "=== Validating AWS Credentials ==="

if ! validate_aws_profile_credentials "$INFRASTRUCTURE_PROFILE" "infrastructure"; then
    echo "❌ Infrastructure profile validation failed. Please fix the issue and try again."
    exit 1
fi

if ! validate_aws_profile_credentials "$TARGET_PROFILE" "target"; then
    echo "❌ Target profile validation failed. Please fix the issue and try again."
    exit 1
fi

echo "✅ All AWS profiles validated successfully"
echo

# Validate distribution prefix format
if ! validate_kebab_case "$DISTRIBUTION_PREFIX"; then
    exit 1
fi

# Validate AWS region
if ! validate_aws_region "$TARGET_REGION" "$TARGET_PROFILE"; then
    exit 1
fi

# Validate VPC ID
echo "=== Validating VPC ==="
if ! validate_vpc_id "$TARGET_VPC_ID" "$TARGET_PROFILE" "$TARGET_REGION"; then
    echo "❌ VPC validation failed. Please check the VPC ID and try again."
    exit 1
fi

# Save inputs to JSON file
INPUTS_FILE="$DATA_DIR/inputs.json"
echo "Saving inputs to: $INPUTS_FILE"

cat > "$INPUTS_FILE" << EOF
{
  "infrastructureProfile": "$INFRASTRUCTURE_PROFILE",
  "targetProfile": "$TARGET_PROFILE",
  "distributionPrefix": "$DISTRIBUTION_PREFIX",
  "targetRegion": "$TARGET_REGION",
  "targetVpcId": "$TARGET_VPC_ID"
}
EOF

echo "✅ All inputs validated and saved successfully"
echo "Configuration saved to: $INPUTS_FILE" 