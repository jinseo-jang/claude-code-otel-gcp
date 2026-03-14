resource "google_service_account" "collector" {
  account_id   = "${var.service_name}-sa"
  display_name = "Claude Code Otel Collector Service Account"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.collector.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.collector.email}"
}

resource "google_project_iam_member" "secret_viewer" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.collector.email}"
}
