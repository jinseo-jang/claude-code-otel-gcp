# Cloud Workstations 환경 Claude Code WIF 통합 연동 테스트 가이드
## Zero-`gcloud` 기반 Vertex AI 모델 호출 및 Cloud Run OTel 텔레메트리 검증

> **Language**: [English](workstation-claude-code-test-guide.md) | **한국어**

Google Cloud Workstations 환경에서 개발자 개인의 GCP IAM 계정 발급이나 `gcloud auth login` 세션 없이, 사내 Okta 자격증명과 Workload Identity Federation(WIF)을 통해 **Vertex AI 기반 Claude 모델 호출**과 **Cloud Run OpenTelemetry 수집기 텔레메트리 전송**을 동시에 수행하고 검증하는 통합 가이드입니다.

---

## 1. 환경 변수 및 설정 파라미터

본 가이드의 모든 명령은 일반화된 환경 변수를 기준으로 작성되었습니다. 터미널에서 작업하기 전 사용자 환경에 맞는 값을 먼저 선언하십시오.

### 1-1. 환경 변수 설정 템플릿

```bash
# === 필수 환경 설정 변수 (사용자 환경에 맞게 수정) ===
export PROJECT_ID="<YOUR_GCP_PROJECT_ID>"               # GCP 프로젝트 ID (예: duper-project-1)
export PROJECT_NUMBER="<YOUR_GCP_PROJECT_NUMBER>"       # GCP 프로젝트 번호 (예: 743441901636)
export REGION="<YOUR_WORKSTATION_REGION>"               # Workstations 리전 (예: asia-northeast3)
export WORKSTATION_CLUSTER="<YOUR_CLUSTER_NAME>"        # Workstations 클러스터 이름
export WORKSTATION_CONFIG="<YOUR_CONFIG_NAME>"          # Workstations 구성 이름
export WORKSTATION_NAME="<YOUR_WORKSTATION_NAME>"        # Workstation 인스턴스 이름
export COLLECTOR_URL="<YOUR_CLOUD_RUN_COLLECTOR_URL>"   # Cloud Run 수집기 URL (예: https://claude-code-otel-collector-xxx-uc.a.run.app)
export CLOUD_ML_REGION="global"                          # Claude 모델이 호스팅된 Vertex AI 대상 리전 (글로벌: global)
export ANTHROPIC_MODEL="claude-opus-4-8"                 # Vertex AI Claude 대상 모델 (예: claude-opus-4-8, claude-sonnet-4-6)
export OKTA_ISSUER_URI="<YOUR_OKTA_ISSUER_URI>"         # Okta OIDC 발급자 URL (예: https://example.okta.com/oauth2/default)
export OKTA_CLIENT_ID="<YOUR_OKTA_CLIENT_ID>"           # Okta Native App 클라이언트 ID
export OKTA_GROUP="claude-code-users"                   # 인가 대상 Okta 그룹명
export RELAY_SA_NAME="claude-code-otel-invoker"         # WIF 연동 중계 서비스 계정 이름
```

### 1-2. 검증 완료 레퍼런스 환경 정보

실제 Google Cloud 환경에서 E2E 실측 검증을 완료한 레퍼런스 정보입니다:

| 구분 | 레퍼런스 값 예시 | 비고 |
|---|---|---|
| **GCP 프로젝트** | `duper-project-1` | 프로젝트 번호: `743441901636` |
| **Workstations 리전** | `asia-northeast3` | 세부 위치: `asia-northeast3-b` |
| **클러스터** | `vibe-jinseo-workstation-cluster` | 관리형 클러스터 |
| **구성(Config)** | `vibe-jinseo-workstation` | 머신: `e2-highmem-8`, 기본 이미지: `code-oss:latest` |
| **인스턴스** | `agy-plugin-cc-test` | 상태: `RUNNING`, 외부 발신 IP: `34.22.90.60` |
| **Cloud ML 리전 / 모델** | `global` / `claude-opus-4-8` | Vertex AI Anthropic Claude Global 엔드포인트 |
| **Cloud Run 수집기 URL** | `https://claude-code-otel-collector-f7p5gpdmfa-uc.a.run.app` | IAM 인가 필수 비공개 엔드포인트 |
| **WIF 풀 / 프로바이더** | `claude-code-pool` / `okta-oidc-provider` | OIDC 페더레이션 풀 |
| **중계 서비스 계정** | `claude-code-otel-invoker@duper-project-1.iam.gserviceaccount.com` | 보유 역할: `run.invoker`, `workloadIdentityUser`, `aiplatform.user` |
| **Okta Issuer URI** | `https://integrator-4025180.okta.com/oauth2/default` | 커스텀 권한 부여 서버 |
| **Okta 인가 그룹** | `claude-code-users` | 검증 사용자: `jinseo.jang@gmail.com` |
| **Okta Client ID** | `0oa17jpfd4fZxEdHE698` | Native App (디바이스 인증 허용) |

---

## 2. Workstation 접속 및 기본 환경 점검

### 2-1. 인스턴스 시작
인스턴스가 중지 상태라면 먼저 시작합니다:

```bash
gcloud workstations start "$WORKSTATION_NAME" \
  --cluster="$WORKSTATION_CLUSTER" \
  --config="$WORKSTATION_CONFIG" \
  --region="$REGION" \
  --project="$PROJECT_ID"
```

### 2-2. 인스턴스 접속
편한 방식으로 워크스테이션 터미널에 접속합니다:

- **방식 1: 웹 IDE (Code-OSS)**
  - [Google Cloud Console > Cloud Workstations > Workstations](https://console.cloud.google.com/workstations/workstations)로 이동합니다.
  - 해당 워크스테이션 행의 **시작(Launch)** 버튼을 클릭하여 웹 IDE를 엽니다.
  - 상단 메뉴에서 `Terminal` > `New Terminal`을 실행합니다.

- **방식 2: gcloud CLI SSH 접속**
  ```bash
  gcloud workstations ssh "$WORKSTATION_NAME" \
    --cluster="$WORKSTATION_CLUSTER" \
    --config="$WORKSTATION_CONFIG" \
    --region="$REGION" \
    --project="$PROJECT_ID"
  ```

### 2-3. 필수 도구 확인
```bash
for cmd in curl jq python3 git; do
  command -v $cmd >/dev/null && echo "[$cmd] 준비 완료" || echo "[$cmd] 누락 (설치 필요)"
done
```

> [!TIP]
> 비대화형 SSH(예: `gcloud workstations ssh --command="..."`) 환경에서는 기본 `PATH`에 `~/.local/bin`이 누락되어 `claude` CLI를 찾지 못할 수 있습니다. 항상 `bash -lc "claude ..."` 형태로 실행하여 전체 로그인 프로파일을 로드하십시오.

---

## 3. 리포지토리 및 스크립트 준비

Workstation 환경에서 본 프로젝트 리포지토리를 복제하거나 최신 커밋으로 업데이트합니다:

```bash
cd ~
git clone https://github.com/jinseo-jang/claude-code-otel-gcp.git
cd claude-code-otel-gcp
```

*(기존 폴더가 존재하면 `git pull`을 실행합니다).*

---

## 4. Okta 디바이스 인증 (`login_okta_device.sh`)

Okta 디바이스 인증 플로우를 통해 액세스 토큰 및 리프레시 토큰을 발급받아 캐시합니다:

```bash
export OKTA_CLIENT_ID="<YOUR_OKTA_CLIENT_ID>"
./idp-federation/scripts/login_okta_device.sh
```

1. 터미널에 출력되는 브라우저 활성화 URL(예: `https://<YOUR_OKTA_DOMAIN>/activate?user_code=XXXXXXXX`)을 엽니다.
2. 터미널의 8자리 코드를 입력하고 `claude-code-users` 그룹에 속한 사내 계정으로 로그인하여 승인합니다.
3. 승인 완료 시 스크립트가 로컬 디렉터리에 보안 권한(`0600`)으로 토큰을 저장합니다:
   - 액세스 토큰: `~/.corporate_idp/token`
   - 리프레시 토큰: `~/.corporate_idp/refresh_token`

---

## 5. WIF ADC 설정 파일 배포 (Zero-`gcloud` 모델 호출)

Claude Code는 Vertex AI 모델 호출 시 Google Cloud Application Default Credentials(ADC)를 기본 참조합니다. Workload Identity Federation 기반 `external_account` 설정 파일을 생성하여, 사람의 `gcloud auth login` 없이도 STS 토큰 교환을 통해 모델을 호출할 수 있도록 구성합니다:

```bash
mkdir -p ~/.config/gcloud

cat << EOF > ~/.config/gcloud/application_default_credentials.json
{
  "type": "external_account",
  "audience": "//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/claude-code-pool/providers/okta-oidc-provider",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "credential_source": {
    "file": "${HOME}/.corporate_idp/token"
  },
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${RELAY_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com:generateAccessToken"
}
EOF

chmod 600 ~/.config/gcloud/application_default_credentials.json
```

> [!IMPORTANT]
> - 파일 권한은 반드시 `chmod 600`(소유자 읽기/쓰기 전용)으로 설정합니다.
> - `service_account_impersonation_url`은 반드시 `:generateAccessToken`(Google API 호출용 OAuth2 액세스 토큰 발급)이어야 합니다.
> - `credential_source.file`은 `${HOME}/.corporate_idp/token`을 정확히 가리켜야 합니다.

---

## 6. Workstation Claude Code 설정 (`~/.claude/settings.json`)

### 6-1. OTel 헤더 생성 헬퍼 스크립트 배치
```bash
mkdir -p ~/.claude
cp idp-federation/scripts/generate_otel_headers.sh ~/.claude/generate_otel_headers.sh
chmod 755 ~/.claude/generate_otel_headers.sh
```

### 6-2. 스크립트 단독 동작 및 출력 검증
```bash
~/.claude/generate_otel_headers.sh | python3 -m json.tool
```
유효한 JSON 객체(`{"Authorization": "Bearer eyJ..."}`)가 종료 코드 0과 함께 출력되는지 확인합니다.

### 6-3. `~/.claude/settings.json` 환경 구성
모델 호출 환경 변수와 OTel 텔레메트리 전송 설정을 통합 구성합니다:

```bash
cat << EOF > ~/.claude/settings.json
{
  "otelHeadersHelper": "${HOME}/.claude/generate_otel_headers.sh",
  "env": {
    "CLAUDE_CODE_USE_VERTEX": "1",
    "CLOUD_ML_REGION": "${CLOUD_ML_REGION}",
    "ANTHROPIC_MODEL": "${ANTHROPIC_MODEL}",
    "ANTHROPIC_VERTEX_PROJECT_ID": "${PROJECT_ID}",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "${COLLECTOR_URL}",
    "OTEL_METRICS_INCLUDE_SESSION_ID": "true",
    "OTEL_METRICS_INCLUDE_VERSION": "true",
    "OTEL_METRICS_INCLUDE_ACCOUNT_UUID": "true",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_METRIC_EXPORT_INTERVAL": "60000",
    "CLAUDE_CODE_OTEL_HEADERS_HELPER_DEBOUNCE_MS": "1740000"
  }
}
EOF
```

---

## 7. 9단계 통합 사전 진단 (`test_token_pipeline.sh`)

Claude Code를 실행하기 전, 통합 진단 스크립트를 실행하여 Okta, WIF, Vertex AI, Cloud Run 전 구간을 사전 검증합니다:

```bash
./idp-federation/scripts/test_token_pipeline.sh
```

### 진단 단계 및 기대 결과
9단계 전수 항목이 `[PASS]`로 표시되어야 합니다:

```text
=====================================================================
  Okta -> GCP Workload Identity Federation Pipeline Diagnostics      
=====================================================================
[INFO] Project Number:          743441901636
[INFO] Project ID:              duper-project-1
[INFO] WIF Pool:                claude-code-pool
[INFO] WIF Provider:            okta-oidc-provider
[INFO] Invoker Service Account: claude-code-otel-invoker@duper-project-1.iam.gserviceaccount.com
[INFO] Collector URL:           https://claude-code-otel-collector-f7p5gpdmfa-uc.a.run.app
[INFO] STS Audience:            //iam.googleapis.com/projects/743441901636/locations/global/workloadIdentityPools/claude-code-pool/providers/okta-oidc-provider
[INFO] Okta Issuer:             https://integrator-4025180.okta.com/oauth2/default
[INFO] Target ML Region:        us-east5

--- Step 1: Locating and Decoding Corporate IdP JWT ---
[PASS] Found IdP token from: /home/user/.corporate_idp/token
[PASS] IdP token is mathematically valid and not expired.
[PASS] Issuer matches expected Okta authority.
[PASS] Target group 'claude-code-users' confirmed present in groups claim.

--- Step 2: Testing Hop 1 (GCP STS Token Exchange) ---
[PASS] Hop 1 Succeeded! Received GCP federated access token.

--- Step 3: Testing Hop 2 (Cloud IAM Credentials generateIdToken) ---
[PASS] Hop 2 Succeeded! Received Google ID Token.

--- Step 4: Verifying Cloud Run Collector Ingestion ---
[PASS] Cloud Run IAM authorization confirmed! Request reached container (Status: 200).

--- Step 5: Validating generate_otel_headers.sh Output Format ---
[PASS] generate_otel_headers.sh returned valid JSON with 'Authorization: Bearer <TOKEN>'.

--- Step 6: Verifying Refresh Token & Okta /v1/token Refresh Flow ---
[PASS] Refresh token file exists with secure permissions (600).
[PASS] Okta /v1/token refresh succeeded (HTTP 200)!

--- Step 7: Testing SA Access Token Generation (generateAccessToken for Vertex AI) ---
[PASS] Step 7 Succeeded! Received Service Account Access Token for Vertex AI.

--- Step 8: Verifying Vertex AI Claude Model Endpoint Reachability ---
[PASS] Vertex AI authorization confirmed! Successfully listed publisher models.

--- Step 9: Validating Workstation WIF ADC Configuration ---
[PASS] ADC configuration file permissions are secure (600).
[PASS] WIF ADC configuration schema is valid!

=====================================================================
  All 9 Pipeline Stages Diagnostic Verification Complete!             
=====================================================================
```

---

## 8. Claude Code 실행 및 GCP 실측 증적 확인

### 8-1. Claude Code CLI 실행 (Zero-`gcloud`)
`gcloud auth` 로그인 없이 터미널에서 Claude Code를 직접 실행합니다:

```bash
claude -p "GCP Cloud Run이 무엇인지 한 문장으로 간결하게 설명해 줘."
```

대화형 세션:
```bash
claude
```
- 예시 질문: `"JSON 파싱 예외 처리 파이썬 함수를 작성해 줘."`
- `/exit`로 세션을 종료합니다.

### 8-2. GCP 실측 증적 검증 (Ground-Truth Evidence)

GCP 프로젝트 조회 권한이 있는 관리자 터미널에서 아래 4가지 증적을 검증합니다:

#### 1. Cloud Audit Logs: Vertex AI WIF 위임 호출 실측
```bash
gcloud logging read \
  'logName="projects/'${PROJECT_ID}'/logs/cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName="aiplatform.googleapis.com"' \
  --project="${PROJECT_ID}" --limit=1 --format=json \
  | jq '{principal: .[0].protoPayload.authenticationInfo.principalEmail, delegation: .[0].protoPayload.authenticationInfo.serviceAccountDelegationInfo[0].principalSubject, permission: .[0].protoPayload.authorizationInfo[0].permission, granted: .[0].protoPayload.authorizationInfo[0].granted}'
```
- 기대 출력:
  - `principal`: `claude-code-otel-invoker@duper-project-1.iam.gserviceaccount.com`
  - `delegation`: `principal://iam.googleapis.com/.../claude-code-pool/subject/<사내이메일>`
  - `permission`: `aiplatform.endpoints.predict`
  - `granted`: `true`

#### 2. Cloud Run Ingress: 텔레메트리 HTTP 200 수신 실측
```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="claude-code-otel-collector" AND logName="projects/'${PROJECT_ID}'/logs/run.googleapis.com%2Frequests"' \
  --project="${PROJECT_ID}" --limit=5 \
  --format="table(timestamp,httpRequest.status,httpRequest.requestUrl,httpRequest.userAgent)"
```
- `STATUS`: `200`
- `USER_AGENT`: `OTel-OTLP-Exporter-JavaScript/*`

#### 3. Cloud Logging: 구조화 텔레메트리 이벤트 적재 실측
```bash
gcloud logging read \
  'logName="projects/'${PROJECT_ID}'/logs/opentelemetry-collector"' \
  --project="${PROJECT_ID}" --limit=3 \
  --format="table(timestamp,labels.\"event.name\",labels.\"user.id\",labels.\"session.id\")"
```

#### 4. Cloud Monitoring: Prometheus 시계열 메트릭 누적 실측
```bash
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/timeSeries?filter=metric.type%20%3D%20%22prometheus.googleapis.com%2Fclaude_code_session_count_total%2Fcounter%22&interval.startTime=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)&interval.endTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  | jq '{series_count: (.timeSeries | length), sessions: [.timeSeries[]? | .metric.labels.session_id]}'
```

---

## 9. 장애 유형별 점검 및 해결 가이드 (Troubleshooting)

### 9-1. Okta 리프레시 토큰 그랜트 타입 활성화 절차
만약 `test_token_pipeline.sh`의 Step 6 실행 중 다음 에러가 발생한다면:
```text
{"error":"unauthorized_client","error_description":"The client is not authorized to use the provided grant type. Configured grant types: [authorization_code, urn:ietf:params:oauth:grant-type:device_code]."}
```

**Okta Admin Console 설정 절차**:
1. Okta 관리자 콘솔(Admin Console)에 관리자 권한으로 로그인합니다.
2. **Applications** > **Applications**로 이동합니다.
3. 등록된 Claude Code 네이티브 앱(예: `Claude Code App`, Client ID: `0oa17jpfd4fZxEdHE698`)을 클릭합니다.
4. **General** 탭의 **General Settings** 섹션에서 **Edit**을 누릅니다.
5. **Grant type** 항목에서 **`Refresh Token`** 체크박스를 활성화합니다.
6. (권장) **Refresh Token** 섹션에서 **Rotate token after every use**를 선택합니다.
7. 하단 **Save**를 누릅니다.
8. **Security** > **API** > **Authorization Servers** > **`default`**로 이동합니다.
9. **Access Policies** 탭에서 해당 앱에 연결된 Rule(예: `Allow Device Flow`)의 **Edit**을 누릅니다.
10. **AND Grant type is**에서 **`Refresh Token`**이 체크되어 있는지 확인하고 저장합니다.
11. 워크스테이션에서 `./idp-federation/scripts/test_token_pipeline.sh`를 다시 실행하여 Step 6가 `[PASS]`가 되는지 확인합니다.

### 9-2. 주요 장애 유형별 조치표

| 증상 | 원인 분석 | 해결 조치 |
|---|---|---|
| Claude Code 실행 시 `Permission 'aiplatform.endpoints.predict' denied` 발생 | 중계 SA에 Vertex AI 역할 누락 | `idp-federation/terraform/iam.tf`에 `roles/aiplatform.user`가 선언되어 있는지 확인하고 `terraform apply`를 실행합니다. |
| Claude Code 실행 시 `Missing or invalid ADC` 오류 | ADC 파일 누락 또는 스키마 오류 | `~/.config/gcloud/application_default_credentials.json` 파일의 `type: external_account` 여부와 `generateAccessToken` 경로를 확인하고 `chmod 600`을 부여합니다. |
| Cloud Run `/v1/metrics` 호출 시 403 Forbidden | 중계 SA에 invoker 권한 누락 | 중계 SA(`claude-code-otel-invoker`)에 `roles/run.invoker` 권한이 부여되어 있는지 점검합니다. |
| `generate_otel_headers.sh` 실행 시 아무것도 출력되지 않음 | 오류 발생 시 침묵 종료(Silent-Exit) 정상 동작 | `./idp-federation/scripts/test_token_pipeline.sh`를 실행하여 실패한 단계와 세부 에러를 확인합니다. |
| STS Hop 1 호출 시 `attribute_condition` 평가 거부 | Access Token 내 `groups` 클레임 누락 | Okta Custom Authorization Server(`/oauth2/default`)에서 `groups` 클레임이 **Access Token**에 정규식 `.*`로 매핑되어 있는지 확인합니다. |
| STS Hop 1 호출 시 `Unable to verify signature` 오류 | 불투명 토큰 발급 | Issuer URI가 기본 Org 서버가 아니라 커스텀 서버(`https://<DOMAIN>/oauth2/default`)인지 점검합니다. |

---

## 10. 연관 문서

- [Okta IdP 연동 통합 참조 아키텍처 (한국어)](../idp-federation/README.ko.md)
- [Okta IdP Federation Unified Reference Architecture (English)](../idp-federation/README.md)
- [IdP 연동 아키텍처 설계 명세서](../docs/plans/2026-09-14-idp-federated-auth-design.md)
- [실측 검증 증적 기록서](../.agents/tests/2026-09-14-verification-evidence.md)
