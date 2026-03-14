# OpenTelemetry Integration with GCP Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Deploy an OpenTelemetry Collector on Cloud Run to collect metrics and logs from Claude Code and route them to Google Cloud Managed Service for Prometheus (GMP) and Cloud Logging.

**Architecture:** A centralized Otel Collector on Cloud Run acting as a gateway. Secured by IAM. Claude Code authenticates using dynamic ID tokens.

**Tech Stack:** Terraform, OpenTelemetry, GCP (Cloud Run, Secret Manager, GMP, Cloud Logging).

---

### Task 1: Terraform Bootstrap & Configuration

**Files:**
- Create: `terraform/provider.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/locals.tf`

**Step 1: Create `provider.tf`**
Configure Google provider.

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
```

**Step 2: Create `variables.tf`**
Define variables.

```hcl
variable "project_id" {
  type    = string
  default = "duper-project-1"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "service_name" {
  type    = string
  default = "claude-code-otel-collector"
}
```

**Step 3: Create `locals.tf`**
Define locals.

```hcl
locals {
  collector_image = "us-docker.pkg.dev/cloud-ops-agents-artifacts/google-cloud-opentelemetry-collector/otelcol-google:0.144.0" # Or latest
}
```

**Step 4: Initialize Terraform**
Run: `terraform -chdir=terraform init`

**Step 5: Commit**
```bash
git add terraform/*.tf
git commit -m "infra: bootstrap terraform"
```

### Task 2: Secret Manager & Config

**Files:**
- Create: `terraform/secret_manager.tf`
- Create: `terraform/otel-config.yaml`

**Step 1: Create `secret_manager.tf`**
Create secret for collector config.

```hcl
resource "google_secret_manager_secret" "otel_config" {
  secret_id = "${var.service_name}-config"
  
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "otel_config_v1" {
  secret = google_secret_manager_secret.otel_config.id
  secret_data = file("${path.module}/otel-config.yaml")
}
```

**Step 2: Create `otel-config.yaml`**
Collector configuration.

```yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:

processors:
  batch:
  resource:
    attributes:
      - key: service.name
        value: claude-code
        action: upsert

exporters:
  googlemanagedprometheus:
  googlecloud:

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [googlemanagedprometheus]
    logs:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [googlecloud]
```

**Step 3: Commit**
```bash
git add terraform/secret_manager.tf terraform/otel-config.yaml
git commit -m "infra: add secret manager and collector config"
```

### Task 3: IAM & Service Account

**Files:**
- Create: `terraform/iam.tf`

**Step 1: Create `iam.tf`**
Create service account for Cloud Run and assign roles.

```hcl
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
```

**Step 2: Commit**
```bash
git add terraform/iam.tf
git commit -m "infra: add iam and service account"
```

### Task 4: Cloud Run Deployment

**Files:**
- Create: `terraform/cloud_run.tf`
- Create: `terraform/outputs.tf`

**Step 1: Create `cloud_run.tf`**
Deploy Cloud Run service.

```hcl
resource "google_cloud_run_service" "collector" {
  name     = var.service_name
  location = var.region

  template {
    spec {
      service_account_name = google_service_account.collector.email
      
      containers {
        image = local.collector_image
        
        ports {
          container_port = 4317 # gRPC
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

# Secure with IAM
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers", # Wait, we want secure! 
      # User prefers secure. Let's change to specific users/SAs.
      # Since we are deploying, we should use the user's gcloud identity.
      # But we don't know it exactly. 
      # Actually, let's allow "allAuthenticatedUsers" or specific email.
      # User said they use ADC.
      # Let's use the VM Service Account if we know it.
      # Or just leave it open for now and user can restrict?
      # No, design says secure.
      # Let's use the default compute engine service account for now?
      # Or "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
      # Let's ask or use a variable.
      # Actually, I can use data source to find the default SA.
    ]
  }
}
# data "google_compute_default_service_account" "default" {}
# resource "google_cloud_run_service_iam_policy" "policy" { ... }

# BETTER APPROACH: Do not set iam_policy for noauth. 
# By default, Cloud Run requires auth.
# We just need to grant roles/run.invoker to the user/SA running Claude Code.
```

Wait, let's refine `cloud_run.tf` to match the design.
Design: "Authentication: 'Require authentication'".
So I will **NOT** add `google_cloud_run_service_iam_policy` with `allUsers`.
By default it's secured.
I just need to output the URL.

**Step 2: Create `outputs.tf`**
Output the URL.

```hcl
output "collector_url" {
  value = google_cloud_run_service.collector.status[0].url
}
```

**Step 3: Commit**
```bash
git add terraform/cloud_run.tf terraform/outputs.tf
git commit -m "infra: add cloud run service"
```

### Task 5: Apply & Verify

**Files:**
- None (Execution)

**Step 1: Validate**
Run: `terraform -chdir=terraform validate`

**Step 2: Plan**
Run: `terraform -chdir=terraform plan`

**Step 3: Apply**
Run: `terraform -chdir=terraform apply -auto-approve`

**Step 4: Verify Deployment**
Follow `docs/plans/2026-03-14-otel-gcp-design.md#Detailed Verification Plan`.

**Step 5: Commit**
```bash
git commit --allow-empty -m "infra: deploy complete"
```
