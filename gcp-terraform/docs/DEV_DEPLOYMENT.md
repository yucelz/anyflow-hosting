# Dev Environment Deployment - Minimized N8N Infrastructure

This document describes the dev environment deployment configuration for N8N, designed for minimal resource usage with maximum 2 Kubernetes nodes and single resource instances for each product.

## Overview

The dev deployment is a cost-optimized, minimal resource configuration that provides:
- **Maximum 2 Kubernetes nodes** (e2-micro instances)
- **Single N8N replica** (no horizontal scaling)
- **Single PostgreSQL instance** (no replication)
- **Minimal resource allocation** (CPU and memory)
- **Disabled monitoring and advanced features** to save resources

## Architecture

### Infrastructure Components

| Component | Configuration | Resource Allocation |
|-----------|---------------|-------------------|
| **GKE Cluster** | Regional (multiple zones) | us-west-1 |
| **Node Pool** | 1-2 nodes max | e2-medium (2 vCPU, 4GB RAM) |
| **N8N Application** | Single replica | 100m CPU, 128Mi RAM |
| **PostgreSQL** | Single instance | 50m CPU, 64Mi RAM |
| **Storage** | Minimal | 5Gi persistent disk |
| **Networking** | Basic | No network policies |

### Key Differences from Production Environment

| Feature | Production Environment | Dev Environment |
|---------|----------------------|-----------------|
| Cluster Type | Regional (spans multiple zones automatically) | Regional (spans multiple zones automatically) |
| Max Nodes | 5+ | 3 |
| Machine Type | e2-standard-2 | e2-medium |
| N8N CPU | 500m request, 1000m limit | 100m request, 200m limit |
| N8N Memory | 512Mi request, 1Gi limit | 128Mi request, 256Mi limit |
| PostgreSQL CPU | 250m request, 500m limit | 50m request, 100m limit |
| PostgreSQL Memory | 256Mi request, 512Mi limit | 64Mi request, 128Mi limit |
| Storage | 50Gi+ | 5Gi |
| Monitoring | Enabled | Disabled |
| Workload Identity | Enabled | Disabled |
| Autoscaling | Enabled | Disabled |
| Pod Disruption Budget | Enabled | Disabled |

## Deployment

### Prerequisites

1. **GCP Project Setup**
   ```bash
   gcloud auth login
   gcloud config set project anyflow-cloud
   ```

2. **Required APIs** (automatically enabled by script)
   - Container API (container.googleapis.com)
   - Compute Engine API (compute.googleapis.com)
   - Certificate Manager API (certificatemanager.googleapis.com)
   - IAM API (iam.googleapis.com)

### Quick Deployment

The development environment now uses a modular deployment approach with three specialized scripts:

#### Complete Environment Deployment
```bash
# Deploy complete environment (infrastructure + application)
./scripts/dev-deploy.sh

# Deploy only infrastructure (Network + GKE)
./scripts/dev-deploy.sh --infra-only

# Deploy only application (requires infrastructure)
./scripts/dev-deploy.sh --app-only

# Destroy complete environment
./scripts/dev-deploy.sh --destroy
# OR 
terraform destroy -auto-approve

# Destroy only application (keep infrastructure)
./scripts/dev-deploy.sh --destroy --app-only

# Destroy only infrastructure (Network + GKE)
./scripts/dev-deploy.sh --destroy --infra-only

# Show help and usage information
./scripts/dev-deploy.sh --help
```

#### Updating the Environment

When configuration changes are made, you can update specific parts of the environment:

```bash
# Update only infrastructure (e.g., GKE cluster settings, network changes)
# This will apply changes to the network and GKE modules.
./scripts/dev-deploy.sh --infra-only

# Update only application (e.g., N8N or PostgreSQL configuration, image tags)
# This will apply changes to the n8n module.
./scripts/dev-deploy.sh --app-only
```

#### Individual Component Scripts
```bash
# Infrastructure deployment (Network + GKE cluster)
./scripts/dev-infra.sh                # Deploy infrastructure
./scripts/dev-infra.sh --destroy      # Destroy infrastructure
./scripts/dev-infra.sh --help         # Show help

# Application deployment (N8N + PostgreSQL)
./scripts/dev-app.sh                  # Deploy application
./scripts/dev-app.sh --destroy        # Destroy application
./scripts/dev-app.sh --help           # Show help

# Application health and endpoint testing
./scripts/dev-app-test.sh             # Test application health and endpoints
./scripts/dev-app-test.sh --help      # Show help

# Environment status check
# Check only application status
./scripts/dev-status.sh --app

# Check only infrastructure status  
./scripts/dev-status.sh --infra

# Check everything (default)
./scripts/dev-status.sh
./scripts/dev-status.sh --all

# Show help
./scripts/dev-status.sh --help
```

#### Modular Deployment Benefits

**Infrastructure Script (`dev-infra.sh`)**:
- **Focused Scope**: Network + GKE cluster deployment only
- **Prerequisites Validation**: GCP authentication, APIs, quotas
- **Deletion Protection Handling**: Automatic detection and resolution
- **Network Validation**: VPC, subnets, firewall rules, NAT gateway
- **GKE Validation**: Cluster status, node pools, kubectl connectivity

**Application Script (`dev-app.sh`)**:
- **Infrastructure Dependency Check**: Validates GKE cluster exists and is ready
- **Extended Health Checks**: 600s timeout for pod readiness
- **Optimized Resource Requirements**: Reduced CPU/memory for development
- **SSL Certificate Monitoring**: Tracks certificate provisioning status
- **Comprehensive Application Validation**: Pods, services, ingress status

**Orchestration Script (`dev-deploy.sh`)**:
- **Flexible Deployment Options**: Complete, infrastructure-only, or application-only
- **Proper Sequencing**: Infrastructure first, then application
- **Safe Destruction Order**: Application first, then infrastructure
- **Backward Compatibility**: Maintains original script behavior

**Testing Script (`dev-app-test.sh`)**:
- **Application Health Checks**: Verifies N8N and PostgreSQL health
- **Endpoint Reachability**: Confirms N8N application is accessible
- **GCP & Kubernetes Connectivity**: Ensures environment is operational

**Status Script (`dev-status.sh`)**:
- **Comprehensive Overview**: Checks status of both infrastructure and application components
- **Detailed Reporting**: Provides granular status for VPC, GKE, N8N, PostgreSQL, and network access
- **Authentication Validation**: Ensures GCP authentication is active

### Manual Deployment

#### Terraform Pre-Deployment Checks

Before applying any changes, it's crucial to perform checks to ensure the configuration is valid and to understand the proposed changes.

1.  **Initialize Terraform**
    ```bash
    cd gcp-terraform
    terraform init
    ```

2.  **Create/Select Workspace**
    ```bash
    terraform workspace new dev
    # or
    terraform workspace select dev
    ```

3.  **Validate Configuration**
    ```bash
    terraform validate
    ```
    This command checks the configuration files in the current directory for syntax errors and internal consistency.

4.  **Plan Deployment**
    ```bash
    terraform plan -var-file="environments/dev/terraform.tfvars" -out="terraform-dev.tfplan"
    ```
    This command creates an execution plan, showing what actions Terraform will take to achieve the desired state. Review this plan carefully before proceeding.

#### Terraform Deployment

1.  **Apply Configuration**
    ```bash
    terraform apply "terraform-dev.tfplan"
    ```
    This command applies the planned changes to create or update the infrastructure.

#### Terraform Post-Deployment Checks

After deployment, verify the state of the infrastructure and ensure everything is running as expected.

1.  **Get Cluster Credentials**
    ```bash
    gcloud container clusters get-credentials dev-n8n-cluster --region=us-west-1 --project=anyflow-cloud
    ```

2.  **Show Current State**
    ```bash
    terraform show
    ```
    This command displays the current state of the managed infrastructure.

3.  **Check Specific Outputs**
    ```bash
    terraform output
    # To get a specific output, e.g., the GKE cluster name
    terraform output gke_cluster_name
    ```
    This command shows the output values defined in the `outputs.tf` file.

4.  **Run Environment Status Check**
    ```bash
    ./scripts/dev-status.sh --all
    ```
    This script provides a comprehensive overview of both infrastructure and application components.

## Resource Limits and Constraints

### Kubernetes Cluster
- **Type**: Regional cluster (multiple zones for availability)
- **Location**: us-west-1
- **Node Pool**: 1-3 nodes maximum
- **Machine Type**: e2-medium (2 vCPU, 4GB RAM, preemptible)
- **Disk**: 20GB standard persistent disk per node

### Application Resources
- **N8N Pod**: 1 replica only
  - CPU Request: 100m (0.1 CPU core)
  - CPU Limit: 200m (0.2 CPU core)
  - Memory Request: 128Mi
  - Memory Limit: 256Mi

- **PostgreSQL Pod**: 1 instance only
  - CPU Request: 50m (0.05 CPU core)
  - CPU Limit: 100m (0.1 CPU core)
  - Memory Request: 64Mi
  - Memory Limit: 128Mi
  - Storage: 5Gi persistent volume

### Total Resource Usage
- **CPU**: ~150m total request (~0.15 CPU core)
- **Memory**: ~192Mi total request
- **Storage**: 5Gi for database + 20Gi per node for OS
- **Network**: Basic VPC with single subnet

## Limitations

### Scalability
- **No Horizontal Pod Autoscaling**: N8N runs as single replica
- **No Pod Disruption Budget**: Single pod means no disruption protection
- **Multi-Zone Redundancy**: Regional cluster spans multiple zones for availability

### Features Disabled
- **Monitoring**: Prometheus metrics disabled
- **Workload Identity**: GCP service account integration disabled
- **Network Policies**: Kubernetes network policies disabled
- **Cluster Autoscaling**: Disabled to enforce strict node limits

### Performance Considerations
- **Limited CPU**: May impact workflow execution performance
- **Limited Memory**: May cause OOM issues with complex workflows
- **Single Database**: No database replication or backup automation
- **Network Latency**: Single zone may have higher latency for some regions

## Monitoring and Maintenance

### Health Checks
Even with monitoring disabled, basic health checks are still active:
- **N8N Liveness Probe**: HTTP GET /healthz every 30s
- **N8N Readiness Probe**: HTTP GET /healthz every 5s
- **PostgreSQL Liveness Probe**: pg_isready every 10s
- **PostgreSQL Readiness Probe**: pg_isready every 5s

### Manual Monitoring Commands
```bash
# Check cluster status
kubectl cluster-info

# Check node status
kubectl get nodes -o wide

# Check pod status
kubectl get pods -n n8n

# Check resource usage
kubectl top nodes
kubectl top pods -n n8n

# Check logs
kubectl logs -n n8n deployment/n8n-deployment
kubectl logs -n n8n statefulset/n8n-postgres

# Check application health and endpoints
./scripts/dev-app-test.sh

# Check overall environment status
./scripts/dev-status.sh
```

### Scaling Considerations
If you need to scale beyond dev limits:
1. **Increase Node Count**: Modify `max_node_count` in terraform.tfvars
2. **Upgrade Machine Type**: Change from e2-micro to e2-small or e2-medium
3. **Enable Autoscaling**: Set `enable_autoscaling = true` and increase `n8n_replicas`
4. **Add Monitoring**: Set `enable_monitoring = true`

## Cost Optimization

### Estimated Monthly Costs (US Central1)
- **GKE Cluster**: ~$73/month (cluster management fee)
- **Compute Instances**: ~$10-20/month (2 x e2-medium preemptible)
- **Storage**: ~$1/month (5Gi standard disk)
- **Networking**: ~$1-5/month (ingress/egress)
- **Load Balancer**: ~$18/month (GCP Load Balancer)

**Total Estimated**: ~$103-117/month

### Cost Reduction Tips
1. **Use Preemptible Nodes**: Already enabled (up to 80% savings)
2. **Minimize Storage**: 5Gi is already minimal
3. **Regional Considerations**: us-central1 is typically cheapest
4. **Cleanup Unused Resources**: Regular cleanup of old deployments

## Troubleshooting

### Common Issues

1. **GKE Deletion Protection Error**
   ```
   Error: Cannot destroy cluster because deletion_protection is set to true.
   ```
   
   **Solution**: The `dev-deploy.sh --destroy` script automatically handles this by:
   - Detecting deletion protection status
   - Disabling protection using gcloud CLI
   - Retrying the terraform destroy operation
   
   **Manual Fix** (if automatic handling fails):
   ```bash
   # Disable deletion protection
   gcloud container clusters update dev-n8n-cluster \
     --zone=us-central1-a \
     --project=anyflow-cloud \
     --no-deletion-protection
   
   # Then retry destroy
   terraform destroy -target=module.gke \
     -var-file=environments/dev/terraform.tfvars \
     -auto-approve
   ```

2. **Pod Stuck in Pending**
   ```bash
   kubectl describe pod -n n8n <pod-name>
   # Check for resource constraints or node availability
   ```

3. **Out of Memory Errors**
   ```bash
   kubectl logs -n n8n deployment/n8n-deployment --previous
   # Consider increasing memory limits
   ```

4. **Database Connection Issues**
   ```bash
   kubectl exec -n n8n deployment/n8n-deployment -- nc -zv n8n-postgres 5432
   # Test database connectivity
   ```

5. **SSL Certificate Issues**
   ```bash
   kubectl describe managedcertificate -n n8n
   # Check certificate provisioning status
   ```

6. **Terraform State Issues**
   ```bash
   # If terraform state becomes corrupted
   terraform refresh -var-file=environments/dev/terraform.tfvars
   
   # If resources exist but not in state
   terraform import <resource_type>.<resource_name> <resource_id>
   ```

### Recovery Procedures

1. **Restart N8N Pod**
   ```bash
   kubectl rollout restart deployment/n8n-deployment -n n8n
   ```

2. **Restart PostgreSQL**
   ```bash
   kubectl rollout restart statefulset/n8n-postgres -n n8n
   ```

3. **Scale Node Pool**
   ```bash
   gcloud container clusters resize dev-n8n-cluster --num-nodes=2 --region=us-central1
   ```

## Security Considerations

### Simplified Security Model
- **No Network Policies**: All pods can communicate freely
- **No Workload Identity**: Uses default node service account
- **Basic Authentication**: N8N protected by basic auth only
- **HTTPS Only**: SSL certificate enforced via ingress

### Security Recommendations
1. **Restrict Access**: Use GCP IAM to limit cluster access
2. **Monitor Logs**: Regularly check application and audit logs
3. **Update Images**: Keep N8N and PostgreSQL images updated
4. **Backup Data**: Implement regular database backups
5. **Network Segmentation**: Consider enabling network policies if needed

## Backup and Recovery

### Database Backup
```bash
# Manual backup
kubectl exec -n n8n statefulset/n8n-postgres -- pg_dump -U n8n n8n > backup.sql

# Restore from backup
kubectl exec -i -n n8n statefulset/n8n-postgres -- psql -U n8n n8n < backup.sql
```

### Configuration Backup
```bash
# Export all Kubernetes resources
kubectl get all,secrets,configmaps,pvc -n n8n -o yaml > n8n-backup.yaml
```

## Upgrade Path

To upgrade from dev to a production environment:

1. **Create Production Environment**
   ```bash
   cp -r environments/dev environments/production
   # Modify production configuration for higher resources
   ```

2. **Migrate Data**
   - Export database from dev
   - Import to production environment
   - Update DNS to point to production environment

3. **Decommission Dev**
   ```bash
   terraform destroy -var-file="environments/dev/terraform.tfvars"
   ```

## Support

For issues specific to the dev deployment:
1. Check this documentation first
2. Review Terraform validation: `terraform validate`
3. Check GCP quotas and limits
4. Verify cluster and pod status
5. Review application logs

Remember: This is a minimal deployment optimized for cost, not performance or high availability.
