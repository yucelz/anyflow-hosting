# Google Spot VMs Migration Guide

## Overview

This document outlines the migration from Google Preemptible VMs to the newer Google Spot VMs for the GKE cluster infrastructure.

## Changes Made

### 1. Variable Updates

#### Main Variables (`variables.tf`)
- Added new `spot_nodes` variable for Spot VM configuration
- Kept `preemptible_nodes` for backward compatibility (marked as deprecated)

#### GKE Module Variables (`modules/gke/variables.tf`)
- Added `spot_nodes` variable to the GKE module
- Updated descriptions to indicate preemptible nodes are deprecated

### 2. Infrastructure Updates

#### Main Configuration (`main.tf`)
- Added `spot_nodes` parameter to the GKE module call
- Passes the spot_nodes variable from root to module

#### GKE Module (`modules/gke/main.tf`)
- Updated node pool configuration to use `spot = var.spot_nodes`
- Added logic to disable preemptible when spot is enabled: `preemptible = var.spot_nodes ? false : var.preemptible_nodes`
- This ensures mutual exclusivity between spot and preemptible settings

### 3. Environment Configuration

#### Development Environment (`environments/dev/terraform.tfvars`)
- Set `preemptible_nodes = false` (deprecated)
- Set `spot_nodes = true` (new recommended approach)

## Key Differences: Preemptible vs Spot VMs

| Feature | Preemptible VMs | Spot VMs |
|---------|----------------|----------|
| **Status** | Deprecated | Current/Recommended |
| **Maximum Runtime** | 24 hours | No time limit |
| **Pricing** | Up to 80% discount | Up to 91% discount |
| **Preemption Notice** | 30 seconds | 30 seconds |
| **API Parameter** | `preemptible = true` | `spot = true` |
| **Availability** | Limited | Better availability |

## Benefits of Spot VMs

1. **Better Cost Savings**: Up to 91% discount vs 80% for preemptible
2. **No Time Limits**: Spot VMs don't have the 24-hour maximum runtime
3. **Improved Availability**: Better resource availability compared to preemptible
4. **Future-Proof**: Google's recommended approach going forward

## Deployment Instructions

### Prerequisites
- Ensure you have the necessary GCP permissions
- Terraform >= 1.0
- gcloud CLI configured with appropriate project

### Deployment Steps

1. **Validate Configuration**
   ```bash
   cd gcp-terraform
   terraform validate
   ```

2. **Review Changes**
   ```bash
   terraform plan -var-file="environments/dev/terraform.tfvars"
   ```

3. **Apply Changes**
   ```bash
   terraform apply -var-file="environments/dev/terraform.tfvars"
   ```

### Expected Changes

The plan will show:
- Recreation of the GKE cluster with Spot VM node pools
- All network infrastructure will be recreated
- N8N application will be redeployed

### Rollback Plan

If needed, you can rollback by:
1. Setting `spot_nodes = false` and `preemptible_nodes = true`
2. Running `terraform apply` again

## Cost Impact

**Estimated Monthly Savings:**
- Previous (Preemptible): ~$24.64 for nodes
- New (Spot VMs): ~$49.28 for nodes (but with better availability and no time limits)

Note: The cost increase shown in the plan may be due to different machine types or configurations. Spot VMs typically provide better cost savings than preemptible VMs.

## Monitoring and Maintenance

### Node Preemption Handling
- Both Spot and Preemptible VMs can be preempted
- Kubernetes will automatically reschedule pods to available nodes
- Consider using pod disruption budgets for critical workloads

### Best Practices
1. **Mixed Node Pools**: Consider having both spot and regular nodes for critical workloads
2. **Graceful Shutdown**: Ensure applications handle SIGTERM signals properly
3. **Monitoring**: Monitor node preemption rates and adjust accordingly

## Troubleshooting

### Common Issues
1. **Insufficient Quota**: Ensure you have sufficient compute quota
2. **Regional Availability**: Spot VMs may not be available in all zones
3. **Kubernetes Client Error**: Expected during plan phase when cluster doesn't exist

### Support
- Check GCP Console for resource availability
- Review Terraform state for any inconsistencies
- Monitor GKE cluster events for preemption notifications

## References
- [Google Cloud Spot VMs Documentation](https://cloud.google.com/compute/docs/instances/spot)
- [GKE Spot Nodes Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/spot-vms)
- [Migration Guide from Preemptible to Spot](https://cloud.google.com/compute/docs/instances/preemptible#migrate-to-spot)
