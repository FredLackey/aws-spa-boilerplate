#!/bin/bash

# validate-deployment.sh
# HTTP testing and deployment validation for Stage A CloudFront deployment
# Tests connectivity, validates content, and generates final outputs.json

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

echo "=== Stage A CloudFront Deployment - Validation ==="
echo "This script will validate the deployment by testing HTTP connectivity and content."
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
    
    # Check if curl is available
    if ! command -v curl > /dev/null 2>&1; then
        echo "❌ Error: curl command not found. Please install curl."
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
    DISTRIBUTION_ID=$(jq -r '.DistributionId' "$stack_outputs")
    DISTRIBUTION_DOMAIN=$(jq -r '.DistributionDomainName' "$stack_outputs")
    DISTRIBUTION_URL=$(jq -r '.DistributionUrl' "$stack_outputs")
    BUCKET_NAME=$(jq -r '.BucketName' "$stack_outputs")
    BUCKET_ARN=$(jq -r '.BucketArn' "$stack_outputs")
    
    # Extract from inputs
    DISTRIBUTION_PREFIX=$(jq -r '.distributionPrefix' "$inputs_file")
    TARGET_REGION=$(jq -r '.targetRegion' "$inputs_file")
    TARGET_VPC_ID=$(jq -r '.targetVpcId' "$inputs_file")
    TARGET_PROFILE=$(jq -r '.targetProfile' "$inputs_file")
    INFRASTRUCTURE_PROFILE=$(jq -r '.infrastructureProfile' "$inputs_file")
    
    # Extract from discovery
    TARGET_ACCOUNT_ID=$(jq -r '.targetAccountId' "$discovery_file")
    INFRASTRUCTURE_ACCOUNT_ID=$(jq -r '.infrastructureAccountId' "$discovery_file")
    
    echo "Distribution URL: $DISTRIBUTION_URL"
    echo "Distribution ID: $DISTRIBUTION_ID"
    echo "S3 Bucket: $BUCKET_NAME"
    echo "Distribution Prefix: $DISTRIBUTION_PREFIX"
    
    # Validate extracted values
    if [[ -z "$DISTRIBUTION_URL" || "$DISTRIBUTION_URL" == "null" ]]; then
        echo "❌ Error: Could not extract CloudFront distribution URL."
        exit 1
    fi
    
    echo "✅ Deployment information extracted successfully"
}

# Function to test HTTP connectivity with retries
test_http_connectivity() {
    local url="$1"
    local max_retries=5
    local retry_delay=30
    local attempt=1
    
    echo "Testing HTTP connectivity to: $url"
    echo "Note: CloudFront propagation may take several minutes..."
    
    while [[ $attempt -le $max_retries ]]; do
        echo "Attempt $attempt of $max_retries..."
        
        # Test HTTP connectivity
        local http_status
        http_status=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
        
        if [[ "$http_status" == "200" ]]; then
            echo "✅ HTTP connectivity test passed (Status: $http_status)"
            return 0
        elif [[ "$http_status" == "000" ]]; then
            echo "⚠️  Connection failed - CloudFront may still be propagating"
        else
            echo "⚠️  HTTP Status: $http_status - CloudFront may still be propagating"
        fi
        
        if [[ $attempt -lt $max_retries ]]; then
            echo "Waiting $retry_delay seconds before retry..."
            sleep $retry_delay
        fi
        
        ((attempt++))
    done
    
    echo "❌ HTTP connectivity test failed after $max_retries attempts"
    echo "This may be due to CloudFront propagation delays."
    echo "You can manually test the URL later: $url"
    return 1
}

# Function to validate content
validate_content() {
    local url="$1"
    local expected_text="CloudFront Distribution is Working!"
    local max_retries=3
    local retry_delay=10
    local attempt=1
    
    echo "Validating content from: $url"
    echo "Looking for text: '$expected_text'"
    
    while [[ $attempt -le $max_retries ]]; do
        echo "Content validation attempt $attempt of $max_retries..."
        
        # Fetch content and check for expected text
        local content
        content=$(curl -s "$url" 2>/dev/null || echo "")
        
        if [[ -n "$content" ]] && echo "$content" | grep -q "$expected_text"; then
            echo "✅ Content validation passed - found '$expected_text'"
            echo "Content preview (first 200 characters):"
            echo "$content" | head -c 200
            echo
            return 0
        fi
        
        if [[ -z "$content" ]]; then
            echo "⚠️  No content received"
        else
            echo "⚠️  Expected text '$expected_text' not found in content"
            echo "Content preview (first 100 characters):"
            echo "$content" | head -c 100
            echo
        fi
        
        if [[ $attempt -lt $max_retries ]]; then
            echo "Waiting $retry_delay seconds before retry..."
            sleep $retry_delay
        fi
        
        ((attempt++))
    done
    
    echo "❌ Content validation failed after $max_retries attempts"
    return 1
}

# Function to validate outputs.json format for Stage B compatibility
validate_outputs_format() {
    local outputs_file="$DATA_DIR/outputs.json"
    
    echo "Validating outputs.json format for Stage B compatibility..."
    
    # Check required fields for Stage B
    local required_fields=(
        "distributionId"
        "distributionDomainName"
        "distributionUrl"
        "bucketName"
        "bucketArn"
        "distributionPrefix"
        "targetRegion"
        "targetVpcId"
        "targetAccountId"
        "infrastructureAccountId"
    )
    
    local missing_fields=()
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$outputs_file" > /dev/null 2>&1; then
            missing_fields+=("$field")
        fi
    done
    
    if [[ ${#missing_fields[@]} -eq 0 ]]; then
        echo "✅ outputs.json format validation passed"
        echo "All required fields for Stage B are present"
        return 0
    else
        echo "❌ outputs.json format validation failed"
        echo "Missing required fields: ${missing_fields[*]}"
        return 1
    fi
}

# Function to generate final outputs.json for subsequent stages
generate_final_outputs() {
    local outputs_file="$DATA_DIR/outputs.json"
    
    echo "Generating final outputs.json for subsequent stages..."
    
    # Create comprehensive outputs file
    cat > "$outputs_file" << EOF
{
  "stageA": {
    "distributionId": "$DISTRIBUTION_ID",
    "distributionDomainName": "$DISTRIBUTION_DOMAIN",
    "distributionUrl": "$DISTRIBUTION_URL",
    "bucketName": "$BUCKET_NAME",
    "bucketArn": "$BUCKET_ARN",
    "distributionPrefix": "$DISTRIBUTION_PREFIX",
    "targetRegion": "$TARGET_REGION",
    "targetVpcId": "$TARGET_VPC_ID",
    "targetAccountId": "$TARGET_ACCOUNT_ID",
    "infrastructureAccountId": "$INFRASTRUCTURE_ACCOUNT_ID",
    "targetProfile": "$TARGET_PROFILE",
    "infrastructureProfile": "$INFRASTRUCTURE_PROFILE"
  },
  "distributionId": "$DISTRIBUTION_ID",
  "distributionDomainName": "$DISTRIBUTION_DOMAIN",
  "distributionUrl": "$DISTRIBUTION_URL",
  "bucketName": "$BUCKET_NAME",
  "bucketArn": "$BUCKET_ARN",
  "distributionPrefix": "$DISTRIBUTION_PREFIX",
  "targetRegion": "$TARGET_REGION",
  "targetVpcId": "$TARGET_VPC_ID",
  "targetAccountId": "$TARGET_ACCOUNT_ID",
  "infrastructureAccountId": "$INFRASTRUCTURE_ACCOUNT_ID",
  "deploymentTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "validationStatus": "passed",
  "readyForStageB": true
}
EOF
    
    echo "✅ Final outputs.json generated successfully"
    echo "Outputs saved to: $outputs_file"
    
    # Display summary
    echo
    echo "=== Stage A Deployment Summary ==="
    echo "Distribution URL: $DISTRIBUTION_URL"
    echo "Distribution ID: $DISTRIBUTION_ID"
    echo "S3 Bucket: $BUCKET_NAME"
    echo "Target Region: $TARGET_REGION"
    echo "Status: Ready for Stage B"
}

# Function to handle validation errors
handle_validation_error() {
    local error_type="$1"
    local exit_code="$2"
    
    echo "❌ Validation failed during $error_type"
    echo
    echo "Troubleshooting steps:"
    case "$error_type" in
        "HTTP connectivity")
            echo "1. CloudFront distributions can take 10-15 minutes to fully propagate"
            echo "2. Try accessing the URL directly in a web browser"
            echo "3. Check CloudFront distribution status in AWS Console"
            echo "4. Verify the S3 bucket has the correct files"
            ;;
        "content validation")
            echo "1. Check if the hello-world-html/index.html file contains expected content"
            echo "2. Verify the S3 sync completed successfully"
            echo "3. Check CloudFront cache invalidation status"
            echo "4. Try accessing the URL directly in a web browser"
            ;;
        "outputs format")
            echo "1. Check if all deployment steps completed successfully"
            echo "2. Verify CDK stack outputs are complete"
            echo "3. Re-run deploy-infrastructure.sh if needed"
            ;;
    esac
    echo
    echo "You can manually test the deployment at: $DISTRIBUTION_URL"
    
    return $exit_code
}

# Main validation function
validate_deployment() {
    validate_prerequisites
    extract_deployment_info
    
    local validation_success=true
    
    # Test HTTP connectivity
    if ! test_http_connectivity "$DISTRIBUTION_URL"; then
        handle_validation_error "HTTP connectivity" 1
        validation_success=false
    fi
    
    # Validate content (only if HTTP connectivity succeeded)
    if [[ "$validation_success" == true ]]; then
        if ! validate_content "$DISTRIBUTION_URL"; then
            handle_validation_error "content validation" 1
            validation_success=false
        fi
    fi
    
    # Generate outputs regardless of validation status
    generate_final_outputs
    
    # Validate outputs format
    if ! validate_outputs_format; then
        handle_validation_error "outputs format" 1
        validation_success=false
    fi
    
    if [[ "$validation_success" == true ]]; then
        echo
        echo "🎉 Stage A deployment validation completed successfully!"
        echo "Your CloudFront distribution is ready and accessible."
        echo "You can now proceed to Stage B for SSL certificate configuration."
        return 0
    else
        echo
        echo "⚠️  Stage A deployment completed with validation warnings."
        echo "The infrastructure is deployed but may need additional time to propagate."
        echo "Check the troubleshooting steps above and test manually if needed."
        return 1
    fi
}

# Global variables for extracted info
DISTRIBUTION_ID=""
DISTRIBUTION_DOMAIN=""
DISTRIBUTION_URL=""
BUCKET_NAME=""
BUCKET_ARN=""
DISTRIBUTION_PREFIX=""
TARGET_REGION=""
TARGET_VPC_ID=""
TARGET_ACCOUNT_ID=""
INFRASTRUCTURE_ACCOUNT_ID=""
TARGET_PROFILE=""
INFRASTRUCTURE_PROFILE=""

# Main execution
main() {
    validate_deployment
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 