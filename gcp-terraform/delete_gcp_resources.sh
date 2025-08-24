#!/bin/bash

# Exit on error
set -e

# Check for project_id argument
if [ -z "$1" ]; then
  echo "Usage: $0 <PROJECT_ID>"
  exit 1
fi

PROJECT_ID="$1"
echo "Deleting all resources in project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

### Step 1: Delete Compute Engine instances
echo "Deleting Compute Engine instances..."
gcloud compute instances list --project="$PROJECT_ID" --format="value(name,zone)" | while read -r name zone; do
  gcloud compute instances delete "$name" --zone="$zone" --quiet
done

### Step 2: Delete Cloud Storage buckets
echo "Deleting Cloud Storage buckets..."
gcloud storage buckets list --project="$PROJECT_ID" --format="value(name)" | while read -r bucket; do
  gcloud storage buckets delete "gs://$bucket" --quiet
done

### Step 3: Delete Cloud Functions
echo "Deleting Cloud Functions..."
gcloud functions list --project="$PROJECT_ID" --format="value(name,region)" | while read -r name region; do
  gcloud functions delete "$name" --region="$region" --quiet
done

### Step 4: Delete Cloud Run services
echo "Deleting Cloud Run services..."
gcloud run services list --platform=managed --project="$PROJECT_ID" --format="value(name,region)" | while read -r name region; do
  gcloud run services delete "$name" --region="$region" --quiet
done

### Step 5: Delete Kubernetes clusters
echo "Deleting Kubernetes clusters..."
gcloud container clusters list --project="$PROJECT_ID" --format="value(name,zone)" | while read -r name zone; do
  gcloud container clusters delete "$name" --zone="$zone" --quiet
done

### Step 6: Delete Firestore Databases
echo "Deleting Firestore Databases..."
gcloud firestore databases list --project="$PROJECT_ID" --format="value(name)" | while read -r name; do
  gcloud firestore databases delete "$name" --quiet
done

echo "All deletions attempted. Some resources may require manual cleanup."
