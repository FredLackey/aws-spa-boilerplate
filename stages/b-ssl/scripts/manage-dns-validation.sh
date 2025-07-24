#!/bin/bash

# manage-dns-validation.sh
# Manages DNS validation records for SSL certificates in the infrastructure account's Route53
# Per architecture: DNS validation records are added to centralized Route53 in infrastructure account

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 <action> [options]

Actions:
  add       Add DNS validation records to infrastructure account Route53
  remove    Remove DNS validation records from infrastructure account Route53
  status    Check status of DNS validation records

Options:
  -h, --help    Show this help message

Notes:
  - This script manages DNS validation records in the infrastructure account
  - Certificate ARN is read from CDK outputs
  - Requires valid AWS credentials for both infrastructure and target accounts

EOF
}

# Function to get certificate validation records
get_certificate_validation_records() {
    local cert_arn="$1"
    local target_profile="$2"
    
    echo "🔍 Getting DNS validation records for certificate..." >&2
    echo "   Certificate ARN: $cert_arn" >&2
    
    # Get certificate details from target account (where certificate was created)
    local cert_details
    cert_details=$(aws acm describe-certificate \
        --certificate-arn "$cert_arn" \
        --profile "$target_profile" \
        --region us-east-1 \
        --output json 2>/dev/null)
    
    if [[ -z "$cert_details" || "$cert_details" == "null" ]]; then
        echo "❌ Failed to get certificate details" >&2
        return 1
    fi
    
    # Extract DNS validation records
    local validation_records
    validation_records=$(echo "$cert_details" | jq -r '.Certificate.DomainValidationOptions[]? | select(.ValidationMethod == "DNS") | {domain: .DomainName, name: .ResourceRecord.Name, value: .ResourceRecord.Value, type: .ResourceRecord.Type}')
    
    if [[ -z "$validation_records" ]]; then
        echo "⚠️  No DNS validation records found or certificate may already be validated" >&2
        return 1
    fi
    
    echo "$validation_records"
}

# Function to add DNS validation records to infrastructure account Route53
add_dns_validation_records() {
    local infra_profile="$1"
    local target_profile="$2"
    local cert_arn="$3"
    
    echo "➕ Adding DNS validation records to infrastructure account Route53..."
    
    # Get validation records
    local validation_records
    validation_records=$(get_certificate_validation_records "$cert_arn" "$target_profile")
    
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to get validation records"
        return 1
    fi
    
    # Get hosted zone from discovery data
    local hosted_zone_id
    if [[ -f "$DATA_DIR/discovery.json" ]]; then
        hosted_zone_id=$(jq -r '.hostedZones[0].zoneId' "$DATA_DIR/discovery.json" | sed 's|/hostedzone/||')
    else
        echo "❌ Discovery data not found. Run aws-discovery.sh first."
        return 1
    fi
    
    echo "   Using hosted zone: $hosted_zone_id"
    
    # Process each validation record
    local records_added=0
    while IFS= read -r record; do
        [[ -z "$record" ]] && continue
        
        local domain name value type
        domain=$(echo "$record" | jq -r '.domain')
        name=$(echo "$record" | jq -r '.name')
        value=$(echo "$record" | jq -r '.value')
        type=$(echo "$record" | jq -r '.type')
        
        echo "   📝 Adding validation record for domain: $domain"
        echo "      Name: $name"
        echo "      Value: $value"
        echo "      Type: $type"
        
        # Create Route53 change batch
        local change_batch
        change_batch=$(cat << EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "$name",
            "Type": "$type",
            "TTL": 300,
            "ResourceRecords": [{"Value": "\"$value\""}]
        }
    }]
}
EOF
)
        
        # Apply the change
        local change_id
        change_id=$(aws route53 change-resource-record-sets \
            --hosted-zone-id "$hosted_zone_id" \
            --change-batch "$change_batch" \
            --profile "$infra_profile" \
            --query 'ChangeInfo.Id' \
            --output text 2>/dev/null)
        
        if [[ -n "$change_id" ]]; then
            echo "      ✅ Record added (Change ID: $change_id)"
            ((records_added++))
        else
            echo "      ❌ Failed to add record"
        fi
        
    done <<< "$validation_records"
    
    if [[ $records_added -gt 0 ]]; then
        echo "✅ Added $records_added DNS validation records to infrastructure account Route53"
        echo "   🕐 DNS propagation may take a few minutes..."
        return 0
    else
        echo "❌ No validation records were added"
        return 1
    fi
}

# Function to remove DNS validation records
remove_dns_validation_records() {
    local infra_profile="$1"
    local target_profile="$2"
    local cert_arn="$3"
    
    echo "➖ Removing DNS validation records from infrastructure account Route53..."
    
    # Get validation records
    local validation_records
    validation_records=$(get_certificate_validation_records "$cert_arn" "$target_profile")
    
    if [[ $? -ne 0 ]]; then
        echo "⚠️  Could not get validation records - they may already be removed"
        return 0
    fi
    
    # Get hosted zone from discovery data
    local hosted_zone_id
    if [[ -f "$DATA_DIR/discovery.json" ]]; then
        hosted_zone_id=$(jq -r '.hostedZones[0].zoneId' "$DATA_DIR/discovery.json" | sed 's|/hostedzone/||')
    else
        echo "❌ Discovery data not found. Cannot determine hosted zone."
        return 1
    fi
    
    echo "   Using hosted zone: $hosted_zone_id"
    
    # Process each validation record
    local records_removed=0
    while IFS= read -r record; do
        [[ -z "$record" ]] && continue
        
        local domain name value type
        domain=$(echo "$record" | jq -r '.domain')
        name=$(echo "$record" | jq -r '.name')
        value=$(echo "$record" | jq -r '.value')
        type=$(echo "$record" | jq -r '.type')
        
        echo "   🗑️  Removing validation record for domain: $domain"
        echo "      Name: $name"
        
        # Create Route53 change batch for deletion
        local change_batch
        change_batch=$(cat << EOF
{
    "Changes": [{
        "Action": "DELETE",
        "ResourceRecordSet": {
            "Name": "$name",
            "Type": "$type",
            "TTL": 300,
            "ResourceRecords": [{"Value": "\"$value\""}]
        }
    }]
}
EOF
)
        
        # Apply the change
        local change_id
        change_id=$(aws route53 change-resource-record-sets \
            --hosted-zone-id "$hosted_zone_id" \
            --change-batch "$change_batch" \
            --profile "$infra_profile" \
            --query 'ChangeInfo.Id' \
            --output text 2>/dev/null)
        
        if [[ -n "$change_id" ]]; then
            echo "      ✅ Record removed (Change ID: $change_id)"
            ((records_removed++))
        else
            echo "      ⚠️  Record may not exist or already removed"
        fi
        
    done <<< "$validation_records"
    
    echo "✅ Removed $records_removed DNS validation records from infrastructure account Route53"
    return 0
}

# Function to check DNS validation status
check_dns_validation_status() {
    local target_profile="$1"
    local cert_arn="$2"
    
    echo "🔍 Checking DNS validation status..."
    echo "   Certificate ARN: $cert_arn"
    
    # Get certificate status
    local cert_status
    cert_status=$(aws acm describe-certificate \
        --certificate-arn "$cert_arn" \
        --profile "$target_profile" \
        --region us-east-1 \
        --query 'Certificate.Status' \
        --output text 2>/dev/null)
    
    echo "   Certificate Status: $cert_status"
    
    # Get domain validation status
    local domain_validation
    domain_validation=$(aws acm describe-certificate \
        --certificate-arn "$cert_arn" \
        --profile "$target_profile" \
        --region us-east-1 \
        --query 'Certificate.DomainValidationOptions[*].{Domain:DomainName,Status:ValidationStatus}' \
        --output table 2>/dev/null)
    
    echo "   Domain Validation Status:"
    echo "$domain_validation"
    
    if [[ "$cert_status" == "ISSUED" ]]; then
        echo "✅ Certificate is fully validated and issued"
        return 0
    elif [[ "$cert_status" == "PENDING_VALIDATION" ]]; then
        echo "⏳ Certificate is pending validation"
        return 1
    else
        echo "❌ Certificate status: $cert_status"
        return 1
    fi
}

# Main script logic
main() {
    local action="${1:-}"
    
    if [[ -z "$action" ]]; then
        echo "❌ Error: Action is required"
        show_usage
        exit 1
    fi
    
    case "$action" in
        -h|--help)
            show_usage
            exit 0
            ;;
        add|remove|status)
            ;;
        *)
            echo "❌ Error: Unknown action '$action'"
            show_usage
            exit 1
            ;;
    esac
    
    # Validate required files exist
    if [[ ! -f "$DATA_DIR/inputs.json" ]]; then
        echo "❌ Error: inputs.json not found. Run gather-inputs.sh first."
        exit 1
    fi
    
    if [[ ! -f "$DATA_DIR/discovery.json" ]]; then
        echo "❌ Error: discovery.json not found. Run aws-discovery.sh first."
        exit 1
    fi
    
    # Get configuration from data files
    local infra_profile target_profile cert_arn
    infra_profile=$(jq -r '.infraProfile' "$DATA_DIR/inputs.json")
    target_profile=$(jq -r '.targetProfile' "$DATA_DIR/inputs.json")
    
    # Get certificate ARN from CDK outputs
    if [[ -f "$DATA_DIR/cdk-outputs.json" ]]; then
        cert_arn=$(jq -r '.StageBSslCertificateStack.CertificateArnOutput // empty' "$DATA_DIR/cdk-outputs.json")
    fi
    
    if [[ -z "$cert_arn" ]]; then
        echo "❌ Error: Certificate ARN not found. Deploy infrastructure first."
        exit 1
    fi
    
    echo "=== Stage B SSL - DNS Validation Management ==="
    echo "Action: $action"
    echo "Infrastructure Profile: $infra_profile"
    echo "Target Profile: $target_profile"
    echo "Certificate ARN: $cert_arn"
    echo
    
    # Execute the requested action
    case "$action" in
        add)
            add_dns_validation_records "$infra_profile" "$target_profile" "$cert_arn"
            ;;
        remove)
            remove_dns_validation_records "$infra_profile" "$target_profile" "$cert_arn"
            ;;
        status)
            check_dns_validation_status "$target_profile" "$cert_arn"
            ;;
    esac
}

# Run main function with all arguments
main "$@" 