# Claude Code Setup Guide: OpenTelemetry on GCP

This guide outlines the steps to configure Claude Code on your GCP VM to send OpenTelemetry data to the Cloud Run Collector.

## 1. Directory Setup
Ensure the configuration directory exists:
```bash
mkdir -p ~/.claude
```

## 2. Dynamic Headers Script
Create a script to dynamically generate the authentication token utilizing your existing GCP credentials (ADC/VM Service Account).

Create file: `~/.claude/generate_otel_headers.sh`
```bash
#!/bin/bash
# Try gcloud first (works if user is logged in)
TOKEN=$(gcloud auth print-identity-token --audiences="https://<collector-cloud-run-url>" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  # Try metadata server (works if using VM Service Account)
  TOKEN=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=https://<collector-cloud-run-url>" 2>/dev/null)
fi

if [ -n "$TOKEN" ]; then
    echo "{\"Authorization\": \"Bearer $TOKEN\"}"
else
    # Fallback or error
    echo "{}"
fi
```
Make the script executable:
```bash
chmod +x ~/.claude/generate_otel_headers.sh
```

## 3. Claude Code Settings
Configure Claude Code to use the dynamic headers script.

Update/Create file: `~/.claude/settings.json` (or `.claude/settings.json` in your project root)
```json
{
  "otelHeadersHelper": "~/.claude/generate_otel_headers.sh"
}
```

## 4. Environment Variables
Set the environment variables to enable telemetry and route it to the Cloud Run Collector.

Add these to your `~/.bashrc` (or run them in your terminal before starting Claude Code):

```bash
# Enable telemetry export
export CLAUDE_CODE_ENABLE_TELEMETRY=1

# Exporters
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp

# OTLP Endpoint (Cloud Run Collector)
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc # or http/json if configured
export OTEL_EXPORTER_OTLP_ENDPOINT=https://<collector-cloud-run-url>

# Full Data Collection
export OTEL_METRICS_INCLUDE_SESSION_ID=true
export OTEL_METRICS_INCLUDE_VERSION=true
export OTEL_METRICS_INCLUDE_ACCOUNT_UUID=true
export OTEL_LOG_USER_PROMPTS=1
export OTEL_LOG_TOOL_DETAILS=1

# Optional: Reduce export interval for faster verification
export OTEL_METRIC_EXPORT_INTERVAL=10000
export OTEL_LOGS_EXPORT_INTERVAL=5000
```

## 5. Verification
After deploying the collector (Phase 1), you can verify the setup by running:
```bash
claude --help
```
Then check the Cloud Run logs to see if requests were received.
