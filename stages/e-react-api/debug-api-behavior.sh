#!/bin/bash

# debug-api-behavior.sh
# Debug script for Stage E API behavior configuration
# Checks CloudFront distribution, origins, behaviors, and tests API endpoint

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

echo "🔍 AWS SPA Boilerplate - Stage E API Behavior Debug"
echo "=================================================="
echo

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Debug the Stage E API behavior configuration.

Options:
  -h, --help        Show this help message
  -v, --verbose     Enable verbose output
  -t, --test-api    Test the API endpoint functionality

Examples:
  $0                # Basic debug check
  $0 -v            # Verbose debug with detailed output
  $0 -t            # Include API endpoint testing

EOF
}

# Parse command line arguments
VERBOSE=false
TEST_API=false

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
        -t|--test-api)
            TEST_API=true
            shift
            ;;
        *)
            echo "❌ Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
done

# Function to check if required files exist
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    local missing_files=()
    
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        missing_files+=("inputs.json")
    fi
    
    if [[ ! -f "$DATA_DIR/outputs.json" ]]; then
        missing_files+=("outputs.json")
    fi
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo "❌ Missing required files:"
        printf "   - %s\n" "${missing_files[@]}"
        echo "Please run the deployment first: ./go-e.sh"
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
}

# Function to read configuration
read_configuration() {
    echo "📖 Reading configuration..."
    
    DISTRIBUTION_ID=$(jq -r '.distributionId' "$DATA_DIR/inputs.json")
    BUCKET_NAME=$(jq -r '.bucketName' "$DATA_DIR/inputs.json")
    PRIMARY_DOMAIN=$(jq -r '.primaryDomain' "$DATA_DIR/inputs.json")
    LAMBDA_FUNCTION_URL=$(jq -r '.lambdaFunctionUrl' "$DATA_DIR/inputs.json")
    TARGET_PROFILE=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    echo "   Distribution ID: $DISTRIBUTION_ID"
    echo "   Bucket Name: $BUCKET_NAME"
    echo "   Primary Domain: $PRIMARY_DOMAIN"
    echo "   Lambda Function URL: $LAMBDA_FUNCTION_URL"
    echo "   AWS Profile: $TARGET_PROFILE"
    echo
}

# Function to check CloudFront distribution
check_cloudfront_distribution() {
    echo "☁️  Checking CloudFront distribution..."
    
    # Get distribution info
    local distribution_info
    if distribution_info=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --profile "$TARGET_PROFILE" \
        --query 'Distribution.{Status:Status,DomainName:DomainName}' \
        --output json 2>/dev/null); then
        
        local status domain_name
        status=$(echo "$distribution_info" | jq -r '.Status')
        domain_name=$(echo "$distribution_info" | jq -r '.DomainName')
        
        echo "   ✅ Distribution Status: $status"
        echo "   ✅ Distribution Domain: $domain_name"
        
        if [[ "$status" != "Deployed" ]]; then
            echo "   ⚠️  Distribution is not fully deployed yet"
        fi
    else
        echo "   ❌ Failed to get distribution information"
        return 1
    fi
}

# Function to check origins
check_cloudfront_origins() {
    echo "🌐 Checking CloudFront origins..."
    
    local origins
    if origins=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --profile "$TARGET_PROFILE" \
        --query 'Distribution.DistributionConfig.Origins' \
        --output json 2>/dev/null); then
        
        local origin_count
        origin_count=$(echo "$origins" | jq -r '.Quantity')
        echo "   Origins count: $origin_count"
        
        # Check each origin
        echo "$origins" | jq -r '.Items[] | "   - \(.Id): \(.DomainName)"'
        
        # Check if Lambda origin exists
        local lambda_origin_exists
        lambda_origin_exists=$(echo "$origins" | jq -r '.Items[] | select(.Id == "lambda-api-origin") | .Id')
        
        if [[ -n "$lambda_origin_exists" ]]; then
            echo "   ✅ Lambda API origin found"
        else
            echo "   ❌ Lambda API origin missing"
            return 1
        fi
    else
        echo "   ❌ Failed to get origins information"
        return 1
    fi
}

# Function to check cache behaviors
check_cache_behaviors() {
    echo "⚡ Checking CloudFront cache behaviors..."
    
    local behaviors
    if behaviors=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --profile "$TARGET_PROFILE" \
        --query 'Distribution.DistributionConfig.CacheBehaviors' \
        --output json 2>/dev/null); then
        
        local behavior_count
        behavior_count=$(echo "$behaviors" | jq -r '.Quantity')
        echo "   Cache behaviors count: $behavior_count"
        
        if [[ "$behavior_count" -gt 0 ]]; then
            echo "   Cache behaviors:"
            echo "$behaviors" | jq -r '.Items[] | "   - \(.PathPattern) -> \(.TargetOriginId)"'
            
            # Check if API behavior exists
            local api_behavior_exists
            api_behavior_exists=$(echo "$behaviors" | jq -r '.Items[] | select(.PathPattern == "/api/*") | .PathPattern')
            
            if [[ -n "$api_behavior_exists" ]]; then
                echo "   ✅ API cache behavior (/api/*) found"
                
                if [[ "$VERBOSE" == "true" ]]; then
                    echo "   API behavior details:"
                    echo "$behaviors" | jq -r '.Items[] | select(.PathPattern == "/api/*")'
                fi
            else
                echo "   ❌ API cache behavior (/api/*) missing"
                return 1
            fi
        else
            echo "   ❌ No cache behaviors configured"
            return 1
        fi
    else
        echo "   ❌ Failed to get cache behaviors information"
        return 1
    fi
}

# Function to check Lambda function
check_lambda_function() {
    echo "🔧 Checking Lambda function..."
    
    local lambda_domain
    lambda_domain=$(echo "$LAMBDA_FUNCTION_URL" | sed 's|https://||' | cut -d'/' -f1)
    
    echo "   Lambda domain: $lambda_domain"
    
    # Test Lambda function directly
    echo "   Testing Lambda function directly..."
    local lambda_response
    if lambda_response=$(curl -s -w "%{http_code}" "$LAMBDA_FUNCTION_URL" 2>/dev/null); then
        local http_code="${lambda_response: -3}"
        local body="${lambda_response%???}"
        
        echo "   ✅ Lambda function responded with HTTP $http_code"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "   Response body: $body"
        fi
    else
        echo "   ❌ Failed to reach Lambda function directly"
        return 1
    fi
}

# Function to test API through CloudFront
test_api_through_cloudfront() {
    if [[ "$TEST_API" != "true" ]]; then
        return 0
    fi
    
    echo "🧪 Testing API through CloudFront..."
    
    local test_urls=(
        "https://$PRIMARY_DOMAIN/api/"
        "https://$DISTRIBUTION_ID.cloudfront.net/api/"
    )
    
    for url in "${test_urls[@]}"; do
        echo "   Testing: $url"
        
        local response
        if response=$(curl -s -w "%{http_code}" "$url" 2>/dev/null); then
            local http_code="${response: -3}"
            local body="${response%???}"
            
            echo "     HTTP $http_code"
            
            if [[ "$VERBOSE" == "true" ]]; then
                echo "     Response: $body"
            fi
            
            if [[ "$http_code" =~ ^[2-3] ]]; then
                echo "     ✅ API accessible through CloudFront"
            else
                echo "     ⚠️  API returned HTTP $http_code"
            fi
        else
            echo "     ❌ Failed to reach API through CloudFront"
        fi
        echo
    done
}

# Function to check CDK deployment logs
check_cdk_logs() {
    echo "📋 Checking recent CDK deployment..."
    
    # Check if CDK outputs exist
    if [[ -f "$DATA_DIR/cdk-outputs.json" ]]; then
        echo "   ✅ CDK outputs file exists"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "   CDK outputs:"
            cat "$DATA_DIR/cdk-outputs.json" | jq '.'
        fi
    else
        echo "   ⚠️  CDK outputs file not found"
    fi
    
    # Check Lambda logs for the API behavior configuration
    echo "   Checking Lambda logs for API behavior configuration..."
    
    local log_groups
    if log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/StageEReactApi" \
        --profile "$TARGET_PROFILE" \
        --query 'logGroups[?contains(logGroupName, `ApiBehaviorLambda`)].logGroupName' \
        --output text 2>/dev/null); then
        
        if [[ -n "$log_groups" ]]; then
            local log_group
            log_group=$(echo "$log_groups" | head -n1)
            echo "   Found log group: $log_group"
            
            # Get recent log events
            local log_stream
            if log_stream=$(aws logs describe-log-streams \
                --log-group-name "$log_group" \
                --profile "$TARGET_PROFILE" \
                --order-by LastEventTime \
                --descending \
                --max-items 1 \
                --query 'logStreams[0].logStreamName' \
                --output text 2>/dev/null); then
                
                echo "   Latest log stream: $log_stream"
                
                echo "   Recent log events:"
                aws logs get-log-events \
                    --log-group-name "$log_group" \
                    --log-stream-name "$log_stream" \
                    --profile "$TARGET_PROFILE" \
                    --query 'events[-10:].message' \
                    --output text 2>/dev/null | tail -10
            fi
        else
            echo "   ⚠️  No API behavior Lambda log groups found"
        fi
    else
        echo "   ❌ Failed to check Lambda logs"
    fi
}

# Function to show troubleshooting suggestions
show_troubleshooting() {
    echo "🔧 Troubleshooting Suggestions"
    echo "=============================="
    
    echo "If API behavior is missing:"
    echo "  1. Re-run deployment: ./go-e.sh"
    echo "  2. Check Lambda logs: aws logs get-log-events --log-group-name [LOG_GROUP]"
    echo "  3. Manually update CloudFront if needed"
    echo
    
    echo "If API is not accessible:"
    echo "  1. Wait for CloudFront distribution to deploy (Status: Deployed)"
    echo "  2. Check cache invalidation completion"
    echo "  3. Test Lambda function directly first"
    echo "  4. Verify CORS configuration"
    echo
    
    echo "For verbose debugging:"
    echo "  $0 -v -t"
    echo
}

# Main execution
main() {
    check_prerequisites
    read_configuration
    
    local exit_code=0
    
    check_cloudfront_distribution || exit_code=1
    echo
    
    check_cloudfront_origins || exit_code=1
    echo
    
    check_cache_behaviors || exit_code=1
    echo
    
    check_lambda_function || exit_code=1
    echo
    
    test_api_through_cloudfront
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo
        check_cdk_logs
        echo
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        echo "❌ Issues found with API behavior configuration"
        echo
        show_troubleshooting
    else
        echo "✅ API behavior configuration looks good!"
        echo
        echo "🌐 Test your API:"
        echo "   https://$PRIMARY_DOMAIN/api/"
        echo "   https://$DISTRIBUTION_ID.cloudfront.net/api/"
    fi
    
    exit $exit_code
}

# Execute main function
main "$@" 