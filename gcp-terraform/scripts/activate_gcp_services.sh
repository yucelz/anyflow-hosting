#!/bin/bash

# This script activates the necessary GCP services for the N8N development environment.

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "Activating required GCP services..."

# List of required services
SERVICES=(
    "container.googleapis.com"
    "compute.googleapis.com"
    "certificatemanager.googleapis.com"
    "iam.googleapis.com"
    "iamcredentials.googleapis.com" # Required for Workload Identity Federation
)

PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    print_error "GCP project not set. Please run 'gcloud config set project YOUR_PROJECT_ID'."
    exit 1
fi

print_status "Ensuring gcloud is authenticated and project is set to: $PROJECT_ID"

for SERVICE in "${SERVICES[@]}"; do
    print_status "Enabling service: $SERVICE"
    if gcloud services enable "$SERVICE" --project="$PROJECT_ID" --async; then
        print_status "Service $SERVICE enabled successfully (or was already enabled)."
    else
        print_error "Failed to enable service: $SERVICE. Please check your permissions."
        exit 1
    fi
done

print_status "All specified GCP services are being enabled in the background. It may take a few minutes for them to become fully active."
print_status "You can check the status of services in the GCP Console or by running 'gcloud services list --project=$PROJECT_ID'."
