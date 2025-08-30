# Cluster Information
output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = module.gke.cluster_location
}

output "cluster_master_version" {
  description = "GKE cluster master version"
  value       = module.gke.cluster_master_version
}

# Network Information
output "network_name" {
  description = "Name of the VPC network"
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = module.network.subnet_name
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = module.network.network_self_link
}

# N8N Application Information
output "n8n_namespace" {
  description = "Kubernetes namespace for N8N"
  value       = module.n8n.namespace
}

output "n8n_url" {
  description = "URL to access N8N"
  value       = "https://${var.domain_name}"
}

output "ingress_ip" {
  description = "Static IP address for the ingress"
  value       = module.n8n.ingress_ip
}

# Authentication Information
output "n8n_basic_auth_user" {
  description = "Basic auth username for N8N"
  value       = var.n8n_basic_auth_user
}

output "n8n_basic_auth_password" {
  description = "Basic auth password for N8N"
  value       = var.n8n_basic_auth_password
  sensitive   = true
}

# Database Information
output "postgres_password" {
  description = "PostgreSQL password"
  value       = random_password.postgres_password.result
  sensitive   = true
}

# SSL Certificate Information
output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = module.n8n.ssl_certificate_name
}

# output "ssl_certificate_status" {
#   description = "Status of the SSL certificate"
#   value       = module.n8n.ssl_certificate_status
# }

# Kubectl Configuration
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${var.zone} --project ${var.project_id}"
}

# DNS Configuration Instructions
output "dns_configuration" {
  description = "DNS configuration instructions"
  value = {
    record_type = "A"
    name        = var.domain_name
    value       = module.n8n.ingress_ip
    ttl         = 300
  }
}

# Project Information
output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "zone" {
  description = "GCP Zone"
  value       = var.zone
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Service Account Information (if workload identity is enabled)
output "workload_identity_service_account" {
  description = "Service account for workload identity"
  value       = var.enable_workload_identity ? module.gke.workload_identity_service_account : null
}

# Monitoring Information
output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring
}

# Backup Information
output "backup_enabled" {
  description = "Whether backups are enabled"
  value       = var.enable_backups
}

# Cost Estimation (approximate monthly costs in USD)
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (approximate USD)"
  value = {
    gke_cluster_management = 74.40
    nodes = var.node_count * (var.machine_type == "e2-standard-2" ? 49.28 : 
             var.machine_type == "e2-medium" ? 24.64 :
             var.machine_type == "e2-standard-4" ? 98.56 : 49.28)
    load_balancer = 18.00
    persistent_disk = parseint(substr(var.postgres_storage_size, 0, length(var.postgres_storage_size) - 2), 10) * 0.040
    static_ip = 1.46
    estimated_total = 74.40 + (var.node_count * 49.28) + 18.00 + (parseint(substr(var.postgres_storage_size, 0, length(var.postgres_storage_size) - 2), 10) * 0.040) + 1.46
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for deployment"
  value = {
    "1_configure_kubectl" = "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${var.zone} --project ${var.project_id}"
    "2_check_pods"       = "kubectl get pods -n ${module.n8n.namespace}"
    "3_check_services"   = "kubectl get services -n ${module.n8n.namespace}"
    "4_check_ingress"    = "kubectl get ingress -n ${module.n8n.namespace}"
    "5_get_logs"        = "kubectl logs -n ${module.n8n.namespace} deployment/n8n-deployment -f"
    "6_scale_n8n"       = "kubectl scale deployment n8n-deployment --replicas=2 -n ${module.n8n.namespace}"
  }
}

# Health Check URLs
output "health_check_urls" {
  description = "Health check URLs for monitoring"
  value = {
    n8n_health     = "https://${var.domain_name}/healthz"
    n8n_metrics    = var.enable_n8n_metrics ? "https://${var.domain_name}/metrics" : "Metrics disabled"
  }
}
