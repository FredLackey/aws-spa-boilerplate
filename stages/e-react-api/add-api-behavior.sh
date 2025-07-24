#!/bin/bash

# add-api-behavior.sh
# Simple script to add API cache behavior to existing CloudFront distribution
# Uses AWS CLI to directly update the distribution configuration

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

echo "🔧 Adding API Cache Behavior to CloudFront Distribution"
echo "====================================================="
echo

# Function to read configuration
read_configuration() {
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    DISTRIBUTION_ID=$(jq -r '.distributionId' "$DATA_DIR/inputs.json")
    LAMBDA_FUNCTION_URL=$(jq -r '.lambdaFunctionUrl' "$DATA_DIR/inputs.json")
    TARGET_PROFILE=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    echo "📖 Configuration:"
    echo "   Distribution ID: $DISTRIBUTION_ID"
    echo "   Lambda Function URL: $LAMBDA_FUNCTION_URL"
    echo "   AWS Profile: $TARGET_PROFILE"
    echo
}

# Function to update CloudFront distribution
update_cloudfront_distribution() {
    echo "🔄 Updating CloudFront distribution with API behavior..."
    
    # Get current distribution configuration
    echo "   Getting current distribution configuration..."
    aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --profile "$TARGET_PROFILE" \
        --output json > /tmp/distribution-config.json
    
    local etag
    etag=$(jq -r '.ETag' /tmp/distribution-config.json)
    
    echo "   Current ETag: $etag"
    
    # Extract Lambda domain from URL
    local lambda_domain
    lambda_domain=$(echo "$LAMBDA_FUNCTION_URL" | sed 's|https://||' | cut -d'/' -f1)
    
    echo "   Lambda domain: $lambda_domain"
    
    # Create updated configuration with Lambda origin and API cache behavior
    jq --arg lambdaDomain "$lambda_domain" '
        .DistributionConfig |
        # Add Lambda origin if not exists
        if (.Origins.Items | map(.Id) | index("lambda-api-origin") | not) then
            .Origins.Items += [{
                "Id": "lambda-api-origin",
                "DomainName": $lambdaDomain,
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0,
                    "Items": []
                },
                "CustomOriginConfig": {
                    "HTTPPort": 443,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    },
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                },
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10,
                "OriginShield": {
                    "Enabled": false
                }
            }] |
            .Origins.Quantity = (.Origins.Items | length)
        else . end |
        # Initialize CacheBehaviors if needed
        if (.CacheBehaviors == null) then
            .CacheBehaviors = {"Quantity": 0, "Items": []}
        else . end |
        # Add API cache behavior if not exists
        if (.CacheBehaviors.Items | map(.PathPattern) | index("/api/*") | not) then
            .CacheBehaviors.Items = [{
                "PathPattern": "/api/*",
                "TargetOriginId": "lambda-api-origin",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
                "Compress": true,
                "AllowedMethods": {
                    "Quantity": 7,
                    "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["GET", "HEAD"]
                    }
                },
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0,
                    "Items": []
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0,
                    "Items": []
                },
                "LambdaFunctionAssociations": {
                    "Quantity": 0,
                    "Items": []
                },
                "FunctionAssociations": {
                    "Quantity": 0,
                    "Items": []
                },
                "FieldLevelEncryptionId": ""
            }] + .CacheBehaviors.Items |
            .CacheBehaviors.Quantity = (.CacheBehaviors.Items | length)
        else . end
    ' /tmp/distribution-config.json > /tmp/updated-distribution-config.json
    
    echo "   Updating CloudFront distribution..."
    
    # Update the distribution
    aws cloudfront update-distribution \
        --id "$DISTRIBUTION_ID" \
        --distribution-config "file:///tmp/updated-distribution-config.json" \
        --if-match "$etag" \
        --profile "$TARGET_PROFILE" \
        --output json > /tmp/update-result.json
    
    local new_etag
    new_etag=$(jq -r '.ETag' /tmp/update-result.json)
    
    echo "   ✅ Distribution updated successfully!"
    echo "   New ETag: $new_etag"
    
    # Clean up temp files
    rm -f /tmp/distribution-config.json /tmp/updated-distribution-config.json /tmp/update-result.json
    
    echo "   ⏳ Distribution update is deploying... This may take 5-15 minutes."
}

# Function to create cache invalidation
create_cache_invalidation() {
    echo "🔄 Creating cache invalidation for API paths..."
    
    local invalidation_id
    invalidation_id=$(aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/api/*" \
        --profile "$TARGET_PROFILE" \
        --query 'Invalidation.Id' \
        --output text)
    
    echo "   ✅ Cache invalidation created: $invalidation_id"
    echo "   Cache invalidation will complete in 5-15 minutes"
}

# Function to verify the update
verify_update() {
    echo "🔍 Verifying the update..."
    
    # Check origins
    local lambda_origin_count
    lambda_origin_count=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --profile "$TARGET_PROFILE" \
        --query 'Distribution.DistributionConfig.Origins.Items[?Id==`lambda-api-origin`] | length(@)' \
        --output text)
    
    if [[ "$lambda_origin_count" -gt 0 ]]; then
        echo "   ✅ Lambda origin added successfully"
    else
        echo "   ❌ Lambda origin not found"
        return 1
    fi
    
    # Check cache behaviors
    local api_behavior_count
    api_behavior_count=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --profile "$TARGET_PROFILE" \
        --query 'Distribution.DistributionConfig.CacheBehaviors.Items[?PathPattern==`/api/*`] | length(@)' \
        --output text)
    
    if [[ "$api_behavior_count" -gt 0 ]]; then
        echo "   ✅ API cache behavior added successfully"
    else
        echo "   ❌ API cache behavior not found"
        return 1
    fi
    
    echo "   ✅ Configuration verified successfully!"
}

# Main execution
main() {
    read_configuration
    update_cloudfront_distribution
    create_cache_invalidation
    verify_update
    
    echo
    echo "🎉 API behavior configuration completed!"
    echo
    echo "📋 Summary:"
    echo "   ✅ Lambda origin added to CloudFront"
    echo "   ✅ /api/* cache behavior configured"
    echo "   ✅ Cache invalidation created"
    echo
    echo "⏳ Next steps:"
    echo "   1. Wait 5-15 minutes for CloudFront deployment to complete"
    echo "   2. Wait 5-15 minutes for cache invalidation to complete"
    echo "   3. Test API endpoints: https://$(jq -r '.primaryDomain' "$DATA_DIR/inputs.json")/api/"
    echo
    echo "🧪 Test the configuration:"
    echo "   ./debug-api-behavior.sh -v -t"
}

# Execute main function
main "$@" 