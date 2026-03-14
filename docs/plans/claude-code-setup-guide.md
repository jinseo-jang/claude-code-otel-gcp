# Claude Code Setup Guide: OpenTelemetry on GCP

This guide outlines the steps to configure Claude Code to send OpenTelemetry data to the Cloud Run Collector.

## Prerequisites

- GCP project with the OTel Collector deployed on Cloud Run (see Terraform in this repo)
- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- Claude Code installed (`npm install -g @anthropic-ai/claude-code`)
- `roles/run.invoker` granted on the Collector Cloud Run service for your identity

## 1. Directory Setup

```bash
mkdir -p ~/.claude
```

## 2. Authentication Headers Script

Create `~/.claude/generate_otel_headers.sh`:

```bash
#!/bin/bash
set -e
TOKEN=$(gcloud auth print-identity-token 2>/dev/null)
if [ -n "$TOKEN" ]; then
  echo "{\"Authorization\": \"Bearer $TOKEN\"}"
fi
```

> **IMPORTANT**: The script MUST output a **JSON object** with string key-value pairs.
> Claude Code internally calls `JSON.parse()` on the script output. Plain text like
> `Authorization: Bearer <token>` will cause a parse error and **silently disable
> all telemetry export**.

Make it executable:

```bash
chmod +x ~/.claude/generate_otel_headers.sh
```

Verify it outputs valid JSON:

```bash
~/.claude/generate_otel_headers.sh | python3 -c "import sys,json; json.load(sys.stdin); print('OK')"
```

## 3. Claude Code Settings

Add the following to `~/.claude/settings.json`. Using the `env` block in settings.json
is preferred over `.bashrc` because it ensures the variables are always set regardless
of how Claude Code is launched (terminal, VS Code, etc.).

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://<collector-cloud-run-url>",
    "OTEL_METRICS_INCLUDE_SESSION_ID": "true",
    "OTEL_METRICS_INCLUDE_VERSION": "true",
    "OTEL_METRICS_INCLUDE_ACCOUNT_UUID": "true",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_METRIC_EXPORT_INTERVAL": "1000"
  },
  "otelHeadersHelper": "/absolute/path/to/.claude/generate_otel_headers.sh"
}
```

> **Notes**:
> - `OTEL_EXPORTER_OTLP_PROTOCOL` must be `http/protobuf`. Claude Code's OTLP SDK uses HTTP, not gRPC.
> - `otelHeadersHelper` must be an **absolute path** (not `~/.claude/...`).
> - `OTEL_METRIC_EXPORT_INTERVAL` is in milliseconds. `1000` = every 1 second (useful for verification; increase to `60000` for production).

## 4. Verification

### 4.1 Restart Claude Code

After updating settings, **restart Claude Code** for changes to take effect.

### 4.2 Check Collector Receives Data

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="claude-code-otel-collector" AND httpRequest.requestUrl:"/v1/"' \
  --project=<PROJECT_ID> --limit=10 \
  --format="table(timestamp,httpRequest.status,httpRequest.requestUrl,httpRequest.userAgent)"
```

Look for requests with User-Agent `OTel-OTLP-Exporter-JavaScript/*` and status `200`.

### 4.3 Check Cloud Logging

```bash
gcloud logging read \
  'logName="projects/<PROJECT_ID>/logs/opentelemetry-collector"' \
  --project=<PROJECT_ID> --limit=5 --format=json
```

Expected log entries: `claude_code.user_prompt`, `claude_code.api_request`, `claude_code.tool_result`.

### 4.4 Check Cloud Monitoring Metrics

In GCP Console > Cloud Monitoring > Metrics Explorer, search for:

| Metric Name | Description |
|---|---|
| `prometheus.googleapis.com/claude_code_cost_usage_USD_total/counter` | Cost (USD) |
| `prometheus.googleapis.com/claude_code_token_usage_tokens_total/counter` | Token usage |
| `prometheus.googleapis.com/claude_code_session_count_total/counter` | Session count |
| `prometheus.googleapis.com/claude_code_active_time_seconds_total/counter` | Active time |
| `prometheus.googleapis.com/claude_code_lines_of_code_count_total/counter` | Lines of code |
| `prometheus.googleapis.com/claude_code_code_edit_tool_decision_total/counter` | Code edit decisions |

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues and solutions.
