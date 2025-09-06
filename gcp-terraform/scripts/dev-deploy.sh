#!/bin/bash

# Deploy Dev Environment - Wrapper Script
# This script orchestrates the deployment of both infrastructure and application
# Usage: ./dev-deploy.sh [--destroy] [--help] [--infra-only] [--app-only]

set -e

# Parse command line arguments
DESTROY_MODE=false
SHOW_HELP=false
INFRA_ONLY=false
APP_ONLY=false
DB_ONLY=false
N8N_ONLY=false

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
        --infra-only)
            INFRA_ONLY=true
            shift
            ;;
        --app-only)
            APP_ONLY=true
            shift
            ;;
        --db-only)
            DB_ONLY=true
            shift
            ;;
        --n8n-only)
            N8N_ONLY=true
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
    echo "Deploy or destroy the N8N development environment"
    echo ""
    echo "OPTIONS:"
    echo "  --destroy      Destroy the existing environment instead of deploying"
    echo "  --infra-only   Deploy/destroy only infrastructure (Network + GKE)"
    echo "  --app-only     Deploy/destroy only application (N8N + PostgreSQL)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    Deploy complete environment (infrastructure + application)"
    echo "  $0 --infra-only       Deploy only infrastructure"
    echo "  $0 --app-only         Deploy only application (requires infrastructure)"
    echo "  $0 --destroy          Destroy complete environment"
    echo "  $0 --destroy --app-only    Destroy only application"
    echo "  $0 --destroy --infra-only  Destroy only infrastructure"
    echo "  $0 --destroy --app-only --db-only    Destroy and redeploy PostgreSQL"
    echo "  $0 --destroy --app-only --n8n-only   Destroy and redeploy N8N"
    echo ""
    echo "Individual Scripts:"
    echo "  ./dev-infra.sh        Infrastructure deployment script"
    echo "  ./dev-app.sh          Application deployment script"
    echo ""
    exit 0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_section() {
    echo -e "${PURPLE}========== $1 ==========${NC}"
}

# Get script directory
SCRIPT_DIR="$(dirname "$0")"

# Validate that individual scripts exist
if [ ! -f "$SCRIPT_DIR/dev-infra.sh" ]; then
    print_error "dev-infra.sh not found in scripts directory"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/dev-app.sh" ]; then
    print_error "dev-app.sh not found in scripts directory"
    exit 1
fi

# Make sure scripts are executable
chmod +x "$SCRIPT_DIR/dev-infra.sh" "$SCRIPT_DIR/dev-app.sh"

if [ "$DESTROY_MODE" = true ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}    N8N Dev Environment Destruction    ${NC}"
    echo -e "${RED}      Orchestrated Destruction        ${NC}"
    echo -e "${RED}========================================${NC}"
    
    if [ "$INFRA_ONLY" = true ]; then
        print_section "INFRASTRUCTURE DESTRUCTION ONLY"
        print_status "Destroying infrastructure using dev-infra.sh..."
        "$SCRIPT_DIR/dev-infra.sh" --destroy
        
    elif [ "$APP_ONLY" = true ]; then
        if [ "$DB_ONLY" = true ]; then
            print_section "DATABASE DESTRUCTION AND REDEPLOYMENT"
            read -p "Are you sure you want to destroy and redeploy the PostgreSQL database? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Destroying PostgreSQL database..."
                "$SCRIPT_DIR/dev-app.sh" --destroy --db-only
                print_status "Redeploying PostgreSQL database..."
                "$SCRIPT_DIR/dev-app.sh" --db-only
                print_success "PostgreSQL database has been redeployed."
            else
                print_warning "Operation cancelled."
            fi
        elif [ "$N8N_ONLY" = true ]; then
            print_section "N8N DESTRUCTION AND REDEPLOYMENT"
            read -p "Are you sure you want to destroy and redeploy N8N? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Destroying N8N..."
                "$SCRIPT_DIR/dev-app.sh" --destroy --n8n-only
                print_status "Redeploying N8N..."
                "$SCRIPT_DIR/dev-app.sh" --n8n-only
                print_success "N8N has been redeployed."
            else
                print_warning "Operation cancelled."
            fi
        else
            print_section "APPLICATION DESTRUCTION ONLY"
            print_status "Destroying application using dev-app.sh..."
            "$SCRIPT_DIR/dev-app.sh" --destroy
        fi
        
    else
        print_section "COMPLETE ENVIRONMENT DESTRUCTION"
        print_status "Destroying complete environment (application first, then infrastructure)..."
        
        # First destroy application
        print_status "Step 1: Destroying application..."
        "$SCRIPT_DIR/dev-app.sh" --destroy
        
        # Then destroy infrastructure
        print_status "Step 2: Destroying infrastructure..."
        "$SCRIPT_DIR/dev-infra.sh" --destroy
        
        print_section "COMPLETE DESTRUCTION FINISHED"
        print_success "Complete N8N development environment has been destroyed!"
    fi
    
else
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    N8N Dev Environment Deployment     ${NC}"
    echo -e "${BLUE}      Orchestrated Deployment         ${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Activate necessary GCP services before any deployment
    print_section "ACTIVATING GCP SERVICES"
    print_status "Ensuring all required GCP services are enabled..."
    "$SCRIPT_DIR/activate_gcp_services.sh"
    
    if [ "$INFRA_ONLY" = true ]; then
        print_section "INFRASTRUCTURE DEPLOYMENT ONLY"
        print_status "Deploying infrastructure using dev-infra.sh..."
        "$SCRIPT_DIR/dev-infra.sh"
        
    elif [ "$APP_ONLY" = true ]; then
        print_section "APPLICATION DEPLOYMENT ONLY"
        print_status "Deploying application using dev-app.sh..."
        
        # Check for potential Terraform state drift issues before deployment
        print_status "Checking for Terraform state drift issues..."
        cd "$(dirname "$0")/.."
        
        # Check if cluster endpoint has changed (common cause of state drift)
        if terraform state list | grep -q "module.n8n" && ! kubectl cluster-info &>/dev/null; then
            print_warning "Detected potential state drift - kubectl cannot connect to cluster"
            print_status "Attempting to fix state drift by cleaning up orphaned Kubernetes resources..."
            
            # Remove Kubernetes resources that might be pointing to old cluster endpoint
            terraform state rm module.n8n.kubernetes_secret.n8n_secrets 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_secret.postgres_secret 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_config_map.postgres_init_data 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_persistent_volume_claim.n8n_claim0 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_service.postgres 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_service.n8n 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_manifest.backend_config 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_namespace.n8n 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_stateful_set.postgres 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_deployment.n8n 2>/dev/null || true
            terraform state rm module.n8n.kubernetes_ingress_v1.n8n_ingress 2>/dev/null || true
            
            print_status "State cleanup completed - resources will be recreated"
        fi
        
        cd "$SCRIPT_DIR"
        ./dev-app.sh
        
    else
        print_section "COMPLETE ENVIRONMENT DEPLOYMENT"
        print_status "Deploying complete environment (infrastructure first, then application)..."
        
        # First deploy infrastructure
        print_status "Step 1: Deploying infrastructure..."
        "$SCRIPT_DIR/dev-infra.sh"
        
        # Then deploy application
        print_status "Step 2: Deploying application..."
        "$SCRIPT_DIR/dev-app.sh"
        
        print_section "COMPLETE DEPLOYMENT FINISHED"
        print_success "Complete N8N development environment has been deployed!"
        
        echo ""
        echo -e "${YELLOW}Environment Summary:${NC}"
        echo -e "${YELLOW}  • Infrastructure: Single Zonal GKE Cluster (1-2 nodes) and Network${NC}"
        echo -e "${YELLOW}  • Application: Single N8N instance + Single PostgreSQL instance${NC}"
        echo -e "${YELLOW}  • External Access: Single Static External IP with SSL (https://www.any-flow.com)${NC}"
        echo ""
        echo -e "${YELLOW}Note: The GKE cluster is configured as a single zonal cluster with 1-2 nodes for development purposes. All other components (N8N, PostgreSQL, External IP) are deployed as single instances.${NC}"
        echo ""
        echo -e "${YELLOW}Individual Management:${NC}"
        echo -e "${YELLOW}  • Infrastructure: ./scripts/dev-infra.sh [--destroy]${NC}"
        echo -e "${YELLOW}  • Application: ./scripts/dev-app.sh [--destroy]${NC}"
    fi
fi

print_success "Operation completed successfully!"
