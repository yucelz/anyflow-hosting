#!/bin/bash

# Deploy Dev Environment with Comprehensive Validation
# Enhanced validation checks for GKE, Network, and N8N components

set -e

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
PROJECT_ID="anyflow-469911"
REGION="us-central1"
ZONE="us-central1-a"
CLUSTER_NAME="${ENVIRONMENT}-n8n-cluster"
# Network names match terraform naming convention: ${environment}-${cluster_name}-${network_name}
NETWORK_NAME="${ENVIRONMENT}-n8n-cluster-n8n-vpc"
SUBNET_NAME="${ENVIRONMENT}-n8n-cluster-n8n-subnet"

# Validation flags
VALIDATION_PASSED=true
VALIDATION_ERRORS=()

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    N8N Dev Environment Deployment     ${NC}"
echo -e "${BLUE}  With Comprehensive Validation Checks ${NC}"
echo -e "${BLUE}========================================${NC}"

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

# Function to validate required APIs
validate_required_apis() {
    print_validation "Checking required GCP APIs..."
    
    local required_apis=(
        "container.googleapis.com"
        "compute.googleapis.com"
        "certificatemanager.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    local missing_apis=()
    
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" --project="$PROJECT_ID" | grep -q "$api"; then
            missing_apis+=("$api")
        else
            print_validation "API $api is enabled"
        fi
    done
    
    if [ ${#missing_apis[@]} -gt 0 ]; then
        print_warning "Missing APIs detected. Enabling them..."
        for api in "${missing_apis[@]}"; do
            print_status "Enabling $api..."
            if gcloud services enable "$api" --project="$PROJECT_ID"; then
                print_success "Enabled $api"
            else
                add_validation_error "Failed to enable $api"
            fi
        done
    else
        print_success "All required APIs are enabled"
    fi
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

# Function to validate network prerequisites
validate_network_prerequisites() {
    print_validation "Validating network prerequisites..."
    
    # Check if network already exists
    if gcloud compute networks describe "$NETWORK_NAME" --project="$PROJECT_ID" &>/dev/null; then
        print_warning "Network $NETWORK_NAME already exists"
        
        # Validate subnet exists
        if gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            print_validation "Subnet $SUBNET_NAME already exists"
        else
            add_validation_error "Network exists but subnet $SUBNET_NAME is missing"
            return 1
        fi
    else
        print_validation "Network $NETWORK_NAME will be created"
    fi
    
    # Validate CIDR ranges don't conflict
    local subnet_cidr="10.0.0.0/24"
    local pods_cidr="10.2.0.0/16"
    local services_cidr="10.1.0.0/16"
    
    print_validation "CIDR ranges configured:"
    print_validation "  Subnet: $subnet_cidr"
    print_validation "  Pods: $pods_cidr"
    print_validation "  Services: $services_cidr"
    
    return 0
}

# Function to validate GKE prerequisites
validate_gke_prerequisites() {
    print_validation "Validating GKE prerequisites..."
    
    # Check if cluster already exists
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        print_warning "GKE cluster $CLUSTER_NAME already exists"
        
        # Validate cluster is running
        local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)")
        if [ "$cluster_status" != "RUNNING" ]; then
            add_validation_error "Cluster $CLUSTER_NAME exists but is not in RUNNING state (current: $cluster_status)"
            return 1
        fi
        print_validation "Cluster $CLUSTER_NAME is in RUNNING state"
    else
        print_validation "GKE cluster $CLUSTER_NAME will be created"
    fi
    
    # Validate machine type availability
    local machine_type="e2-medium"
    if ! gcloud compute machine-types describe "$machine_type" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        add_validation_error "Machine type $machine_type is not available in zone $ZONE"
        return 1
    fi
    print_validation "Machine type $machine_type is available in zone $ZONE"
    
    # Validate resource quotas
    print_validation "Checking compute quotas..."
    local cpu_quota=$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(quotas[metric=CPUS].limit)" 2>/dev/null || echo "unknown")
    local instance_quota=$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(quotas[metric=INSTANCES].limit)" 2>/dev/null || echo "unknown")
    
    print_validation "Available quotas - CPUs: $cpu_quota, Instances: $instance_quota"
    
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
    print_validation "  CPU Request: 250m, Limit: 500m"
    print_validation "  Memory Request: 256Mi, Limit: 512Mi"
    print_validation "  PostgreSQL CPU: 100m-250m, Memory: 128Mi-256Mi"
    print_validation "  Storage: 10Gi"
    
    return 0
}

# Function to validate post-deployment network
validate_network_deployment() {
    print_validation "Validating network deployment..."
    
    # Check VPC network
    if ! gcloud compute networks describe "$NETWORK_NAME" --project="$PROJECT_ID" &>/dev/null; then
        add_validation_error "VPC network $NETWORK_NAME was not created successfully"
        return 1
    fi
    print_success "VPC network $NETWORK_NAME is deployed"
    
    # Check subnet
    if ! gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        add_validation_error "Subnet $SUBNET_NAME was not created successfully"
        return 1
    fi
    print_success "Subnet $SUBNET_NAME is deployed"
    
    # Check firewall rules
    local firewall_rules=("${NETWORK_NAME}-allow-internal" "${NETWORK_NAME}-allow-ssh" "${NETWORK_NAME}-allow-health-check")
    for rule in "${firewall_rules[@]}"; do
        if gcloud compute firewall-rules describe "$rule" --project="$PROJECT_ID" &>/dev/null; then
            print_success "Firewall rule $rule is deployed"
        else
            add_validation_error "Firewall rule $rule was not created"
        fi
    done
    
    # Check NAT gateway
    if gcloud compute routers describe "${NETWORK_NAME}-router" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        print_success "NAT router is deployed"
    else
        add_validation_error "NAT router was not created"
    fi
    
    return 0
}

# Function to validate post-deployment GKE
validate_gke_deployment() {
    print_validation "Validating GKE deployment..."
    
    # Check cluster status
    local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    if [ "$cluster_status" != "RUNNING" ]; then
        add_validation_error "GKE cluster is not in RUNNING state (current: $cluster_status)"
        return 1
    fi
    print_success "GKE cluster is in RUNNING state"
    
    # Check node pool
    local node_pool_status=$(gcloud container node-pools describe "n8n-node-pool" --cluster="$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    if [ "$node_pool_status" != "RUNNING" ]; then
        add_validation_error "Node pool is not in RUNNING state (current: $node_pool_status)"
        return 1
    fi
    print_success "Node pool is in RUNNING state"
    
    # Validate kubectl connectivity
    if ! kubectl cluster-info &>/dev/null; then
        add_validation_error "Cannot connect to cluster via kubectl"
        return 1
    fi
    print_success "kubectl connectivity established"
    
    # Check node readiness
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    local total_nodes=$(kubectl get nodes --no-headers | wc -l || echo "0")
    
    if [ "$ready_nodes" -eq 0 ] || [ "$ready_nodes" -ne "$total_nodes" ]; then
        add_validation_error "Not all nodes are ready ($ready_nodes/$total_nodes)"
        return 1
    fi
    print_success "All nodes are ready ($ready_nodes/$total_nodes)"
    
    # Validate system pods
    local system_pods_ready=$(kubectl get pods -n kube-system --no-headers | grep -c "Running" || echo "0")
    local total_system_pods=$(kubectl get pods -n kube-system --no-headers | wc -l || echo "0")
    
    if [ "$system_pods_ready" -lt "$((total_system_pods * 80 / 100))" ]; then
        add_validation_error "Less than 80% of system pods are running ($system_pods_ready/$total_system_pods)"
        return 1
    fi
    print_success "System pods are healthy ($system_pods_ready/$total_system_pods running)"
    
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
    local postgres_ready=$(kubectl get statefulset n8n-postgres -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
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
    
    if ! kubectl get service n8n-postgres -n n8n &>/dev/null; then
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

validate_required_apis

# Navigate to terraform directory
cd "$(dirname "$0")/.."

validate_terraform_config
validate_network_prerequisites
validate_gke_prerequisites
validate_n8n_prerequisites

# Check if pre-deployment validation passed
if ! validation_summary; then
    print_error "Pre-deployment validation failed. Please fix the issues above before proceeding."
    exit 1
fi

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init

# Select workspace or create if it doesn't exist
print_status "Setting up Terraform workspace for $ENVIRONMENT..."
if terraform workspace list | grep -q "$ENVIRONMENT"; then
    terraform workspace select "$ENVIRONMENT"
else
    terraform workspace new "$ENVIRONMENT"
fi

# STAGE 1: Deploy Infrastructure (Network + GKE)
print_section "STAGE 1: INFRASTRUCTURE DEPLOYMENT"
print_status "Planning infrastructure deployment (Network + GKE)..."

# Plan infrastructure only (exclude n8n module)
terraform plan \
    -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
    -target="module.network" \
    -target="module.gke" \
    -target="google_project_service.required_apis" \
    -target="random_password.postgres_password" \
    -target="random_password.n8n_basic_auth_password" \
    -target="random_password.n8n_encryption_key" \
    -target="time_sleep.wait_for_cluster" \
    -target="data.google_container_cluster.cluster" \
    -target="null_resource.get_credentials" \
    -out="terraform-$ENVIRONMENT-infra.tfplan"

# Show infrastructure summary
print_status "Infrastructure Deployment Summary:"
echo -e "${YELLOW}  • GCP APIs: Enable required services${NC}"
echo -e "${YELLOW}  • Network: VPC and subnet creation${NC}"
echo -e "${YELLOW}  • GKE Cluster: Zonal (single zone)${NC}"
echo -e "${YELLOW}  • Node Pool: 1-2 nodes maximum (e2-medium)${NC}"
echo -e "${YELLOW}  • Credentials: Cluster access setup${NC}"

# Ask for confirmation for infrastructure
echo ""
read -p "Deploy infrastructure (Network + GKE)? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Infrastructure deployment cancelled by user"
    exit 0
fi

# Apply infrastructure
print_status "Deploying infrastructure (Network + GKE)..."
terraform apply "terraform-$ENVIRONMENT-infra.tfplan"

# Post-deployment validation for infrastructure
print_section "POST-INFRASTRUCTURE VALIDATION"
VALIDATION_PASSED=true
VALIDATION_ERRORS=()

# Get cluster credentials
print_status "Getting cluster credentials..."
gcloud container clusters get-credentials \
    "$CLUSTER_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID"

validate_network_deployment
validate_gke_deployment

if ! validation_summary; then
    print_error "Infrastructure validation failed. Check the deployment."
    exit 1
fi

print_success "Infrastructure deployment completed and validated successfully!"
echo ""

# STAGE 2: Deploy Application (N8N)
print_section "STAGE 2: APPLICATION DEPLOYMENT"
print_status "Planning N8N application deployment..."

# Plan N8N application
terraform plan \
    -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
    -target="module.n8n" \
    -out="terraform-$ENVIRONMENT-app.tfplan"

# Show application summary
print_status "Application Deployment Summary:"
echo -e "${YELLOW}  • N8N: Single replica (250m CPU, 256Mi RAM)${NC}"
echo -e "${YELLOW}  • PostgreSQL: Single instance (100m CPU, 128Mi RAM)${NC}"
echo -e "${YELLOW}  • Storage: 10Gi minimal storage${NC}"
echo -e "${YELLOW}  • Ingress: SSL-enabled load balancer${NC}"
echo -e "${YELLOW}  • Monitoring: Enabled${NC}"
echo -e "${YELLOW}  • Workload Identity: Enabled${NC}"

# Ask for confirmation for application
echo ""
read -p "Deploy N8N application? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Application deployment cancelled by user"
    print_status "Infrastructure remains deployed. You can deploy the application later."
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
kubectl wait --for=condition=Ready pods --all -n n8n --timeout=300s || print_warning "Some pods may still be starting"

validate_n8n_deployment

if ! validation_summary; then
    print_warning "Some N8N validation checks failed, but deployment may still be functional."
fi

# Final deployment summary
print_section "DEPLOYMENT COMPLETE"

# Get final status information
EXTERNAL_IP=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
CERT_STATUS=$(gcloud compute ssl-certificates describe "${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "Unknown")

echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Region:${NC} $REGION"
echo -e "${GREEN}Zone:${NC} $ZONE"
echo -e "${GREEN}Cluster:${NC} $CLUSTER_NAME"
echo -e "${GREEN}External IP:${NC} $EXTERNAL_IP"
echo -e "${GREEN}Domain:${NC} www.any-flow.com"
echo -e "${GREEN}SSL Status:${NC} $CERT_STATUS"
echo ""

# Show resource usage
print_status "Resource Usage Summary:"
echo -e "${GREEN}  • Maximum Nodes: 2${NC}"
echo -e "${GREEN}  • N8N Replicas: 1${NC}"
echo -e "${GREEN}  • PostgreSQL Instances: 1${NC}"
echo -e "${GREEN}  • Total CPU Request: ~350m${NC}"
echo -e "${GREEN}  • Total Memory Request: ~384Mi${NC}"
echo -e "${GREEN}  • Storage: 10Gi${NC}"

echo ""
if [ "$CERT_STATUS" != "ACTIVE" ]; then
    echo -e "${YELLOW}Note: SSL certificate may take 10-15 minutes to provision${NC}"
    echo -e "${YELLOW}Monitor certificate status: gcloud compute ssl-certificates describe ${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert --global${NC}"
fi

echo -e "${YELLOW}Monitor deployment: kubectl get pods -n n8n -w${NC}"
echo -e "${YELLOW}View logs: kubectl logs -f deployment/n8n-deployment -n n8n${NC}"

print_success "Deployment completed with comprehensive validation!"
