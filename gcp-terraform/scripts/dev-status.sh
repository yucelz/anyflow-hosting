#!/bin/bash

# Check Status of Dev Environment Components
# Usage: ./dev-status.sh [--infra] [--app] [--all] [--help] [--db-only] [--n8n-only]

set -e

# Parse command line arguments
CHECK_INFRA=false
CHECK_APP=false
CHECK_ALL=false
SHOW_HELP=false
DB_ONLY=false
N8N_ONLY=false

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
        --db-only)
            DB_ONLY=true
            CHECK_APP=true
            shift
            ;;
        --n8n-only)
            N8N_ONLY=true
            CHECK_APP=true
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
    echo "  --infra      Check only infrastructure status (Network + GKE)"
    echo "  --app        Check only application status (N8N + PostgreSQL)"
    echo "  --all        Check both infrastructure and application status (default)"
    echo "  --db-only    Check only PostgreSQL database status"
    echo "  --n8n-only   Check only N8N application status"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                Check all components (default)"
    echo "  $0 --infra        Check only infrastructure"
    echo "  $0 --app          Check only application"
    echo "  $0 --all          Check all components explicitly"
    echo "  $0 --db-only      Check only PostgreSQL database"
    echo "  $0 --n8n-only     Check only N8N application"
    echo ""
    echo "Deployment Scripts:"
    echo "  ./dev-deploy.sh          Full deployment wrapper script"
    echo "  ./dev-infra.sh           Infrastructure deployment script"
    echo "  ./dev-app.sh             Application deployment script"
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
PROJECT_ID="anyflow-cloud"
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

# Function to get all external IP addresses and port mappings
get_external_ip_mappings() {
    print_subsection "External IP Address Mappings"
    
    # Static IP addresses
    local static_ips=$(gcloud compute addresses list --project="$PROJECT_ID" --format="table(name,address,region,status)" --filter="name~'.*n8n.*'" 2>/dev/null || echo "")
    if [ -n "$static_ips" ]; then
        print_status "Static IP Addresses:"
        echo "$static_ips" | grep -v "^NAME" | while read -r name address region status; do
            if [ -n "$name" ]; then
                print_status "  Static IP: $name = $address ($region) [$status]"
                APP_DETAILS+=("Static IP: $name = $address [$status]")
            fi
        done
    fi
    
    # Load Balancer services with external IPs
    local lb_services=$(kubectl get services --all-namespaces -o wide 2>/dev/null | grep "LoadBalancer" || echo "")
    if [ -n "$lb_services" ]; then
        print_status "LoadBalancer Services:"
        echo "$lb_services" | while read -r namespace name type cluster_ip external_ip ports age selector; do
            if [ "$external_ip" != "<pending>" ] && [ "$external_ip" != "<none>" ]; then
                print_status "  Service: $name.$namespace = $external_ip (Ports: $ports)"
                APP_DETAILS+=("LoadBalancer: $name.$namespace = $external_ip")
            fi
        done
    fi
    
    # Ingress external IPs
    local ingress_ips=$(kubectl get ingress --all-namespaces -o wide 2>/dev/null || echo "")
    if [ -n "$ingress_ips" ]; then
        print_status "Ingress External IPs:"
        echo "$ingress_ips" | grep -v "^NAMESPACE" | while read -r namespace name class hosts address ports age; do
            if [ "$address" != "<none>" ] && [ -n "$address" ]; then
                print_status "  Ingress: $name.$namespace = $address (Hosts: $hosts)"
                APP_DETAILS+=("Ingress IP: $name.$namespace = $address")
                
                # Get detailed ingress rules and backend services
                local ingress_details=$(kubectl describe ingress "$name" -n "$namespace" 2>/dev/null || echo "")
                if [ -n "$ingress_details" ]; then
                    echo "$ingress_details" | grep -A 5 "Rules:" | grep "Host\|Path\|Backend" | while read -r line; do
                        print_status "    $line"
                    done
                fi
            fi
        done
    fi
    
    # Node external IPs (for NodePort services)
    local node_ips=$(kubectl get nodes -o wide --no-headers 2>/dev/null | awk '{print $1, $7}' || echo "")
    if [ -n "$node_ips" ]; then
        print_status "Node External IPs:"
        echo "$node_ips" | while read -r node_name external_ip; do
            if [ "$external_ip" != "<none>" ] && [ -n "$external_ip" ]; then
                print_status "  Node: $node_name = $external_ip"
                APP_DETAILS+=("Node IP: $node_name = $external_ip")
            fi
        done
        
        # Check for NodePort services that would use these IPs
        local nodeport_services=$(kubectl get services --all-namespaces -o wide 2>/dev/null | grep "NodePort" || echo "")
        if [ -n "$nodeport_services" ]; then
            print_status "NodePort Services (accessible via Node IPs):"
            echo "$nodeport_services" | while read -r namespace name type cluster_ip external_ip ports age selector; do
                local nodeport=$(echo "$ports" | grep -o '[0-9]*:[0-9]*' | cut -d':' -f2)
                print_status "  Service: $name.$namespace (NodePort: $nodeport)"
                APP_DETAILS+=("NodePort: $name.$namespace port $nodeport")
            done
        fi
    fi
    
    # Google Cloud Load Balancer forwarding rules
    local forwarding_rules=$(gcloud compute forwarding-rules list --project="$PROJECT_ID" --format="table(name,IPAddress,portRange,target)" --filter="name~'.*n8n.*'" 2>/dev/null || echo "")
    if [ -n "$forwarding_rules" ]; then
        print_status "Load Balancer Forwarding Rules:"
        echo "$forwarding_rules" | grep -v "^NAME" | while read -r name ip_address port_range target; do
            if [ -n "$name" ]; then
                print_status "  Forwarding Rule: $name = $ip_address:$port_range -> $target"
                APP_DETAILS+=("Forwarding Rule: $name = $ip_address:$port_range")
            fi
        done
    fi
}

# Function to get comprehensive N8N connection details
get_n8n_connection_details() {
    print_subsection "N8N Connection Details & Port Mapping"
    
    # Get secrets
    local N8N_USER=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.N8N_BASIC_AUTH_USER}' 2>/dev/null | base64 --decode 2>/dev/null || echo "N/A")
    local N8N_PASSWORD=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.N8N_BASIC_AUTH_PASSWORD}' 2>/dev/null | base64 --decode 2>/dev/null || echo "N/A")
    
    # Get ingress details
    local DOMAIN_NAME=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "N/A")
    local INGRESS_IP=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "N/A")
    
    # Get service details
    local N8N_SERVICE_TYPE=$(kubectl get service n8n-service -n n8n -o jsonpath='{.spec.type}' 2>/dev/null || echo "N/A")
    local N8N_SERVICE_PORT=$(kubectl get service n8n-service -n n8n -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "N/A")
    local N8N_TARGET_PORT=$(kubectl get service n8n-service -n n8n -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "N/A")
    local N8N_NODE_PORT=$(kubectl get service n8n-service -n n8n -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    
    # SSL Certificate status
    local SSL_CERT_NAME="${ENVIRONMENT}-n8n-cluster-n8n-ssl-cert"
    local SSL_STATUS=$(gcloud compute ssl-certificates describe "$SSL_CERT_NAME" --global --project="$PROJECT_ID" --format="value(managed.status)" 2>/dev/null || echo "N/A")
    local SSL_DOMAINS=$(gcloud compute ssl-certificates describe "$SSL_CERT_NAME" --global --project="$PROJECT_ID" --format="value(managed.domains)" 2>/dev/null || echo "N/A")
    
    print_success "=== PRIMARY N8N ACCESS ==="
    print_status "🌐 N8N Web Interface: https://$DOMAIN_NAME"
    print_status "🔐 Basic Auth User: $N8N_USER"
    print_status "🔑 Basic Auth Password: $N8N_PASSWORD"
    print_status "📍 External IP: $INGRESS_IP"
    print_status "🔒 SSL Certificate: $SSL_STATUS (Domains: $SSL_DOMAINS)"
    
    print_success "=== PORT MAPPING DETAILS ==="
    print_status "🔧 Service Type: $N8N_SERVICE_TYPE"
    print_status "🚪 Service Port: $N8N_SERVICE_PORT (exposed to cluster)"
    print_status "🎯 Target Port: $N8N_TARGET_PORT (container port)"
    if [ "$N8N_NODE_PORT" != "N/A" ] && [ "$N8N_NODE_PORT" != "<none>" ]; then
        print_status "🔗 Node Port: $N8N_NODE_PORT (direct node access)"
    fi
    
    # Get all external access methods
    print_success "=== ALL EXTERNAL ACCESS METHODS ==="
    
    # Method 1: Ingress (Primary)
    if [ "$INGRESS_IP" != "N/A" ] && [ "$DOMAIN_NAME" != "N/A" ]; then
        print_status "1. Via Ingress (RECOMMENDED):"
        print_status "   URL: https://$DOMAIN_NAME"
        print_status "   IP: $INGRESS_IP:443 (HTTPS)"
        print_status "   Protocol: HTTPS with SSL termination"
    fi
    
    # Method 2: LoadBalancer service (if exists)
    local lb_external_ip=$(kubectl get service n8n-service -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$lb_external_ip" ] && [ "$lb_external_ip" != "<none>" ]; then
        print_status "2. Via LoadBalancer Service:"
        print_status "   IP: $lb_external_ip:$N8N_SERVICE_PORT"
        print_status "   Protocol: HTTP (direct to service)"
    fi
    
    # Method 3: NodePort (if exists)
    if [ "$N8N_NODE_PORT" != "N/A" ] && [ "$N8N_NODE_PORT" != "<none>" ]; then
        print_status "3. Via NodePort (any node IP):"
        kubectl get nodes -o wide --no-headers 2>/dev/null | awk '{print $1, $7}' | while read -r node_name external_ip; do
            if [ "$external_ip" != "<none>" ] && [ -n "$external_ip" ]; then
                print_status "   Node: $external_ip:$N8N_NODE_PORT ($node_name)"
            fi
        done
        print_status "   Protocol: HTTP (direct to node)"
    fi
    
    # Method 4: Port forwarding (for development)
    print_status "4. Via kubectl port-forward (development):"
    print_status "   Command: kubectl port-forward svc/n8n-service 5678:$N8N_SERVICE_PORT -n n8n"
    print_status "   Local URL: http://localhost:5678"
    print_status "   Protocol: HTTP (tunneled through kubectl)"
    
    # Add connection details to summary
    APP_DETAILS+=("N8N Primary URL: https://$DOMAIN_NAME")
    APP_DETAILS+=("N8N External IP: $INGRESS_IP")
    APP_DETAILS+=("N8N Auth User: $N8N_USER")
    APP_DETAILS+=("N8N Auth Password: $N8N_PASSWORD")
    APP_DETAILS+=("SSL Certificate: $SSL_STATUS")
    APP_DETAILS+=("Service Type: $N8N_SERVICE_TYPE")
    APP_DETAILS+=("Port Mapping: $N8N_SERVICE_PORT -> $N8N_TARGET_PORT")
    if [ "$N8N_NODE_PORT" != "N/A" ]; then
        APP_DETAILS+=("Node Port: $N8N_NODE_PORT")
    fi
    
    # Show current pod status for debugging
    print_success "=== N8N POD STATUS ==="
    kubectl get pods -l app=n8n,component=deployment -n n8n -o wide 2>/dev/null | grep -v "^NAME" | while read -r name ready status restarts age ip node nominated_node readiness_gates; do
        print_status "Pod: $name ($status) - IP: $ip on Node: $node"
        if [ "$status" != "Running" ]; then
            print_warning "  Pod is not running - check logs: kubectl logs $name -n n8n"
        fi
    done
}

# Function to check infrastructure status
check_infrastructure_status() {
    print_section "INFRASTRUCTURE STATUS CHECK"
    
    local infra_healthy=true
    
    # Check VPC Network
    print_subsection "Network Components"
    
    if gcloud compute networks describe "$NETWORK_NAME" --project="$PROJECT_ID" &>/dev/null; then
        local vpc_subnets=$(gcloud compute networks describe "$NETWORK_NAME" --project="$PROJECT_ID" --format="value(subnetworks[])" 2>/dev/null | wc -l || echo "0")
        print_success "VPC Network: $NETWORK_NAME exists (Subnets: $vpc_subnets)"
        INFRA_DETAILS+=("VPC Network: ACTIVE ($vpc_subnets subnets)")
    else
        print_fail "VPC Network: $NETWORK_NAME not found"
        INFRA_DETAILS+=("VPC Network: NOT_FOUND")
        infra_healthy=false
    fi
    
    # Check Subnet
    if gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        local subnet_ip_range=$(gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --project="$PROJECT_ID" --format="value(ipCidrRange)" 2>/dev/null || echo "Unknown")
        print_success "Subnet: $SUBNET_NAME exists (IP Range: $subnet_ip_range)"
        INFRA_DETAILS+=("Subnet: ACTIVE ($subnet_ip_range)")
    else
        print_fail "Subnet: $SUBNET_NAME not found"
        INFRA_DETAILS+=("Subnet: NOT_FOUND")
        infra_healthy=false
    fi
    
    # Check NAT Router
    local router_name="${NETWORK_NAME}-router"
    if gcloud compute routers describe "$router_name" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        local nat_gateway_ip=$(gcloud compute routers describe "$router_name" --region="$REGION" --project="$PROJECT_ID" --format="value(nats[0].natIpAllocateOption)" 2>/dev/null || echo "AUTO")
        print_success "NAT Router: $router_name exists (IP Allocation: $nat_gateway_ip)"
        INFRA_DETAILS+=("NAT Router: ACTIVE ($nat_gateway_ip)")
    else
        print_fail "NAT Router: $router_name not found"
        INFRA_DETAILS+=("NAT Router: NOT_FOUND")
        infra_healthy=false
    fi
    
    # Check Firewall Rules
    print_subsection "Firewall Rules"
    local firewall_rules=("${NETWORK_NAME}-allow-internal" "${NETWORK_NAME}-allow-ssh" "${NETWORK_NAME}-allow-health-check")
    local firewall_count=0
    for rule in "${firewall_rules[@]}"; do
        if gcloud compute firewall-rules describe "$rule" --project="$PROJECT_ID" &>/dev/null; then
            local rule_direction=$(gcloud compute firewall-rules describe "$rule" --project="$PROJECT_ID" --format="value(direction)" 2>/dev/null || echo "Unknown")
            local rule_ports=$(gcloud compute firewall-rules describe "$rule" --project="$PROJECT_ID" --format="value(allowed[].ports.join(','))" 2>/dev/null || echo "All")
            print_success "  Firewall Rule: $rule ($rule_direction - Ports: $rule_ports)"
            ((firewall_count++))
        else
            print_fail "  Firewall Rule: $rule not found"
        fi
    done
    if [ "$firewall_count" -eq "${#firewall_rules[@]}" ]; then
        print_success "Firewall Rules: All ${#firewall_rules[@]} rules exist and configured"
        INFRA_DETAILS+=("Firewall Rules: ${firewall_count}/${#firewall_rules[@]} configured")
    else
        print_warning "Firewall Rules: Only $firewall_count/${#firewall_rules[@]} rules exist"
        INFRA_DETAILS+=("Firewall Rules: ${firewall_count}/${#firewall_rules[@]} configured")
    fi
    
    # Check GKE Cluster
    print_subsection "GKE Cluster Details"
    
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        local cluster_status=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)")
        local cluster_location=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(location)" 2>/dev/null || echo "$ZONE")
        local cluster_version=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(currentMasterVersion)" 2>/dev/null || echo "Unknown")
        
        if [ "$cluster_status" = "RUNNING" ]; then
            print_success "GKE Cluster: $CLUSTER_NAME is $cluster_status"
            print_status "  Location: $cluster_location"
            print_status "  Version: $cluster_version"
            INFRA_DETAILS+=("GKE Cluster: RUNNING ($cluster_location)")
            INFRA_DETAILS+=("K8s Version: $cluster_version")
            
            # Check deletion protection
            local deletion_protection=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(deletionProtection)" 2>/dev/null || echo "false")
            if [ "$deletion_protection" = "true" ]; then
                print_warning "  Deletion Protection: ENABLED"
                INFRA_DETAILS+=("Deletion Protection: ENABLED")
            else
                print_status "  Deletion Protection: DISABLED"
                INFRA_DETAILS+=("Deletion Protection: DISABLED")
            fi
            
            # Check node pool details
            local node_pool_status=$(gcloud container node-pools describe "n8n-node-pool" --cluster="$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
            if [ "$node_pool_status" = "RUNNING" ]; then
                local node_count=$(gcloud container node-pools describe "n8n-node-pool" --cluster="$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(initialNodeCount)" 2>/dev/null || echo "0")
                local machine_type=$(gcloud container node-pools describe "n8n-node-pool" --cluster="$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(config.machineType)" 2>/dev/null || echo "Unknown")
                local disk_size=$(gcloud container node-pools describe "n8n-node-pool" --cluster="$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(config.diskSizeGb)" 2>/dev/null || echo "Unknown")
                
                print_success "  Node Pool: n8n-node-pool is $node_pool_status"
                print_status "  Node Count: $node_count"
                print_status "  Machine Type: $machine_type"
                print_status "  Disk Size: ${disk_size}GB"
                INFRA_DETAILS+=("Node Pool: RUNNING ($node_count nodes)")
                INFRA_DETAILS+=("Machine Type: $machine_type")
                INFRA_DETAILS+=("Disk Size: ${disk_size}GB")
            else
                print_fail "  Node Pool: n8n-node-pool is $node_pool_status"
                INFRA_DETAILS+=("Node Pool: $node_pool_status")
                infra_healthy=false
            fi
            
            # Check kubectl connectivity and cluster details
            if kubectl cluster-info &>/dev/null; then
                print_success "  Kubectl: Connected to cluster"
                
                # Check nodes details
                local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
                local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
                
                if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -gt 0 ]; then
                    print_success "  Cluster Nodes: $ready_nodes/$total_nodes nodes ready"
                    INFRA_DETAILS+=("Cluster Nodes: $ready_nodes/$total_nodes ready")
                    
                    # Check system namespaces
                    local system_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
                    print_status "  System Pods: $system_pods running in kube-system"
                    INFRA_DETAILS+=("System Pods: $system_pods running")
                else
                    print_warning "  Cluster Nodes: Only $ready_nodes/$total_nodes nodes ready"
                    INFRA_DETAILS+=("Cluster Nodes: $ready_nodes/$total_nodes ready")
                fi
            else
                print_fail "  Kubectl: Cannot connect to cluster"
                INFRA_DETAILS+=("Kubectl: DISCONNECTED")
                infra_healthy=false
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
    
    # Set infrastructure status
    if [ "$infra_healthy" = true ]; then
        INFRA_STATUS="HEALTHY"
        print_success "Infrastructure Status: HEALTHY"
    else
        INFRA_STATUS="UNHEALTHY"
        print_fail "Infrastructure Status: UNHEALTHY"
    fi
}

# Function to check application status
check_application_status() {
    print_section "APPLICATION STATUS CHECK"
    
    local app_healthy=true
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        APP_STATUS="UNHEALTHY"
        APP_DETAILS+=("kubectl: NOT_AVAILABLE")
        return
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        APP_STATUS="UNHEALTHY"
        APP_DETAILS+=("Cluster Connection: FAILED")
        return
    fi
    
    # Check if N8N namespace exists
    if ! kubectl get namespace n8n &>/dev/null; then
        print_error "N8N namespace does not exist"
        APP_STATUS="UNHEALTHY"
        APP_DETAILS+=("N8N Namespace: NOT_FOUND")
        return
    fi
    
    # Skip N8N checks if only checking database
    if [ "$DB_ONLY" != true ]; then
        # Check N8N deployment
        print_subsection "N8N Application"
        
        if kubectl get deployment n8n-deployment -n n8n &>/dev/null; then
            local n8n_ready=$(kubectl get deployment n8n-deployment -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local n8n_desired=$(kubectl get deployment n8n-deployment -n n8n -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            local n8n_image=$(kubectl get deployment n8n-deployment -n n8n -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "Unknown")
            
            if [ "$n8n_ready" -eq "$n8n_desired" ] && [ "$n8n_desired" -gt 0 ]; then
                print_success "N8N Deployment: $n8n_ready/$n8n_desired replicas ready"
                print_status "  Image: $n8n_image"
                APP_DETAILS+=("N8N Deployment: READY ($n8n_ready/$n8n_desired)")
                APP_DETAILS+=("N8N Image: $n8n_image")
            else
                print_fail "N8N Deployment: Only $n8n_ready/$n8n_desired replicas ready"
                APP_DETAILS+=("N8N Deployment: NOT_READY ($n8n_ready/$n8n_desired)")
                app_healthy=false
            fi
            
            # Check N8N service
            if kubectl get service n8n-service -n n8n &>/dev/null; then
                local service_type=$(kubectl get service n8n-service -n n8n -o jsonpath='{.spec.type}' 2>/dev/null || echo "Unknown")
                local service_port=$(kubectl get service n8n-service -n n8n -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "Unknown")
                local service_target_port=$(kubectl get service n8n-service -n n8n -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "Unknown")
                
                print_success "N8N Service: Available ($service_type)"
                print_status "  Port: $service_port -> $service_target_port"
                APP_DETAILS+=("N8N Service: AVAILABLE ($service_type)")
                APP_DETAILS+=("Service Port: $service_port -> $service_target_port")
            else
                print_fail "N8N Service: Not found"
                APP_DETAILS+=("N8N Service: NOT_FOUND")
                app_healthy=false
            fi
            
            # Check N8N pods
            local n8n_pods_running=$(kubectl get pods -l app=n8n,component=deployment -n n8n --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            local n8n_pods_total=$(kubectl get pods -l app=n8n,component=deployment -n n8n --no-headers 2>/dev/null | wc -l || echo "0")
            
            if [ "$n8n_pods_running" -eq "$n8n_pods_total" ] && [ "$n8n_pods_total" -gt 0 ]; then
                print_success "N8N Pods: $n8n_pods_running/$n8n_pods_total running"
                APP_DETAILS+=("N8N Pods: $n8n_pods_running/$n8n_pods_total running")
            else
                print_warning "N8N Pods: Only $n8n_pods_running/$n8n_pods_total running"
                APP_DETAILS+=("N8N Pods: $n8n_pods_running/$n8n_pods_total running")
                if [ "$n8n_pods_running" -lt "$n8n_pods_total" ]; then
                    app_healthy=false
                fi
            fi
        else
            print_fail "N8N Deployment: Not found"
            APP_DETAILS+=("N8N Deployment: NOT_FOUND")
            app_healthy=false
        fi
    fi
    
    # Skip PostgreSQL checks if only checking N8N
    if [ "$N8N_ONLY" != true ]; then
        # Check PostgreSQL deployment
        print_subsection "PostgreSQL Database"
        
        if kubectl get statefulset postgres -n n8n &>/dev/null; then
            local pg_ready=$(kubectl get statefulset postgres -n n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local pg_desired=$(kubectl get statefulset postgres -n n8n -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            local pg_image=$(kubectl get statefulset postgres -n n8n -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "Unknown")
            
            if [ "$pg_ready" -eq "$pg_desired" ] && [ "$pg_desired" -gt 0 ]; then
                print_success "PostgreSQL Deployment: $pg_ready/$pg_desired replicas ready"
                print_status "  Image: $pg_image"
                APP_DETAILS+=("PostgreSQL Deployment: READY ($pg_ready/$pg_desired)")
                APP_DETAILS+=("PostgreSQL Image: $pg_image")
            else
                print_fail "PostgreSQL Deployment: Only $pg_ready/$pg_desired replicas ready"
                APP_DETAILS+=("PostgreSQL Deployment: NOT_READY ($pg_ready/$pg_desired)")
                app_healthy=false
            fi
            
            # Check PostgreSQL service
            if kubectl get service postgres-service -n n8n &>/dev/null; then
                local pg_service_port=$(kubectl get service postgres-service -n n8n -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "Unknown")
                print_success "PostgreSQL Service: Available (Port: $pg_service_port)"
                APP_DETAILS+=("PostgreSQL Service: AVAILABLE (Port: $pg_service_port)")
            else
                print_fail "PostgreSQL Service: Not found"
                APP_DETAILS+=("PostgreSQL Service: NOT_FOUND")
                app_healthy=false
            fi
            
            # Check PostgreSQL pods
            local pg_pods_running=$(kubectl get pods -l app=n8n,component=database -n n8n --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            local pg_pods_total=$(kubectl get pods -l app=n8n,component=database -n n8n --no-headers 2>/dev/null | wc -l || echo "0")
            
            if [ "$pg_pods_running" -eq "$pg_pods_total" ] && [ "$pg_pods_total" -gt 0 ]; then
                print_success "PostgreSQL Pods: $pg_pods_running/$pg_pods_total running"
                APP_DETAILS+=("PostgreSQL Pods: $pg_pods_running/$pg_pods_total running")
            else
                print_warning "PostgreSQL Pods: Only $pg_pods_running/$pg_pods_total running"
                APP_DETAILS+=("PostgreSQL Pods: $pg_pods_running/$pg_pods_total running")
                if [ "$pg_pods_running" -lt "$pg_pods_total" ]; then
                    app_healthy=false
                fi
            fi
            
            # Check PersistentVolumeClaim
            if kubectl get pvc postgresql-pv-postgres-0 -n n8n &>/dev/null; then
                local pvc_status=$(kubectl get pvc postgresql-pv-postgres-0 -n n8n -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                local pvc_size=$(kubectl get pvc postgresql-pv-postgres-0 -n n8n -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo "Unknown")
                
                if [ "$pvc_status" = "Bound" ]; then
                    print_success "PostgreSQL Storage: PVC bound (Size: $pvc_size)"
                    APP_DETAILS+=("PostgreSQL Storage: BOUND ($pvc_size)")
                else
                    print_fail "PostgreSQL Storage: PVC $pvc_status"
                    APP_DETAILS+=("PostgreSQL Storage: $pvc_status")
                    app_healthy=false
                fi
            else
                print_warning "PostgreSQL Storage: PVC not found"
                APP_DETAILS+=("PostgreSQL Storage: NOT_FOUND")
            fi
        else
            print_fail "PostgreSQL Deployment: Not found"
            APP_DETAILS+=("PostgreSQL Deployment: NOT_FOUND")
            app_healthy=false
        fi
        
        # Get PostgreSQL connection details
        print_subsection "PostgreSQL Connection Details"
        local POSTGRES_USER=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_USER}' 2>/dev/null | base64 --decode 2>/dev/null || echo "N/A")
        local POSTGRES_PASSWORD=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_PASSWORD}' 2>/dev/null | base64 --decode 2>/dev/null || echo "N/A")
        local POSTGRES_HOST=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_HOST}' 2>/dev/null | base64 --decode 2>/dev/null || echo "N/A")
        local POSTGRES_PORT=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_PORT}' 2>/dev/null | base64 --decode 2>/dev/null || echo "N/A")
        local POSTGRES_DATABASE=$(kubectl get secret n8n-secrets -n n8n -o jsonpath='{.data.DB_POSTGRESDB_DATABASE}' 2>/dev/null | base64 --decode 2>/dev/null || echo "N/A")
        
        print_status "PostgreSQL Host: $POSTGRES_HOST"
        print_status "PostgreSQL Port: $POSTGRES_PORT"
        print_status "PostgreSQL User: $POSTGRES_USER"
        print_status "PostgreSQL Password: $POSTGRES_PASSWORD"
        print_status "PostgreSQL Database: $POSTGRES_DATABASE"
        
        APP_DETAILS+=("PostgreSQL Host: $POSTGRES_HOST")
        APP_DETAILS+=("PostgreSQL Port: $POSTGRES_PORT")
        APP_DETAILS+=("PostgreSQL User: $POSTGRES_USER")
        APP_DETAILS+=("PostgreSQL Database: $POSTGRES_DATABASE")
    fi
    
    # Check ingress/load balancer (skip if only checking database)
    if [ "$DB_ONLY" != true ]; then
        print_subsection "Network Access"
        
        if kubectl get ingress n8n-ingress -n n8n &>/dev/null; then
            local ingress_count=$(kubectl get ingress n8n-ingress -n n8n --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$ingress_count" -gt 0 ]; then
                print_success "Ingress: $ingress_count ingress rules found"
                APP_DETAILS+=("Ingress: $ingress_count rules configured")
                
                # Show ingress details
                kubectl get ingress n8n-ingress -n n8n --no-headers 2>/dev/null | while read -r name class hosts address ports age; do
                    print_status "  Ingress: $name -> $hosts (IP: $address)"
                done
            else
                print_warning "Ingress: No ingress rules found"
                APP_DETAILS+=("Ingress: NONE")
            fi
        else
            print_fail "Ingress: n8n-ingress not found in n8n namespace"
            APP_DETAILS+=("Ingress: NOT_FOUND")
            app_healthy=false
        fi
        
        # Check for LoadBalancer services
        local lb_services=$(kubectl get services -n n8n --no-headers 2>/dev/null | grep -c "LoadBalancer" 2>/dev/null || echo "0")
        if [ "$lb_services" -gt 0 ]; then
            print_warning "Load Balancer Services: $lb_services found"
            APP_DETAILS+=("Load Balancer: $lb_services services")
        else
            print_status "Load Balancer Services: None found (expected for N8N with Ingress)"
            APP_DETAILS+=("Load Balancer: NONE (expected)")
        fi
        
        # Get all external IP mappings
        get_external_ip_mappings
        
        # Get comprehensive N8N connection details
        get_n8n_connection_details
    fi
    
    # Set application status
    if [ "$app_healthy" = true ]; then
        APP_STATUS="HEALTHY"
        print_success "Application Status: HEALTHY"
    else
        APP_STATUS="UNHEALTHY"
        print_fail "Application Status: UNHEALTHY"
    fi
}

# Function to print summary
print_summary() {
    print_section "SUMMARY"
    
    echo -e "${CYAN}Environment:${NC} $ENVIRONMENT"
    echo -e "${CYAN}Project ID:${NC} $PROJECT_ID"
    echo -e "${CYAN}Region/Zone:${NC} $REGION/$ZONE"
    echo -e "${CYAN}Cluster:${NC} $CLUSTER_NAME"
    echo ""
    
    if [ "$CHECK_INFRA" = true ]; then
        if [ "$INFRA_STATUS" = "HEALTHY" ]; then
            echo -e "${GREEN}Infrastructure Status: HEALTHY${NC}"
        elif [ "$INFRA_STATUS" = "UNHEALTHY" ]; then
            echo -e "${RED}Infrastructure Status: UNHEALTHY${NC}"
        else
            echo -e "${YELLOW}Infrastructure Status: NOT_CHECKED${NC}"
        fi
        
        if [ ${#INFRA_DETAILS[@]} -gt 0 ]; then
            echo -e "${CYAN}Infrastructure Details:${NC}"
            for detail in "${INFRA_DETAILS[@]}"; do
                echo "  - $detail"
            done
        fi
        echo ""
    fi
    
    if [ "$CHECK_APP" = true ]; then
        if [ "$APP_STATUS" = "HEALTHY" ]; then
            echo -e "${GREEN}Application Status: HEALTHY${NC}"
        elif [ "$APP_STATUS" = "UNHEALTHY" ]; then
            echo -e "${RED}Application Status: UNHEALTHY${NC}"
        else
            echo -e "${YELLOW}Application Status: NOT_CHECKED${NC}"
        fi
        
        if [ ${#APP_DETAILS[@]} -gt 0 ]; then
            echo -e "${CYAN}Application Details:${NC}"
            for detail in "${APP_DETAILS[@]}"; do
                echo "  - $detail"
            done
        fi
        echo ""
    fi
    
    # Overall status
    if [ "$CHECK_INFRA" = true ] && [ "$CHECK_APP" = true ]; then
        if [ "$INFRA_STATUS" = "HEALTHY" ] && [ "$APP_STATUS" = "HEALTHY" ]; then
            echo -e "${GREEN}Overall Status: HEALTHY${NC}"
            echo -e "${GREEN}✓ All components are running normally${NC}"
        else
            echo -e "${RED}Overall Status: ISSUES_DETECTED${NC}"
            echo -e "${YELLOW}⚠ Some components need attention${NC}"
        fi
    elif [ "$CHECK_INFRA" = true ]; then
        if [ "$INFRA_STATUS" = "HEALTHY" ]; then
            echo -e "${GREEN}Infrastructure Overall: HEALTHY${NC}"
        else
            echo -e "${RED}Infrastructure Overall: UNHEALTHY${NC}"
        fi
    elif [ "$CHECK_APP" = true ]; then
        if [ "$APP_STATUS" = "HEALTHY" ]; then
            echo -e "${GREEN}Application Overall: HEALTHY${NC}"
        else
            echo -e "${RED}Application Overall: UNHEALTHY${NC}"
        fi
    fi
    
    # Quick access commands
    echo -e "${PURPLE}========== QUICK ACCESS COMMANDS ==========${NC}"
    if [ "$CHECK_APP" = true ] && [ "$DB_ONLY" != true ] && [ "$APP_STATUS" = "HEALTHY" ]; then
        echo -e "${CYAN}Port Forward N8N (Local Development):${NC}"
        echo "  kubectl port-forward svc/n8n-service 5678:80 -n n8n"
        echo "  Then access: http://localhost:5678"
        echo ""
    fi
    
    if [ "$CHECK_APP" = true ] && [ "$N8N_ONLY" != true ] && [ "$APP_STATUS" = "HEALTHY" ]; then
        echo -e "${CYAN}PostgreSQL Direct Access:${NC}"
        echo "  kubectl port-forward svc/postgres-service 5432:5432 -n n8n"
        echo "  Then connect: psql -h localhost -p 5432 -U \$POSTGRES_USER -d \$POSTGRES_DATABASE"
        echo ""
    fi
    
    echo -e "${CYAN}Pod Logs:${NC}"
    echo "  N8N Logs: kubectl logs -l app=n8n,component=deployment -n n8n -f"
    echo "  PostgreSQL Logs: kubectl logs -l app=n8n,component=database -n n8n -f"
    echo ""
    
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "  Check all pods: kubectl get pods -n n8n -o wide"
    echo "  Check services: kubectl get svc -n n8n"
    echo "  Check ingress: kubectl get ingress -n n8n"
    echo "  Check events: kubectl get events -n n8n --sort-by='.lastTimestamp'"
    echo ""
    
    echo -e "${CYAN}Management Scripts:${NC}"
    echo "  Deploy/Update: ./dev-deploy.sh"
    echo "  Infrastructure Only: ./dev-deploy.sh --infra-only"
    echo "  Application Only: ./dev-deploy.sh --app-only"
    echo "  Destroy All: ./dev-deploy.sh --destroy"
    echo "  Redeploy N8N: ./dev-deploy.sh --destroy --app-only --n8n-only"
    echo "  Redeploy Database: ./dev-deploy.sh --destroy --app-only --db-only"
}

# Main execution
main() {
    print_section "N8N DEVELOPMENT ENVIRONMENT STATUS CHECK"
    
    # Check GCP authentication
    check_gcp_auth
    echo ""
    
    # Check infrastructure if requested
    if [ "$CHECK_INFRA" = true ]; then
        check_infrastructure_status
        echo ""
    fi
    
    # Check application if requested
    if [ "$CHECK_APP" = true ]; then
        check_application_status
        echo ""
    fi
    
    # Print summary
    print_summary
}

# Run main function
main