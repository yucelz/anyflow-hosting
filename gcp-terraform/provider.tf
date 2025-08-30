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
  
  # Add timeout configurations to prevent rate limiter issues
  # Note: manifest_resource is now permanently enabled and no longer needed
  
  # Configure client timeouts
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "gcloud"
    args = [
      "container",
      "clusters",
      "get-credentials",
      var.cluster_name != null ? "${var.environment}-${var.cluster_name}" : "dev-n8n-cluster",
      "--zone=${var.zone}",
      "--project=${var.project_id}"
    ]
  }
}

# Configure Helm provider with timeout settings
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    
    # Configure client timeouts
    exec {
      api_version = "client.authentication.k8s.io/v1"
      command     = "gcloud"
      args = [
        "container",
        "clusters", 
        "get-credentials",
        var.cluster_name != null ? "${var.environment}-${var.cluster_name}" : "dev-n8n-cluster",
        "--zone=${var.zone}",
        "--project=${var.project_id}"
      ]
    }
  }
}
