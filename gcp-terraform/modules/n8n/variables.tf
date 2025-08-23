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

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
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

# Resource configuration
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