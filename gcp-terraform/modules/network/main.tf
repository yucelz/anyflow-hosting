# Network module for N8N GCP deployment

# Create VPC network
resource "google_compute_network" "vpc_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  mtu                     = 1460

  description = "VPC network for ${var.network_name}"
}

# Create subnet
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.id

  description = "Subnet for ${var.subnet_name}"

  # Secondary IP ranges for GKE
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = var.services_cidr
  }

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = var.pods_cidr
  }

  # Enable private Google access
  private_ip_google_access = true

  # Log configuration
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling       = 0.5
    metadata           = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rule for internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.vpc_network.name

  description = "Allow internal communication within VPC"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr
  ]

  target_tags = ["n8n"]
}

# Firewall rule for SSH access (if needed for debugging)
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.vpc_network.name

  description = "Allow SSH access to nodes for debugging"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google Cloud IAP range
  target_tags   = ["n8n"]
}

# Firewall rule for health checks
resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.network_name}-allow-health-check"
  network = google_compute_network.vpc_network.name

  description = "Allow health check probes"

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "130.211.0.0/22",  # Google Load Balancer health check ranges
    "35.191.0.0/16"
  ]

  target_tags = ["n8n"]
}

# Cloud NAT Router (for outbound internet access from private nodes)
resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.vpc_network.id

  description = "Router for NAT gateway"
}

# Cloud NAT gateway
resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}