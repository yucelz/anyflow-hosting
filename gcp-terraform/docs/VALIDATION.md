# Dev-Deploy Validation Documentation

## Overview

The enhanced `dev-deploy.sh` script includes comprehensive validation checks for GKE, Network, and N8N components. This document outlines the validation process, checks performed, and troubleshooting guidance.

## Validation Architecture

The validation system is structured in three main phases:

1. **Pre-deployment Validation** - Validates prerequisites before deployment
2. **Post-infrastructure Validation** - Validates network and GKE after infrastructure deployment
3. **Post-application Validation** - Validates N8N components after application deployment

## Validation Phases

### Phase 1: Pre-deployment Validation

#### Prerequisites Check
- **Command Availability**: Validates `gcloud`, `terraform`, and `kubectl` are installed
- **GCP Authentication**: Ensures active gcloud authentication
- **Project Access**: Verifies access to the target GCP project
- **Required APIs**: Checks and enables necessary GCP APIs
- **Terraform Configuration**: Validates terraform files and syntax

#### Network Prerequisites
- **Existing Resources**: Checks if VPC network and subnet already exist
- **CIDR Configuration**: Validates CIDR ranges for subnet, pods, and services
- **Conflict Detection**: Ensures no IP range conflicts

#### GKE Prerequisites
- **Cluster Status**: Checks if cluster already exists and its status
- **Machine Type**: Validates machine type availability in target zone
- **Resource Quotas**: Checks available compute quotas
- **Zone Availability**: Ensures target zone is available

#### N8N Prerequisites
- **Domain Configuration**: Validates domain settings
- **Static IP**: Checks if static IP already exists
- **SSL Certificate**: Validates SSL certificate configuration
- **Resource Requirements**: Reviews CPU, memory, and storage requirements

### Phase 2: Post-infrastructure Validation

#### Network Validation
- **VPC Network**: Confirms VPC network creation
- **Subnet**: Validates subnet deployment
- **Firewall Rules**: Checks creation of required firewall rules:
  - `n8n-vpc-allow-internal`
  - `n8n-vpc-allow-ssh`
  - `n8n-vpc-allow-health-check`
- **NAT Gateway**: Validates NAT router and gateway deployment

#### GKE Validation
- **Cluster Status**: Ensures cluster is in RUNNING state
- **Node Pool**: Validates node pool is in RUNNING state
- **kubectl Connectivity**: Tests cluster connectivity
- **Node Readiness**: Confirms all nodes are ready
- **System Pods**: Validates at least 80% of system pods are running

### Phase 3: Post-application Validation

#### N8N Application Validation
- **Namespace**: Confirms N8N namespace creation
- **PostgreSQL**: Validates PostgreSQL StatefulSet readiness
- **N8N Deployment**: Checks N8N deployment readiness
- **Services**: Validates both N8N and PostgreSQL services
- **Ingress**: Confirms ingress creation and IP assignment
- **SSL Certificate**: Checks SSL certificate provisioning status

## Validation Functions

### Core Validation Functions

#### `validate_command(cmd, description)`
Validates that required CLI tools are available.

#### `validate_gcp_auth()`
Ensures active GCP authentication and displays authenticated account.

#### `validate_project_access()`
Verifies access to the target GCP project.

#### `validate_required_apis()`
Checks and enables required GCP APIs:
- `container.googleapis.com`
- `compute.googleapis.com`
- `certificatemanager.googleapis.com`
- `iam.googleapis.com`
- `cloudresourcemanager.googleapis.com`

#### `validate_terraform_config()`
Validates Terraform configuration files and syntax.

### Infrastructure Validation Functions

#### `validate_network_prerequisites()`
Pre-deployment network validation including CIDR range checks.

#### `validate_gke_prerequisites()`
Pre-deployment GKE validation including machine type and quota checks.

#### `validate_network_deployment()`
Post-deployment network validation confirming all network resources.

#### `validate_gke_deployment()`
Post-deployment GKE validation including cluster health and connectivity.

### Application Validation Functions

#### `validate_n8n_prerequisites()`
Pre-deployment N8N validation including domain and resource configuration.

#### `validate_n8n_deployment()`
Post-deployment N8N validation including all application components.

## Error Handling

### Validation Error System
- **Error Collection**: All validation errors are collected in `VALIDATION_ERRORS` array
- **Failure Flag**: `VALIDATION_PASSED` flag tracks overall validation status
- **Error Display**: Comprehensive error summary with actionable information

### Error Categories

#### Authentication Errors
- **No Active Authentication**: Run `gcloud auth login`
- **Project Access Denied**: Check project permissions and billing

#### API Errors
- **API Not Enabled**: Script automatically enables missing APIs
- **API Enable Failed**: Check project permissions and billing status

#### Resource Errors
- **Quota Exceeded**: Check GCP quotas and request increases if needed
- **Resource Conflicts**: Existing resources may conflict with deployment

#### Configuration Errors
- **Invalid Terraform**: Fix syntax errors in Terraform files
- **Missing Files**: Ensure all required configuration files exist

## Troubleshooting Guide

### Common Issues and Solutions

#### Pre-deployment Issues

**Issue**: `gcloud command not found`
```bash
# Install Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

**Issue**: `No active gcloud authentication`
```bash
gcloud auth login
gcloud config set project anyflow-469911
```

**Issue**: `Terraform validation failed`
```bash
# Check terraform syntax
terraform validate
# Fix any syntax errors in .tf files
```

#### Infrastructure Issues

**Issue**: `Machine type not available`
- Check available machine types: `gcloud compute machine-types list --zones=us-central1-a`
- Update terraform.tfvars with available machine type

**Issue**: `Quota exceeded`
- Check quotas: `gcloud compute project-info describe --project=anyflow-469911`
- Request quota increase in GCP Console

**Issue**: `Network already exists`
- Script handles existing networks gracefully
- Ensure subnet configuration matches existing setup

#### Application Issues

**Issue**: `Pods not ready`
```bash
# Check pod status
kubectl get pods -n n8n
# Check pod logs
kubectl logs -f deployment/n8n-deployment -n n8n
```

**Issue**: `SSL certificate not provisioning`
- Ensure domain DNS points to ingress IP
- Check certificate status: `gcloud compute ssl-certificates describe n8n-ssl-cert --global`

**Issue**: `Ingress IP not assigned`
- Wait 5-10 minutes for IP assignment
- Check ingress status: `kubectl describe ingress n8n-ingress -n n8n`

### Validation Bypass

For development purposes, you can modify validation behavior:

```bash
# Skip specific validation (not recommended)
export SKIP_NETWORK_VALIDATION=true
export SKIP_GKE_VALIDATION=true
export SKIP_N8N_VALIDATION=true
```

## Monitoring and Maintenance

### Health Checks

The script provides several monitoring commands:

```bash
# Monitor deployment
kubectl get pods -n n8n -w

# View N8N logs
kubectl logs -f deployment/n8n-deployment -n n8n

# Check SSL certificate status
gcloud compute ssl-certificates describe n8n-ssl-cert --global

# Monitor ingress
kubectl describe ingress n8n-ingress -n n8n
```

### Regular Validation

Run validation checks independently:

```bash
# Network validation
gcloud compute networks describe n8n-vpc
gcloud compute networks subnets describe n8n-subnet --region=us-central1

# GKE validation
gcloud container clusters describe dev-n8n-cluster --zone=us-central1-a
kubectl get nodes
kubectl get pods -n kube-system

# N8N validation
kubectl get all -n n8n
kubectl get ingress -n n8n
```

## Best Practices

### Before Running the Script

1. **Verify Prerequisites**: Ensure all CLI tools are installed and updated
2. **Check Authentication**: Confirm active GCP authentication
3. **Review Configuration**: Validate terraform.tfvars settings
4. **Check Quotas**: Ensure sufficient GCP quotas

### During Deployment

1. **Monitor Output**: Watch validation messages carefully
2. **Address Warnings**: Investigate warnings even if deployment continues
3. **Wait for Completion**: Allow time for SSL certificate provisioning

### After Deployment

1. **Verify Functionality**: Test N8N application access
2. **Monitor Resources**: Check resource usage and costs
3. **Document Issues**: Record any issues for future reference

## Script Configuration

### Environment Variables

The script uses these key variables:

```bash
ENVIRONMENT="dev"
PROJECT_ID="anyflow-469911"
REGION="us-central1"
ZONE="us-central1-a"
CLUSTER_NAME="${ENVIRONMENT}-n8n-cluster"
NETWORK_NAME="n8n-vpc"
SUBNET_NAME="n8n-subnet"
```

### Validation Flags

```bash
VALIDATION_PASSED=true
VALIDATION_ERRORS=()
```

## Output Interpretation

### Color Coding

- **🔵 BLUE**: Section headers and general information
- **🟢 GREEN**: Success messages and information
- **🟡 YELLOW**: Warnings and deployment summaries
- **🔴 RED**: Errors and failures
- **🔷 CYAN**: Validation messages
- **🟣 PURPLE**: Section separators

### Exit Codes

- **0**: Successful deployment with all validations passed
- **1**: Validation failure or deployment error

## Integration with CI/CD

The validation script can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions integration
- name: Deploy with Validation
  run: |
    cd gcp-terraform
    ./scripts/dev-deploy.sh
  env:
    GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
```

## Security Considerations

### Validation Security

- **Credential Validation**: Ensures proper authentication before deployment
- **Permission Checks**: Validates project access and API permissions
- **Resource Isolation**: Confirms network isolation and security groups

### Best Practices

1. **Least Privilege**: Use service accounts with minimal required permissions
2. **Audit Logging**: Enable GCP audit logging for deployment tracking
3. **Secret Management**: Use secure secret management for sensitive data

## Performance Optimization

### Validation Performance

- **Parallel Checks**: Some validations run in parallel where possible
- **Early Exit**: Script exits early on critical validation failures
- **Caching**: Reuses validation results where appropriate

### Resource Optimization

- **Right-sizing**: Validates resource requests match actual needs
- **Cost Monitoring**: Provides resource usage summary for cost tracking

## Conclusion

The enhanced dev-deploy.sh script provides comprehensive validation to ensure reliable and secure N8N deployments on GKE. The multi-phase validation approach catches issues early and provides detailed feedback for troubleshooting.

For additional support or questions, refer to the main project documentation or create an issue in the project repository.
