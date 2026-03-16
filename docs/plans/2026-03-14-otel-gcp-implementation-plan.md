# OpenTelemetry Integration with GCP Implementation Plan

**Goal:** Deploy an OpenTelemetry Collector on Cloud Run to collect metrics and logs from Claude Code and route them to Google Cloud Managed Service for Prometheus (GMP) and Cloud Logging.

**Architecture:** Centralized OTel Collector on Cloud Run as a gateway. Secured by IAM. Claude Code authenticates using dynamic ID tokens via `otelHeadersHelper`.

**Tech Stack:** Terraform, OpenTelemetry, GCP (Cloud Run, Secret Manager, GMP, Cloud Logging).

---

### Task 1: Terraform Bootstrap & Configuration

**Files:** `terraform/provider.tf`, `terraform/variables.tf`, `terraform/locals.tf`

- Google provider with `~> 5.0`
- Variables: `project_id` (required, no default), `region` (default: `us-central1`), `service_name` (default: `claude-code-otel-collector`)
- Locals: `collector_image` pinned to `otelcol-google:0.144.0`

### Task 2: Secret Manager & Collector Config

**Files:** `terraform/secret_manager.tf`, `terraform/otel-config.yaml`

- Secret Manager secret for collector config with auto replication
- Collector config:
  - Receiver: OTLP HTTP on port 4318 (no gRPC — Claude Code uses HTTP only)
  - Processors: `batch`, `memory_limiter`, `resourcedetection(gcp)`, `transform/collision`
  - Exporters: `googlemanagedprometheus` (metrics), `googlecloud` (logs), `debug`
  - `transform/collision`: Renames GCP-reserved attributes to avoid conflicts

### Task 3: IAM & Service Account

**Files:** `terraform/iam.tf`

- Service account for Cloud Run collector
- Roles: `monitoring.metricWriter`, `logging.logWriter`, `secretmanager.secretAccessor`
- `run.invoker` granted to default compute SA (customize per environment)

### Task 4: Cloud Run Deployment

**Files:** `terraform/cloud_run.tf`, `terraform/outputs.tf`

- Cloud Run service with:
  - Port 4318 (OTLP HTTP)
  - `min-instances: 1` (prevents cold start data loss)
  - `cpu-boost: true` (faster startup)
  - Resource limits: 1 CPU, 512Mi memory
  - Config hash annotation for automatic redeployment on config changes
- Output: `collector_url`

### Task 5: Apply & Verify

1. `terraform -chdir=terraform init`
2. `terraform -chdir=terraform plan`
3. `terraform -chdir=terraform apply -auto-approve`
4. Verify following [claude-code-setup-guide.md](claude-code-setup-guide.md)
