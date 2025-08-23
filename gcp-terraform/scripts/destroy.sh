#!/bin/bash

# Destroy N8N GCP Infrastructure
# Usage: ./scripts/destroy.sh [environment]

set -e

ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
    exit 1
fi

# Change to project directory
cd "$PROJECT_ROOT"

print_warning "=== DESTRUCTION WARNING ==="
print_warning "This will PERMANENTLY DESTROY all resources for environment: $ENVIRONMENT"
print_warning "This includes:"
print_warning "  - GKE cluster and all workloads"
print_warning "  - PostgreSQL database and ALL DATA"
print_warning "  - Static IP addresses"
print_warning "  - SSL certificates"
print_warning "  - VPC network and subnets"
print_warning "  - All N8N workflows and configurations"
echo ""

# Check if terraform state exists
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
    print_error "Terraform state not found. Nothing to destroy."
    exit 1
fi

# Show current resources
print_info "Current resources in environment '$ENVIRONMENT':"
terraform show -no-color | grep -E "^resource|^data" | head -10
if [[ $(terraform show -no-color | grep -E "^resource|^data" | wc -l) -gt 10 ]]; then
    echo "... and $(( $(terraform show -no-color | grep -E "^resource|^data" | wc -l) - 10 )) more resources"
fi
echo ""

# Multiple confirmations for production
if [[ "$ENVIRONMENT" == "prod" ]]; then
    print_error "THIS IS A PRODUCTION ENVIRONMENT!"
    print_warning "You are about to destroy PRODUCTION resources!"
    echo ""
    
    read -p "Type 'DELETE PRODUCTION' to confirm: " confirm1
    if [[ "$confirm1" != "DELETE PRODUCTION" ]]; then
        print_info "Destruction cancelled"
        exit 0
    fi
    
    print_warning "Final confirmation required!"
    read -p "Are you absolutely sure? Type 'yes' to continue: " confirm2
    if [[ "$confirm2" != "yes" ]]; then
        print_info "Destruction cancelled"
        exit 0
    fi
else
    read -p "Type 'DELETE' to confirm destruction: " confirm1
    if [[ "$confirm1" != "DELETE" ]]; then
        print_info "Destruction cancelled"
        exit 0
    fi
    
    read -p "Are you sure? Type 'yes' to continue: " confirm2
    if [[ "$confirm2" != "yes" ]]; then
        print_info "Destruction cancelled"
        exit 0
    fi
fi

# Backup reminder
print_warning "BACKUP REMINDER:"
print_warning "Have you backed up your N8N workflows and database?"
read -p "Have you completed backups? (yes/no): " backup_confirm
if [[ "$backup_confirm" != "yes" ]]; then
    print_info "Please complete backups before destroying infrastructure"
    print_info "You can use: kubectl exec -n n8n statefulset/n8n-postgres -- pg_dump -U n8n n8n > backup.sql"
    exit 0
fi

print_info "Starting destruction process..."

# Get some info before destruction
if command -v kubectl &> /dev/null && terraform output n8n_namespace >/dev/null 2>&1; then
    namespace=$(terraform output -raw n8n_namespace 2>/dev/null || echo "n8n")
    print_info "Getting final status before destruction..."
    
    echo "Final pod status:"
    kubectl get pods -n "$namespace" 2>/dev/null || echo "Could not get pod status"
    
    echo ""
    echo "Final service status:"
    kubectl get services -n "$namespace" 2>/dev/null || echo "Could not get service status"
fi

echo ""
print_info "Running terraform destroy..."

# Destroy infrastructure
local var_file="environments/$ENVIRONMENT/terraform.tfvars"

if [[ -f "$var_file" ]]; then
    terraform destroy \
        -var-file="$var_file" \
        -auto-approve
else
    print_error "Variable file not found: $var_file"
    exit 1
fi

if [[ $? -eq 0 ]]; then
    print_success "Infrastructure destroyed successfully!"
    
    # Clean up local files
    print_info "Cleaning up local files..."
    rm -f terraform.tfplan
    rm -f terraform-*.tfplan
    rm -f backend.tf
    
    print_info "Destruction completed for environment: $ENVIRONMENT"
    echo ""
    print_warning "Note: Some resources may take additional time to be fully deleted:"
    print_warning "  - DNS records (if any) need to be manually removed"
    print_warning "  - Persistent disks snapshots may still exist"
    print_warning "  - Load balancer forwarding rules may take time to clean up"
    
    echo ""
    print_success "Environment '$ENVIRONMENT' has been successfully destroyed!"
    
else
    print_error "Destruction failed!"
    print_warning "Some resources may have been partially destroyed."
    print_warning "Check the Terraform state and GCP console for remaining resources."
    exit 1
fi