variable "namespace" {
  description = "Kubernetes namespace for n8n"
  type        = string
  default     = "n8n"
}

variable "domain_name" {
  description = "Domain name for n8n"
  type        = string
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
}

variable "n8n_basic_auth_user" {
  description = "Basic auth username for n8n"
  type        = string
}

variable "n8n_basic_auth_password" {
  description = "Basic auth password for n8n"
  type        = string
  sensitive   = true
}

variable "n8n_encryption_key" {
  description = "Encryption key for n8n"
  type        = string
  sensitive   = true
}

variable "postgres_image_tag" {
  description = "PostgreSQL Docker image tag"
  type        = string
  default     = "13"
}

variable "postgres_user" {
  description = "PostgreSQL root user"
  type        = string
  default     = "postgres"
}

variable "postgres_password" {
  description = "PostgreSQL root password"
  type        = string
  sensitive   = true
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

variable "postgres_storage_size" {
  description = "PostgreSQL storage size"
  type        = string
  default     = "300Gi" # Updated default as per reference
}

variable "postgres_storage_class" {
  description = "Storage class for PostgreSQL"
  type        = string
  default     = "standard-rwo"
}

variable "n8n_storage_size" { # New variable for N8N storage
  description = "N8N persistent volume storage size"
  type        = string
  default     = "2Gi" # As per reference
}

variable "n8n_storage_class" { # New variable for N8N storage class
  description = "Storage class for N8N persistent volume"
  type        = string
  default     = "standard-rwo"
}

# Resource configuration
variable "n8n_cpu_request" {
  description = "CPU request for n8n pods"
  type        = string
  default     = "250m" # Updated default as per reference
}

variable "n8n_memory_request" {
  description = "Memory request for n8n pods"
  type        = string
  default     = "250Mi" # Updated default as per reference
}

variable "n8n_cpu_limit" {
  description = "CPU limit for n8n pods"
  type        = string
  default     = "500m" # Updated default as per reference
}

variable "n8n_memory_limit" {
  description = "Memory limit for n8n pods"
  type        = string
  default     = "500Mi" # Updated default as per reference
}


variable "postgres_cpu_request" {
  description = "CPU request for PostgreSQL pods"
  type        = string
  default     = "1" # Updated default as per reference
}

variable "postgres_memory_request" {
  description = "Memory request for PostgreSQL pods"
  type        = string
  default     = "2Gi" # Updated default as per reference
}

variable "postgres_cpu_limit" {
  description = "CPU limit for PostgreSQL pods"
  type        = string
  default     = "4" # Updated default as per reference
}

variable "postgres_memory_limit" {
  description = "Memory limit for PostgreSQL pods"
  type        = string
  default     = "4Gi" # Updated default as per reference
}

# SSL and ingress configuration
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

# Monitoring configuration
variable "enable_monitoring" {
  description = "Enable monitoring annotations"
  type        = bool
  default     = true
}

variable "enable_n8n_metrics" {
  description = "Enable n8n metrics collection"
  type        = bool
  default     = true
}

# Network policy
variable "enable_network_policy" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = false
}

# Autoscaling configuration
variable "enable_autoscaling" {
  description = "Enable horizontal pod autoscaling"
  type        = bool
  default     = false
}

variable "min_replicas" {
  description = "Minimum number of replicas for autoscaling"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of replicas for autoscaling"
  type        = number
  default     = 5
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 70
}

variable "target_memory_utilization" {
  description = "Target memory utilization for autoscaling"
  type        = number
  default     = 80
}

# Timezone configuration
variable "timezone" {
  description = "Timezone for n8n"
  type        = string
  default     = "UTC"
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
