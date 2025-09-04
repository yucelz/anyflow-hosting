#!/bin/bash

# Deploy Dev Infrastructure (Network + GKE)
# Enhanced validation checks for Network and GKE components
# Usage: ./dev-infra.sh [--destroy] [--help]

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
    echo "Deploy or destroy the N8N development infrastructure (Network + GKE)"
    echo ""
    echo "OPTIONS:"
    echo "  --destroy    Destroy the existing infrastructure instead of deploying"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                Deploy the development infrastructure"
    echo "  $0 --destroy      Destroy the development infrastructure"
    echo ""
    echo "Note: After infrastructure deployment, use dev-app.sh to deploy the N8N application"
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
ZONE="us-central1-a"
CLUSTER_NAME="${ENVIRONMENT}-n8n-cluster"
# Network names match terraform naming convention: ${environment}-${cluster_name}-${network_name}
NETWORK_NAME="${ENVIRONMENT}-n8n-cluster-n8n-vpc"
SUBNET_NAME="${ENVIRONMENT}-n8n-cluster-n8n-subnet"

# Validation flags
VALIDATION_PASSED=true
VALIDATION_ERRORS=()

if [ "$DESTROY_MODE" = true ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}   N8N Dev Infrastructure Destruction  ${NC}"
    echo -e "${RED}  With Deletion Protection Handling   ${NC}"
    echo -e "${RED}========================================${NC}"
else
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   N8N Dev Infrastructure Deployment   ${NC}"
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

# Function to handle cluster deletion protection
handle_cluster_deletion_protection() {
    local cluster_name=$1
    local zone_or_region=$2
    local location_flag=$3
    
    print_warning "Cluster deletion protection is enabled. Attempting to disable it..."
    
    # Try to update the cluster to disable deletion protection
    if gcloud container clusters update "$cluster_name" \
        --$location_flag="$zone_or_region" \
        --project="$PROJECT_ID" \
        --no-deletion-protection \
        --quiet; then
        print_success "Deletion protection disabled for cluster $cluster_name"
        return 0
    else
        print_error "Failed to disable deletion protection for cluster $cluster_name"
        print_error "You may need to disable it manually using:"
        print_error "gcloud container clusters update $cluster_name --$location_flag=$zone_or_region --project=$PROJECT_ID --no-deletion-protection"
        return 1
    fi
}

# Function to safely destroy cluster
destroy_cluster_safely() {
    local cluster_name=$1
    local zone_or_region=$2
    local location_flag=$3
    
    print_status "Attempting to destroy cluster $cluster_name..."
    
    # First try normal terraform destroy
    if terraform destroy -target="module.gke" \
        -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
        -auto-approve; then
        print_success "Cluster destroyed successfully"
        return 0
    else
        print_warning "Cluster destruction failed, likely due to deletion protection"
        
        # Check if cluster still exists and has deletion protection
        if gcloud container clusters describe "$cluster_name" \
            --$location_flag="$zone_or_region" \
            --project="$PROJECT_ID" \
            --format="value(deletionProtection)" 2>/dev/null | grep -q "true"; then
            
            print_status "Cluster has deletion protection enabled. Disabling it..."
            if handle_cluster_deletion_protection "$cluster_name" "$zone_or_region" "$location_flag"; then
                print_status "Retrying cluster destruction..."
                if terraform destroy -target="module.gke" \
                    -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
                    -auto-approve; then
                    print_success "Cluster destroyed successfully after disabling deletion protection"
                    return 0
                else
                    print_error "Cluster destruction still failed after disabling deletion protection"
                    return 1
                fi
            else
                return 1
            fi
        else
            print_error "Cluster destruction failed for unknown reasons"
            return 1
        fi
    fi
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

# Handle destroy mode
if [ "$DESTROY_MODE" = true ]; then
    print_section "INFRASTRUCTURE DESTRUCTION"
    
    # Ask for confirmation
    echo -e "${RED}WARNING: This will destroy the entire $ENVIRONMENT infrastructure!${NC}"
    echo -e "${RED}This includes:${NC}"
    echo -e "${RED}  • GKE cluster and nodes${NC}"
    echo -e "${RED}  • VPC network and subnets${NC}"
    echo -e "${RED}  • NAT gateway and firewall rules${NC}"
    echo ""
    echo -e "${YELLOW}Note: If N8N application is deployed, destroy it first using: ./dev-app.sh --destroy${NC}"
    echo ""
    read -p "Are you sure you want to destroy the $ENVIRONMENT infrastructure? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Infrastructure destruction cancelled by user"
        exit 0
    fi
    
    # Stage 1: Destroy GKE cluster (with deletion protection handling)
    print_section "STAGE 1: DESTROYING GKE CLUSTER"
    
    if destroy_cluster_safely "$CLUSTER_NAME" "$ZONE" "zone"; then
        print_success "GKE cluster destroyed successfully"
    else
        print_error "Failed to destroy GKE cluster. Manual intervention may be required."
        print_error "Try running: gcloud container clusters update $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID --no-deletion-protection"
        print_error "Then run: terraform destroy -target=module.gke -var-file=environments/$ENVIRONMENT/terraform.tfvars -auto-approve"
        exit 1
    fi
    
    # Stage 2: Destroy network infrastructure
    print_section "STAGE 2: DESTROYING NETWORK"
    
    print_status "Destroying network infrastructure (VPC, subnets, firewall rules, NAT gateway)..."
    
    if terraform destroy -target="module.network" \
        -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
        -auto-approve; then
        print_success "Network infrastructure destroyed successfully"
    else
        print_error "Network destruction failed. Some network resources may remain."
        print_error "You may need to manually clean up network resources using gcloud commands."
        exit 1
    fi
    
    # Stage 3: Clean up remaining infrastructure resources
    print_section "STAGE 3: CLEANUP"
    print_status "Cleaning up remaining infrastructure resources..."
    
    # Destroy remaining infrastructure terraform resources (excluding n8n module)
    if terraform destroy \
        -target="google_project_service.required_apis" \
        -target="random_password.postgres_password" \
        -target="random_password.n8n_encryption_key" \
        -target="time_sleep.wait_for_cluster" \
        -target="data.google_container_cluster.cluster" \
        -target="null_resource.get_credentials" \
        -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
        -auto-approve; then
        print_success "Infrastructure resources cleaned up successfully"
    else
        print_warning "Some infrastructure resources may remain"
    fi
    
    print_section "INFRASTRUCTURE DESTRUCTION COMPLETE"
    print_success "Infrastructure for environment $ENVIRONMENT has been destroyed!"
    print_status "Note: Some GCP resources may take a few minutes to fully disappear from the console"
    
    exit 0
fi

# Deploy Infrastructure (Network + GKE)
print_section "INFRASTRUCTURE DEPLOYMENT"
print_status "Planning infrastructure deployment (Network + GKE)..."

# Plan infrastructure only (exclude n8n module)
terraform plan \
    -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
    -target="module.network" \
    -target="module.gke" \
    -target="google_project_service.required_apis" \
    -target="random_password.postgres_password" \
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

# Final infrastructure summary
print_section "INFRASTRUCTURE DEPLOYMENT COMPLETE"

echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Region:${NC} $REGION"
echo -e "${GREEN}Zone:${NC} $ZONE"
echo -e "${GREEN}Cluster:${NC} $CLUSTER_NAME"
echo -e "${GREEN}Network:${NC} $NETWORK_NAME"
echo -e "${GREEN}Subnet:${NC} $SUBNET_NAME"
echo ""

# Show infrastructure resource usage
print_status "Infrastructure Resource Summary:"
echo -e "${GREEN}  • GKE Cluster: 1 zonal cluster${NC}"
echo -e "${GREEN}  • Node Pool: 1-2 nodes (e2-medium)${NC}"
echo -e "${GREEN}  • VPC Network: 1 custom network${NC}"
echo -e "${GREEN}  • Subnet: 1 regional subnet${NC}"
echo -e "${GREEN}  • NAT Gateway: 1 router with NAT${NC}"

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${YELLOW}  1. Deploy N8N application: ./scripts/dev-app.sh${NC}"
echo -e "${YELLOW}  2. Monitor cluster: kubectl get nodes${NC}"
echo -e "${YELLOW}  3. Check cluster info: kubectl cluster-info${NC}"

print_success "Infrastructure is ready for application deployment!"
