#!/bin/bash

# go-a.sh
# Main orchestration script for Stage A CloudFront deployment
# Coordinates the entire deployment workflow by calling helper scripts sequentially

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DATA_DIR="$SCRIPT_DIR/data"

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Required Options:
  --infraprofile PROFILE    AWS CLI profile for infrastructure resources (Route53, certificates)
  --targetprofile PROFILE   AWS CLI profile for target resources (S3, CloudFront)
  --prefix PREFIX           Distribution prefix (kebab-case, lowercase, alphanumeric)
  --region REGION           Target AWS region
  --vpc VPC_ID              Target VPC ID

Example:
  $0 --infraprofile yourawsprofile-infra --targetprofile yourawsprofile-sandbox --prefix hellospa --region us-east-1 --vpc vpc-0f59afe5908b84a1a

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

# Validate that we have arguments
if [[ $# -eq 0 ]]; then
    echo "❌ Error: No arguments provided."
    echo
    show_usage
    exit 1
fi

echo "🚀 AWS SPA Boilerplate - Stage A CloudFront Deployment"
echo "======================================================="
echo "This script will deploy a CloudFront distribution for static content hosting."
echo "Each step builds upon the previous one, so please complete them in order."
echo

# Function to check if all helper scripts exist
validate_helper_scripts() {
    echo "Validating helper scripts..."
    
    local required_scripts=(
        "gather-inputs.sh"
        "aws-discovery.sh"
        "deploy-infrastructure.sh"
        "deploy-content.sh"
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
            echo "Input collection failed. Please check your AWS profiles and inputs, then re-run this script."
            ;;
        "aws-discovery.sh")
            echo "AWS discovery failed. Please check your AWS credentials, permissions, and region access, then re-run this script."
            ;;
        "deploy-infrastructure.sh")
            echo "CDK deployment failed. CDK automatically rolls back failed deployments."
            echo "Check the error messages above, fix the issue, and re-run this script."
            echo "No manual cleanup needed - CDK handles rollback automatically."
            ;;
        "deploy-content.sh")
            echo "Content deployment failed. The CDK infrastructure is still intact."
            echo "Fix the content upload issue and re-run this script."
            echo "Manual cleanup only needed if you want to remove the entire deployment."
            ;;
        "validate-deployment.sh")
            echo "Deployment validation failed. This may be due to CloudFront propagation delays."
            echo "Wait a few minutes and re-run this script, or test the deployment manually."
            echo "Manual cleanup only needed if you want to remove the entire deployment."
            ;;
        *)
            echo "Unknown script failure. Check the error messages above for details."
            ;;
    esac
    
    echo
    echo "Options:"
    echo "1. Fix the issue and re-run: ./go-a.sh"
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
        "content")
            # Check if validation was successful (implies content was deployed)
            [[ -f "$DATA_DIR/outputs.json" ]] && jq -e '.readyForStageB == true' "$DATA_DIR/outputs.json" > /dev/null 2>&1
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
    
    show_progress "$step_number" "5" "$description"
    
    if should_skip_step "$step_name" "$step_number"; then
        return 0  # Step was skipped
    fi
    
    echo "Executing: $script_name"
    echo
    
    # Special handling for gather-inputs.sh to pass command-line arguments
    if [[ "$script_name" == "gather-inputs.sh" ]]; then
        if "$SCRIPTS_DIR/$script_name" "${SCRIPT_ARGS[@]}"; then
            echo
            echo "✅ Step $step_number completed successfully"
            return 0
        else
            local exit_code=$?
            handle_script_error "$script_name" $exit_code
            return $exit_code
        fi
    else
        if "$SCRIPTS_DIR/$script_name"; then
            echo
            echo "✅ Step $step_number completed successfully"
            return 0
        else
            local exit_code=$?
            handle_script_error "$script_name" $exit_code
            return $exit_code
        fi
    fi
}

# Function to display final deployment summary
show_deployment_summary() {
    echo
    echo "🎉 Stage A CloudFront Deployment Summary"
    echo "========================================"
    
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        local distribution_url bucket_name distribution_id
        distribution_url=$(jq -r '.distributionUrl // "Not available"' "$DATA_DIR/outputs.json")
        bucket_name=$(jq -r '.bucketName // "Not available"' "$DATA_DIR/outputs.json")
        distribution_id=$(jq -r '.distributionId // "Not available"' "$DATA_DIR/outputs.json")
        
        echo "✅ CloudFront Distribution URL: $distribution_url"
        echo "✅ S3 Bucket Name: $bucket_name"
        echo "✅ Distribution ID: $distribution_id"
        echo
        echo "🌐 Your application is now accessible at:"
        echo "   $distribution_url"
        echo
        echo "📝 Next Steps:"
        echo "   - Test your deployment by visiting the URL above"
        echo "   - Proceed to Stage B for SSL certificate configuration"
        echo "   - Stage A outputs are saved in: $DATA_DIR/outputs.json"
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

# Function to check for in-progress CloudFront distributions
check_cloudfront_status() {
    echo "🔍 Checking for in-progress CloudFront distributions..."
    
    # Extract target profile from arguments for the check
    echo "   📋 Extracting target profile from command arguments..."
    local target_profile=""
    for i in "${!SCRIPT_ARGS[@]}"; do
        if [[ "${SCRIPT_ARGS[i]}" == "--targetprofile" ]] && [[ $((i+1)) -lt ${#SCRIPT_ARGS[@]} ]]; then
            target_profile="${SCRIPT_ARGS[$((i+1))]}"
            break
        fi
    done
    
    if [[ -z "$target_profile" ]]; then
        echo "⚠️  Could not determine target profile for CloudFront check"
        return 0  # Continue deployment
    fi
    
    echo "   🔑 Using AWS profile: $target_profile"
    echo "   🌐 Querying AWS CloudFront service for distribution status..."
    
    # Check for in-progress distributions
    local in_progress_distributions
    echo "   ⏳ Running: aws cloudfront list-distributions --profile $target_profile"
    in_progress_distributions=$(aws cloudfront list-distributions --profile "$target_profile" --query 'DistributionList.Items[?Status==`InProgress`].{Id:Id,Comment:Comment}' --output text 2>/dev/null || echo "")
    
    echo "   📊 CloudFront API query completed"
    
    if [[ -n "$in_progress_distributions" ]] && [[ "$in_progress_distributions" != "None" ]]; then
        echo "❌ CloudFront distributions currently in progress:"
        echo "$in_progress_distributions" | while read -r id comment; do
            [[ -n "$id" ]] && echo "   - Distribution ID: $id ($comment)"
        done
        echo
        echo "⚠️  Cannot proceed with deployment while CloudFront distributions are in progress."
        echo "   CloudFront operations can take 15-45 minutes to complete."
        echo "   Please wait for the distributions to reach 'Deployed' status before running this script."
        echo
        echo "💡 You can check status with:"
        echo "   aws cloudfront list-distributions --profile $target_profile --query 'DistributionList.Items[?Status==\`InProgress\`]'"
        echo
        exit 1
    fi
    
    echo "✅ No in-progress CloudFront distributions found"
}

# Main deployment orchestration function
main_deployment() {
    echo "Starting Stage A deployment workflow..."
    echo
    
    # Pre-check: Ensure no CloudFront distributions are in progress
    check_cloudfront_status
    echo
    
    # Step 1: Gather Inputs
    execute_step 1 "inputs" "gather-inputs.sh" "Collect deployment configuration inputs"
    
    # Step 2: AWS Discovery
    execute_step 2 "discovery" "aws-discovery.sh" "Validate AWS access and discover existing resources"
    
    # Step 3: Deploy Infrastructure
    execute_step 3 "infrastructure" "deploy-infrastructure.sh" "Deploy CloudFront and S3 infrastructure using CDK"
    
    # Step 4: Deploy Content
    execute_step 4 "content" "deploy-content.sh" "Upload hello-world-html content to S3"
    
    # Step 5: Validate Deployment
    execute_step 5 "validation" "validate-deployment.sh" "Test HTTP connectivity and validate deployment"
    
    # Show final summary
    show_deployment_summary
    
    echo "🎊 Stage A CloudFront deployment completed successfully!"
    echo "   You are now ready to proceed to Stage B for SSL configuration."
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
