#!/bin/bash
# Usage: ./gcloud_project_cleanup.sh PROJECT_ID

set -euo pipefail

PROJECT_ID="$1"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Usage: $0 PROJECT_ID"
  exit 1
fi

echo "⚠️ WARNING: This will delete ALL resources in project [$PROJECT_ID] and the project itself!"
read -p "Are you sure? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo "Setting project..."
gcloud config set project "$PROJECT_ID"

echo "Enabling required services for cleanup..."
gcloud services enable compute.googleapis.com container.googleapis.com \
    sqladmin.googleapis.com pubsub.googleapis.com storage.googleapis.com \
    iam.googleapis.com --quiet || true

echo "Deleting Compute Engine instances..."
gcloud compute instances list --format="value(name,zone)" | \
while read -r NAME ZONE; do
  gcloud compute instances delete "$NAME" --zone="$ZONE" --quiet || true
done

echo "Deleting GKE clusters..."
gcloud container clusters list --format="value(name,zone)" | \
while read -r NAME ZONE; do
  gcloud container clusters delete "$NAME" --zone="$ZONE" --quiet || true
done

echo "Deleting Cloud SQL instances..."
gcloud sql instances list --format="value(name)" | \
while read -r NAME; do
  gcloud sql instances delete "$NAME" --quiet || true
done

echo "Deleting Pub/Sub topics..."
gcloud pubsub topics list --format="value(name)" | \
while read -r NAME; do
  gcloud pubsub topics delete "$NAME" --quiet || true
done

echo "Deleting Storage buckets..."
gcloud storage buckets list --format="value(name)" | \
while read -r NAME; do
  gcloud storage buckets delete "gs://$NAME" --quiet || true
done

echo "Deleting IAM service accounts..."
gcloud iam service-accounts list --format="value(email)" | \
while read -r EMAIL; do
  gcloud iam service-accounts delete "$EMAIL" --quiet || true
done

echo "Final project deletion..."
gcloud projects delete "$PROJECT_ID" --quiet

echo "✅ Project [$PROJECT_ID] and all its resources have been deleted."
