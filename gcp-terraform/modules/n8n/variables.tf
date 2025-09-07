# N8N Module Variables

variable "namespace" {
  description = "The Kubernetes namespace for N8N."
  type        = string
  default     = "n8n"
}

variable "labels" {
  description = "A map of labels to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "n8n_basic_auth_user" {
  description = "The basic authentication username for N8N."
  type        = string
}

variable "n8n_basic_auth_password" {
  description = "The basic authentication password for N8N."
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "The domain name for N8N."
  type        = string
}

variable "n8n_encryption_key" {
  description = "The encryption key for N8N."
  type        = string
  sensitive   = true
}

variable "timezone" {
  description = "The timezone for N8N."
  type        = string
  default     = "UTC"
}

variable "enable_n8n_metrics" {
  description = "Enable Prometheus metrics for N8N."
  type        = bool
  default     = false
}

variable "n8n_storage_size" {
  description = "The storage size for the N8N persistent volume."
  type        = string
  default     = "10Gi"
}

variable "n8n_storage_class" {
  description = "The storage class for the N8N persistent volume."
  type        = string
  default     = "standard"
}

variable "postgres_image_tag" {
  description = "The image tag for the PostgreSQL container."
  type        = string
  default     = "13"
}

variable "postgres_user" {
  description = "The main user for PostgreSQL."
  type        = string
}

variable "postgres_password" {
  description = "The password for the main PostgreSQL user."
  type        = string
  sensitive   = true
}

variable "postgres_non_root_user" {
  description = "The non-root user for PostgreSQL."
  type        = string
}

variable "postgres_non_root_password" {
  description = "The password for the non-root PostgreSQL user."
  type        = string
  sensitive   = true
}

variable "postgres_root_user" {
  description = "The root user for PostgreSQL."
  type        = string
  default     = ""
}

variable "postgres_root_password" {
  description = "The password for the root PostgreSQL user."
  type        = string
  sensitive   = true
  default     = ""
}

variable "postgres_memory_request" {
  description = "The memory request for the PostgreSQL container."
  type        = string
  default     = "512Mi"
}

variable "postgres_cpu_request" {
  description = "The CPU request for the PostgreSQL container."
  type        = string
  default     = "250m"
}

variable "postgres_memory_limit" {
  description = "The memory limit for the PostgreSQL container."
  type        = string
  default     = "1Gi"
}

variable "postgres_cpu_limit" {
  description = "The CPU limit for the PostgreSQL container."
  type        = string
  default     = "500m"
}

variable "postgres_storage_size" {
  description = "The storage size for the PostgreSQL persistent volume."
  type        = string
  default     = "10Gi"
}

variable "postgres_storage_class" {
  description = "The storage class for the PostgreSQL persistent volume."
  type        = string
  default     = "standard"
}

variable "n8n_replicas" {
  description = "The number of replicas for the N8N deployment."
  type        = number
  default     = 1
}

variable "enable_monitoring" {
  description = "Enable Prometheus monitoring annotations."
  type        = bool
  default     = false
}

variable "n8n_image_tag" {
  description = "The image tag for the N8N container."
  type        = string
  default     = "latest"
}

variable "n8n_cpu_limit" {
  description = "The CPU limit for the N8N container."
  type        = string
  default     = "1"
}

variable "n8n_memory_limit" {
  description = "The memory limit for the N8N container."
  type        = string
  default     = "2Gi"
}

variable "n8n_cpu_request" {
  description = "The CPU request for the N8N container."
  type        = string
  default     = "500m"
}

variable "n8n_memory_request" {
  description = "The memory request for the N8N container."
  type        = string
  default     = "1Gi"
}

variable "static_ip_name" {
  description = "The name of the static IP for the ingress."
  type        = string
}

variable "enable_ssl" {
  description = "Enable SSL for the ingress."
  type        = bool
  default     = false
}

variable "ssl_certificate_name" {
  description = "The name of the SSL certificate for the ingress."
  type        = string
  default     = ""
}

variable "enable_network_policy" {
  description = "Enable network policy for N8N."
  type        = bool
  default     = false
}

variable "enable_autoscaling" {
  description = "Enable Horizontal Pod Autoscaler for N8N."
  type        = bool
  default     = false
}

variable "min_replicas" {
  description = "The minimum number of replicas for the HPA."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "The maximum number of replicas for the HPA."
  type        = number
  default     = 3
}

variable "target_cpu_utilization" {
  description = "The target CPU utilization for the HPA."
  type        = number
  default     = 80
}

variable "target_memory_utilization" {
  description = "The target memory utilization for the HPA."
  type        = number
  default     = 80
}

variable "n8n_service_type" {
  description = "The type of the N8N Kubernetes service."
  type        = string
  default     = "NodePort"
}
