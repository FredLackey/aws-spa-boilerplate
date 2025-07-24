#!/bin/bash

# go-c.sh
# Main orchestration script for Stage C Lambda deployment
# Coordinates the entire Lambda deployment workflow by calling helper scripts sequentially

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DATA_DIR="$SCRIPT_DIR/data"

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Stage C Lambda deployment requires successful completion of Stage A and Stage B.
No additional command line arguments are required - all configuration is derived
from previous stage outputs.

Examples:
  $0                    # Deploy Lambda function using Stage A and B outputs
  $0 -h                 # Show this help message

Notes:
  - Stage A (CloudFront) must be completed successfully
  - Stage B (SSL Certificate) must be completed successfully  
  - Lambda function will be deployed with Function URL for API access
  - All configuration is automatically derived from previous stages

EOF
}

# Parse and store command line arguments
SCRIPT_ARGS=("$@")

# Check for help flag first
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        show_usage
        exit 0
    fi
done

# Validate that we don't have unexpected arguments
if [[ $# -gt 0 ]]; then
    echo "❌ Error: Stage C does not accept command line arguments."
    echo "All configuration is derived from Stage A and B outputs."
    echo
    show_usage
    exit 1
fi

echo "🚀 AWS SPA Boilerplate - Stage C Lambda Deployment"
echo "=================================================="
echo "This script will deploy a Lambda function with Function URL for API access."
echo "Each step builds upon the previous one, so please complete them in order."
echo

# Function to check if all helper scripts exist
validate_helper_scripts() {
    echo "Validating helper scripts..."
    
    local required_scripts=(
        "gather-inputs.sh"
        "aws-discovery.sh"
        "deploy-infrastructure.sh"
        "validate-deployment.sh"
        "cleanup-rollback.sh"
    )
    
    local missing_scripts=()
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPTS_DIR/$script" ]]; then
            missing_scripts+=("$script")
        elif [[ ! -x "$SCRIPTS_DIR/$script" ]]; then
            echo "⚠️  Making $script executable..."
            chmod +x "$SCRIPTS_DIR/$script"
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        echo "❌ Missing required helper scripts:"
        printf "   - %s\n" "${missing_scripts[@]}"
        echo "Please ensure all helper scripts are present before running this script."
        exit 1
    fi
    
    echo "✅ All helper scripts validated"
}

# Function to display deployment progress
show_progress() {
    local step="$1"
    local total="$2"
    local description="$3"
    
    echo
    echo "📋 Step $step of $total: $description"
    echo "$(printf '%.0s─' {1..60})"
}

# Function to handle script errors
handle_script_error() {
    local script_name="$1"
    local exit_code="$2"
    
    echo
    echo "❌ ERROR: $script_name failed with exit code $exit_code"
    echo
    
    case "$script_name" in
        "gather-inputs.sh")
            echo "Input collection failed. Please check Stage A and B completion, then re-run this script."
            ;;
        "aws-discovery.sh")
            echo "AWS discovery failed. Please check your AWS credentials, permissions, and Lambda service access, then re-run this script."
            ;;
        "deploy-infrastructure.sh")
            echo "CDK deployment failed. CDK automatically rolls back failed deployments."
            echo "Check the error messages above, fix the issue, and re-run this script."
            echo "No manual cleanup needed - CDK handles rollback automatically."
            ;;
        "validate-deployment.sh")
            echo "Deployment validation failed. This may be due to Lambda initialization delays."
            echo "Wait a few minutes and re-run this script, or test the deployment manually."
            echo "Manual cleanup only needed if you want to remove the entire deployment."
            ;;
        *)
            echo "Unknown script failure. Check the error messages above for details."
            ;;
    esac
    
    echo
    echo "Options:"
    echo "1. Fix the issue and re-run: ./go-c.sh"
    echo "2. Run individual helper scripts for debugging"
    echo "3. Use cleanup-rollback.sh only if you want to completely remove this deployment"
    echo
    
    return $exit_code
}

# Function to check if a step was already completed
is_step_completed() {
    local step="$1"
    
    case "$step" in
        "inputs")
            [[ -f "$DATA_DIR/inputs.json" ]]
            ;;
        "discovery")
            [[ -f "$DATA_DIR/discovery.json" ]]
            ;;
        "infrastructure")
            [[ -f "$DATA_DIR/cdk-stack-outputs.json" ]]
            ;;
        "validation")
            [[ -f "$DATA_DIR/outputs.json" ]] && jq -e '.validationStatus == "passed"' "$DATA_DIR/outputs.json" > /dev/null 2>&1
            ;;
        *)
            false
            ;;
    esac
}

# Function to check if step should be skipped
should_skip_step() {
    local step_name="$1"
    local step_number="$2"
    
    if is_step_completed "$step_name"; then
        echo "✅ Step $step_number already completed ($step_name) - skipping"
        return 0  # Skip this step
    fi
    
    return 1  # Run this step
}

# Function to execute a deployment step
execute_step() {
    local step_number="$1"
    local step_name="$2"
    local script_name="$3"
    local description="$4"
    
    show_progress "$step_number" "4" "$description"
    
    if should_skip_step "$step_name" "$step_number"; then
        return 0  # Step was skipped
    fi
    
    echo "Executing: $script_name"
    echo
    
    # Execute the script (no special argument handling needed for Stage C)
    if "$SCRIPTS_DIR/$script_name"; then
        echo
        echo "✅ Step $step_number completed successfully"
        return 0
    else
        local exit_code=$?
        handle_script_error "$script_name" $exit_code
        return $exit_code
    fi
}

# Function to display final deployment summary
show_deployment_summary() {
    echo
    echo "🎉 Stage C Lambda Deployment Summary"
    echo "===================================="
    
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        local function_arn function_name function_url log_group_name
        function_arn=$(jq -r '.lambdaFunctionArn // "Not available"' "$DATA_DIR/outputs.json")
        function_name=$(jq -r '.lambdaFunctionName // "Not available"' "$DATA_DIR/outputs.json")
        function_url=$(jq -r '.functionUrl // "Not available"' "$DATA_DIR/outputs.json")
        log_group_name=$(jq -r '.logGroupName // "Not available"' "$DATA_DIR/outputs.json")
        
        echo "✅ Lambda Function ARN: $function_arn"
        echo "✅ Lambda Function Name: $function_name"
        echo "✅ Function URL: $function_url"
        echo "✅ CloudWatch Log Group: $log_group_name"
        echo
        echo "🌐 Your Lambda API is now accessible via:"
        echo "   Function URL: $function_url"
        echo "   Note: Function URL requires AWS IAM authentication"
        echo
        echo "📝 Next Steps:"
        echo "   - Test your Lambda function using AWS CLI or SDK"
        echo "   - Proceed to Stage D for React application integration"
        echo "   - Stage C outputs are saved in: $DATA_DIR/outputs.json"
        echo
    else
        echo "⚠️  Deployment completed but outputs.json not found"
        echo "   Please check the validation step for any issues"
    fi
    
    echo "🔧 Helper Scripts Available:"
    echo "   - $SCRIPTS_DIR/validate-deployment.sh  (Re-run validation)"
    echo "   - $SCRIPTS_DIR/cleanup-rollback.sh     (Clean up deployment)"
    echo
}

# Function to check Stage A and B prerequisites
check_stage_prerequisites() {
    echo "🔍 Checking Stage A and B prerequisites..."
    
    local stage_a_outputs="../a-cloudfront/data/outputs.json"
    local stage_b_outputs="../b-ssl/data/outputs.json"
    
    # Check Stage A completion
    if [[ ! -f "$stage_a_outputs" ]]; then
        echo "❌ Stage A outputs not found at: $stage_a_outputs"
        echo "   Please complete Stage A (CloudFront) deployment before running Stage C"
        exit 1
    fi
    
    local ready_for_stage_b
    ready_for_stage_b=$(jq -r '.readyForStageB // false' "$stage_a_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_b" != "true" ]]; then
        echo "❌ Stage A is not properly completed"
        echo "   Please ensure Stage A completed successfully before running Stage C"
        exit 1
    fi
    
    # Check Stage B completion
    if [[ ! -f "$stage_b_outputs" ]]; then
        echo "❌ Stage B outputs not found at: $stage_b_outputs"
        echo "   Please complete Stage B (SSL Certificate) deployment before running Stage C"
        exit 1
    fi
    
    local ready_for_stage_c
    ready_for_stage_c=$(jq -r '.readyForStageC // false' "$stage_b_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_c" != "true" ]]; then
        echo "❌ Stage B is not ready for Stage C"
        echo "   Please ensure Stage B completed successfully before running Stage C"
        exit 1
    fi
    
    echo "✅ Stage A and B prerequisites verified"
}

# Main deployment orchestration function
main_deployment() {
    echo "Starting Stage C Lambda deployment workflow..."
    echo
    
    # Pre-check: Ensure Stage A and B are completed
    check_stage_prerequisites
    echo
    
    # Step 1: Gather Inputs
    execute_step 1 "inputs" "gather-inputs.sh" "Validate Stage A/B completion and gather configuration"
    
    # Step 2: AWS Discovery
    execute_step 2 "discovery" "aws-discovery.sh" "Validate AWS access and discover existing Lambda resources"
    
    # Step 3: Deploy Infrastructure
    execute_step 3 "infrastructure" "deploy-infrastructure.sh" "Deploy Lambda function and related resources using CDK"
    
    # Step 4: Validate Deployment
    execute_step 4 "validation" "validate-deployment.sh" "Test Lambda function invocation and validate response format"
    
    # Show final summary
    show_deployment_summary
    
    echo "🎊 Stage C Lambda deployment completed successfully!"
    echo "   You are now ready to proceed to Stage D for React application integration."
}

# Function to handle cleanup on script interruption
cleanup_on_interrupt() {
    echo
    echo "⚠️  Deployment interrupted by user (Ctrl+C)"
    echo "You can:"
    echo "1. Re-run this script to continue from where you left off"
    echo "2. Run individual helper scripts manually"
    echo "3. Use cleanup-rollback.sh to clean up partial deployment"
    exit 130
}

# Set up interrupt handler
trap cleanup_on_interrupt INT TERM

# Main execution
main() {
    validate_helper_scripts
    main_deployment
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
