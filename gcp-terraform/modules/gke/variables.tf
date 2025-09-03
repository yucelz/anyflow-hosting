variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "zone" {
  description = "The GCP zone"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "The Kubernetes version for the cluster"
  type        = string
  default     = "latest"
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "pods_range_name" {
  description = "Name of the pods IP range"
  type        = string
}

variable "services_range_name" {
  description = "Name of the services IP range"
  type        = string
}

# Node pool configuration
variable "node_pool_name" {
  description = "Name of the node pool"
  type        = string
}

variable "node_count" {
  description = "Initial number of nodes in the node pool"
  type        = number
  default     = 1
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
  default     = 50
}

variable "disk_type" {
  description = "Disk type for cluster nodes"
  type        = string
  default     = "pd-standard"
}

variable "preemptible_nodes" {
  description = "Whether to use preemptible nodes (deprecated, use spot_nodes instead)"
  type        = bool
  default     = false
}

variable "spot_nodes" {
  description = "Whether to use Spot VMs (recommended over preemptible nodes)"
  type        = bool
  default     = false
}

# Security configuration
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

variable "workload_identity_namespace" {
  description = "Kubernetes namespace for workload identity"
  type        = string
  default     = "n8n"
}

variable "workload_identity_ksa_name" {
  description = "Kubernetes service account name for workload identity"
  type        = string
  default     = "n8n-ksa"
}

variable "authorized_networks" {
  description = "List of authorized networks for GKE master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "node_locations" {
  description = "List of zones for regional cluster nodes"
  type        = list(string)
  default     = null
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the GKE cluster"
  type        = bool
  default     = true
}
