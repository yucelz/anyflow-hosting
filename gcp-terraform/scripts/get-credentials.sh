#!/bin/bash

# Get GKE Cluster Credentials Script
# This script helps get the correct credentials for the GKE cluster
# Usage: ./get-credentials.sh [environment]

set -e

# Parse command line arguments
ENVIRONMENT=${1:-"dev"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration based on environment
PROJECT_ID="anyflow-469911"
REGION="us-central1"
ZONE="us-central1-a"
CLUSTER_NAME="${ENVIRONMENT}-n8n-cluster"

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    GKE Cluster Credentials Setup      ${NC}"
echo -e "${BLUE}========================================${NC}"

print_status "Environment: $ENVIRONMENT"
print_status "Project: $PROJECT_ID"
print_status "Cluster: $CLUSTER_NAME"
print_status "Zone: $ZONE"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI is not installed. Please install Google Cloud SDK."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    print_error "No active gcloud authentication found."
    print_status "Please run: gcloud auth login"
    exit 1
fi

# Set the project
print_status "Setting GCP project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

# Check if cluster exists
print_status "Checking if cluster exists..."
if ! gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
    print_error "Cluster $CLUSTER_NAME not found in zone $ZONE"
    print_status "Available clusters:"
    gcloud container clusters list --project="$PROJECT_ID"
    exit 1
fi

# Get cluster status
CLUSTER_STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)")
print_status "Cluster status: $CLUSTER_STATUS"

if [ "$CLUSTER_STATUS" != "RUNNING" ]; then
    print_warning "Cluster is not in RUNNING state. Current state: $CLUSTER_STATUS"
    print_status "Attempting to get credentials anyway..."
fi

# Get credentials
print_status "Getting cluster credentials..."
if gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID"; then
    print_success "Credentials obtained successfully!"
else
    print_error "Failed to get cluster credentials"
    exit 1
fi

# Test connectivity
print_status "Testing cluster connectivity..."
if kubectl cluster-info --request-timeout=30s &>/dev/null; then
    print_success "Cluster connectivity test passed!"
    
    # Show cluster info
    echo ""
    print_status "Cluster Information:"
    kubectl cluster-info
    
    echo ""
    print_status "Node Status:"
    kubectl get nodes
    
else
    print_warning "Cluster connectivity test failed, but credentials were set"
    print_status "This might be due to network restrictions or cluster startup time"
fi

echo ""
print_success "Credentials setup completed!"
print_status "You can now use kubectl to interact with the cluster"
print_status "Example commands:"
echo -e "${YELLOW}  kubectl get nodes${NC}"
echo -e "${YELLOW}  kubectl get pods --all-namespaces${NC}"
echo -e "${YELLOW}  kubectl get svc --all-namespaces${NC}"
