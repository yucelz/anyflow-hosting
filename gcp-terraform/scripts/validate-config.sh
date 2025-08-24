#!/bin/bash

# Script to validate Terraform configuration
# This script helps verify that the workload identity configuration is correct

set -e

echo "🔍 Validating Terraform configuration..."

# Change to the terraform directory
cd "$(dirname "$0")/.."

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "📦 Initializing Terraform..."
    terraform init
fi

# Validate the configuration
echo "✅ Validating Terraform syntax..."
terraform validate

# Plan the deployment to check for errors
echo "📋 Creating Terraform plan..."
terraform plan -var-file="environments/dev/terraform.tfvars" -out=terraform-validation.tfplan

echo "✅ Configuration validation completed successfully!"
echo ""
echo "🎯 Key fixes applied:"
echo "   - Added workload_identity_namespace = var.n8n_namespace"
echo "   - Added workload_identity_ksa_name = 'n8n-ksa'"
echo "   - Added iam.googleapis.com to required APIs"
echo ""
echo "🚀 You can now run 'terraform apply terraform-validation.tfplan' to deploy"
