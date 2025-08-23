output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc_network.name
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.vpc_network.self_link
}

output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.vpc_network.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_self_link" {
  description = "Self link of the subnet"
  value       = google_compute_subnetwork.subnet.self_link
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "pods_range_name" {
  description = "Name of the pods IP range"
  value       = "pod-ranges"
}

output "services_range_name" {
  description = "Name of the services IP range"
  value       = "services-range"
}

output "pods_cidr" {
  description = "CIDR range for pods"
  value       = var.pods_cidr
}

output "services_cidr" {
  description = "CIDR range for services"
  value       = var.services_cidr
}

output "router_name" {
  description = "Name of the Cloud Router"
  value       = google_compute_router.router.name
}

output "nat_name" {
  description = "Name of the Cloud NAT"
  value       = google_compute_router_nat.nat.name
}