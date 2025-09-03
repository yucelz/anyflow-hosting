# GKE module for N8N deployment

# Service account for GKE nodes
resource "google_service_account" "gke_node_service_account" {
  account_id   = "${var.cluster_name}-gke-sa"
  display_name = "GKE Node Service Account for ${var.cluster_name}"
  description  = "Service account for GKE nodes in ${var.cluster_name} cluster"
}

# IAM bindings for the service account
resource "google_project_iam_member" "gke_node_service_account_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_service_account.email}"
}

# Workload Identity service account (if enabled)
resource "google_service_account" "workload_identity_service_account" {
  count = var.enable_workload_identity ? 1 : 0

  account_id   = "${var.cluster_name}-wi-sa"
  display_name = "Workload Identity Service Account for ${var.cluster_name}"
  description  = "Service account for Workload Identity in ${var.cluster_name} cluster"
}

# Create GKE cluster (Zonal for singularity, Regional for others)
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.max_node_count <= 2 ? var.zone : var.region  # Use zonal for singularity (max 2 nodes)

  network    = var.network_name
  subnetwork = var.subnet_name

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # Kubernetes version
  min_master_version = var.kubernetes_version == "latest" ? null : var.kubernetes_version

  # For regional clusters, specify node locations (zones within the region)
  # For zonal clusters (singularity), this is ignored
  node_locations = var.max_node_count <= 2 ? null : (var.node_locations != null ? var.node_locations : [
    "${var.region}-a",
    "${var.region}-b",
    "${var.region}-c"
  ])

  # Network configuration
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Enable network policy if specified
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled  = true
      provider = "CALICO"
    }
  }

  # Enable workload identity if specified
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Addons configuration
  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    network_policy_config {
      disabled = !var.enable_network_policy
    }

    dns_cache_config {
      enabled = true
    }
  }

  # Enable logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Cluster autoscaling - disabled for singularity to enforce strict limits
  dynamic "cluster_autoscaling" {
    for_each = var.max_node_count > 2 ? [1] : []
    content {
      enabled = true
      resource_limits {
        resource_type = "cpu"
        minimum       = 1
        maximum       = 100
      }
      resource_limits {
        resource_type = "memory"
        minimum       = 2
        maximum       = 1000
      }
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "02:00"
    }
  }

  # Enable Shielded GKE nodes
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Resource labels
  resource_labels = var.labels

  # Deletion protection
  deletion_protection = var.deletion_protection

  lifecycle {
    ignore_changes = [
      node_config,
      initial_node_count
    ]
  }
}

# Create node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = var.node_pool_name
  location   = var.max_node_count <= 2 ? var.zone : var.region  # Match cluster location type
  cluster    = google_container_cluster.primary.name
  
  # Auto-scaling configuration
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  # Initial node count
  initial_node_count = var.node_count

  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # Node configuration
  node_config {
    # Use Spot VMs if enabled, otherwise fall back to preemptible nodes for backward compatibility
    spot         = var.spot_nodes
    preemptible  = var.spot_nodes ? false : var.preemptible_nodes
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    image_type   = "COS_CONTAINERD"

    # Service account
    service_account = google_service_account.gke_node_service_account.email

    # OAuth scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Labels and tags
    labels = merge(var.labels, {
      cluster = var.cluster_name
      pool    = var.node_pool_name
    })

    tags = ["gke-node", var.cluster_name, "n8n"]

    # Shielded instance configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload metadata configuration for Workload Identity
    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }

    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  # Network configuration
  network_config {
    pod_range     = var.pods_range_name
    pod_ipv4_cidr_block = null
  }

  depends_on = [google_container_cluster.primary]
}

# Bind Workload Identity (if enabled)
resource "google_service_account_iam_binding" "workload_identity_binding" {
  count = var.enable_workload_identity ? 1 : 0

  service_account_id = google_service_account.workload_identity_service_account[0].name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.workload_identity_namespace}/${var.workload_identity_ksa_name}]",
  ]
}
