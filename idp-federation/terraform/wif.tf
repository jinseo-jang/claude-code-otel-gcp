resource "google_iam_workload_identity_pool" "claude_code" {
  workload_identity_pool_id = var.pool_id
  display_name              = var.pool_display_name
  description               = "Workload Identity Pool for Claude Code OTel telemetry federation via Okta"
  disabled                  = false
}

resource "google_iam_workload_identity_pool_provider" "okta" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.claude_code.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = var.provider_display_name
  description                        = "Okta OIDC provider for Claude Code telemetry federation"

  attribute_mapping = {
    "google.subject"  = "assertion.sub"
    "google.groups"   = "assertion.groups"
    "attribute.email" = "assertion.email"
  }

  attribute_condition = "has(assertion.groups) && '${var.authorized_group}' in assertion.groups"

  oidc {
    issuer_uri        = var.issuer_uri
    allowed_audiences = var.allowed_audiences
  }
}
