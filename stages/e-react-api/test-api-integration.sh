#!/bin/bash

# test-api-integration.sh
# Comprehensive test script for Stage E API integration
# Tests the API endpoint accessibility and functionality

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

echo "🧪 AWS SPA Boilerplate - Stage E API Integration Test"
echo "===================================================="
echo

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test the Stage E API integration and endpoint functionality.

Options:
  -h, --help        Show this help message
  -v, --verbose     Enable verbose output
  -w, --wait        Wait for cache invalidation before testing

Examples:
  $0                # Basic API test
  $0 -v            # Verbose API test with detailed output
  $0 -w            # Wait for cache invalidation and test

EOF
}

# Parse command line arguments
VERBOSE=false
WAIT_FOR_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -w|--wait)
            WAIT_FOR_CACHE=true
            shift
            ;;
        *)
            echo "❌ Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
done

# Function to read configuration
read_configuration() {
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found. Please run ./go-e.sh first."
        exit 1
    fi
    
    DISTRIBUTION_ID=$(jq -r '.distributionId' "$DATA_DIR/inputs.json")
    PRIMARY_DOMAIN=$(jq -r '.primaryDomain' "$DATA_DIR/inputs.json")
    LAMBDA_FUNCTION_URL=$(jq -r '.lambdaFunctionUrl' "$DATA_DIR/inputs.json")
    TARGET_PROFILE=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    echo "📖 Configuration:"
    echo "   Distribution ID: $DISTRIBUTION_ID"
    echo "   Primary Domain: $PRIMARY_DOMAIN"
    echo "   Lambda Function URL: $LAMBDA_FUNCTION_URL"
    echo "   AWS Profile: $TARGET_PROFILE"
    echo
}

# Function to wait for cache invalidation
wait_for_cache_invalidation() {
    if [[ "$WAIT_FOR_CACHE" != "true" ]]; then
        return 0
    fi
    
    echo "⏳ Waiting for CloudFront cache invalidation to complete..."
    
    # Check for recent invalidations
    local recent_invalidation
    if recent_invalidation=$(aws cloudfront list-invalidations \
        --distribution-id "$DISTRIBUTION_ID" \
        --profile "$TARGET_PROFILE" \
        --query 'InvalidationList.Items[0].Id' \
        --output text 2>/dev/null); then
        
        if [[ "$recent_invalidation" != "None" && "$recent_invalidation" != "null" ]]; then
            echo "   Found recent invalidation: $recent_invalidation"
            echo "   Waiting for completion..."
            
            # Wait for invalidation to complete (up to 5 minutes)
            local wait_count=0
            while [[ $wait_count -lt 30 ]]; do
                local status
                if status=$(aws cloudfront get-invalidation \
                    --distribution-id "$DISTRIBUTION_ID" \
                    --id "$recent_invalidation" \
                    --profile "$TARGET_PROFILE" \
                    --query 'Invalidation.Status' \
                    --output text 2>/dev/null); then
                    
                    if [[ "$status" == "Completed" ]]; then
                        echo "   ✅ Cache invalidation completed"
                        break
                    else
                        echo "   Status: $status (waiting...)"
                        sleep 10
                        ((wait_count++))
                    fi
                else
                    echo "   ⚠️  Could not check invalidation status"
                    break
                fi
            done
            
            if [[ $wait_count -ge 30 ]]; then
                echo "   ⚠️  Timeout waiting for invalidation. Proceeding with tests..."
            fi
        else
            echo "   No recent invalidation found"
        fi
    else
        echo "   ⚠️  Could not check invalidation status"
    fi
    
    echo
}

# Function to test React app routing
test_react_app() {
    echo "🌐 Testing React application routing..."
    
    local test_urls=(
        "https://$PRIMARY_DOMAIN/"
        "https://$DISTRIBUTION_ID.cloudfront.net/"
    )
    
    for url in "${test_urls[@]}"; do
        echo "   Testing: $url"
        
        local response
        if response=$(curl -s -w "%{http_code}" "$url" 2>/dev/null); then
            local http_code="${response: -3}"
            local body="${response%???}"
            
            if [[ "$http_code" =~ ^[2] ]]; then
                if echo "$body" | grep -q "<!doctype html" && echo "$body" | grep -q "AWS SPA Boilerplate"; then
                    echo "     ✅ React app accessible (HTTP $http_code)"
                else
                    echo "     ⚠️  Response received but doesn't look like React app (HTTP $http_code)"
                fi
            else
                echo "     ❌ Failed to access React app (HTTP $http_code)"
            fi
        else
            echo "     ❌ Failed to reach URL"
        fi
    done
    
    echo
}

# Function to test API routing
test_api_routing() {
    echo "🔗 Testing API routing behavior..."
    
    local api_paths=(
        "/api/"
        "/api/test"
        "/api/health"
    )
    
    local test_domains=(
        "$PRIMARY_DOMAIN"
        "$DISTRIBUTION_ID.cloudfront.net"
    )
    
    for domain in "${test_domains[@]}"; do
        echo "   Testing domain: $domain"
        
        for path in "${api_paths[@]}"; do
            local url="https://$domain$path"
            echo "     Testing: $url"
            
            local response
            if response=$(curl -s -w "%{http_code}" "$url" 2>/dev/null); then
                local http_code="${response: -3}"
                local body="${response%???}"
                
                if [[ "$VERBOSE" == "true" ]]; then
                    echo "       HTTP $http_code"
                    echo "       Response (first 100 chars): ${body:0:100}..."
                fi
                
                # Check if we're getting HTML (React app) or JSON/error (Lambda)
                if echo "$body" | grep -q "<!doctype html"; then
                    echo "       ❌ Getting React app HTML (cache behavior not working)"
                elif echo "$body" | grep -q -E '"Message":|"message":|"error":|"Error":'; then
                    echo "       ✅ Getting Lambda response (HTTP $http_code)"
                elif [[ "$http_code" == "403" ]]; then
                    echo "       ✅ Getting Lambda 403 (expected due to IAM auth)"
                else
                    echo "       ⚠️  Unknown response type (HTTP $http_code)"
                fi
            else
                echo "       ❌ Failed to reach URL"
            fi
        done
        echo
    done
}

# Function to test Lambda function access
test_lambda_function() {
    echo "🔧 Testing Lambda function configuration..."
    
    # Check Lambda function URL auth type
    local auth_type
    if auth_type=$(aws lambda get-function-url-config \
        --function-name "hellospa-api" \
        --profile "$TARGET_PROFILE" \
        --query 'AuthType' \
        --output text 2>/dev/null); then
        
        echo "   Lambda Function URL Auth Type: $auth_type"
        
        if [[ "$auth_type" == "AWS_IAM" ]]; then
            echo "   ℹ️  Lambda requires IAM authentication - 403 responses are expected when accessing directly"
        fi
    else
        echo "   ⚠️  Could not check Lambda function URL configuration"
    fi
    
    echo
}

# Function to show test summary
show_test_summary() {
    echo "📊 Test Summary"
    echo "==============="
    echo
    echo "✅ What should be working:"
    echo "   - React app accessible at https://$PRIMARY_DOMAIN/"
    echo "   - CloudFront distribution deployed and configured"
    echo "   - API cache behavior (/api/*) configured to route to Lambda origin"
    echo "   - Lambda origin added to CloudFront"
    echo
    echo "⚠️  Expected behaviors:"
    echo "   - Lambda Function URL returns 403 (IAM auth required)"
    echo "   - API paths through CloudFront may return 403 or Lambda errors"
    echo "   - Cache invalidation may take 5-15 minutes to fully propagate"
    echo
    echo "🔧 If API routing is not working:"
    echo "   1. Wait 10-15 minutes for CloudFront cache to fully clear"
    echo "   2. Check cache behavior precedence in CloudFront console"
    echo "   3. Create manual cache invalidation: aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths '/api/*'"
    echo "   4. Verify Lambda function is accessible with IAM credentials"
    echo
    echo "🌐 Test URLs:"
    echo "   React App: https://$PRIMARY_DOMAIN/"
    echo "   API Endpoint: https://$PRIMARY_DOMAIN/api/"
    echo "   CloudFront: https://$DISTRIBUTION_ID.cloudfront.net/"
    echo
}

# Main execution
main() {
    read_configuration
    wait_for_cache_invalidation
    test_react_app
    test_api_routing
    test_lambda_function
    show_test_summary
}

# Execute main function
main "$@" 