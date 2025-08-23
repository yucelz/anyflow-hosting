output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "Endpoint for the GKE cluster"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.primary.location
}

output "cluster_master_version" {
  description = "Master version of the GKE cluster"
  value       = google_container_cluster.primary.master_version
}

output "cluster_ca_certificate" {
  description = "Base64 encoded CA certificate for the GKE cluster"
  value       = google_container_cluster.primary.master_auth.0.cluster_ca_certificate
  sensitive   = true
}

output "cluster_self_link" {
  description = "Self link of the GKE cluster"
  value       = google_container_cluster.primary.self_link
}

output "cluster_id" {
  description = "ID of the GKE cluster"
  value       = google_container_cluster.primary.id
}

output "node_pool_name" {
  description = "Name of the node pool"
  value       = google_container_node_pool.primary_nodes.name
}

output "node_pool_instance_group_urls" {
  description = "Instance group URLs of the node pool"
  value       = google_container_node_pool.primary_nodes.instance_group_urls
}

output "node_service_account_email" {
  description = "Email of the node service account"
  value       = google_service_account.gke_node_service_account.email
}

output "node_service_account_name" {
  description = "Name of the node service account"
  value       = google_service_account.gke_node_service_account.name
}

output "workload_identity_service_account" {
  description = "Workload Identity service account email"
  value       = var.enable_workload_identity ? google_service_account.workload_identity_service_account[0].email : null
}

output "workload_identity_service_account_name" {
  description = "Workload Identity service account name"
  value       = var.enable_workload_identity ? google_service_account.workload_identity_service_account[0].name : null
}

output "cluster_ipv4_cidr" {
  description = "IPv4 CIDR block used by the cluster"
  value       = google_container_cluster.primary.cluster_ipv4_cidr
}

output "services_ipv4_cidr" {
  description = "IPv4 CIDR block used by services"
  value       = google_container_cluster.primary.services_ipv4_cidr
}

output "network_policy_enabled" {
  description = "Whether network policy is enabled"
  value       = var.enable_network_policy
}

output "workload_identity_enabled" {
  description = "Whether workload identity is enabled"
  value       = var.enable_workload_identity
}