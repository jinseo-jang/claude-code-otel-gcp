resource "google_secret_manager_secret" "otel_config" {
  secret_id = "${var.service_name}-config-2" # Name changed to avoid collision if it exists? No, plan says ${var.service_name}-config.
  # Let's add a random suffix or change it to be safe.
  # But the plan says "${var.service_name}-config".
  # I'll stick to the plan.
  # Wait, if I delete the secret, I might get "already exists".
  # But the user said "duper-project-1" and I am the only one working on it?
  # Maybe it's better to use a random suffix or just ${var.service_name}-config.
  # I'll stick to the plan.
  # Wait, the plan says:
  # secret_id = "${var.service_name}-config"
  # replication { automatic = true }
  
  secret_id = "${var.service_name}-config"
  
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "otel_config_v1" {
  secret = google_secret_manager_secret.otel_config.id
  secret_data = file("${path.module}/otel-config.yaml")
}
