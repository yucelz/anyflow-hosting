#!/bin/bash

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <PROJECT_ID>"
  exit 1
fi

PROJECT_ID="$1"
echo "Listing resources in project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

### Existing Resource Checks
echo -e "\n=== Compute Engine Instances ==="
gcloud compute instances list --project="$PROJECT_ID"

echo -e "\n=== Cloud Storage Buckets ==="
gcloud storage buckets list --project="$PROJECT_ID"

echo -e "\n=== Cloud Functions ==="
gcloud functions list --project="$PROJECT_ID"

echo -e "\n=== Cloud Run Services ==="
gcloud run services list --platform=managed --project="$PROJECT_ID"

echo -e "\n=== Kubernetes Clusters (GKE) ==="
gcloud container clusters list --project="$PROJECT_ID"

echo -e "\n=== VPC Networks ==="
gcloud compute networks list --project="$PROJECT_ID"

echo -e "\n=== VPC Subnets ==="
gcloud compute networks subnets list --project="$PROJECT_ID"

echo -e "\n=== Firewall Rules ==="
gcloud compute firewall-rules list --project="$PROJECT_ID"

echo -e "\n=== Network Security Policies ==="
gcloud compute security-policies list --project="$PROJECT_ID"

### Additional Resources from main.tf
echo -e "\n=== Service Accounts (google_service_account) ==="
gcloud iam service-accounts list --project="$PROJECT_ID"

echo -e "\n=== IAM Bindings (google_project_iam_member & google_service_account_iam_binding) ==="
gcloud projects get-iam-policy "$PROJECT_ID" --format=json

echo -e "\n=== Kubernetes Node Pools (google_container_node_pool) ==="
gcloud container node-pools list --cluster=primary --region=<YOUR_REGION> --project="$PROJECT_ID"

echo -e "\nResource listing completed."
