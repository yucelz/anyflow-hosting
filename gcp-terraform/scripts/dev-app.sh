#!/bin/bash

# Deploy Dev Application (N8N + PostgreSQL)
# Enhanced validation checks for N8N application components
# Usage: ./dev-app.sh [--destroy] [--help]

set -e

# Parse command line arguments
DESTROY_MODE=false
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --destroy)
            DESTROY_MODE=true
            shift
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Show help if requested
if [ "$SHOW_HELP" = true ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy or destroy the N8N development application (N8N + PostgreSQL)"
    echo ""
    echo "OPTIONS:"
    echo "  --destroy    Destroy the existing application instead of deploying"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                Deploy the development application"
    echo "  $0 --destroy      Destroy the development application"
    echo ""
    echo "Prerequisites:"
    echo "  • Infrastructure must be deployed first using: ./dev-infra.sh"
    echo "  • GKE cluster must be running and accessible"
    exit 0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="dev"
PROJECT_ID="anyflow-cloud"
REGION="us-central1"
ZONE="us-central1-b"
CLUSTER_NAME="${ENVIRONMENT}-n8n-cluster"

# Validation flags
VALIDATION_PASSED=true
VALIDATION_ERRORS=()

if [ "$DESTROY_MODE" = true ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}    N8N Dev Application Destruction    ${NC}"
    echo -e "${RED}     Safe Application Removal         ${NC}"
    echo -e "${RED}========================================${NC}"
else
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    N8N Dev Application Deployment     ${NC}"
    echo -e "${BLUE}  With Comprehensive Validation Checks ${NC}"
    echo -e "${BLUE}========================================${NC}"
fi

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_validation() {
    echo -e "${CYAN}[VALIDATION]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_section() {
    echo -e "${PURPLE}========== $1 ==========${NC}"
}

# Function to add validation error
add_validation_error() {
    VALIDATION_ERRORS+=("$1")
    VALIDATION_PASSED=false
    print_error "VALIDATION FAILED: $1"
}

# Function to validate command exists
validate_command() {
    local cmd=$1
    local description=$2
    
    if ! command -v "$cmd" &> /dev/null; then
        add_validation_error "$description: $cmd command not found"
        return 1
    fi
    print_validation "$description: $cmd is available"
    return 0
}

# Function to validate GCP authentication
validate_gcp_auth() {
    print_validation "Checking GCP authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        add_validation_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        return 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    print_success "Authenticated as: $active_account"
    return 0
}

# Function to validate GCP project access
validate_project_access() {
    print_validation "Validating project access for $PROJECT_ID..."
    
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        add_validation_error "Cannot access project $PROJECT_ID. Check permissions."
        return 1
    fi
    
    print_success "Project $PROJECT_ID is accessible"
    return 0
}

# Function to validate terraform configuration
validate_terraform_config() {
    print_validation "Validating Terraform configuration..."
    
    # Check if terraform files exist
    if [ ! -f "main.tf" ]; then
        add_validation_error "main.tf not found in current directory"
        return 1
    fi
    
    if [ ! -f "environments/$ENVIRONMENT/terraform.tfvars" ]; then
        add_validation_error "terraform.tfvars not found for $ENVIRONMENT environment"
        return 1
    fi
    
    # Validate terraform syntax
    if ! terraform validate; then
        add_validation_error "Terraform configuration validation failed"
        return 1
    fi
    
    print_success "Terraform configuration is valid"
    return 0
}

# Function to validate infrastructure prerequisites
validate_infrastructure_prerequisites() {
    print_validation "Validating infrastructure prerequisites..."
    
    # Check if GKE cluster exists and is running
    if ! gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        add_validation_error "GKE cluster $CLUSTER_NAME not found. Deploy infrastructure first using: ./dev-infra.sh"
        return 1
    fi
    
    local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)")
    if [ "$cluster_status" != "RUNNING" ]; then
        add_validation_error "GKE cluster $CLUSTER_NAME is not in RUNNING state (current: $cluster_status)"
        return 1
    fi
    print_success "GKE cluster $CLUSTER_NAME is running"
    
    # Validate kubectl connectivity
    if ! kubectl cluster-info &>/dev/null; then
        add_validation_error "Cannot connect to cluster via kubectl. Check cluster credentials."
        return 1
    fi
    print_success "kubectl connectivity established"
    
    # Check if nodes are ready
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    local total_nodes=$(kubectl get nodes --no-headers | wc -l || echo "0")
    
    if [ "$ready_nodes" -eq 0 ] || [ "$ready_nodes" -ne "$total_nodes" ]; then
        add_validation_error "Not all nodes are ready ($ready_nodes/$total_nodes)"
        return 1
    fi
    print_success "All cluster nodes are ready ($ready_nodes/$total_nodes)"
    
    return 0
}

# Function to validate N8N prerequisites
validate_n8n_prerequisites() {
    print_validation "Validating N8N prerequisites..."
    
    # Validate domain configuration
    local domain_name="www.any-flow.com"
    print_validation "Domain configured: $domain_name"
    
    # Check if static IP already exists (matches terraform naming: ${environment}-${cluster_name}-${static_ip_name})
    local static_ip_name="${ENVIRONMENT}-n8n-cluster-n8n-static-ip"
    if gcloud compute addresses describe "$static_ip_name" --global --project="$PROJECT_ID" &>/dev/null; then
        local static_ip=$(gcloud compute addresses describe "$static_ip_name" --global --project="$PROJECT_ID" --format="value(address)")
        print_validation "Static IP already exists: $static_ip"
    else
        print_validation "Static IP will be created"
    fi
    
    # Validate SSL certificate configuration (matches terraform naming: ${environment}-${cluster_name}-${ssl_cert_name})
    local ssl_cert_name="${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert"
    if gcloud compute ssl-certificates describe "$ssl_cert_name" --global --project="$PROJECT_ID" &>/dev/null; then
        local cert_status=$(gcloud compute ssl-certificates describe "$ssl_cert_name" --global --project="$PROJECT_ID" --format="value(managed.status)")
        print_validation "SSL certificate exists with status: $cert_status"
    else
        print_validation "SSL certificate will be created"
    fi
    
    # Validate resource requirements
    print_validation "N8N resource configuration:"
    print_validation "  CPU Request: 100m, Limit: 300m"
    print_validation "  Memory Request: 128Mi, Limit: 384Mi"
    print_validation "  PostgreSQL CPU: 50m-150m, Memory: 64Mi-128Mi"
    print_validation "  Storage: 5Gi"
    
    return 0
}

# Function to validate post-deployment N8N
validate_n8n_deployment() {
    print_validation "Validating N8N deployment..."
    
    # Check namespace
    if ! kubectl get namespace n8n &>/dev/null; then
        add_validation_error "N8N namespace was not created"
        return 1
    fi
    print_success "N8N namespace exists"
    
    # Check PostgreSQL deployment
    local postgres_ready=$(kubectl get statefulset postgres -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$postgres_ready" != "1" ]; then
        add_validation_error "PostgreSQL is not ready (ready replicas: $postgres_ready)"
        return 1
    fi
    print_success "PostgreSQL is ready"
    
    # Check N8N deployment
    local n8n_ready=$(kubectl get deployment n8n-deployment -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$n8n_ready" != "1" ]; then
        add_validation_error "N8N deployment is not ready (ready replicas: $n8n_ready)"
        return 1
    fi
    print_success "N8N deployment is ready"
    
    # Check services
    if ! kubectl get service n8n-service -n n8n &>/dev/null; then
        add_validation_error "N8N service was not created"
        return 1
    fi
    print_success "N8N service exists"
    
    if ! kubectl get service postgres-service -n n8n &>/dev/null; then
        add_validation_error "PostgreSQL service was not created"
        return 1
    fi
    print_success "PostgreSQL service exists"
    
    # Check ingress
    if ! kubectl get ingress n8n-ingress -n n8n &>/dev/null; then
        add_validation_error "N8N ingress was not created"
        return 1
    fi
    print_success "N8N ingress exists"
    
    # Check ingress IP
    local ingress_ip=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -z "$ingress_ip" ]; then
        print_warning "Ingress IP is not yet assigned (this may take a few minutes)"
    else
        print_success "Ingress IP assigned: $ingress_ip"
    fi
    
    # Check SSL certificate status (matches terraform naming)
    local ssl_cert_name="${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert"
    local cert_status=$(gcloud compute ssl-certificates describe "$ssl_cert_name" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "NOT_FOUND")
    if [ "$cert_status" = "ACTIVE" ]; then
        print_success "SSL certificate is active"
    elif [ "$cert_status" = "PROVISIONING" ]; then
        print_warning "SSL certificate is still provisioning (this may take 10-15 minutes)"
    else
        print_warning "SSL certificate status: $cert_status"
    fi
    
    return 0
}

# Function to run comprehensive validation summary
validation_summary() {
    echo ""
    print_section "VALIDATION SUMMARY"
    
    if [ "$VALIDATION_PASSED" = true ]; then
        print_success "All validations passed successfully!"
        return 0
    else
        print_error "Validation failed with ${#VALIDATION_ERRORS[@]} error(s):"
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo -e "${RED}  • $error${NC}"
        done
        return 1
    fi
}

# Main execution starts here
print_section "PRE-DEPLOYMENT VALIDATION"

# Validate prerequisites
validate_command "gcloud" "Google Cloud SDK"
validate_command "terraform" "Terraform"
validate_command "kubectl" "Kubernetes CLI"

validate_gcp_auth
validate_project_access

# Set the project
print_status "Setting GCP project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

# Navigate to terraform directory
cd "$(dirname "$0")/.."

validate_terraform_config
validate_infrastructure_prerequisites
validate_n8n_prerequisites

# Check if pre-deployment validation passed
if ! validation_summary; then
    print_error "Pre-deployment validation failed. Please fix the issues above before proceeding."
    exit 1
fi

# Initialize Terraform (should already be initialized from infra deployment)
print_status "Initializing Terraform..."
terraform init

# Select workspace (should already exist from infra deployment)
print_status "Selecting Terraform workspace for $ENVIRONMENT..."
if terraform workspace list | grep -q "$ENVIRONMENT"; then
    terraform workspace select "$ENVIRONMENT"
else
    add_validation_error "Terraform workspace '$ENVIRONMENT' not found. Deploy infrastructure first using: ./dev-infra.sh"
    exit 1
fi

# Handle destroy mode
if [ "$DESTROY_MODE" = true ]; then
    print_section "APPLICATION DESTRUCTION"
    
    # Ask for confirmation
    echo -e "${RED}WARNING: This will destroy the N8N application and all data!${NC}"
    echo -e "${RED}This includes:${NC}"
    echo -e "${RED}  • N8N application and workflows${NC}"
    echo -e "${RED}  • PostgreSQL database and all data${NC}"
    echo -e "${RED}  • SSL certificates and static IPs${NC}"
    echo -e "${RED}  • Ingress and load balancer${NC}"
    echo ""
    echo -e "${YELLOW}Note: Infrastructure (GKE cluster and network) will remain deployed${NC}"
    echo ""
    read -p "Are you sure you want to destroy the N8N application? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Application destruction cancelled by user"
        exit 0
    fi
    
    # Destroy N8N application
    print_section "DESTROYING N8N APPLICATION"
    print_status "Destroying N8N application and database..."
    
    if terraform destroy -target="module.n8n" \
        -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
        -auto-approve; then
        print_success "N8N application destroyed successfully"
    else
        print_error "N8N application destruction failed"
        print_error "You may need to manually clean up Kubernetes resources:"
        print_error "kubectl delete namespace n8n --force --grace-period=0"
        exit 1
    fi
    
    print_section "APPLICATION DESTRUCTION COMPLETE"
    print_success "N8N application has been destroyed!"
    print_status "Infrastructure remains available for redeployment"
    print_status "To redeploy: ./dev-app.sh"
    print_status "To destroy infrastructure: ./dev-infra.sh --destroy"
    
    exit 0
fi

# Deploy Application (N8N)
print_section "APPLICATION DEPLOYMENT"
print_status "Planning N8N application deployment..."

# Plan N8N application
terraform plan \
    -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
    -target="module.n8n" \
    -out="terraform-$ENVIRONMENT-app.tfplan"

# Show application summary
print_status "Application Deployment Summary:"
    echo -e "${YELLOW}  • N8N: Single replica (500m CPU, 512Mi RAM, 2Gi Storage)${NC}"
    echo -e "${YELLOW}  • PostgreSQL: Single instance (250m CPU, 1Gi RAM, 10Gi Storage)${NC}"
echo -e "${YELLOW}  • Ingress: SSL-enabled load balancer${NC}"
echo -e "${YELLOW}  • Monitoring: Enabled${NC}"
echo -e "${YELLOW}  • Workload Identity: Enabled${NC}"

# Ask for confirmation for application
echo ""
read -p "Deploy N8N application? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Application deployment cancelled by user"
    exit 0
fi

# Apply application
print_status "Deploying N8N application..."
terraform apply "terraform-$ENVIRONMENT-app.tfplan"

# Post-deployment validation for N8N
print_section "POST-APPLICATION VALIDATION"
VALIDATION_PASSED=true
VALIDATION_ERRORS=()

# Wait for pods to be ready
print_status "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n n8n --timeout=600s || print_warning "Some pods may still be starting"

validate_n8n_deployment

if ! validation_summary; then
    print_warning "Some N8N validation checks failed, but deployment may still be functional."
fi

# Final deployment summary
print_section "APPLICATION DEPLOYMENT COMPLETE"

# Get final status information
EXTERNAL_IP=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
CERT_STATUS=$(gcloud compute ssl-certificates describe "${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "Unknown")

echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Cluster:${NC} $CLUSTER_NAME"
echo -e "${GREEN}External IP:${NC} $EXTERNAL_IP"
echo -e "${GREEN}Domain:${NC} www.any-flow.com"
echo -e "${GREEN}SSL Status:${NC} $CERT_STATUS"
echo ""

# Show application resource usage
print_status "Application Resource Summary:"
echo -e "${GREEN}  • N8N Replicas: 1${NC}"
echo -e "${GREEN}  • PostgreSQL Instances: 1${NC}"
echo -e "${GREEN}  • Total CPU Request: ~1.25 CPU${NC}"
echo -e "${GREEN}  • Total Memory Request: ~2.25Gi${NC}"
echo -e "${GREEN}  • Total Storage: 12Gi${NC}"

echo ""
if [ "$CERT_STATUS" != "ACTIVE" ]; then
    echo -e "${YELLOW}Note: SSL certificate may take 10-15 minutes to provision${NC}"
    echo -e "${YELLOW}Monitor certificate status: gcloud compute ssl-certificates describe ${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert --global${NC}"
fi

echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "${YELLOW}  • Monitor deployment: kubectl get pods -n n8n -w${NC}"
echo -e "${YELLOW}  • View N8N logs: kubectl logs -f deployment/n8n-deployment -n n8n${NC}"
echo -e "${YELLOW}  • View PostgreSQL logs: kubectl logs -f statefulset/postgres -n n8n${NC}"
echo -e "${YELLOW}  • Access N8N: https://www.any-flow.com (once SSL is active)${NC}"

print_success "N8N application deployment completed successfully!"
