#!/bin/bash

# Exit on error
set -e

# Check for project_id argument
if [ -z "$1" ]; then
  echo "Usage: $0 <PROJECT_ID> [REGION]"
  echo "REGION is optional and defaults to us-central1"
  exit 1
fi

PROJECT_ID="$1"
REGION="${2:-us-central1}"
echo "Deleting all resources in project: $PROJECT_ID"
echo "Using region: $REGION for regional resources"
gcloud config set project "$PROJECT_ID"

### Step 1: Delete Kubernetes Node Pools (must be done before clusters)
echo "Deleting Kubernetes Node Pools..."
gcloud container clusters list --project="$PROJECT_ID" --format="value(name,zone)" | while read -r cluster_name zone; do
  if [ ! -z "$cluster_name" ]; then
    echo "  Checking node pools for cluster: $cluster_name in zone: $zone"
    gcloud container node-pools list --cluster="$cluster_name" --zone="$zone" --project="$PROJECT_ID" --format="value(name)" | while read -r pool_name; do
      if [ ! -z "$pool_name" ]; then
        echo "    Deleting node pool: $pool_name"
        gcloud container node-pools delete "$pool_name" --cluster="$cluster_name" --zone="$zone" --quiet || true
      fi
    done
  fi
done

### Step 2: Delete Kubernetes clusters
echo "Deleting Kubernetes clusters..."
gcloud container clusters list --project="$PROJECT_ID" --format="value(name,zone)" | while read -r name zone; do
  if [ ! -z "$name" ]; then
    echo "  Deleting cluster: $name in zone: $zone"
    gcloud container clusters delete "$name" --zone="$zone" --quiet || true
  fi
done

### Step 3: Delete Compute Engine instances
echo "Deleting Compute Engine instances..."
gcloud compute instances list --project="$PROJECT_ID" --format="value(name,zone)" | while read -r name zone; do
  if [ ! -z "$name" ]; then
    echo "  Deleting instance: $name in zone: $zone"
    gcloud compute instances delete "$name" --zone="$zone" --quiet || true
  fi
done

### Step 4: Delete Cloud Run services
echo "Deleting Cloud Run services..."
gcloud run services list --platform=managed --project="$PROJECT_ID" --format="value(name,region)" | while read -r name region; do
  if [ ! -z "$name" ]; then
    echo "  Deleting Cloud Run service: $name in region: $region"
    gcloud run services delete "$name" --region="$region" --quiet || true
  fi
done

### Step 5: Delete Cloud Functions
echo "Deleting Cloud Functions..."
gcloud functions list --project="$PROJECT_ID" --format="value(name,region)" | while read -r name region; do
  if [ ! -z "$name" ]; then
    echo "  Deleting function: $name in region: $region"
    gcloud functions delete "$name" --region="$region" --quiet || true
  fi
done

### Step 6: Delete Cloud Storage buckets
echo "Deleting Cloud Storage buckets..."
gcloud storage buckets list --project="$PROJECT_ID" --format="value(name)" | while read -r bucket; do
  if [ ! -z "$bucket" ]; then
    echo "  Deleting bucket: $bucket"
    # First try to remove all objects, then delete bucket
    gcloud storage rm -r "gs://$bucket/**" --quiet 2>/dev/null || true
    gcloud storage buckets delete "gs://$bucket" --quiet || true
  fi
done

### Step 7: Delete Firestore Databases
echo "Deleting Firestore Databases..."
gcloud firestore databases list --project="$PROJECT_ID" --format="value(name)" | while read -r name; do
  if [ ! -z "$name" ] && [ "$name" != "(default)" ]; then
    echo "  Deleting Firestore database: $name"
    gcloud firestore databases delete "$name" --quiet || true
  fi
done

### Step 8: Delete Network Security Policies
echo "Deleting Network Security Policies..."
gcloud compute security-policies list --project="$PROJECT_ID" --format="value(name)" | while read -r name; do
  if [ ! -z "$name" ] && [ "$name" != "default-security-policy-for-backend-service" ]; then
    echo "  Deleting security policy: $name"
    gcloud compute security-policies delete "$name" --quiet || true
  fi
done

### Step 9: Delete Firewall Rules (except default ones)
echo "Deleting custom Firewall Rules..."
gcloud compute firewall-rules list --project="$PROJECT_ID" --format="value(name)" | while read -r name; do
  if [ ! -z "$name" ] && [[ ! "$name" =~ ^default-.* ]]; then
    echo "  Deleting firewall rule: $name"
    gcloud compute firewall-rules delete "$name" --quiet || true
  fi
done

### Step 10: Delete Cloud Routers (must be done before subnets and VPCs)
echo "Deleting Cloud Routers..."
# First delete the specific dev-n8n-cluster-n8n-vpc-router
echo "  Deleting router: dev-n8n-cluster-n8n-vpc-router in region: $REGION"
gcloud compute routers delete "dev-n8n-cluster-n8n-vpc-router" --region="$REGION" --quiet || true

# Then delete any other custom routers
gcloud compute routers list --project="$PROJECT_ID" --format="value(name,region)" | while read -r name region; do
  if [ ! -z "$name" ]; then
    echo "  Deleting router: $name in region: $region"
    gcloud compute routers delete "$name" --region="$region" --quiet || true
  fi
done

### Step 11: Delete VPC Subnets (except default ones)
echo "Deleting custom VPC Subnets..."
gcloud compute networks subnets list --project="$PROJECT_ID" --format="value(name,region)" | while read -r name region; do
  if [ ! -z "$name" ] && [[ ! "$name" =~ ^default$ ]]; then
    echo "  Deleting subnet: $name in region: $region"
    gcloud compute networks subnets delete "$name" --region="$region" --quiet || true
  fi
done

### Step 12: Delete VPC Networks (except default)
echo "Deleting custom VPC Networks..."
gcloud compute networks list --project="$PROJECT_ID" --format="value(name)" | while read -r name; do
  if [ ! -z "$name" ] && [ "$name" != "default" ]; then
    echo "  Deleting network: $name"
    gcloud compute networks delete "$name" --quiet || true
  fi
done

### Step 13: Delete Service Accounts (except default ones)
echo "Deleting custom Service Accounts..."
gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)" | while read -r email; do
  if [ ! -z "$email" ] && [[ ! "$email" =~ .*@.*\.iam\.gserviceaccount\.com$ ]] || [[ "$email" =~ ^[^@]*@$PROJECT_ID\.iam\.gserviceaccount\.com$ ]]; then
    # Only delete service accounts that belong to this project and are not Google-managed
    if [[ "$email" =~ ^[^@]*@$PROJECT_ID\.iam\.gserviceaccount\.com$ ]] && [[ ! "$email" =~ ^[0-9]+-compute@developer\.gserviceaccount\.com$ ]] && [[ ! "$email" =~ .*@appspot\.gserviceaccount\.com$ ]]; then
      echo "  Deleting service account: $email"
      gcloud iam service-accounts delete "$email" --quiet || true
    fi
  fi
done

echo ""
echo "============================================"
echo "All resource deletions attempted."
echo "============================================"
echo "Note: Some resources may require manual cleanup, including:"
echo "- Default networks, subnets, and firewall rules"
echo "- Google-managed service accounts"
echo "- IAM bindings (must be removed manually)"
echo "- The default Firestore database"
echo "- Some resources may have dependencies that prevent deletion"
echo ""
echo "To check remaining resources, run the list script:"
echo "./list_gcp_resources.sh $PROJECT_ID"
