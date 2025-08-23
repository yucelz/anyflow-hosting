output "namespace" {
  description = "Kubernetes namespace for n8n"
  value       = kubernetes_namespace.n8n.metadata[0].name
}

output "n8n_service_name" {
  description = "Name of the n8n service"
  value       = kubernetes_service.n8n.metadata[0].name
}

output "postgres_service_name" {
  description = "Name of the PostgreSQL service"
  value       = kubernetes_service.postgres.metadata[0].name
}

output "ingress_name" {
  description = "Name of the ingress"
  value       = kubernetes_ingress_v1.n8n_ingress.metadata[0].name
}

output "ingress_ip" {
  description = "Static IP address for the ingress"
  value       = google_compute_global_address.n8n_ip.address
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = var.enable_ssl ? google_compute_managed_ssl_certificate.n8n_ssl_cert[0].name : null
}

output "ssl_certificate_status" {
  description = "Status of the SSL certificate"
  value       = var.enable_ssl ? google_compute_managed_ssl_certificate.n8n_ssl_cert[0].managed[0].status : null
}

output "n8n_deployment_name" {
  description = "Name of the n8n deployment"
  value       = kubernetes_deployment.n8n.metadata[0].name
}

output "postgres_statefulset_name" {
  description = "Name of the PostgreSQL statefulset"
  value       = kubernetes_stateful_set.postgres.metadata[0].name
}

output "n8n_url" {
  description = "URL to access n8n"
  value       = "https://${var.domain_name}"
}

output "secret_name" {
  description = "Name of the secrets"
  value       = kubernetes_secret.n8n_secrets.metadata[0].name
}

output "static_ip_name" {
  description = "Name of the static IP"
  value       = google_compute_global_address.n8n_ip.name
}

output "backend_config_name" {
  description = "Name of the backend config"
  value       = kubernetes_manifest.backend_config.manifest.metadata.name
}

output "network_policy_enabled" {
  description = "Whether network policy is enabled"
  value       = var.enable_network_policy
}

output "autoscaling_enabled" {
  description = "Whether autoscaling is enabled"
  value       = var.enable_autoscaling
}

output "hpa_name" {
  description = "Name of the horizontal pod autoscaler"
  value       = var.enable_autoscaling ? kubernetes_horizontal_pod_autoscaler_v2.n8n_hpa[0].metadata[0].name : null
}

output "pod_disruption_budget_name" {
  description = "Name of the pod disruption budget"
  value       = kubernetes_pod_disruption_budget_v1.n8n_pdb.metadata[0].name
}