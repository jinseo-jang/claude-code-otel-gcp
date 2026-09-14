output "workload_identity_pool_id" {
  description = "The ID of the Workload Identity Pool."
  value       = google_iam_workload_identity_pool.claude_code.workload_identity_pool_id
}

output "workload_identity_pool_name" {
  description = "The canonical resource name of the Workload Identity Pool."
  value       = google_iam_workload_identity_pool.claude_code.name
}

output "workload_identity_pool_provider_id" {
  description = "The ID of the Workload Identity Pool Provider."
  value       = google_iam_workload_identity_pool_provider.okta.workload_identity_pool_provider_id
}

output "workload_identity_pool_provider_name" {
  description = "The canonical resource name of the Workload Identity Pool Provider."
  value       = google_iam_workload_identity_pool_provider.okta.name
}

output "invoker_service_account_email" {
  description = "The email address of the intermediate invocation service account."
  value       = google_service_account.invoker.email
}

output "sts_audience" {
  description = "The audience URI required when calling GCP STS token exchange."
  value       = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.okta.name}"
}

output "authorized_principal_set" {
  description = "The IAM principalSet member string bound to roles/iam.workloadIdentityUser."
  value       = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.claude_code.name}/group/${var.authorized_group}"
}

output "collector_url" {
  description = "The invocation URL of the Cloud Run OTel Collector service."
  value       = data.google_cloud_run_service.collector.status[0].url
}

