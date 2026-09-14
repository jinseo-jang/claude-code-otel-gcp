# Cloud Workstations Claude Code Unified WIF Integration Testing Guide
## Zero-`gcloud` Vertex AI Model Invocations & Cloud Run OTel Telemetry

> **Language**: **English** | [한국어 (Korean)](workstation-claude-code-test-guide.ko.md)

This guide provides comprehensive, step-by-step instructions for configuring and verifying Claude Code on Google Cloud Workstations using corporate Okta credentials and Workload Identity Federation (WIF). With this unified model, a single Okta SSO session authorizes both **Vertex AI Claude model invocations** and **Cloud Run OpenTelemetry telemetry forwarding** without issuing individual GCP IAM user accounts or requiring `gcloud auth login`.

---

## 1. Environment Variables & Parameters

All procedures in this guide use generalized environment variables. Export these variables in your workstation terminal before running commands.

### 1-1. Configuration Template

```bash
# === Required Environment Variables (Customize for your environment) ===
export PROJECT_ID="<YOUR_GCP_PROJECT_ID>"               # GCP Project ID (e.g., duper-project-1)
export PROJECT_NUMBER="<YOUR_GCP_PROJECT_NUMBER>"       # GCP Project Number (e.g., 743441901636)
export REGION="<YOUR_WORKSTATION_REGION>"               # Workstations region (e.g., asia-northeast3)
export WORKSTATION_CLUSTER="<YOUR_CLUSTER_NAME>"        # Workstations cluster name
export WORKSTATION_CONFIG="<YOUR_CONFIG_NAME>"          # Workstations config name
export WORKSTATION_NAME="<YOUR_WORKSTATION_NAME>"        # Workstation instance name
export COLLECTOR_URL="<YOUR_CLOUD_RUN_COLLECTOR_URL>"   # Cloud Run Collector URL (e.g., https://claude-code-otel-collector-xxx-uc.a.run.app)
export CLOUD_ML_REGION="global"                          # Target Vertex AI region for Claude models (global)
export ANTHROPIC_MODEL="claude-opus-4-8"                 # Target Vertex AI Claude model (e.g., claude-opus-4-8, claude-sonnet-4-6)
export OKTA_ISSUER_URI="<YOUR_OKTA_ISSUER_URI>"         # Okta OIDC Issuer URI (e.g., https://example.okta.com/oauth2/default)
export OKTA_CLIENT_ID="<YOUR_OKTA_CLIENT_ID>"           # Okta Native App Client ID
export OKTA_GROUP="claude-code-users"                   # Authorized Okta group name
export RELAY_SA_NAME="claude-code-otel-invoker"         # Relay Service Account name
```

### 1-2. Verified Reference Environment

The following concrete parameters were used during live end-to-end ground-truth verification on Google Cloud Workstations:

| Parameter | Reference Value | Description |
|---|---|---|
| **GCP Project** | `duper-project-1` | Project Number: `743441901636` |
| **Workstations Region** | `asia-northeast3` | Location: `asia-northeast3-b` |
| **Cluster** | `vibe-jinseo-workstation-cluster` | Managed Workstation Cluster |
| **Config** | `vibe-jinseo-workstation` | Machine: `e2-highmem-8`, Base: `code-oss:latest` |
| **Instance** | `agy-plugin-cc-test` | State: `RUNNING`, Egress IP: `34.22.90.60` |
| **Cloud ML Region / Model** | `global` / `claude-opus-4-8` | Vertex AI Anthropic Claude Global Endpoint |
| **Cloud Run Collector URL** | `https://claude-code-otel-collector-f7p5gpdmfa-uc.a.run.app` | Private IAM-protected endpoint |
| **WIF Pool / Provider** | `claude-code-pool` / `okta-oidc-provider` | Workload Identity Federation |
| **Relay Service Account** | `claude-code-otel-invoker@duper-project-1.iam.gserviceaccount.com` | Roles: `run.invoker`, `workloadIdentityUser`, `aiplatform.user` |
| **Okta Issuer URI** | `https://integrator-4025180.okta.com/oauth2/default` | Custom Authorization Server |
| **Okta Authorized Group** | `claude-code-users` | Verified User: `jinseo.jang@gmail.com` |
| **Okta Client ID** | `0oa17jpfd4fZxEdHE698` | Native App (Device flow allowed) |

---

## 2. Workstation Access & Environment Verification

### 2-1. Check & Start Instance
If your workstation instance is stopped, start it:

```bash
gcloud workstations start "$WORKSTATION_NAME" \
  --cluster="$WORKSTATION_CLUSTER" \
  --config="$WORKSTATION_CONFIG" \
  --region="$REGION" \
  --project="$PROJECT_ID"
```

### 2-2. Connect to the Workstation
Connect using either method:

- **Method 1: Web IDE (Code-OSS)**
  - Open [Cloud Workstations in Google Cloud Console](https://console.cloud.google.com/workstations/workstations).
  - Click **Launch** on your workstation row to open the web IDE.
  - Open a terminal via `Terminal` > `New Terminal`.

- **Method 2: gcloud SSH CLI**
  ```bash
  gcloud workstations ssh "$WORKSTATION_NAME" \
    --cluster="$WORKSTATION_CLUSTER" \
    --config="$WORKSTATION_CONFIG" \
    --region="$REGION" \
    --project="$PROJECT_ID"
  ```

### 2-3. Verify Required Tools
Ensure standard CLI utilities are installed:

```bash
for cmd in curl jq python3 git; do
  command -v $cmd >/dev/null && echo "[$cmd] Installed" || echo "[$cmd] Missing (install required)"
done
```

> [!TIP]
> When executing remote commands via non-interactive SSH (e.g. `gcloud workstations ssh --command="..."`), the non-login shell may not include user binaries (`~/.local/bin/claude`). Always wrap commands with `bash -lc "..."` to load the complete profile and PATH.

---

## 3. Clone Repository & Prepare Workspace

Clone or update the repository on the workstation:

```bash
cd ~
git clone https://github.com/jinseo-jang/claude-code-otel-gcp.git
cd claude-code-otel-gcp
```

*(If already cloned, run `git pull` to fetch the latest updates).*

---

## 4. Okta Device Authentication (`login_okta_device.sh`)

> [!IMPORTANT]
> **Essential Okta App Setting (Enable Refresh Token Grant Type)**:  
> When creating or configuring the Native Application in the Okta Admin Console, the **`Refresh Token`** grant type **must be checked**.  
> If this option is omitted, Okta will issue a 1-hour access token without error, but will silently skip issuing a refresh token. As a result, once the access token expires after 60 minutes, background auto-refresh cannot occur and the CLI will prompt for browser authentication repeatedly.  
> - **Navigation**: Okta Admin Console > **Applications** > **Applications** > [Your App] > **General** tab > **General Settings** (`Edit`) > **Grant type** > Check **`Refresh Token`** > **Save**.

Authenticate with Okta to obtain and cache your signed JWT access token and refresh token:

```bash
export OKTA_CLIENT_ID="<YOUR_OKTA_CLIENT_ID>"
./idp-federation/scripts/login_okta_device.sh
```

1. Open the activation URL displayed in the terminal (e.g. `https://<YOUR_OKTA_DOMAIN>/activate?user_code=XXXXXXXX`) in your browser.
2. Enter the user code and sign in with your corporate account belonging to `claude-code-users`.
3. Upon browser confirmation, the script saves:
   - Access token: `~/.corporate_idp/token` (file mode `0600`)
   - Refresh token: `~/.corporate_idp/refresh_token` (file mode `0600`)

---

## 5. Deploy WIF ADC Configuration (Zero-`gcloud` Model Execution)

Claude Code relies on Google Cloud Application Default Credentials (ADC) to interact with Vertex AI. Deploy a WIF `external_account` configuration file so that Claude Code transparently exchanges the cached Okta token via GCP STS without any human `gcloud auth login`:

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
> - Ensure permissions are set to `0600` (read/write only by owner).
> - `service_account_impersonation_url` must target `:generateAccessToken` (OAuth2 access token for Google Cloud APIs).
> - `credential_source.file` points to `${HOME}/.corporate_idp/token`.

---

## 6. Configure Claude Code Settings (`~/.claude/settings.json`)

### 6-1. Install the Header Helper Script
Copy the production header helper script to `~/.claude/`:

```bash
mkdir -p ~/.claude
cp idp-federation/scripts/generate_otel_headers.sh ~/.claude/generate_otel_headers.sh
chmod 755 ~/.claude/generate_otel_headers.sh
```

### 6-2. Test Header Helper Script Locally
```bash
~/.claude/generate_otel_headers.sh | python3 -m json.tool
```
Confirm that valid JSON (`{"Authorization": "Bearer eyJ..."}`) is returned with exit code 0.

### 6-3. Configure `~/.claude/settings.json`
Configure model execution and telemetry settings in `~/.claude/settings.json`:

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

## 7. Pre-flight 9-Stage Diagnostic Pipeline (`test_token_pipeline.sh`)

Before launching Claude Code, run the diagnostic suite to verify all 9 stages across the Okta, WIF, Vertex AI, and Cloud Run pipelines:

```bash
./idp-federation/scripts/test_token_pipeline.sh
```

### Expected Output
All 9 stages must return `[PASS]`:

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

## 8. Run Claude Code & Verify Ground-Truth Telemetry

### 8-1. Run Claude Code CLI (Zero-`gcloud`)
Start Claude Code without running `gcloud auth`:

```bash
claude -p "Explain briefly what GCP Cloud Run is in one sentence."
```

Or start an interactive session:
```bash
claude
```
- Example query: `"Write a Python function to parse JSON with error handling."`
- Exit with `/exit`.

### 8-2. Verify GCP Ground-Truth Telemetry

Run the following checks from a terminal with project read access:

#### 1. Cloud Audit Logs: Verify WIF Impersonation on Vertex AI
```bash
gcloud logging read \
  'logName="projects/'${PROJECT_ID}'/logs/cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName="aiplatform.googleapis.com"' \
  --project="${PROJECT_ID}" --limit=1 --format=json \
  | jq '{principal: .[0].protoPayload.authenticationInfo.principalEmail, delegation: .[0].protoPayload.authenticationInfo.serviceAccountDelegationInfo[0].principalSubject, permission: .[0].protoPayload.authorizationInfo[0].permission, granted: .[0].protoPayload.authorizationInfo[0].granted}'
```
- Expected output:
  - `principal`: `claude-code-otel-invoker@duper-project-1.iam.gserviceaccount.com`
  - `delegation`: `principal://iam.googleapis.com/.../claude-code-pool/subject/<USER_EMAIL>`
  - `permission`: `aiplatform.endpoints.predict`
  - `granted`: `true`

#### 2. Cloud Run Ingress: Verify HTTP 200 Telemetry Delivery
```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="claude-code-otel-collector" AND logName="projects/'${PROJECT_ID}'/logs/run.googleapis.com%2Frequests"' \
  --project="${PROJECT_ID}" --limit=5 \
  --format="table(timestamp,httpRequest.status,httpRequest.requestUrl,httpRequest.userAgent)"
```
- Expected output:
  - `STATUS`: `200`
  - `USER_AGENT`: `OTel-OTLP-Exporter-JavaScript/*`

#### 3. Cloud Logging: Verify Structured Event Attribution
```bash
gcloud logging read \
  'logName="projects/'${PROJECT_ID}'/logs/opentelemetry-collector"' \
  --project="${PROJECT_ID}" --limit=3 \
  --format="table(timestamp,labels.\"event.name\",labels.\"user.id\",labels.\"session.id\")"
```

#### 4. Cloud Monitoring: Verify Prometheus Time Series Metrics
```bash
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/timeSeries?filter=metric.type%20%3D%20%22prometheus.googleapis.com%2Fclaude_code_session_count_total%2Fcounter%22&interval.startTime=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)&interval.endTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  | jq '{series_count: (.timeSeries | length), sessions: [.timeSeries[]? | .metric.labels.session_id]}'
```

---

## 9. Troubleshooting Reference

### 9-1. Okta Refresh Token Grant Type Configuration
If browser login is prompted repeatedly after 1 hour instead of background auto-refreshing, or if Step 6 of `test_token_pipeline.sh` reports:
```text
{"error":"unauthorized_client","error_description":"The client is not authorized to use the provided grant type. Configured grant types: [authorization_code, urn:ietf:params:oauth:grant-type:device_code]."}
```

**Resolution in Okta Admin Console**:
1. Log in to the Okta Admin Console as a Super Admin or Application Admin.
2. Navigate to **Applications** > **Applications**.
3. Select your Claude Code Native Application (e.g. `Claude Code App`, Client ID: `0oa17jpfd4fZxEdHE698`).
4. In the **General** tab, scroll to **General Settings** and click **Edit**.
5. Under **Grant type**, check the box for **`Refresh Token`**.
6. (Optional/Recommended) Under **Refresh Token**, configure **Rotate token after every use**.
7. Click **Save**.
8. Navigate to **Security** > **API** > **Authorization Servers** > **`default`**.
9. Under **Access Policies**, edit the active rule (e.g. `Allow Device Flow`).
10. Under **AND Grant type is**, ensure **`Refresh Token`** is checked.
11. Click **Save Rule**.
12. Re-run `./idp-federation/scripts/test_token_pipeline.sh` on the workstation to verify Step 6 returns `[PASS]`.

### 9-2. Common Diagnostics Matrix

| Symptom | Cause | Resolution |
|---|---|---|
| Repeated browser login prompted after 1 hour | Okta App lacks 'Refresh Token' grant type; refresh_token omitted | In Okta Admin Console (Applications > [App] > General > Grant type), check 'Refresh Token' and save. Re-authenticate once to store refresh_token. |
| Claude Code fails with `Permission 'aiplatform.endpoints.predict' denied` | Relay SA lacks Vertex AI IAM role | In `idp-federation/terraform/iam.tf`, ensure `roles/aiplatform.user` is bound to `claude-code-otel-invoker` and applied via `terraform apply`. |
| Claude Code reports `Missing or invalid ADC` | ADC file missing or invalid schema | Inspect `~/.config/gcloud/application_default_credentials.json`. Verify `type: external_account` and `service_account_impersonation_url` points to `:generateAccessToken`. Set `chmod 600`. |
| Cloud Run returns `403 Forbidden` on `/v1/metrics` | Relay SA lacks Cloud Run Invoker role | Ensure `roles/run.invoker` is granted to `claude-code-otel-invoker` on `claude-code-otel-collector`. |
| `generate_otel_headers.sh` emits no output | Expected silent-exit on failure | Run `./idp-federation/scripts/test_token_pipeline.sh` to identify which step failed. |
| STS Hop 1 reports `attribute_condition` failure | `groups` claim missing from Access Token | In Okta Custom Authorization Server (`/oauth2/default`), verify `groups` claim is mapped to **`Access Token`** (not ID Token) with regex `.*`. |
| STS Hop 1 reports `Unable to verify signature` | Opaque token issued | Verify the Issuer URI in `terraform.tfvars` and ADC is `https://<DOMAIN>/oauth2/default`, NOT the root Org server. |

---

## 10. Related Documentation

- [Okta IdP Federation Unified Reference Architecture (English)](../idp-federation/README.md)
- [Okta IdP 연동 통합 참조 아키텍처 (한국어)](../idp-federation/README.ko.md)
- [IdP Federation Architectural Design Specification](../docs/plans/2026-09-14-idp-federated-auth-design.md)
- [Live Ground-Truth Verification Evidence](../.agents/tests/2026-09-14-verification-evidence.md)
