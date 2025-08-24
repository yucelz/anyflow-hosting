#!/bin/bash

# Debug script to check Terraform state and outputs
# Run this from your project root directory

echo "=== Checking Terraform State ==="
terraform state list | grep -E "(cluster|gke)"

echo ""
echo "=== All Terraform Outputs ==="
terraform output

echo ""
echo "=== Checking specific outputs the script expects ==="
echo "cluster_name:"
terraform output cluster_name 2>&1

echo "project_id:"
terraform output project_id 2>&1

echo "region:"
terraform output region 2>&1

echo ""
echo "=== Raw output values (without quotes) ==="
echo "cluster_name (raw):"
terraform output -raw cluster_name 2>&1

echo "project_id (raw):"
terraform output -raw project_id 2>&1

echo "region (raw):"
terraform output -raw region 2>&1

echo ""
echo "=== Current gcloud configuration ==="
gcloud config list

echo ""
echo "=== Available GKE clusters ==="
gcloud container clusters list