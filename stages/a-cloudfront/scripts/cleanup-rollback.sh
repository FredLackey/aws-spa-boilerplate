#!/bin/bash

# cleanup-rollback.sh
# Error recovery and rollback procedures for Stage A CloudFront deployment
# Cleans up partial deployments and orphaned resources

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
IAC_DIR="$STAGE_DIR/iac"

echo "=== Stage A CloudFront Deployment - Cleanup & Rollback ==="
echo "This script will clean up AWS resources and handle rollback procedures."
echo

# Function to validate prerequisites for cleanup
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
    DISTRIBUTION_ID=""
    BUCKET_NAME=""
    
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
        DISTRIBUTION_ID=$(jq -r '.DistributionId // empty' "$DATA_DIR/cdk-stack-outputs.json")
        BUCKET_NAME=$(jq -r '.BucketName // empty' "$DATA_DIR/cdk-stack-outputs.json")
        echo "Found CDK outputs with distribution ID: $DISTRIBUTION_ID"
        echo "Found bucket name: $BUCKET_NAME"
    fi
    
    # Display what we found
    echo "=== Cleanup Information ==="
    echo "Target Profile: ${TARGET_PROFILE:-'Not found'}"
    echo "Infrastructure Profile: ${INFRASTRUCTURE_PROFILE:-'Not found'}"
    echo "Distribution Prefix: ${DISTRIBUTION_PREFIX:-'Not found'}"
    echo "Target Region: ${TARGET_REGION:-'Not found'}"
    echo "Distribution ID: ${DISTRIBUTION_ID:-'Not found'}"
    echo "Bucket Name: ${BUCKET_NAME:-'Not found'}"
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

# Function to empty and delete S3 bucket
cleanup_s3_bucket() {
    local bucket_name="$1"
    local profile="$2"
    local region="$3"
    
    if [[ -z "$bucket_name" || -z "$profile" ]]; then
        echo "⚠️  Insufficient information to clean up S3 bucket"
        return 1
    fi
    
    echo "Cleaning up S3 bucket: $bucket_name"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" --profile "$profile" --region "$region" 2>/dev/null; then
        echo "✅ S3 bucket does not exist or is already deleted"
        return 0
    fi
    
    # Empty the bucket first
    echo "Emptying S3 bucket contents..."
    aws s3 rm "s3://$bucket_name" --recursive --profile "$profile" --region "$region" 2>/dev/null || true
    
    # Delete the bucket
    echo "Deleting S3 bucket..."
    if aws s3api delete-bucket --bucket "$bucket_name" --profile "$profile" --region "$region" 2>/dev/null; then
        echo "✅ S3 bucket deleted successfully"
        return 0
    else
        echo "⚠️  S3 bucket deletion failed - it may have been deleted already or have remaining objects"
        return 1
    fi
}

# Function to delete CloudFront distribution
cleanup_cloudfront_distribution() {
    local distribution_id="$1"
    local profile="$2"
    
    if [[ -z "$distribution_id" || -z "$profile" ]]; then
        echo "⚠️  Insufficient information to clean up CloudFront distribution"
        return 1
    fi
    
    echo "Cleaning up CloudFront distribution: $distribution_id"
    
    # Check if distribution exists and get its current state
    local distribution_status
    distribution_status=$(aws cloudfront get-distribution --id "$distribution_id" --profile "$profile" --query 'Distribution.Status' --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$distribution_status" == "NotFound" ]]; then
        echo "✅ CloudFront distribution does not exist or is already deleted"
        return 0
    fi
    
    echo "Current distribution status: $distribution_status"
    
    # Disable the distribution first if it's enabled
    local enabled
    enabled=$(aws cloudfront get-distribution --id "$distribution_id" --profile "$profile" --query 'Distribution.DistributionConfig.Enabled' --output text 2>/dev/null || echo "false")
    
    if [[ "$enabled" == "true" ]]; then
        echo "Disabling CloudFront distribution..."
        
        # Get current distribution config
        aws cloudfront get-distribution-config --id "$distribution_id" --profile "$profile" > /tmp/distribution-config.json 2>/dev/null || {
            echo "❌ Failed to get distribution config"
            return 1
        }
        
        # Extract ETag and modify config to disable
        local etag
        etag=$(jq -r '.ETag' /tmp/distribution-config.json)
        jq '.DistributionConfig.Enabled = false' /tmp/distribution-config.json > /tmp/distribution-config-disabled.json
        
        # Update distribution to disable it
        aws cloudfront update-distribution \
            --id "$distribution_id" \
            --distribution-config file:///tmp/distribution-config-disabled.json \
            --if-match "$etag" \
            --profile "$profile" > /dev/null 2>&1 || {
            echo "❌ Failed to disable distribution"
            return 1
        }
        
        echo "⏳ Distribution disabled. Waiting for deployment to complete..."
        echo "This may take several minutes..."
        
        # Wait for distribution to be in Deployed state
        local max_wait=600  # 10 minutes
        local wait_time=0
        while [[ $wait_time -lt $max_wait ]]; do
            distribution_status=$(aws cloudfront get-distribution --id "$distribution_id" --profile "$profile" --query 'Distribution.Status' --output text 2>/dev/null || echo "NotFound")
            
            if [[ "$distribution_status" == "Deployed" ]]; then
                echo "✅ Distribution is now deployed and disabled"
                break
            fi
            
            echo "Current status: $distribution_status (waiting...)"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            echo "⚠️  Timeout waiting for distribution to be deployed"
            echo "You may need to wait longer and delete the distribution manually"
            return 1
        fi
    fi
    
    # Now delete the distribution
    echo "Deleting CloudFront distribution..."
    
    # Get fresh ETag for deletion
    local delete_etag
    delete_etag=$(aws cloudfront get-distribution --id "$distribution_id" --profile "$profile" --query 'ETag' --output text 2>/dev/null || echo "")
    
    if [[ -n "$delete_etag" ]]; then
        if aws cloudfront delete-distribution --id "$distribution_id" --if-match "$delete_etag" --profile "$profile" 2>/dev/null; then
            echo "✅ CloudFront distribution deletion initiated"
            echo "Note: Complete deletion may take additional time to propagate"
            return 0
        else
            echo "❌ Failed to delete CloudFront distribution"
            return 1
        fi
    else
        echo "❌ Could not get ETag for distribution deletion"
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
    local distribution_id="$1"
    local bucket_name="$2"
    local profile="$3"
    
    echo "Verifying cleanup completion..."
    
    local cleanup_complete=true
    
    # Check CloudFront distribution
    if [[ -n "$distribution_id" && -n "$profile" ]]; then
        if aws cloudfront get-distribution --id "$distribution_id" --profile "$profile" > /dev/null 2>&1; then
            echo "⚠️  CloudFront distribution still exists (may be in process of deletion)"
            cleanup_complete=false
        else
            echo "✅ CloudFront distribution verified as deleted"
        fi
    fi
    
    # Check S3 bucket
    if [[ -n "$bucket_name" && -n "$profile" ]]; then
        if aws s3api head-bucket --bucket "$bucket_name" --profile "$profile" > /dev/null 2>&1; then
            echo "⚠️  S3 bucket still exists"
            cleanup_complete=false
        else
            echo "✅ S3 bucket verified as deleted"
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
    echo "If you need to restart Stage A deployment:"
    echo "1. Ensure all resources have been cleaned up"
    echo "2. Run ./gather-inputs.sh to collect deployment parameters"
    echo "3. Run ./aws-discovery.sh to validate AWS access"
    echo "4. Run ./deploy-infrastructure.sh to redeploy infrastructure"
    echo "5. Run ./deploy-content.sh to upload application files"
    echo "6. Run ./validate-deployment.sh to test the deployment"
    echo
    echo "If cleanup was partial:"
    echo "1. Check AWS Console for remaining CloudFront distributions"
    echo "2. Check AWS Console for remaining S3 buckets"
    echo "3. Wait for CloudFront propagation if distribution is still deleting"
    echo "4. Manually clean up any remaining resources if needed"
    echo
}

# Main cleanup function with different modes
cleanup_deployment() {
    local cleanup_mode="${1:-full}"
    
    case "$cleanup_mode" in
        "full")
            if ! prompt_cleanup_confirmation "delete ALL Stage A resources and data files"; then
                exit 1
            fi
            ;;
        "resources")
            if ! prompt_cleanup_confirmation "delete AWS resources but keep data files"; then
                exit 1
            fi
            ;;
        "data")
            if ! prompt_cleanup_confirmation "delete data files but keep AWS resources"; then
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
        if [[ -n "$DISTRIBUTION_ID" && -n "$TARGET_PROFILE" ]]; then
            cleanup_cloudfront_distribution "$DISTRIBUTION_ID" "$TARGET_PROFILE"
        fi
        
        if [[ -n "$BUCKET_NAME" && -n "$TARGET_PROFILE" && -n "$TARGET_REGION" ]]; then
            cleanup_s3_bucket "$BUCKET_NAME" "$TARGET_PROFILE" "$TARGET_REGION"
        fi
    fi
    
    # Clean up data files
    if [[ "$cleanup_mode" == "full" || "$cleanup_mode" == "data" ]]; then
        cleanup_data_files
    fi
    
    # Verify cleanup
    if [[ "$cleanup_mode" == "full" ]]; then
        if verify_cleanup "$DISTRIBUTION_ID" "$BUCKET_NAME" "$TARGET_PROFILE"; then
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
DISTRIBUTION_ID=""
BUCKET_NAME=""

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