#!/bin/bash

# undo-c.sh
# Complete rollback script for Stage C Lambda deployment
# Removes all Lambda resources and reverts to pre-Stage C state

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DATA_DIR="$SCRIPT_DIR/data"

echo "=== Stage C Lambda Deployment - Complete Rollback ==="
echo "This script will completely remove all Stage C Lambda resources."
echo

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

This script will completely remove all Stage C Lambda resources and revert
to the state before Stage C deployment.

Options:
  -h, --help           Show this help message
  --force              Skip confirmation prompts (use with caution)

Examples:
  $0                   # Interactive rollback with confirmation
  $0 --force           # Automatic rollback without confirmation

Warning:
  This action cannot be undone. All Lambda function data, logs, and
  configurations will be permanently deleted.

EOF
}

# Parse command line arguments
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to validate rollback prerequisites
validate_rollback_prerequisites() {
    echo "Validating rollback prerequisites..."
    
    # Check if cleanup script exists
    if [[ ! -f "$SCRIPTS_DIR/cleanup-rollback.sh" ]]; then
        echo "❌ Error: cleanup-rollback.sh script not found."
        echo "Cannot perform rollback without the cleanup script."
        exit 1
    fi
    
    # Make sure cleanup script is executable
    if [[ ! -x "$SCRIPTS_DIR/cleanup-rollback.sh" ]]; then
        echo "Making cleanup-rollback.sh executable..."
        chmod +x "$SCRIPTS_DIR/cleanup-rollback.sh"
    fi
    
    # Check if there's anything to rollback
    if [[ ! -f "$DATA_DIR/inputs.json" ]] && [[ ! -f "$DATA_DIR/discovery.json" ]] && [[ ! -f "$DATA_DIR/cdk-stack-outputs.json" ]]; then
        echo "⚠️  No Stage C deployment data found."
        echo "There may be nothing to rollback, but will proceed anyway."
    fi
    
    echo "✅ Rollback prerequisites validated"
}

# Function to display rollback warning
display_rollback_warning() {
    if [[ "$FORCE_MODE" == true ]]; then
        echo "🚨 FORCE MODE: Skipping confirmation prompts"
        return 0
    fi
    
    echo
    echo "🚨 WARNING: COMPLETE STAGE C ROLLBACK"
    echo "======================================"
    echo
    echo "This operation will PERMANENTLY DELETE:"
    echo "  ❌ Lambda function and all its code"
    echo "  ❌ Function URL configuration"
    echo "  ❌ IAM execution role and policies"
    echo "  ❌ CloudWatch log group and all logs"
    echo "  ❌ All Stage C deployment data files"
    echo
    echo "After rollback:"
    echo "  ✅ Stage A (CloudFront) will remain intact"
    echo "  ✅ Stage B (SSL Certificate) will remain intact"
    echo "  ❌ Stage C (Lambda) will be completely removed"
    echo
    echo "This action CANNOT be undone!"
    echo
    echo "Are you absolutely sure you want to proceed? (type 'yes' to confirm)"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        echo "❌ Rollback cancelled by user"
        echo "No changes have been made to your deployment."
        exit 0
    fi
    
    echo "✅ User confirmed complete rollback"
}

# Function to check Stage A and B status
check_prerequisite_stages() {
    echo "🔍 Checking Stage A and B status..."
    
    local stage_a_outputs="../a-cloudfront/data/outputs.json"
    local stage_b_outputs="../b-ssl/data/outputs.json"
    
    # Check Stage A
    if [[ -f "$stage_a_outputs" ]]; then
        local ready_for_stage_b
        ready_for_stage_b=$(jq -r '.readyForStageB // false' "$stage_a_outputs" 2>/dev/null || echo "false")
        
        if [[ "$ready_for_stage_b" == "true" ]]; then
            echo "✅ Stage A (CloudFront) is healthy"
        else
            echo "⚠️  Stage A may have issues - check status after rollback"
        fi
    else
        echo "⚠️  Stage A outputs not found - may have been removed"
    fi
    
    # Check Stage B
    if [[ -f "$stage_b_outputs" ]]; then
        local ready_for_stage_c
        ready_for_stage_c=$(jq -r '.readyForStageC // false' "$stage_b_outputs" 2>/dev/null || echo "false")
        
        if [[ "$ready_for_stage_c" == "true" ]]; then
            echo "✅ Stage B (SSL Certificate) is healthy"
        else
            echo "⚠️  Stage B may have issues - check status after rollback"
        fi
    else
        echo "⚠️  Stage B outputs not found - may have been removed"
    fi
    
    echo "✅ Prerequisite stage check completed"
}

# Function to execute rollback
execute_rollback() {
    echo
    echo "🚀 Starting Stage C Lambda rollback..."
    echo "======================================="
    
    # Execute the cleanup script in full mode
    echo "Executing complete cleanup of all Stage C resources..."
    
    if [[ "$FORCE_MODE" == true ]]; then
        # In force mode, we need to automatically answer "yes" to the cleanup script
        echo "yes" | "$SCRIPTS_DIR/cleanup-rollback.sh" full
    else
        # Normal mode - let cleanup script handle its own prompts
        "$SCRIPTS_DIR/cleanup-rollback.sh" full
    fi
    
    local cleanup_exit_code=$?
    
    if [[ $cleanup_exit_code -eq 0 ]]; then
        echo
        echo "✅ Stage C Lambda rollback completed successfully"
        return 0
    else
        echo
        echo "❌ Stage C Lambda rollback encountered issues (exit code: $cleanup_exit_code)"
        echo "Some resources may not have been cleaned up completely."
        echo "Check the error messages above and consider manual cleanup if needed."
        return $cleanup_exit_code
    fi
}

# Function to display rollback summary
display_rollback_summary() {
    local rollback_success=$1
    
    echo
    echo "🎯 Stage C Lambda Rollback Summary"
    echo "=================================="
    
    if [[ $rollback_success -eq 0 ]]; then
        echo "✅ Rollback Status: SUCCESSFUL"
        echo
        echo "Stage C Lambda resources have been removed:"
        echo "  ✅ Lambda function deleted"
        echo "  ✅ Function URL removed"
        echo "  ✅ IAM execution role deleted"
        echo "  ✅ CloudWatch log group deleted"
        echo "  ✅ Deployment data files cleaned up"
        echo
        echo "Your deployment is now back to Stage B state:"
        echo "  ✅ Stage A (CloudFront) - Active"
        echo "  ✅ Stage B (SSL Certificate) - Active"
        echo "  ❌ Stage C (Lambda) - Removed"
        echo
        echo "Next steps:"
        echo "  - Your CloudFront distribution with SSL is still active"
        echo "  - You can re-deploy Stage C by running: ./go-c.sh"
        echo "  - Or proceed to Stage D if you have another Lambda implementation"
    else
        echo "⚠️  Rollback Status: PARTIAL"
        echo
        echo "The rollback completed with some issues."
        echo "Some Stage C resources may still exist."
        echo
        echo "Recommended actions:"
        echo "  1. Check AWS Console for any remaining Lambda resources"
        echo "  2. Manually delete any remaining resources if needed"
        echo "  3. Verify Stage A and B are still working properly"
        echo "  4. Contact support if you need assistance with manual cleanup"
    fi
    
    echo
    echo "🔧 Available commands:"
    echo "  - Check Stage A status: cd ../a-cloudfront && ./status-a.sh"
    echo "  - Check Stage B status: cd ../b-ssl && ./status-b.sh"
    echo "  - Re-deploy Stage C: ./go-c.sh"
}

# Function to handle script interruption
handle_interruption() {
    echo
    echo "⚠️  Rollback interrupted by user (Ctrl+C)"
    echo "The rollback may be in an incomplete state."
    echo
    echo "Recommended actions:"
    echo "  1. Check AWS Console to see what resources remain"
    echo "  2. Re-run this script to complete the rollback: ./undo-c.sh"
    echo "  3. Or run the cleanup script directly: ./scripts/cleanup-rollback.sh full"
    echo
    exit 130
}

# Set up interrupt handler
trap handle_interruption INT TERM

# Main execution function
main_rollback() {
    validate_rollback_prerequisites
    display_rollback_warning
    check_prerequisite_stages
    
    local rollback_result=0
    execute_rollback || rollback_result=$?
    
    display_rollback_summary $rollback_result
    
    return $rollback_result
}

# Main execution
main() {
    main_rollback
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 