#!/bin/bash
set -euo pipefail

DISTRIBUTION_ID="E3Q3IZJ1UV53QK"
PROFILE="bh-fred-sandbox"

echo "🔧 Adding cache behavior for exact /api path (without trailing slash)..."

# Get current config
aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --profile "$PROFILE" > /tmp/current-config.json
ETAG=$(jq -r '.ETag' /tmp/current-config.json)

# Add a second cache behavior for exact "/api" path
jq '.DistributionConfig |
# Add exact /api behavior at the beginning (highest precedence)
.CacheBehaviors.Items = [{
    "PathPattern": "/api",
    "TargetOriginId": "lambda-api-origin", 
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
    "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
    "Compress": true,
    "SmoothStreaming": false,
    "AllowedMethods": {
        "Quantity": 7,
        "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
        "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
    },
    "TrustedSigners": {"Enabled": false, "Quantity": 0, "Items": []},
    "TrustedKeyGroups": {"Enabled": false, "Quantity": 0, "Items": []},
    "LambdaFunctionAssociations": {"Quantity": 0, "Items": []},
    "FunctionAssociations": {"Quantity": 0, "Items": []},
    "FieldLevelEncryptionId": ""
}] + .CacheBehaviors.Items |
.CacheBehaviors.Quantity = (.CacheBehaviors.Items | length)
' /tmp/current-config.json > /tmp/fixed-config.json

echo "Updating distribution..."
aws cloudfront update-distribution \
    --id "$DISTRIBUTION_ID" \
    --distribution-config "file:///tmp/fixed-config.json" \
    --if-match "$ETAG" \
    --profile "$PROFILE" > /tmp/update-result.json

NEW_ETAG=$(jq -r '.ETag' /tmp/update-result.json)
echo "✅ Distribution updated. New ETag: $NEW_ETAG"

# Create invalidation
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths "/api" "/api/*" \
    --profile "$PROFILE" \
    --query 'Invalidation.Id' --output text)

echo "✅ Cache invalidation created: $INVALIDATION_ID"

# Verify both behaviors exist
echo "🔍 Verifying cache behaviors:"
aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --profile "$PROFILE" --query 'Distribution.DistributionConfig.CacheBehaviors.Items[*].{PathPattern:PathPattern,TargetOriginId:TargetOriginId}' --output table

rm -f /tmp/current-config.json /tmp/fixed-config.json /tmp/update-result.json
