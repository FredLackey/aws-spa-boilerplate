#!/bin/bash

# deploy-infrastructure.sh
# CDK deployment orchestration for Stage A CloudFront deployment
# Generates CDK context from data files and executes CDK deployment

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
IAC_DIR="$STAGE_DIR/iac"

echo "=== Stage A CloudFront Deployment - Infrastructure Deployment ==="
echo "This script will deploy the CDK infrastructure for CloudFront distribution."
echo

# Function to validate required files exist
validate_prerequisites() {
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    
    echo "Validating prerequisites..."
    
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    if [[ ! -f "$discovery_file" ]]; then
        echo "❌ Error: discovery.json not found. Please run aws-discovery.sh first."
        exit 1
    fi
    
    if [[ ! -d "$IAC_DIR" ]]; then
        echo "❌ Error: iac directory not found."
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
}

# Function to generate CDK context from data files
generate_cdk_context() {
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    local cdk_json="$IAC_DIR/cdk.json"
    
    echo "Generating CDK context from data files..."
    
    # Read values from data files
    local distribution_prefix target_region target_profile infrastructure_profile target_vpc_id
    local target_account_id infrastructure_account_id
    
    distribution_prefix=$(jq -r '.distributionPrefix' "$inputs_file")
    target_region=$(jq -r '.targetRegion' "$inputs_file")
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    infrastructure_profile=$(jq -r '.infrastructureProfile' "$inputs_file")
    target_vpc_id=$(jq -r '.targetVpcId' "$inputs_file")
    
    target_account_id=$(jq -r '.targetAccountId' "$discovery_file")
    infrastructure_account_id=$(jq -r '.infrastructureAccountId' "$discovery_file")
    
    echo "Distribution Prefix: $distribution_prefix"
    echo "Target Region: $target_region"
    echo "Target Profile: $target_profile"
    echo "Target VPC ID: $target_vpc_id"
    echo "Target Account ID: $target_account_id"
    
    # Update CDK context in cdk.json
    jq --arg prefix "$distribution_prefix" \
       --arg region "$target_region" \
       --arg profile "$target_profile" \
       --arg infra_profile "$infrastructure_profile" \
       --arg target_account "$target_account_id" \
       --arg infra_account "$infrastructure_account_id" \
       --arg vpc_id "$target_vpc_id" \
       '.context["stage-a-cloudfront:distributionPrefix"] = $prefix |
        .context["stage-a-cloudfront:targetRegion"] = $region |
        .context["stage-a-cloudfront:targetProfile"] = $profile |
        .context["stage-a-cloudfront:infrastructureProfile"] = $infra_profile |
        .context["stage-a-cloudfront:targetAccountId"] = $target_account |
        .context["stage-a-cloudfront:infrastructureAccountId"] = $infra_account |
        .context["stage-a-cloudfront:targetVpcId"] = $vpc_id' \
        "$cdk_json" > "${cdk_json}.tmp" && mv "${cdk_json}.tmp" "$cdk_json"
    
    echo "✅ CDK context updated successfully"
}

# Function to execute CDK deployment
deploy_cdk_stack() {
    local target_profile
    target_profile=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    echo "Deploying CDK stack with profile: $target_profile"
    echo "Changing to IAC directory: $IAC_DIR"
    
    cd "$IAC_DIR"
    
    # Install dependencies if needed
    if [[ ! -d "node_modules" ]]; then
        echo "Installing CDK dependencies..."
        npm install
    fi
    
    # Bootstrap CDK if needed (this is safe to run multiple times)
    echo "Bootstrapping CDK (if needed)..."
    if ! npx cdk bootstrap --profile "$target_profile" 2>/dev/null; then
        echo "⚠️  CDK bootstrap failed or not needed, continuing..."
    fi
    
    # Build the CDK app
    echo "Building CDK application..."
    npm run build
    
    # Deploy the stack
    echo "Deploying CloudFront stack..."
    npx cdk deploy --require-approval never --profile "$target_profile" --outputs-file "$DATA_DIR/cdk-outputs.json"
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ CDK stack deployed successfully"
        return 0
    else
        echo "❌ CDK deployment failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Function to capture and process CDK outputs
process_cdk_outputs() {
    local cdk_outputs_file="$DATA_DIR/cdk-outputs.json"
    local outputs_file="$DATA_DIR/cdk-stack-outputs.json"
    
    echo "Processing CDK outputs..."
    
    if [[ ! -f "$cdk_outputs_file" ]]; then
        echo "❌ Error: CDK outputs file not found. Deployment may have failed."
        return 1
    fi
    
    # Extract outputs from CDK outputs file
    local stack_name
    stack_name=$(jq -r 'keys[0]' "$cdk_outputs_file")
    
    if [[ "$stack_name" == "null" ]]; then
        echo "❌ Error: No stack found in CDK outputs."
        return 1
    fi
    
    # Process and save stack outputs
    jq -r --arg stack "$stack_name" '.[$stack]' "$cdk_outputs_file" > "$outputs_file"
    
    # Display key outputs
    echo "=== CDK Stack Outputs ==="
    echo "Stack Name: $stack_name"
    
    if jq -e '.DistributionId' "$outputs_file" > /dev/null; then
        local distribution_id distribution_domain distribution_url bucket_name
        distribution_id=$(jq -r '.DistributionId' "$outputs_file")
        distribution_domain=$(jq -r '.DistributionDomainName' "$outputs_file")
        distribution_url=$(jq -r '.DistributionUrl' "$outputs_file")
        bucket_name=$(jq -r '.BucketName' "$outputs_file")
        
        echo "Distribution ID: $distribution_id"
        echo "Distribution Domain: $distribution_domain"
        echo "Distribution URL: $distribution_url"
        echo "S3 Bucket Name: $bucket_name"
    fi
    
    echo "✅ CDK outputs processed successfully"
    echo "Outputs saved to: $outputs_file"
}

# Function to handle CDK deployment errors
handle_deployment_error() {
    local exit_code=$1
    
    echo "❌ Infrastructure deployment failed with exit code: $exit_code"
    echo "Common troubleshooting steps:"
    echo "1. Check AWS credentials and permissions"
    echo "2. Verify the target region is correct"
    echo "3. Check for naming conflicts with existing resources"
    echo "4. Review CDK logs above for specific error details"
    echo
    echo "To clean up partial deployment, you may need to run the cleanup script."
    
    return $exit_code
}

# Main deployment function
deploy_infrastructure() {
    validate_prerequisites
    generate_cdk_context
    
    if deploy_cdk_stack; then
        process_cdk_outputs
        echo "🎉 Infrastructure deployment completed successfully!"
        return 0
    else
        local exit_code=$?
        handle_deployment_error $exit_code
        return $exit_code
    fi
}

# Main execution
main() {
    deploy_infrastructure
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 