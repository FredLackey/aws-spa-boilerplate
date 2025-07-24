#!/bin/bash
set -euo pipefail

DISTRIBUTION_ID="E3Q3IZJ1UV53QK"
PROFILE="bh-fred-sandbox"

echo "🔧 FIXING: Adding explicit Precedence to cache behavior..."

# Get current config
aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --profile "$PROFILE" > /tmp/current-config.json
ETAG=$(jq -r '.ETag' /tmp/current-config.json)

echo "Current ETag: $ETAG"

# Add Precedence: 0 to the cache behavior (highest priority)
jq '.DistributionConfig.CacheBehaviors.Items[0].Precedence = 0' /tmp/current-config.json > /tmp/fixed-config.json

echo "Updating distribution with explicit Precedence: 0..."
aws cloudfront update-distribution \
    --id "$DISTRIBUTION_ID" \
    --distribution-config "file:///tmp/fixed-config.json" \
    --if-match "$ETAG" \
    --profile "$PROFILE" > /tmp/update-result.json

NEW_ETAG=$(jq -r '.ETag' /tmp/update-result.json)
echo "✅ Distribution updated with Precedence. New ETag: $NEW_ETAG"

# Verify the fix
echo "🔍 Verifying Precedence was set:"
aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --profile "$PROFILE" --query 'Distribution.DistributionConfig.CacheBehaviors.Items[0].{PathPattern:PathPattern,TargetOriginId:TargetOriginId,Precedence:Precedence}' --output json

echo "✅ Cache behavior now has explicit precedence!"
rm -f /tmp/current-config.json /tmp/fixed-config.json /tmp/update-result.json
