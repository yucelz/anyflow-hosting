#!/bin/bash

# Get N8N credentials and connection info with comprehensive validation
# Enhanced with validation checks similar to dev-deploy.sh
# Usage: ./scripts/get-credentials.sh [environment]

set -e

ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration based on environment
case "$ENVIRONMENT" in
    "dev")
        PROJECT_ID="anyflow-469911"
        REGION="us-central1"
        ZONE="us-central1-a"
        CLUSTER_NAME="dev-n8n-cluster"
        ;;
    "staging")
        PROJECT_ID="anyflow-469911"
        REGION="us-central1"
        ZONE="us-central1-b"
        CLUSTER_NAME="staging-n8n-cluster"
        ;;
    "prod")
        PROJECT_ID="anyflow-469911"
        REGION="us-central1"
        ZONE="us-central1-c"
        CLUSTER_NAME="prod-n8n-cluster"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
        exit 1
        ;;
esac

# Validation flags
VALIDATION_PASSED=true
VALIDATION_ERRORS=()

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
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

print_validation() {
    echo -e "${CYAN}[VALIDATION]${NC} $1"
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

# Function to validate project access
validate_project_access() {
    print_validation "Validating project access for $PROJECT_ID..."
    
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        add_validation_error "Cannot access project $PROJECT_ID. Check permissions."
        return 1
    fi
    
    print_success "Project $PROJECT_ID is accessible"
    return 0
}

# Function to validate terraform state
validate_terraform_state() {
    print_validation "Validating Terraform state..."
    
    # Check if we're in the right directory
    if [[ ! -f "main.tf" ]]; then
        add_validation_error "main.tf not found. Please run from terraform directory."
        return 1
    fi
    
    # Check terraform workspace
    local current_workspace=$(terraform workspace show 2>/dev/null || echo "default")
    if [[ "$current_workspace" != "$ENVIRONMENT" ]]; then
        print_warning "Current workspace is '$current_workspace', expected '$ENVIRONMENT'"
        print_info "Switching to $ENVIRONMENT workspace..."
        if terraform workspace select "$ENVIRONMENT" 2>/dev/null; then
            print_success "Switched to $ENVIRONMENT workspace"
        else
            add_validation_error "Cannot switch to $ENVIRONMENT workspace. Does it exist?"
            return 1
        fi
    else
        print_validation "Using correct workspace: $ENVIRONMENT"
    fi
    
    # Check if terraform state exists
    if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]] && ! terraform state list &>/dev/null; then
        add_validation_error "Terraform state not found. Please run deployment first."
        return 1
    fi
    
    print_success "Terraform state is valid"
    return 0
}

# Function to validate cluster connectivity
validate_cluster_connectivity() {
    print_validation "Validating cluster connectivity..."
    
    # Check if cluster exists
    if ! gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        add_validation_error "Cluster $CLUSTER_NAME not found in zone $ZONE"
        return 1
    fi
    
    # Check cluster status
    local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    if [[ "$cluster_status" != "RUNNING" ]]; then
        add_validation_error "Cluster $CLUSTER_NAME is not in RUNNING state (current: $cluster_status)"
        return 1
    fi
    print_success "Cluster $CLUSTER_NAME is running"
    
    # Test kubectl connectivity
    if command -v kubectl &> /dev/null; then
        if kubectl cluster-info &>/dev/null; then
            print_success "kubectl connectivity established"
        else
            print_warning "kubectl not connected to cluster. Will configure automatically."
        fi
    else
        print_warning "kubectl not available"
    fi
    
    return 0
}

# Function to validate deployment status
validate_deployment_status() {
    print_validation "Validating deployment status..."
    
    local namespace=$(terraform output -raw n8n_namespace 2>/dev/null || echo "n8n")
    
    # Check if kubectl is configured and cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        print_warning "kubectl not configured. Skipping deployment status validation."
        return 0
    fi
    
    # Check namespace
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        add_validation_error "Namespace $namespace not found"
        return 1
    fi
    print_success "Namespace $namespace exists"
    
    # Check N8N deployment
    local n8n_ready=$(kubectl get deployment n8n-deployment -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local n8n_desired=$(kubectl get deployment n8n-deployment -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [[ "$n8n_ready" != "$n8n_desired" ]]; then
        print_warning "N8N deployment not fully ready ($n8n_ready/$n8n_desired replicas)"
    else
        print_success "N8N deployment is ready ($n8n_ready/$n8n_desired replicas)"
    fi
    
    # Check PostgreSQL
    local postgres_ready=$(kubectl get statefulset n8n-postgres -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$postgres_ready" != "1" ]]; then
        print_warning "PostgreSQL not ready (ready replicas: $postgres_ready)"
    else
        print_success "PostgreSQL is ready"
    fi
    
    return 0
}

# Function to run validation summary
validation_summary() {
    echo ""
    print_section "VALIDATION SUMMARY"
    
    if [[ "$VALIDATION_PASSED" = true ]]; then
        print_success "All validations passed successfully!"
        return 0
    else
        print_error "Validation failed with ${#VALIDATION_ERRORS[@]} error(s):"
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo -e "${RED}  • $error${NC}"
        done
        echo ""
        print_warning "Some information may not be available due to validation failures."
        return 1
    fi
}

# Function to get terraform output safely
get_terraform_output() {
    local output_name=$1
    local default_value=${2:-"Not available"}
    
    terraform output -raw "$output_name" 2>/dev/null || echo "$default_value"
}

# Function to configure kubectl if needed
configure_kubectl() {
    print_info "Configuring kubectl for cluster access..."
    
    if gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" 2>/dev/null; then
        print_success "kubectl configured successfully"
        return 0
    else
        print_error "Failed to configure kubectl"
        return 1
    fi
}

# Function to perform health checks
perform_health_checks() {
    print_section "HEALTH CHECKS"
    
    local namespace=$(get_terraform_output "n8n_namespace" "n8n")
    local n8n_url=$(get_terraform_output "n8n_url" "")
    
    # Check N8N health endpoint
    if [[ -n "$n8n_url" ]]; then
        print_info "Testing N8N health endpoint..."
        if curl -s -k "${n8n_url}/healthz" --max-time 10 >/dev/null 2>&1; then
            print_success "N8N health check passed"
        else
            print_warning "N8N health check failed - this is normal if DNS is not configured yet"
        fi
    fi
    
    # Check SSL certificate status
    if gcloud compute ssl-certificates describe "n8n-ssl-cert" --global --project="$PROJECT_ID" &>/dev/null; then
        local cert_status=$(gcloud compute ssl-certificates describe "n8n-ssl-cert" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "UNKNOWN")
        if [[ "$cert_status" = "ACTIVE" ]]; then
            print_success "SSL certificate is active"
        elif [[ "$cert_status" = "PROVISIONING" ]]; then
            print_warning "SSL certificate is still provisioning (this may take 10-15 minutes)"
        else
            print_warning "SSL certificate status: $cert_status"
        fi
    else
        print_warning "SSL certificate not found"
    fi
    
    # Check ingress IP assignment
    if kubectl get ingress n8n-ingress -n "$namespace" &>/dev/null; then
        local ingress_ip=$(kubectl get ingress n8n-ingress -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$ingress_ip" ]]; then
            print_success "Ingress IP assigned: $ingress_ip"
        else
            print_warning "Ingress IP not yet assigned"
        fi
    fi
}

# Main execution starts here
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    N8N Credentials & Connection Info   ${NC}"
echo -e "${BLUE}      Environment: $ENVIRONMENT         ${NC}"
echo -e "${BLUE}========================================${NC}"

print_section "PRE-VALIDATION CHECKS"

# Validate prerequisites
validate_command "gcloud" "Google Cloud SDK"
validate_command "terraform" "Terraform"
validate_command "kubectl" "Kubernetes CLI"

validate_gcp_auth
validate_project_access

# Set the project
print_info "Setting GCP project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

# Change to project directory
cd "$PROJECT_ROOT"

validate_terraform_state
validate_cluster_connectivity
validate_deployment_status

# Run validation summary
if ! validation_summary; then
    print_warning "Proceeding with available information despite validation warnings..."
fi

# Configure kubectl if not already configured
if command -v kubectl &> /dev/null && ! kubectl cluster-info &>/dev/null; then
    configure_kubectl
fi

echo ""
print_section "CONNECTION INFORMATION"
echo -e "${BLUE}N8N URL:${NC} $(get_terraform_output 'n8n_url')"
echo -e "${BLUE}Static IP:${NC} $(get_terraform_output 'ingress_ip')"
echo -e "${BLUE}Cluster Name:${NC} $(get_terraform_output 'cluster_name' "$CLUSTER_NAME")"
echo -e "${BLUE}Project ID:${NC} $(get_terraform_output 'project_id' "$PROJECT_ID")"
echo -e "${BLUE}Region:${NC} $(get_terraform_output 'region' "$REGION")"
echo -e "${BLUE}Zone:${NC} $ZONE"
echo ""

print_section "AUTHENTICATION"
echo -e "${BLUE}Basic Auth User:${NC} $(get_terraform_output 'n8n_basic_auth_user')"

# Get sensitive outputs with validation
if terraform output n8n_basic_auth_password >/dev/null 2>&1; then
    echo -e "${BLUE}Basic Auth Password:${NC} $(terraform output -raw n8n_basic_auth_password)"
else
    print_warning "Basic auth password not available in outputs"
fi

if terraform output postgres_password >/dev/null 2>&1; then
    echo -e "${BLUE}PostgreSQL Password:${NC} $(terraform output -raw postgres_password)"
else
    print_warning "PostgreSQL password not available in outputs"
fi
echo ""

print_section "KUBECTL CONFIGURATION"
if terraform output kubectl_config_command >/dev/null 2>&1; then
    kubectl_cmd=$(terraform output -raw kubectl_config_command)
    echo -e "${BLUE}Configure kubectl:${NC} $kubectl_cmd"
    
    # Ask if user wants to configure kubectl now
    read -p "Configure kubectl now? (y/N): " configure_kubectl_now
    if [[ "$configure_kubectl_now" =~ ^[Yy]$ ]]; then
        print_info "Configuring kubectl..."
        if eval "$kubectl_cmd"; then
            print_success "kubectl configured successfully"
        else
            print_error "Failed to configure kubectl"
        fi
    fi
else
    # Fallback kubectl configuration
    kubectl_cmd="gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID"
    echo -e "${BLUE}Configure kubectl:${NC} $kubectl_cmd"
    
    read -p "Configure kubectl now? (y/N): " configure_kubectl_now
    if [[ "$configure_kubectl_now" =~ ^[Yy]$ ]]; then
        configure_kubectl
    fi
fi
echo ""

print_section "DNS CONFIGURATION"
if terraform output dns_configuration >/dev/null 2>&1; then
    echo "Configure your DNS with the following settings:"
    terraform output dns_configuration
else
    local domain=$(get_terraform_output 'n8n_url' | sed 's|https://||' | sed 's|http://||')
    local ip=$(get_terraform_output 'ingress_ip')
    
    if [[ "$domain" != "Not available" ]] && [[ "$ip" != "Not available" ]]; then
        echo -e "${BLUE}Record Type:${NC} A"
        echo -e "${BLUE}Name:${NC} $domain"
        echo -e "${BLUE}Value:${NC} $ip"
        echo -e "${BLUE}TTL:${NC} 300"
    else
        print_warning "DNS configuration not available"
    fi
fi
echo ""

# Get cluster status if kubectl is configured
if command -v kubectl &> /dev/null && kubectl cluster-info &>/dev/null; then
    print_section "CLUSTER STATUS"
    
    local namespace=$(get_terraform_output "n8n_namespace" "n8n")
    echo -e "${BLUE}Namespace:${NC} $namespace"
    
    # Check if namespace exists
    if kubectl get namespace "$namespace" &>/dev/null; then
        print_success "Namespace '$namespace' exists"
        
        # Get pod status
        echo ""
        echo -e "${BLUE}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -o wide 2>/dev/null || print_warning "Could not get pod status"
        
        # Get service status
        echo ""
        echo -e "${BLUE}Service Status:${NC}"
        kubectl get services -n "$namespace" 2>/dev/null || print_warning "Could not get service status"
        
        # Get ingress status
        echo ""
        echo -e "${BLUE}Ingress Status:${NC}"
        kubectl get ingress -n "$namespace" 2>/dev/null || print_warning "Could not get ingress status"
        
    else
        print_warning "Namespace '$namespace' not found"
    fi
else
    print_warning "kubectl not configured or cluster not accessible"
    print_info "Run the kubectl configuration command above to connect to the cluster"
fi

# Perform health checks
perform_health_checks

echo ""
print_section "USEFUL COMMANDS"
local namespace=$(get_terraform_output "n8n_namespace" "n8n")
echo -e "${BLUE}Check pods:${NC} kubectl get pods -n $namespace"
echo -e "${BLUE}Check logs:${NC} kubectl logs -n $namespace deployment/n8n-deployment -f"
echo -e "${BLUE}Scale N8N:${NC} kubectl scale deployment n8n-deployment --replicas=2 -n $namespace"
echo -e "${BLUE}Port forward:${NC} kubectl port-forward -n $namespace service/n8n-service 8080:80"
echo -e "${BLUE}Get secrets:${NC} kubectl get secrets -n $namespace"
echo -e "${BLUE}Describe ingress:${NC} kubectl describe ingress -n $namespace"
echo -e "${BLUE}Check SSL cert:${NC} gcloud compute ssl-certificates describe n8n-ssl-cert --global"
echo -e "${BLUE}Monitor pods:${NC} kubectl get pods -n $namespace -w"

echo ""
print_section "TROUBLESHOOTING COMMANDS"
echo -e "${BLUE}Debug N8N pod:${NC} kubectl describe pod -l app=n8n,component=deployment -n $namespace"
echo -e "${BLUE}Debug PostgreSQL:${NC} kubectl describe statefulset n8n-postgres -n $namespace"
echo -e "${BLUE}Check events:${NC} kubectl get events -n $namespace --sort-by='.lastTimestamp'"
echo -e "${BLUE}Check ingress details:${NC} kubectl describe ingress n8n-ingress -n $namespace"
echo -e "${BLUE}Test connectivity:${NC} kubectl exec -it deployment/n8n-deployment -n $namespace -- wget -qO- http://n8n-postgres:5432"

echo ""
if [[ "$VALIDATION_PASSED" = true ]]; then
    print_success "Credentials and connection information retrieved successfully!"
else
    print_warning "Information retrieved with some validation warnings. Check the validation summary above."
fi

echo ""
print_info "For detailed troubleshooting, refer to: docs/VALIDATION.md"
