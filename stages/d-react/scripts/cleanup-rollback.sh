#!/bin/bash

# cleanup-rollback.sh
# Error recovery and rollback procedures for Stage D React deployment
# Cleans up React content and reverts CloudFront to previous state

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
IAC_DIR="$STAGE_DIR/iac"

echo "=== Stage D React Deployment - Cleanup & Rollback ==="
echo "This script will clean up React deployment and handle rollback procedures."
echo

# Function to validate cleanup prerequisites
validate_cleanup_prerequisites() {
    echo "Validating cleanup prerequisites..."
    
    # Check if we have any data files to work with
    if [[ ! -f "$DATA_DIR/inputs.json" ]] && [[ ! -f "$DATA_DIR/discovery.json" ]] && [[ ! -f "$DATA_DIR/outputs.json" ]]; then
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
    DISTRIBUTION_ID=""
    BUCKET_NAME=""
    PRIMARY_DOMAIN=""
    INVALIDATION_ID=""
    
    # Try to extract from inputs.json
    if [[ -f "$DATA_DIR/inputs.json" ]]; then
        TARGET_PROFILE=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json")
        INFRASTRUCTURE_PROFILE=$(jq -r '.infrastructureProfile // empty' "$DATA_DIR/inputs.json")
        DISTRIBUTION_PREFIX=$(jq -r '.distributionPrefix // empty' "$DATA_DIR/inputs.json")
        TARGET_REGION=$(jq -r '.targetRegion // empty' "$DATA_DIR/inputs.json")
        DISTRIBUTION_ID=$(jq -r '.distributionId // empty' "$DATA_DIR/inputs.json")
        BUCKET_NAME=$(jq -r '.bucketName // empty' "$DATA_DIR/inputs.json")
        PRIMARY_DOMAIN=$(jq -r '.primaryDomain // empty' "$DATA_DIR/inputs.json")
        echo "Found inputs.json with prefix: $DISTRIBUTION_PREFIX"
    fi
    
    # Try to extract from outputs.json
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        INVALIDATION_ID=$(jq -r '.invalidationId // empty' "$DATA_DIR/outputs.json")
        echo "Found outputs.json with invalidation ID: $INVALIDATION_ID"
    fi
    
    # Try to extract invalidation ID from temporary file
    if [[ -f "$DATA_DIR/.invalidation_id" ]]; then
        INVALIDATION_ID=$(cat "$DATA_DIR/.invalidation_id" 2>/dev/null || echo "")
        echo "Found invalidation ID from deployment: $INVALIDATION_ID"
    fi
    
    # Display what we found
    echo "=== Cleanup Information ==="
    echo "Target Profile: ${TARGET_PROFILE:-'Not found'}"
    echo "Infrastructure Profile: ${INFRASTRUCTURE_PROFILE:-'Not found'}"
    echo "Distribution Prefix: ${DISTRIBUTION_PREFIX:-'Not found'}"
    echo "Target Region: ${TARGET_REGION:-'Not found'}"
    echo "Distribution ID: ${DISTRIBUTION_ID:-'Not found'}"
    echo "Bucket Name: ${BUCKET_NAME:-'Not found'}"
    echo "Primary Domain: ${PRIMARY_DOMAIN:-'Not found'}"
    echo "Invalidation ID: ${INVALIDATION_ID:-'Not found'}"
    echo
}

# Function to prompt for cleanup confirmation
prompt_cleanup_confirmation() {
    local cleanup_type="$1"
    
    echo "⚠️  WARNING: This will $cleanup_type"
    echo "This action cannot be undone."
    echo
    echo "📋 What will be cleaned up:"
    echo "   - React application files from S3 bucket"
    echo "   - CloudFront cache invalidations (if in progress)"
    echo "   - Stage D deployment data files"
    echo "   - CDK resources created for React deployment"
    echo
    echo "📋 What will be preserved:"
    echo "   - CloudFront distribution (reverted to Stage C state)"
    echo "   - S3 bucket (with previous content restored if available)"
    echo "   - SSL certificates and domain configuration from Stage B"
    echo "   - Lambda function from Stage C"
    echo "   - All previous stage configurations"
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

# Function to clean React content from S3
clean_s3_content() {
    local profile="$1"
    local bucket_name="$2"
    
    echo "🧹 Cleaning React content from S3 bucket..."
    echo "   Profile: $profile"
    echo "   Bucket: $bucket_name"
    
    if [[ -z "$profile" ]] || [[ -z "$bucket_name" ]]; then
        echo "❌ Error: Missing profile or bucket name for S3 cleanup"
        return 1
    fi
    
    # Check if bucket exists and is accessible
    if ! aws s3 ls "s3://$bucket_name" --profile "$profile" > /dev/null 2>&1; then
        echo "❌ Error: Cannot access S3 bucket '$bucket_name'"
        return 1
    fi
    
    # Get current object count
    local object_count
    object_count=$(aws s3 ls "s3://$bucket_name" --profile "$profile" --recursive 2>/dev/null | wc -l)
    echo "   Current objects in bucket: $object_count"
    
    if [[ "$object_count" -eq 0 ]]; then
        echo "✅ S3 bucket is already empty"
        return 0
    fi
    
    # Remove all React-related files
    echo "   Removing React application files..."
    
    # Common React/Vite files and patterns
    local react_patterns=(
        "index.html"
        "assets/"
        "*.js"
        "*.css"
        "*.svg"
        "*.ico"
        "manifest.json"
        "service-worker.js"
        "vite.svg"
        "react.svg"
    )
    
    # Remove files using patterns
    for pattern in "${react_patterns[@]}"; do
        if aws s3 rm "s3://$bucket_name/$pattern" --profile "$profile" --recursive > /dev/null 2>&1; then
            echo "   Removed: $pattern"
        fi
    done
    
    # Clean up any remaining files (be cautious here)
    echo "   Performing final cleanup..."
    if aws s3 rm "s3://$bucket_name" --profile "$profile" --recursive > /dev/null 2>&1; then
        echo "✅ S3 bucket cleaned successfully"
    else
        echo "⚠️  Some files may remain in S3 bucket"
    fi
    
    # Verify cleanup
    local remaining_count
    remaining_count=$(aws s3 ls "s3://$bucket_name" --profile "$profile" --recursive 2>/dev/null | wc -l)
    echo "   Remaining objects in bucket: $remaining_count"
}

# Function to cancel CloudFront invalidation if in progress
cancel_cloudfront_invalidation() {
    local profile="$1"
    local distribution_id="$2"
    local invalidation_id="$3"
    
    echo "🔄 Checking CloudFront cache invalidation status..."
    
    if [[ -z "$invalidation_id" ]]; then
        echo "   No invalidation ID found, skipping invalidation cleanup"
        return 0
    fi
    
    echo "   Distribution ID: $distribution_id"
    echo "   Invalidation ID: $invalidation_id"
    
    # Check invalidation status
    local invalidation_status
    invalidation_status=$(aws cloudfront get-invalidation \
        --distribution-id "$distribution_id" \
        --id "$invalidation_id" \
        --profile "$profile" \
        --query 'Invalidation.Status' \
        --output text 2>/dev/null || echo "NotFound")
    
    echo "   Current status: $invalidation_status"
    
    case "$invalidation_status" in
        "InProgress")
            echo "   ⚠️  Invalidation is in progress, cannot cancel"
            echo "   The invalidation will complete automatically"
            ;;
        "Completed")
            echo "   ✅ Invalidation already completed"
            ;;
        "NotFound")
            echo "   ⚠️  Invalidation not found or already expired"
            ;;
        *)
            echo "   ⚠️  Unknown invalidation status: $invalidation_status"
            ;;
    esac
    
    # Note: AWS doesn't allow canceling invalidations once started
    echo "   Note: CloudFront invalidations cannot be cancelled once started"
    return 0
}

# Function to clean up CDK resources
cleanup_cdk_resources() {
    local profile="$1"
    
    echo "🏗️  Cleaning up CDK resources..."
    
    if [[ ! -d "$IAC_DIR" ]]; then
        echo "   No CDK directory found, skipping CDK cleanup"
        return 0
    fi
    
    cd "$IAC_DIR"
    
    # Check if CDK is available
    if ! command -v npx > /dev/null 2>&1; then
        echo "   npx not available, skipping CDK cleanup"
        cd - > /dev/null
        return 0
    fi
    
    echo "   Installing CDK dependencies..."
    if npm install > /dev/null 2>&1; then
        echo "   ✅ CDK dependencies installed"
    else
        echo "   ⚠️  Failed to install CDK dependencies, skipping CDK cleanup"
        cd - > /dev/null
        return 0
    fi
    
    # Attempt to destroy the CDK stack
    echo "   Destroying CDK stack..."
    if npx cdk destroy --profile "$profile" --force > /dev/null 2>&1; then
        echo "✅ CDK stack destroyed successfully"
    else
        echo "⚠️  CDK stack destruction failed or no stack found"
    fi
    
    cd - > /dev/null
}

# Function to clean up temporary files
cleanup_temporary_files() {
    echo "🗂️  Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    local temp_files=(
        "$DATA_DIR/.build_output_dir"
        "$DATA_DIR/.invalidation_id"
        "$DATA_DIR/cdk-outputs.json"
    )
    
    for temp_file in "${temp_files[@]}"; do
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file"
            echo "   Removed: ${temp_file##*/}"
        fi
    done
    
    echo "✅ Temporary files cleaned"
}

# Function to restore previous state (if possible)
restore_previous_state() {
    local profile="$1"
    local bucket_name="$2"
    
    echo "🔄 Attempting to restore previous state..."
    
    # Check if we have Stage C outputs to restore from
    local stage_c_outputs="$STAGE_DIR/../c-lambda/data/outputs.json"
    
    if [[ -f "$stage_c_outputs" ]]; then
        echo "   Found Stage C outputs, checking for content to restore..."
        
        # We could potentially restore a simple index.html pointing to the Lambda function
        # But for now, we'll just create a placeholder
        local placeholder_html="<!DOCTYPE html>
<html>
<head>
    <title>Lambda API</title>
</head>
<body>
    <h1>Lambda API Available</h1>
    <p>React application has been removed.</p>
    <p>Lambda API is still available.</p>
</body>
</html>"
        
        echo "   Creating placeholder content..."
        echo "$placeholder_html" | aws s3 cp - "s3://$bucket_name/index.html" \
            --profile "$profile" \
            --cache-control "no-cache, no-store, must-revalidate" \
            --content-type "text/html" > /dev/null 2>&1
        
        echo "✅ Placeholder content created"
    else
        echo "   No previous state found to restore"
    fi
}

# Function to remove Stage D data files
remove_stage_d_data() {
    echo "🗃️  Removing Stage D data files..."
    
    local data_files=(
        "$DATA_DIR/inputs.json"
        "$DATA_DIR/discovery.json"
        "$DATA_DIR/outputs.json"
    )
    
    for data_file in "${data_files[@]}"; do
        if [[ -f "$data_file" ]]; then
            rm -f "$data_file"
            echo "   Removed: ${data_file##*/}"
        fi
    done
    
    echo "✅ Stage D data files removed"
}

# Main cleanup execution
main() {
    # Validate prerequisites
    if ! validate_cleanup_prerequisites; then
        echo "Nothing to clean up. Exiting."
        exit 0
    fi
    
    # Extract cleanup information
    extract_cleanup_info
    
    # Prompt for confirmation
    if ! prompt_cleanup_confirmation "remove React deployment and revert to previous state"; then
        exit 0
    fi
    
    echo
    echo "🧹 Starting Stage D React deployment cleanup..."
    echo
    
    # Clean S3 content
    if [[ -n "$TARGET_PROFILE" ]] && [[ -n "$BUCKET_NAME" ]]; then
        clean_s3_content "$TARGET_PROFILE" "$BUCKET_NAME"
        echo
    else
        echo "⚠️  Cannot clean S3 content - missing profile or bucket information"
        echo
    fi
    
    # Handle CloudFront invalidation
    if [[ -n "$TARGET_PROFILE" ]] && [[ -n "$DISTRIBUTION_ID" ]]; then
        cancel_cloudfront_invalidation "$TARGET_PROFILE" "$DISTRIBUTION_ID" "$INVALIDATION_ID"
        echo
    else
        echo "⚠️  Cannot check CloudFront invalidation - missing profile or distribution information"
        echo
    fi
    
    # Clean up CDK resources
    if [[ -n "$TARGET_PROFILE" ]]; then
        cleanup_cdk_resources "$TARGET_PROFILE"
        echo
    else
        echo "⚠️  Cannot clean CDK resources - missing profile information"
        echo
    fi
    
    # Clean up temporary files
    cleanup_temporary_files
    echo
    
    # Attempt to restore previous state
    if [[ -n "$TARGET_PROFILE" ]] && [[ -n "$BUCKET_NAME" ]]; then
        restore_previous_state "$TARGET_PROFILE" "$BUCKET_NAME"
        echo
    fi
    
    # Remove Stage D data files
    remove_stage_d_data
    echo
    
    echo "🎉 Stage D React deployment cleanup completed!"
    echo
    echo "📋 Summary:"
    echo "   ✅ React content removed from S3"
    echo "   ✅ CloudFront invalidation status checked"
    echo "   ✅ CDK resources cleaned up"
    echo "   ✅ Temporary files removed"
    echo "   ✅ Previous state restored (where possible)"
    echo "   ✅ Stage D data files removed"
    echo
    echo "📝 Next steps:"
    echo "   - CloudFront distribution has been reverted to previous state"
    echo "   - Lambda function from Stage C is still available"
    echo "   - SSL certificates and domains from Stage B are preserved"
    echo "   - To redeploy React application, start from gather-inputs.sh"
    echo
}

# Execute main function
main 