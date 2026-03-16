resource "google_monitoring_dashboard" "claude_code" {
  dashboard_json = templatefile("${path.module}/dashboard.json.tpl", {
    project_id = var.project_id
  })
}
