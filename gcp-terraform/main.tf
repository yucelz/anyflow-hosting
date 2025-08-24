# Get current client configuration
data "google_client_config" "default" {}

# Local values for consistent naming
locals {
  name_prefix = "${var.environment}-${var.cluster_name}"
  common_labels = {
    environment = var.environment
    project     = "n8n"
    managed_by  = "terraform"
  }
}

# Generate random passwords
resource "random_password" "postgres_password" {
  length  = 16
  special = true
}

resource "random_password" "n8n_basic_auth_password" {
  length  = 16
  special = true
}

resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = true
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "certificatemanager.googleapis.com"
  ])

  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Network Module
module "network" {
  source = "./modules/network"

  project_id      = var.project_id
  region          = var.region
  network_name    = "${local.name_prefix}-${var.network_name}"
  subnet_name     = "${local.name_prefix}-${var.subnet_name}"
  subnet_cidr     = var.subnet_cidr
  pods_cidr       = var.pods_cidr
  services_cidr   = var.services_cidr
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# GKE Module
module "gke" {
  source = "./modules/gke"

  project_id             = var.project_id
  region                 = var.region
  zone                   = var.zone
  cluster_name           = local.name_prefix
  kubernetes_version     = var.kubernetes_version
  network_name           = module.network.network_name
  subnet_name            = module.network.subnet_name
  pods_range_name        = module.network.pods_range_name
  services_range_name    = module.network.services_range_name
  
  # Node pool configuration
  node_pool_name         = var.node_pool_name
  node_count             = var.node_count
  min_node_count         = var.min_node_count
  max_node_count         = var.max_node_count
  machine_type           = var.machine_type
  disk_size_gb           = var.disk_size_gb
  disk_type              = var.disk_type
  preemptible_nodes      = var.preemptible_nodes
  
  # Security
  enable_network_policy   = var.enable_network_policy
  enable_workload_identity = var.enable_workload_identity
  authorized_networks     = var.authorized_networks
  
  labels = local.common_labels

  depends_on = [module.network]
}

# Time delay to ensure cluster is fully ready
resource "time_sleep" "wait_for_cluster" {
  create_duration = "60s"
  depends_on     = [module.gke]
}

# Data source to verify cluster is accessible
data "google_container_cluster" "cluster" {
  name       = local.name_prefix
  location   = var.region
  depends_on = [time_sleep.wait_for_cluster]
}

# Local exec to get credentials
resource "null_resource" "get_credentials" {
  depends_on = [data.google_container_cluster.cluster]
  
  provisioner "local-exec" {
    command = <<-EOT
      # Get cluster credentials
      gcloud container clusters get-credentials ${local.name_prefix} --region=${var.region} --project=${var.project_id}
      
      # Test cluster connectivity
      kubectl cluster-info --request-timeout=30s
    EOT
  }
  
  # Re-run if cluster changes
  triggers = {
    cluster_endpoint = data.google_container_cluster.cluster.endpoint
    cluster_name     = local.name_prefix
  }
}

# N8N Module - only deploy after cluster is verified ready
module "n8n" {
  source = "./modules/n8n"

  # Basic configuration
  namespace           = var.n8n_namespace
  domain_name         = var.domain_name
  n8n_image_tag      = var.n8n_image_tag
  n8n_replicas       = var.n8n_replicas
  
  # Authentication
  n8n_basic_auth_user     = var.n8n_basic_auth_user
  n8n_basic_auth_password = random_password.n8n_basic_auth_password.result
  n8n_encryption_key      = random_password.n8n_encryption_key.result
  
  # Database configuration
  postgres_image_tag      = var.postgres_image_tag
  postgres_password       = random_password.postgres_password.result
  postgres_storage_size   = var.postgres_storage_size
  postgres_storage_class  = var.postgres_storage_class
  
  # Resource limits
  n8n_cpu_request       = var.n8n_cpu_request
  n8n_memory_request    = var.n8n_memory_request
  n8n_cpu_limit         = var.n8n_cpu_limit
  n8n_memory_limit      = var.n8n_memory_limit
  
  postgres_cpu_request  = var.postgres_cpu_request
  postgres_memory_request = var.postgres_memory_request
  postgres_cpu_limit    = var.postgres_cpu_limit
  postgres_memory_limit = var.postgres_memory_limit
  
  # SSL and networking
  enable_ssl            = var.enable_ssl
  ssl_certificate_name  = "${local.name_prefix}-${var.ssl_certificate_name}"
  static_ip_name        = "${local.name_prefix}-${var.static_ip_name}"
  
  # Monitoring and features
  enable_monitoring     = var.enable_monitoring
  enable_n8n_metrics    = var.enable_n8n_metrics
  timezone              = var.timezone
  
  labels = local.common_labels

  depends_on = [
    null_resource.get_credentials,
    data.google_container_cluster.cluster
  ]
}