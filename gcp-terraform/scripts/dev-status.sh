#!/bin/bash

# Check Status of Dev Environment Components
# Usage: ./dev-status.sh [--infra] [--app] [--all] [--help]

set -e

# Parse command line arguments
CHECK_INFRA=false
CHECK_APP=false
CHECK_ALL=false
SHOW_HELP=false

# If no arguments provided, default to checking all
if [ $# -eq 0 ]; then
    CHECK_ALL=true
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --infra)
            CHECK_INFRA=true
            shift
            ;;
        --app)
            CHECK_APP=true
            shift
            ;;
        --all)
            CHECK_ALL=true
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
    echo "Check the status of N8N development environment components"
    echo ""
    echo "OPTIONS:"
    echo "  --infra    Check only infrastructure status (Network + GKE)"
    echo "  --app      Check only application status (N8N + PostgreSQL)"
    echo "  --all      Check both infrastructure and application status (default)"
    echo "  --help, -h Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                Check all components (default)"
    echo "  $0 --infra        Check only infrastructure"
    echo "  $0 --app          Check only application"
    echo "  $0 --all          Check all components explicitly"
    echo ""
    exit 0
fi

# If --all is set, check both
if [ "$CHECK_ALL" = true ]; then
    CHECK_INFRA=true
    CHECK_APP=true
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
ZONE="us-central1-a"
CLUSTER_NAME="${ENVIRONMENT}-n8n-cluster"
NETWORK_NAME="${ENVIRONMENT}-n8n-cluster-n8n-vpc"
SUBNET_NAME="${ENVIRONMENT}-n8n-cluster-n8n-subnet"

# Status tracking
INFRA_STATUS="NOT_CHECKED"
APP_STATUS="NOT_CHECKED"
INFRA_DETAILS=()
APP_DETAILS=()

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

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

print_section() {
    echo -e "${PURPLE}========== $1 ==========${NC}"
}

print_subsection() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

# Function to check GCP authentication
check_gcp_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    print_status "Authenticated as: $active_account"
}

# Function to check infrastructure status
check_infrastructure_status() {
    print_section "INFRASTRUCTURE STATUS CHECK"
    
    local infra_healthy=true
    
    # Check VPC Network
    print_subsection "Network Components"
    
    if gcloud compute networks describe "$NETWORK_NAME" --project="$PROJECT_ID" &>/dev/null; then
        print_success "VPC Network: $NETWORK_NAME exists"
        INFRA_DETAILS+=("VPC Network: ACTIVE")
    else
        print_fail "VPC Network: $NETWORK_NAME not found"
        INFRA_DETAILS+=("VPC Network: NOT_FOUND")
        infra_healthy=false
    fi
    
    # Check Subnet
    if gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        print_success "Subnet: $SUBNET_NAME exists"
        INFRA_DETAILS+=("Subnet: ACTIVE")
    else
        print_fail "Subnet: $SUBNET_NAME not found"
        INFRA_DETAILS+=("Subnet: NOT_FOUND")
        infra_healthy=false
    fi
    
    # Check NAT Router
    local router_name="${NETWORK_NAME}-router"
    if gcloud compute routers describe "$router_name" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        print_success "NAT Router: $router_name exists"
        INFRA_DETAILS+=("NAT Router: ACTIVE")
    else
        print_fail "NAT Router: $router_name not found"
        INFRA_DETAILS+=("NAT Router: NOT_FOUND")
        infra_healthy=false
    fi
    
    # Check Firewall Rules
    local firewall_rules=("${NETWORK_NAME}-allow-internal" "${NETWORK_NAME}-allow-ssh" "${NETWORK_NAME}-allow-health-check")
    local firewall_count=0
    for rule in "${firewall_rules[@]}"; do
        if gcloud compute firewall-rules describe "$rule" --project="$PROJECT_ID" &>/dev/null; then
            ((firewall_count++))
        fi
    done
    if [ "$firewall_count" -eq "${#firewall_rules[@]}" ]; then
        print_success "Firewall Rules: All ${#firewall_rules[@]} rules exist"
        INFRA_DETAILS+=("Firewall Rules: ${firewall_count}/${#firewall_rules[@]}")
    else
        print_warning "Firewall Rules: Only $firewall_count/${#firewall_rules[@]} rules exist"
        INFRA_DETAILS+=("Firewall Rules: ${firewall_count}/${#firewall_rules[@]}")
    fi
    
    # Check GKE Cluster
    print_subsection "GKE Cluster"
    
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)")
        
        if [ "$cluster_status" = "RUNNING" ]; then
            print_success "GKE Cluster: $CLUSTER_NAME is $cluster_status"
            INFRA_DETAILS+=("GKE Cluster: RUNNING")
            
            # Check deletion protection
            local deletion_protection=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(deletionProtection)")
            if [ "$deletion_protection" = "true" ]; then
                print_warning "  Deletion Protection: ENABLED"
            else
                print_status "  Deletion Protection: DISABLED"
            fi
            
            # Check node pool
            local node_pool_status=$(gcloud container node-pools describe "n8n-node-pool" --cluster="$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
            if [ "$node_pool_status" = "RUNNING" ]; then
                print_success "  Node Pool: n8n-node-pool is $node_pool_status"
                
                # Get node count
                local node_count=$(gcloud container node-pools describe "n8n-node-pool" --cluster="$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(initialNodeCount)" 2>/dev/null || echo "0")
                print_status "  Node Count: $node_count"
                INFRA_DETAILS+=("Nodes: $node_count")
            else
                print_fail "  Node Pool: n8n-node-pool is $node_pool_status"
                INFRA_DETAILS+=("Node Pool: $node_pool_status")
                infra_healthy=false
            fi
            
            # Check kubectl connectivity
            if kubectl cluster-info &>/dev/null 2>&1; then
                print_success "  Kubectl: Connected to cluster"
                
                # Check nodes
                local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
                local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
                
                if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -gt 0 ]; then
                    print_success "  Kubernetes Nodes: $ready_nodes/$total_nodes ready"
                    INFRA_DETAILS+=("K8s Nodes: $ready_nodes/$total_nodes ready")
                else
                    print_warning "  Kubernetes Nodes: $ready_nodes/$total_nodes ready"
                    INFRA_DETAILS+=("K8s Nodes: $ready_nodes/$total_nodes ready")
                fi
            else
                print_warning "  Kubectl: Not connected (run: gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE)"
            fi
            
        else
            print_fail "GKE Cluster: $CLUSTER_NAME is $cluster_status"
            INFRA_DETAILS+=("GKE Cluster: $cluster_status")
            infra_healthy=false
        fi
    else
        print_fail "GKE Cluster: $CLUSTER_NAME not found"
        INFRA_DETAILS+=("GKE Cluster: NOT_FOUND")
        infra_healthy=false
    fi
    
    # Set overall infrastructure status
    if [ "$infra_healthy" = true ]; then
        INFRA_STATUS="HEALTHY"
        echo ""
        print_success "Infrastructure Status: HEALTHY"
    else
        INFRA_STATUS="UNHEALTHY"
        echo ""
        print_error "Infrastructure Status: UNHEALTHY"
    fi
}

# Function to check application status
check_application_status() {
    print_section "APPLICATION STATUS CHECK"
    
    local app_healthy=true
    
    # First check if we can connect to the cluster
    if ! kubectl cluster-info &>/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        print_warning "Run: gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE"
        APP_STATUS="CANNOT_CONNECT"
        APP_DETAILS+=("Cluster: NOT_CONNECTED")
        return
    fi
    
    # Check N8N Namespace
    print_subsection "Kubernetes Resources"
    
    if kubectl get namespace n8n &>/dev/null 2>&1; then
        print_success "Namespace: n8n exists"
        APP_DETAILS+=("Namespace: EXISTS")
        
        # Check PostgreSQL StatefulSet
        local postgres_ready=$(kubectl get statefulset n8n-postgres -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local postgres_replicas=$(kubectl get statefulset n8n-postgres -n n8n -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "$postgres_ready" = "$postgres_replicas" ] && [ "$postgres_replicas" -gt 0 ]; then
            print_success "PostgreSQL: $postgres_ready/$postgres_replicas replicas ready"
            APP_DETAILS+=("PostgreSQL: $postgres_ready/$postgres_replicas")
            
            # Check PostgreSQL pod status
            local postgres_pod=$(kubectl get pods -n n8n -l component=database --no-headers 2>/dev/null | head -n1)
            if [ -n "$postgres_pod" ]; then
                local pod_status=$(echo "$postgres_pod" | awk '{print $3}')
                print_status "  PostgreSQL Pod: $pod_status"
            fi
        else
            print_fail "PostgreSQL: $postgres_ready/$postgres_replicas replicas ready"
            APP_DETAILS+=("PostgreSQL: $postgres_ready/$postgres_replicas")
            app_healthy=false
        fi
        
        # Check N8N Deployment
        local n8n_ready=$(kubectl get deployment n8n-deployment -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local n8n_replicas=$(kubectl get deployment n8n-deployment -n n8n -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "$n8n_ready" = "$n8n_replicas" ] && [ "$n8n_replicas" -gt 0 ]; then
            print_success "N8N Deployment: $n8n_ready/$n8n_replicas replicas ready"
            APP_DETAILS+=("N8N: $n8n_ready/$n8n_replicas")
            
            # Check N8N pod status
            local n8n_pod=$(kubectl get pods -n n8n -l component=deployment --no-headers 2>/dev/null | head -n1)
            if [ -n "$n8n_pod" ]; then
                local pod_status=$(echo "$n8n_pod" | awk '{print $3}')
                local restarts=$(echo "$n8n_pod" | awk '{print $4}')
                print_status "  N8N Pod: $pod_status (Restarts: $restarts)"
                
                # Check for high restart count
                if [ "$restarts" -gt 5 ]; then
                    print_warning "  High restart count detected!"
                fi
            fi
        else
            print_fail "N8N Deployment: $n8n_ready/$n8n_replicas replicas ready"
            APP_DETAILS+=("N8N: $n8n_ready/$n8n_replicas")
            app_healthy=false
        fi
        
        # Check Services
        print_subsection "Services & Networking"
        
        if kubectl get service n8n-service -n n8n &>/dev/null 2>&1; then
            print_success "N8N Service: exists"
            APP_DETAILS+=("N8N Service: EXISTS")
        else
            print_fail "N8N Service: not found"
            APP_DETAILS+=("N8N Service: NOT_FOUND")
            app_healthy=false
        fi
        
        if kubectl get service n8n-postgres -n n8n &>/dev/null 2>&1; then
            print_success "PostgreSQL Service: exists"
            APP_DETAILS+=("PostgreSQL Service: EXISTS")
        else
            print_fail "PostgreSQL Service: not found"
            APP_DETAILS+=("PostgreSQL Service: NOT_FOUND")
            app_healthy=false
        fi
        
        # Check Ingress
        if kubectl get ingress n8n-ingress -n n8n &>/dev/null 2>&1; then
            print_success "Ingress: exists"
            
            # Get ingress IP
            local ingress_ip=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ -n "$ingress_ip" ]; then
                print_success "  External IP: $ingress_ip"
                APP_DETAILS+=("External IP: $ingress_ip")
            else
                print_warning "  External IP: Pending..."
                APP_DETAILS+=("External IP: PENDING")
            fi
        else
            print_fail "Ingress: not found"
            APP_DETAILS+=("Ingress: NOT_FOUND")
            app_healthy=false
        fi
        
        # Check SSL Certificate
        local ssl_cert_name="${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert"
        if gcloud compute ssl-certificates describe "$ssl_cert_name" --global --project="$PROJECT_ID" &>/dev/null 2>&1; then
            local cert_status=$(gcloud compute ssl-certificates describe "$ssl_cert_name" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "UNKNOWN")
            
            if [ "$cert_status" = "ACTIVE" ]; then
                print_success "SSL Certificate: $cert_status"
                APP_DETAILS+=("SSL: ACTIVE")
            elif [ "$cert_status" = "PROVISIONING" ]; then
                print_warning "SSL Certificate: $cert_status (may take 10-15 minutes)"
                APP_DETAILS+=("SSL: PROVISIONING")
            else
                print_warning "SSL Certificate: $cert_status"
                APP_DETAILS+=("SSL: $cert_status")
            fi
        else
            print_warning "SSL Certificate: not found"
            APP_DETAILS+=("SSL: NOT_FOUND")
        fi
        
        # Check Static IP
        local static_ip_name="${ENVIRONMENT}-n8n-cluster-n8n-static-ip"
        if gcloud compute addresses describe "$static_ip_name" --global --project="$PROJECT_ID" &>/dev/null 2>&1; then
            local static_ip=$(gcloud compute addresses describe "$static_ip_name" --global --project="$PROJECT_ID" --format="value(address)")
            print_success "Static IP: $static_ip"
            APP_DETAILS+=("Static IP: $static_ip")
        else
            print_warning "Static IP: not found"
            APP_DETAILS+=("Static IP: NOT_FOUND")
        fi
        
    else
        print_fail "Namespace: n8n not found"
        APP_DETAILS+=("Namespace: NOT_FOUND")
        app_healthy=false
    fi
    
    # Set overall application status
    if [ "$app_healthy" = true ]; then
        APP_STATUS="HEALTHY"
        echo ""
        print_success "Application Status: HEALTHY"
    else
        APP_STATUS="UNHEALTHY"
        echo ""
        print_error "Application Status: UNHEALTHY"
    fi
}

# Function to print summary
print_summary() {
    echo ""
    print_section "STATUS SUMMARY"
    
    # Infrastructure Summary
    if [ "$CHECK_INFRA" = true ]; then
        echo -e "${CYAN}Infrastructure:${NC}"
        if [ "$INFRA_STATUS" = "HEALTHY" ]; then
            echo -e "  Status: ${GREEN}$INFRA_STATUS${NC}"
        elif [ "$INFRA_STATUS" = "UNHEALTHY" ]; then
            echo -e "  Status: ${RED}$INFRA_STATUS${NC}"
        else
            echo -e "  Status: ${YELLOW}$INFRA_STATUS${NC}"
        fi
        
        for detail in "${INFRA_DETAILS[@]}"; do
            echo "  • $detail"
        done
    fi
    
    # Application Summary
    if [ "$CHECK_APP" = true ]; then
        echo ""
        echo -e "${CYAN}Application:${NC}"
        if [ "$APP_STATUS" = "HEALTHY" ]; then
            echo -e "  Status: ${GREEN}$APP_STATUS${NC}"
        elif [ "$APP_STATUS" = "UNHEALTHY" ] || [ "$APP_STATUS" = "CANNOT_CONNECT" ]; then
            echo -e "  Status: ${RED}$APP_STATUS${NC}"
        else
            echo -e "  Status: ${YELLOW}$APP_STATUS${NC}"
        fi
        
        for detail in "${APP_DETAILS[@]}"; do
            echo "  • $detail"
        done
    fi
    
    # Access Information
    if [ "$APP_STATUS" = "HEALTHY" ]; then
        echo ""
        echo -e "${CYAN}Access Information:${NC}"
        echo "  • Domain: https://www.any-flow.com"
        
        local ingress_ip=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$ingress_ip" ]; then
            echo "  • Direct IP: https://$ingress_ip"
        fi
        
        echo "  • Username: admin (configured in terraform)"
        echo "  • Password: (check terraform output or secrets)"
    fi
    
    # Recommendations
    echo ""
    echo -e "${CYAN}Quick Commands:${NC}"
    
    if [ "$INFRA_STATUS" = "NOT_CHECKED" ] || [ "$INFRA_STATUS" = "UNHEALTHY" ]; then
        echo "  • Deploy infrastructure: ./scripts/dev-infra.sh"
    fi
    
    if [ "$APP_STATUS" = "NOT_CHECKED" ] || [ "$APP_STATUS" = "UNHEALTHY" ]; then
        echo "  • Deploy application: ./scripts/dev-app.sh"
    fi
    
    if [ "$APP_STATUS" = "CANNOT_CONNECT" ]; then
        echo "  • Connect to cluster: gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID"
    fi
    
    if [ "$APP_STATUS" = "HEALTHY" ]; then
        echo "  • View logs: kubectl logs -f deployment/n8n-deployment -n n8n"
        echo "  • Watch pods: kubectl get pods -n n8n -w"
    fi
}

# Main execution
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    N8N Dev Environment Status Check    ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check GCP authentication
check_gcp_auth

# Set the project
print_status "Project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID" 2>/dev/null

# Check infrastructure if requested
if [ "$CHECK_INFRA" = true ]; then
    check_infrastructure_status
fi

# Check application if requested
if [ "$CHECK_APP" = true ]; then
    check_application_status
fi

# Print summary
print_summary

echo ""
print_success "Status check completed!"
