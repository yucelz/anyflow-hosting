#!/bin/bash

# Test Dev Application (N8N + PostgreSQL) Health and Endpoints
# Usage: ./dev-app-test.sh [--help]

set -e

# Parse command line arguments
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
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
    echo "Test the health and endpoints of the N8N development application"
    echo ""
    echo "OPTIONS:"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                Run application health and endpoint tests"
    echo ""
    echo "Prerequisites:"
    echo "  • Infrastructure and application must be deployed first using: ./dev-infra.sh and ./dev-app.sh"
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
PROJECT_ID="anyflow-469911"
REGION="us-central1"
ZONE="us-central1-b"
CLUSTER_NAME="${ENVIRONMENT}-n8n-cluster"
DOMAIN_NAME="www.any-flow.com"

# Test flags
TEST_PASSED=true
TEST_ERRORS=()

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    N8N Dev Application Health Check   ${NC}"
echo -e "${BLUE}  Cluster Endpoints & Application Details ${NC}"
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

print_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_section() {
    echo -e "${PURPLE}========== $1 ==========${NC}"
}

# Function to add test error
add_test_error() {
    TEST_ERRORS+=("$1")
    TEST_PASSED=false
    print_error "TEST FAILED: $1"
}

# Function to validate command exists
validate_command() {
    local cmd=$1
    local description=$2
    
    if ! command -v "$cmd" &> /dev/null; then
        add_test_error "$description: $cmd command not found"
        return 1
    fi
    print_test "$description: $cmd is available"
    return 0
}

# Function to validate GCP authentication
validate_gcp_auth() {
    print_test "Checking GCP authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        add_test_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        return 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    print_success "Authenticated as: $active_account"
    return 0
}

# Function to validate GCP project access
validate_project_access() {
    print_test "Validating project access for $PROJECT_ID..."
    
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        add_test_error "Cannot access project $PROJECT_ID. Check permissions."
        return 1
    fi
    
    print_success "Project $PROJECT_ID is accessible"
    return 0
}

# Function to validate infrastructure prerequisites (GKE cluster and kubectl connectivity)
validate_infrastructure_connectivity() {
    print_test "Validating GKE cluster connectivity..."
    
    # Check if GKE cluster exists and is running
    if ! gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        add_test_error "GKE cluster $CLUSTER_NAME not found. Deploy infrastructure first using: ./dev-infra.sh"
        return 1
    fi
    
    local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)")
    if [ "$cluster_status" != "RUNNING" ]; then
        add_test_error "GKE cluster $CLUSTER_NAME is not in RUNNING state (current: $cluster_status)"
        return 1
    fi
    print_success "GKE cluster $CLUSTER_NAME is running"
    
    # Validate kubectl connectivity
    if ! kubectl cluster-info &>/dev/null; then
        add_test_error "Cannot connect to cluster via kubectl. Check cluster credentials."
        return 1
    fi
    print_success "kubectl connectivity established"
    
    # Check if nodes are ready
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    local total_nodes=$(kubectl get nodes --no-headers | wc -l || echo "0")
    
    if [ "$ready_nodes" -eq 0 ] || [ "$ready_nodes" -ne "$total_nodes" ]; then
        add_test_error "Not all nodes are ready ($ready_nodes/$total_nodes)"
        return 1
    fi
    print_success "All cluster nodes are ready ($ready_nodes/$total_nodes)"
    
    return 0
}

# Function to validate N8N deployment health
validate_n8n_deployment_health() {
    print_test "Validating N8N deployment health..."
    
    # Check namespace
    if ! kubectl get namespace n8n &>/dev/null; then
        add_test_error "N8N namespace was not created"
        return 1
    fi
    print_success "N8N namespace exists"
    
    # Check PostgreSQL deployment
    local postgres_ready=$(kubectl get statefulset n8n-postgres -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$postgres_ready" != "1" ]; then
        add_test_error "PostgreSQL is not ready (ready replicas: $postgres_ready)"
        return 1
    fi
    print_success "PostgreSQL is ready"
    
    # Check N8N deployment
    local n8n_ready=$(kubectl get deployment n8n-deployment -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$n8n_ready" != "1" ]; then
        add_test_error "N8N deployment is not ready (ready replicas: $n8n_ready)"
        return 1
    fi
    print_success "N8N deployment is ready"
    
    # Check services
    if ! kubectl get service n8n-service -n n8n &>/dev/null; then
        add_test_error "N8N service was not created"
        return 1
    fi
    print_success "N8N service exists"
    
    if ! kubectl get service n8n-postgres -n n8n &>/dev/null; then
        add_test_error "PostgreSQL service was not created"
        return 1
    fi
    print_success "PostgreSQL service exists"
    
    # Check ingress
    if ! kubectl get ingress n8n-ingress -n n8n &>/dev/null; then
        add_test_error "N8N ingress was not created"
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
    
    # Check SSL certificate status
    local ssl_cert_name="${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert"
    local cert_status=$(gcloud compute ssl-certificates describe "$ssl_cert_name" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "NOT_FOUND")
    if [ "$cert_status" = "ACTIVE" ]; then
        print_success "SSL certificate is active"
    elif [ "$cert_status" = "PROVISIONING" ]; then
        print_warning "SSL certificate is still provisioning (this may take 10-15 minutes)"
    else
        print_warning "SSL certificate status: $cert_status"
    fi

    # Check N8N application endpoint (HTTP/HTTPS)
    if [ "$cert_status" = "ACTIVE" ]; then
        print_test "Checking N8N application endpoint (HTTPS)..."
        if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME" | grep -q "200"; then
            print_success "N8N application is reachable at https://$DOMAIN_NAME"
        else
            add_test_error "N8N application is not reachable at https://$DOMAIN_NAME (or returned non-200 status)"
        fi
    else
        print_warning "SSL certificate not active, skipping HTTPS endpoint check. Try HTTP if applicable."
        # Optionally, check HTTP if HTTPS is not ready
        # if curl -s -o /dev/null -w "%{http_code}" "http://$ingress_ip" | grep -q "200"; then
        #     print_success "N8N application is reachable at http://$ingress_ip"
        # else
        #     add_test_error "N8N application is not reachable at http://$ingress_ip (or returned non-200 status)"
        # fi
    fi
    
    return 0
}

# Function to run comprehensive test summary
test_summary() {
    echo ""
    print_section "TEST SUMMARY"
    
    if [ "$TEST_PASSED" = true ]; then
        print_success "All tests passed successfully!"
        return 0
    else
        print_error "Tests failed with ${#TEST_ERRORS[@]} error(s):"
        for error in "${TEST_ERRORS[@]}"; do
            echo -e "${RED}  • $error${NC}"
        done
        return 1
    fi
}

# Main execution starts here
print_section "PRE-TEST VALIDATION"

# Validate prerequisites
validate_command "gcloud" "Google Cloud SDK"
validate_command "kubectl" "Kubernetes CLI"
validate_command "curl" "Curl"

validate_gcp_auth
validate_project_access

# Set the project
print_status "Setting GCP project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

# Get GKE credentials
print_status "Getting GKE cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID"

# Run connectivity tests
print_section "CLUSTER CONNECTIVITY TESTS"
validate_infrastructure_connectivity

# Run application health tests
print_section "APPLICATION HEALTH AND ENDPOINT TESTS"
validate_n8n_deployment_health

# Final summary
test_summary

# Output application details
print_section "APPLICATION DETAILS"

EXTERNAL_IP=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
CERT_STATUS=$(gcloud compute ssl-certificates describe "${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "Unknown")

echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Cluster:${NC} $CLUSTER_NAME"
echo -e "${GREEN}External IP:${NC} $EXTERNAL_IP"
echo -e "${GREEN}Domain:${NC} $DOMAIN_NAME"
echo -e "${GREEN}SSL Status:${NC} $CERT_STATUS"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "${YELLOW}  • Monitor deployment: kubectl get pods -n n8n -w${NC}"
echo -e "${YELLOW}  • View N8N logs: kubectl logs -f deployment/n8n-deployment -n n8n${NC}"
echo -e "${YELLOW}  • View PostgreSQL logs: kubectl logs -f statefulset/n8n-postgres -n n8n${NC}"
echo -e "${YELLOW}  • Access N8N: https://$DOMAIN_NAME (once SSL is active)${NC}"

# Output connection details
print_section "CONNECTION DETAILS"

N8N_USER=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.N8N_BASIC_AUTH_USER}' | base64 --decode 2>/dev/null || echo "N/A")
N8N_PASSWORD=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.N8N_BASIC_AUTH_PASSWORD}' | base64 --decode 2>/dev/null || echo "N/A")
POSTGRES_USER=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_USER}' | base64 --decode 2>/dev/null || echo "N/A")
POSTGRES_PASSWORD=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_PASSWORD}' | base64 --decode 2>/dev/null || echo "N/A")
POSTGRES_HOST=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_HOST}' | base64 --decode 2>/dev/null || echo "N/A")
POSTGRES_PORT=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_PORT}' | base64 --decode 2>/dev/null || echo "N/A")

echo -e "${GREEN}N8N Endpoint URL:${NC} https://$DOMAIN_NAME"
echo -e "${GREEN}N8N Basic Auth User:${NC} $N8N_USER"
echo -e "${GREEN}N8N Basic Auth Password:${NC} $N8N_PASSWORD"
echo ""
echo -e "${GREEN}PostgreSQL Host:${NC} $POSTGRES_HOST"
echo -e "${GREEN}PostgreSQL Port:${NC} $POSTGRES_PORT"
echo -e "${GREEN}PostgreSQL User:${NC} $POSTGRES_USER"
echo -e "${GREEN}PostgreSQL Password:${NC} $POSTGRES_PASSWORD"
echo ""

if [ "$TEST_PASSED" = true ]; then
    print_success "All application health and endpoint checks passed!"
else
    print_error "Some application health and endpoint checks failed. Please review the errors above."
    exit 1
fi
