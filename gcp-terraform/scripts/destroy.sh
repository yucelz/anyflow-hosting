#!/bin/bash

# N8N GCP Terraform Destruction Script
# Usage: ./scripts/destroy.sh [environment] [target]
# Example: ./scripts/destroy.sh dev
# Example: ./scripts/destroy.sh dev apps (destroy only applications)
# Example: ./scripts/destroy.sh dev infra (destroy only infrastructure)

set -e

# Default values
ENVIRONMENT="${1:-dev}"
TARGET="${2:-all}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
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
validate_environment() {
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        print_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
        exit 1
    fi
}

# Validate target
validate_target() {
    if [[ ! "$TARGET" =~ ^(all|apps|infra)$ ]]; then
        print_error "Invalid target: $TARGET. Must be one of: all, apps, infra"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if required tools are installed
    local tools=("terraform" "gcloud")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "Please authenticate with gcloud: gcloud auth login"
        exit 1
    fi
    
    # Check if environment config exists
    local env_dir="$PROJECT_ROOT/environments/$ENVIRONMENT"
    if [[ ! -d "$env_dir" ]]; then
        print_error "Environment directory not found: $env_dir"
        exit 1
    fi
    
    if [[ ! -f "$env_dir/terraform.tfvars" ]]; then
        print_error "terraform.tfvars not found in $env_dir"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Setup Terraform backend
setup_backend() {
    local env_dir="$PROJECT_ROOT/environments/$ENVIRONMENT"
    local backend_file="$env_dir/backend.tf"
    
    if [[ -f "$backend_file" ]]; then
        print_info "Using custom backend configuration from $backend_file"
        cp "$backend_file" "$PROJECT_ROOT/backend.tf"
    else
        print_warning "No backend configuration found. Using local state."
    fi
}

# Initialize Terraform
init_terraform() {
    print_info "Initializing Terraform..."
    cd "$PROJECT_ROOT"
    terraform init
    print_success "Terraform initialized"
}

# Check if terraform state exists
check_terraform_state() {
    if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
        # Check for remote state
        if ! terraform show >/dev/null 2>&1; then
            print_error "Terraform state not found. Nothing to destroy."
            exit 1
        fi
    fi
}

# Show current resources
show_current_resources() {
    print_info "Current resources in environment '$ENVIRONMENT':"
    local resources=$(terraform show -no-color 2>/dev/null | grep -E "^resource|^data" || echo "")
    
    if [[ -n "$resources" ]]; then
        echo "$resources" | head -10
        local total_count=$(echo "$resources" | wc -l)
        if [[ $total_count -gt 10 ]]; then
            echo "... and $(( total_count - 10 )) more resources"
        fi
    else
        echo "No resources found or unable to read state"
    fi
    echo ""
}

# Get backup status information
show_backup_info() {
    print_info "Getting current deployment status for backup purposes..."
    
    if command -v kubectl &> /dev/null && terraform output n8n_namespace >/dev/null 2>&1; then
        local namespace=$(terraform output -raw n8n_namespace 2>/dev/null || echo "n8n")
        
        echo "Current pod status:"
        kubectl get pods -n "$namespace" 2>/dev/null || echo "Could not get pod status"
        
        echo ""
        echo "Current service status:"
        kubectl get services -n "$namespace" 2>/dev/null || echo "Could not get service status"
        
        echo ""
        echo "Current persistent volumes:"
        kubectl get pv 2>/dev/null | grep "$namespace" || echo "Could not get persistent volume status"
    fi
}

# Confirm destruction
confirm_destruction() {
    print_warning "=== DESTRUCTION WARNING ==="
    print_warning "This will PERMANENTLY DESTROY resources for environment: $ENVIRONMENT"
    
    case "$TARGET" in
        all)
            print_warning "This includes:"
            print_warning "  - GKE cluster and all workloads"
            print_warning "  - PostgreSQL database and ALL DATA"
            print_warning "  - Static IP addresses"
            print_warning "  - SSL certificates"
            print_warning "  - VPC network and subnets"
            print_warning "  - All N8N workflows and configurations"
            ;;
        apps)
            print_warning "This includes:"
            print_warning "  - N8N application and all workflows"
            print_warning "  - PostgreSQL database and ALL DATA"
            print_warning "  - Application secrets and configs"
            print_warning "  - Ingress and SSL certificates"
            ;;
        infra)
            print_warning "This includes:"
            print_warning "  - GKE cluster (this will also destroy applications)"
            print_warning "  - VPC network and subnets"
            print_warning "  - Static IP addresses"
            print_warning "  - All cluster resources"
            ;;
    esac
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
    
    # Backup reminder for data-containing targets
    if [[ "$TARGET" == "all" || "$TARGET" == "apps" ]]; then
        print_warning "BACKUP REMINDER:"
        print_warning "Have you backed up your N8N workflows and database?"
        print_info "You can use: kubectl exec -n n8n deployment/n8n-postgres -- pg_dump -U n8n n8n > backup.sql"
        read -p "Have you completed backups? (yes/no): " backup_confirm
        if [[ "$backup_confirm" != "yes" ]]; then
            print_info "Please complete backups before destroying infrastructure"
            exit 0
        fi
    fi
}

# Destroy applications only
destroy_applications() {
    print_info "Destroying applications for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    
    # Get cluster credentials if available
    setup_cluster_credentials_if_available
    
    # Target only application resources
    terraform destroy \
        -var-file="$var_file" \
        -target=module.n8n \
        -target=time_sleep.wait_for_cluster \
        -auto-approve
    
    if [[ $? -eq 0 ]]; then
        print_success "Applications destroyed successfully!"
        
        # Clean up application-specific plan files
        rm -f terraform-*-apps.tfplan
    else
        print_error "Applications destruction failed"
        exit 1
    fi
}

# Destroy infrastructure only  
destroy_infrastructure() {
    print_info "Destroying infrastructure for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    
    # Target only infrastructure resources
    terraform destroy \
        -var-file="$var_file" \
        -target=module.network \
        -target=module.gke \
        -target=google_project_service.required_apis \
        -target=random_password.postgres_password \
        -target=random_password.n8n_basic_auth_password \
        -target=random_password.n8n_encryption_key \
        -target=data.google_container_cluster.cluster \
        -target=null_resource.get_credentials \
        -auto-approve
    
    if [[ $? -eq 0 ]]; then
        print_success "Infrastructure destroyed successfully!"
        
        # Clean up infrastructure-specific plan files
        rm -f terraform-*-infra.tfplan
    else
        print_error "Infrastructure destruction failed"
        exit 1
    fi
}

# Destroy everything
destroy_all() {
    print_info "Destroying all resources for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    
    # Get cluster credentials if available for final status
    setup_cluster_credentials_if_available
    
    terraform destroy \
        -var-file="$var_file" \
        -auto-approve
    
    if [[ $? -eq 0 ]]; then
        print_success "All resources destroyed successfully!"
        cleanup_local_files
    else
        print_error "Destruction failed!"
        print_warning "Some resources may have been partially destroyed."
        print_warning "Check the Terraform state and GCP console for remaining resources."
        exit 1
    fi
}

# Setup cluster credentials if available (non-failing)
setup_cluster_credentials_if_available() {
    # Try to get cluster info from Terraform state (don't fail if not available)
    local cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    local project_id=$(terraform output -raw project_id 2>/dev/null || echo "")
    local region=$(terraform output -raw region 2>/dev/null || echo "")
    
    if [[ -n "$cluster_name" && -n "$project_id" && -n "$region" ]]; then
        if command -v kubectl &> /dev/null; then
            gcloud container clusters get-credentials "$cluster_name" --region="$region" --project="$project_id" >/dev/null 2>&1 || true
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    print_info "Cleaning up local files..."
    rm -f terraform.tfplan
    rm -f terraform-*.tfplan
    rm -f backend.tf
    
    print_success "Local files cleaned up"
}

# Show post-destruction information
show_post_destruction_info() {
    echo ""
    print_success "Environment '$ENVIRONMENT' destruction completed!"
    
    case "$TARGET" in
        all)
            print_warning "Note: Some resources may take additional time to be fully deleted:"
            print_warning "  - DNS records (if any) need to be manually removed"
            print_warning "  - Persistent disk snapshots may still exist"
            print_warning "  - Load balancer forwarding rules may take time to clean up"
            print_warning "  - GCP project quotas may take time to reset"
            ;;
        apps)
            print_info "Applications have been destroyed. Infrastructure remains available."
            print_info "You can redeploy applications with: ./scripts/deploy.sh $ENVIRONMENT apply-apps"
            ;;
        infra)
            print_info "Infrastructure has been destroyed. This includes any applications."
            print_info "You can redeploy everything with: ./scripts/deploy.sh $ENVIRONMENT apply"
            ;;
    esac
}

# Main execution
main() {
    print_info "N8N GCP Terraform Destruction"
    print_info "Environment: $ENVIRONMENT"
    print_info "Target: $TARGET"
    echo ""
    
    validate_environment
    validate_target
    check_prerequisites
    setup_backend
    init_terraform
    check_terraform_state
    show_current_resources
    show_backup_info
    confirm_destruction
    
    print_info "Starting destruction process..."
    
    case "$TARGET" in
        all)
            destroy_all
            ;;
        apps)
            destroy_applications
            ;;
        infra)
            destroy_infrastructure
            ;;
        *)
            print_error "Unknown target: $TARGET"
            exit 1
            ;;
    esac
    
    show_post_destruction_info
}

# Show usage if no arguments or help requested
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: $0 [environment] [target]"
    echo ""
    echo "Environments: dev, staging, prod"
    echo "Targets: all, apps, infra (default: all)"
    echo ""
    echo "Examples:"
    echo "  $0 dev              # Destroy everything in dev environment"
    echo "  $0 dev all          # Destroy everything in dev environment"
    echo "  $0 dev apps         # Destroy only applications (keep infrastructure)"
    echo "  $0 dev infra        # Destroy only infrastructure (includes applications)"
    echo ""
    echo "Staged destruction (recommended for production):"
    echo "  $0 prod apps        # First destroy applications"
    echo "  $0 prod infra       # Then destroy infrastructure"
    echo ""
    echo "Note: Infrastructure destruction will also destroy applications"
    echo "      since applications depend on the cluster."
    exit 1
fi

# Run main function
main