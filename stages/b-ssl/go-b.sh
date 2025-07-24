#!/bin/bash

# go-b.sh
# Main orchestration script for Stage B SSL Certificate deployment
# Coordinates SSL certificate creation and CloudFront integration workflow
# 
# ARCHITECTURE COMPLIANCE:
# - SSL certificates created in environment-specific accounts (us-east-1)
# - DNS validation records managed in infrastructure account Route53
# - CloudFront distributions updated in environment-specific accounts
# - Aligns with ARCHITECTURE.md centralized DNS approach

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DATA_DIR="$SCRIPT_DIR/data"

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 -d DOMAIN [-d DOMAIN2] [-d DOMAIN3] ...

Required Options:
  -d DOMAIN                 Fully qualified domain name (FQDN) for SSL certificate
                           Can be specified multiple times for multi-domain certificates

Examples:
  $0 -d www.sbx.yourdomain.com -d sbx.yourdomain.com
  $0 -d api.example.com
  $0 -d www.mysite.com -d mysite.com -d api.mysite.com

Notes:
  - At least one domain is required
  - All domains will be covered by a single SSL certificate
  - Domains must have existing Route53 hosted zones in the infrastructure account
  - Stage A must be completed successfully before running Stage B

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

echo "🚀 AWS SPA Boilerplate - Stage B SSL Certificate Deployment"
echo "==========================================================="
echo "This script will add SSL certificates to your CloudFront distribution."
echo "Each step builds upon the previous one, so please complete them in order."
echo

# Function to check if all helper scripts exist
validate_helper_scripts() {
    echo "Validating helper scripts..."
    
    local required_scripts=(
        "gather-inputs.sh"
        "aws-discovery.sh"
        "deploy-infrastructure.sh"
        "deploy-dns.sh"
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
            echo "Input collection failed. Please check your domain names and Stage A completion, then re-run this script."
            ;;
        "aws-discovery.sh")
            echo "AWS discovery failed. Please check your AWS credentials, permissions, and Route53 hosted zones, then re-run this script."
            ;;
        "deploy-infrastructure.sh")
            echo "SSL certificate and CloudFront deployment failed. CDK automatically rolls back failed deployments."
            echo "Check the error messages above, fix the issue, and re-run this script."
            echo "No manual cleanup needed - CDK handles rollback automatically."
            ;;
        "deploy-dns.sh")
            echo "DNS validation record deployment failed. The SSL certificate may be in pending validation state."
            echo "Fix the DNS issue and re-run this script."
            echo "Manual cleanup only needed if you want to remove the entire deployment."
            ;;
        "validate-deployment.sh")
            echo "HTTPS validation failed. This may be due to CloudFront propagation delays or DNS resolution issues."
            echo "Wait a few minutes and re-run this script, or test the deployment manually."
            echo "Manual cleanup only needed if you want to remove the entire deployment."
            ;;
        *)
            echo "Unknown script failure. Check the error messages above for details."
            ;;
    esac
    
    echo
    echo "Options:"
    echo "1. Fix the issue and re-run: ./go-b.sh [your domain arguments]"
    echo "2. Run individual helper scripts for debugging"
    echo "3. Use cleanup-rollback.sh to remove SSL configuration and revert to Stage A"
    echo "4. Use ../a-cloudfront/undo-a.sh for complete cleanup if Stage B rollback fails"
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
        "dns")
            # Check if certificate is validated (implies DNS records were created)
            [[ -f "$DATA_DIR/outputs.json" ]] && jq -e '.certificateStatus == "ISSUED"' "$DATA_DIR/outputs.json" > /dev/null 2>&1
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
    echo "🎉 Stage B SSL Certificate Deployment Summary"
    echo "=============================================="
    
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        local certificate_arn distribution_url distribution_id domains
        certificate_arn=$(jq -r '.certificateArn // "Not available"' "$DATA_DIR/outputs.json")
        distribution_url=$(jq -r '.distributionUrl // "Not available"' "$DATA_DIR/outputs.json")
        distribution_id=$(jq -r '.distributionId // "Not available"' "$DATA_DIR/outputs.json")
        domains=$(jq -r '.domains[]?' "$DATA_DIR/outputs.json" 2>/dev/null | tr '\n' ' ' || echo "Not available")
        
        echo "✅ SSL Certificate ARN: $certificate_arn"
        echo "✅ CloudFront Distribution URL: $distribution_url"
        echo "✅ Distribution ID: $distribution_id"
        echo "✅ Configured Domains: $domains"
        echo
        echo "🌐 Your application is now accessible via HTTPS at:"
        for domain in $(jq -r '.domains[]?' "$DATA_DIR/outputs.json" 2>/dev/null || echo ""); do
            [[ -n "$domain" ]] && echo "   https://$domain"
        done
        echo
        echo "📝 Next Steps:"
        echo "   - Test your HTTPS deployment by visiting the URLs above"
        echo "   - Proceed to Stage C for Lambda function integration"
        echo "   - Stage B outputs are saved in: $DATA_DIR/outputs.json"
        echo
    else
        echo "⚠️  Deployment completed but outputs.json not found"
        echo "   Please check the validation step for any issues"
    fi
    
    echo "🔧 Helper Scripts Available:"
    echo "   - $SCRIPTS_DIR/validate-deployment.sh  (Re-run HTTPS validation)"
    echo "   - $SCRIPTS_DIR/cleanup-rollback.sh     (Remove SSL and revert to Stage A)"
    echo
}

# Function to check for in-progress CloudFront distributions
check_cloudfront_status() {
    echo "🔍 Checking for in-progress CloudFront distributions..."
    
    # Load Stage A outputs to get target profile
    local stage_a_outputs="../a-cloudfront/data/outputs.json"
    if [[ ! -f "$stage_a_outputs" ]]; then
        echo "❌ Stage A outputs not found at: $stage_a_outputs"
        echo "   Please complete Stage A before running Stage B"
        exit 1
    fi
    
    local target_profile
    target_profile=$(jq -r '.targetProfile // .stageA.targetProfile // empty' "$stage_a_outputs")
    
    if [[ -z "$target_profile" ]]; then
        echo "❌ Could not determine target profile from Stage A outputs"
        echo "   Please verify Stage A completed successfully"
        exit 1
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
    echo "Starting Stage B SSL deployment workflow..."
    echo
    
    # Pre-check: Ensure no CloudFront distributions are in progress
    check_cloudfront_status
    echo
    
    # Step 1: Gather Inputs
    execute_step 1 "inputs" "gather-inputs.sh" "Collect domain names and validate Stage A prerequisites"
    
    # Step 2: AWS Discovery
    execute_step 2 "discovery" "aws-discovery.sh" "Discover Route53 zones and validate account access"
    
    # Step 3: Deploy Infrastructure
    execute_step 3 "infrastructure" "deploy-infrastructure.sh" "Create SSL certificate and update CloudFront via CDK"
    
    # Step 4: Deploy DNS
    execute_step 4 "dns" "deploy-dns.sh" "Configure Route53 DNS validation records"
    
    # Step 5: Validate Deployment
    execute_step 5 "validation" "validate-deployment.sh" "Test HTTPS connectivity and certificate attachment"
    
    # Show final summary
    show_deployment_summary
    
    echo "🎊 Stage B SSL certificate deployment completed successfully!"
    echo "   You are now ready to proceed to Stage C for Lambda integration."
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
