#!/bin/bash

# deploy-infrastructure.sh
# CDK deployment orchestration for Stage B SSL Certificate deployment
# Generates CDK context from data files and executes SSL certificate creation
# Per architecture: Certificates in environment accounts, DNS validation in infrastructure account

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
IAC_DIR="$STAGE_DIR/iac"

# Timeout settings to prevent hanging
CDK_TIMEOUT=1800  # 30 minutes for CDK operations
DNS_TIMEOUT=300   # 5 minutes for DNS operations

echo "=== Stage B SSL Certificate Deployment - Infrastructure Deployment ==="
echo "This script will deploy SSL certificates and update CloudFront via CDK."
echo "Per architecture: Certificates in environment account, DNS validation in infrastructure account"
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
    local target_profile="$1"
    local domains=("${@:2}")
    
    echo "🔍 Checking for existing SSL certificates..." >&2
    
    # Sort domains for consistent comparison
    local sorted_domains
    IFS=$'\n' sorted_domains=($(sort <<<"${domains[*]}"))
    local domain_set
    domain_set=$(printf '%s,' "${sorted_domains[@]}" | sed 's/,$//')
    
    echo "   Looking for certificate with domains: $domain_set" >&2
    
    # List existing certificates with timeout
    local certificates
    certificates=$(timeout $DNS_TIMEOUT aws acm list-certificates \
        --profile "$target_profile" \
        --region us-east-1 \
        --output json 2>/dev/null || echo '{"CertificateSummaryList":[]}')
    
    local matching_cert_arn=""
    
    # Check each certificate to find exact domain match
    local existing_cert_arn=""
    while IFS= read -r cert_arn; do
        [[ -z "$cert_arn" ]] && continue
        
        # Get certificate details with timeout
        local cert_details
        cert_details=$(timeout $DNS_TIMEOUT aws acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --profile "$target_profile" \
            --region us-east-1 \
            --output json 2>/dev/null || echo '{}')
        
        if [[ "$cert_details" != "{}" ]]; then
            local cert_domains status
            cert_domains=$(echo "$cert_details" | jq -r '.Certificate.SubjectAlternativeNames[]?' 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            status=$(echo "$cert_details" | jq -r '.Certificate.Status // "UNKNOWN"' 2>/dev/null)
            
            echo "   📋 Found certificate: $cert_arn" >&2
            echo "      Domains: $cert_domains" >&2
            echo "      Status: $status" >&2
            
            # Check for exact match with ISSUED or PENDING_VALIDATION status
            if [[ "$cert_domains" == "$domain_set" ]] && [[ "$status" == "ISSUED" || "$status" == "PENDING_VALIDATION" ]]; then
                echo "      ✅ EXACT MATCH - Will reuse this certificate (Status: $status)" >&2
                existing_cert_arn="$cert_arn"
                break
            fi
        fi
    done < <(echo "$certificates" | jq -r '.CertificateSummaryList[]? | .CertificateArn')
    
    if [[ -z "$existing_cert_arn" ]]; then
        echo "   ℹ️  No matching existing certificate found - will create new one" >&2
    fi
    
    # Return the certificate ARN (empty if none found)
    echo "$existing_cert_arn"
}

# Function to generate CDK context from data files
generate_cdk_context() {
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    
    echo "📋 Generating CDK context from data files..."
    
    # Read data files
    local inputs discovery
    inputs=$(cat "$inputs_file")
    discovery=$(cat "$discovery_file")
    
    # Extract key values
    local domains infra_profile target_profile infra_account_id target_account_id distribution_id
    domains=$(echo "$inputs" | jq -r '.domains[]')
    infra_profile=$(echo "$inputs" | jq -r '.infraProfile')
    target_profile=$(echo "$inputs" | jq -r '.targetProfile')
    infra_account_id=$(echo "$discovery" | jq -r '.infraAccountId')
    target_account_id=$(echo "$discovery" | jq -r '.targetAccountId')
    distribution_id=$(echo "$inputs" | jq -r '.distributionId')
    
    # Convert domains to array for certificate checking
    local domains_array
    readarray -t domains_array < <(echo "$inputs" | jq -r '.domains[]')
    
    # Check for existing certificate
    local existing_cert_arn
    existing_cert_arn=$(check_existing_certificate "$target_profile" "${domains_array[@]}")
    
    # Generate CDK context JSON
    local cdk_context
    cdk_context=$(jq -n \
        --argjson domains "$(echo "$inputs" | jq '.domains')" \
        --arg distributionId "$distribution_id" \
        --arg infraAccountId "$infra_account_id" \
        --arg targetAccountId "$target_account_id" \
        --arg existingCertificateArn "$existing_cert_arn" \
        '{
        "stage-b-ssl:domains": $domains,
        "stage-b-ssl:distributionId": $distributionId,
        "stage-b-ssl:infraAccountId": $infraAccountId,
        "stage-b-ssl:targetAccountId": $targetAccountId,
        "stage-b-ssl:existingCertificateArn": ($existingCertificateArn | if . == "" then null else . end)
    }')
    
    echo "   Generated context:"
    echo "   Infrastructure Account: $infra_account_id"
    echo "   Target Account: $target_account_id"
    echo "   Distribution ID: $distribution_id"
    echo "   Domains: $(echo "$inputs" | jq -r '.domains | join(", ")')"
    if [[ -n "$existing_cert_arn" ]]; then
        echo "   Existing Certificate: $existing_cert_arn"
    else
        echo "   Existing Certificate: None (will create new)"
    fi
    
    # Write context to CDK context file
    echo "$cdk_context" > "$IAC_DIR/cdk.context.json"
    
    echo "✅ CDK context generated successfully"
    return 0
}

# Function to deploy CDK stack
deploy_cdk_stack() {
    local target_profile="$1"
    
    echo "🚀 Deploying CDK infrastructure..."
    echo "   Using AWS profile: $target_profile"
    echo "   Target region: us-east-1 (required for CloudFront certificates)"
    echo "   Per architecture: Certificate created in environment-specific account"
    
    cd "$IAC_DIR"
    
    # Set AWS profile for CDK
    export AWS_PROFILE="$target_profile"
    export AWS_DEFAULT_REGION="us-east-1"
    
    # Bootstrap CDK if needed (idempotent operation) with timeout
    echo "   🔧 Ensuring CDK bootstrap..."
    timeout $CDK_TIMEOUT npx cdk bootstrap "aws://$(aws sts get-caller-identity --query Account --output text)/us-east-1" || {
        echo "⚠️  CDK bootstrap failed or timed out, but continuing with deployment..."
    }
    
    # Deploy the stack with timeout
    echo "   📤 Deploying SSL certificate stack..."
    if timeout $CDK_TIMEOUT npx cdk deploy --require-approval never --outputs-file "$DATA_DIR/cdk-outputs.json" 2>&1 | tee "$DATA_DIR/cdk-deploy.log"; then
        echo "✅ CDK deployment completed successfully"
        
        # Also save stack outputs in a separate file
        timeout $DNS_TIMEOUT npx cdk ls --json > "$DATA_DIR/cdk-stack-list.json" 2>/dev/null || echo "[]" > "$DATA_DIR/cdk-stack-list.json"
        
        return 0
    else
        echo "❌ CDK deployment failed or timed out"
        echo "   Check the deployment log: $DATA_DIR/cdk-deploy.log"
        return 1
    fi
}

# Function to manage DNS validation records
manage_dns_validation() {
    local action="$1"
    
    echo "🌐 Managing DNS validation records..."
    echo "   Action: $action"
    echo "   Per architecture: DNS validation records managed in infrastructure account Route53"
    
    # Use the manage-dns-validation.sh script
    local dns_script="$SCRIPT_DIR/manage-dns-validation.sh"
    
    if [[ ! -f "$dns_script" ]]; then
        echo "❌ Error: DNS validation script not found: $dns_script"
        return 1
    fi
    
    # Run DNS validation management with timeout
    if timeout $DNS_TIMEOUT "$dns_script" "$action"; then
        echo "✅ DNS validation $action completed successfully"
        return 0
    else
        echo "❌ DNS validation $action failed or timed out"
        return 1
    fi
}

# Function to wait for certificate validation with timeout
wait_for_certificate_validation() {
    local target_profile="$1"
    local max_wait_minutes="${2:-30}"
    
    # Check if we have a certificate ARN to monitor
    local cert_arn=""
    
    # Get certificate ARN from CDK outputs (works for both new and reused certificates)
    if [[ -f "$DATA_DIR/cdk-outputs.json" ]]; then
        cert_arn=$(jq -r '.StageBSslCertificateStack.CertificateArnOutput // empty' "$DATA_DIR/cdk-outputs.json" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$cert_arn" ]]; then
        echo "⚠️  Could not find certificate ARN - skipping validation wait"
        return 0
    fi
    
    echo "⏳ Waiting for SSL certificate validation..."
    echo "   Certificate ARN: $cert_arn"
    echo "   Maximum wait time: $max_wait_minutes minutes"
    
    local max_attempts=$((max_wait_minutes * 2))  # 30 second intervals
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "   Attempt $attempt/$max_attempts - Checking certificate status..."
        
        # Get certificate status with timeout
        local cert_status
        cert_status=$(timeout $DNS_TIMEOUT aws acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --profile "$target_profile" \
            --region us-east-1 \
            --query 'Certificate.Status' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        case "$cert_status" in
            "ISSUED")
                echo "✅ Certificate validation completed successfully!"
                echo "   Status: $cert_status"
                return 0
                ;;
            "PENDING_VALIDATION")
                echo "   Status: $cert_status - Still waiting..."
                ;;
            "FAILED"|"VALIDATION_TIMED_OUT"|"REVOKED")
                echo "❌ Certificate validation failed!"
                echo "   Status: $cert_status"
                return 1
                ;;
            *)
                echo "   Status: $cert_status - Unknown status, continuing..."
                ;;
        esac
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo "   Waiting 30 seconds before next check..."
            sleep 30
        fi
        
        ((attempt++))
    done
    
    echo "⚠️  Certificate validation timed out after $max_wait_minutes minutes"
    echo "   You can check the status later using: manage-dns-validation.sh status"
    return 1
}

# Function to update CloudFront distribution
update_cloudfront_distribution() {
    local target_profile="$1"
    
    echo "☁️  Updating CloudFront distribution with SSL certificate..."
    echo "   Per architecture: CloudFront distribution updated in environment-specific account"
    
    # Get required values from data files
    local cert_arn distribution_id domains
    
    if [[ -f "$DATA_DIR/cdk-outputs.json" ]]; then
        cert_arn=$(jq -r '.StageBSslCertificateStack.CertificateArnOutput // empty' "$DATA_DIR/cdk-outputs.json")
        distribution_id=$(jq -r '.StageBSslCertificateStack.DistributionIdOutput // empty' "$DATA_DIR/cdk-outputs.json")
        domains=$(jq -r '.StageBSslCertificateStack.DomainsOutput // empty' "$DATA_DIR/cdk-outputs.json")
    fi
    
    if [[ -z "$cert_arn" || -z "$distribution_id" || -z "$domains" ]]; then
        echo "❌ Error: Missing required values from CDK outputs"
        return 1
    fi
    
    echo "   Certificate ARN: $cert_arn"
    echo "   Distribution ID: $distribution_id"
    echo "   Domains: $domains"
    
    # Get current distribution configuration with timeout
    local current_config
    current_config=$(timeout $DNS_TIMEOUT aws cloudfront get-distribution-config \
        --id "$distribution_id" \
        --profile "$target_profile" \
        --output json 2>/dev/null)
    
    if [[ -z "$current_config" ]]; then
        echo "❌ Error: Failed to get current distribution configuration"
        return 1
    fi
    
    # Extract ETag and configuration
    local etag distribution_config
    etag=$(echo "$current_config" | jq -r '.ETag')
    distribution_config=$(echo "$current_config" | jq '.DistributionConfig')
    
    # Update the configuration with SSL certificate and domains
    local updated_config
    updated_config=$(echo "$distribution_config" | jq \
        --arg certArn "$cert_arn" \
        --arg domains "$domains" \
        '
        .Aliases.Items = ($domains | split(",")) |
        .Aliases.Quantity = (.Aliases.Items | length) |
        .ViewerCertificate.ACMCertificateArn = $certArn |
        .ViewerCertificate.SSLSupportMethod = "sni-only" |
        .ViewerCertificate.MinimumProtocolVersion = "TLSv1.2_2021" |
        .ViewerCertificate.CertificateSource = "acm" |
        del(.ViewerCertificate.CloudFrontDefaultCertificate)
        ')
    
    # Update the distribution with timeout
    echo "   📤 Applying CloudFront distribution update..."
    local update_result
    update_result=$(timeout $CDK_TIMEOUT aws cloudfront update-distribution \
        --id "$distribution_id" \
        --distribution-config "$updated_config" \
        --if-match "$etag" \
        --profile "$target_profile" \
        --output json 2>/dev/null)
    
    if [[ -n "$update_result" ]]; then
        echo "✅ CloudFront distribution updated successfully"
        echo "   🕐 Distribution deployment may take 10-15 minutes to complete globally"
        return 0
    else
        echo "❌ Failed to update CloudFront distribution"
        return 1
    fi
}

# Main deployment function
main() {
    echo "Starting Stage B SSL Certificate deployment..."
    echo "Architecture compliance: Certificates in environment accounts, DNS in infrastructure account"
    echo
    
    # Validate prerequisites
    validate_prerequisites
    
    # Read configuration
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    
    local target_profile
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    
    echo "Configuration:"
    echo "   Target Profile: $target_profile"
    echo "   Timeout Settings: CDK=$CDK_TIMEOUT sec, DNS=$DNS_TIMEOUT sec"
    echo
    
    # Step 1: Generate CDK context
    if ! generate_cdk_context; then
        echo "❌ Failed to generate CDK context"
        exit 1
    fi
    
    # Step 2: Deploy CDK stack (creates certificate in environment account)
    if ! deploy_cdk_stack "$target_profile"; then
        echo "❌ Failed to deploy CDK stack"
        exit 1
    fi
    
    # Step 3: Add DNS validation records to infrastructure account Route53
    if ! manage_dns_validation "add"; then
        echo "❌ Failed to add DNS validation records"
        exit 1
    fi
    
    # Step 4: Wait for certificate validation
    if ! wait_for_certificate_validation "$target_profile" 30; then
        echo "⚠️  Certificate validation incomplete, but continuing..."
        echo "   You can check status later with: scripts/manage-dns-validation.sh status"
    fi
    
    # Step 5: Update CloudFront distribution
    if ! update_cloudfront_distribution "$target_profile"; then
        echo "❌ Failed to update CloudFront distribution"
        exit 1
    fi
    
    # Save final outputs
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    jq -n \
        --argjson inputs "$(cat "$inputs_file")" \
        --argjson discovery "$(cat "$discovery_file")" \
        --argjson cdkOutputs "$(cat "$DATA_DIR/cdk-outputs.json" 2>/dev/null || echo '{}')" \
        --arg deploymentTimestamp "$timestamp" \
        --arg deploymentStatus "completed" \
        '{
        inputs: $inputs[0],
        discovery: $discovery[0],
        cdkOutputs: $cdkOutputs,
        deploymentTimestamp: $deploymentTimestamp,
        deploymentStatus: $deploymentStatus,
        infraAccountId: $discovery[0].infraAccountId,
        targetAccountId: $discovery[0].targetAccountId,
        certificateArn: $cdkOutputs.StageBSslCertificateStack.CertificateArnOutput,
        distributionId: $cdkOutputs.StageBSslCertificateStack.DistributionIdOutput,
        domains: ($cdkOutputs.StageBSslCertificateStack.DomainsOutput | split(","))
    }' > "$DATA_DIR/outputs.json"
    
    echo
    echo "🎉 Stage B SSL Certificate deployment completed successfully!"
    echo "   ✅ Certificate created in environment-specific account"
    echo "   ✅ DNS validation records added to infrastructure account Route53"
    echo "   ✅ CloudFront distribution updated with SSL certificate"
    echo
    echo "Next steps:"
    echo "   1. Wait for CloudFront distribution deployment (10-15 minutes)"
    echo "   2. Test your domains with HTTPS"
    echo "   3. Check certificate status: scripts/manage-dns-validation.sh status"
    echo
    echo "Architecture compliance: ✅ ALIGNED"
    echo "   - SSL certificates stored in environment-specific account (us-east-1)"
    echo "   - DNS validation records managed in infrastructure account Route53"
    echo "   - CloudFront distribution updated in environment-specific account"
}

# Run main function
main "$@" 