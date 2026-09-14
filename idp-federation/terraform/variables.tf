variable "project_id" {
  description = "GCP project ID where WIF and intermediate IAM resources will be deployed."
  type        = string
}

variable "region" {
  description = "GCP region where the Cloud Run service is deployed."
  type        = string
  default     = "us-central1"
}

variable "pool_id" {
  description = "ID of the Workload Identity Pool."
  type        = string
  default     = "claude-code-pool"
}

variable "pool_display_name" {
  description = "Display name of the Workload Identity Pool (max 32 chars)."
  type        = string
  default     = "Claude Code WIF Pool"
}

variable "provider_id" {
  description = "ID of the Workload Identity Pool Provider for Okta."
  type        = string
  default     = "okta-oidc-provider"
}

variable "provider_display_name" {
  description = "Display name of the Workload Identity Pool Provider."
  type        = string
  default     = "Okta OIDC Provider"
}

variable "issuer_uri" {
  description = "OIDC Issuer URI of the corporate IdP (Okta)."
  type        = string
  default     = "https://example.okta.com/oauth2/default"
}

variable "allowed_audiences" {
  description = "List of acceptable audience values in the IdP JWT."
  type        = list(string)
  default     = ["api://default"]
}

variable "authorized_group" {
  description = "Name of the corporate IdP group authorized to authenticate and invoke the collector."
  type        = string
  default     = "claude-code-users"
}

variable "service_name" {
  description = "Name of the Cloud Run service running the OTel Collector."
  type        = string
  default     = "claude-code-otel-collector"
}

variable "invoker_sa_name" {
  description = "Name of the intermediate service account used for Cloud Run invocation."
  type        = string
  default     = "claude-code-otel-invoker"
}
