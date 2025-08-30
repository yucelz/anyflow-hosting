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
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
    args        = []
    env = {
      USE_GKE_GCLOUD_AUTH_PLUGIN = "True"
    }
  }
}

# Configure Helm provider with timeout settings
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
      args        = []
      env = {
        USE_GKE_GCLOUD_AUTH_PLUGIN = "True"
      }
    }
  }
}
