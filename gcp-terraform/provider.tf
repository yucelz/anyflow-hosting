# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure Kubernetes provider - will be configured after cluster creation
provider "kubernetes" {
  # Configuration will be provided via environment or CLI
  config_path = "~/.kube/config"
  
  # Ignore annotations that cause issues
  ignore_annotations = [
    "kubectl.kubernetes.io/last-applied-configuration",
  ]
}