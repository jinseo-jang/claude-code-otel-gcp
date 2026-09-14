resource "google_service_account" "invoker" {
  account_id   = var.invoker_sa_name
  display_name = "Claude Code OTel Invoker Service Account"
  description  = "Intermediate service account impersonated by federated IdP identities to generate Cloud Run ID tokens"
}

# Allow federated IdP users belonging to authorized_group to impersonate the intermediate SA
resource "google_service_account_iam_member" "wif_group_impersonator" {
  service_account_id = google_service_account.invoker.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.claude_code.name}/group/${var.authorized_group}"
}

# Grant the intermediate SA permission to invoke the Cloud Run OTel Collector
resource "google_cloud_run_service_iam_member" "invoker_run_access" {
  location = var.region
  service  = var.service_name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.invoker.email}"
}

# Look up the Cloud Run OTel Collector service to export its URL
data "google_cloud_run_service" "collector" {
  name     = var.service_name
  location = var.region
}

# Grant the intermediate SA permission to invoke Vertex AI models (Claude)
resource "google_project_iam_member" "invoker_aiplatform_access" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.invoker.email}"
}

