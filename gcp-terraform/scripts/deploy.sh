#!/bin/bash

# N8N GCP Terraform Deployment Script
# Usage: ./scripts/deploy.sh [environment] [action]
# Example: ./scripts/deploy.sh dev apply

set -e

# Default values
ENVIRONMENT="${1:-dev}"
ACTION="${2:-plan}"
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

# Validate action
validate_action() {
    if [[ ! "$ACTION" =~ ^(init|plan|apply|destroy|show|output)$ ]]; then
        print_error "Invalid action: $ACTION. Must be one of: init, plan, apply, destroy, show, output"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if required tools are installed
    local tools=("terraform" "gcloud" "kubectl")
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
        print_info "Please copy terraform.tfvars.example and customize it for your environment"
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
        print_warning "For production, consider setting up remote state storage."
    fi
}

# Initialize Terraform
init_terraform() {
    print_info "Initializing Terraform..."
    cd "$PROJECT_ROOT"
    terraform init
    print_success "Terraform initialized"
}

# Plan deployment
plan_deployment() {
    print_info "Planning deployment for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    local plan_file="terraform-$ENVIRONMENT.tfplan"
    
    terraform plan \
        -var-file="$var_file" \
        -out="$plan_file" \
        -detailed-exitcode
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "No changes required"
    elif [[ $exit_code -eq 2 ]]; then
        print_success "Plan created successfully: $plan_file"
    else
        print_error "Planning failed"
        exit 1
    fi
}

# Apply deployment
apply_deployment() {
    print_info "Applying deployment for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    local plan_file="terraform-$ENVIRONMENT.tfplan"
    
    # Create plan first if it doesn't exist
    if [[ ! -f "$plan_file" ]]; then
        print_info "Plan file not found, creating one..."
        terraform plan \
            -var-file="$var_file" \
            -out="$plan_file"
    fi
    
    # Apply the plan
    terraform apply "$plan_file"
    
    if [[ $? -eq 0 ]]; then
        print_success "Deployment completed successfully!"
        
        # Clean up plan file
        rm -f "$plan_file"
        
        # Show important outputs
        print_info "Important outputs:"
        terraform output n8n_url
        terraform output ingress_ip
        terraform output kubectl_config_command
        
        # Configure kubectl
        print_info "Configuring kubectl..."
        local kubectl_cmd=$(terraform output -raw kubectl_config_command)
        eval "$kubectl_cmd"
        
        print_info "Checking deployment status..."
        kubectl get pods -n $(terraform output -raw n8n_namespace)
        
        print_success "Deployment is ready!"
        print_info "N8N URL: $(terraform output -raw n8n_url)"
        print_info "Please configure your DNS to point $(terraform output -raw domain_name) to $(terraform output -raw ingress_ip)"
    else
        print_error "Deployment failed"
        exit 1
    fi
}

# Destroy infrastructure
destroy_deployment() {
    print_warning "This will destroy all resources for environment: $ENVIRONMENT"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_info "Destruction cancelled"
        exit 0
    fi
    
    print_info "Destroying infrastructure..."
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    
    terraform destroy \
        -var-file="$var_file" \
        -auto-approve
    
    if [[ $? -eq 0 ]]; then
        print_success "Infrastructure destroyed successfully"
    else
        print_error "Destruction failed"
        exit 1
    fi
}

# Show terraform state
show_state() {
    print_info "Showing Terraform state for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    terraform show
}

# Show terraform outputs
show_outputs() {
    print_info "Showing Terraform outputs for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    terraform output
}

# Main execution
main() {
    print_info "N8N GCP Terraform Deployment"
    print_info "Environment: $ENVIRONMENT"
    print_info "Action: $ACTION"
    echo ""
    
    validate_environment
    validate_action
    check_prerequisites
    setup_backend
    
    case "$ACTION" in
        init)
            init_terraform
            ;;
        plan)
            init_terraform
            plan_deployment
            ;;
        apply)
            init_terraform
            apply_deployment
            ;;
        destroy)
            init_terraform
            destroy_deployment
            ;;
        show)
            show_state
            ;;
        output)
            show_outputs
            ;;
        *)
            print_error "Unknown action: $ACTION"
            exit 1
            ;;
    esac
}

# Show usage if no arguments
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [environment] [action]"
    echo ""
    echo "Environments: dev, staging, prod"
    echo "Actions: init, plan, apply, destroy, show, output"
    echo ""
    echo "Examples:"
    echo "  $0 dev plan     - Plan development deployment"
    echo "  $0 dev apply    - Apply development deployment"
    echo "  $0 prod plan    - Plan production deployment"
    echo "  $0 prod destroy - Destroy production deployment"
    exit 1
fi

# Run main function
main