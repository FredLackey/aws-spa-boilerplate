#!/bin/bash

# aws-discovery.sh
# AWS account discovery and Route53 zone validation for Stage B SSL Certificate deployment
# Validates AWS profiles, captures account IDs, and discovers Route53 hosted zones

set -euo pipefail

# Script directory and data directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

echo "=== Stage B SSL Certificate Deployment - AWS Discovery ==="
echo "This script will validate AWS profiles and discover Route53 hosted zones."
echo

# Function to validate AWS profile credentials
validate_aws_credentials() {
    local profile="$1"
    local profile_type="$2"
    
    echo "Validating $profile_type profile: $profile"
    
    # Test AWS credentials by getting caller identity
    if ! aws sts get-caller-identity --profile "$profile" --output json > /dev/null 2>&1; then
        echo "❌ Error: Cannot authenticate with AWS profile '$profile'"
        echo "Please check your AWS credentials and try again."
        return 1
    fi
    
    echo "✅ AWS profile '$profile' credentials validated"
    return 0
}

# Function to get AWS account ID
get_account_id() {
    local profile="$1"
    aws sts get-caller-identity --profile "$profile" --query 'Account' --output text
}



# Function to check Certificate Manager limits and existing certificates
check_certificate_manager_status() {
    local profile="$1"
    local domains=("${@:2}")
    
    echo "🔒 Checking AWS Certificate Manager status..."
    echo "   Using infrastructure profile: $profile"
    echo "   Region: us-east-1 (required for CloudFront certificates)"
    echo
    
    # List existing certificates
    local certificates
    certificates=$(aws acm list-certificates --profile "$profile" --region us-east-1 --output json 2>/dev/null || echo '{"CertificateSummaryList":[]}')
    
    local cert_count
    cert_count=$(echo "$certificates" | jq '.CertificateSummaryList | length' 2>/dev/null || echo "0")
    
    echo "📊 Found $cert_count existing SSL certificate(s)"
    
    # Check for existing certificates that match our domain set
    local sorted_domains
    IFS=$'\n' sorted_domains=($(sort <<<"${domains[*]}"))
    local domain_set
    domain_set=$(printf '%s,' "${sorted_domains[@]}" | sed 's/,$//')
    
    echo "🔍 Checking for existing certificates matching domain set: $domain_set"
    
    # Look for certificates that might match our domains
    local matching_certs=()
    if [[ "$cert_count" -gt 0 ]]; then
        echo "$certificates" | jq -r '.CertificateSummaryList[]? | "\(.CertificateArn)|\(.DomainName)"' | while IFS='|' read -r cert_arn domain_name; do
            [[ -z "$cert_arn" ]] && continue
            
            # Get detailed certificate info to check all domains
            local cert_details
            cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --profile "$profile" --region us-east-1 --output json 2>/dev/null || echo '{}')
            
            if [[ "$cert_details" != "{}" ]]; then
                local cert_domains
                cert_domains=$(echo "$cert_details" | jq -r '.Certificate.SubjectAlternativeNames[]?' 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//' || echo "")
                
                echo "   📋 Certificate: $domain_name"
                echo "      ARN: $cert_arn"
                echo "      Domains: $cert_domains"
                echo "      Status: $(echo "$cert_details" | jq -r '.Certificate.Status // "UNKNOWN"' 2>/dev/null)"
                
                # Check if this certificate covers exactly our domain set
                if [[ "$cert_domains" == "$domain_set" ]]; then
                    echo "      ✅ EXACT MATCH for our domain set!"
                    matching_certs+=("$cert_arn")
                fi
                echo
            fi
        done
    fi
    
    echo "✅ Certificate Manager status check completed"
    return 0
}

# Function to discover AWS account information
discover_aws_info() {
    local inputs_file="$DATA_DIR/inputs.json"
    
    # Check if inputs file exists
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    # Read inputs from JSON file
    local infra_profile target_profile domains_json
    infra_profile=$(jq -r '.infraProfile' "$inputs_file")
    target_profile=$(jq -r '.targetProfile' "$inputs_file")
    domains_json=$(jq -r '.domains[]?' "$inputs_file" 2>/dev/null | tr '\n' ' ' || echo "")
    
    # Convert domains to array
    local domains=()
    while IFS= read -r domain; do
        [[ -n "$domain" ]] && domains+=("$domain")
    done < <(jq -r '.domains[]?' "$inputs_file" 2>/dev/null)
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "❌ Error: No domains found in inputs.json"
        exit 1
    fi
    
    echo "Using inputs from: $inputs_file"
    echo "Infrastructure Profile: $infra_profile"
    echo "Target Profile: $target_profile"
    echo "Domains: ${domains[*]}"
    echo
    
    # Validate AWS profiles
    echo "🔑 Validating AWS profiles..."
    if ! validate_aws_credentials "$infra_profile" "infrastructure"; then
        exit 1
    fi
    
    if ! validate_aws_credentials "$target_profile" "target"; then
        exit 1
    fi
    echo
    
    # Get account IDs
    echo "📋 Capturing account information..."
    local infra_account_id target_account_id
    infra_account_id=$(get_account_id "$infra_profile")
    target_account_id=$(get_account_id "$target_profile")
    
    echo "✅ Infrastructure Account ID: $infra_account_id"
    echo "✅ Target Account ID: $target_account_id"
    echo
    
    # Discover Route53 hosted zones
    echo "🌐 Discovering Route53 hosted zones for ${#domains[@]} domain(s)..."
    echo "   Using infrastructure profile: $infra_profile"
    echo
    
    local zone_discoveries=()
    local missing_zones=()
    
    for domain in "${domains[@]}"; do
        echo "Discovering Route53 hosted zone for domain: $domain"
        
        # Get all hosted zones
        local zones
        zones=$(aws route53 list-hosted-zones --profile "$infra_profile" --output json 2>/dev/null || echo '{"HostedZones":[]}')
        
        # Find the best matching hosted zone for this domain
        local best_zone_id=""
        local best_zone_name=""
        local best_match_length=0
        
        # Extract zones and find best match
        while IFS='|' read -r zone_id zone_name; do
            [[ -z "$zone_id" ]] && continue
            
            # Remove trailing dot from zone name
            local clean_zone_name="${zone_name%.}"
            
            # Check if domain matches this zone (exact match or subdomain)
            if [[ "$domain" == "$clean_zone_name" ]] || [[ "$domain" == *".$clean_zone_name" ]]; then
                # This zone matches - check if it's the most specific match
                local match_length=${#clean_zone_name}
                if [[ $match_length -gt $best_match_length ]]; then
                    best_zone_id="$zone_id"
                    best_zone_name="$clean_zone_name"
                    best_match_length=$match_length
                fi
            fi
        done < <(echo "$zones" | jq -r '.HostedZones[]? | "\(.Id)|\(.Name)"')
        
        # Store results
        if [[ -n "$best_zone_id" ]]; then
            echo "✅ Found hosted zone: $best_zone_name ($best_zone_id)"
            zone_discoveries+=("$domain:$best_zone_id:$best_zone_name")
        else
            echo "❌ No hosted zone found for domain: $domain"
            missing_zones+=("$domain")
        fi
        echo
    done
    
    # Check if any zones are missing
    if [[ ${#missing_zones[@]} -gt 0 ]]; then
        echo "❌ Missing hosted zones for the following domains:"
        for domain in "${missing_zones[@]}"; do
            echo "   - $domain"
        done
        echo
        echo "💡 To fix this issue:"
        echo "   1. Create Route53 hosted zones for the missing domains in account: $infra_account_id"
        echo "   2. Or use domains that already have hosted zones in the infrastructure account"
        echo "   3. Note: This script does not create hosted zones automatically"
        exit 1
    else
        echo "✅ All domains have hosted zones available"
    fi
    echo
    
    # Check Certificate Manager status
    check_certificate_manager_status "$infra_profile" "${domains[@]}"
    echo
    
    # Create discovery JSON file
    echo "💾 Saving discovery results to discovery.json..."
    
    # Parse zone discoveries into JSON structure
    local zones_json="[]"
    if [[ ${#zone_discoveries[@]} -gt 0 ]]; then
        zones_json="["
        local first=true
        for zone_entry in "${zone_discoveries[@]}"; do
            IFS=':' read -r domain zone_id zone_name <<< "$zone_entry"
            [[ -z "$domain" ]] && continue
            if [[ "$first" == "true" ]]; then
                first=false
            else
                zones_json+=","
            fi
            zones_json+="{\"domain\":\"$domain\",\"zoneId\":\"$zone_id\",\"zoneName\":\"$zone_name\"}"
        done
        zones_json+="]"
    fi
    
    # Create the discovery JSON structure
    cat > "$DATA_DIR/discovery.json" << EOF
{
  "infraProfile": "$infra_profile",
  "targetProfile": "$target_profile",
  "infraAccountId": "$infra_account_id",
  "targetAccountId": "$target_account_id",
  "domains": $(printf '%s\n' "${domains[@]}" | jq -R . | jq -s .),
  "hostedZones": $zones_json,
  "certificateRegion": "us-east-1",
  "discoveryTimestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "validationStatus": "passed"
}
EOF
    
    echo "✅ Discovery results saved to: $DATA_DIR/discovery.json"
    echo
    
    # Display summary
    echo "📋 AWS Discovery Summary"
    echo "════════════════════════"
    echo "✅ Infrastructure Profile: $infra_profile (Account: $infra_account_id)"
    echo "✅ Target Profile: $target_profile (Account: $target_account_id)"
    echo "✅ Domains: ${#domains[@]} validated with hosted zones"
    for domain in "${domains[@]}"; do
        echo "   - $domain"
    done
    echo "✅ Certificate Region: us-east-1 (required for CloudFront)"
    echo
    
    echo "🎉 AWS discovery completed successfully!"
    echo "Ready to proceed to SSL certificate and CloudFront deployment."
}

# Main execution
main() {
    discover_aws_info
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 