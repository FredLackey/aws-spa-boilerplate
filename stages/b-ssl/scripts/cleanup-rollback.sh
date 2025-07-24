#!/bin/bash

# cleanup-rollback.sh
# Cleanup and rollback for Stage B SSL Certificate deployment
# Removes SSL configuration and reverts CloudFront to Stage A state

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

echo "=== Stage B SSL Certificate Deployment - Cleanup and Rollback ==="
echo "This script will remove SSL configuration and revert to Stage A state."
echo

# Function to validate required files exist
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # We need at least inputs.json to know what to clean up
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found."
        echo "   Cannot determine what resources to clean up without configuration data."
        echo "   If you need to force cleanup, please run ../undo-b.sh instead."
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
}

# Function to confirm cleanup action
confirm_cleanup() {
    echo "⚠️  WARNING: This will remove SSL certificates and revert CloudFront to Stage A state!"
    echo
    echo "📋 What will be cleaned up:"
    echo "   - SSL certificates created by Stage B"
    echo "   - CloudFront SSL configuration (revert to HTTP-only)"
    echo "   - Custom domain aliases from CloudFront distribution"
    echo "   - Stage B deployment data files"
    echo
    echo "📋 What will be preserved:"
    echo "   - DNS validation records in Route53 (retained permanently)"
    echo "   - CloudFront distribution itself (reverted to Stage A state)"
    echo "   - S3 bucket and content from Stage A"
    echo "   - Stage A configuration and data"
    echo
    
    read -p "Do you want to continue with cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled by user."
        exit 0
    fi
    
    echo "✅ User confirmed cleanup - proceeding..."
}

# Function to revert CloudFront distribution to Stage A state
revert_cloudfront_distribution() {
    local target_profile="$1"
    local distribution_id="$2"
    
    echo "☁️  Reverting CloudFront distribution to Stage A state..."
    echo "   Distribution ID: $distribution_id"
    echo "   Target Profile: $target_profile"
    
    # Get current distribution configuration
    echo "   📥 Getting current distribution configuration..."
    local dist_config etag
    dist_config=$(aws cloudfront get-distribution-config --id "$distribution_id" --profile "$target_profile" --output json 2>/dev/null || echo "{}")
    
    if [[ "$dist_config" == "{}" ]]; then
        echo "❌ Could not retrieve CloudFront distribution configuration"
        return 1
    fi
    
    etag=$(echo "$dist_config" | jq -r '.ETag // empty')
    if [[ -z "$etag" ]]; then
        echo "❌ Could not retrieve distribution ETag"
        return 1
    fi
    
    # Check current configuration
    local current_aliases current_cert
    current_aliases=$(echo "$dist_config" | jq -r '.DistributionConfig.Aliases.Items[]?' 2>/dev/null | tr '\n' ' ' || echo "")
    current_cert=$(echo "$dist_config" | jq -r '.DistributionConfig.ViewerCertificate.ACMCertificateArn // empty' 2>/dev/null)
    
    echo "   📋 Current configuration:"
    echo "      Custom domains: ${current_aliases:-none}"
    echo "      SSL certificate: ${current_cert##*/}"
    
    if [[ -z "$current_aliases" ]] && [[ -z "$current_cert" ]]; then
        echo "✅ CloudFront distribution is already in Stage A state"
        return 0
    fi
    
    # Modify configuration to remove SSL and custom domains (revert to Stage A)
    echo "   🔧 Removing SSL certificate and custom domains..."
    local updated_config
    updated_config=$(echo "$dist_config" | jq '
        .DistributionConfig |
        .Aliases.Quantity = 0 |
        .Aliases.Items = [] |
        .ViewerCertificate = {
            "CloudFrontDefaultCertificate": true,
            "CertificateSource": "cloudfront"
        } |
        .DefaultCacheBehavior.ViewerProtocolPolicy = "allow-all"
    ' 2>/dev/null)
    
    if [[ -z "$updated_config" ]] || [[ "$updated_config" == "null" ]]; then
        echo "❌ Failed to create updated distribution configuration"
        return 1
    fi
    
    # Apply the updated configuration
    echo "   📤 Applying updated configuration..."
    local update_result
    update_result=$(echo "$updated_config" | aws cloudfront update-distribution --id "$distribution_id" --distribution-config file:///dev/stdin --if-match "$etag" --profile "$target_profile" --output json 2>/dev/null || echo "{}")
    
    if [[ "$update_result" == "{}" ]]; then
        echo "❌ Failed to update CloudFront distribution"
        return 1
    fi
    
    echo "✅ CloudFront distribution reverted to Stage A state"
    echo "   ⏳ Distribution changes may take 15-45 minutes to propagate"
    
    return 0
}

# Function to remove SSL certificate
remove_ssl_certificate() {
    local target_profile="$1"
    local cert_arn="$2"
    
    echo "🔒 Removing SSL certificate..."
    echo "   Certificate ARN: $cert_arn"
    echo "   Target Profile: $target_profile (environment-specific account)"
    
    # Check if certificate still exists
    echo "   🔍 Checking certificate status..."
    local cert_details
    cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --profile "$target_profile" --region us-east-1 --output json 2>/dev/null || echo '{}')
    
    if [[ "$cert_details" == "{}" ]]; then
        echo "✅ SSL certificate no longer exists or is not accessible"
        return 0
    fi
    
    local cert_status in_use_by
    cert_status=$(echo "$cert_details" | jq -r '.Certificate.Status // "UNKNOWN"' 2>/dev/null)
    in_use_by=$(echo "$cert_details" | jq -r '.Certificate.InUseBy[]?' 2>/dev/null | tr '\n' ' ' || echo "")
    
    echo "   📋 Certificate Status: $cert_status"
    echo "   📋 In Use By: ${in_use_by:-none}"
    
    # Check if certificate is still in use
    if [[ -n "$in_use_by" ]]; then
        echo "⚠️  Certificate is still in use by other resources:"
        echo "   $in_use_by"
        echo "   Cannot delete certificate while it's attached to resources"
        echo "   Please ensure CloudFront distribution has been updated first"
        return 1
    fi
    
    # Attempt to delete the certificate
    echo "   🗑️  Deleting SSL certificate..."
    if aws acm delete-certificate --certificate-arn "$cert_arn" --profile "$target_profile" --region us-east-1 2>/dev/null; then
        echo "✅ SSL certificate deleted successfully"
        return 0
    else
        local exit_code=$?
        echo "❌ Failed to delete SSL certificate (exit code: $exit_code)"
        echo "   This may be because:"
        echo "   - Certificate is still attached to CloudFront (wait for propagation)"
        echo "   - Certificate has other dependencies"
        echo "   - Insufficient permissions"
        return $exit_code
    fi
}

# Function to clean up CDK resources
cleanup_cdk_resources() {
    local infra_profile="$1"
    
    echo "🏗️  Cleaning up CDK resources..."
    echo "   Infrastructure Profile: $infra_profile"
    
    # Check if CDK directory exists
    local iac_dir="$STAGE_DIR/iac"
    if [[ ! -d "$iac_dir" ]]; then
        echo "✅ CDK directory does not exist - no CDK resources to clean up"
        return 0
    fi
    
    cd "$iac_dir"
    
    # Set AWS profile for CDK
    export AWS_PROFILE="$infra_profile"
    export AWS_DEFAULT_REGION="us-east-1"
    
    # Check if CDK stack exists
    echo "   🔍 Checking for existing CDK stacks..."
    local existing_stacks
    existing_stacks=$(npx cdk list 2>/dev/null | grep -E "StageBSslCertificateStack" || echo "")
    
    if [[ -z "$existing_stacks" ]]; then
        echo "✅ No CDK stacks found - nothing to destroy"
        return 0
    fi
    
    echo "   📋 Found CDK stacks to destroy:"
    echo "$existing_stacks" | sed 's/^/      - /'
    
    # Destroy the CDK stack
    echo "   🗑️  Destroying CDK stack..."
    if npx cdk destroy --force 2>&1 | tee "$DATA_DIR/cdk-destroy.log"; then
        echo "✅ CDK stack destroyed successfully"
        return 0
    else
        echo "❌ CDK stack destruction failed"
        echo "   Check the destruction log: $DATA_DIR/cdk-destroy.log"
        return 1
    fi
}

# Function to clean up local data files
cleanup_local_data() {
    echo "📁 Cleaning up local data files..."
    
    local files_to_remove=(
        "$DATA_DIR/outputs.json"
        "$DATA_DIR/cdk-outputs.json"
        "$DATA_DIR/cdk-stack-outputs.json"
        "$DATA_DIR/cdk-deploy.log"
        "$DATA_DIR/cdk-destroy.log"
        "$DATA_DIR/cdk-stack-list.json"
        "$DATA_DIR/.existing_cert_arn"
    )
    
    local removed_count=0
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            echo "   🗑️  Removing: $(basename "$file")"
            rm -f "$file"
            ((removed_count++))
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        echo "✅ Cleaned up $removed_count local data files"
    else
        echo "✅ No local data files to clean up"
    fi
    
    # Preserve inputs.json and discovery.json as they may be useful for re-deployment
    echo "📋 Preserved files for potential re-deployment:"
    echo "   - inputs.json (domain configuration)"
    echo "   - discovery.json (Route53 zone information)"
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo
    echo "📋 Stage B SSL Certificate Cleanup Summary"
    echo "══════════════════════════════════════════"
    echo "✅ SSL certificate configuration removed"
    echo "✅ CloudFront distribution reverted to Stage A state"
    echo "✅ Local deployment data cleaned up"
    echo
    echo "📋 Current State:"
    echo "   - CloudFront distribution: HTTP-only (Stage A state)"
    echo "   - SSL certificates: Removed"
    echo "   - DNS validation records: Retained in Route53 (as intended)"
    echo "   - Stage A resources: Unchanged and functional"
    echo
    echo "💡 Next Steps:"
    echo "   - Your application is now accessible via HTTP using the CloudFront URL"
    echo "   - You can re-run Stage B deployment if needed: ./go-b.sh -d [domains]"
    echo "   - Or proceed with Stage A configuration (HTTP-only)"
    echo "   - DNS validation records are retained for future certificate deployments"
}

# Main cleanup orchestration function
main_cleanup() {
    echo "Starting Stage B SSL certificate cleanup and rollback..."
    echo
    
    # Step 1: Validate prerequisites
    validate_prerequisites
    echo
    
    # Step 2: Load configuration
    local infra_profile target_profile distribution_id cert_arn
    infra_profile=$(jq -r '.infraProfile' "$DATA_DIR/inputs.json")
    target_profile=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    distribution_id=$(jq -r '.distributionId' "$DATA_DIR/inputs.json")
    
    # Certificate ARN might not exist if deployment failed early
    cert_arn=""
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        cert_arn=$(jq -r '.certificateArn // empty' "$DATA_DIR/outputs.json" 2>/dev/null || echo "")
    fi
    
    echo "📋 Cleanup Configuration:"
    echo "   Infrastructure Profile: $infra_profile"
    echo "   Target Profile: $target_profile"
    echo "   Distribution ID: $distribution_id"
    echo "   Certificate ARN: ${cert_arn:-none}"
    echo
    
    # Step 3: Confirm cleanup
    confirm_cleanup
    echo
    
    # Step 4: Revert CloudFront distribution
    echo "🔄 Step 1: Reverting CloudFront distribution to Stage A state..."
    if ! revert_cloudfront_distribution "$target_profile" "$distribution_id"; then
        echo "⚠️  CloudFront reversion failed - SSL certificate removal may also fail"
        echo "   Continuing with cleanup anyway..."
    fi
    echo
    
    # Step 5: Remove DNS validation records from infrastructure account Route53
    echo "🔄 Step 2: Removing DNS validation records from infrastructure account Route53..."
    echo "   Per architecture: DNS validation records managed in infrastructure account"
    
    local dns_script="$SCRIPT_DIR/manage-dns-validation.sh"
    if [[ -f "$dns_script" ]] && [[ -n "$cert_arn" ]] && [[ "$cert_arn" != "unknown" ]]; then
        if ! "$dns_script" remove; then
            echo "⚠️  DNS validation record removal failed or records already removed"
            echo "   This is usually not critical - continuing with cleanup..."
        fi
    else
        echo "   ℹ️  Skipping DNS validation cleanup (no certificate or script not found)"
    fi
    echo

    # Step 6: Remove SSL certificate (if it exists)
    if [[ -n "$cert_arn" ]] && [[ "$cert_arn" != "unknown" ]]; then
        echo "🔄 Step 3: Removing SSL certificate from environment account..."
        echo "   Per architecture: Certificate stored in environment-specific account"
        
        # Wait a bit for CloudFront changes to take effect
        echo "   ⏰ Waiting 30 seconds for CloudFront changes to propagate..."
        sleep 30
        
        if ! remove_ssl_certificate "$target_profile" "$cert_arn"; then
            echo "⚠️  SSL certificate removal failed"
            echo "   The certificate may still be in use or have dependencies"
            echo "   You can try running this cleanup script again in a few minutes"
        fi
    else
        echo "⏭️  Step 2: No SSL certificate to remove"
    fi
    echo
    
    # Step 6: Clean up CDK resources
    echo "🔄 Step 3: Cleaning up CDK infrastructure..."
    if ! cleanup_cdk_resources "$infra_profile"; then
        echo "⚠️  CDK cleanup failed - some resources may remain"
        echo "   You may need to clean up CDK resources manually"
    fi
    echo
    
    # Step 7: Clean up local data files
    echo "🔄 Step 4: Cleaning up local data files..."
    cleanup_local_data
    echo
    
    # Step 8: Display summary
    show_cleanup_summary
    
    echo "🎉 Stage B SSL certificate cleanup completed!"
    echo "   Your deployment has been reverted to Stage A state"
}

# Main execution
main() {
    main_cleanup
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 