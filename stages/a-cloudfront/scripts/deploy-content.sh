#!/bin/bash

# deploy-content.sh
# Application file deployment for Stage A CloudFront deployment
# Uploads hello-world-html files to S3 bucket and invalidates CloudFront cache

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
APPS_DIR="$(dirname "$(dirname "$STAGE_DIR")")/apps"
HELLO_WORLD_HTML_DIR="$APPS_DIR/hello-world-html"

echo "=== Stage A CloudFront Deployment - Content Deployment ==="
echo "This script will upload hello-world-html files to S3 and invalidate CloudFront cache."
echo

# Function to validate prerequisites
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # Check for required data files
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    if [[ ! -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        echo "❌ Error: CDK stack outputs not found. Please run deploy-infrastructure.sh first."
        exit 1
    fi
    
    # Check for hello-world-html application
    if [[ ! -d "$HELLO_WORLD_HTML_DIR" ]]; then
        echo "❌ Error: hello-world-html application directory not found at: $HELLO_WORLD_HTML_DIR"
        exit 1
    fi
    
    if [[ ! -f "$HELLO_WORLD_HTML_DIR/index.html" ]]; then
        echo "❌ Error: index.html not found in hello-world-html application."
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
    echo "Hello World HTML Directory: $HELLO_WORLD_HTML_DIR"
}

# Function to extract deployment information
extract_deployment_info() {
    local stack_outputs="$DATA_DIR/cdk-stack-outputs.json"
    local inputs_file="$DATA_DIR/inputs.json"
    
    echo "Extracting deployment information..."
    
    # Extract from CDK outputs
    BUCKET_NAME=$(jq -r '.BucketName' "$stack_outputs")
    DISTRIBUTION_ID=$(jq -r '.DistributionId' "$stack_outputs")
    DISTRIBUTION_DOMAIN=$(jq -r '.DistributionDomainName' "$stack_outputs")
    DISTRIBUTION_URL=$(jq -r '.DistributionUrl' "$stack_outputs")
    
    # Extract from inputs
    TARGET_PROFILE=$(jq -r '.targetProfile' "$inputs_file")
    TARGET_REGION=$(jq -r '.targetRegion' "$inputs_file")
    
    echo "S3 Bucket: $BUCKET_NAME"
    echo "CloudFront Distribution ID: $DISTRIBUTION_ID"
    echo "CloudFront Domain: $DISTRIBUTION_DOMAIN"
    echo "CloudFront URL: $DISTRIBUTION_URL"
    echo "AWS Profile: $TARGET_PROFILE"
    echo "AWS Region: $TARGET_REGION"
    
    # Validate extracted values
    if [[ -z "$BUCKET_NAME" || "$BUCKET_NAME" == "null" ]]; then
        echo "❌ Error: Could not extract S3 bucket name from CDK outputs."
        exit 1
    fi
    
    if [[ -z "$DISTRIBUTION_ID" || "$DISTRIBUTION_ID" == "null" ]]; then
        echo "❌ Error: Could not extract CloudFront distribution ID from CDK outputs."
        exit 1
    fi
    
    echo "✅ Deployment information extracted successfully"
}

# Function to upload files to S3
upload_to_s3() {
    echo "Uploading hello-world-html files to S3 bucket: $BUCKET_NAME"
    
    # Upload all files from hello-world-html directory
    aws s3 sync "$HELLO_WORLD_HTML_DIR" "s3://$BUCKET_NAME" \
        --profile "$TARGET_PROFILE" \
        --region "$TARGET_REGION" \
        --delete \
        --exact-timestamps
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ Files uploaded to S3 successfully"
        
        # List uploaded files for verification
        echo "Files in S3 bucket:"
        aws s3 ls "s3://$BUCKET_NAME" --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --recursive
        
        return 0
    else
        echo "❌ S3 upload failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Function to invalidate CloudFront cache
invalidate_cloudfront_cache() {
    echo "Invalidating CloudFront cache for distribution: $DISTRIBUTION_ID"
    
    # Create invalidation for all files
    local invalidation_id
    invalidation_id=$(aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/*" \
        --profile "$TARGET_PROFILE" \
        --query 'Invalidation.Id' \
        --output text)
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ CloudFront cache invalidation created successfully"
        echo "Invalidation ID: $invalidation_id"
        
        # Wait for invalidation to complete (optional, for verification)
        echo "Checking invalidation status..."
        aws cloudfront get-invalidation \
            --distribution-id "$DISTRIBUTION_ID" \
            --id "$invalidation_id" \
            --profile "$TARGET_PROFILE" \
            --query 'Invalidation.Status' \
            --output text
        
        return 0
    else
        echo "❌ CloudFront cache invalidation failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Function to verify content upload
verify_content_upload() {
    echo "Verifying content upload..."
    
    # Check if index.html exists in S3
    if aws s3api head-object \
        --bucket "$BUCKET_NAME" \
        --key "index.html" \
        --profile "$TARGET_PROFILE" \
        --region "$TARGET_REGION" > /dev/null 2>&1; then
        
        echo "✅ index.html verified in S3 bucket"
        
        # Get object details
        local last_modified content_length
        last_modified=$(aws s3api head-object \
            --bucket "$BUCKET_NAME" \
            --key "index.html" \
            --profile "$TARGET_PROFILE" \
            --region "$TARGET_REGION" \
            --query 'LastModified' \
            --output text)
        
        content_length=$(aws s3api head-object \
            --bucket "$BUCKET_NAME" \
            --key "index.html" \
            --profile "$TARGET_PROFILE" \
            --region "$TARGET_REGION" \
            --query 'ContentLength' \
            --output text)
        
        echo "Last Modified: $last_modified"
        echo "Content Length: $content_length bytes"
        
        return 0
    else
        echo "❌ index.html not found in S3 bucket"
        return 1
    fi
}

# Function to handle deployment errors
handle_deployment_error() {
    local exit_code=$1
    local operation="$2"
    
    echo "❌ Content deployment failed during $operation with exit code: $exit_code"
    echo "Common troubleshooting steps:"
    echo "1. Check AWS credentials and permissions for S3 and CloudFront"
    echo "2. Verify the S3 bucket exists and is accessible"
    echo "3. Verify the CloudFront distribution exists and is accessible"
    echo "4. Check if the hello-world-html files exist and are readable"
    echo
    
    return $exit_code
}

# Main content deployment function
deploy_content() {
    validate_prerequisites
    extract_deployment_info
    
    # Upload files to S3
    if ! upload_to_s3; then
        local exit_code=$?
        handle_deployment_error $exit_code "S3 upload"
        return $exit_code
    fi
    
    # Verify upload
    if ! verify_content_upload; then
        local exit_code=$?
        handle_deployment_error $exit_code "content verification"
        return $exit_code
    fi
    
    # Invalidate CloudFront cache
    if ! invalidate_cloudfront_cache; then
        local exit_code=$?
        handle_deployment_error $exit_code "CloudFront cache invalidation"
        return $exit_code
    fi
    
    echo "🎉 Content deployment completed successfully!"
    echo "Your application is now available at: $DISTRIBUTION_URL"
    echo
    echo "Note: CloudFront propagation may take a few minutes."
    echo "You can test the deployment using the validation script."
    
    return 0
}

# Global variables for extracted info
BUCKET_NAME=""
DISTRIBUTION_ID=""
DISTRIBUTION_DOMAIN=""
DISTRIBUTION_URL=""
TARGET_PROFILE=""
TARGET_REGION=""

# Main execution
main() {
    deploy_content
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 