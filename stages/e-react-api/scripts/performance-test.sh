#!/bin/bash

# performance-test.sh
# Performance and timing validation for Stage D React deployment
# Provides detailed metrics for React application performance through CloudFront

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

echo "=== Stage D React Deployment - Performance Testing ==="
echo "This script will measure performance metrics for the React application deployment."
echo

# Function to validate prerequisites
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    local inputs_file="$DATA_DIR/inputs.json"
    local outputs_file="$DATA_DIR/outputs.json"
    
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    if [[ ! -f "$outputs_file" ]]; then
        echo "❌ Error: outputs.json not found. Please run deploy-infrastructure.sh first."
        exit 1
    fi
    
    # Check if curl is available for testing
    if ! command -v curl > /dev/null 2>&1; then
        echo "❌ Error: curl command not found. Please install curl for performance testing."
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
}

# Function to load configuration
load_configuration() {
    echo "Loading deployment configuration..."
    
    local inputs_file="$DATA_DIR/inputs.json"
    local outputs_file="$DATA_DIR/outputs.json"
    
    # Load from inputs.json
    TARGET_PROFILE=$(jq -r '.targetProfile' "$inputs_file")
    DISTRIBUTION_ID=$(jq -r '.distributionId' "$inputs_file")
    PRIMARY_DOMAIN=$(jq -r '.primaryDomain' "$inputs_file")
    
    # Load from outputs.json
    DISTRIBUTION_URL=$(jq -r '.urls.cloudfront' "$outputs_file")
    PRIMARY_DOMAIN_URL=$(jq -r '.urls.primaryDomain' "$outputs_file")
    
    echo "Configuration loaded:"
    echo "   Distribution URL: $DISTRIBUTION_URL"
    echo "   Primary Domain URL: $PRIMARY_DOMAIN_URL"
    echo
}

# Function to perform detailed timing tests
perform_timing_tests() {
    local test_url="$1"
    local test_name="$2"
    local iterations="${3:-5}"
    
    echo "⏱️  Performing timing tests for $test_name..."
    echo "   URL: $test_url"
    echo "   Iterations: $iterations"
    
    local total_time=0
    local total_response_time=0
    local total_connect_time=0
    local total_download_time=0
    local successful_tests=0
    
    for ((i=1; i<=iterations; i++)); do
        echo "   Test $i/$iterations..."
        
        # Perform detailed timing measurement
        local timing_data
        timing_data=$(curl -s -o /dev/null -w "%{time_total},%{time_starttransfer},%{time_connect},%{time_pretransfer},%{time_namelookup},%{http_code},%{size_download}" --max-time 30 "$test_url" 2>/dev/null || echo "0,0,0,0,0,000,0")
        
        IFS=',' read -r time_total time_response time_connect time_pretransfer time_namelookup http_code size_download <<< "$timing_data"
        
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            total_time=$(echo "$total_time + $time_total" | bc -l 2>/dev/null || echo "$total_time")
            total_response_time=$(echo "$total_response_time + $time_response" | bc -l 2>/dev/null || echo "$total_response_time")
            total_connect_time=$(echo "$total_connect_time + $time_connect" | bc -l 2>/dev/null || echo "$total_connect_time")
            successful_tests=$((successful_tests + 1))
            
            echo "     ✅ Success: ${time_total}s total, ${time_response}s response, ${size_download} bytes"
        else
            echo "     ❌ Failed: HTTP $http_code"
        fi
        
        # Brief pause between tests
        sleep 1
    done
    
    if [[ "$successful_tests" -gt 0 ]]; then
        # Calculate averages using bc if available, otherwise use basic arithmetic
        local avg_total avg_response avg_connect
        if command -v bc > /dev/null 2>&1; then
            avg_total=$(echo "scale=3; $total_time / $successful_tests" | bc -l)
            avg_response=$(echo "scale=3; $total_response_time / $successful_tests" | bc -l)
            avg_connect=$(echo "scale=3; $total_connect_time / $successful_tests" | bc -l)
        else
            # Fallback to basic arithmetic (less precise)
            avg_total=$(echo "$total_time $successful_tests" | awk '{printf "%.3f", $1/$2}')
            avg_response=$(echo "$total_response_time $successful_tests" | awk '{printf "%.3f", $1/$2}')
            avg_connect=$(echo "$total_connect_time $successful_tests" | awk '{printf "%.3f", $1/$2}')
        fi
        
        echo "   📊 Performance Summary ($successful_tests/$iterations successful):"
        echo "      Average Total Time: ${avg_total}s"
        echo "      Average Response Time: ${avg_response}s"
        echo "      Average Connect Time: ${avg_connect}s"
        
        # Store results for final report
        echo "$test_name,$avg_total,$avg_response,$avg_connect,$successful_tests,$iterations" >> "$DATA_DIR/.performance_results"
        
        return 0
    else
        echo "   ❌ All timing tests failed for $test_name"
        return 1
    fi
}

# Function to test asset loading performance
test_asset_performance() {
    echo "📦 Testing React asset loading performance..."
    
    # Get index.html content to extract asset references
    local index_content
    index_content=$(curl -s --max-time 30 "$DISTRIBUTION_URL" || echo "")
    
    if [[ -z "$index_content" ]]; then
        echo "❌ Could not retrieve index.html content"
        return 1
    fi
    
    # Extract CSS and JS file references
    local css_files js_files
    css_files=$(echo "$index_content" | grep -oE 'href="[^"]*\.css[^"]*"' | sed 's/href="//g' | sed 's/"//g' | head -3 || echo "")
    js_files=$(echo "$index_content" | grep -oE 'src="[^"]*\.js[^"]*"' | sed 's/src="//g' | sed 's/"//g' | head -3 || echo "")
    
    local asset_performance_passed=0
    local asset_performance_total=0
    
    # Test CSS file performance
    if [[ -n "$css_files" ]]; then
        echo "   Testing CSS asset performance..."
        while IFS= read -r css_file; do
            if [[ -n "$css_file" ]]; then
                asset_performance_total=$((asset_performance_total + 1))
                local css_url
                if [[ "$css_file" =~ ^https?:// ]]; then
                    css_url="$css_file"
                else
                    css_url="$DISTRIBUTION_URL/${css_file#/}"
                fi
                
                echo "   Testing CSS: ${css_file##*/}"
                if perform_timing_tests "$css_url" "CSS-${css_file##*/}" 3; then
                    asset_performance_passed=$((asset_performance_passed + 1))
                fi
                echo
            fi
        done <<< "$css_files"
    fi
    
    # Test JS file performance
    if [[ -n "$js_files" ]]; then
        echo "   Testing JavaScript asset performance..."
        while IFS= read -r js_file; do
            if [[ -n "$js_file" ]]; then
                asset_performance_total=$((asset_performance_total + 1))
                local js_url
                if [[ "$js_file" =~ ^https?:// ]]; then
                    js_url="$js_file"
                else
                    js_url="$DISTRIBUTION_URL/${js_file#/}"
                fi
                
                echo "   Testing JS: ${js_file##*/}"
                if perform_timing_tests "$js_url" "JS-${js_file##*/}" 3; then
                    asset_performance_passed=$((asset_performance_passed + 1))
                fi
                echo
            fi
        done <<< "$js_files"
    fi
    
    echo "📊 Asset performance summary: $asset_performance_passed/$asset_performance_total assets tested successfully"
    
    if [[ "$asset_performance_total" -eq 0 ]]; then
        echo "   ⚠️  No assets found to test"
        return 0
    elif [[ "$asset_performance_passed" -eq "$asset_performance_total" ]]; then
        echo "✅ Asset performance testing passed"
        return 0
    else
        echo "❌ Some asset performance tests failed"
        return 1
    fi
}

# Function to test global CDN performance
test_global_performance() {
    echo "🌍 Testing global CDN performance..."
    
    # Test from different CloudFront edge locations by using different test patterns
    local test_patterns=(
        "/?cache-buster=$(date +%s)"
        "/assets/?test=performance"
        "/?performance-test=true"
    )
    
    echo "   Testing different request patterns to evaluate CDN performance..."
    
    for pattern in "${test_patterns[@]}"; do
        local test_url="${DISTRIBUTION_URL}${pattern}"
        echo "   🔗 Testing pattern: $pattern"
        
        # Shorter test for patterns
        if perform_timing_tests "$test_url" "Pattern-${pattern//[\/\?\=\-\(\)]/_}" 3; then
            echo "   ✅ Pattern test successful"
        else
            echo "   ⚠️  Pattern test had issues"
        fi
        echo
    done
    
    echo "✅ Global CDN performance testing completed"
}

# Function to generate performance report
generate_performance_report() {
    local performance_file="$DATA_DIR/performance-results.json"
    
    echo "📊 Generating comprehensive performance report..."
    
    # Check if we have performance results
    if [[ ! -f "$DATA_DIR/.performance_results" ]]; then
        echo "⚠️  No performance results found"
        return 0
    fi
    
    # Read performance results and generate JSON report
    local performance_data=""
    local test_count=0
    
    while IFS=',' read -r test_name avg_total avg_response avg_connect successful iterations; do
        if [[ -n "$test_name" ]]; then
            test_count=$((test_count + 1))
            performance_data="$performance_data
    {
      \"testName\": \"$test_name\",
      \"averageTotalTime\": $avg_total,
      \"averageResponseTime\": $avg_response,
      \"averageConnectTime\": $avg_connect,
      \"successfulTests\": $successful,
      \"totalIterations\": $iterations,
      \"successRate\": $(echo "$successful $iterations" | awk '{printf "%.2f", ($1/$2)*100}')
    },"
        fi
    done < "$DATA_DIR/.performance_results"
    
    # Remove trailing comma
    performance_data="${performance_data%,}"
    
    # Create comprehensive performance report
    cat > "$performance_file" << EOF
{
  "performanceTestTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "testSuite": "Stage D React Performance Testing",
  "version": "1.0",
  "configuration": {
    "distributionUrl": "$DISTRIBUTION_URL",
    "primaryDomainUrl": "$PRIMARY_DOMAIN_URL",
    "distributionId": "$DISTRIBUTION_ID"
  },
  "performanceResults": [$performance_data
  ],
  "summary": {
    "totalTests": $test_count,
    "testTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "testEnvironment": "CloudFront CDN",
    "testMethod": "curl with timing metrics"
  },
  "recommendations": {
    "caching": "Assets served through CloudFront with appropriate cache headers",
    "compression": "Verify gzip/brotli compression is enabled",
    "optimization": "Monitor CloudFront cache hit ratios",
    "monitoring": "Set up CloudWatch alarms for response times"
  }
}
EOF
    
    echo "✅ Performance report saved to: $performance_file"
    
    # Clean up temporary results file
    rm -f "$DATA_DIR/.performance_results"
}

# Main performance testing execution
main() {
    echo "Starting comprehensive React application performance testing..."
    echo
    
    # Initialize performance results file
    rm -f "$DATA_DIR/.performance_results"
    
    # Validate prerequisites
    validate_prerequisites
    echo
    
    # Load configuration
    load_configuration
    
    # Test main application performance
    echo "🚀 Testing main application performance..."
    perform_timing_tests "$DISTRIBUTION_URL" "CloudFront-Index" 5
    echo
    
    perform_timing_tests "$PRIMARY_DOMAIN_URL" "Primary-Domain-Index" 5
    echo
    
    # Test asset performance
    test_asset_performance
    echo
    
    # Test global CDN performance
    test_global_performance
    echo
    
    # Generate performance report
    generate_performance_report
    echo
    
    echo "🎉 Performance testing completed successfully!"
    echo
    echo "📋 Performance Testing Summary:"
    echo "   ✅ Main application timing tests completed"
    echo "   ✅ Asset loading performance measured"
    echo "   ✅ Global CDN performance evaluated"
    echo "   ✅ Comprehensive performance report generated"
    echo
    echo "📁 Performance results available in:"
    echo "   - $DATA_DIR/performance-results.json"
    echo
    echo "🔧 Next steps:"
    echo "   1. Review performance metrics for optimization opportunities"
    echo "   2. Monitor CloudFront cache hit ratios"
    echo "   3. Consider implementing performance monitoring"
    echo
}

# Execute main function
main 