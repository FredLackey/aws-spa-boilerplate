#!/bin/bash

# undo-a.sh - Systematically undo/remove everything created by go-a.sh
# This script provides a clean slate for testing Stage A deployment again

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DATA_DIR="$SCRIPT_DIR/data"

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
  --aws-only        Only clean up AWS resources, keep local data files
  --data-only       Only clean up local data files, keep AWS resources
  -h, --help        Show this help message

Examples:
  $0                # Interactive cleanup (recommended)
  $0 --force        # Force cleanup without prompts
  $0 --aws-only     # Only remove AWS resources
  $0 --data-only    # Only remove local data files

EOF
}

# Parse command line arguments
FORCE_CLEANUP=false
AWS_ONLY=false
DATA_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --aws-only)
            AWS_ONLY=true
            shift
            ;;
        --data-only)
            DATA_ONLY=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to confirm action
confirm_action() {
    local message="$1"
    
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}${message}${NC}"
    read -p "Do you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "$BLUE" "Operation cancelled by user."
        return 1
    fi
    return 0
}

# Function to check for in-progress CloudFront distributions
check_cloudfront_status() {
    print_status "$BLUE" "🔍 Checking for in-progress CloudFront distributions..."
    
    # Try to extract target profile from existing inputs.json if available
    print_status "$BLUE" "   📋 Looking for target profile in existing configuration..."
    local target_profile=""
    if [[ -f "$DATA_DIR/inputs.json" ]]; then
        print_status "$BLUE" "   📄 Found inputs.json, extracting profile..."
        target_profile=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
    fi
    
    # If no profile found, try default
    if [[ -z "$target_profile" ]]; then
        print_status "$YELLOW" "   ⚠️  No target profile found, checking with default profile"
        target_profile="default"
    fi
    
    print_status "$BLUE" "   🔑 Using AWS profile: $target_profile"
    print_status "$BLUE" "   🌐 Querying AWS CloudFront service for distribution status..."
    
    # Check for in-progress distributions
    local in_progress_distributions
    print_status "$BLUE" "   ⏳ Running: aws cloudfront list-distributions --profile $target_profile"
    in_progress_distributions=$(aws cloudfront list-distributions --profile "$target_profile" --query 'DistributionList.Items[?Status==`InProgress`].{Id:Id,Comment:Comment}' --output text 2>/dev/null || echo "")
    
    print_status "$BLUE" "   📊 CloudFront API query completed"
    
    if [[ -n "$in_progress_distributions" ]] && [[ "$in_progress_distributions" != "None" ]]; then
        print_status "$RED" "❌ CloudFront distributions currently in progress:"
        echo "$in_progress_distributions" | while read -r id comment; do
            [[ -n "$id" ]] && print_status "$RED" "   - Distribution ID: $id ($comment)"
        done
        echo
        print_status "$YELLOW" "⚠️  Cannot proceed with cleanup while CloudFront distributions are in progress."
        print_status "$BLUE" "   CloudFront operations can take 15-45 minutes to complete."
        print_status "$BLUE" "   Please wait for the distributions to reach 'Deployed' status before running cleanup."
        echo
        print_status "$BLUE" "💡 You can check status with:"
        print_status "$BLUE" "   aws cloudfront list-distributions --profile $target_profile --query 'DistributionList.Items[?Status==\`InProgress\`]'"
        echo
        exit 1
    fi
    
    print_status "$GREEN" "✅ No in-progress CloudFront distributions found"
}

# Function to check if deployment exists
check_deployment_exists() {
    print_status "$BLUE" "🔍 Checking for existing Stage A deployment..."
    
    local has_aws_resources=false
    local has_data_files=false
    
    # Check for data files
    if [[ -f "$DATA_DIR/inputs.json" ]] || [[ -f "$DATA_DIR/outputs.json" ]] || [[ -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        has_data_files=true
        print_status "$YELLOW" "   📁 Local data files found"
    fi
    
    # Check for AWS resources if we have deployment info
    if [[ -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        local distribution_id bucket_name
        distribution_id=$(jq -r '.distributionId // empty' "$DATA_DIR/cdk-stack-outputs.json" 2>/dev/null || echo "")
        bucket_name=$(jq -r '.bucketName // empty' "$DATA_DIR/cdk-stack-outputs.json" 2>/dev/null || echo "")
        
        if [[ -n "$distribution_id" ]] || [[ -n "$bucket_name" ]]; then
            has_aws_resources=true
            print_status "$YELLOW" "   ☁️  AWS resources found"
            [[ -n "$distribution_id" ]] && print_status "$YELLOW" "      - CloudFront Distribution: $distribution_id"
            [[ -n "$bucket_name" ]] && print_status "$YELLOW" "      - S3 Bucket: $bucket_name"
        fi
    fi
    
    if [[ "$has_aws_resources" == "false" ]] && [[ "$has_data_files" == "false" ]]; then
        print_status "$GREEN" "✅ No Stage A deployment found - nothing to clean up"
        exit 0
    fi
    
    echo
    print_status "$YELLOW" "⚠️  Stage A deployment detected!"
    if [[ "$has_aws_resources" == "true" ]]; then
        print_status "$YELLOW" "   - AWS resources will be permanently deleted"
        print_status "$YELLOW" "   - This action cannot be undone"
    fi
    if [[ "$has_data_files" == "true" ]]; then
        print_status "$YELLOW" "   - Local data files will be removed"
    fi
    echo
}

# Function to extract deployment information
extract_deployment_info() {
    local target_profile=""
    local distribution_prefix=""
    local target_region=""
    local distribution_id=""
    local bucket_name=""
    
    # Extract from inputs.json if available
    if [[ -f "$DATA_DIR/inputs.json" ]]; then
        target_profile=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        distribution_prefix=$(jq -r '.distributionPrefix // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        target_region=$(jq -r '.targetRegion // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
    fi
    
    # Extract from CDK outputs if available (CDK uses PascalCase field names)
    if [[ -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        distribution_id=$(jq -r '.DistributionId // empty' "$DATA_DIR/cdk-stack-outputs.json" 2>/dev/null || echo "")
        bucket_name=$(jq -r '.BucketName // empty' "$DATA_DIR/cdk-stack-outputs.json" 2>/dev/null || echo "")
    fi
    
    # Store in global variables for use by other functions
    DEPLOY_TARGET_PROFILE="$target_profile"
    DEPLOY_DISTRIBUTION_PREFIX="$distribution_prefix"
    DEPLOY_TARGET_REGION="$target_region"
    DEPLOY_DISTRIBUTION_ID="$distribution_id"
    DEPLOY_BUCKET_NAME="$bucket_name"
}

# Function to clean up AWS resources using targeted approach
cleanup_aws_resources() {
    if [[ "$DATA_ONLY" == "true" ]]; then
        print_status "$BLUE" "⏭️  Skipping AWS cleanup (--data-only flag)"
        return 0
    fi
    
    print_status "$BLUE" "☁️  Cleaning up AWS resources using deployment information..."
    
    # Check if we have the necessary information
    if [[ -z "$DEPLOY_TARGET_PROFILE" ]]; then
        print_status "$YELLOW" "⚠️  No target profile found - attempting cleanup with default profile"
        DEPLOY_TARGET_PROFILE="default"
    fi
    
    if [[ -z "$DEPLOY_TARGET_REGION" ]]; then
        print_status "$YELLOW" "⚠️  No target region found - using us-east-1"
        DEPLOY_TARGET_REGION="us-east-1"
    fi
    
    local cleanup_success=true
    
    # Step 1: Clean up S3 bucket first (must be empty before CDK can delete it)
    if [[ -n "$DEPLOY_BUCKET_NAME" ]]; then
        print_status "$BLUE" "   🪣 Cleaning up S3 bucket: $DEPLOY_BUCKET_NAME"
        if cleanup_s3_bucket_targeted; then
            print_status "$GREEN" "   ✅ S3 bucket cleanup completed"
        else
            print_status "$YELLOW" "   ⚠️  S3 bucket cleanup had issues (may already be cleaned)"
            cleanup_success=false
        fi
    else
        print_status "$BLUE" "   📋 No S3 bucket information found - skipping S3 cleanup"
    fi
    
    # Step 2: Clean up CDK stack using the correct profile and region
    print_status "$BLUE" "   📦 Cleaning up CDK infrastructure..."
    if cleanup_cdk_stack_targeted; then
        print_status "$GREEN" "   ✅ CDK stack cleanup completed"
    else
        print_status "$YELLOW" "   ⚠️  CDK stack cleanup had issues (may already be cleaned)"
        cleanup_success=false
    fi
    
    # Report final status
    if [[ "$cleanup_success" == "true" ]]; then
        print_status "$GREEN" "✅ AWS resources cleanup completed successfully"
    else
        print_status "$YELLOW" "⚠️  Some AWS resources may still exist - this is OK for repeated runs"
        print_status "$BLUE" "   You can run this script again or check AWS console manually"
    fi
    
    return 0  # Always return success to allow script to continue
}

# Function to clean up S3 bucket using targeted approach
cleanup_s3_bucket_targeted() {
    print_status "$BLUE" "      🔍 Checking S3 bucket existence: $DEPLOY_BUCKET_NAME"
    print_status "$BLUE" "      ⏳ Running: aws s3api head-bucket --bucket $DEPLOY_BUCKET_NAME --profile $DEPLOY_TARGET_PROFILE --region $DEPLOY_TARGET_REGION"
    
    # Check if bucket exists first
    if aws s3api head-bucket --bucket "$DEPLOY_BUCKET_NAME" --profile "$DEPLOY_TARGET_PROFILE" --region "$DEPLOY_TARGET_REGION" 2>/dev/null; then
        print_status "$BLUE" "      📊 S3 bucket exists, proceeding with cleanup"
        
        # Empty the bucket first
        print_status "$BLUE" "      🗑️  Emptying S3 bucket contents..."
        print_status "$BLUE" "      ⏳ Running: aws s3 rm s3://$DEPLOY_BUCKET_NAME --recursive --profile $DEPLOY_TARGET_PROFILE"
        
        if aws s3 rm "s3://$DEPLOY_BUCKET_NAME" --recursive --profile "$DEPLOY_TARGET_PROFILE" 2>/dev/null; then
            print_status "$GREEN" "      ✅ S3 bucket emptied successfully"
        else
            print_status "$YELLOW" "      ⚠️  Could not empty S3 bucket (may already be empty)"
        fi
        
        # Note: We don't delete the bucket here - CDK will handle that
        print_status "$BLUE" "      📋 S3 bucket prepared for CDK cleanup (CDK will delete the bucket)"
        return 0
    else
        print_status "$GREEN" "      ✅ S3 bucket does not exist (already cleaned up)"
        return 0
    fi
}

# Function to clean up CDK stack using targeted approach
cleanup_cdk_stack_targeted() {
    local iac_dir="$SCRIPT_DIR/iac"
    if [[ ! -d "$iac_dir" ]]; then
        print_status "$BLUE" "      📋 No IAC directory found - skipping CDK cleanup"
        return 0
    fi
    
    print_status "$BLUE" "      🔍 Checking for CDK stacks to destroy..."
    cd "$iac_dir"
    
    # Check if there are any stacks to destroy first
    print_status "$BLUE" "      ⏳ Running: npx cdk list --profile $DEPLOY_TARGET_PROFILE"
    local stacks_output
    stacks_output=$(npx cdk list --profile "$DEPLOY_TARGET_PROFILE" 2>/dev/null || echo "")
    print_status "$BLUE" "      📊 CDK list command completed"
    
    if [[ -n "$stacks_output" ]] && [[ "$stacks_output" != *"no stacks"* ]] && [[ "$stacks_output" != "" ]]; then
        print_status "$BLUE" "      🗑️  Destroying CDK stack(s): $stacks_output"
        print_status "$YELLOW" "      ⚠️  This may take several minutes - CDK is working..."
        print_status "$BLUE" "      ⏳ Running: npx cdk destroy --all --force --profile $DEPLOY_TARGET_PROFILE"
        
        # Set the correct region context for CDK
        export CDK_DEFAULT_REGION="$DEPLOY_TARGET_REGION"
        
        # Run CDK destroy with the correct profile and region
        if npx cdk destroy --all --force --profile "$DEPLOY_TARGET_PROFILE" --context "targetRegion=$DEPLOY_TARGET_REGION"; then
            print_status "$GREEN" "      ✅ CDK stack destroyed successfully"
            cd "$SCRIPT_DIR"
            return 0
        else
            print_status "$YELLOW" "      ⚠️  CDK destroy failed (stack may not exist or already destroyed)"
            cd "$SCRIPT_DIR"
            return 1
        fi
    else
        print_status "$GREEN" "      ✅ No CDK stacks found (already cleaned up)"
        cd "$SCRIPT_DIR"
        return 0
    fi
}

# Function to clean up local data files
cleanup_data_files() {
    if [[ "$AWS_ONLY" == "true" ]]; then
        print_status "$BLUE" "⏭️  Skipping data cleanup (--aws-only flag)"
        return 0
    fi
    
    print_status "$BLUE" "📁 Cleaning up local data files..."
    
    # Ensure data directory exists
    if [[ ! -d "$DATA_DIR" ]]; then
        print_status "$GREEN" "   ✅ Data directory doesn't exist (already cleaned up)"
        return 0
    fi
    
    local files_to_remove=(
        "$DATA_DIR/inputs.json"
        "$DATA_DIR/discovery.json"
        "$DATA_DIR/cdk-outputs.json"
        "$DATA_DIR/cdk-stack-outputs.json"
        "$DATA_DIR/outputs.json"
    )
    
    local removed_count=0
    local skipped_count=0
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file" 2>/dev/null; then
                print_status "$GREEN" "   ✅ Removed: $(basename "$file")"
                ((removed_count++))
            else
                print_status "$YELLOW" "   ⚠️  Could not remove: $(basename "$file") (permissions?)"
                ((skipped_count++))
            fi
        else
            print_status "$BLUE" "   ⏭️  Already removed: $(basename "$file")"
        fi
    done
    
    # Summary message
    if [[ $removed_count -gt 0 ]]; then
        print_status "$GREEN" "✅ Successfully removed $removed_count data files"
    fi
    
    if [[ $skipped_count -gt 0 ]]; then
        print_status "$YELLOW" "⚠️  Could not remove $skipped_count files (may require manual cleanup)"
    fi
    
    if [[ $removed_count -eq 0 ]] && [[ $skipped_count -eq 0 ]]; then
        print_status "$GREEN" "✅ All data files already cleaned up"
    fi
}

# Function to clean up CDK artifacts
cleanup_cdk_artifacts() {
    if [[ "$AWS_ONLY" == "true" ]]; then
        print_status "$BLUE" "⏭️  Skipping CDK artifacts cleanup (--aws-only flag)"
        return 0
    fi
    
    print_status "$BLUE" "🔧 Cleaning up CDK build artifacts..."
    
    local iac_dir="$SCRIPT_DIR/iac"
    if [[ ! -d "$iac_dir" ]]; then
        print_status "$GREEN" "   ✅ No IAC directory found (already cleaned up)"
        return 0
    fi
    
    cd "$iac_dir"
    
    local artifacts_removed=0
    
    # Remove CDK output directory
    if [[ -d "cdk.out" ]]; then
        if rm -rf cdk.out 2>/dev/null; then
            print_status "$GREEN" "   ✅ Removed cdk.out directory"
            ((artifacts_removed++))
        else
            print_status "$YELLOW" "   ⚠️  Could not remove cdk.out directory (permissions?)"
        fi
    else
        print_status "$BLUE" "   ⏭️  cdk.out directory already removed"
    fi
    
    # Remove compiled TypeScript files
    local js_files=($(find . -name "*.js" -not -path "./node_modules/*" 2>/dev/null || true))
    local d_ts_files=($(find . -name "*.d.ts" -not -path "./node_modules/*" 2>/dev/null || true))
    
    local compiled_files_removed=0
    for file in "${js_files[@]}" "${d_ts_files[@]}"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file" 2>/dev/null; then
                print_status "$GREEN" "   ✅ Removed: $file"
                ((compiled_files_removed++))
                ((artifacts_removed++))
            else
                print_status "$YELLOW" "   ⚠️  Could not remove: $file (permissions?)"
            fi
        fi
    done
    
    if [[ $compiled_files_removed -eq 0 ]] && [[ ${#js_files[@]} -eq 0 ]] && [[ ${#d_ts_files[@]} -eq 0 ]]; then
        print_status "$BLUE" "   ⏭️  No compiled TypeScript files found to remove"
    fi
    
    cd "$SCRIPT_DIR"
    
    # Summary
    if [[ $artifacts_removed -gt 0 ]]; then
        print_status "$GREEN" "✅ CDK artifacts cleanup completed ($artifacts_removed items removed)"
    else
        print_status "$GREEN" "✅ CDK artifacts already cleaned up"
    fi
}

# Function to completely clean up the data directory for a fresh start
cleanup_data_directory() {
    if [[ "$AWS_ONLY" == "true" ]]; then
        print_status "$BLUE" "⏭️  Skipping complete data directory cleanup (--aws-only flag)"
        return 0
    fi
    
    print_status "$BLUE" "🗂️  Performing complete data directory cleanup for fresh start..."
    
    # Ensure data directory exists
    if [[ ! -d "$DATA_DIR" ]]; then
        print_status "$GREEN" "   ✅ Data directory doesn't exist (already cleaned up)"
        return 0
    fi
    
    # Get list of all files in data directory
    local all_files=($(find "$DATA_DIR" -type f 2>/dev/null || true))
    local all_dirs=($(find "$DATA_DIR" -type d -not -path "$DATA_DIR" 2>/dev/null || true))
    
    local files_removed=0
    local dirs_removed=0
    local removal_errors=0
    
    # Remove all files
    if [[ ${#all_files[@]} -gt 0 ]]; then
        print_status "$BLUE" "   Removing all files from data directory..."
        for file in "${all_files[@]}"; do
            if rm -f "$file" 2>/dev/null; then
                print_status "$GREEN" "   ✅ Removed: $(basename "$file")"
                ((files_removed++))
            else
                print_status "$YELLOW" "   ⚠️  Could not remove: $(basename "$file") (permissions?)"
                ((removal_errors++))
            fi
        done
    fi
    
    # Remove all subdirectories
    if [[ ${#all_dirs[@]} -gt 0 ]]; then
        print_status "$BLUE" "   Removing all subdirectories from data directory..."
        # Sort directories by depth (deepest first) to avoid removal conflicts
        local sorted_dirs=($(printf '%s\n' "${all_dirs[@]}" | sort -r))
        for dir in "${sorted_dirs[@]}"; do
            if rmdir "$dir" 2>/dev/null; then
                print_status "$GREEN" "   ✅ Removed directory: $(basename "$dir")"
                ((dirs_removed++))
            else
                print_status "$YELLOW" "   ⚠️  Could not remove directory: $(basename "$dir") (not empty or permissions?)"
                ((removal_errors++))
            fi
        done
    fi
    
    # Final check - try to clean any remaining content
    if [[ -d "$DATA_DIR" ]]; then
        local remaining_items=($(find "$DATA_DIR" -mindepth 1 2>/dev/null || true))
        if [[ ${#remaining_items[@]} -gt 0 ]]; then
            print_status "$BLUE" "   Attempting to remove any remaining items..."
            if rm -rf "$DATA_DIR"/* 2>/dev/null; then
                print_status "$GREEN" "   ✅ Removed remaining items with rm -rf"
            else
                print_status "$YELLOW" "   ⚠️  Some items may still remain in data directory"
                ((removal_errors++))
            fi
        fi
    fi
    
    # Recreate empty .gitkeep file to maintain directory structure
    if [[ -d "$DATA_DIR" ]]; then
        if touch "$DATA_DIR/.gitkeep" 2>/dev/null; then
            print_status "$GREEN" "   ✅ Recreated .gitkeep file to maintain directory structure"
        else
            print_status "$YELLOW" "   ⚠️  Could not recreate .gitkeep file"
        fi
    fi
    
    # Summary
    local total_removed=$((files_removed + dirs_removed))
    if [[ $total_removed -gt 0 ]]; then
        print_status "$GREEN" "✅ Data directory cleanup completed"
        print_status "$GREEN" "   - Files removed: $files_removed"
        [[ $dirs_removed -gt 0 ]] && print_status "$GREEN" "   - Directories removed: $dirs_removed"
    fi
    
    if [[ $removal_errors -gt 0 ]]; then
        print_status "$YELLOW" "⚠️  $removal_errors items could not be removed (may require manual cleanup)"
        return 1
    fi
    
    if [[ $total_removed -eq 0 ]] && [[ ${#all_files[@]} -eq 0 ]] && [[ ${#all_dirs[@]} -eq 0 ]]; then
        print_status "$GREEN" "✅ Data directory was already clean"
    fi
    
    return 0
}

# Function to verify cleanup completion
verify_cleanup() {
    print_status "$BLUE" "🔍 Verifying cleanup completion..."
    
    local warnings_found=false
    local verification_errors=0
    
    # Check for remaining data files and directory cleanliness
    if [[ "$AWS_ONLY" != "true" ]] && [[ -d "$DATA_DIR" ]]; then
        local remaining_items=($(find "$DATA_DIR" -mindepth 1 -not -name ".gitkeep" 2>/dev/null || true))
        if [[ ${#remaining_items[@]} -gt 0 ]]; then
            print_status "$YELLOW" "   ⚠️  Some items still exist in data directory:"
            for item in "${remaining_items[@]}"; do
                if [[ -f "$item" ]]; then
                    print_status "$YELLOW" "      - File: $(basename "$item")"
                elif [[ -d "$item" ]]; then
                    print_status "$YELLOW" "      - Directory: $(basename "$item")"
                fi
            done
            warnings_found=true
        else
            print_status "$GREEN" "   ✅ Data directory completely cleaned (only .gitkeep remains)"
        fi
    fi
    
    # Check for AWS resources (basic check) - only if we have the necessary info
    if [[ "$DATA_ONLY" != "true" ]] && [[ -n "$DEPLOY_BUCKET_NAME" ]] && [[ -n "$DEPLOY_TARGET_PROFILE" ]]; then
        print_status "$BLUE" "   Checking if S3 bucket still exists..."
        if aws s3api head-bucket --bucket "$DEPLOY_BUCKET_NAME" --profile "$DEPLOY_TARGET_PROFILE" 2>/dev/null; then
            print_status "$YELLOW" "   ⚠️  S3 bucket still exists: $DEPLOY_BUCKET_NAME"
            print_status "$BLUE" "      This may be normal if cleanup is still in progress"
            warnings_found=true
        else
            print_status "$GREEN" "   ✅ S3 bucket successfully removed or doesn't exist"
        fi
    fi
    
    # Check for CDK stacks if we have the necessary info
    if [[ "$DATA_ONLY" != "true" ]] && [[ -n "$DEPLOY_TARGET_PROFILE" ]] && [[ -d "$SCRIPT_DIR/iac" ]]; then
        print_status "$BLUE" "   Checking for remaining CDK stacks..."
        cd "$SCRIPT_DIR/iac"
        local remaining_stacks
        remaining_stacks=$(npx cdk list --profile "$DEPLOY_TARGET_PROFILE" 2>/dev/null || echo "")
        cd "$SCRIPT_DIR"
        
        if [[ -n "$remaining_stacks" ]] && [[ "$remaining_stacks" != *"no stacks"* ]] && [[ "$remaining_stacks" != "" ]]; then
            print_status "$YELLOW" "   ⚠️  CDK stacks may still exist: $remaining_stacks"
            warnings_found=true
        else
            print_status "$GREEN" "   ✅ No CDK stacks found"
        fi
    fi
    
    # Final verification status
    if [[ "$warnings_found" == "false" ]]; then
        print_status "$GREEN" "✅ Cleanup verification passed - all resources appear to be cleaned up"
    else
        print_status "$YELLOW" "⚠️  Some resources may still exist"
        print_status "$BLUE" "   This is normal for repeated runs - resources may already be cleaned up"
        print_status "$BLUE" "   You can safely run this script again or check AWS console manually"
    fi
    
    return 0  # Always return success for verification to avoid blocking repeated runs
}

# Function to show cleanup summary
show_cleanup_summary() {
    local completed_steps="${1:-0}"
    local total_steps="${2:-4}"
    
    echo
    print_status "$GREEN" "🎉 Stage A Cleanup Summary"
    print_status "$GREEN" "=========================="
    
    print_status "$BLUE" "Cleanup Steps Completed: $completed_steps/$total_steps"
    echo
    
    if [[ "$DATA_ONLY" != "true" ]]; then
        print_status "$GREEN" "✅ AWS resources cleanup attempted (using deployment profiles)"
        print_status "$GREEN" "   - S3 bucket emptying (targeted cleanup)"
        print_status "$GREEN" "   - CDK stack destruction (with correct profile/region)"
    fi
    
    if [[ "$AWS_ONLY" != "true" ]]; then
        print_status "$GREEN" "✅ CDK build artifacts cleanup attempted"
        print_status "$GREEN" "✅ Local data files cleanup attempted (after AWS cleanup)"
        print_status "$GREEN" "✅ Complete data directory cleanup attempted"
    fi
    
    echo
    if [[ $completed_steps -eq $total_steps ]]; then
        print_status "$GREEN" "🎊 All cleanup steps completed successfully!"
        print_status "$BLUE" "🚀 Ready for fresh Stage A deployment!"
        print_status "$BLUE" "   You can now run ./go-a.sh again to start clean"
    else
        print_status "$YELLOW" "⚠️  Some cleanup steps had issues, but this is normal for repeated runs"
        print_status "$BLUE" "💡 Troubleshooting tips:"
        print_status "$BLUE" "   - Resources may already be cleaned up from previous runs"
        print_status "$BLUE" "   - AWS resources may take time to fully delete"
        print_status "$BLUE" "   - You can run this script again if needed"
        print_status "$BLUE" "   - Check AWS console manually if you're unsure"
        echo
        print_status "$BLUE" "🚀 You can still proceed with fresh deployment!"
        print_status "$BLUE" "   Run ./go-a.sh to start a new Stage A deployment"
    fi
    echo
}

# Main cleanup function
main_cleanup() {
    print_status "$BLUE" "🧹 AWS SPA Boilerplate - Stage A Cleanup"
    print_status "$BLUE" "========================================"
    echo
    
    # Pre-check: Ensure no CloudFront distributions are in progress
    check_cloudfront_status
    echo
    
    # Check what needs to be cleaned up
    check_deployment_exists
    
    # Confirm cleanup action
    if ! confirm_action "⚠️  This will permanently delete AWS resources and local data files."; then
        exit 0
    fi
    
    echo
    print_status "$BLUE" "🚀 Starting Stage A cleanup process..."
    print_status "$BLUE" "   (This script can be run repeatedly if steps fail)"
    echo
    
    # Extract deployment information
    extract_deployment_info
    
    # Perform cleanup steps with error handling
    # IMPORTANT: AWS cleanup must happen FIRST while JSON files are still available
    local cleanup_steps_completed=0
    local total_cleanup_steps=4
    
    # Step 1: AWS Resources (using JSON file information)
    print_status "$BLUE" "📋 Step 1 of $total_cleanup_steps: AWS Resources Cleanup"
    print_status "$BLUE" "   Using deployment information from JSON files for targeted cleanup"
    if cleanup_aws_resources; then
        ((cleanup_steps_completed++))
        print_status "$GREEN" "   ✅ AWS resources cleanup step completed"
    else
        print_status "$YELLOW" "   ⚠️  AWS resources cleanup had issues (this is OK for repeated runs)"
    fi
    echo
    
    # Step 2: CDK Build Artifacts (safe to clean while JSON files exist)
    print_status "$BLUE" "📋 Step 2 of $total_cleanup_steps: CDK Build Artifacts Cleanup"
    if cleanup_cdk_artifacts; then
        ((cleanup_steps_completed++))
        print_status "$GREEN" "   ✅ CDK artifacts cleanup step completed"
    else
        print_status "$YELLOW" "   ⚠️  CDK artifacts cleanup had issues"
    fi
    echo
    
    # Step 3: Local Data Files (NOW it's safe to remove JSON files)
    print_status "$BLUE" "📋 Step 3 of $total_cleanup_steps: Local Data Files Cleanup"
    print_status "$BLUE" "   Removing JSON files after AWS cleanup is complete"
    if cleanup_data_files; then
        ((cleanup_steps_completed++))
        print_status "$GREEN" "   ✅ Data files cleanup step completed"
    else
        print_status "$YELLOW" "   ⚠️  Data files cleanup had issues"
    fi
    echo
    
    # Step 4: Final Data Directory Cleanup (ensure completely clean state)
    print_status "$BLUE" "📋 Step 4 of $total_cleanup_steps: Complete Data Directory Cleanup"
    print_status "$BLUE" "   Ensuring data directory is completely clean for fresh start"
    if cleanup_data_directory; then
        ((cleanup_steps_completed++))
        print_status "$GREEN" "   ✅ Data directory cleanup step completed"
    else
        print_status "$YELLOW" "   ⚠️  Data directory cleanup had issues"
    fi
    echo
    
    # Verify cleanup
    print_status "$BLUE" "🔍 Final Verification Step"
    verify_cleanup
    echo
    
    # Show summary with completion status
    show_cleanup_summary "$cleanup_steps_completed" "$total_cleanup_steps"
}

# Function to handle cleanup on script interruption
cleanup_on_interrupt() {
    echo
    print_status "$YELLOW" "⚠️  Cleanup interrupted by user (Ctrl+C)"
    print_status "$YELLOW" "Some resources may still exist - run this script again to complete cleanup"
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
