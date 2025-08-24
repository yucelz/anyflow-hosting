#!/bin/bash

# Deploy Production Environment - Full N8N Deployment
# High availability, scalable configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="prod"
PROJECT_ID="anyflow-469911"
REGION="us-central1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   N8N Production Environment Deploy   ${NC}"
echo -e "${BLUE}  High Availability & Scalable Setup   ${NC}"
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

# Check if gcloud is installed and authenticated
print_status "Checking gcloud authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
    exit 1
fi

# Set the project
print_status "Setting GCP project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# Check if required APIs are enabled
print_status "Checking required APIs..."
REQUIRED_APIS=(
    "container.googleapis.com"
    "compute.googleapis.com"
    "certificatemanager.googleapis.com"
    "iam.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        print_warning "Enabling $api..."
        gcloud services enable $api
    else
        print_status "$api is already enabled"
    fi
done

# Navigate to terraform directory
cd "$(dirname "$0")/.."

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init

# Select workspace or create if it doesn't exist
print_status "Setting up Terraform workspace for $ENVIRONMENT..."
if terraform workspace list | grep -q "$ENVIRONMENT"; then
    terraform workspace select $ENVIRONMENT
else
    terraform workspace new $ENVIRONMENT
fi

# Validate configuration
print_status "Validating Terraform configuration..."
terraform validate

# Plan the deployment
print_status "Planning Terraform deployment for production environment..."
terraform plan \
    -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
    -out="terraform-$ENVIRONMENT.tfplan"

# Show resource summary
print_status "Deployment Summary for Production Environment:"
echo -e "${YELLOW}  • GKE Cluster: Regional (multi-zone)${NC}"
echo -e "${YELLOW}  • Node Pool: 3-10 nodes (e2-standard-2)${NC}"
echo -e "${YELLOW}  • N8N: Multiple replicas with autoscaling${NC}"
echo -e "${YELLOW}  • PostgreSQL: Production instance${NC}"
echo -e "${YELLOW}  • Storage: 50Gi+ production storage${NC}"
echo -e "${YELLOW}  • Monitoring: Enabled${NC}"
echo -e "${YELLOW}  • Workload Identity: Enabled${NC}"
echo -e "${YELLOW}  • Network Policies: Enabled${NC}"

# Production deployment warning
echo ""
echo -e "${RED}⚠️  PRODUCTION DEPLOYMENT WARNING ⚠️${NC}"
echo -e "${RED}This will deploy production resources with higher costs!${NC}"
echo -e "${RED}Estimated monthly cost: $300-500+${NC}"
echo ""

# Ask for confirmation
read -p "Are you sure you want to deploy to PRODUCTION? Type 'PRODUCTION' to confirm: " -r
echo ""
if [[ ! $REPLY == "PRODUCTION" ]]; then
    print_warning "Production deployment cancelled - confirmation not received"
    exit 0
fi

# Final confirmation
echo -e "${YELLOW}Last chance to cancel...${NC}"
read -p "Proceed with production deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Production deployment cancelled by user"
    exit 0
fi

# Apply the configuration
print_status "Applying Terraform configuration for PRODUCTION..."
terraform apply "terraform-$ENVIRONMENT.tfplan"

# Get cluster credentials
print_status "Getting cluster credentials..."
gcloud container clusters get-credentials \
    "${ENVIRONMENT}-n8n-cluster" \
    --region=$REGION \
    --project=$PROJECT_ID

# Verify deployment
print_status "Verifying production deployment..."
echo ""
echo -e "${GREEN}Cluster Information:${NC}"
kubectl cluster-info

echo ""
echo -e "${GREEN}Node Information:${NC}"
kubectl get nodes -o wide

echo ""
echo -e "${GREEN}N8N Pods:${NC}"
kubectl get pods -n n8n

echo ""
echo -e "${GREEN}Services:${NC}"
kubectl get services -n n8n

echo ""
echo -e "${GREEN}Ingress:${NC}"
kubectl get ingress -n n8n

echo ""
echo -e "${GREEN}Horizontal Pod Autoscaler:${NC}"
kubectl get hpa -n n8n

# Get external IP
print_status "Getting external IP address..."
EXTERNAL_IP=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    Production Deployment Complete     ${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Region:${NC} $REGION"
echo -e "${GREEN}External IP:${NC} $EXTERNAL_IP"
echo -e "${GREEN}Domain:${NC} www.any-flow.com"
echo ""
echo -e "${YELLOW}Note: SSL certificate may take 10-15 minutes to provision${NC}"
echo -e "${YELLOW}Monitor certificate status: kubectl describe managedcertificate -n n8n${NC}"
echo ""

# Show resource usage
print_status "Production Resource Summary:"
echo -e "${GREEN}  • Cluster Type: Regional (High Availability)${NC}"
echo -e "${GREEN}  • Node Pool: Auto-scaling enabled${NC}"
echo -e "${GREEN}  • N8N: Multiple replicas with HPA${NC}"
echo -e "${GREEN}  • PostgreSQL: Production configuration${NC}"
echo -e "${GREEN}  • Monitoring: Full monitoring enabled${NC}"
echo -e "${GREEN}  • Security: Network policies & Workload Identity${NC}"

# Production monitoring recommendations
echo ""
print_status "Production Monitoring Recommendations:"
echo -e "${YELLOW}  • Set up alerting for critical metrics${NC}"
echo -e "${YELLOW}  • Configure log aggregation${NC}"
echo -e "${YELLOW}  • Implement backup strategies${NC}"
echo -e "${YELLOW}  • Monitor resource usage and costs${NC}"
echo -e "${YELLOW}  • Set up disaster recovery procedures${NC}"

print_status "Production deployment completed successfully!"
print_warning "Remember to configure monitoring, alerting, and backup procedures!"
