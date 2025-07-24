#!/bin/bash

# status-e.sh - Check Stage E React API deployment status
# This script provides a quick overview of the current deployment state

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

echo "🔍 Stage E React API Deployment Status"
echo "====================================="
echo

# Check if inputs.json exists
if [[ -f "$DATA_DIR/inputs.json" ]]; then
    echo "✅ Inputs file exists"
    distribution_id=$(jq -r '.distributionId // "not-set"' "$DATA_DIR/inputs.json")
    echo "   Distribution ID: $distribution_id"
else
    echo "❌ Inputs file missing - run gather-inputs.sh first"
fi

# Check if discovery.json exists
if [[ -f "$DATA_DIR/discovery.json" ]]; then
    echo "✅ Discovery file exists"
else
    echo "❌ Discovery file missing - run aws-discovery.sh"
fi

# Check if outputs.json exists and Stage E is complete
if [[ -f "$DATA_DIR/outputs.json" ]]; then
    echo "✅ Outputs file exists"
    
    stage_complete=$(jq -r '.stageEComplete // false' "$DATA_DIR/outputs.json")
    
    if [[ "$stage_complete" == "true" ]]; then
        echo "✅ Stage E deployment completed successfully"
        
        # Show URLs if available
        cloudfront_url=$(jq -r '.urls.cloudfront // "not-available"' "$DATA_DIR/outputs.json")
        primary_url=$(jq -r '.urls.primaryDomain // "not-available"' "$DATA_DIR/outputs.json")
        api_url=$(jq -r '.urls.lambdaApi // "not-available"' "$DATA_DIR/outputs.json")
        
        echo "   🌐 CloudFront URL: $cloudfront_url"
        echo "   🌐 Primary Domain: $primary_url"
        echo "   🔗 Lambda API URL: $api_url"
    else
        echo "❌ Stage E deployment not yet completed"
    fi
else
    echo "❌ Outputs file missing - deployment not completed"
fi

echo
echo "💡 To deploy Stage E: ./go-e.sh"
echo "💡 To validate deployment: scripts/validate-deployment.sh"
