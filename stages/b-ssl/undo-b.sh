#!/bin/bash

# undo-b.sh - Systematically undo/remove SSL configuration created by go-b.sh
# This script reverts to Stage A state or provides fallback to complete cleanup

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DATA_DIR="$SCRIPT_DIR/data"
STAGE_A_DIR="$SCRIPT_DIR/../a-cloudfront"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --force           Skip confirmation prompts and force cleanup
  --ssl-only        Only remove SSL certificates, keep CloudFront changes
  --data-only       Only clean up local data files, keep AWS resources
  --fallback-full   Use Stage A's undo-a.sh for complete cleanup
  -h, --help        Show this help message

Examples:
  $0                # Interactive SSL cleanup (recommended)
  $0 --force        # Force cleanup without prompts
  $0 --ssl-only     # Only remove SSL certificates
  $0 --data-only    # Only remove local data files
  $0 --fallback-full # Complete cleanup using Stage A's undo script

Notes:
  - This script removes SSL certificates and reverts CloudFront to Stage A state
  - DNS validation records are retained permanently as intended
  - Use --fallback-full if Stage B rollback fails and complete cleanup is needed

EOF
}

# Parse command line arguments
FORCE_CLEANUP=false
SSL_ONLY=false
DATA_ONLY=false
FALLBACK_FULL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --ssl-only)
            SSL_ONLY=true
            shift
            ;;
        --data-only)
            DATA_ONLY=true
            shift
            ;;
        --fallback-full)
            FALLBACK_FULL=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to print colored messages
print_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to confirm action with user
confirm_action() {
    local message="$1"
    
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        return 0  # Always confirm in force mode
    fi
    
    echo -e "${YELLOW}${message}${NC}"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "$YELLOW" "Operation cancelled by user."
        return 1
    fi
    return 0
}

# Function to load configuration from data files
load_configuration() {
    print_message "$BLUE" "📄 Loading Stage B configuration..."
    
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        print_message "$YELLOW" "⚠️  No Stage B inputs.json found - limited cleanup possible"
        return 1
    fi
    
    # Extract configuration
    INFRA_PROFILE=$(jq -r '.infraProfile // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
    TARGET_PROFILE=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
    DOMAINS=($(jq -r '.domains[]?' "$DATA_DIR/inputs.json" 2>/dev/null || echo ""))
    
    if [[ -z "$INFRA_PROFILE" ]] || [[ -z "$TARGET_PROFILE" ]]; then
        print_message "$RED" "❌ Could not load AWS profiles from inputs.json"
        return 1
    fi
    
    print_message "$GREEN" "✅ Configuration loaded:"
    print_message "$BLUE" "   Infrastructure Profile: $INFRA_PROFILE"
    print_message "$BLUE" "   Target Profile: $TARGET_PROFILE"
    print_message "$BLUE" "   Domains: ${DOMAINS[*]}"
    
    return 0
}

# Function to remove SSL certificate
remove_ssl_certificate() {
    if [[ ! -f "$DATA_DIR/outputs.json" ]]; then
        print_message "$YELLOW" "⚠️  No outputs.json found - cannot determine SSL certificate to remove"
        return 0
    fi
    
    local certificate_arn
    certificate_arn=$(jq -r '.certificateArn // empty' "$DATA_DIR/outputs.json" 2>/dev/null || echo "")
    
    if [[ -z "$certificate_arn" ]]; then
        print_message "$YELLOW" "⚠️  No SSL certificate ARN found in outputs.json"
        return 0
    fi
    
    print_message "$BLUE" "🔒 Removing SSL certificate..."
    print_message "$BLUE" "   Certificate ARN: $certificate_arn"
    
    if confirm_action "⚠️  This will permanently delete the SSL certificate. Continue?"; then
        # Check if certificate is still attached to CloudFront
        print_message "$BLUE" "   🔍 Checking if certificate is attached to CloudFront distributions..."
        
        local attached_distributions
        attached_distributions=$(aws cloudfront list-distributions --profile "$TARGET_PROFILE" --query "DistributionList.Items[?DistributionConfig.ViewerCertificate.ACMCertificateArn=='$certificate_arn'].Id" --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached_distributions" ]] && [[ "$attached_distributions" != "None" ]]; then
            print_message "$YELLOW" "⚠️  Certificate is still attached to CloudFront distributions: $attached_distributions"
            print_message "$YELLOW" "   You must remove CloudFront SSL configuration first"
            return 1
        fi
        
        # Attempt to delete the certificate
        print_message "$BLUE" "   🗑️  Deleting SSL certificate..."
        if aws acm delete-certificate --certificate-arn "$certificate_arn" --profile "$INFRA_PROFILE" --region us-east-1 2>/dev/null; then
            print_message "$GREEN" "✅ SSL certificate deleted successfully"
        else
            local exit_code=$?
            print_message "$RED" "❌ Failed to delete SSL certificate (exit code: $exit_code)"
            print_message "$YELLOW" "   This may be because the certificate is still in use or has dependencies"
            return $exit_code
        fi
    else
        print_message "$YELLOW" "⏭️  Skipping SSL certificate deletion"
    fi
}

# Function to revert CloudFront distribution to Stage A state
revert_cloudfront_distribution() {
    if [[ ! -f "$DATA_DIR/outputs.json" ]]; then
        print_message "$YELLOW" "⚠️  No outputs.json found - cannot determine CloudFront distribution to revert"
        return 0
    fi
    
    local distribution_id
    distribution_id=$(jq -r '.distributionId // empty' "$DATA_DIR/outputs.json" 2>/dev/null || echo "")
    
    if [[ -z "$distribution_id" ]]; then
        print_message "$YELLOW" "⚠️  No CloudFront distribution ID found in outputs.json"
        return 0
    fi
    
    print_message "$BLUE" "☁️  Reverting CloudFront distribution to Stage A state..."
    print_message "$BLUE" "   Distribution ID: $distribution_id"
    
    if confirm_action "⚠️  This will remove SSL certificate and custom domains from CloudFront. Continue?"; then
        # Get current distribution configuration
        print_message "$BLUE" "   📋 Getting current distribution configuration..."
        local dist_config
        dist_config=$(aws cloudfront get-distribution-config --id "$distribution_id" --profile "$TARGET_PROFILE" --output json 2>/dev/null || echo "{}")
        
        if [[ "$dist_config" == "{}" ]]; then
            print_message "$RED" "❌ Could not retrieve CloudFront distribution configuration"
            return 1
        fi
        
        local etag
        etag=$(echo "$dist_config" | jq -r '.ETag // empty' 2>/dev/null)
        
        if [[ -z "$etag" ]]; then
            print_message "$RED" "❌ Could not retrieve distribution ETag"
            return 1
        fi
        
        # Modify configuration to remove SSL and custom domains
        print_message "$BLUE" "   🔧 Removing SSL certificate and custom domains..."
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
            print_message "$RED" "❌ Failed to create updated distribution configuration"
            return 1
        fi
        
        # Apply the updated configuration
        print_message "$BLUE" "   📤 Applying updated configuration..."
        local update_result
        update_result=$(echo "$updated_config" | aws cloudfront update-distribution --id "$distribution_id" --distribution-config file:///dev/stdin --if-match "$etag" --profile "$TARGET_PROFILE" --output json 2>/dev/null || echo "{}")
        
        if [[ "$update_result" == "{}" ]]; then
            print_message "$RED" "❌ Failed to update CloudFront distribution"
            return 1
        fi
        
        print_message "$GREEN" "✅ CloudFront distribution reverted to Stage A state"
        print_message "$YELLOW" "⏳ CloudFront changes may take 15-45 minutes to propagate"
    else
        print_message "$YELLOW" "⏭️  Skipping CloudFront distribution reversion"
    fi
}

# Function to clean up local data files
cleanup_local_data() {
    print_message "$BLUE" "📁 Cleaning up local data files..."
    
    local files_to_remove=(
        "$DATA_DIR/inputs.json"
        "$DATA_DIR/discovery.json"
        "$DATA_DIR/outputs.json"
        "$DATA_DIR/cdk-outputs.json"
        "$DATA_DIR/cdk-stack-outputs.json"
    )
    
    local removed_count=0
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if confirm_action "Remove file: $(basename "$file")?"; then
                rm -f "$file"
                print_message "$GREEN" "✅ Removed: $(basename "$file")"
                ((removed_count++))
            else
                print_message "$YELLOW" "⏭️  Skipped: $(basename "$file")"
            fi
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        print_message "$GREEN" "✅ Cleaned up $removed_count local data files"
    else
        print_message "$BLUE" "📄 No local data files to clean up"
    fi
}

# Function to execute fallback cleanup using Stage A's undo script
execute_fallback_cleanup() {
    local stage_a_undo="$STAGE_A_DIR/undo-a.sh"
    
    if [[ ! -f "$stage_a_undo" ]]; then
        print_message "$RED" "❌ Stage A undo script not found at: $stage_a_undo"
        return 1
    fi
    
    if [[ ! -x "$stage_a_undo" ]]; then
        print_message "$YELLOW" "⚠️  Making Stage A undo script executable..."
        chmod +x "$stage_a_undo"
    fi
    
    print_message "$YELLOW" "🔄 Executing fallback cleanup using Stage A's undo script..."
    print_message "$YELLOW" "   This will remove the entire CloudFront distribution and all related resources"
    
    if confirm_action "⚠️  This will completely remove Stage A and Stage B deployments. Continue?"; then
        print_message "$BLUE" "   🚀 Executing: $stage_a_undo"
        
        if [[ "$FORCE_CLEANUP" == "true" ]]; then
            "$stage_a_undo" --force
        else
            "$stage_a_undo"
        fi
        
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            print_message "$GREEN" "✅ Fallback cleanup completed successfully"
            # Also clean up Stage B data files
            cleanup_local_data
        else
            print_message "$RED" "❌ Fallback cleanup failed with exit code: $exit_code"
            return $exit_code
        fi
    else
        print_message "$YELLOW" "⏭️  Fallback cleanup cancelled"
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    print_message "$BLUE" "📋 Stage B SSL Cleanup Summary"
    print_message "$BLUE" "══════════════════════════════"
    
    if [[ "$FALLBACK_FULL" == "true" ]]; then
        print_message "$YELLOW" "🔄 Fallback cleanup executed - both Stage A and Stage B resources removed"
    else
        print_message "$GREEN" "✅ Stage B SSL configuration removed"
        print_message "$BLUE" "   - SSL certificates deleted (if applicable)"
        print_message "$BLUE" "   - CloudFront reverted to Stage A state (if applicable)"
        print_message "$BLUE" "   - DNS validation records retained (as intended)"
        print_message "$BLUE" "   - Local data files cleaned up (if requested)"
    fi
    
    print_message "$BLUE" ""
    print_message "$BLUE" "Next steps:"
    if [[ "$FALLBACK_FULL" == "true" ]]; then
        print_message "$BLUE" "   - You can now re-run Stage A deployment from scratch"
    else
        print_message "$BLUE" "   - You can re-run Stage B deployment: ./go-b.sh -d [domains]"
        print_message "$BLUE" "   - Or proceed with Stage A state (HTTP-only access)"
    fi
}

# Main cleanup orchestration function
main_cleanup() {
    print_message "$BLUE" "🚀 AWS SPA Boilerplate - Stage B SSL Cleanup"
    print_message "$BLUE" "============================================="
    
    # Handle fallback cleanup first
    if [[ "$FALLBACK_FULL" == "true" ]]; then
        execute_fallback_cleanup
        show_cleanup_summary
        return $?
    fi
    
    # Load configuration if not doing data-only cleanup
    if [[ "$DATA_ONLY" != "true" ]]; then
        if ! load_configuration; then
            print_message "$RED" "❌ Could not load configuration - trying fallback cleanup"
            if confirm_action "Would you like to try fallback cleanup using Stage A's undo script?"; then
                execute_fallback_cleanup
                return $?
            else
                print_message "$RED" "❌ Cannot proceed without configuration"
                return 1
            fi
        fi
    fi
    
    # Execute cleanup steps based on options
    if [[ "$DATA_ONLY" == "true" ]]; then
        cleanup_local_data
    elif [[ "$SSL_ONLY" == "true" ]]; then
        remove_ssl_certificate
    else
        # Full Stage B cleanup
        print_message "$BLUE" "🔧 Executing full Stage B SSL cleanup..."
        
        # Step 1: Revert CloudFront distribution
        if ! revert_cloudfront_distribution; then
            print_message "$YELLOW" "⚠️  CloudFront reversion failed - SSL certificate removal may also fail"
        fi
        
        # Step 2: Remove SSL certificate
        if ! remove_ssl_certificate; then
            print_message "$YELLOW" "⚠️  SSL certificate removal failed"
        fi
        
        # Step 3: Clean up local data files
        cleanup_local_data
    fi
    
    show_cleanup_summary
}

# Function to handle cleanup on script interruption
cleanup_on_interrupt() {
    print_message "$YELLOW" ""
    print_message "$YELLOW" "⚠️  Cleanup interrupted by user (Ctrl+C)"
    print_message "$YELLOW" "Some resources may not have been cleaned up completely."
    print_message "$YELLOW" "You can re-run this script to continue cleanup."
    exit 130
}

# Set up interrupt handler
trap cleanup_on_interrupt INT TERM

# Main execution
main() {
    main_cleanup
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 