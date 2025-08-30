# Troubleshooting Guide

This document provides solutions for common issues encountered when deploying the n8n infrastructure on GCP with Terraform.

## GCloud Credentials Issues

### Error: executable gcloud failed with exit code 1

**Symptoms:**
- Terraform fails with error: `Get "https://IP_ADDRESS/api/v1/namespaces/n8n": getting credentials: exec: executable gcloud failed with exit code 1`
- Error occurs when trying to create Kubernetes resources like namespaces
- Usually happens in the n8n module when creating the kubernetes_namespace resource
- May also show: `exec plugin is configured to use API version client.authentication.k8s.io/v1beta1, plugin returned version client.authentication.k8s.io/__internal`

**Root Causes:**
1. **Zone/Region Mismatch**: The Kubernetes provider configuration is using the wrong gcloud command arguments for the cluster type:
   - **Zonal clusters** require `--zone=ZONE_NAME` 
   - **Regional clusters** require `--region=REGION_NAME`
2. **API Version Mismatch**: The exec plugin API version is incompatible with the current gcloud version

**Solution:**

#### 1. Fix Provider Configuration (RECOMMENDED)
Update the `provider.tf` file to use the correct zone/region parameter:

For **zonal clusters** (like dev environment):
```hcl
provider "kubernetes" {
  config_path = "~/.kube/config"
  
  exec {
    api_version = "client.authentication.k8s.io/v1"  # Use v1 for compatibility
    command     = "gcloud"
    args = [
      "container",
      "clusters",
      "get-credentials",
      "${var.environment}-${var.cluster_name}",
      "--zone=${var.zone}",        # Use --zone for zonal clusters
      "--project=${var.project_id}"
    ]
  }
}
```

For **regional clusters**:
```hcl
provider "kubernetes" {
  config_path = "~/.kube/config"
  
  exec {
    api_version = "client.authentication.k8s.io/v1"  # Use v1 for compatibility
    command     = "gcloud"
    args = [
      "container",
      "clusters",
      "get-credentials",
      "${var.environment}-${var.cluster_name}",
      "--region=${var.region}",    # Use --region for regional clusters
      "--project=${var.project_id}"
    ]
  }
}
```

**Note on API Version:** If you encounter API version mismatch errors, use `client.authentication.k8s.io/v1` instead of `v1beta1` for better compatibility with newer gcloud versions.

#### 2. Manual Credentials Setup
If the provider fix doesn't work immediately, manually get credentials:

```bash
# For zonal clusters (dev environment)
gcloud container clusters get-credentials dev-n8n-cluster --zone=us-west1-a --project=anyflow-469911

# For regional clusters
gcloud container clusters get-credentials cluster-name --region=us-west-1 --project=your-project-id

# Test connectivity
kubectl cluster-info --request-timeout=30s
```

#### 3. Use the Credentials Helper Script
Run the provided script to automatically get the correct credentials:

```bash
./scripts/get-credentials.sh dev
```

#### 4. Verify Cluster Type
Check if your cluster is zonal or regional:

```bash
# List clusters and their types
gcloud container clusters list --project=anyflow-469911

# Describe specific cluster
gcloud container clusters describe dev-n8n-cluster --zone=us-west1-a --project=anyflow-469911
```

## Kubernetes Provider Timeout Issues

### Error: client rate limiter Wait returned an error: context deadline exceeded

**Symptoms:**
- Terraform fails when creating Kubernetes resources (PVCs, deployments, services)
- Error message mentions "client rate limiter" and "context deadline exceeded"
- Usually occurs on line 96 in `modules/n8n/main.tf` with the PVC resource

**Root Causes:**
1. Kubernetes API server is slow to respond
2. Network connectivity issues to the cluster
3. Rate limiting on the Kubernetes API
4. Insufficient timeout configurations in the provider
5. Incorrect gcloud credentials configuration (see above section)

**Solutions:**

#### 1. Provider Configuration (Already Implemented)
The Kubernetes provider has been configured with proper authentication and timeout handling:

```hcl
provider "kubernetes" {
  config_path = "~/.kube/config"
  
  ignore_annotations = [
    "kubectl.kubernetes.io/last-applied-configuration",
  ]
  
  experiments {
    manifest_resource = true
  }
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gcloud"
    args = [
      "container",
      "clusters",
      "get-credentials",
      var.cluster_name != null ? "${var.environment}-${var.cluster_name}" : "dev-n8n-cluster",
      "--region=${var.region}",
      "--project=${var.project_id}",
      "--format=json"
    ]
  }
}
```

#### 2. Resource Timeout Configuration (Already Implemented)
PVC resources now include timeout configurations:

```hcl
resource "kubernetes_persistent_volume_claim" "n8n_claim0" {
  # ... resource configuration ...
  
  timeouts {
    create = "10m"
  }
  
  depends_on = [kubernetes_namespace.n8n]
}
```

#### 3. Manual Retry Steps
If the error persists, try these manual steps:

```bash
# 1. Refresh cluster credentials
gcloud container clusters get-credentials dev-n8n-cluster --region=us-west-1 --project=your-project-id

# 2. Test cluster connectivity
kubectl cluster-info --request-timeout=30s

# 3. Check cluster status
kubectl get nodes

# 4. Retry Terraform apply with increased parallelism
terraform apply -parallelism=1
```

#### 4. Alternative Deployment Approach
If timeouts persist, deploy resources in stages:

```bash
# Stage 1: Deploy infrastructure only
terraform apply -target=module.network -target=module.gke

# Stage 2: Wait for cluster to be fully ready
sleep 120

# Stage 3: Deploy n8n module
terraform apply -target=module.n8n
```

## Storage Class Issues

### Error: StorageClass not found

**Symptoms:**
- PVC creation fails with storage class not found
- Error mentions `standard-rwo` storage class

**Solution:**
Check available storage classes and update variables:

```bash
# List available storage classes
kubectl get storageclass

# Update terraform.tfvars with correct storage class
postgres_storage_class = "standard"
n8n_storage_class = "standard"
```

## Network Connectivity Issues

### Error: Unable to connect to the server

**Symptoms:**
- Terraform cannot connect to Kubernetes API
- Network timeouts during resource creation

**Solutions:**

1. **Check GKE cluster status:**
```bash
gcloud container clusters describe dev-n8n-cluster --region=us-west-1
```

2. **Verify authorized networks:**
```bash
# Get your current IP
curl ifconfig.me

# Update authorized networks in terraform.tfvars
authorized_networks = [
  {
    cidr_block   = "YOUR_IP/32"
    display_name = "Your IP"
  }
]
```

3. **Check firewall rules:**
```bash
gcloud compute firewall-rules list --filter="name~gke"
```

## Resource Quota Issues

### Error: Insufficient quota

**Symptoms:**
- Resource creation fails due to quota limits
- Error mentions CPU, memory, or disk quota exceeded

**Solutions:**

1. **Check current quotas:**
```bash
gcloud compute project-info describe --project=your-project-id
```

2. **Request quota increase:**
- Go to GCP Console → IAM & Admin → Quotas
- Filter by the resource type (CPU, Memory, Persistent Disk)
- Request increase

3. **Reduce resource requirements:**
Update `terraform.tfvars` with smaller resource requests:
```hcl
# Reduce PostgreSQL resources
postgres_cpu_request = "500m"
postgres_memory_request = "1Gi"
postgres_cpu_limit = "2"
postgres_memory_limit = "2Gi"

# Reduce n8n resources
n8n_cpu_request = "100m"
n8n_memory_request = "128Mi"
n8n_cpu_limit = "250m"
n8n_memory_limit = "256Mi"
```

## SSL Certificate Issues

### Error: SSL certificate provisioning failed

**Symptoms:**
- Ingress shows certificate provisioning errors
- HTTPS access fails

**Solutions:**

1. **Check certificate status:**
```bash
kubectl describe managedcertificate -n n8n
```

2. **Verify DNS configuration:**
```bash
nslookup your-domain.com
```

3. **Check domain ownership:**
- Ensure domain points to the static IP
- Verify DNS propagation (can take up to 48 hours)

## Pod Startup Issues

### Error: Pods stuck in Pending or CrashLoopBackOff

**Symptoms:**
- n8n or PostgreSQL pods don't start properly
- Pods show Pending, CrashLoopBackOff, or ImagePullBackOff status

**Solutions:**

1. **Check pod status:**
```bash
kubectl get pods -n n8n
kubectl describe pod <pod-name> -n n8n
kubectl logs <pod-name> -n n8n
```

2. **Check node resources:**
```bash
kubectl describe nodes
kubectl top nodes
```

3. **Verify storage:**
```bash
kubectl get pvc -n n8n
kubectl describe pvc -n n8n
```

## Database Connection Issues

### Error: n8n cannot connect to PostgreSQL

**Symptoms:**
- n8n pod logs show database connection errors
- PostgreSQL connection timeouts

**Solutions:**

1. **Check PostgreSQL pod:**
```bash
kubectl logs postgres-0 -n n8n
kubectl exec -it postgres-0 -n n8n -- psql -U n8n -d n8n
```

2. **Verify service connectivity:**
```bash
kubectl get svc -n n8n
kubectl exec -it n8n-deployment-xxx -n n8n -- nslookup postgres-service.n8n.svc.cluster.local
```

3. **Check secrets:**
```bash
kubectl get secrets -n n8n
kubectl describe secret postgres-secret -n n8n
```

## General Debugging Commands

### Useful kubectl commands for troubleshooting:

```bash
# Get all resources in n8n namespace
kubectl get all -n n8n

# Check events for errors
kubectl get events -n n8n --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n n8n
kubectl top nodes

# Get detailed pod information
kubectl describe pod <pod-name> -n n8n

# Check logs
kubectl logs <pod-name> -n n8n --previous
kubectl logs <pod-name> -n n8n --follow

# Execute commands in pods
kubectl exec -it <pod-name> -n n8n -- /bin/bash

# Port forward for local testing
kubectl port-forward svc/n8n-service 8080:80 -n n8n
```

### Terraform debugging:

```bash
# Enable detailed logging
export TF_LOG=DEBUG
terraform apply

# Show current state
terraform show

# Refresh state
terraform refresh

# Import existing resources
terraform import <resource_type>.<resource_name> <resource_id>
```

## Prevention Best Practices

1. **Always test cluster connectivity before deploying:**
```bash
kubectl cluster-info --request-timeout=30s
```

2. **Use staged deployments for large changes:**
```bash
terraform plan -target=module.network
terraform apply -target=module.network
```

3. **Monitor resource quotas regularly:**
```bash
gcloud compute project-info describe --project=your-project-id
```

4. **Keep Terraform state backed up:**
```bash
terraform state pull > backup-$(date +%Y%m%d).tfstate
```

5. **Use consistent naming and labeling:**
- Follow the established naming conventions
- Apply consistent labels for resource management

## Getting Help

If you continue to experience issues:

1. Check the [Terraform Kubernetes Provider documentation](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
2. Review [GKE troubleshooting guide](https://cloud.google.com/kubernetes-engine/docs/troubleshooting)
3. Check [n8n documentation](https://docs.n8n.io/) for application-specific issues
4. Enable debug logging and collect detailed error messages
5. Consider reaching out to the respective communities for support
