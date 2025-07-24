#!/bin/bash

# status-d.sh
# Status checking script for Stage D React deployment
# Checks the health and status of deployed React application and CloudFront distribution

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

echo "=== Stage D React Deployment - Status Check ==="
echo "This script will check the status and health of your React application deployment."
echo

# Function to validate prerequisites
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # Check for required data files
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found. React deployment may not be started."
        return 1
    fi
    
    if [[ ! -f "$DATA_DIR/outputs.json" ]]; then
        echo "⚠️  Warning: outputs.json not found. Deployment may not be complete."
        echo "   Will check what's available from other data files."
    fi
    
    # Check if aws CLI is available
    if ! command -v aws > /dev/null 2>&1; then
        echo "❌ Error: AWS CLI not found. Please install AWS CLI."
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq > /dev/null 2>&1; then
        echo "❌ Error: jq command not found. Please install jq."
        return 1
    fi
    
    # Check if curl is available
    if ! command -v curl > /dev/null 2>&1; then
        echo "❌ Error: curl command not found. Please install curl."
        return 1
    fi
    
    echo "✅ Prerequisites validated"
    return 0
}

# Function to extract deployment information
extract_deployment_info() {
    echo "Extracting deployment information..."
    
    # Initialize global variables
    TARGET_PROFILE=""
    DISTRIBUTION_PREFIX=""
    DISTRIBUTION_ID=""
    BUCKET_NAME=""
    CERTIFICATE_ARN=""
    DOMAINS=""
    DISTRIBUTION_DOMAIN=""
    
    # Load from inputs.json if available
    if [[ -f "$DATA_DIR/inputs.json" ]]; then
        TARGET_PROFILE=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json")
        DISTRIBUTION_PREFIX=$(jq -r '.distributionPrefix // empty' "$DATA_DIR/inputs.json")
    fi
    
    # Load from outputs.json if available
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        DISTRIBUTION_ID=$(jq -r '.distributionId // empty' "$DATA_DIR/outputs.json")
        BUCKET_NAME=$(jq -r '.bucketName // empty' "$DATA_DIR/outputs.json")
        CERTIFICATE_ARN=$(jq -r '.stageD.certificateArn // empty' "$DATA_DIR/outputs.json")
        DISTRIBUTION_DOMAIN=$(jq -r '.distributionDomainName // empty' "$DATA_DIR/outputs.json")
        DOMAINS=$(jq -r '.domains[]? // empty' "$DATA_DIR/outputs.json" | tr '\n' ' ')
    fi
    
    # Try to get info from previous stages if current outputs missing
    if [[ -z "$DISTRIBUTION_ID" ]] && [[ -f "../a-cloudfront/data/outputs.json" ]]; then
        DISTRIBUTION_ID=$(jq -r '.distributionId // empty' "../a-cloudfront/data/outputs.json")
    fi
    
    if [[ -z "$BUCKET_NAME" ]] && [[ -f "../a-cloudfront/data/outputs.json" ]]; then
        BUCKET_NAME=$(jq -r '.bucketName // empty' "../a-cloudfront/data/outputs.json")
    fi
    
    if [[ -z "$CERTIFICATE_ARN" ]] && [[ -f "../b-ssl/data/outputs.json" ]]; then
        CERTIFICATE_ARN=$(jq -r '.certificateArn // empty' "../b-ssl/data/outputs.json")
    fi
    
    if [[ -z "$DOMAINS" ]] && [[ -f "../b-ssl/data/outputs.json" ]]; then
        DOMAINS=$(jq -r '.domains[]? // empty' "../b-ssl/data/outputs.json" | tr '\n' ' ')
    fi
    
    if [[ -z "$DISTRIBUTION_DOMAIN" ]] && [[ -f "../a-cloudfront/data/outputs.json" ]]; then
        DISTRIBUTION_DOMAIN=$(jq -r '.distributionDomainName // empty' "../a-cloudfront/data/outputs.json")
    fi
    
    echo "✅ Deployment information extracted"
}

# Function to check AWS CloudFront distribution status
check_cloudfront_status() {
    echo
    echo "🔍 Checking CloudFront Distribution Status"
    echo "$(printf '%.0s─' {1..50})"
    
    if [[ -z "$DISTRIBUTION_ID" ]]; then
        echo "❌ CloudFront Distribution ID not found"
        return 1
    fi
    
    echo "Distribution ID: $DISTRIBUTION_ID"
    
    local distribution_status
    if distribution_status=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --profile "$TARGET_PROFILE" 2>&1); then
        local status enabled domain_name
        status=$(echo "$distribution_status" | jq -r '.Distribution.Status')
        enabled=$(echo "$distribution_status" | jq -r '.Distribution.DistributionConfig.Enabled')
        domain_name=$(echo "$distribution_status" | jq -r '.Distribution.DomainName')
        
        echo "✅ Distribution Status: $status"
        echo "✅ Distribution Enabled: $enabled"
        echo "✅ Distribution Domain: $domain_name"
        
        # Check if distribution is deployed
        if [[ "$status" == "Deployed" ]]; then
            echo "✅ Distribution is fully deployed and ready"
        else
            echo "⚠️  Distribution is still deploying (status: $status)"
        fi
        
        return 0
    else
        echo "❌ Failed to get CloudFront distribution status"
        echo "Error: $distribution_status"
        return 1
    fi
}

# Function to check S3 bucket status and content
check_s3_bucket_status() {
    echo
    echo "🔍 Checking S3 Bucket Status and Content"
    echo "$(printf '%.0s─' {1..50})"
    
    if [[ -z "$BUCKET_NAME" ]]; then
        echo "❌ S3 Bucket name not found"
        return 1
    fi
    
    echo "Bucket Name: $BUCKET_NAME"
    
    # Check if bucket exists and is accessible
    if aws s3 ls "s3://$BUCKET_NAME" --profile "$TARGET_PROFILE" > /dev/null 2>&1; then
        echo "✅ S3 bucket is accessible"
        
        # Check for key React files
        local has_index has_assets
        has_index=false
        has_assets=false
        
        if aws s3 ls "s3://$BUCKET_NAME/index.html" --profile "$TARGET_PROFILE" > /dev/null 2>&1; then
            has_index=true
            echo "✅ index.html found in bucket"
        else
            echo "❌ index.html not found in bucket"
        fi
        
        if aws s3 ls "s3://$BUCKET_NAME/assets/" --profile "$TARGET_PROFILE" > /dev/null 2>&1; then
            has_assets=true
            echo "✅ assets/ directory found in bucket"
        else
            echo "⚠️  assets/ directory not found in bucket"
        fi
        
        # List bucket contents summary
        local object_count
        object_count=$(aws s3 ls "s3://$BUCKET_NAME" --recursive --profile "$TARGET_PROFILE" | wc -l)
        echo "📊 Total objects in bucket: $object_count"
        
        if [[ "$has_index" == "true" ]]; then
            return 0
        else
            return 1
        fi
    else
        echo "❌ S3 bucket is not accessible or does not exist"
        return 1
    fi
}

# Function to test React application accessibility
test_react_application() {
    echo
    echo "🔍 Testing React Application Accessibility"
    echo "$(printf '%.0s─' {1..50})"
    
    local test_urls=()
    
    # Add custom domains if available
    if [[ -n "$DOMAINS" ]]; then
        for domain in $DOMAINS; do
            test_urls+=("https://$domain")
        done
    fi
    
    # Add CloudFront domain
    if [[ -n "$DISTRIBUTION_DOMAIN" ]]; then
        test_urls+=("https://$DISTRIBUTION_DOMAIN")
    fi
    
    if [[ ${#test_urls[@]} -eq 0 ]]; then
        echo "❌ No URLs available for testing"
        return 1
    fi
    
    local all_tests_passed=true
    
    for url in "${test_urls[@]}"; do
        echo "Testing: $url"
        
        local response_code content_type has_react_content
        
        # Test HTTP response
        if response_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" --max-time 30); then
            echo "  ✅ HTTP Status: $response_code"
            
            if [[ "$response_code" == "200" ]]; then
                # Test content type
                content_type=$(curl -s -I "$url" --max-time 30 | grep -i content-type | cut -d' ' -f2- | tr -d '\r')
                echo "  ✅ Content-Type: $content_type"
                
                # Check for React-specific content
                local page_content
                if page_content=$(curl -s "$url" --max-time 30); then
                    if echo "$page_content" | grep -qi "react\|vite\|root"; then
                        echo "  ✅ React application content detected"
                        has_react_content=true
                    else
                        echo "  ⚠️  React-specific content not detected"
                        has_react_content=false
                    fi
                else
                    echo "  ❌ Failed to retrieve page content"
                    all_tests_passed=false
                    continue
                fi
                
                # Check for JavaScript and CSS assets
                if echo "$page_content" | grep -q "\.js\|\.css"; then
                    echo "  ✅ JavaScript/CSS assets referenced"
                else
                    echo "  ⚠️  No JavaScript/CSS assets found"
                fi
                
            else
                echo "  ❌ Unexpected HTTP status code"
                all_tests_passed=false
            fi
        else
            echo "  ❌ Failed to connect to URL"
            all_tests_passed=false
        fi
        
        echo
    done
    
    if [[ "$all_tests_passed" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check SSL certificate status
check_ssl_certificate() {
    echo
    echo "🔍 Checking SSL Certificate Status"
    echo "$(printf '%.0s─' {1..50})"
    
    if [[ -z "$CERTIFICATE_ARN" ]]; then
        echo "❌ SSL Certificate ARN not found"
        return 1
    fi
    
    echo "Certificate ARN: $CERTIFICATE_ARN"
    
    local cert_status
    if cert_status=$(aws acm describe-certificate --certificate-arn "$CERTIFICATE_ARN" --profile "$TARGET_PROFILE" 2>&1); then
        local status domain_name
        status=$(echo "$cert_status" | jq -r '.Certificate.Status')
        domain_name=$(echo "$cert_status" | jq -r '.Certificate.DomainName')
        
        echo "✅ Certificate Status: $status"
        echo "✅ Primary Domain: $domain_name"
        
        if [[ "$status" == "ISSUED" ]]; then
            echo "✅ Certificate is valid and issued"
            return 0
        else
            echo "⚠️  Certificate status is not 'ISSUED'"
            return 1
        fi
    else
        echo "❌ Failed to get certificate status"
        echo "Error: $cert_status"
        return 1
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    echo
    echo "📊 Stage D React Deployment Summary"
    echo "==================================="
    
    if [[ -n "$DISTRIBUTION_ID" ]]; then
        echo "CloudFront Distribution: $DISTRIBUTION_ID"
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "S3 Bucket: $BUCKET_NAME"
    fi
    
    if [[ -n "$CERTIFICATE_ARN" ]]; then
        echo "SSL Certificate: $CERTIFICATE_ARN"
    fi
    
    if [[ -n "$DOMAINS" ]]; then
        echo "Custom Domains: $DOMAINS"
    fi
    
    if [[ -n "$DISTRIBUTION_DOMAIN" ]]; then
        echo "CloudFront Domain: $DISTRIBUTION_DOMAIN"
    fi
    
    echo
    echo "🌐 Application URLs:"
    if [[ -n "$DOMAINS" ]]; then
        for domain in $DOMAINS; do
            echo "  https://$domain"
        done
    fi
    if [[ -n "$DISTRIBUTION_DOMAIN" ]]; then
        echo "  https://$DISTRIBUTION_DOMAIN"
    fi
}

# Main execution function
main() {
    if ! validate_prerequisites; then
        exit 1
    fi
    
    extract_deployment_info
    
    local overall_status=0
    
    # Run all status checks
    if ! check_cloudfront_status; then
        overall_status=1
    fi
    
    if ! check_s3_bucket_status; then
        overall_status=1
    fi
    
    if ! check_ssl_certificate; then
        overall_status=1
    fi
    
    if ! test_react_application; then
        overall_status=1
    fi
    
    show_deployment_summary
    
    echo
    if [[ $overall_status -eq 0 ]]; then
        echo "🎉 Overall Status: ✅ ALL SYSTEMS OPERATIONAL"
        echo "Your React application is successfully deployed and accessible!"
    else
        echo "⚠️  Overall Status: ❌ ISSUES DETECTED"
        echo "Some components have issues. Please review the details above."
        echo "You may need to re-run the deployment or check your configuration."
    fi
    
    exit $overall_status
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 