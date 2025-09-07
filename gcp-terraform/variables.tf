# Project Configuration
variable "project_id" {
  description = "The GCP project ID"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Regional Configuration
variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "us-central1-a"
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "n8n-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "n8n-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "CIDR range for pods"
  type        = string
  default     = "10.2.0.0/16"
}

variable "services_cidr" {
  description = "CIDR range for services"
  type        = string
  default     = "10.1.0.0/16"
}

# GKE Configuration
variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "n8n-cluster"
}

variable "kubernetes_version" {
  description = "The Kubernetes version for the cluster"
  type        = string
  default     = "latest"
}

variable "node_pool_name" {
  description = "Name of the node pool"
  type        = string
  default     = "n8n-node-pool"
}

variable "node_count" {
  description = "Number of nodes in each zone"
  type        = number
  default     = 1
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "min_node_count" {
  description = "Minimum number of nodes in the node pool"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes in the node pool"
  type        = number
  default     = 3
}

variable "machine_type" {
  description = "Machine type for the cluster nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  description = "Disk size in GB for cluster nodes"
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 20 && var.disk_size_gb <= 500
    error_message = "Disk size must be between 20 and 500 GB."
  }
}

variable "disk_type" {
  description = "Disk type for cluster nodes"
  type        = string
  default     = "pd-standard"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

variable "spot_nodes" {
  description = "Whether to use Spot VMs (recommended over preemptible nodes)"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the GKE cluster"
  type        = bool
  default     = true
}

# N8N Configuration
variable "domain_name" {
  description = "Domain name for n8n (e.g., n8n.example.com)"
  type        = string
  default     = "n8n.example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid FQDN."
  }
}

variable "n8n_namespace" {
  description = "Kubernetes namespace for n8n"
  type        = string
  default     = "n8n"
}

variable "n8n_image_tag" {
  description = "Docker image tag for n8n"
  type        = string
  default     = "latest"
}

variable "n8n_replicas" {
  description = "Number of n8n replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.n8n_replicas >= 1 && var.n8n_replicas <= 5
    error_message = "N8N replicas must be between 1 and 5."
  }
}

variable "n8n_basic_auth_user" {
  description = "Basic auth username for n8n"
  type        = string
  default     = "admin"
}

variable "n8n_basic_auth_password" {
  description = "Basic auth password for n8n"
  type        = string
  sensitive   = true
}

variable "enable_n8n_metrics" {
  description = "Enable n8n metrics collection"
  type        = bool
  default     = true
}

# Resource Configuration
variable "n8n_cpu_request" {
  description = "CPU request for n8n pods"
  type        = string
  default     = "500m"
}

variable "n8n_memory_request" {
  description = "Memory request for n8n pods"
  type        = string
  default     = "512Mi"
}

variable "n8n_cpu_limit" {
  description = "CPU limit for n8n pods"
  type        = string
  default     = "1000m"
}

variable "n8n_memory_limit" {
  description = "Memory limit for n8n pods"
  type        = string
  default     = "1024Mi"
}

# PostgreSQL Configuration
variable "postgres_image_tag" {
  description = "PostgreSQL Docker image tag"
  type        = string
  default     = "13"
}

variable "postgres_storage_size" {
  description = "PostgreSQL storage size"
  type        = string
  default     = "20Gi"
}

variable "postgres_storage_class" {
  description = "Storage class for PostgreSQL"
  type        = string
  default     = "standard-rwo"
}

variable "n8n_storage_size" {
  description = "N8N persistent volume storage size"
  type        = string
  default     = "2Gi"
}

variable "n8n_storage_class" {
  description = "Storage class for N8N persistent volume"
  type        = string
  default     = "standard-rwo"
}

variable "postgres_cpu_request" {
  description = "CPU request for PostgreSQL pods"
  type        = string
  default     = "250m"
}

variable "postgres_memory_request" {
  description = "Memory request for PostgreSQL pods"
  type        = string
  default     = "256Mi"
}

variable "postgres_cpu_limit" {
  description = "CPU limit for PostgreSQL pods"
  type        = string
  default     = "500m"
}

variable "postgres_memory_limit" {
  description = "Memory limit for PostgreSQL pods"
  type        = string
  default     = "512Mi"
}

variable "postgres_non_root_user" {
  description = "PostgreSQL non-root user for n8n"
  type        = string
  default     = "n8n_user"
}

variable "postgres_non_root_password" {
  description = "PostgreSQL non-root password for n8n"
  type        = string
  sensitive   = true
}

variable "postgres_root_user" {
  description = "PostgreSQL root user"
  type        = string
}

variable "postgres_root_password" {
  description = "PostgreSQL root password"
  type        = string
  sensitive   = true
}

variable "postgres_user" {
  description = "PostgreSQL user"
  type        = string
}

# SSL and Ingress Configuration
variable "enable_ssl" {
  description = "Enable SSL certificate for ingress"
  type        = bool
  default     = true
}

variable "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  type        = string
  default     = "n8n-ssl-cert"
}

variable "static_ip_name" {
  description = "Name of the static IP address"
  type        = string
  default     = "n8n-static-ip"
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and logging"
  type        = bool
  default     = true
}

# Backup Configuration
variable "enable_backups" {
  description = "Enable automatic backups"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

# Security Configuration
variable "enable_network_policy" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable GKE Workload Identity"
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "List of authorized networks for GKE master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# Timezone Configuration
variable "timezone" {
  description = "Timezone for n8n"
  type        = string
  default     = "UTC"
}

variable "n8n_service_type" {
  description = "The type of the N8N Kubernetes service."
  type        = string
  default     = "NodePort"
}
