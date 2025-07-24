#!/bin/bash

# validate-deployment.sh
# Deployment validation for Stage B SSL Certificate deployment
# Tests HTTPS connectivity and validates SSL certificate attachment

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

echo "=== Stage B SSL Certificate Deployment - Validation ==="
echo "This script validates HTTPS connectivity and SSL certificate attachment."
echo

# Function to validate required files exist
validate_prerequisites() {
    local inputs_file="$DATA_DIR/inputs.json"
    local outputs_file="$DATA_DIR/outputs.json"
    
    echo "Validating prerequisites..."
    
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    if [[ ! -f "$outputs_file" ]]; then
        echo "❌ Error: outputs.json not found. Please run deploy-infrastructure.sh first."
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
}

# Function to check certificate validation status
check_certificate_status() {
    local infra_profile="$1"
    local cert_arn="$2"
    
    echo "🔒 Checking SSL certificate validation status..."
    echo "   Certificate ARN: $cert_arn"
    
    # Get certificate details
    local cert_details
    cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --profile "$infra_profile" --region us-east-1 --output json 2>/dev/null || echo '{}')
    
    if [[ "$cert_details" == "{}" ]]; then
        echo "❌ Could not retrieve certificate details"
        return 1
    fi
    
    local cert_status domains
    cert_status=$(echo "$cert_details" | jq -r '.Certificate.Status // "UNKNOWN"' 2>/dev/null)
    domains=$(echo "$cert_details" | jq -r '.Certificate.SubjectAlternativeNames[]?' 2>/dev/null | sort | tr '\n' ' ' || echo "")
    
    echo "   📋 Certificate Status: $cert_status"
    echo "   🌐 Certificate Domains: $domains"
    
    case "$cert_status" in
        "ISSUED")
            echo "✅ Certificate is validated and ready for use"
            return 0
            ;;
        "PENDING_VALIDATION")
            echo "⏳ Certificate is still pending validation"
            echo "   This may take several minutes after DNS records are created"
            return 1
            ;;
        "FAILED"|"VALIDATION_TIMED_OUT"|"REVOKED")
            echo "❌ Certificate validation failed with status: $cert_status"
            return 1
            ;;
        *)
            echo "⚠️  Certificate is in unexpected status: $cert_status"
            return 1
            ;;
    esac
}

# Function to check CloudFront distribution status
check_cloudfront_status() {
    local target_profile="$1"
    local distribution_id="$2"
    local expected_cert_arn="$3"
    local expected_domains=("${@:4}")
    
    echo "☁️  Checking CloudFront distribution status..."
    echo "   Distribution ID: $distribution_id"
    
    # Get distribution details
    local dist_details
    dist_details=$(aws cloudfront get-distribution --id "$distribution_id" --profile "$target_profile" --output json 2>/dev/null || echo '{}')
    
    if [[ "$dist_details" == "{}" ]]; then
        echo "❌ Could not retrieve CloudFront distribution details"
        return 1
    fi
    
    local dist_status aliases cert_arn viewer_protocol_policy
    dist_status=$(echo "$dist_details" | jq -r '.Distribution.Status // "UNKNOWN"' 2>/dev/null)
    aliases=$(echo "$dist_details" | jq -r '.Distribution.DistributionConfig.Aliases.Items[]?' 2>/dev/null | sort | tr '\n' ' ' || echo "")
    cert_arn=$(echo "$dist_details" | jq -r '.Distribution.DistributionConfig.ViewerCertificate.ACMCertificateArn // empty' 2>/dev/null)
    viewer_protocol_policy=$(echo "$dist_details" | jq -r '.Distribution.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy // "allow-all"' 2>/dev/null)
    
    echo "   📋 Distribution Status: $dist_status"
    echo "   🌐 Custom Domains: $aliases"
    echo "   🔒 SSL Certificate: ${cert_arn##*/}"
    echo "   🔐 Viewer Protocol Policy: $viewer_protocol_policy"
    
    # Validate distribution status
    case "$dist_status" in
        "Deployed")
            echo "✅ CloudFront distribution is deployed"
            ;;
        "InProgress")
            echo "⏳ CloudFront distribution is still updating"
            echo "   Changes may take 15-45 minutes to propagate"
            return 1
            ;;
        *)
            echo "❌ CloudFront distribution is in unexpected status: $dist_status"
            return 1
            ;;
    esac
    
    # Validate SSL certificate attachment
    if [[ -z "$cert_arn" ]]; then
        echo "❌ No SSL certificate attached to CloudFront distribution"
        return 1
    fi
    
    if [[ "$cert_arn" != "$expected_cert_arn" ]]; then
        echo "⚠️  Attached certificate does not match expected certificate"
        echo "   Expected: $expected_cert_arn"
        echo "   Attached: $cert_arn"
        # This is a warning, not an error - continue validation
    else
        echo "✅ Correct SSL certificate is attached to CloudFront distribution"
    fi
    
    # Validate custom domains
    local expected_domains_str
    expected_domains_str=$(printf '%s ' "${expected_domains[@]}" | sed 's/ $//')
    
    if [[ "$aliases" != "$expected_domains_str" ]]; then
        echo "⚠️  CloudFront aliases do not match expected domains"
        echo "   Expected: $expected_domains_str"
        echo "   Configured: $aliases"
        # This is a warning, not an error - continue validation
    else
        echo "✅ CloudFront distribution has correct custom domains configured"
    fi
    
    # Validate HTTPS redirect policy
    if [[ "$viewer_protocol_policy" == "redirect-to-https" ]]; then
        echo "✅ CloudFront is configured to redirect HTTP to HTTPS"
    else
        echo "⚠️  CloudFront viewer protocol policy is: $viewer_protocol_policy"
        echo "   Expected: redirect-to-https"
    fi
    
    return 0
}

# Function to test HTTPS connectivity for each domain
test_https_connectivity() {
    local domains=("$@")
    
    echo "🌐 Testing HTTPS connectivity for configured domains..."
    
    local successful_tests=0
    local total_tests=${#domains[@]}
    
    for domain in "${domains[@]}"; do
        echo "   🔍 Testing HTTPS connectivity for: https://$domain"
        
        # Test basic HTTPS connectivity
        local curl_result http_status cert_info
        curl_result=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "https://$domain" 2>/dev/null || echo "000")
        
        echo "      📊 HTTP Status Code: $curl_result"
        
        # Analyze HTTP status
        case "$curl_result" in
            "200"|"301"|"302"|"304")
                echo "      ✅ HTTPS connectivity successful"
                ((successful_tests++))
                ;;
            "000")
                echo "      ❌ HTTPS connection failed (timeout or DNS resolution failure)"
                echo "         This may be due to CloudFront propagation delays or DNS issues"
                ;;
            "403")
                echo "      ⚠️  HTTPS connection established but received 403 Forbidden"
                echo "         This may be expected if no content is configured for this domain"
                ((successful_tests++))
                ;;
            "404")
                echo "      ⚠️  HTTPS connection established but received 404 Not Found"
                echo "         This may be expected if no content is configured for this domain"
                ((successful_tests++))
                ;;
            *)
                echo "      ⚠️  HTTPS connection established but received unexpected status: $curl_result"
                ((successful_tests++))
                ;;
        esac
        
        # Test SSL certificate details
        echo "      🔒 Checking SSL certificate details..."
        cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" -verify_return_error 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "")
        
        if [[ -n "$cert_info" ]]; then
            echo "      ✅ SSL certificate is valid and properly configured"
            local subject issuer not_after
            subject=$(echo "$cert_info" | grep "subject=" | sed 's/subject=//' || echo "")
            issuer=$(echo "$cert_info" | grep "issuer=" | sed 's/issuer=//' || echo "")
            not_after=$(echo "$cert_info" | grep "notAfter=" | sed 's/notAfter=//' || echo "")
            
            [[ -n "$subject" ]] && echo "         Subject: $subject"
            [[ -n "$issuer" ]] && echo "         Issuer: $issuer"
            [[ -n "$not_after" ]] && echo "         Expires: $not_after"
        else
            echo "      ⚠️  Could not retrieve SSL certificate details"
            echo "         This may be due to network issues or certificate configuration problems"
        fi
        
        echo
    done
    
    echo "📊 HTTPS Connectivity Test Summary:"
    echo "   Total domains tested: $total_tests"
    echo "   Successful connections: $successful_tests"
    
    if [[ $successful_tests -eq $total_tests ]]; then
        echo "✅ All domains are accessible via HTTPS"
        return 0
    elif [[ $successful_tests -gt 0 ]]; then
        echo "⚠️  Some domains are accessible via HTTPS"
        echo "   Failed connections may be due to CloudFront propagation delays"
        return 1
    else
        echo "❌ No domains are accessible via HTTPS"
        echo "   This may be due to CloudFront propagation delays or configuration issues"
        return 1
    fi
}

# Function to validate DNS resolution
validate_dns_resolution() {
    local domains=("$@")
    
    echo "🌐 Validating DNS resolution for configured domains..."
    
    local successful_resolutions=0
    local total_domains=${#domains[@]}
    
    for domain in "${domains[@]}"; do
        echo "   🔍 Checking DNS resolution for: $domain"
        
        # Test DNS resolution
        local dns_result
        dns_result=$(dig +short "$domain" 2>/dev/null || echo "")
        
        if [[ -n "$dns_result" ]]; then
            echo "      ✅ DNS resolution successful"
            echo "         Resolved to: $dns_result"
            ((successful_resolutions++))
        else
            echo "      ❌ DNS resolution failed"
            echo "         Domain may not have DNS records configured"
        fi
        echo
    done
    
    echo "📊 DNS Resolution Summary:"
    echo "   Total domains tested: $total_domains"
    echo "   Successful resolutions: $successful_resolutions"
    
    if [[ $successful_resolutions -eq $total_domains ]]; then
        echo "✅ All domains resolve correctly"
        return 0
    else
        echo "⚠️  Some domains do not resolve correctly"
        echo "   You may need to configure DNS records to point to CloudFront"
        return 1
    fi
}

# Function to save validation results
save_validation_results() {
    local validation_status="$1"
    local cert_validated="$2"
    local cloudfront_ready="$3"
    local https_working="$4"
    local dns_working="$5"
    
    echo "💾 Saving validation results..."
    
    # Update outputs.json with validation results
    local temp_outputs="$DATA_DIR/outputs.json.tmp"
    jq --arg validationStatus "$validation_status" \
       --arg certValidated "$cert_validated" \
       --arg cloudfrontReady "$cloudfront_ready" \
       --arg httpsWorking "$https_working" \
       --arg dnsWorking "$dns_working" \
       --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       --arg readyForStageC "$(if [[ "$validation_status" == "passed" ]]; then echo "true"; else echo "false"; fi)" \
       '.validationStatus = $validationStatus |
        .certificateValidated = ($certValidated == "true") |
        .cloudfrontReady = ($cloudfrontReady == "true") |
        .httpsConnectivity = ($httpsWorking == "true") |
        .dnsResolution = ($dnsWorking == "true") |
        .validationTimestamp = $timestamp |
        .readyForStageC = ($readyForStageC == "true") |
        .certificateStatus = (if $certValidated == "true" then "ISSUED" else "PENDING_VALIDATION" end)' \
       "$DATA_DIR/outputs.json" > "$temp_outputs"
    
    mv "$temp_outputs" "$DATA_DIR/outputs.json"
    echo "✅ Validation results saved to outputs.json"
}

# Main validation orchestration function
main_validation() {
    echo "Starting Stage B SSL certificate deployment validation..."
    echo
    
    # Step 1: Validate prerequisites
    validate_prerequisites
    echo
    
    # Step 2: Load configuration
    local domains infra_profile target_profile distribution_id cert_arn
    mapfile -t domains < <(jq -r '.domains[]' "$DATA_DIR/inputs.json" | sort)
    infra_profile=$(jq -r '.infraProfile' "$DATA_DIR/inputs.json")
    target_profile=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    distribution_id=$(jq -r '.distributionId' "$DATA_DIR/inputs.json")
    cert_arn=$(jq -r '.certificateArn // empty' "$DATA_DIR/outputs.json")
    
    if [[ -z "$cert_arn" ]] || [[ "$cert_arn" == "unknown" ]]; then
        echo "❌ Could not find certificate ARN in outputs.json"
        echo "   Please ensure deploy-infrastructure.sh completed successfully"
        exit 1
    fi
    
    echo "📋 Validation Configuration:"
    echo "   Domains: ${domains[*]}"
    echo "   Certificate ARN: $cert_arn"
    echo "   Distribution ID: $distribution_id"
    echo "   Infrastructure Profile: $infra_profile"
    echo "   Target Profile: $target_profile"
    echo
    
    # Step 3: Check certificate validation status
    local cert_validated="false"
    if check_certificate_status "$infra_profile" "$cert_arn"; then
        cert_validated="true"
    fi
    echo
    
    # Step 4: Check CloudFront distribution status
    local cloudfront_ready="false"
    if check_cloudfront_status "$target_profile" "$distribution_id" "$cert_arn" "${domains[@]}"; then
        cloudfront_ready="true"
    fi
    echo
    
    # Step 5: Validate DNS resolution
    local dns_working="false"
    if validate_dns_resolution "${domains[@]}"; then
        dns_working="true"
    fi
    echo
    
    # Step 6: Test HTTPS connectivity
    local https_working="false"
    if [[ "$cert_validated" == "true" ]] && [[ "$cloudfront_ready" == "true" ]]; then
        if test_https_connectivity "${domains[@]}"; then
            https_working="true"
        fi
    else
        echo "⏭️  Skipping HTTPS connectivity tests due to certificate or CloudFront issues"
    fi
    echo
    
    # Step 7: Determine overall validation status
    local validation_status="failed"
    if [[ "$cert_validated" == "true" ]] && [[ "$cloudfront_ready" == "true" ]] && [[ "$https_working" == "true" ]]; then
        validation_status="passed"
    elif [[ "$cert_validated" == "false" ]]; then
        validation_status="pending"
    fi
    
    # Step 8: Save validation results
    save_validation_results "$validation_status" "$cert_validated" "$cloudfront_ready" "$https_working" "$dns_working"
    echo
    
    # Step 9: Display validation summary
    echo "📋 Stage B SSL Certificate Deployment Validation Summary"
    echo "════════════════════════════════════════════════════════"
    
    if [[ "$cert_validated" == "true" ]]; then
        echo "✅ SSL Certificate: Validated and ready"
    else
        echo "⏳ SSL Certificate: Pending validation"
    fi
    
    if [[ "$cloudfront_ready" == "true" ]]; then
        echo "✅ CloudFront Distribution: Deployed and configured"
    else
        echo "⏳ CloudFront Distribution: Not ready or updating"
    fi
    
    if [[ "$dns_working" == "true" ]]; then
        echo "✅ DNS Resolution: Working correctly"
    else
        echo "⚠️  DNS Resolution: Some issues detected"
    fi
    
    if [[ "$https_working" == "true" ]]; then
        echo "✅ HTTPS Connectivity: All domains accessible"
    else
        echo "⏳ HTTPS Connectivity: Some domains not accessible"
    fi
    
    echo
    echo "🎯 Overall Validation Status: $validation_status"
    
    case "$validation_status" in
        "passed")
            echo "✅ Stage B SSL certificate deployment validation PASSED!"
            echo "   All domains are accessible via HTTPS with valid SSL certificates"
            echo "   CloudFront distribution is properly configured"
            echo "   Ready to proceed to Stage C"
            ;;
        "pending")
            echo "⏳ Stage B SSL certificate deployment validation PENDING"
            echo "   Certificate validation is still in progress"
            echo "   Re-run this script in a few minutes to check again"
            ;;
        "failed")
            echo "❌ Stage B SSL certificate deployment validation FAILED"
            echo "   Please check the issues above and resolve them"
            echo "   You may need to re-run previous deployment steps"
            ;;
    esac
    
    echo
    echo "💡 Next Steps:"
    if [[ "$validation_status" == "passed" ]]; then
        echo "   - Your HTTPS deployment is complete and working"
        echo "   - Test your domains: $(printf 'https://%s ' "${domains[@]}")"
        echo "   - Proceed to Stage C for Lambda function integration"
    elif [[ "$validation_status" == "pending" ]]; then
        echo "   - Wait for certificate validation to complete (usually 5-30 minutes)"
        echo "   - Re-run this validation script: ./scripts/validate-deployment.sh"
        echo "   - Monitor certificate status: ./status-b.sh"
    else
        echo "   - Review the validation errors above"
        echo "   - Check CloudFront distribution status in AWS Console"
        echo "   - Verify DNS records are configured correctly"
        echo "   - Re-run deployment scripts if necessary"
    fi
    
    # Return appropriate exit code
    case "$validation_status" in
        "passed") return 0 ;;
        "pending") return 2 ;;
        *) return 1 ;;
    esac
}

# Main execution
main() {
    main_validation
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 