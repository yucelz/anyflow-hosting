# N8N module for Kubernetes deployment

# Create namespace
resource "kubernetes_namespace" "n8n" {
  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      name = var.namespace
    })
  }
}

# Create secrets for N8N configuration
resource "kubernetes_secret" "n8n_secrets" {
  metadata {
    name      = "n8n-secrets"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "secrets"
    })
  }

  type = "Opaque"

  data = {
    DB_TYPE                   = "postgresdb"
    DB_POSTGRESDB_DATABASE    = "n8n"
    N8N_BASIC_AUTH_ACTIVE     = "true"
    N8N_BASIC_AUTH_USER       = var.n8n_basic_auth_user
    N8N_BASIC_AUTH_PASSWORD   = var.n8n_basic_auth_password
    N8N_HOST                  = var.domain_name
    N8N_ENCRYPTION_KEY        = var.n8n_encryption_key
    GENERIC_TIMEZONE          = var.timezone
    WEBHOOK_TUNNEL_URL        = "https://${var.domain_name}/"
    NODE_ENV                  = "production"
    N8N_METRICS               = var.enable_n8n_metrics ? "true" : "false"
    NODE_OPTIONS              = "--max_old_space_size=1024"
    EXECUTIONS_PROCESS        = "main"
    N8N_LOG_LEVEL             = "info"
    N8N_PROTOCOL              = "http" # Changed to http as per reference
    N8N_PORT                  = "5678"
  }
}

# Create secrets for PostgreSQL configuration
resource "kubernetes_secret" "postgres_secret" {
  metadata {
    name      = "postgres-secret"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "database-secrets"
    })
  }

  type = "Opaque"

  data = {
    POSTGRES_USER             = base64encode(var.postgres_user)
    POSTGRES_PASSWORD         = base64encode(var.postgres_password)
    POSTGRES_DB               = base64encode("n8n")
    POSTGRES_NON_ROOT_USER    = base64encode(var.postgres_non_root_user)
    POSTGRES_NON_ROOT_PASSWORD = base64encode(var.postgres_non_root_password)
  }
}

# PostgreSQL ConfigMap for init script
resource "kubernetes_config_map" "postgres_init_data" {
  metadata {
    name      = "init-data"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "database-config"
    })
  }

  data = {
    "init-data.sh" = <<-EOT
      #!/bin/bash
      set -e;
      if [ -n "$${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "$${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
        psql -v ON_ERROR_STOP=1 --username "$${POSTGRES_USER}" --dbname "$${POSTGRES_DB}" <<-EOSQL
          CREATE USER "$${POSTGRES_NON_ROOT_USER}" WITH PASSWORD '$${POSTGRES_NON_ROOT_PASSWORD}';
          GRANT ALL PRIVILEGES ON DATABASE $${POSTGRES_DB} TO "$${POSTGRES_NON_ROOT_USER}";
        EOSQL
      else
        echo "SETUP INFO: No Environment variables given!"
      fi
    EOT
  }
}

# N8N Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "n8n_claim0" {
  metadata {
    name      = "n8n-claim0"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "data"
    })
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.n8n_storage_size # New variable for N8N storage
      }
    }
    storage_class_name = var.n8n_storage_class # New variable for N8N storage class
  }

  # Extended timeouts to handle rate limiting issues
  timeouts {
    create = "15m"
  }

  # Wait for namespace to be fully ready
  depends_on = [kubernetes_namespace.n8n]
}

# PostgreSQL StatefulSet
resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "postgres" # Renamed to postgres as per reference
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "database"
    })
  }

  spec {
    service_name = "postgres-service" # Renamed to postgres-service as per reference
    replicas     = 1

    selector {
      match_labels = {
        app       = "n8n"
        component = "database"
      }
    }

    template {
      metadata {
        labels = merge(var.labels, {
          app       = "n8n"
          component = "database"
        })
      }

      spec {
        container {
          name  = "postgresql"
          image = "postgres:${var.postgres_image_tag}"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secret.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
          }

          env {
            name = "POSTGRES_DB"
            value = "n8n"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secret.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name = "POSTGRES_NON_ROOT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secret.metadata[0].name
                key  = "POSTGRES_NON_ROOT_USER"
              }
            }
          }

          env {
            name = "POSTGRES_NON_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secret.metadata[0].name
                key  = "POSTGRES_NON_ROOT_PASSWORD"
              }
            }
          }

          env {
            name  = "POSTGRES_HOST"
            value = "postgres-service"
          }

          env {
            name  = "POSTGRES_PORT"
            value = "5432"
          }

          volume_mount {
            name       = "postgresql-pv" # Renamed to postgresql-pv as per reference
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "init-data"
            mount_path = "/docker-entrypoint-initdb.d/init-n8n-user.sh"
            sub_path   = "init-data.sh"
          }

          resources {
            requests = {
              memory = var.postgres_memory_request
              cpu    = var.postgres_cpu_request
            }
            limits = {
              memory = var.postgres_memory_limit
              cpu    = var.postgres_cpu_limit
            }
          }

          # Liveness probe
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", var.postgres_non_root_user, "-d", "n8n"] # Updated user
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          # Readiness probe
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", var.postgres_non_root_user, "-d", "n8n"] # Updated user
            }
            initial_delay_seconds = 15
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        # Security context
        security_context {
          fs_group = 999
        }

        volume {
          name = "postgres-secret"
          secret {
            secret_name = kubernetes_secret.postgres_secret.metadata[0].name
          }
        }

        volume {
          name = "init-data"
          config_map {
            name        = kubernetes_config_map.postgres_init_data.metadata[0].name
            default_mode = "0744"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgresql-pv" # Renamed to postgresql-pv as per reference
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = var.postgres_storage_size
          }
        }
        storage_class_name = var.postgres_storage_class
      }
    }
  }

  depends_on = [kubernetes_secret.postgres_secret, kubernetes_config_map.postgres_init_data]
}


# PostgreSQL Service
resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres-service" # Renamed to postgres-service as per reference
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "database"
    })
  }

  spec {
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }

    cluster_ip = "None"

    selector = {
      app       = "n8n"
      component = "database"
    }
  }
}

# N8N Deployment
resource "kubernetes_deployment" "n8n" {
  metadata {
    name      = "n8n-deployment"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "deployment"
    })
  }

  spec {
    replicas = var.n8n_replicas

    selector {
      match_labels = {
        app       = "n8n"
        component = "deployment"
      }
    }

    template {
      metadata {
        labels = merge(var.labels, {
          app       = "n8n"
          component = "deployment"
        })
        annotations = var.enable_monitoring ? {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "5678"
          "prometheus.io/path"   = "/metrics"
        } : {}
      }

      spec {
        init_container { # Added initContainer
          name  = "volume-permissions"
          image = "busybox:1.36"
          command = ["sh", "-c", "chown 1000:1000 /home/node/.n8n"] # Updated path
          volume_mount {
            name       = "n8n-claim0"
            mount_path = "/home/node/.n8n"
          }
        }

        container {
          name              = "n8n"
          image             = "n8nio/n8n:${var.n8n_image_tag}"
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/sh"] # Added command
          args              = ["-c", "sleep 5; n8n start"] # Added args

          port {
            name           = "http"
            container_port = 5678
          }

          env {
            name = "DB_TYPE"
            value = "postgresdb"
          }
          env {
            name = "DB_POSTGRESDB_HOST"
            value = "postgres-service.n8n.svc.cluster.local" # Updated FQDN
          }
          env {
            name = "DB_POSTGRESDB_PORT"
            value = "5432"
          }
          env {
            name = "DB_POSTGRESDB_DATABASE"
            value = "n8n"
          }
          env {
            name = "DB_POSTGRESDB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secret.metadata[0].name
                key  = "POSTGRES_NON_ROOT_USER" # Updated key
              }
            }
          }
          env {
            name = "DB_POSTGRESDB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres_secret.metadata[0].name
                key  = "POSTGRES_NON_ROOT_PASSWORD" # Updated key
              }
            }
          }
          env {
            name = "N8N_PROTOCOL"
            value = "http" # Changed to http
          }
          env_from {
            secret_ref {
              name = kubernetes_secret.n8n_secrets.metadata[0].name
            }
          }

          # Health checks - more lenient for development
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }

          # Startup probe - more generous timing
          startup_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 60
            period_seconds        = 15
            timeout_seconds       = 10
            failure_threshold     = 40
          }

          resources {
            limits = {
              cpu    = var.n8n_cpu_limit
              memory = var.n8n_memory_limit
            }
            requests = {
              cpu    = var.n8n_cpu_request
              memory = var.n8n_memory_request
            }
          }

          # Security context
          security_context {
            run_as_non_root                = true
            run_as_user                   = 1000
            run_as_group                  = 1000
            allow_privilege_escalation    = false
            read_only_root_filesystem     = false
            capabilities {
              drop = ["ALL"]
            }
          }

          # Volume mounts for temporary data
          volume_mount {
            name       = "n8n-claim0" # Updated to n8n-claim0
            mount_path = "/home/node/.n8n" # Updated path
          }
        }

        # Volumes
        volume {
          name = "n8n-claim0" # Updated to n8n-claim0
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.n8n_claim0.metadata[0].name
          }
        }

        # Security context for pod
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
        }

        # Node affinity for better distribution
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = ["n8n"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
      }
    }

    strategy {
      type = "Recreate" # Changed to Recreate as per reference
    }
  }

  depends_on = [kubernetes_service.postgres, kubernetes_persistent_volume_claim.n8n_claim0]
}

# N8N Service
resource "kubernetes_service" "n8n" {
  metadata {
    name      = "n8n-service"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    annotations = var.enable_monitoring ? {
      "prometheus.io/probe"      = "true"
      "prometheus.io/probe-path" = "/healthz"
    } : {}
    labels = merge(var.labels, {
      app       = "n8n"
      component = "service"
    })
  }

  spec {
    type = "ClusterIP"

    selector = {
      app       = "n8n"
      component = "deployment"
    }

    port {
      protocol    = "TCP"
      name        = "http"
      port        = 80
      target_port = 5678
    }

    session_affinity = "ClientIP"
  }
}

# Create static IP for the ingress
resource "google_compute_global_address" "n8n_ip" {
  name = var.static_ip_name
}

# Create SSL certificate (if enabled)
resource "google_compute_managed_ssl_certificate" "n8n_ssl_cert" {
  count = var.enable_ssl ? 1 : 0

  name = var.ssl_certificate_name

  managed {
    domains = [var.domain_name]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create BackendConfig for health checks
resource "kubernetes_manifest" "backend_config" {
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "n8n-backend-config"
      namespace = kubernetes_namespace.n8n.metadata[0].name
    }
    spec = {
      healthCheck = {
        checkIntervalSec   = 30
        timeoutSec         = 5
        healthyThreshold   = 1
        unhealthyThreshold = 2
        type               = "HTTP"
        requestPath        = "/healthz"
        port               = 5678
      }
      sessionAffinity = {
        affinityType = "CLIENT_IP"
      }
    }
  }
}

# Ingress
resource "kubernetes_ingress_v1" "n8n_ingress" {
  metadata {
    name      = "n8n-ingress"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.labels, {
      app       = "n8n"
      component = "ingress"
    })
    annotations = merge(
      {
        "kubernetes.io/ingress.class"                    = "gce"
        "kubernetes.io/ingress.global-static-ip-name"    = google_compute_global_address.n8n_ip.name
        "kubernetes.io/ingress.allow-http"               = "false"
        "cloud.google.com/backend-config"                = jsonencode({
          "default" = "n8n-backend-config"
        })
        "cloud.google.com/neg"                           = jsonencode({
          "ingress" = true
        })
      },
      var.enable_ssl ? {
        "networking.gke.io/managed-certificates" = google_compute_managed_ssl_certificate.n8n_ssl_cert[0].name
      } : {}
    )
  }

  spec {
    rule {
      host = var.domain_name
      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = kubernetes_service.n8n.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service.n8n,
    kubernetes_manifest.backend_config
  ]
}

# Network Policy (if enabled)
resource "kubernetes_network_policy" "n8n_network_policy" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "n8n-network-policy"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "n8n"
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Ingress rules
    ingress {
      # Allow traffic from ingress controller
      from {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      
      # Allow traffic between n8n pods
      from {
        pod_selector {
          match_labels = {
            app = "n8n"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "5678"
      }

      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }

    # Egress rules
    egress {
      # Allow all egress (n8n needs to connect to external services)
    }
  }
}

# Horizontal Pod Autoscaler for N8N - disabled for singularity (single replica)
resource "kubernetes_horizontal_pod_autoscaler_v2" "n8n_hpa" {
  count = var.enable_autoscaling && var.n8n_replicas > 1 ? 1 : 0

  metadata {
    name      = "n8n-hpa"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.n8n.metadata[0].name
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.target_cpu_utilization
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.target_memory_utilization
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 300
        select_policy               = "Max"
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 15
        }
        policy {
          type          = "Pods"
          value         = 2
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 300
        select_policy               = "Min"
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 15
        }
      }
    }
  }
}

# Pod Disruption Budget - only for multi-replica deployments
resource "kubernetes_pod_disruption_budget_v1" "n8n_pdb" {
  count = var.n8n_replicas > 1 ? 1 : 0

  metadata {
    name      = "n8n-pdb"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }

  spec {
    min_available = "50%"
    selector {
      match_labels = {
        app       = "n8n"
        component = "deployment"
      }
    }
  }
}
