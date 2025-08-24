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
    if [[ ! "$ACTION" =~ ^(init|plan|apply|destroy|show|output|plan-infra|apply-infra|plan-apps|apply-apps)$ ]]; then
        print_error "Invalid action: $ACTION. Must be one of: init, plan, apply, destroy, show, output, plan-infra, apply-infra, plan-apps, apply-apps"
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

# Plan infrastructure only (without Kubernetes resources)
plan_infrastructure() {
    print_info "Planning infrastructure deployment for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    local plan_file="terraform-$ENVIRONMENT-infra.tfplan"
    
    # Target only infrastructure resources
    terraform plan \
        -var-file="$var_file" \
        -target=module.network \
        -target=module.gke \
        -target=google_project_service.required_apis \
        -target=random_password.postgres_password \
        -target=random_password.n8n_basic_auth_password \
        -target=random_password.n8n_encryption_key \
        -out="$plan_file" \
        -detailed-exitcode
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "No infrastructure changes required"
    elif [[ $exit_code -eq 2 ]]; then
        print_success "Infrastructure plan created successfully: $plan_file"
    else
        print_error "Infrastructure planning failed"
        exit 1
    fi
}

# Apply infrastructure only
apply_infrastructure() {
    print_info "Applying infrastructure deployment for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    local plan_file="terraform-$ENVIRONMENT-infra.tfplan"
    
    # Create infrastructure plan if it doesn't exist
    if [[ ! -f "$plan_file" ]]; then
        print_info "Infrastructure plan file not found, creating one..."
        terraform plan \
            -var-file="$var_file" \
            -target=module.network \
            -target=module.gke \
            -target=google_project_service.required_apis \
            -target=random_password.postgres_password \
            -target=random_password.n8n_basic_auth_password \
            -target=random_password.n8n_encryption_key \
            -out="$plan_file"
    fi
    
    # Apply infrastructure
    terraform apply "$plan_file"
    
    if [[ $? -eq 0 ]]; then
        print_success "Infrastructure deployment completed successfully!"
        rm -f "$plan_file"
        
        # Wait for cluster to be ready and get credentials
        print_info "Waiting for cluster to be ready and getting credentials..."
        sleep 30
        
        # Get cluster credentials with improved logic
        get_cluster_credentials_after_deployment
    else
        print_error "Infrastructure deployment failed"
        exit 1
    fi
}

# Enhanced function to get cluster credentials after deployment
get_cluster_credentials_after_deployment() {
    local cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    local project_id=$(terraform output -raw project_id 2>/dev/null || echo "")
    local region=$(terraform output -raw region 2>/dev/null || echo "")
    local zone=$(terraform output -raw zone 2>/dev/null || echo "")
    
    if [[ -n "$cluster_name" && -n "$project_id" ]]; then
        print_info "Attempting to get cluster credentials..."
        
        # Try regional cluster first (preferred)
        if [[ -n "$region" ]]; then
            if gcloud container clusters get-credentials "$cluster_name" --region="$region" --project="$project_id" 2>/dev/null; then
                print_success "Successfully connected to regional cluster: $cluster_name in $region"
            elif [[ -n "$zone" ]]; then
                # Fallback to zonal cluster using the zone from Terraform output
                print_info "Regional cluster not found, trying zonal cluster in zone: $zone"
                if gcloud container clusters get-credentials "$cluster_name" --zone="$zone" --project="$project_id" 2>/dev/null; then
                    print_success "Successfully connected to zonal cluster: $cluster_name in $zone"
                else
                    # Try common zones in the region
                    print_info "Trying common zones in region $region..."
                    for zone_suffix in "a" "b" "c"; do
                        local test_zone="${region}-${zone_suffix}"
                        print_info "Trying zone: $test_zone"
                        if gcloud container clusters get-credentials "$cluster_name" --zone="$test_zone" --project="$project_id" 2>/dev/null; then
                            print_success "Successfully connected to cluster in zone: $test_zone"
                            break
                        fi
                    done
                fi
            fi
        fi
        
        # Test cluster connectivity
        print_info "Testing cluster connectivity..."
        if kubectl cluster-info --request-timeout=30s >/dev/null 2>&1; then
            print_success "Cluster is ready for application deployment!"
            print_info "You can now run: $0 $ENVIRONMENT plan-apps"
        else
            print_warning "Cluster connectivity test failed, but infrastructure is deployed."
            print_info "The cluster might still be initializing. Try again in a few minutes."
        fi
    else
        print_warning "Could not get cluster information from Terraform outputs"
        print_info "You may need to manually run: gcloud container clusters get-credentials CLUSTER_NAME --region=REGION --project=PROJECT_ID"
    fi
}

# Plan applications (N8N and Kubernetes resources)
plan_applications() {
    print_info "Planning applications deployment for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    local plan_file="terraform-$ENVIRONMENT-apps.tfplan"
    
    # Ensure cluster credentials are available
    setup_cluster_credentials
    
    # Target only application resources
    terraform plan \
        -var-file="$var_file" \
        -target=module.n8n \
        -target=time_sleep.wait_for_cluster \
        -target=data.google_container_cluster.cluster \
        -target=null_resource.get_credentials \
        -out="$plan_file" \
        -detailed-exitcode
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "No application changes required"
    elif [[ $exit_code -eq 2 ]]; then
        print_success "Applications plan created successfully: $plan_file"
    else
        print_error "Applications planning failed"
        exit 1
    fi
}

# Apply applications
apply_applications() {
    print_info "Applying applications deployment for environment: $ENVIRONMENT"
    cd "$PROJECT_ROOT"
    
    local var_file="environments/$ENVIRONMENT/terraform.tfvars"
    local plan_file="terraform-$ENVIRONMENT-apps.tfplan"
    
    # Ensure cluster credentials are available
    setup_cluster_credentials
    
    # Create application plan if it doesn't exist
    if [[ ! -f "$plan_file" ]]; then
        print_info "Applications plan file not found, creating one..."
        terraform plan \
            -var-file="$var_file" \
            -target=module.n8n \
            -target=time_sleep.wait_for_cluster \
            -target=data.google_container_cluster.cluster \
            -target=null_resource.get_credentials \
            -out="$plan_file"
    fi
    
    # Apply applications
    terraform apply "$plan_file"
    
    if [[ $? -eq 0 ]]; then
        print_success "Applications deployment completed successfully!"
        rm -f "$plan_file"
        
        # Show important outputs
        show_deployment_info
    else
        print_error "Applications deployment failed"
        exit 1
    fi
}

# Enhanced setup cluster credentials with fallback support
setup_cluster_credentials() {
    print_info "Setting up cluster credentials..."
    
    # Try to get cluster info from Terraform state
    local cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    local project_id=$(terraform output -raw project_id 2>/dev/null || echo "")
    local region=$(terraform output -raw region 2>/dev/null || echo "")
    local zone=$(terraform output -raw zone 2>/dev/null || echo "")
    
    if [[ -n "$cluster_name" && -n "$project_id" ]]; then
        local connected=false
        
        # Try regional cluster first
        if [[ -n "$region" ]]; then
            print_info "Trying to connect to regional cluster: $cluster_name in $region"
            if gcloud container clusters get-credentials "$cluster_name" --region="$region" --project="$project_id" 2>/dev/null; then
                print_success "Connected to regional cluster"
                connected=true
            else
                print_info "Regional cluster connection failed, trying zonal clusters..."
                
                # Try zone from terraform output first
                if [[ -n "$zone" ]]; then
                    print_info "Trying zone from Terraform output: $zone"
                    if gcloud container clusters get-credentials "$cluster_name" --zone="$zone" --project="$project_id" 2>/dev/null; then
                        print_success "Connected to zonal cluster in $zone"
                        connected=true
                    fi
                fi
                
                # Try common zones in the region if not connected yet
                if [[ "$connected" == false ]]; then
                    for zone_suffix in "a" "b" "c"; do
                        local test_zone="${region}-${zone_suffix}"
                        print_info "Trying zone: $test_zone"
                        if gcloud container clusters get-credentials "$cluster_name" --zone="$test_zone" --project="$project_id" 2>/dev/null; then
                            print_success "Connected to zonal cluster in $test_zone"
                            connected=true
                            break
                        fi
                    done
                fi
            fi
        fi
        
        if [[ "$connected" == true ]]; then
            # Test connectivity
            if ! kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
                print_warning "Cluster connectivity test failed. Cluster might still be initializing."
                print_info "Waiting 60 seconds for cluster to be ready..."
                sleep 60
                
                # Test again
                if ! kubectl cluster-info --request-timeout=30s >/dev/null 2>&1; then
                    print_warning "Cluster still not responding. Proceeding anyway..."
                fi
            fi
        else
            print_error "Could not connect to cluster. Make sure infrastructure is deployed first."
            print_info "Run: $0 $ENVIRONMENT apply-infra"
            exit 1
        fi
    else
        print_error "Could not get cluster information. Make sure infrastructure is deployed first."
        print_info "Run: $0 $ENVIRONMENT apply-infra"
        exit 1
    fi
}

# Show deployment information
show_deployment_info() {
    print_info "Deployment Information:"
    echo ""
    
    # Show important outputs
    terraform output n8n_url 2>/dev/null || echo "N8N URL: Not available"
    terraform output ingress_ip 2>/dev/null || echo "Ingress IP: Not available"
    
    # Check pod status
    local namespace=$(terraform output -raw n8n_namespace 2>/dev/null || echo "n8n")
    print_info "Checking deployment status..."
    kubectl get pods -n "$namespace" || echo "Could not get pod status"
    
    echo ""
    print_success "Deployment completed!"
    
    local n8n_url=$(terraform output -raw n8n_url 2>/dev/null || echo "")
    local ingress_ip=$(terraform output -raw ingress_ip 2>/dev/null || echo "")
    local domain_name=$(terraform output -raw domain_name 2>/dev/null || echo "")
    
    if [[ -n "$n8n_url" ]]; then
        print_info "N8N URL: $n8n_url"
    fi
    
    if [[ -n "$domain_name" && -n "$ingress_ip" ]]; then
        print_info "Configure your DNS: $domain_name -> $ingress_ip"
    fi
}

# Plan full deployment
plan_deployment() {
    print_info "Planning full deployment for environment: $ENVIRONMENT"
    print_warning "This may fail if the cluster doesn't exist yet. Consider using plan-infra first."
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
        print_info "Try running: $0 $ENVIRONMENT plan-infra"
        exit 1
    fi
}

# Apply full deployment
apply_deployment() {
    print_info "Applying full deployment for environment: $ENVIRONMENT"
    print_info "This will deploy infrastructure first, then applications."
    
    # Deploy infrastructure first
    apply_infrastructure
    
    # Then deploy applications
    print_info "Now deploying applications..."
    sleep 10
    apply_applications
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
        plan-infra)
            init_terraform
            plan_infrastructure
            ;;
        apply-infra)
            init_terraform
            apply_infrastructure
            ;;
        plan-apps)
            init_terraform
            plan_applications
            ;;
        apply-apps)
            init_terraform
            apply_applications
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
    echo "         plan-infra, apply-infra, plan-apps, apply-apps"
    echo ""
    echo "Staged deployment (recommended):"
    echo "  $0 dev plan-infra   - Plan infrastructure only"
    echo "  $0 dev apply-infra  - Deploy infrastructure (GKE cluster)"
    echo "  $0 dev plan-apps    - Plan applications (N8N)"
    echo "  $0 dev apply-apps   - Deploy applications"
    echo ""
    echo "Full deployment:"
    echo "  $0 dev plan         - Plan everything (may fail if cluster doesn't exist)"
    echo "  $0 dev apply        - Deploy everything (staged automatically)"
    echo ""
    echo "Other actions:"
    echo "  $0 dev output       - Show outputs"
    echo "  $0 dev destroy      - Destroy everything"
    exit 1
fi

# Run main function
main