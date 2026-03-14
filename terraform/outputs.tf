output "collector_url" {
  value = google_cloud_run_service.collector.status[0].url
}
