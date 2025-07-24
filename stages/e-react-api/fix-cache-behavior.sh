#!/bin/bash
set -euo pipefail

DISTRIBUTION_ID="E3Q3IZJ1UV53QK"
PROFILE="yourawsprofile-sandbox"
LAMBDA_URL="https://ljol5hyg76f3amvxxzdjfta5vi0cpqjv.lambda-url.us-east-1.on.aws/"

echo "🔧 Fixing CloudFront cache behavior..."

# Get current config
aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --profile "$PROFILE" > /tmp/current-config.json
ETAG=$(jq -r '.ETag' /tmp/current-config.json)

# Remove existing cache behavior and re-add it with explicit precedence
jq --arg lambdaDomain "$(echo "$LAMBDA_URL" | sed 's|https://||' | cut -d'/' -f1)" '
.DistributionConfig |
# Ensure cache behaviors array exists
if (.CacheBehaviors == null) then .CacheBehaviors = {"Quantity": 0, "Items": []} else . end |
# Remove any existing /api/* behavior
.CacheBehaviors.Items = (.CacheBehaviors.Items | map(select(.PathPattern != "/api/*"))) |
# Add the new behavior at the beginning (highest precedence)
.CacheBehaviors.Items = [{
    "PathPattern": "/api/*",
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
    --paths "/api/*" "/*" \
    --profile "$PROFILE" \
    --query 'Invalidation.Id' --output text)

echo "✅ Cache invalidation created: $INVALIDATION_ID"
echo "⏳ Wait 5-10 minutes then test: https://sbx.yourdomain.com/api/"

rm -f /tmp/current-config.json /tmp/fixed-config.json /tmp/update-result.json
