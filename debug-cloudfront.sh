#!/bin/bash

set -e

DISTRIBUTION_ID="E3Q3IZJ1UV53QK"
CERT_ARN="arn:aws:acm:us-east-1:953082249352:certificate/57b989d7-e77a-41e6-8235-89191a509c62"
PROFILE="bh-fred-sandbox"
DOMAINS=("sbx.briskhaven.com" "www.sbx.briskhaven.com")

echo "🔍 Testing CloudFront update process..."
echo "   Distribution ID: $DISTRIBUTION_ID"
echo "   Certificate ARN: $CERT_ARN"
echo "   Profile: $PROFILE"
echo "   Domains: ${DOMAINS[*]}"

# Step 1: Get current config
echo "📥 Getting current distribution configuration..."
dist_config=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --profile "$PROFILE" --output json)

if [[ $? -ne 0 ]]; then
    echo "❌ Failed to get distribution config"
    exit 1
fi

echo "✅ Retrieved distribution config"

# Step 2: Extract ETag
etag=$(echo "$dist_config" | jq -r '.ETag')
echo "   ETag: $etag"

# Step 3: Create updated config
echo "🔧 Creating updated configuration..."
updated_config=$(echo "$dist_config" | jq --argjson domains "$(printf '%s\n' "${DOMAINS[@]}" | jq -R . | jq -s .)" --arg certArn "$CERT_ARN" '
    .DistributionConfig |
    .Aliases.Quantity = ($domains | length) |
    .Aliases.Items = $domains |
    .ViewerCertificate = {
        "ACMCertificateArn": $certArn,
        "CertificateSource": "acm",
        "MinimumProtocolVersion": "TLSv1.2_2021",
        "SSLSupportMethod": "sni-only"
    } |
    .DefaultCacheBehavior.ViewerProtocolPolicy = "redirect-to-https"
')

echo "✅ Created updated config"

# Step 4: Apply the update
echo "📤 Applying updated configuration..."
echo "$updated_config" | aws cloudfront update-distribution --id "$DISTRIBUTION_ID" --distribution-config file:///dev/stdin --if-match "$etag" --profile "$PROFILE" --output json

if [[ $? -eq 0 ]]; then
    echo "✅ CloudFront distribution updated successfully"
else
    echo "❌ CloudFront update failed"
    exit 1
fi 