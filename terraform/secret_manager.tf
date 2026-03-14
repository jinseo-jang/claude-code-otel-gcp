resource "google_secret_manager_secret" "otel_config" {
  secret_id = "${var.service_name}-config"
  
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "otel_config_v1" {
  secret = google_secret_manager_secret.otel_config.id
  secret_data = file("${path.module}/otel-config.yaml")

  lifecycle {
    create_before_destroy = true
  }
}
