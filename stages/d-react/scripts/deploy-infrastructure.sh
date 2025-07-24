#!/bin/bash

# deploy-infrastructure.sh
# CDK deployment orchestration for Stage D React deployment
# Builds React application and deploys content to CloudFront distribution

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
IAC_DIR="$STAGE_DIR/iac"
REACT_APP_DIR="$STAGE_DIR/../../apps/hello-world-react"

echo "=== Stage D React Deployment - Infrastructure Deployment ==="
echo "This script will build the React application and deploy content to CloudFront."
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
    
    if [[ ! -d "$REACT_APP_DIR" ]]; then
        echo "❌ Error: React application directory not found at: $REACT_APP_DIR"
        exit 1
    fi
    
    if [[ ! -f "$REACT_APP_DIR/package.json" ]]; then
        echo "❌ Error: React application package.json not found"
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
    echo "React application directory: $REACT_APP_DIR"
}

# Function to generate CDK context from data files
generate_cdk_context() {
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    local cdk_json="$IAC_DIR/cdk.json"
    
    echo "Generating CDK context from data files..."
    
    # Read values from data files
    local distribution_prefix target_region target_profile infrastructure_profile target_vpc_id
    local target_account_id infrastructure_account_id distribution_id bucket_name
    local primary_domain certificate_arn lambda_function_url
    
    distribution_prefix=$(jq -r '.distributionPrefix' "$inputs_file")
    target_region=$(jq -r '.targetRegion' "$inputs_file")
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    infrastructure_profile=$(jq -r '.infrastructureProfile' "$inputs_file")
    target_vpc_id=$(jq -r '.targetVpcId' "$inputs_file")
    distribution_id=$(jq -r '.distributionId' "$inputs_file")
    bucket_name=$(jq -r '.bucketName' "$inputs_file")
    primary_domain=$(jq -r '.primaryDomain' "$inputs_file")
    certificate_arn=$(jq -r '.certificateArn' "$inputs_file")
    lambda_function_url=$(jq -r '.lambdaFunctionUrl' "$inputs_file")
    
    target_account_id=$(jq -r '.targetAccountId' "$discovery_file")
    infrastructure_account_id=$(jq -r '.infrastructureAccountId' "$discovery_file")
    
    echo "Distribution Prefix: $distribution_prefix"
    echo "Target Region: $target_region"
    echo "Target Profile: $target_profile"
    echo "Target VPC ID: $target_vpc_id"
    echo "Target Account ID: $target_account_id"
    echo "Distribution ID: $distribution_id"
    echo "Bucket Name: $bucket_name"
    echo "Primary Domain: $primary_domain"
    echo "Lambda Function URL: $lambda_function_url"
    
    # Update CDK context in cdk.json
    jq --arg prefix "$distribution_prefix" \
       --arg region "$target_region" \
       --arg profile "$target_profile" \
       --arg infra_profile "$infrastructure_profile" \
       --arg target_account "$target_account_id" \
       --arg infra_account "$infrastructure_account_id" \
       --arg vpc_id "$target_vpc_id" \
       --arg distribution_id "$distribution_id" \
       --arg bucket_name "$bucket_name" \
       --arg primary_domain "$primary_domain" \
       --arg certificate_arn "$certificate_arn" \
       --arg lambda_url "$lambda_function_url" \
       '.context["stage-d-react:distributionPrefix"] = $prefix |
        .context["stage-d-react:targetRegion"] = $region |
        .context["stage-d-react:targetProfile"] = $profile |
        .context["stage-d-react:infrastructureProfile"] = $infra_profile |
        .context["stage-d-react:targetAccountId"] = $target_account |
        .context["stage-d-react:infrastructureAccountId"] = $infra_account |
        .context["stage-d-react:targetVpcId"] = $vpc_id |
        .context["stage-d-react:distributionId"] = $distribution_id |
        .context["stage-d-react:bucketName"] = $bucket_name |
        .context["stage-d-react:primaryDomain"] = $primary_domain |
        .context["stage-d-react:certificateArn"] = $certificate_arn |
        .context["stage-d-react:lambdaFunctionUrl"] = $lambda_url' \
       "$cdk_json" > "${cdk_json}.tmp" && mv "${cdk_json}.tmp" "$cdk_json"
    
    echo "✅ CDK context updated successfully"
}

# Function to clean existing React build artifacts
clean_react_build() {
    echo "🧹 Cleaning existing React build artifacts..."
    
    cd "$REACT_APP_DIR"
    
    # Remove existing build directories
    if [[ -d "dist" ]]; then
        echo "   Removing existing dist/ directory..."
        rm -rf dist
    fi
    
    if [[ -d "build" ]]; then
        echo "   Removing existing build/ directory..."
        rm -rf build
    fi
    
    # Clean npm cache for this project
    if [[ -f "package-lock.json" ]]; then
        echo "   Cleaning npm cache..."
        npm cache clean --force > /dev/null 2>&1 || true
    fi
    
    echo "✅ React build artifacts cleaned"
}

# Function to install React dependencies
install_react_dependencies() {
    echo "📦 Installing React application dependencies..."
    
    cd "$REACT_APP_DIR"
    
    # Check if node_modules exists and is up to date
    if [[ -d "node_modules" ]] && [[ -f "package-lock.json" ]]; then
        echo "   Checking if dependencies are up to date..."
        
        # Compare package-lock.json and node_modules timestamps
        if [[ "package-lock.json" -nt "node_modules" ]]; then
            echo "   Dependencies appear outdated, reinstalling..."
            rm -rf node_modules
        else
            echo "   Dependencies appear up to date"
            return 0
        fi
    fi
    
    echo "   Running npm install..."
    if npm install; then
        echo "✅ React dependencies installed successfully"
    else
        echo "❌ Error: Failed to install React dependencies"
        exit 1
    fi
}

# Function to build React application
build_react_application() {
    echo "🔨 Building React application..."
    
    cd "$REACT_APP_DIR"
    
    # Determine build command and output directory
    local build_command="npm run build"
    local build_output_dir
    
    if grep -q '"vite"' package.json 2>/dev/null; then
        echo "   Detected Vite React application"
        build_output_dir="dist"
    elif grep -q '"react-scripts"' package.json 2>/dev/null; then
        echo "   Detected Create React App"
        build_output_dir="build"
    else
        echo "   Using default Vite configuration"
        build_output_dir="dist"
    fi
    
    echo "   Build command: $build_command"
    echo "   Expected output directory: $build_output_dir"
    
    # Set production environment
    export NODE_ENV=production
    
    # Run the build command
    if $build_command; then
        echo "✅ React application built successfully"
    else
        echo "❌ Error: React build failed"
        exit 1
    fi
    
    # Verify build output exists
    if [[ ! -d "$build_output_dir" ]]; then
        echo "❌ Error: Build output directory '$build_output_dir' not found"
        exit 1
    fi
    
    # Count files in build output
    local file_count
    file_count=$(find "$build_output_dir" -type f | wc -l)
    echo "   Build output contains $file_count files"
    
    # Store build output directory for deployment
    echo "$build_output_dir" > "$DATA_DIR/.build_output_dir"
    
    cd - > /dev/null
}

# Function to deploy React content to S3
deploy_react_content() {
    local inputs_file="$DATA_DIR/inputs.json"
    local build_output_dir
    
    echo "🚀 Deploying React content to S3..."
    
    if [[ ! -f "$DATA_DIR/.build_output_dir" ]]; then
        echo "❌ Error: Build output directory not found. Build may have failed."
        exit 1
    fi
    
    build_output_dir=$(cat "$DATA_DIR/.build_output_dir")
    
    # Read S3 configuration
    local target_profile bucket_name
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    bucket_name=$(jq -r '.bucketName' "$inputs_file")
    
    echo "   Target Profile: $target_profile"
    echo "   S3 Bucket: $bucket_name"
    echo "   Source Directory: $REACT_APP_DIR/$build_output_dir"
    
    cd "$REACT_APP_DIR"
    
    # Deploy content to S3 with appropriate content types
    echo "   Uploading React application files..."
    
    if aws s3 sync "$build_output_dir/" "s3://$bucket_name/" \
        --profile "$target_profile" \
        --delete \
        --cache-control "public, max-age=31536000" \
        --exclude "*.html" \
        --exclude "service-worker.js" \
        --exclude "manifest.json"; then
        echo "   ✅ Static assets uploaded with long cache control"
    else
        echo "❌ Error: Failed to upload static assets"
        exit 1
    fi
    
    # Upload HTML files with no cache
    if find "$build_output_dir" -name "*.html" -type f | while read -r html_file; do
        local s3_path="${html_file#$build_output_dir/}"
        aws s3 cp "$html_file" "s3://$bucket_name/$s3_path" \
            --profile "$target_profile" \
            --cache-control "no-cache, no-store, must-revalidate" \
            --content-type "text/html"
    done; then
        echo "   ✅ HTML files uploaded with no-cache headers"
    else
        echo "❌ Error: Failed to upload HTML files"
        exit 1
    fi
    
    # Upload service worker and manifest with short cache if they exist
    for special_file in "service-worker.js" "manifest.json"; do
        if [[ -f "$build_output_dir/$special_file" ]]; then
            aws s3 cp "$build_output_dir/$special_file" "s3://$bucket_name/$special_file" \
                --profile "$target_profile" \
                --cache-control "public, max-age=300" || true
        fi
    done
    
    echo "✅ React content deployed to S3 successfully"
    
    cd - > /dev/null
}

# Function to invalidate CloudFront cache
invalidate_cloudfront_cache() {
    local inputs_file="$DATA_DIR/inputs.json"
    
    echo "🔄 Invalidating CloudFront cache..."
    
    # Read CloudFront configuration
    local target_profile distribution_id
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    distribution_id=$(jq -r '.distributionId' "$inputs_file")
    
    echo "   Target Profile: $target_profile"
    echo "   Distribution ID: $distribution_id"
    
    # Create cache invalidation for all content
    local invalidation_id
    if invalidation_id=$(aws cloudfront create-invalidation \
        --distribution-id "$distribution_id" \
        --paths "/*" \
        --profile "$target_profile" \
        --query 'Invalidation.Id' \
        --output text); then
        
        echo "✅ CloudFront cache invalidation created"
        echo "   Invalidation ID: $invalidation_id"
        
        # Store invalidation ID for status checking
        echo "$invalidation_id" > "$DATA_DIR/.invalidation_id"
        
        echo "   Cache invalidation will take 5-15 minutes to complete"
        echo "   New React content will be available immediately via S3, and globally via CloudFront after invalidation"
    else
        echo "❌ Error: Failed to create CloudFront cache invalidation"
        exit 1
    fi
}

# Function to run CDK deployment (if needed for additional infrastructure)
run_cdk_deployment() {
    echo "🏗️  Running CDK deployment for additional React infrastructure..."
    
    cd "$IAC_DIR"
    
    # Read configuration
    local inputs_file="$DATA_DIR/inputs.json"
    local target_profile
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    
    echo "   Installing CDK dependencies..."
    if npm install; then
        echo "   ✅ CDK dependencies installed"
    else
        echo "❌ Error: Failed to install CDK dependencies"
        exit 1
    fi
    
    echo "   Bootstrapping CDK (if needed)..."
    if npx cdk bootstrap --profile "$target_profile" > /dev/null 2>&1; then
        echo "   ✅ CDK bootstrap completed"
    else
        echo "   ⚠️  CDK bootstrap skipped (may already be bootstrapped)"
    fi
    
    echo "   Synthesizing CDK stack..."
    if npx cdk synth --profile "$target_profile" > /dev/null; then
        echo "   ✅ CDK synthesis successful"
    else
        echo "❌ Error: CDK synthesis failed"
        exit 1
    fi
    
    echo "   Deploying CDK stack..."
    if npx cdk deploy --profile "$target_profile" --require-approval never --outputs-file "$DATA_DIR/cdk-outputs.json"; then
        echo "✅ CDK deployment completed successfully"
    else
        echo "❌ Error: CDK deployment failed"
        exit 1
    fi
    
    cd - > /dev/null
}

# Function to save deployment outputs
save_deployment_outputs() {
    local outputs_file="$DATA_DIR/outputs.json"
    local inputs_file="$DATA_DIR/inputs.json"
    
    echo "💾 Saving deployment outputs..."
    
    # Read current configuration
    local distribution_id bucket_name primary_domain lambda_function_url
    distribution_id=$(jq -r '.distributionId' "$inputs_file")
    bucket_name=$(jq -r '.bucketName' "$inputs_file")
    primary_domain=$(jq -r '.primaryDomain' "$inputs_file")
    lambda_function_url=$(jq -r '.lambdaFunctionUrl' "$inputs_file")
    
    # Get CloudFront distribution URL
    local distribution_url="https://${distribution_id}.cloudfront.net"
    local primary_domain_url="https://${primary_domain}"
    
    # Read invalidation ID if available
    local invalidation_id=""
    if [[ -f "$DATA_DIR/.invalidation_id" ]]; then
        invalidation_id=$(cat "$DATA_DIR/.invalidation_id")
    fi
    
    # Create outputs.json
    cat > "$outputs_file" << EOF
{
  "stageD": {
    "distributionId": "$distribution_id",
    "bucketName": "$bucket_name",
    "primaryDomain": "$primary_domain",
    "lambdaFunctionUrl": "$lambda_function_url",
    "distributionUrl": "$distribution_url",
    "primaryDomainUrl": "$primary_domain_url",
    "invalidationId": "$invalidation_id",
    "deploymentTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  },
  "reactApplicationDeployed": true,
  "cloudfrontCacheInvalidated": true,
  "contentDeploymentComplete": true,
  "readyForStageE": true,
  "deploymentTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "urls": {
    "cloudfront": "$distribution_url",
    "primaryDomain": "$primary_domain_url",
    "lambdaApi": "$lambda_function_url"
  },
  "distributionId": "$distribution_id",
  "bucketName": "$bucket_name",
  "primaryDomain": "$primary_domain",
  "invalidationId": "$invalidation_id"
}
EOF
    
    echo "✅ Deployment outputs saved to: $outputs_file"
}

# Main deployment execution
main() {
    echo "Starting Stage D React deployment process..."
    echo
    
    # Validate prerequisites
    validate_prerequisites
    echo
    
    # Generate CDK context
    generate_cdk_context
    echo
    
    # Clean and build React application
    clean_react_build
    echo
    
    install_react_dependencies
    echo
    
    build_react_application
    echo
    
    # Deploy React content
    deploy_react_content
    echo
    
    # Invalidate CloudFront cache
    invalidate_cloudfront_cache
    echo
    
    # Run CDK deployment for any additional infrastructure
    run_cdk_deployment
    echo
    
    # Save deployment outputs
    save_deployment_outputs
    echo
    
    echo "🎉 Stage D React deployment completed successfully!"
    echo
    echo "📋 Summary:"
    echo "   ✅ React application built successfully"
    echo "   ✅ Content deployed to S3"
    echo "   ✅ CloudFront cache invalidated"
    echo "   ✅ CDK infrastructure deployed"
    echo "   ✅ Deployment outputs saved"
    echo
    echo "🌐 Access URLs:"
    echo "   CloudFront: https://$(jq -r '.distributionId' "$DATA_DIR/inputs.json").cloudfront.net"
    echo "   Primary Domain: https://$(jq -r '.primaryDomain' "$DATA_DIR/inputs.json")"
    echo "   Lambda API: $(jq -r '.lambdaFunctionUrl' "$DATA_DIR/inputs.json")"
    echo
    echo "Next steps:"
    echo "   1. Wait 5-15 minutes for CloudFront cache invalidation to complete"
    echo "   2. Run: scripts/validate-deployment.sh"
    echo "   3. Test the React application in your browser"
    echo
}

# Execute main function
main 