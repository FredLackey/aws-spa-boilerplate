#!/bin/bash

# deploy-dns.sh
# DNS validation record management for Stage B SSL Certificate deployment
# Creates and manages DNS validation records in Route53 for certificate validation

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$STAGE_DIR/data"

echo "=== Stage B SSL Certificate Deployment - DNS Validation Records ==="
echo "This script manages DNS validation records for SSL certificate validation."
echo

# Function to validate required files exist
validate_prerequisites() {
    local inputs_file="$DATA_DIR/inputs.json"
    local discovery_file="$DATA_DIR/discovery.json"
    local outputs_file="$DATA_DIR/outputs.json"
    
    echo "Validating prerequisites..."
    
    if [[ ! -f "$inputs_file" ]]; then
        echo "❌ Error: inputs.json not found. Please run gather-inputs.sh first."
        exit 1
    fi
    
    if [[ ! -f "$discovery_file" ]]; then
        echo "❌ Error: discovery.json not found. Please run aws-discovery.sh first."
        exit 1
    fi
    
    if [[ ! -f "$outputs_file" ]]; then
        echo "❌ Error: outputs.json not found. Please run deploy-infrastructure.sh first."
        exit 1
    fi
    
    echo "✅ Prerequisites validated"
}

# Function to get certificate validation records
get_certificate_validation_records() {
    local infra_profile="$1"
    local cert_arn="$2"
    
    echo "🔍 Getting DNS validation records for certificate..."
    echo "   Certificate ARN: $cert_arn"
    
    # Get certificate details including validation options
    local cert_details
    cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --profile "$infra_profile" --region us-east-1 --output json 2>/dev/null || echo '{}')
    
    if [[ "$cert_details" == "{}" ]]; then
        echo "❌ Could not retrieve certificate details"
        return 1
    fi
    
    local cert_status
    cert_status=$(echo "$cert_details" | jq -r '.Certificate.Status // "UNKNOWN"' 2>/dev/null)
    
    echo "   📋 Certificate status: $cert_status"
    
    if [[ "$cert_status" == "ISSUED" ]]; then
        echo "✅ Certificate is already validated - no DNS records needed"
        return 0
    fi
    
    if [[ "$cert_status" != "PENDING_VALIDATION" ]]; then
        echo "❌ Certificate is in unexpected status: $cert_status"
        return 1
    fi
    
    # Extract validation options
    local validation_records
    validation_records=$(echo "$cert_details" | jq -c '.Certificate.DomainValidationOptions[]? | select(.ResourceRecord) | {domain: .DomainName, name: .ResourceRecord.Name, value: .ResourceRecord.Value, type: .ResourceRecord.Type}' 2>/dev/null || echo "")
    
    if [[ -z "$validation_records" ]]; then
        echo "⚠️  No DNS validation records found - certificate may not be ready yet"
        return 1
    fi
    
    echo "✅ Found DNS validation records"
    echo "$validation_records"
    return 0
}

# Function to create DNS validation records in Route53
create_dns_validation_records() {
    local infra_profile="$1"
    local cert_arn="$2"
    
    echo "🌐 Creating DNS validation records in Route53..."
    
    # Get validation records from certificate
    local validation_records
    validation_records=$(get_certificate_validation_records "$infra_profile" "$cert_arn")
    local validation_exit_code=$?
    
    if [[ $validation_exit_code -ne 0 ]]; then
        return $validation_exit_code
    fi
    
    if [[ -z "$validation_records" ]]; then
        echo "✅ No DNS validation records to create"
        return 0
    fi
    
    # Load hosted zones from discovery
    local hosted_zones
    hosted_zones=$(jq -c '.hostedZones[]' "$DATA_DIR/discovery.json" 2>/dev/null || echo "")
    
    if [[ -z "$hosted_zones" ]]; then
        echo "❌ No hosted zones found in discovery.json"
        return 1
    fi
    
    # Create a map of domain to hosted zone
    local -A domain_to_zone
    while IFS= read -r zone_info; do
        [[ -z "$zone_info" ]] && continue
        local domain zone_id zone_name
        domain=$(echo "$zone_info" | jq -r '.domain')
        zone_id=$(echo "$zone_info" | jq -r '.zoneId' | sed 's|/hostedzone/||')
        zone_name=$(echo "$zone_info" | jq -r '.zoneName')
        domain_to_zone["$domain"]="$zone_id:$zone_name"
    done <<< "$hosted_zones"
    
    # Process each validation record
    local records_created=0
    while IFS= read -r record_info; do
        [[ -z "$record_info" ]] && continue
        
        local domain record_name record_value record_type
        domain=$(echo "$record_info" | jq -r '.domain')
        record_name=$(echo "$record_info" | jq -r '.name')
        record_value=$(echo "$record_info" | jq -r '.value')
        record_type=$(echo "$record_info" | jq -r '.type')
        
        echo "   📋 Processing validation record for domain: $domain"
        echo "      Record Name: $record_name"
        echo "      Record Type: $record_type"
        echo "      Record Value: ${record_value:0:50}..."
        
        # Find the appropriate hosted zone
        local zone_info="${domain_to_zone[$domain]:-}"
        if [[ -z "$zone_info" ]]; then
            echo "      ❌ No hosted zone found for domain: $domain"
            continue
        fi
        
        local zone_id zone_name
        IFS=':' read -r zone_id zone_name <<< "$zone_info"
        
        echo "      🌐 Using hosted zone: $zone_name ($zone_id)"
        
        # Check if record already exists
        echo "      🔍 Checking if validation record already exists..."
        local existing_record
        existing_record=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" --profile "$infra_profile" --query "ResourceRecordSets[?Name=='$record_name' && Type=='$record_type'].ResourceRecords[0].Value" --output text 2>/dev/null || echo "")
        
        if [[ -n "$existing_record" ]] && [[ "$existing_record" != "None" ]]; then
            if [[ "$existing_record" == "$record_value" ]]; then
                echo "      ✅ Validation record already exists with correct value"
                ((records_created++))
                continue
            else
                echo "      ⚠️  Validation record exists but with different value"
                echo "         Existing: ${existing_record:0:50}..."
                echo "         Required: ${record_value:0:50}..."
            fi
        fi
        
        # Create the DNS record
        echo "      ➕ Creating DNS validation record..."
        local change_batch
        change_batch=$(jq -n \
            --arg action "UPSERT" \
            --arg name "$record_name" \
            --arg type "$record_type" \
            --arg value "$record_value" \
            '{
                Changes: [{
                    Action: $action,
                    ResourceRecordSet: {
                        Name: $name,
                        Type: $type,
                        TTL: 300,
                        ResourceRecords: [{Value: $value}]
                    }
                }]
            }')
        
        local change_result
        change_result=$(echo "$change_batch" | aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch file:///dev/stdin --profile "$infra_profile" --output json 2>/dev/null || echo '{}')
        
        if [[ "$change_result" == "{}" ]]; then
            echo "      ❌ Failed to create DNS validation record"
            continue
        fi
        
        local change_id
        change_id=$(echo "$change_result" | jq -r '.ChangeInfo.Id // empty' 2>/dev/null)
        
        if [[ -n "$change_id" ]]; then
            echo "      ✅ DNS validation record created successfully"
            echo "         Change ID: $change_id"
            ((records_created++))
        else
            echo "      ⚠️  DNS record creation completed but no change ID returned"
            ((records_created++))
        fi
        
        echo
    done <<< "$validation_records"
    
    echo "📊 DNS validation record creation summary:"
    echo "   Records processed: $(echo "$validation_records" | wc -l)"
    echo "   Records created/updated: $records_created"
    
    if [[ $records_created -gt 0 ]]; then
        echo "✅ DNS validation records have been created"
        echo "   Records will be retained permanently (no automatic cleanup)"
        echo "   Certificate validation should complete automatically"
        return 0
    else
        echo "❌ No DNS validation records were created"
        return 1
    fi
}

# Function to verify DNS propagation
verify_dns_propagation() {
    local cert_arn="$1"
    local infra_profile="$2"
    
    echo "🔍 Verifying DNS record propagation..."
    
    # Get validation records
    local validation_records
    validation_records=$(get_certificate_validation_records "$infra_profile" "$cert_arn")
    local validation_exit_code=$?
    
    if [[ $validation_exit_code -ne 0 ]] || [[ -z "$validation_records" ]]; then
        echo "⚠️  Could not retrieve validation records for verification"
        return 0
    fi
    
    local verified_count=0
    local total_count=0
    
    # Check each validation record
    while IFS= read -r record_info; do
        [[ -z "$record_info" ]] && continue
        ((total_count++))
        
        local domain record_name record_value
        domain=$(echo "$record_info" | jq -r '.domain')
        record_name=$(echo "$record_info" | jq -r '.name')
        record_value=$(echo "$record_info" | jq -r '.value')
        
        echo "   🌐 Checking DNS propagation for: $domain"
        echo "      Record: $record_name"
        
        # Query DNS to check if record exists
        local dns_result
        dns_result=$(dig +short TXT "$record_name" 2>/dev/null | tr -d '"' || echo "")
        
        if [[ -n "$dns_result" ]] && [[ "$dns_result" == "$record_value" ]]; then
            echo "      ✅ DNS record propagated correctly"
            ((verified_count++))
        else
            echo "      ⏳ DNS record not yet propagated (this is normal)"
            echo "         Expected: ${record_value:0:50}..."
            echo "         Found: ${dns_result:0:50}..."
        fi
        echo
    done <<< "$validation_records"
    
    echo "📊 DNS propagation verification:"
    echo "   Total records: $total_count"
    echo "   Propagated: $verified_count"
    
    if [[ $verified_count -eq $total_count ]]; then
        echo "✅ All DNS validation records have propagated"
    else
        echo "⏳ DNS propagation in progress (this can take several minutes)"
        echo "   Certificate validation will proceed automatically once propagated"
    fi
    
    return 0
}

# Main DNS deployment orchestration function
main_dns_deployment() {
    echo "Starting DNS validation record deployment..."
    echo
    
    # Step 1: Validate prerequisites
    validate_prerequisites
    echo
    
    # Step 2: Get certificate ARN from outputs
    local cert_arn infra_profile
    cert_arn=$(jq -r '.certificateArn // empty' "$DATA_DIR/outputs.json" 2>/dev/null || echo "")
    infra_profile=$(jq -r '.infraProfile' "$DATA_DIR/inputs.json")
    
    if [[ -z "$cert_arn" ]] || [[ "$cert_arn" == "unknown" ]]; then
        echo "❌ Could not find certificate ARN in outputs.json"
        echo "   Please ensure deploy-infrastructure.sh completed successfully"
        exit 1
    fi
    
    echo "📋 Certificate Information:"
    echo "   ARN: $cert_arn"
    echo "   Infrastructure Profile: $infra_profile"
    echo
    
    # Step 3: Create DNS validation records
    if ! create_dns_validation_records "$infra_profile" "$cert_arn"; then
        echo "❌ DNS validation record creation failed"
        exit 1
    fi
    echo
    
    # Step 4: Verify DNS propagation
    verify_dns_propagation "$cert_arn" "$infra_profile"
    echo
    
    # Step 5: Update outputs with DNS deployment status
    echo "💾 Updating deployment outputs..."
    
    # Update outputs.json with DNS deployment status
    local temp_outputs="$DATA_DIR/outputs.json.tmp"
    jq --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.dnsValidationDeployed = true |
        .dnsValidationTimestamp = $timestamp |
        .certificateStatus = "PENDING_VALIDATION"' \
       "$DATA_DIR/outputs.json" > "$temp_outputs"
    
    mv "$temp_outputs" "$DATA_DIR/outputs.json"
    echo "✅ Deployment outputs updated"
    echo
    
    echo "🎉 DNS validation record deployment completed!"
    echo "   DNS validation records have been created in Route53"
    echo "   Records will be retained permanently for certificate validation"
    echo "   Certificate validation will proceed automatically"
    echo "   You can monitor certificate status using status-b.sh"
}

# Main execution
main() {
    main_dns_deployment
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 