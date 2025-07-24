#!/bin/bash

# status-a.sh - Check status of Stage A CloudFront deployment resources
# This script helps monitor CloudFront distributions, S3 buckets, and VPC resources

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
  --profile PROFILE     AWS CLI profile to use (defaults to checking inputs.json)
  --prefix PREFIX       Distribution prefix to filter results (defaults to checking inputs.json)
  --region REGION       AWS region to check (defaults to checking inputs.json)
  --vpc VPC_ID          VPC ID to check (defaults to checking inputs.json)
  --watch               Continuously monitor status (refresh every 30 seconds)
  --all                 Show all CloudFront distributions and S3 buckets
  -h, --help            Show this help message

Examples:
  $0                                    # Check status using saved configuration
  $0 --profile bh-fred-sandbox         # Check with specific profile
  $0 --prefix hellospa --watch          # Monitor specific prefix continuously
  $0 --all                              # Show all resources

EOF
}

# Default values
PROFILE=""
PREFIX=""
REGION=""
VPC_ID=""
WATCH_MODE=false
SHOW_ALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --vpc)
            VPC_ID="$2"
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
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to load configuration from inputs.json if available
load_configuration() {
    if [[ -f "$DATA_DIR/inputs.json" ]]; then
        print_status "$BLUE" "📄 Loading configuration from inputs.json..."
        
        if [[ -z "$PROFILE" ]]; then
            PROFILE=$(jq -r '.targetProfile // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        fi
        
        if [[ -z "$PREFIX" ]]; then
            PREFIX=$(jq -r '.distributionPrefix // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        fi
        
        if [[ -z "$REGION" ]]; then
            REGION=$(jq -r '.targetRegion // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        fi
        
        if [[ -z "$VPC_ID" ]]; then
            VPC_ID=$(jq -r '.targetVpcId // empty' "$DATA_DIR/inputs.json" 2>/dev/null || echo "")
        fi
    fi
    
    # Set defaults if still empty
    if [[ -z "$PROFILE" ]]; then
        PROFILE="default"
        print_status "$YELLOW" "⚠️  No profile specified, using 'default'"
    fi
    
    if [[ -z "$REGION" ]]; then
        REGION="us-east-1"
        print_status "$YELLOW" "⚠️  No region specified, using 'us-east-1'"
    fi
}

# Function to check CloudFront distributions
check_cloudfront_distributions() {
    print_status "$CYAN" "☁️  CloudFront Distributions Status"
    print_status "$CYAN" "════════════════════════════════════"
    
    print_status "$BLUE" "🔍 Querying CloudFront distributions..."
    print_status "$BLUE" "   Profile: $PROFILE"
    [[ -n "$PREFIX" ]] && print_status "$BLUE" "   Filtering by prefix: $PREFIX"
    
    local query
    if [[ "$SHOW_ALL" == "true" ]]; then
        query='DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Comment:Comment,Enabled:Enabled}'
    elif [[ -n "$PREFIX" ]]; then
        query="DistributionList.Items[?contains(Comment, \`$PREFIX\`)].{Id:Id,DomainName:DomainName,Status:Status,Comment:Comment,Enabled:Enabled}"
    else
        query='DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Comment:Comment,Enabled:Enabled}'
    fi
    
    local distributions
    distributions=$(aws cloudfront list-distributions --profile "$PROFILE" --query "$query" --output json 2>/dev/null || echo "[]")
    
    if [[ "$distributions" == "[]" ]] || [[ -z "$distributions" ]] || [[ "$distributions" == "null" ]]; then
        if [[ -n "$PREFIX" ]]; then
            print_status "$GREEN" "✅ No CloudFront distributions found with prefix '$PREFIX'"
        else
            print_status "$GREEN" "✅ No CloudFront distributions found"
        fi
        return 0
    fi
    
    # Parse and display distributions
    local count
    count=$(echo "$distributions" | jq length 2>/dev/null || echo "0")
    if [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        if [[ -n "$PREFIX" ]]; then
            print_status "$GREEN" "✅ No CloudFront distributions found with prefix '$PREFIX'"
        else
            print_status "$GREEN" "✅ No CloudFront distributions found"
        fi
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
        print_status "$BLUE" "   Domain: $domain"
        print_status "$status_color" "   Status: $status"
        print_status "$BLUE" "   Comment: $comment"
        print_status "$BLUE" "   Enabled: $enabled"
        echo
    done
}

# Function to check S3 buckets
check_s3_buckets() {
    print_status "$CYAN" "🪣 S3 Buckets Status"
    print_status "$CYAN" "═══════════════════"
    
    print_status "$BLUE" "🔍 Querying S3 buckets..."
    print_status "$BLUE" "   Profile: $PROFILE"
    [[ -n "$PREFIX" ]] && print_status "$BLUE" "   Filtering by prefix: $PREFIX"
    
    local buckets
    if [[ "$SHOW_ALL" == "true" ]]; then
        buckets=$(aws s3api list-buckets --profile "$PROFILE" --query 'Buckets[].Name' --output text 2>/dev/null || echo "")
    elif [[ -n "$PREFIX" ]]; then
        buckets=$(aws s3api list-buckets --profile "$PROFILE" --query "Buckets[?starts_with(Name, \`$PREFIX\`)].Name" --output text 2>/dev/null || echo "")
    else
        buckets=$(aws s3api list-buckets --profile "$PROFILE" --query 'Buckets[].Name' --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "$buckets" ]] || [[ "$buckets" == "None" ]]; then
        if [[ -n "$PREFIX" ]]; then
            print_status "$GREEN" "✅ No S3 buckets found with prefix '$PREFIX'"
        else
            print_status "$GREEN" "✅ No S3 buckets found"
        fi
        return 0
    fi
    
    local bucket_count=0
    for bucket in $buckets; do
        ((bucket_count++))
        print_status "$GREEN" "✅ Bucket: $bucket"
        
        # Get bucket region
        local bucket_region
        bucket_region=$(aws s3api get-bucket-location --bucket "$bucket" --profile "$PROFILE" --query 'LocationConstraint' --output text 2>/dev/null || echo "us-east-1")
        [[ "$bucket_region" == "None" ]] && bucket_region="us-east-1"
        print_status "$BLUE" "   Region: $bucket_region"
        
        # Get bucket size and object count
        local size_info
        size_info=$(aws s3 ls "s3://$bucket" --recursive --summarize --profile "$PROFILE" 2>/dev/null | tail -2 || echo "")
        if [[ -n "$size_info" ]]; then
            local object_count=$(echo "$size_info" | grep "Total Objects:" | awk '{print $3}' || echo "0")
            local total_size=$(echo "$size_info" | grep "Total Size:" | awk '{print $3, $4}' || echo "0 Bytes")
            print_status "$BLUE" "   Objects: $object_count"
            print_status "$BLUE" "   Size: $total_size"
        fi
        echo
    done
    
    print_status "$BLUE" "📊 Found $bucket_count bucket(s)"
}

# Function to check VPC status
check_vpc_status() {
    if [[ -z "$VPC_ID" ]]; then
        print_status "$YELLOW" "⚠️  No VPC ID specified, skipping VPC check"
        return 0
    fi
    
    print_status "$CYAN" "🌐 VPC Status"
    print_status "$CYAN" "════════════"
    
    print_status "$BLUE" "🔍 Checking VPC: $VPC_ID"
    print_status "$BLUE" "   Profile: $PROFILE"
    print_status "$BLUE" "   Region: $REGION"
    
    # Check VPC existence and details
    local vpc_info
    vpc_info=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo "")
    
    if [[ -z "$vpc_info" ]] || [[ "$vpc_info" == "null" ]]; then
        print_status "$RED" "❌ VPC '$VPC_ID' not found or not accessible"
        return 1
    fi
    
    local vpc_state cidr_block is_default
    vpc_state=$(echo "$vpc_info" | jq -r '.Vpcs[0].State // "unknown"')
    cidr_block=$(echo "$vpc_info" | jq -r '.Vpcs[0].CidrBlock // "unknown"')
    is_default=$(echo "$vpc_info" | jq -r '.Vpcs[0].IsDefault // false')
    
    local state_color="$BLUE"
    local state_icon="📋"
    
    case "$vpc_state" in
        "available")
            state_color="$GREEN"
            state_icon="✅"
            ;;
        "pending")
            state_color="$YELLOW"
            state_icon="⏳"
            ;;
        *)
            state_color="$RED"
            state_icon="❌"
            ;;
    esac
    
    print_status "$state_color" "$state_icon VPC ID: $VPC_ID"
    print_status "$state_color" "   State: $vpc_state"
    print_status "$BLUE" "   CIDR Block: $cidr_block"
    print_status "$BLUE" "   Is Default: $is_default"
    
    # Check subnets in the VPC
    local subnets
    subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --profile "$PROFILE" --region "$REGION" --query 'Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,CidrBlock:CidrBlock,State:State}' --output json 2>/dev/null || echo "[]")
    
    local subnet_count
    subnet_count=$(echo "$subnets" | jq length)
    print_status "$BLUE" "   Subnets: $subnet_count"
    
    if [[ $subnet_count -gt 0 ]]; then
        echo "$subnets" | jq -r '.[] | "      \(.SubnetId) (\(.AvailabilityZone)) - \(.CidrBlock) - \(.State)"' | while read -r subnet_info; do
            print_status "$BLUE" "$subnet_info"
        done
    fi
    
    echo
}

# Function to check CDK stack status
check_cdk_stack_status() {
    print_status "$CYAN" "📦 CDK Stack Status"
    print_status "$CYAN" "══════════════════"
    
    local iac_dir="$SCRIPT_DIR/iac"
    if [[ ! -d "$iac_dir" ]]; then
        print_status "$YELLOW" "⚠️  No IAC directory found"
        return 0
    fi
    
    print_status "$BLUE" "🔍 Checking CDK stacks..."
    print_status "$BLUE" "   Profile: $PROFILE"
    
    cd "$iac_dir"
    
    # List CDK stacks
    local stacks
    stacks=$(npx cdk list --profile "$PROFILE" 2>/dev/null || echo "")
    
    if [[ -z "$stacks" ]] || [[ "$stacks" == *"no stacks"* ]]; then
        print_status "$GREEN" "✅ No CDK stacks found"
        cd "$SCRIPT_DIR"
        return 0
    fi
    
    print_status "$BLUE" "📊 Found CDK stacks: $stacks"
    
    # Get stack status from CloudFormation
    for stack in $stacks; do
        local stack_status
        stack_status=$(aws cloudformation describe-stacks --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
        
        local status_color="$BLUE"
        local status_icon="📋"
        
        case "$stack_status" in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                status_color="$GREEN"
                status_icon="✅"
                ;;
            "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS"|"DELETE_IN_PROGRESS")
                status_color="$YELLOW"
                status_icon="⏳"
                ;;
            "CREATE_FAILED"|"UPDATE_FAILED"|"DELETE_FAILED"|"ROLLBACK_FAILED")
                status_color="$RED"
                status_icon="❌"
                ;;
            "NOT_FOUND")
                status_color="$YELLOW"
                status_icon="⚠️"
                ;;
        esac
        
        print_status "$status_color" "$status_icon Stack: $stack"
        print_status "$status_color" "   Status: $stack_status"
    done
    
    cd "$SCRIPT_DIR"
    echo
}

# Function to show summary status
show_summary() {
    print_status "$CYAN" "📋 Summary"
    print_status "$CYAN" "═════════"
    
    # Check if ready for deployment
    local ready_for_deployment=true
    local ready_for_cleanup=false
    
    # Check for in-progress CloudFront distributions
    local in_progress_distributions
    in_progress_distributions=$(aws cloudfront list-distributions --profile "$PROFILE" --query 'DistributionList.Items[?Status==`InProgress`].Id' --output text 2>/dev/null || echo "")
    
    if [[ -n "$in_progress_distributions" ]] && [[ "$in_progress_distributions" != "None" ]]; then
        ready_for_deployment=false
        print_status "$YELLOW" "⏳ CloudFront distributions are in progress - deployment blocked"
    fi
    
    # Check for existing resources
    local existing_distributions existing_buckets
    if [[ -n "$PREFIX" ]]; then
        existing_distributions=$(aws cloudfront list-distributions --profile "$PROFILE" --query "DistributionList.Items[?contains(Comment, \`$PREFIX\`)].Id" --output text 2>/dev/null || echo "")
        existing_buckets=$(aws s3api list-buckets --profile "$PROFILE" --query "Buckets[?starts_with(Name, \`$PREFIX\`)].Name" --output text 2>/dev/null || echo "")
    else
        existing_distributions=""
        existing_buckets=""
    fi
    
    if [[ -n "$existing_distributions" ]] && [[ "$existing_distributions" != "None" ]]; then
        ready_for_cleanup=true
    fi
    
    if [[ -n "$existing_buckets" ]] && [[ "$existing_buckets" != "None" ]]; then
        ready_for_cleanup=true
    fi
    
    # Show recommendations
    if [[ "$ready_for_deployment" == "true" ]] && [[ "$ready_for_cleanup" == "false" ]]; then
        print_status "$GREEN" "🚀 Ready for deployment!"
        print_status "$BLUE" "   You can run: ./go-a.sh --infraprofile <profile> --targetprofile $PROFILE --prefix <prefix> --region $REGION --vpc $VPC_ID"
    elif [[ "$ready_for_deployment" == "false" ]]; then
        print_status "$YELLOW" "⏳ Waiting for CloudFront operations to complete..."
        print_status "$BLUE" "   CloudFront operations typically take 15-45 minutes"
        if [[ "$WATCH_MODE" == "false" ]]; then
            print_status "$BLUE" "   Use --watch to monitor continuously"
        fi
    elif [[ "$ready_for_cleanup" == "true" ]]; then
        print_status "$BLUE" "🧹 Resources exist - cleanup available"
        print_status "$BLUE" "   You can run: ./undo-a.sh"
    fi
    
    echo
}

# Function to display status header
show_header() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    print_status "$CYAN" "🔍 AWS SPA Boilerplate - Stage A Status Check"
    print_status "$CYAN" "═══════════════════════════════════════════"
    print_status "$BLUE" "Timestamp: $timestamp"
    print_status "$BLUE" "Profile: $PROFILE"
    print_status "$BLUE" "Region: $REGION"
    [[ -n "$PREFIX" ]] && print_status "$BLUE" "Prefix: $PREFIX"
    [[ -n "$VPC_ID" ]] && print_status "$BLUE" "VPC ID: $VPC_ID"
    echo
}

# Main status check function
main_status_check() {
    load_configuration
    
    while true; do
        clear
        show_header
        
        check_cloudfront_distributions
        echo
        
        check_s3_buckets
        echo
        
        check_vpc_status
        echo
        
        check_cdk_stack_status
        echo
        
        show_summary
        
        if [[ "$WATCH_MODE" == "false" ]]; then
            break
        fi
        
        print_status "$BLUE" "🔄 Refreshing in 30 seconds... (Press Ctrl+C to stop)"
        sleep 30
    done
}

# Function to handle cleanup on script interruption
cleanup_on_interrupt() {
    echo
    print_status "$YELLOW" "⚠️  Status monitoring stopped by user (Ctrl+C)"
    exit 130
}

# Set up interrupt handler
trap cleanup_on_interrupt INT TERM

# Main execution
main() {
    main_status_check
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
