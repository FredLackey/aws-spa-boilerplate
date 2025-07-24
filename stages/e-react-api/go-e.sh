#!/bin/bash

# go-e.sh
# Main orchestration script for Stage E React API deployment
# Coordinates the entire React API deployment workflow by calling helper scripts sequentially

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DATA_DIR="$SCRIPT_DIR/data"

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Stage E React API deployment requires successful completion of Stage A, Stage B, Stage C, and Stage D.
No additional command line arguments are required - all configuration is derived
from previous stage outputs.

Examples:
  $0                    # Deploy React API application using Stage A, B, C, and D outputs
  $0 -h                 # Show this help message

Notes:
  - Stage A (CloudFront) must be completed successfully
  - Stage B (SSL Certificate) must be completed successfully  
  - Stage C (Lambda) must be completed successfully
  - Stage D (React) must be completed successfully
  - React JSON application will be built and deployed with API integration
  - CloudFront will be configured with API behavior for /api/* routes
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
    echo "❌ Error: Stage E does not accept command line arguments."
    echo "All configuration is derived from Stage A, B, C, and D outputs."
    echo
    show_usage
    exit 1
fi

echo "🚀 AWS SPA Boilerplate - Stage E React API Deployment"
echo "================================================="
echo "This script will build and deploy the React API application to CloudFront."
echo "Each step builds upon the previous stages, so please ensure A, B, C, and D are completed."
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
            echo "Input collection failed. Please check Stage A, B, C, and D completion, then re-run this script."
            ;;
        "aws-discovery.sh")
            echo "AWS discovery failed. Please check your AWS credentials, permissions, and React service access, then re-run this script."
            ;;
        "deploy-infrastructure.sh")
            echo "React deployment failed. This may involve CDK deployment and/or content deployment."
            echo "Check the error messages above, fix the issue, and re-run this script."
            echo "CDK automatically handles rollback for infrastructure failures."
            ;;
        "validate-deployment.sh")
            echo "Deployment validation failed. This may be due to CloudFront cache propagation delays."
            echo "Wait a few minutes and re-run this script, or test the deployment manually."
            echo "Manual cleanup only needed if you want to remove the entire deployment."
            ;;
        *)
            echo "Unknown script failure. Check the error messages above for details."
            ;;
    esac
    
    echo
    echo "Options:"
    echo "1. Fix the issue and re-run: ./go-e.sh"
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
            [[ -f "$DATA_DIR/cdk-stack-outputs.json" ]] || [[ -f "$DATA_DIR/outputs.json" ]]
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
    
    # Execute the script (no special argument handling needed for Stage D)
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
    echo "🎉 Stage E React API Deployment Summary"
    echo "==================================="
    
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        local distribution_id distribution_domain bucket_name domains certificate_arn
        distribution_id=$(jq -r '.distributionId // "Not available"' "$DATA_DIR/outputs.json")
        distribution_domain=$(jq -r '.distributionDomainName // "Not available"' "$DATA_DIR/outputs.json")
        bucket_name=$(jq -r '.bucketName // "Not available"' "$DATA_DIR/outputs.json")
        domains=$(jq -r '.domains[]? // empty' "$DATA_DIR/outputs.json" | tr '\n' ', ' | sed 's/,$//')
        certificate_arn=$(jq -r '.stageD.certificateArn // "Not available"' "$DATA_DIR/outputs.json")
        
        echo "✅ CloudFront Distribution ID: $distribution_id"
        echo "✅ CloudFront Domain: $distribution_domain"
        echo "✅ S3 Bucket: $bucket_name"
        if [[ -n "$domains" ]]; then
            echo "✅ Custom Domains: $domains"
        fi
        echo "✅ SSL Certificate: $certificate_arn"
        echo
        echo "🌐 Your React application is now accessible via:"
        if [[ -n "$domains" ]]; then
            for domain in $(echo "$domains" | tr ',' '\n'); do
                echo "   https://$domain"
            done
        fi
        echo "   https://$distribution_domain"
        echo
        echo "📝 Next Steps:"
        echo "   - Test your React application in a web browser"
        echo "   - Proceed to Stage E for React API integration (if applicable)"
        echo "   - Stage D outputs are saved in: $DATA_DIR/outputs.json"
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

# Function to check Stage A, B, and C prerequisites
check_stage_prerequisites() {
    echo "🔍 Checking Stage A, B, C, and D prerequisites..."
    
    local stage_a_outputs="../a-cloudfront/data/outputs.json"
    local stage_b_outputs="../b-ssl/data/outputs.json"
    local stage_c_outputs="../c-lambda/data/outputs.json"
    local stage_d_outputs="../d-react/data/outputs.json"
    
    # Check Stage A completion
    if [[ ! -f "$stage_a_outputs" ]]; then
        echo "❌ Stage A outputs not found at: $stage_a_outputs"
        echo "   Please complete Stage A (CloudFront) deployment before running Stage E"
        exit 1
    fi
    
    local ready_for_stage_b
    ready_for_stage_b=$(jq -r '.readyForStageB // false' "$stage_a_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_b" != "true" ]]; then
        echo "❌ Stage A is not properly completed"
        echo "   Please ensure Stage A completed successfully before running Stage E"
        exit 1
    fi
    
    # Check Stage B completion
    if [[ ! -f "$stage_b_outputs" ]]; then
        echo "❌ Stage B outputs not found at: $stage_b_outputs"
        echo "   Please complete Stage B (SSL Certificate) deployment before running Stage E"
        exit 1
    fi
    
    local ready_for_stage_c
    ready_for_stage_c=$(jq -r '.readyForStageC // false' "$stage_b_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_c" != "true" ]]; then
        echo "❌ Stage B is not ready for Stage C"
        echo "   Please ensure Stage B completed successfully before running Stage E"
        exit 1
    fi
    
    # Check Stage C completion
    if [[ ! -f "$stage_c_outputs" ]]; then
        echo "❌ Stage C outputs not found at: $stage_c_outputs"
        echo "   Please complete Stage C (Lambda) deployment before running Stage E"
        exit 1
    fi
    
    local ready_for_stage_d
    ready_for_stage_d=$(jq -r '.readyForStageD // false' "$stage_c_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_d" != "true" ]]; then
        echo "❌ Stage C is not ready for Stage D"
        echo "   Please ensure Stage C completed successfully before running Stage E"
        exit 1
    fi

    # Check Stage D completion
    if [[ ! -f "$stage_d_outputs" ]]; then
        echo "❌ Stage D outputs not found at: $stage_d_outputs"
        echo "   Please complete Stage D (React) deployment before running Stage E"
        exit 1
    fi

    local ready_for_stage_e
    ready_for_stage_e=$(jq -r '.readyForStageE // false' "$stage_d_outputs" 2>/dev/null || echo "false")

    if [[ "$ready_for_stage_e" != "true" ]]; then
        echo "❌ Stage D is not ready for Stage E"
        echo "   Please ensure Stage D completed successfully before running Stage E"
        exit 1
    fi
    
    echo "✅ Stage A, B, C, and D prerequisites verified"
}

# Main deployment orchestration function
main_deployment() {
    echo "Starting Stage E React API deployment workflow..."
    echo
    
    # Pre-check: Ensure Stage A, B, C, and D are completed
    check_stage_prerequisites
    echo
    
    # Step 1: Gather Inputs
    execute_step 1 "inputs" "gather-inputs.sh" "Validate Stage A/B/C/D completion and gather configuration"
    
    # Step 2: AWS Discovery
    execute_step 2 "discovery" "aws-discovery.sh" "Validate AWS access and discover existing React deployment resources"
    
    # Step 3: Deploy Infrastructure and Content
    execute_step 3 "infrastructure" "deploy-infrastructure.sh" "Build React app and deploy content to S3 with CloudFront cache invalidation"
    
    # Step 4: Validate Deployment
    execute_step 4 "validation" "validate-deployment.sh" "Test React application accessibility and validate content serving"
    
    # Show final summary
    show_deployment_summary
    
    echo "🎊 Stage E React API deployment completed successfully!"
    echo "   Your React application is now live and accessible via HTTPS."
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
