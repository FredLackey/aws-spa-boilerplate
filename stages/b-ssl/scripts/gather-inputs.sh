#!/bin/bash

# gather-inputs.sh - Collect domain inputs for Stage B SSL Certificate deployment
# This script gathers domain names via command line arguments, validates Stage A completion,
# and saves configuration to inputs.json for use by other scripts.

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"
STAGE_A_DIR="$STAGE_DIR/../a-cloudfront"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Arrays to store domains
DOMAINS=()

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 -d DOMAIN [-d DOMAIN2] [-d DOMAIN3] ...

Required Options:
  -d DOMAIN                 Fully qualified domain name (FQDN) for SSL certificate
                           Can be specified multiple times for multi-domain certificates

Examples:
  $0 -d www.sbx.briskhaven.com -d sbx.briskhaven.com
  $0 -d api.example.com
  $0 -d www.mysite.com -d mysite.com -d api.mysite.com

Notes:
  - At least one domain is required
  - All domains will be covered by a single SSL certificate
  - Domains must have existing Route53 hosted zones in the infrastructure account
  - Stage A must be completed successfully before running Stage B

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Error: -d option requires a domain name"
                show_usage
                exit 1
            fi
            DOMAINS+=("$2")
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate at least one domain is provided
if [[ ${#DOMAINS[@]} -eq 0 ]]; then
    echo "❌ Error: At least one domain must be provided using -d option."
    echo
    show_usage
    exit 1
fi

echo "=== Stage B SSL Certificate Deployment - Input Validation ==="
echo "Validating provided domain configuration and Stage A prerequisites..."
echo

# Function to validate FQDN format
validate_fqdn() {
    local domain="$1"
    
    # Basic FQDN validation regex
    # Must contain at least one dot, no spaces, valid characters only
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    
    # Must contain at least one dot (not just a single word)
    if [[ ! "$domain" =~ \. ]]; then
        return 1
    fi
    
    # Must not start or end with dot or hyphen
    if [[ "$domain" =~ ^[\.\-] ]] || [[ "$domain" =~ [\.\-]$ ]]; then
        return 1
    fi
    
    # Must not contain consecutive dots
    if [[ "$domain" =~ \.\. ]]; then
        return 1
    fi
    
    return 0
}

# Function to load and validate Stage A outputs
load_stage_a_outputs() {
    local stage_a_outputs="$STAGE_A_DIR/data/outputs.json"
    
    echo "📋 Loading Stage A outputs..."
    echo "   Checking: $stage_a_outputs"
    
    if [[ ! -f "$stage_a_outputs" ]]; then
        echo "❌ Error: Stage A outputs not found at: $stage_a_outputs"
        echo "   Please complete Stage A deployment before running Stage B"
        return 1
    fi
    
    # Validate Stage A completion status
    local ready_for_stage_b
    ready_for_stage_b=$(jq -r '.readyForStageB // false' "$stage_a_outputs" 2>/dev/null || echo "false")
    
    if [[ "$ready_for_stage_b" != "true" ]]; then
        echo "❌ Error: Stage A is not ready for Stage B"
        echo "   Stage A outputs indicate: readyForStageB = $ready_for_stage_b"
        echo "   Please ensure Stage A completed successfully"
        return 1
    fi
    
    # Extract Stage A configuration (try both nested and root level)
    INFRA_PROFILE=$(jq -r '.stageA.infrastructureProfile // .infrastructureProfile // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    TARGET_PROFILE=$(jq -r '.stageA.targetProfile // .targetProfile // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    DISTRIBUTION_ID=$(jq -r '.distributionId // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    DISTRIBUTION_URL=$(jq -r '.distributionUrl // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    BUCKET_NAME=$(jq -r '.bucketName // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    TARGET_REGION=$(jq -r '.targetRegion // empty' "$stage_a_outputs" 2>/dev/null || echo "")
    
    if [[ -z "$INFRA_PROFILE" ]] || [[ -z "$TARGET_PROFILE" ]] || [[ -z "$DISTRIBUTION_ID" ]]; then
        echo "❌ Error: Stage A outputs are incomplete"
        echo "   Missing required fields: infrastructureProfile, targetProfile, or distributionId"
        return 1
    fi
    
    echo "✅ Stage A outputs loaded successfully:"
    echo "   Infrastructure Profile: $INFRA_PROFILE"
    echo "   Target Profile: $TARGET_PROFILE"
    echo "   Distribution ID: $DISTRIBUTION_ID"
    echo "   Distribution URL: $DISTRIBUTION_URL"
    echo "   Ready for Stage B: $ready_for_stage_b"
    
    return 0
}

# Function to validate AWS profile exists and has valid credentials
validate_aws_profile() {
    local profile="$1"
    echo "Validating AWS profile: $profile"
    
    # Check if profile exists in AWS config
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo "❌ Error: AWS profile '$profile' not found"
        echo "Available profiles:"
        aws configure list-profiles | sed 's/^/  - /'
        return 1
    fi
    
    echo "✅ Profile '$profile' found in AWS configuration"
    return 0
}

# Function to validate AWS profile credentials and handle SSO login
validate_aws_profile_credentials() {
    local profile="$1"
    local profile_type="$2"
    
    echo "Validating $profile_type profile credentials: $profile"
    
    # Try to get account ID to test credentials
    local account_id
    account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ Profile '$profile' credentials are valid (Account: $account_id)"
        return 0
    fi
    
    # Check if the error is related to SSO
    if echo "$account_id" | grep -q -i "sso\|token.*expired\|session.*expired\|credentials.*expired"; then
        echo "🔑 SSO token appears to be expired for profile '$profile'"
        echo "Attempting to refresh SSO login..."
        
        # Attempt SSO login
        if aws sso login --profile "$profile"; then
            echo "✅ SSO login successful, re-validating credentials..."
            
            # Re-test credentials
            account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>&1)
            exit_code=$?
            
            if [[ $exit_code -eq 0 ]]; then
                echo "✅ Profile '$profile' credentials are now valid (Account: $account_id)"
                return 0
            else
                echo "❌ Credentials still invalid after SSO login: $account_id"
                return 1
            fi
        else
            echo "❌ SSO login failed for profile '$profile'"
            echo "Please run 'aws sso login --profile $profile' manually and try again"
            return 1
        fi
    else
        echo "❌ Profile '$profile' credentials are invalid: $account_id"
        echo "This doesn't appear to be an SSO issue. Please check your AWS configuration."
        return 1
    fi
}

# Function to sort domains alphabetically for consistent processing
sort_domains() {
    local sorted_domains
    IFS=$'\n' sorted_domains=($(sort <<<"${DOMAINS[*]}"))
    DOMAINS=("${sorted_domains[@]}")
    
    echo "📝 Domains sorted alphabetically for consistent processing:"
    for domain in "${DOMAINS[@]}"; do
        echo "   - $domain"
    done
}

# Main validation and processing
echo "🔍 Validating ${#DOMAINS[@]} domain(s):"
for domain in "${DOMAINS[@]}"; do
    echo "   - $domain"
done
echo

# Validate each domain format
echo "📋 Validating FQDN format for each domain..."
for domain in "${DOMAINS[@]}"; do
    echo "Checking domain: $domain"
    if validate_fqdn "$domain"; then
        echo "✅ Valid FQDN format: $domain"
    else
        echo "❌ Invalid FQDN format: $domain"
        echo "   Domain names must be fully qualified (e.g., www.example.com, api.mysite.com)"
        echo "   They cannot contain spaces, special characters, or be single words"
        exit 1
    fi
done
echo

# Sort domains alphabetically
sort_domains
echo

# Load and validate Stage A outputs
if ! load_stage_a_outputs; then
    exit 1
fi
echo

# Validate AWS profiles from Stage A
echo "🔑 Validating AWS profiles from Stage A..."

# Validate infrastructure profile
if ! validate_aws_profile "$INFRA_PROFILE"; then
    exit 1
fi

if ! validate_aws_profile_credentials "$INFRA_PROFILE" "infrastructure"; then
    exit 1
fi

# Validate target profile
if ! validate_aws_profile "$TARGET_PROFILE"; then
    exit 1
fi

if ! validate_aws_profile_credentials "$TARGET_PROFILE" "target"; then
    exit 1
fi

echo

# Get account IDs for both profiles
echo "📋 Capturing account information..."
INFRA_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$INFRA_PROFILE" --query 'Account' --output text)
TARGET_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$TARGET_PROFILE" --query 'Account' --output text)

echo "✅ Infrastructure Account ID: $INFRA_ACCOUNT_ID"
echo "✅ Target Account ID: $TARGET_ACCOUNT_ID"
echo

# Create inputs JSON file
echo "💾 Saving configuration to inputs.json..."

# Create the JSON structure
cat > "$DATA_DIR/inputs.json" << EOF
{
  "domains": $(printf '%s\n' "${DOMAINS[@]}" | jq -R . | jq -s .),
  "infraProfile": "$INFRA_PROFILE",
  "targetProfile": "$TARGET_PROFILE",
  "infraAccountId": "$INFRA_ACCOUNT_ID",
  "targetAccountId": "$TARGET_ACCOUNT_ID",
  "distributionId": "$DISTRIBUTION_ID",
  "distributionUrl": "$DISTRIBUTION_URL",
  "bucketName": "$BUCKET_NAME",
  "targetRegion": "$TARGET_REGION",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "stageAReady": true
}
EOF

echo "✅ Configuration saved to: $DATA_DIR/inputs.json"
echo

# Display summary
echo "📋 Input Collection Summary"
echo "═══════════════════════════"
echo "✅ Domains to configure: ${#DOMAINS[@]}"
for domain in "${DOMAINS[@]}"; do
    echo "   - $domain"
done
echo "✅ Infrastructure Profile: $INFRA_PROFILE (Account: $INFRA_ACCOUNT_ID)"
echo "✅ Target Profile: $TARGET_PROFILE (Account: $TARGET_ACCOUNT_ID)"
echo "✅ CloudFront Distribution: $DISTRIBUTION_ID"
echo "✅ Stage A Prerequisites: Met"
echo

echo "🎉 Input collection completed successfully!"
echo "Ready to proceed to Stage B SSL certificate deployment." 