# Troubleshooting: Claude Code OTel → GCP

## Issue 1: Telemetry Not Being Sent (Root Cause Found 2026-03-14)

**Symptom**: Claude Code runs normally but no telemetry data appears in Cloud Logging or Cloud Monitoring. No requests reach the Cloud Run Collector.

**Root Cause**: `generate_otel_headers.sh` outputs plain text instead of JSON.

Claude Code internally calls `JSON.parse()` on the `otelHeadersHelper` script output. If the output is not valid JSON, parsing fails silently and **all telemetry export is disabled**.

**Wrong** (plain text HTTP header format):
```bash
echo "Authorization: Bearer $TOKEN"
```

**Correct** (JSON object):
```bash
echo "{\"Authorization\": \"Bearer $TOKEN\"}"
```

**Diagnosis**:
```bash
# Check if the script outputs valid JSON
~/.claude/generate_otel_headers.sh | python3 -c "import sys,json; json.load(sys.stdin); print('OK')"

# Check Cloud Run request logs for any Claude Code traffic
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="claude-code-otel-collector" AND httpRequest.requestUrl:"/v1/"' \
  --project=<PROJECT_ID> --limit=10 \
  --format="table(timestamp,httpRequest.status,httpRequest.requestUrl,httpRequest.userAgent)"

# If no requests with "OTel-OTLP-Exporter-JavaScript" user agent → headers script is broken
```

**Fix**: Update the script to output JSON, then restart Claude Code.

---

## Issue 2: Cold Start Data Loss

**Symptom**: Telemetry arrives intermittently. Cloud Run startup probe failures in logs:
```
Default STARTUP TCP probe failed 1 time consecutively for container "otelcol-google-1" on port 4318.
The instance was not started.
```

**Root Cause**: Cloud Run `min-instances=0` (default). Container scales to zero, cold start takes too long, startup probe fails, and incoming telemetry data is lost.

**Fix**: Set `min-instances=1` and enable CPU boost:
```bash
gcloud run services update claude-code-otel-collector \
  --region=us-central1 \
  --min-instances=1 \
  --cpu-boost
```

Or in Terraform (`cloud_run.tf`):
```hcl
annotations = {
  "autoscaling.knative.dev/minScale"     = "1"
  "run.googleapis.com/startup-cpu-boost" = "true"
}
```

---

## Issue 3: Protocol Mismatch

**Symptom**: `415 Unsupported Media Type` in Cloud Run request logs.

**Root Cause**: `OTEL_EXPORTER_OTLP_PROTOCOL` set to `grpc` but Collector only listens on HTTP port 4318.

**Fix**: Set protocol to `http/protobuf`:
```json
{
  "env": {
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf"
  }
}
```

Claude Code's OTLP SDK uses HTTP. Do not use `grpc`.

---

## Issue 4: Authentication Errors (403)

**Symptom**: `403 Forbidden` in Cloud Run request logs.

**Possible Causes**:
1. Identity token expired or invalid
2. User/SA lacks `roles/run.invoker` on the Cloud Run service
3. `--audiences` flag in `gcloud auth print-identity-token` causes token rejection

**Fix**:
```bash
# Verify token works
TOKEN=$(gcloud auth print-identity-token)
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  -X POST "https://<collector-url>/v1/metrics"
# Should return 200

# If 403, grant run.invoker
gcloud run services add-iam-policy-binding claude-code-otel-collector \
  --region=us-central1 \
  --member="user:<your-email>" \
  --role="roles/run.invoker"
```

> **Note**: Do NOT use `--audiences` flag with `gcloud auth print-identity-token`.
> It can cause token rejection depending on Cloud Run configuration.

---

## Issue 5: Metrics Export Error (Dropping Data)

**Symptom**: Collector logs show:
```
Exporting failed. Dropping data.
error: "The start time must be before the end time for the non-gauge metric"
```

**Root Cause**: Cumulative counter metrics sent with `start_time == end_time`. This happens when the same metric value is re-sent without time progression.

**Fix**: This is typically a transient issue. If persistent, check that `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` is set to `delta`:
```json
{
  "env": {
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "delta"
  }
}
```

---

## Useful Diagnostic Commands

```bash
# Check if Claude Code is sending telemetry (look for OTel-OTLP-Exporter-JavaScript user agent)
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="claude-code-otel-collector" AND httpRequest.requestUrl:"/v1/"' \
  --project=<PROJECT_ID> --limit=20 \
  --format="table(timestamp,httpRequest.status,httpRequest.requestUrl,httpRequest.userAgent)"

# Check for export errors in Collector
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="claude-code-otel-collector" AND severity>=ERROR' \
  --project=<PROJECT_ID> --limit=20 \
  --format="value(timestamp,textPayload)"

# Check Cloud Logging for OTel data
gcloud logging read \
  'logName="projects/<PROJECT_ID>/logs/opentelemetry-collector"' \
  --project=<PROJECT_ID> --limit=5 --format=json

# Send a manual test log
TOKEN=$(gcloud auth print-identity-token)
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "https://<collector-url>/v1/logs" \
  -d '{
    "resourceLogs": [{
      "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "manual-test"}}]},
      "scopeLogs": [{"logRecords": [{"timeUnixNano": "'$(date +%s)000000000'", "body": {"stringValue": "test"}, "severityText": "INFO"}]}]
    }]
  }'
```
