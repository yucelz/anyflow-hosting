#!/bin/bash

# Get N8N credentials and connection info
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

# Check if terraform state exists
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
    print_error "Terraform state not found. Please run deployment first."
    exit 1
fi

print_info "Getting credentials for environment: $ENVIRONMENT"
echo ""

# Get basic information
print_info "=== CONNECTION INFORMATION ==="
echo -e "${BLUE}N8N URL:${NC} $(terraform output -raw n8n_url 2>/dev/null || echo 'Not available')"
echo -e "${BLUE}Static IP:${NC} $(terraform output -raw ingress_ip 2>/dev/null || echo 'Not available')"
echo -e "${BLUE}Cluster Name:${NC} $(terraform output -raw cluster_name 2>/dev/null || echo 'Not available')"
echo -e "${BLUE}Project ID:${NC} $(terraform output -raw project_id 2>/dev/null || echo 'Not available')"
echo -e "${BLUE}Region:${NC} $(terraform output -raw region 2>/dev/null || echo 'Not available')"
echo ""

# Get authentication information
print_info "=== AUTHENTICATION ==="
echo -e "${BLUE}Basic Auth User:${NC} $(terraform output -raw n8n_basic_auth_user 2>/dev/null || echo 'Not available')"

# Get sensitive outputs
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

# Get kubectl configuration
print_info "=== KUBECTL CONFIGURATION ==="
if terraform output kubectl_config_command >/dev/null 2>&1; then
    kubectl_cmd=$(terraform output -raw kubectl_config_command)
    echo -e "${BLUE}Configure kubectl:${NC} $kubectl_cmd"
    
    # Ask if user wants to configure kubectl now
    read -p "Configure kubectl now? (y/N): " configure_kubectl
    if [[ "$configure_kubectl" =~ ^[Yy]$ ]]; then
        print_info "Configuring kubectl..."
        eval "$kubectl_cmd"
        print_success "kubectl configured successfully"
    fi
else
    print_warning "kubectl configuration command not available"
fi
echo ""

# Get DNS configuration
print_info "=== DNS CONFIGURATION ==="
if terraform output dns_configuration >/dev/null 2>&1; then
    echo "Configure your DNS with the following settings:"
    terraform output dns_configuration
else
    if terraform output ingress_ip >/dev/null 2>&1 && terraform output n8n_url >/dev/null 2>&1; then
        domain=$(terraform output -raw n8n_url | sed 's|https://||')
        ip=$(terraform output -raw ingress_ip)
        echo -e "${BLUE}Record Type:${NC} A"
        echo -e "${BLUE}Name:${NC} $domain"
        echo -e "${BLUE}Value:${NC} $ip"
        echo -e "${BLUE}TTL:${NC} 300"
    else
        print_warning "DNS configuration not available"
    fi
fi
echo ""

# Get SSL certificate status
print_info "=== SSL CERTIFICATE STATUS ==="
if terraform output ssl_certificate_status >/dev/null 2>&1; then
    ssl_status=$(terraform output -raw ssl_certificate_status)
    if [[ "$ssl_status" == "ACTIVE" ]]; then
        print_success "SSL certificate is active"
    else
        print_warning "SSL certificate status: $ssl_status"
        print_info "SSL certificates can take up to 60 minutes to become active"
    fi
else
    print_warning "SSL certificate status not available"
fi
echo ""

# Get cluster status if kubectl is configured
if command -v kubectl &> /dev/null; then
    # Try to get cluster info
    if kubectl cluster-info &>/dev/null; then
        print_info "=== CLUSTER STATUS ==="
        
        # Get namespace
        namespace=$(terraform output -raw n8n_namespace 2>/dev/null || echo "n8n")
        
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
fi

echo ""
print_info "=== USEFUL COMMANDS ==="
namespace=$(terraform output -raw n8n_namespace 2>/dev/null || echo "n8n")
echo -e "${BLUE}Check pods:${NC} kubectl get pods -n $namespace"
echo -e "${BLUE}Check logs:${NC} kubectl logs -n $namespace deployment/n8n-deployment -f"
echo -e "${BLUE}Scale N8N:${NC} kubectl scale deployment n8n-deployment --replicas=2 -n $namespace"
echo -e "${BLUE}Port forward:${NC} kubectl port-forward -n $namespace service/n8n-service 8080:80"
echo -e "${BLUE}Get secrets:${NC} kubectl get secrets -n $namespace"
echo -e "${BLUE}Describe ingress:${NC} kubectl describe ingress -n $namespace"

echo ""
print_success "Credentials and connection information retrieved successfully!"

# Health check
print_info "=== HEALTH CHECK ==="
n8n_url=$(terraform output -raw n8n_url 2>/dev/null || echo "")
if [[ -n "$n8n_url" ]]; then
    print_info "Testing N8N health endpoint..."
    if curl -s -k "${n8n_url}/healthz" >/dev/null 2>&1; then
        print_success "N8N health check passed"
    else
        print_warning "N8N health check failed - this is normal if DNS is not configured yet"
    fi
fi