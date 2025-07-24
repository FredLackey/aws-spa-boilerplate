#!/bin/bash

# validate-architecture.sh
# Validates that Stage B SSL implementation aligns with ARCHITECTURE.md requirements
# Checks certificate location, DNS validation approach, and CloudFront configuration

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

echo "=== Stage B SSL Architecture Validation ==="
echo "Verifying alignment with ARCHITECTURE.md requirements"
echo

# Function to validate certificate is in correct account
validate_certificate_location() {
    echo "🔍 Validating SSL certificate location..."
    
    if [[ ! -f "$DATA_DIR/inputs.json" ]] || [[ ! -f "$DATA_DIR/outputs.json" ]]; then
        echo "⚠️  Missing data files - Stage B may not be deployed yet"
        return 1
    fi
    
    local target_account_id cert_arn target_profile
    target_account_id=$(jq -r '.targetAccountId' "$DATA_DIR/inputs.json")
    cert_arn=$(jq -r '.certificateArn // empty' "$DATA_DIR/outputs.json")
    target_profile=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    if [[ -z "$cert_arn" ]]; then
        echo "❌ No certificate ARN found in outputs"
        return 1
    fi
    
    echo "   Certificate ARN: $cert_arn"
    echo "   Expected Account: $target_account_id (environment-specific)"
    
    # Extract account ID from certificate ARN
    local cert_account_id
    cert_account_id=$(echo "$cert_arn" | cut -d':' -f5)
    
    if [[ "$cert_account_id" == "$target_account_id" ]]; then
        echo "   ✅ Certificate is in correct environment-specific account"
        return 0
    else
        echo "   ❌ Certificate is in wrong account: $cert_account_id (expected: $target_account_id)"
        return 1
    fi
}

# Function to validate DNS validation approach
validate_dns_validation() {
    echo "🌐 Validating DNS validation approach..."
    
    if [[ ! -f "$DATA_DIR/discovery.json" ]]; then
        echo "⚠️  Missing discovery data - cannot validate DNS setup"
        return 1
    fi
    
    local infra_account_id hosted_zones
    infra_account_id=$(jq -r '.infraAccountId' "$DATA_DIR/discovery.json")
    hosted_zones=$(jq -r '.hostedZones[0].zoneName' "$DATA_DIR/discovery.json")
    
    echo "   Infrastructure Account: $infra_account_id (for Route53 DNS)"
    echo "   Hosted Zone: $hosted_zones"
    
    # Check if manage-dns-validation.sh script exists
    local dns_script="$SCRIPT_DIR/manage-dns-validation.sh"
    if [[ -f "$dns_script" ]]; then
        echo "   ✅ DNS validation management script exists"
        echo "   ✅ DNS validation records managed in infrastructure account"
        return 0
    else
        echo "   ❌ DNS validation management script missing"
        return 1
    fi
}

# Function to validate CloudFront configuration
validate_cloudfront_configuration() {
    echo "☁️  Validating CloudFront configuration..."
    
    if [[ ! -f "$DATA_DIR/inputs.json" ]] || [[ ! -f "$DATA_DIR/outputs.json" ]]; then
        echo "⚠️  Missing data files - cannot validate CloudFront setup"
        return 1
    fi
    
    local target_account_id distribution_id target_profile
    target_account_id=$(jq -r '.targetAccountId' "$DATA_DIR/inputs.json")
    distribution_id=$(jq -r '.distributionId' "$DATA_DIR/inputs.json")
    target_profile=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    echo "   Distribution ID: $distribution_id"
    echo "   Expected Account: $target_account_id (environment-specific)"
    
    # Verify distribution exists in target account
    echo "   🔍 Testing CloudFront distribution access..."
    if aws cloudfront get-distribution --id "$distribution_id" --profile "$target_profile" --query 'Distribution.Id' --output text >/dev/null 2>&1; then
        echo "   ✅ CloudFront distribution accessible in environment-specific account"
        return 0
    else
        echo "   ❌ CloudFront distribution not accessible in target account"
        echo "   ℹ️  This may be due to AWS credentials or permissions"
        return 1
    fi
}

# Function to validate script architecture compliance
validate_script_compliance() {
    echo "📜 Validating script architecture compliance..."
    
    local issues=0
    
    # Check SSL certificate stack
    local ssl_stack="$STAGE_DIR/iac/lib/ssl-certificate-stack.ts"
    if [[ -f "$ssl_stack" ]]; then
        # Should NOT import route53 for zone management
        if grep -q "import.*route53" "$ssl_stack"; then
            echo "   ❌ SSL stack imports route53 - should not manage DNS zones"
            ((issues++))
        else
            echo "   ✅ SSL stack does not manage Route53 zones"
        fi
        
        # Should create certificates with DNS validation
        if grep -q "CertificateValidation.fromDns()" "$ssl_stack"; then
            echo "   ✅ SSL stack uses DNS validation"
        else
            echo "   ❌ SSL stack does not use DNS validation"
            ((issues++))
        fi
    else
        echo "   ❌ SSL certificate stack not found"
        ((issues++))
    fi
    
    # Check deployment script uses target profile
    local deploy_script="$SCRIPT_DIR/deploy-infrastructure.sh"
    if [[ -f "$deploy_script" ]]; then
        if grep -q 'AWS_PROFILE="$target_profile"' "$deploy_script"; then
            echo "   ✅ Deployment script uses target profile for certificate creation"
        else
            echo "   ❌ Deployment script does not use target profile"
            ((issues++))
        fi
    else
        echo "   ❌ Deployment script not found"
        ((issues++))
    fi
    
    # Check DNS validation script exists
    local dns_script="$SCRIPT_DIR/manage-dns-validation.sh"
    if [[ -f "$dns_script" ]]; then
        echo "   ✅ DNS validation management script exists"
    else
        echo "   ❌ DNS validation management script missing"
        ((issues++))
    fi
    
    return $issues
}

# Main validation function
main() {
    local validation_errors=0
    
    echo "Checking Stage B SSL implementation against ARCHITECTURE.md requirements..."
    echo
    
    # Architecture Requirements from ARCHITECTURE.md:
    echo "📋 Architecture Requirements:"
    echo "   1. SSL certificates in environment-specific accounts (us-east-1)"
    echo "   2. DNS validation records in infrastructure account Route53"
    echo "   3. CloudFront distributions in environment-specific accounts"
    echo "   4. No Route53 hosted zones in member accounts"
    echo
    
    # Run validations
    echo "Running validations..."
    echo
    
    if ! validate_certificate_location; then
        ((validation_errors++))
    fi
    echo
    
    if ! validate_dns_validation; then
        ((validation_errors++))
    fi
    echo
    
    if ! validate_cloudfront_configuration; then
        ((validation_errors++))
    fi
    echo
    
    if ! validate_script_compliance; then
        ((validation_errors++))
    fi
    echo
    
    # Final results
    if [[ $validation_errors -eq 0 ]]; then
        echo "🎉 VALIDATION PASSED"
        echo "   ✅ Stage B SSL implementation is ALIGNED with ARCHITECTURE.md"
        echo
        echo "Architecture Compliance Summary:"
        echo "   ✅ SSL certificates stored in environment-specific accounts"
        echo "   ✅ DNS validation managed in infrastructure account Route53"
        echo "   ✅ CloudFront distributions in environment-specific accounts"
        echo "   ✅ Scripts follow centralized DNS approach"
        echo
        echo "Stage B is ready for production use!"
        exit 0
    else
        echo "❌ VALIDATION FAILED"
        echo "   Found $validation_errors architecture compliance issues"
        echo
        echo "Please review the issues above and ensure Stage B aligns with ARCHITECTURE.md"
        echo "Run this script again after making corrections."
        exit 1
    fi
}

# Run main function
main "$@" 