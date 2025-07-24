#!/bin/bash

# deploy-infrastructure.sh
# CDK deployment orchestration for Stage B SSL Certificate deployment
# Generates CDK context from data files and executes SSL certificate creation

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
IAC_DIR="$STAGE_DIR/iac"

echo "=== Stage B SSL Certificate Deployment - Infrastructure Deployment ==="
echo "This script will deploy SSL certificates and update CloudFront via CDK."
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

# Function to check for existing certificates with matching domains
check_existing_certificate() {
    local infra_profile="$1"
    local domains=("${@:2}")
    
    echo "🔍 Checking for existing SSL certificates..."
    
    # Sort domains for consistent comparison
    local sorted_domains
    IFS=$'\n' sorted_domains=($(sort <<<"${domains[*]}"))
    local domain_set
    domain_set=$(printf '%s,' "${sorted_domains[@]}" | sed 's/,$//')
    
    echo "   Looking for certificate with domains: $domain_set"
    
    # List existing certificates
    local certificates
    certificates=$(aws acm list-certificates --profile "$infra_profile" --region us-east-1 --output json 2>/dev/null || echo '{"CertificateSummaryList":[]}')
    
    local matching_cert_arn=""
    
    # Check each certificate
    echo "$certificates" | jq -r '.CertificateSummaryList[]? | .CertificateArn' | while read -r cert_arn; do
        [[ -z "$cert_arn" ]] && continue
        
        # Get certificate details
        local cert_details
        cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --profile "$infra_profile" --region us-east-1 --output json 2>/dev/null || echo '{}')
        
        if [[ "$cert_details" != "{}" ]]; then
            local cert_domains status
            cert_domains=$(echo "$cert_details" | jq -r '.Certificate.SubjectAlternativeNames[]?' 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            status=$(echo "$cert_details" | jq -r '.Certificate.Status // "UNKNOWN"' 2>/dev/null)
            
            echo "   📋 Found certificate: $cert_arn"
            echo "      Domains: $cert_domains"
            echo "      Status: $status"
            
            # Check for exact match
            if [[ "$cert_domains" == "$domain_set" ]] && [[ "$status" == "ISSUED" ]]; then
                echo "      ✅ EXACT MATCH - Will reuse this certificate"
                echo "$cert_arn" > "$DATA_DIR/.existing_cert_arn"
                return 0
            fi
        fi
    done
    
    echo "   ℹ️  No matching existing certificate found - will create new one"
    rm -f "$DATA_DIR/.existing_cert_arn"
    return 0
}

# Function to generate CDK context from data files
generate_cdk_context() {
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    local cdk_json="$IAC_DIR/cdk.json"
    
    echo "Generating CDK context from data files..."
    
    # Read data from JSON files
    local domains infra_profile target_profile infra_account_id target_account_id distribution_id hosted_zones
    domains=$(jq -c '.domains' "$inputs_file")
    infra_profile=$(jq -r '.infraProfile' "$inputs_file")
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    infra_account_id=$(jq -r '.infraAccountId' "$discovery_file")
    target_account_id=$(jq -r '.targetAccountId' "$discovery_file")
    distribution_id=$(jq -r '.distributionId' "$inputs_file")
    hosted_zones=$(jq -c '.hostedZones' "$discovery_file")
    
    # Check for existing certificate
    local domains_array
    mapfile -t domains_array < <(jq -r '.domains[]' "$inputs_file")
    check_existing_certificate "$infra_profile" "${domains_array[@]}"
    
    local existing_cert_arn=""
    if [[ -f "$DATA_DIR/.existing_cert_arn" ]]; then
        existing_cert_arn=$(cat "$DATA_DIR/.existing_cert_arn")
        echo "   📋 Will reuse existing certificate: $existing_cert_arn"
    fi
    
    # Create temporary CDK context file
    local temp_cdk_json="$cdk_json.tmp"
    
    # Read the base cdk.json and add our context
    jq --argjson domains "$domains" \
       --argjson hostedZones "$hosted_zones" \
       --arg distributionId "$distribution_id" \
       --arg infraProfile "$infra_profile" \
       --arg targetProfile "$target_profile" \
       --arg infraAccountId "$infra_account_id" \
       --arg targetAccountId "$target_account_id" \
       --arg existingCertArn "$existing_cert_arn" \
       '.context += {
         "stage-b-ssl:domains": $domains,
         "stage-b-ssl:hostedZones": $hostedZones,
         "stage-b-ssl:distributionId": $distributionId,
         "stage-b-ssl:infraProfile": $infraProfile,
         "stage-b-ssl:targetProfile": $targetProfile,
         "stage-b-ssl:infraAccountId": $infraAccountId,
         "stage-b-ssl:targetAccountId": $targetAccountId,
         "stage-b-ssl:existingCertificateArn": (if $existingCertArn != "" then $existingCertArn else null end)
       }' "$cdk_json" > "$temp_cdk_json"
    
    # Replace the original cdk.json with the updated version
    mv "$temp_cdk_json" "$cdk_json"
    
    echo "✅ CDK context generated successfully"
    echo "   Domains: $(echo "$domains" | jq -r '.[]' | tr '\n' ' ')"
    echo "   Distribution ID: $distribution_id"
    echo "   Infrastructure Account: $infra_account_id"
    echo "   Target Account: $target_account_id"
    [[ -n "$existing_cert_arn" ]] && echo "   Existing Certificate: $existing_cert_arn"
}

# Function to install CDK dependencies
install_dependencies() {
    echo "Installing CDK dependencies..."
    
    cd "$IAC_DIR"
    
    if [[ ! -f "package-lock.json" ]]; then
        echo "   📦 Installing npm packages..."
        npm install
    else
        echo "   📦 Updating npm packages..."
        npm ci
    fi
    
    echo "✅ Dependencies installed successfully"
}

# Function to deploy CDK infrastructure
deploy_cdk_infrastructure() {
    local infra_profile="$1"
    
    echo "🚀 Deploying CDK infrastructure..."
    echo "   Using AWS profile: $infra_profile"
    echo "   Target region: us-east-1 (required for CloudFront certificates)"
    
    cd "$IAC_DIR"
    
    # Set AWS profile for CDK
    export AWS_PROFILE="$infra_profile"
    export AWS_DEFAULT_REGION="us-east-1"
    
    # Bootstrap CDK if needed (idempotent operation)
    echo "   🔧 Ensuring CDK bootstrap..."
    npx cdk bootstrap aws://"$(aws sts get-caller-identity --query Account --output text)"/us-east-1 || {
        echo "⚠️  CDK bootstrap failed, but continuing with deployment..."
    }
    
    # Deploy the stack
    echo "   📤 Deploying SSL certificate stack..."
    npx cdk deploy --require-approval never --outputs-file "$DATA_DIR/cdk-outputs.json" 2>&1 | tee "$DATA_DIR/cdk-deploy.log"
    
    # Check if deployment was successful
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo "✅ CDK deployment completed successfully"
        
        # Also save stack outputs in a separate file
        npx cdk ls --json > "$DATA_DIR/cdk-stack-list.json" 2>/dev/null || echo "[]" > "$DATA_DIR/cdk-stack-list.json"
        
        return 0
    else
        echo "❌ CDK deployment failed"
        echo "   Check the deployment log: $DATA_DIR/cdk-deploy.log"
        return 1
    fi
}

# Function to wait for certificate validation
wait_for_certificate_validation() {
    local infra_profile="$1"
    
    # Check if we have a certificate ARN to monitor
    local cert_arn=""
    if [[ -f "$DATA_DIR/cdk-outputs.json" ]]; then
        cert_arn=$(jq -r '.StageBSslCertificateStack.CertificateArnOutput // empty' "$DATA_DIR/cdk-outputs.json" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$cert_arn" ]]; then
        echo "⚠️  Could not find certificate ARN - skipping validation wait"
        return 0
    fi
    
    echo "⏳ Waiting for SSL certificate validation..."
    echo "   Certificate ARN: $cert_arn"
    echo "   This may take several minutes..."
    
    local max_attempts=60  # 30 minutes (30 second intervals)
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "   📊 Checking certificate status (attempt $attempt/$max_attempts)..."
        
        local cert_status
        cert_status=$(aws acm describe-certificate --certificate-arn "$cert_arn" --profile "$infra_profile" --region us-east-1 --query 'Certificate.Status' --output text 2>/dev/null || echo "UNKNOWN")
        
        case "$cert_status" in
            "ISSUED")
                echo "✅ Certificate validation completed successfully!"
                return 0
                ;;
            "PENDING_VALIDATION")
                echo "   ⏳ Certificate still pending validation..."
                ;;
            "FAILED"|"VALIDATION_TIMED_OUT"|"REVOKED")
                echo "❌ Certificate validation failed with status: $cert_status"
                return 1
                ;;
            *)
                echo "   📋 Certificate status: $cert_status"
                ;;
        esac
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo "   ⏰ Waiting 30 seconds before next check..."
            sleep 30
        fi
        
        ((attempt++))
    done
    
    echo "⚠️  Certificate validation timeout after 30 minutes"
    echo "   The certificate may still be validating in the background"
    echo "   You can check status manually or re-run this script later"
    return 1
}

# Function to update CloudFront distribution with SSL certificate
update_cloudfront_distribution() {
    local target_profile="$1"
    
    echo "☁️  Updating CloudFront distribution with SSL certificate..."
    
    # Get required information from data files
    local distribution_id cert_arn domains
    distribution_id=$(jq -r '.distributionId' "$DATA_DIR/inputs.json")
    
    if [[ -f "$DATA_DIR/cdk-outputs.json" ]]; then
        cert_arn=$(jq -r '.StageBSslCertificateStack.CertificateArnOutput // empty' "$DATA_DIR/cdk-outputs.json" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$cert_arn" ]]; then
        echo "❌ Could not find certificate ARN from CDK outputs"
        return 1
    fi
    
    # Get domains from inputs
    mapfile -t domain_array < <(jq -r '.domains[]' "$DATA_DIR/inputs.json" | sort)
    
    echo "   📋 Distribution ID: $distribution_id"
    echo "   🔒 Certificate ARN: $cert_arn"
    echo "   🌐 Domains: ${domain_array[*]}"
    
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
    
    # Update the distribution configuration
    echo "   🔧 Updating distribution configuration..."
    local updated_config
    updated_config=$(echo "$dist_config" | jq --argjson domains "$(printf '%s\n' "${domain_array[@]}" | jq -R . | jq -s .)" --arg certArn "$cert_arn" '
        .DistributionConfig |
        .Aliases.Quantity = ($domains | length) |
        .Aliases.Items = $domains |
        .ViewerCertificate = {
            "ACMCertificateArn": $certArn,
            "CertificateSource": "acm",
            "MinimumProtocolVersion": "TLSv1.2_2021",
            "SSLSupportMethod": "sni-only"
        } |
        .DefaultCacheBehavior.ViewerProtocolPolicy = "redirect-to-https"
    ')
    
    # Apply the updated configuration
    echo "   📤 Applying updated configuration..."
    local update_result
    update_result=$(echo "$updated_config" | aws cloudfront update-distribution --id "$distribution_id" --distribution-config file:///dev/stdin --if-match "$etag" --profile "$target_profile" --output json 2>/dev/null || echo "{}")
    
    if [[ "$update_result" == "{}" ]]; then
        echo "❌ Failed to update CloudFront distribution"
        return 1
    fi
    
    echo "✅ CloudFront distribution updated successfully"
    echo "   ⏳ Distribution changes may take 15-45 minutes to propagate"
    
    return 0
}

# Function to save deployment outputs
save_deployment_outputs() {
    echo "💾 Saving deployment outputs..."
    
    # Load inputs and discovery data
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    local cdk_outputs_file="$DATA_DIR/cdk-outputs.json"
    
    # Get certificate ARN from CDK outputs
    local cert_arn=""
    if [[ -f "$cdk_outputs_file" ]]; then
        cert_arn=$(jq -r '.StageBSslCertificateStack.CertificateArnOutput // empty' "$cdk_outputs_file" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$cert_arn" ]]; then
        echo "⚠️  Could not find certificate ARN in CDK outputs"
        cert_arn="unknown"
    fi
    
    # Create comprehensive outputs file
    jq -n \
        --slurpfile inputs "$inputs_file" \
        --slurpfile discovery "$discovery_file" \
        --arg certArn "$cert_arn" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{
            domains: $inputs[0].domains,
            infraProfile: $inputs[0].infraProfile,
            targetProfile: $inputs[0].targetProfile,
            infraAccountId: $discovery[0].infraAccountId,
            targetAccountId: $discovery[0].targetAccountId,
            distributionId: $inputs[0].distributionId,
            distributionUrl: $inputs[0].distributionUrl,
            certificateArn: $certArn,
            certificateRegion: "us-east-1",
            certificateStatus: "PENDING_VALIDATION",
            hostedZones: $discovery[0].hostedZones,
            deploymentTimestamp: $timestamp,
            validationStatus: "pending",
            readyForStageC: false,
            stageAData: {
                distributionId: $inputs[0].distributionId,
                distributionUrl: $inputs[0].distributionUrl,
                bucketName: $inputs[0].bucketName,
                targetRegion: $inputs[0].targetRegion
            }
        }' > "$DATA_DIR/outputs.json"
    
    echo "✅ Deployment outputs saved to: $DATA_DIR/outputs.json"
}

# Main deployment orchestration function
main_deployment() {
    echo "Starting Stage B SSL certificate infrastructure deployment..."
    echo
    
    # Step 1: Validate prerequisites
    validate_prerequisites
    echo
    
    # Step 2: Generate CDK context
    generate_cdk_context
    echo
    
    # Step 3: Install dependencies
    install_dependencies
    echo
    
    # Step 4: Deploy CDK infrastructure
    local infra_profile
    infra_profile=$(jq -r '.infraProfile' "$DATA_DIR/inputs.json")
    
    if ! deploy_cdk_infrastructure "$infra_profile"; then
        echo "❌ Infrastructure deployment failed"
        exit 1
    fi
    echo
    
    # Step 5: Wait for certificate validation
    if ! wait_for_certificate_validation "$infra_profile"; then
        echo "⚠️  Certificate validation incomplete, but continuing..."
    fi
    echo
    
    # Step 6: Update CloudFront distribution
    local target_profile
    target_profile=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    if ! update_cloudfront_distribution "$target_profile"; then
        echo "❌ CloudFront update failed"
        exit 1
    fi
    echo
    
    # Step 7: Save deployment outputs
    save_deployment_outputs
    echo
    
    echo "🎉 Stage B SSL certificate infrastructure deployment completed!"
    echo "   SSL certificate has been created and attached to CloudFront distribution"
    echo "   DNS validation records have been automatically created in Route53"
    echo "   CloudFront distribution is now configured for HTTPS traffic"
}

# Main execution
main() {
    main_deployment
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 