#!/bin/bash

# status-b.sh - Check status of Stage B SSL Certificate deployment resources
# This script helps monitor SSL certificates, CloudFront distributions, and Route53 DNS records

set -euo pipefail

# Script directory and related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --infraprofile PROFILE    AWS CLI profile for infrastructure resources (defaults to checking inputs.json)
  --targetprofile PROFILE   AWS CLI profile for target resources (defaults to checking inputs.json)
  --domains DOMAIN1,DOMAIN2 Comma-separated list of domains to check (defaults to checking inputs.json)
  --watch                   Continuously monitor status (refresh every 30 seconds)
  --all                     Show all SSL certificates and CloudFront distributions
  -h, --help                Show this help message

Examples:
  $0                                                    # Check status using saved configuration
  $0 --infraprofile yourawsprofile-infra                      # Check with specific infrastructure profile
  $0 --domains www.sbx.yourdomain.com,sbx.yourdomain.com --watch  # Monitor specific domains continuously
  $0 --all                                              # Show all resources

EOF
}

# Default values
INFRA_PROFILE=""
TARGET_PROFILE=""
DOMAINS=""
WATCH_MODE=false
SHOW_ALL=false

# Function to print colored status messages
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --infraprofile)
                INFRA_PROFILE="$2"
                shift 2
                ;;
            --targetprofile)
                TARGET_PROFILE="$2"
                shift 2
                ;;
            --domains)
                DOMAINS="$2"
                shift 2
                ;;
            --watch)
                WATCH_MODE=true
                shift
                ;;
            --all)
                SHOW_ALL=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to load configuration from data files
load_configuration() {
    if [[ -f "$DATA_DIR/inputs.json" ]]; then
        print_status "$BLUE" "📄 Loading configuration from inputs.json..."
        
        if [[ -z "$INFRA_PROFILE" ]]; then
            INFRA_PROFILE=$(jq -r '.infraProfile // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        fi
        
        if [[ -z "$TARGET_PROFILE" ]]; then
            TARGET_PROFILE=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        fi
        
        if [[ -z "$DOMAINS" ]]; then
            local domain_array
            domain_array=$(jq -r '.domains[]?' "$DATA_DIR/inputs.json" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
            DOMAINS="$domain_array"
        fi
    fi
    
    # Set defaults if still empty
    if [[ -z "$INFRA_PROFILE" ]]; then
        INFRA_PROFILE="default"
        print_status "$YELLOW" "⚠️  No infrastructure profile specified, using 'default'"
    fi
    
    if [[ -z "$TARGET_PROFILE" ]]; then
        TARGET_PROFILE="default"
        print_status "$YELLOW" "⚠️  No target profile specified, using 'default'"
    fi
}

# Function to check SSL certificates
check_ssl_certificates() {
    print_status "$CYAN" "🔒 SSL Certificates Status"
    print_status "$CYAN" "══════════════════════════"
    
    print_status "$BLUE" "🔍 Querying SSL certificates..."
    print_status "$BLUE" "   Profile: $INFRA_PROFILE"
    print_status "$BLUE" "   Region: us-east-1 (certificates must be in us-east-1 for CloudFront)"
    
    local certificates
    certificates=$(aws acm list-certificates --profile "$INFRA_PROFILE" --region us-east-1 --output json 2>/dev/null || echo '{"CertificateSummaryList":[]}')
    
    local cert_list
    cert_list=$(echo "$certificates" | jq -r '.CertificateSummaryList[]? | "\(.CertificateArn)|\(.DomainName)"' 2>/dev/null || echo "")
    
    if [[ -z "$cert_list" ]]; then
        print_status "$GREEN" "✅ No SSL certificates found"
        return 0
    fi
    
    print_status "$BLUE" "📊 Found SSL certificates:"
    echo
    
    echo "$cert_list" | while IFS='|' read -r arn domain_name; do
        [[ -z "$arn" ]] && continue
        
        print_status "$BLUE" "🔒 Certificate: $domain_name"
        print_status "$BLUE" "   ARN: $arn"
        
        # Get detailed certificate information
        local cert_details
        cert_details=$(aws acm describe-certificate --certificate-arn "$arn" --profile "$INFRA_PROFILE" --region us-east-1 --output json 2>/dev/null || echo '{}')
        
        if [[ "$cert_details" != "{}" ]]; then
            local status subject_alt_names validation_method
            status=$(echo "$cert_details" | jq -r '.Certificate.Status // "UNKNOWN"' 2>/dev/null)
            validation_method=$(echo "$cert_details" | jq -r '.Certificate.Options[0].ValidationMethod // "UNKNOWN"' 2>/dev/null)
            subject_alt_names=$(echo "$cert_details" | jq -r '.Certificate.SubjectAlternativeNames[]?' 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || echo "")
            
            local status_color="$BLUE"
            local status_icon="📋"
            
            case "$status" in
                "ISSUED")
                    status_color="$GREEN"
                    status_icon="✅"
                    ;;
                "PENDING_VALIDATION")
                    status_color="$YELLOW"
                    status_icon="⏳"
                    ;;
                "FAILED"|"VALIDATION_TIMED_OUT"|"REVOKED")
                    status_color="$RED"
                    status_icon="❌"
                    ;;
            esac
            
            print_status "$status_color" "   Status: $status_icon $status"
            print_status "$BLUE" "   Validation Method: $validation_method"
            [[ -n "$subject_alt_names" ]] && print_status "$BLUE" "   Domains: $subject_alt_names"
            
            # Show validation records if pending
            if [[ "$status" == "PENDING_VALIDATION" ]]; then
                local validation_options
                validation_options=$(echo "$cert_details" | jq -r '.Certificate.DomainValidationOptions[]? | "\(.DomainName)|\(.ValidationStatus)|\(.ResourceRecord.Name)|\(.ResourceRecord.Value)"' 2>/dev/null || echo "")
                
                if [[ -n "$validation_options" ]]; then
                    print_status "$YELLOW" "   🔍 Validation Records Needed:"
                    echo "$validation_options" | while IFS='|' read -r val_domain val_status record_name record_value; do
                        [[ -z "$val_domain" ]] && continue
                        print_status "$YELLOW" "     Domain: $val_domain ($val_status)"
                        print_status "$YELLOW" "     DNS Record: $record_name"
                        print_status "$YELLOW" "     Value: ${record_value:0:50}..."
                    done
                fi
            fi
        fi
        echo
    done
}

# Function to check CloudFront distributions
check_cloudfront_distributions() {
    print_status "$CYAN" "☁️  CloudFront Distributions Status"
    print_status "$CYAN" "════════════════════════════════════"
    
    print_status "$BLUE" "🔍 Querying CloudFront distributions..."
    print_status "$BLUE" "   Profile: $TARGET_PROFILE"
    
    local distributions
    distributions=$(aws cloudfront list-distributions --profile "$TARGET_PROFILE" --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Comment:Comment,Enabled:Enabled}' --output json 2>/dev/null || echo "[]")
    
    if [[ "$distributions" == "[]" ]] || [[ -z "$distributions" ]] || [[ "$distributions" == "null" ]]; then
        print_status "$GREEN" "✅ No CloudFront distributions found"
        return 0
    fi
    
    # Parse and display distributions
    local count
    count=$(echo "$distributions" | jq length 2>/dev/null || echo "0")
    if [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        print_status "$GREEN" "✅ No CloudFront distributions found"
        return 0
    fi
    
    print_status "$BLUE" "📊 Found $count distribution(s):"
    echo
    
    echo "$distributions" | jq -r '.[] | "\(.Id)|\(.DomainName)|\(.Status)|\(.Comment)|\(.Enabled)"' 2>/dev/null | while IFS='|' read -r id domain status comment enabled; do
        local status_color="$BLUE"
        local status_icon="📋"
        
        case "$status" in
            "Deployed")
                status_color="$GREEN"
                status_icon="✅"
                ;;
            "InProgress")
                status_color="$YELLOW"
                status_icon="⏳"
                ;;
            *)
                status_color="$RED"
                status_icon="❌"
                ;;
        esac
        
        print_status "$status_color" "$status_icon Distribution ID: $id"
        print_status "$BLUE" "   CloudFront Domain: $domain"
        print_status "$status_color" "   Status: $status"
        print_status "$BLUE" "   Comment: $comment"
        print_status "$BLUE" "   Enabled: $enabled"
        
        # Get detailed distribution information including SSL certificate and aliases
        local dist_details
        dist_details=$(aws cloudfront get-distribution --id "$id" --profile "$TARGET_PROFILE" --output json 2>/dev/null || echo '{}')
        
        if [[ "$dist_details" != "{}" ]]; then
            local aliases cert_arn viewer_protocol_policy
            aliases=$(echo "$dist_details" | jq -r '.Distribution.DistributionConfig.Aliases.Items[]?' 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || echo "")
            cert_arn=$(echo "$dist_details" | jq -r '.Distribution.DistributionConfig.ViewerCertificate.ACMCertificateArn // empty' 2>/dev/null)
            viewer_protocol_policy=$(echo "$dist_details" | jq -r '.Distribution.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy // "allow-all"' 2>/dev/null)
            
            [[ -n "$aliases" ]] && print_status "$BLUE" "   Custom Domains: $aliases"
            
            if [[ -n "$cert_arn" ]]; then
                print_status "$GREEN" "   🔒 SSL Certificate: ${cert_arn##*/}"
                print_status "$BLUE" "   Viewer Protocol: $viewer_protocol_policy"
            else
                print_status "$YELLOW" "   ⚠️  No custom SSL certificate attached"
            fi
        fi
        echo
    done
}

# Function to check Route53 DNS records
check_route53_records() {
    if [[ -z "$DOMAINS" ]]; then
        print_status "$YELLOW" "⚠️  No domains specified, skipping Route53 DNS check"
        return 0
    fi
    
    print_status "$CYAN" "🌐 Route53 DNS Records Status"
    print_status "$CYAN" "═════════════════════════════"
    
    print_status "$BLUE" "🔍 Checking DNS records for domains: $DOMAINS"
    print_status "$BLUE" "   Profile: $INFRA_PROFILE"
    
    # Convert comma-separated domains to array
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    
    for domain in "${DOMAIN_ARRAY[@]}"; do
        [[ -z "$domain" ]] && continue
        
        print_status "$BLUE" "🌐 Domain: $domain"
        
        # Find the hosted zone for this domain
        local hosted_zones
        hosted_zones=$(aws route53 list-hosted-zones --profile "$INFRA_PROFILE" --output json 2>/dev/null || echo '{"HostedZones":[]}')
        
        local zone_id=""
        local zone_name=""
        
        # Find the best matching hosted zone
        echo "$hosted_zones" | jq -r '.HostedZones[]? | "\(.Id)|\(.Name)"' 2>/dev/null | while IFS='|' read -r id name; do
            [[ -z "$id" ]] && continue
            local clean_name="${name%.}"  # Remove trailing dot
            if [[ "$domain" == "$clean_name" ]] || [[ "$domain" == *".$clean_name" ]]; then
                if [[ -z "$zone_id" ]] || [[ ${#clean_name} -gt ${#zone_name} ]]; then
                    zone_id="$id"
                    zone_name="$clean_name"
                fi
            fi
        done
        
        if [[ -n "$zone_id" ]]; then
            print_status "$GREEN" "   ✅ Found hosted zone: $zone_name ($zone_id)"
            
            # Check for DNS validation records
            local records
            records=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" --profile "$INFRA_PROFILE" --output json 2>/dev/null || echo '{"ResourceRecordSets":[]}')
            
            local validation_records
            validation_records=$(echo "$records" | jq -r '.ResourceRecordSets[]? | select(.Type == "CNAME" and (.Name | contains("_acme-challenge") or contains("_")) and (.Name | contains("'$domain'"))) | "\(.Name)|\(.ResourceRecords[0].Value)"' 2>/dev/null || echo "")
            
            if [[ -n "$validation_records" ]]; then
                print_status "$GREEN" "     🔍 DNS validation records found:"
                echo "$validation_records" | while IFS='|' read -r record_name record_value; do
                    [[ -z "$record_name" ]] && continue
                    print_status "$GREEN" "       $record_name -> ${record_value:0:50}..."
                done
            else
                print_status "$YELLOW" "     ⚠️  No DNS validation records found for $domain"
            fi
        else
            print_status "$RED" "   ❌ No hosted zone found for domain: $domain"
        fi
        echo
    done
}

# Function to display deployment summary
show_deployment_summary() {
    if [[ -f "$DATA_DIR/outputs.json" ]]; then
        print_status "$CYAN" "📋 Stage B Deployment Summary"
        print_status "$CYAN" "═════════════════════════════"
        
        local certificate_arn distribution_url domains validation_status
        certificate_arn=$(jq -r '.certificateArn // "Not available"' "$DATA_DIR/outputs.json" 2>/dev/null)
        distribution_url=$(jq -r '.distributionUrl // "Not available"' "$DATA_DIR/outputs.json" 2>/dev/null)
        domains=$(jq -r '.domains[]?' "$DATA_DIR/outputs.json" 2>/dev/null | tr '\n' ' ' || echo "Not available")
        validation_status=$(jq -r '.validationStatus // "Not available"' "$DATA_DIR/outputs.json" 2>/dev/null)
        
        print_status "$BLUE" "🔒 SSL Certificate: ${certificate_arn##*/}"
        print_status "$BLUE" "☁️  CloudFront URL: $distribution_url"
        print_status "$BLUE" "🌐 Configured Domains: $domains"
        
        case "$validation_status" in
            "passed")
                print_status "$GREEN" "✅ Validation Status: $validation_status"
                ;;
            "failed")
                print_status "$RED" "❌ Validation Status: $validation_status"
                ;;
            *)
                print_status "$YELLOW" "⏳ Validation Status: $validation_status"
                ;;
        esac
        
        echo
        print_status "$BLUE" "🌐 Test your HTTPS deployment:"
        for domain in $(jq -r '.domains[]?' "$DATA_DIR/outputs.json" 2>/dev/null || echo ""); do
            [[ -n "$domain" ]] && print_status "$BLUE" "   https://$domain"
        done
        echo
    fi
}

# Main status checking function
main_status_check() {
    print_status "$CYAN" "🚀 AWS SPA Boilerplate - Stage B SSL Status Check"
    print_status "$CYAN" "═══════════════════════════════════════════════════"
    echo
    
    load_configuration
    echo
    
    check_ssl_certificates
    echo
    
    check_cloudfront_distributions
    echo
    
    check_route53_records
    echo
    
    show_deployment_summary
}

# Function to handle watch mode
watch_status() {
    while true; do
        clear
        main_status_check
        print_status "$YELLOW" "⏰ Refreshing in 30 seconds... (Press Ctrl+C to exit)"
        sleep 30
    done
}

# Main execution
main() {
    parse_arguments "$@"
    
    if [[ "$WATCH_MODE" == "true" ]]; then
        watch_status
    else
        main_status_check
    fi
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 