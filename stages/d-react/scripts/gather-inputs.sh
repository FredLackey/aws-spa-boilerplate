#!/bin/bash

# gather-inputs.sh - Collect inputs for Stage D React deployment
# This script validates Stage A, B, and C completion and prepares inputs for React deployment

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
STAGE_A_DIR="$STAGE_DIR/../a-cloudfront"
STAGE_B_DIR="$STAGE_DIR/../b-ssl"
STAGE_C_DIR="$STAGE_DIR/../c-lambda"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Stage D React deployment requires successful completion of Stages A, B, and C.
No additional command line arguments are required - all configuration is derived
from previous stage outputs.

Examples:
  $0                    # Deploy React SPA using Stages A, B, and C outputs

Notes:
  - Stage A (CloudFront) must be completed successfully
  - Stage B (SSL Certificate) must be completed successfully  
  - Stage C (Lambda) must be completed successfully
  - React application will be built and deployed to CloudFront
  - All configuration is automatically derived from previous stages

EOF
}

# Parse command line arguments (minimal for Stage D)
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Stage D does not require additional command line arguments."
            echo "All configuration is derived from Stage A, B, and C outputs."
            show_usage
            exit 1
            ;;
    esac
done

echo "=== Stage D React Deployment - Input Validation ==="
echo "Validating Stage A, B, and C completion and gathering configuration..."
echo

# Function to load and validate Stage A outputs
load_stage_a_outputs() {
    local stage_a_outputs="$STAGE_A_DIR/data/outputs.json"
    
    echo "📋 Loading Stage A outputs..."
    echo "   Checking: $stage_a_outputs"
    
    if [[ ! -f "$stage_a_outputs" ]]; then
        echo "❌ Error: Stage A outputs not found at: $stage_a_outputs"
        echo "   Please complete Stage A (CloudFront) deployment before running Stage D"
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
    DISTRIBUTION_DOMAIN_NAME=$(jq -r '.distributionDomainName // empty' "$stage_a_outputs" 2>/dev/null || echo "")
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
    
    echo "✅ Stage A outputs loaded successfully"
    echo "   Infrastructure Profile: $INFRA_PROFILE"
    echo "   Target Profile: $TARGET_PROFILE"
    echo "   Distribution Prefix: $DISTRIBUTION_PREFIX"
    echo "   Distribution ID: $DISTRIBUTION_ID"
    echo "   Bucket Name: $BUCKET_NAME"
    echo "   Target Region: $TARGET_REGION"
    echo
}

# Function to load and validate Stage B outputs
load_stage_b_outputs() {
    local stage_b_outputs="$STAGE_B_DIR/data/outputs.json"
    
    echo "📋 Loading Stage B outputs..."
    echo "   Checking: $stage_b_outputs"
    
    if [[ ! -f "$stage_b_outputs" ]]; then
        echo "❌ Error: Stage B outputs not found at: $stage_b_outputs"
        echo "   Please complete Stage B (SSL Certificate) deployment before running Stage D"
        return 1
    fi
    
    # Validate Stage B completion status
    local ready_for_stage_c
    ready_for_stage_c=$(jq -r '.readyForStageC // false' "$stage_b_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_c" != "true" ]]; then
        echo "❌ Error: Stage B is not properly completed"
        echo "   Stage B outputs indicate: readyForStageC = $ready_for_stage_c"
        echo "   Please ensure Stage B completed successfully"
        return 1
    fi
    
    # Extract Stage B configuration
    DOMAINS=($(jq -r '.domains[]? // empty' "$stage_b_outputs" 2>/dev/null || echo ""))
    PRIMARY_DOMAIN=$(jq -r '.domains[0] // empty' "$stage_b_outputs" 2>/dev/null || echo "")  # Use first domain as primary
    CERTIFICATE_ARN=$(jq -r '.certificateArn // empty' "$stage_b_outputs" 2>/dev/null || echo "")
    HTTPS_URLS=()  # Build HTTPS URLs from domains
    
    # Create HTTPS URLs from domains
    for domain in "${DOMAINS[@]}"; do
        if [[ -n "$domain" ]]; then
            HTTPS_URLS+=("https://$domain")
        fi
    done
    
    if [[ -z "$PRIMARY_DOMAIN" ]] || [[ -z "$CERTIFICATE_ARN" ]] || [[ ${#DOMAINS[@]} -eq 0 ]]; then
        echo "❌ Error: Stage B outputs are incomplete"
        echo "   Missing required fields: domains[0] as primaryDomain, certificateArn, or domains array"
        return 1
    fi
    
    echo "✅ Stage B outputs loaded successfully"
    echo "   Primary Domain: $PRIMARY_DOMAIN"
    echo "   Certificate ARN: ${CERTIFICATE_ARN##*/}"
    echo "   All Domains: ${DOMAINS[*]}"
    echo
}

# Function to load and validate Stage C outputs
load_stage_c_outputs() {
    local stage_c_outputs="$STAGE_C_DIR/data/outputs.json"
    
    echo "📋 Loading Stage C outputs..."
    echo "   Checking: $stage_c_outputs"
    
    if [[ ! -f "$stage_c_outputs" ]]; then
        echo "❌ Error: Stage C outputs not found at: $stage_c_outputs"
        echo "   Please complete Stage C (Lambda) deployment before running Stage D"
        return 1
    fi
    
    # Validate Stage C completion status
    local ready_for_stage_d
    ready_for_stage_d=$(jq -r '.readyForStageD // false' "$stage_c_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_d" != "true" ]]; then
        echo "❌ Error: Stage C is not properly completed"
        echo "   Stage C outputs indicate: readyForStageD = $ready_for_stage_d"
        echo "   Please ensure Stage C completed successfully"
        return 1
    fi
    
    # Extract Stage C configuration
    LAMBDA_FUNCTION_NAME=$(jq -r '.lambdaFunctionName // empty' "$stage_c_outputs" 2>/dev/null || echo "")
    LAMBDA_FUNCTION_ARN=$(jq -r '.lambdaFunctionArn // empty' "$stage_c_outputs" 2>/dev/null || echo "")
    LAMBDA_FUNCTION_URL=$(jq -r '.functionUrl // empty' "$stage_c_outputs" 2>/dev/null || echo "")
    API_ENDPOINTS=("$LAMBDA_FUNCTION_URL")  # Use function URL as the main API endpoint
    
    if [[ -z "$LAMBDA_FUNCTION_NAME" ]] || [[ -z "$LAMBDA_FUNCTION_ARN" ]] || [[ -z "$LAMBDA_FUNCTION_URL" ]]; then
        echo "❌ Error: Stage C outputs are incomplete"
        echo "   Missing required fields: lambdaFunctionName, lambdaFunctionArn, or functionUrl"
        return 1
    fi
    
    echo "✅ Stage C outputs loaded successfully"
    echo "   Lambda Function Name: $LAMBDA_FUNCTION_NAME"
    echo "   Lambda Function URL: $LAMBDA_FUNCTION_URL"
    echo "   API Endpoints: ${API_ENDPOINTS[*]:-none}"
    echo
}

# Function to validate React application exists
validate_react_application() {
    local react_app_dir="$STAGE_DIR/../../apps/hello-world-react"
    
    echo "📋 Validating React application..."
    echo "   Checking: $react_app_dir"
    
    if [[ ! -d "$react_app_dir" ]]; then
        echo "❌ Error: React application directory not found at: $react_app_dir"
        return 1
    fi
    
    if [[ ! -f "$react_app_dir/package.json" ]]; then
        echo "❌ Error: React application package.json not found"
        return 1
    fi
    
    if [[ ! -f "$react_app_dir/vite.config.js" ]]; then
        echo "❌ Error: React application vite.config.js not found"
        return 1
    fi
    
    if [[ ! -f "$react_app_dir/index.html" ]]; then
        echo "❌ Error: React application index.html not found"
        return 1
    fi
    
    echo "✅ React application validated"
    echo "   Application Directory: $react_app_dir"
    echo
}

# Function to save configuration to inputs.json
save_inputs_json() {
    local inputs_file="$DATA_DIR/inputs.json"
    
    echo "💾 Saving configuration to inputs.json..."
    
    # Create the inputs.json structure
    cat > "$inputs_file" << EOF
{
  "stageD": {
    "infrastructureProfile": "$INFRA_PROFILE",
    "targetProfile": "$TARGET_PROFILE",
    "distributionPrefix": "$DISTRIBUTION_PREFIX",
    "targetRegion": "$TARGET_REGION",
    "targetVpcId": "$TARGET_VPC_ID",
    "targetAccountId": "$TARGET_ACCOUNT_ID",
    "infrastructureAccountId": "$INFRA_ACCOUNT_ID"
  },
  "stageA": {
    "distributionId": "$DISTRIBUTION_ID",
    "distributionDomainName": "$DISTRIBUTION_DOMAIN_NAME",
    "distributionUrl": "$DISTRIBUTION_URL",
    "bucketName": "$BUCKET_NAME"
  },
  "stageB": {
    "primaryDomain": "$PRIMARY_DOMAIN",
    "domains": $(printf '%s\n' "${DOMAINS[@]}" | jq -R . | jq -s .),
    "certificateArn": "$CERTIFICATE_ARN",
    "httpsUrls": $(printf '%s\n' "${HTTPS_URLS[@]}" | jq -R . | jq -s .)
  },
  "stageC": {
    "lambdaFunctionName": "$LAMBDA_FUNCTION_NAME",
    "lambdaFunctionArn": "$LAMBDA_FUNCTION_ARN",
    "lambdaFunctionUrl": "$LAMBDA_FUNCTION_URL",
    "apiEndpoints": $(printf '%s\n' "${API_ENDPOINTS[@]}" | jq -R . | jq -s .)
  },
  "infrastructureProfile": "$INFRA_PROFILE",
  "targetProfile": "$TARGET_PROFILE",
  "distributionPrefix": "$DISTRIBUTION_PREFIX",
  "targetRegion": "$TARGET_REGION",
  "targetVpcId": "$TARGET_VPC_ID",
  "distributionId": "$DISTRIBUTION_ID",
  "distributionDomainName": "$DISTRIBUTION_DOMAIN_NAME",
  "distributionUrl": "$DISTRIBUTION_URL",
  "bucketName": "$BUCKET_NAME",
  "primaryDomain": "$PRIMARY_DOMAIN",
  "certificateArn": "$CERTIFICATE_ARN",
  "lambdaFunctionUrl": "$LAMBDA_FUNCTION_URL"
}
EOF
    
    echo "✅ Configuration saved to: $inputs_file"
    echo
}

# Main execution
main() {
    # Load outputs from all previous stages
    load_stage_a_outputs
    load_stage_b_outputs
    load_stage_c_outputs
    
    # Validate React application exists
    validate_react_application
    
    # Save all configuration to inputs.json
    save_inputs_json
    
    echo "🎉 Stage D inputs gathering completed successfully!"
    echo
    echo "📋 Summary:"
    echo "   ✅ Stage A (CloudFront) validated"
    echo "   ✅ Stage B (SSL) validated"
    echo "   ✅ Stage C (Lambda) validated"
    echo "   ✅ React application validated"
    echo "   ✅ Configuration saved to inputs.json"
    echo
    echo "Next steps:"
    echo "   1. Run: scripts/aws-discovery.sh"
    echo "   2. Run: scripts/deploy-infrastructure.sh"
    echo "   3. Run: scripts/validate-deployment.sh"
    echo
}

# Execute main function
main 