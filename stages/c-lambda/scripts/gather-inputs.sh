#!/bin/bash

# gather-inputs.sh - Collect inputs for Stage C Lambda deployment
# This script validates Stage A and B completion and prepares inputs for Lambda deployment

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
STAGE_A_DIR="$STAGE_DIR/../a-cloudfront"
STAGE_B_DIR="$STAGE_DIR/../b-ssl"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Stage C Lambda deployment requires successful completion of Stage A and Stage B.
No additional command line arguments are required - all configuration is derived
from previous stage outputs.

Examples:
  $0                    # Deploy Lambda function using Stage A and B outputs

Notes:
  - Stage A (CloudFront) must be completed successfully
  - Stage B (SSL Certificate) must be completed successfully  
  - Lambda function will be deployed with Function URL for API access
  - All configuration is automatically derived from previous stages

EOF
}

# Parse command line arguments (minimal for Stage C)
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Stage C does not require additional command line arguments."
            echo "All configuration is derived from Stage A and B outputs."
            show_usage
            exit 1
            ;;
    esac
done

echo "=== Stage C Lambda Deployment - Input Validation ==="
echo "Validating Stage A and Stage B completion and gathering configuration..."
echo

# Function to load and validate Stage A outputs
load_stage_a_outputs() {
    local stage_a_outputs="$STAGE_A_DIR/data/outputs.json"
    
    echo "📋 Loading Stage A outputs..."
    echo "   Checking: $stage_a_outputs"
    
    if [[ ! -f "$stage_a_outputs" ]]; then
        echo "❌ Error: Stage A outputs not found at: $stage_a_outputs"
        echo "   Please complete Stage A (CloudFront) deployment before running Stage C"
        return 1
    fi
    
    # Validate Stage A completion status
    local ready_for_stage_b
    ready_for_stage_b=$(jq -r '.readyForStageB // false' "$stage_a_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_b" != "true" ]]; then
        echo "❌ Error: Stage A is not properly completed"
        echo "   Stage A outputs indicate: readyForStageB = $ready_for_stage_b"
        echo "   Please ensure Stage A completed successfully"
        return 1
    fi
    
    # Extract Stage A configuration
    INFRA_PROFILE=$(jq -r '.stageA.infrastructureProfile // .infrastructureProfile // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    TARGET_PROFILE=$(jq -r '.stageA.targetProfile // .targetProfile // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    DISTRIBUTION_PREFIX=$(jq -r '.distributionPrefix // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    DISTRIBUTION_ID=$(jq -r '.distributionId // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    DISTRIBUTION_URL=$(jq -r '.distributionUrl // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    BUCKET_NAME=$(jq -r '.bucketName // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    TARGET_REGION=$(jq -r '.targetRegion // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    TARGET_VPC_ID=$(jq -r '.targetVpcId // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    TARGET_ACCOUNT_ID=$(jq -r '.targetAccountId // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    INFRA_ACCOUNT_ID=$(jq -r '.infrastructureAccountId // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    
    if [[ -z "$INFRA_PROFILE" ]] || [[ -z "$TARGET_PROFILE" ]] || [[ -z "$DISTRIBUTION_ID" ]] || [[ -z "$DISTRIBUTION_PREFIX" ]]; then
        echo "❌ Error: Stage A outputs are incomplete"
        echo "   Missing required fields: infrastructureProfile, targetProfile, distributionId, or distributionPrefix"
        return 1
    fi
    
    echo "✅ Stage A outputs loaded successfully:"
    echo "   Infrastructure Profile: $INFRA_PROFILE"
    echo "   Target Profile: $TARGET_PROFILE"
    echo "   Distribution Prefix: $DISTRIBUTION_PREFIX"
    echo "   Distribution ID: $DISTRIBUTION_ID"
    echo "   Target Region: $TARGET_REGION"
    
    return 0
}

# Function to load and validate Stage B outputs
load_stage_b_outputs() {
    local stage_b_outputs="$STAGE_B_DIR/data/outputs.json"
    
    echo "📋 Loading Stage B outputs..."
    echo "   Checking: $stage_b_outputs"
    
    if [[ ! -f "$stage_b_outputs" ]]; then
        echo "❌ Error: Stage B outputs not found at: $stage_b_outputs"
        echo "   Please complete Stage B (SSL Certificate) deployment before running Stage C"
        return 1
    fi
    
    # Validate Stage B completion status
    local ready_for_stage_c
    ready_for_stage_c=$(jq -r '.readyForStageC // false' "$stage_b_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_c" != "true" ]]; then
        echo "❌ Error: Stage B is not ready for Stage C"
        echo "   Stage B outputs indicate: readyForStageC = $ready_for_stage_c"
        echo "   Please ensure Stage B completed successfully"
        return 1
    fi
    
    # Extract Stage B configuration
    CERTIFICATE_ARN=$(jq -r '.certificateArn // empty' "$stage_b_outputs" 2>/dev/null || echo "")
    DOMAINS=$(jq -r '.domains[]?' "$stage_b_outputs" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
    
    echo "✅ Stage B outputs loaded successfully:"
    echo "   Certificate ARN: $CERTIFICATE_ARN"
    echo "   Configured Domains: $DOMAINS"
    
    return 0
}

# Function to validate AWS profile credentials
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

# Function to save inputs to JSON file
save_inputs_json() {
    local inputs_file="$DATA_DIR/inputs.json"
    
    echo "Saving Stage C inputs to: $inputs_file"
    
    cat > "$inputs_file" << EOF
{
  "infrastructureProfile": "$INFRA_PROFILE",
  "targetProfile": "$TARGET_PROFILE",
  "distributionPrefix": "$DISTRIBUTION_PREFIX",
  "targetRegion": "$TARGET_REGION",
  "targetVpcId": "$TARGET_VPC_ID",
  "targetAccountId": "$TARGET_ACCOUNT_ID",
  "infrastructureAccountId": "$INFRA_ACCOUNT_ID",
  "distributionId": "$DISTRIBUTION_ID",
  "distributionUrl": "$DISTRIBUTION_URL",
  "bucketName": "$BUCKET_NAME",
  "certificateArn": "$CERTIFICATE_ARN",
  "domains": $(echo "$DOMAINS" | jq -R 'split(",") | map(select(length > 0))' 2>/dev/null || echo '[]'),
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "stageAReady": true,
  "stageBReady": true
}
EOF
    
    echo "✅ Stage C inputs saved successfully"
    return 0
}

# Main execution function
main() {
    echo "Starting Stage C Lambda deployment input validation..."
    echo
    
    # Load and validate Stage A outputs
    if ! load_stage_a_outputs; then
        echo "❌ Stage A validation failed. Please complete Stage A before proceeding."
        exit 1
    fi
    
    echo
    
    # Load and validate Stage B outputs
    if ! load_stage_b_outputs; then
        echo "❌ Stage B validation failed. Please complete Stage B before proceeding."
        exit 1
    fi
    
    echo
    echo "=== Validating AWS Credentials ==="
    
    # Validate AWS credentials
    if ! validate_aws_profile_credentials "$INFRA_PROFILE" "infrastructure"; then
        echo "❌ Infrastructure profile validation failed. Please fix the issue and try again."
        exit 1
    fi
    
    if ! validate_aws_profile_credentials "$TARGET_PROFILE" "target"; then
        echo "❌ Target profile validation failed. Please fix the issue and try again."
        exit 1
    fi
    
    echo "✅ All AWS profiles validated successfully"
    echo
    
    # Save inputs
    if ! save_inputs_json; then
        echo "❌ Failed to save inputs. Please check file permissions and try again."
        exit 1
    fi
    
    echo
    echo "🎉 Stage C input validation completed successfully!"
    echo "   Configuration derived from Stage A and Stage B outputs"
    echo "   Ready to proceed with AWS discovery and Lambda deployment"
    echo "   Lambda function will be deployed with Function URL for API access"
}

# Global variables for extracted configuration
INFRA_PROFILE=""
TARGET_PROFILE=""
DISTRIBUTION_PREFIX=""
TARGET_REGION=""
TARGET_VPC_ID=""
TARGET_ACCOUNT_ID=""
INFRA_ACCOUNT_ID=""
DISTRIBUTION_ID=""
DISTRIBUTION_URL=""
BUCKET_NAME=""
CERTIFICATE_ARN=""
DOMAINS=""

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 