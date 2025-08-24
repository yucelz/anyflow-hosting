#!/bin/bash

# Deploy Dev Environment - Minimized N8N Deployment
# Maximum 2 nodes, single resource per product

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="dev"
PROJECT_ID="anyflow-469911"
REGION="us-central1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    N8N Dev Environment Deployment     ${NC}"
echo -e "${BLUE}  Maximum 2 nodes, single resources    ${NC}"
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
print_status "Planning Terraform deployment for dev environment..."
terraform plan \
    -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
    -out="terraform-$ENVIRONMENT.tfplan"

# Show resource summary
print_status "Deployment Summary for Dev Environment:"
echo -e "${YELLOW}  • GKE Cluster: Zonal (single zone)${NC}"
echo -e "${YELLOW}  • Node Pool: 1-2 nodes maximum (e2-micro)${NC}"
echo -e "${YELLOW}  • N8N: Single replica (100m CPU, 128Mi RAM)${NC}"
echo -e "${YELLOW}  • PostgreSQL: Single instance (50m CPU, 64Mi RAM)${NC}"
echo -e "${YELLOW}  • Storage: 5Gi minimal storage${NC}"
echo -e "${YELLOW}  • Monitoring: Disabled${NC}"
echo -e "${YELLOW}  • Workload Identity: Disabled${NC}"

# Ask for confirmation
echo ""
read -p "Do you want to apply this dev deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled by user"
    exit 0
fi

# Apply the configuration
print_status "Applying Terraform configuration..."
terraform apply "terraform-$ENVIRONMENT.tfplan"

# Get cluster credentials
print_status "Getting cluster credentials..."
gcloud container clusters get-credentials \
    "${ENVIRONMENT}-n8n-cluster" \
    --region=$REGION \
    --project=$PROJECT_ID

# Verify deployment
print_status "Verifying deployment..."
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

# Get external IP
print_status "Getting external IP address..."
EXTERNAL_IP=$(kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      Dev Deployment Complete          ${NC}"
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
print_status "Resource Usage Summary:"
echo -e "${GREEN}  • Maximum Nodes: 2${NC}"
echo -e "${GREEN}  • N8N Replicas: 1${NC}"
echo -e "${GREEN}  • PostgreSQL Instances: 1${NC}"
echo -e "${GREEN}  • Total CPU Request: ~150m${NC}"
echo -e "${GREEN}  • Total Memory Request: ~192Mi${NC}"
echo -e "${GREEN}  • Storage: 5Gi${NC}"

print_status "Deployment completed successfully!"
