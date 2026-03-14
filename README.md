# Claude Code OpenTelemetry → GCP

Claude Code의 텔레메트리 데이터(메트릭, 로그)를 Google Cloud Platform으로 수집하는 구성입니다.

## Architecture

```
Claude Code CLI
    │
    │ OTLP/HTTP (protobuf)
    │ + IAM Identity Token
    ▼
Cloud Run (OTel Collector)
    │
    ├──→ Cloud Monitoring (GMP)  ← metrics
    └──→ Cloud Logging           ← logs
```

## Collected Data

### Metrics (Cloud Monitoring)

Metrics Explorer에서 `claude_code`로 검색:

| Metric | Description |
|---|---|
| `claude_code_cost_usage_USD_total` | 비용 (USD) |
| `claude_code_token_usage_tokens_total` | 토큰 사용량 |
| `claude_code_session_count_total` | 세션 수 |
| `claude_code_active_time_seconds_total` | 활성 시간 |
| `claude_code_lines_of_code_count_total` | 코드 라인 수 |
| `claude_code_code_edit_tool_decision_total` | 코드 편집 결정 |

### Logs (Cloud Logging)

`logName="projects/<PROJECT>/logs/opentelemetry-collector"` 로 검색:

| Event | Key Fields |
|---|---|
| `claude_code.user_prompt` | 프롬프트 내용, 길이, 세션 ID |
| `claude_code.api_request` | 모델, 토큰, 비용, 응답시간 |
| `claude_code.tool_result` | 도구명, 성공 여부, 소요시간 |

## Quick Start

### 1. Infrastructure (Terraform)

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Claude Code Setup

`~/.claude/generate_otel_headers.sh` 생성:

```bash
#!/bin/bash
set -e
TOKEN=$(gcloud auth print-identity-token 2>/dev/null)
if [ -n "$TOKEN" ]; then
  echo "{\"Authorization\": \"Bearer $TOKEN\"}"
fi
```

```bash
chmod +x ~/.claude/generate_otel_headers.sh
```

> **IMPORTANT**: 반드시 JSON 형식으로 출력해야 합니다. 평문 출력 시 텔레메트리가 전혀 전송되지 않습니다.

`~/.claude/settings.json`에 추가:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://<COLLECTOR_URL>",
    "OTEL_METRICS_INCLUDE_SESSION_ID": "true",
    "OTEL_METRICS_INCLUDE_VERSION": "true",
    "OTEL_METRICS_INCLUDE_ACCOUNT_UUID": "true",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_METRIC_EXPORT_INTERVAL": "1000"
  },
  "otelHeadersHelper": "/home/<USER>/.claude/generate_otel_headers.sh"
}
```

### 3. IAM (Claude Code 사용자)

```bash
gcloud run services add-iam-policy-binding claude-code-otel-collector \
  --region=us-central1 \
  --member="user:<YOUR_EMAIL>" \
  --role="roles/run.invoker"
```

### 4. Restart & Verify

Claude Code 재시작 후:

```bash
# Collector에 요청이 도착하는지 확인
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="claude-code-otel-collector" AND httpRequest.requestUrl:"/v1/"' \
  --project=<PROJECT_ID> --limit=10 \
  --format="table(timestamp,httpRequest.status,httpRequest.userAgent)"
```

`OTel-OTLP-Exporter-JavaScript` User-Agent와 HTTP 200이 보이면 성공입니다.

## Key Gotchas

| Issue | Solution |
|---|---|
| `otelHeadersHelper` 출력이 JSON이 아님 | `echo "{\"Authorization\": \"Bearer $TOKEN\"}"` 형식 사용 |
| `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` | `http/protobuf`로 변경 (Claude Code는 HTTP 사용) |
| Cold start로 데이터 유실 | Cloud Run `min-instances=1` 설정 |
| 403 인증 에러 | `roles/run.invoker` 부여 확인 |

자세한 트러블슈팅은 [docs/plans/troubleshooting.md](docs/plans/troubleshooting.md)를 참조하세요.

## Docs

- [Setup Guide](docs/plans/claude-code-setup-guide.md) — Claude Code 설정 상세 가이드
- [Design](docs/plans/2026-03-14-otel-gcp-design.md) — 아키텍처 설계 문서
- [Implementation Plan](docs/plans/2026-03-14-otel-gcp-implementation-plan.md) — Terraform 구현 계획
- [Troubleshooting](docs/plans/troubleshooting.md) — 문제 해결 가이드
