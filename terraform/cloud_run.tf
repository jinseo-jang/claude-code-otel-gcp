resource "google_cloud_run_service" "collector" {
  name     = var.service_name
  location = var.region

  template {
    metadata {
      annotations = {
        "config-hash" = sha256(file("${path.module}/otel-config.yaml"))
      }
    }
    spec {
      service_account_name = google_service_account.collector.email
      
      containers {
        image = local.collector_image
        
        ports {
          name           = "http1"
          container_port = 4318
        }
        
        args = ["--config=/etc/otel/config.yaml"] # Path to mounted config

        volume_mounts {
          name       = "config-volume"
          mount_path = "/etc/otel"
        }
      }
      
      volumes {
        name = "config-volume"
        secret {
          secret_name = google_secret_manager_secret.otel_config.secret_id
          items {
            key  = "latest"
            path = "config.yaml"
          }
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}
