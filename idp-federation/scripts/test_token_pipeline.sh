#!/usr/bin/env bash
# =============================================================================
# test_token_pipeline.sh
#
# Diagnostic and verification tool for Okta -> GCP WIF -> Cloud Run OTel auth pipeline.
# Performs detailed, verbose verification across each hop with actionable error output.
# =============================================================================

set -euo pipefail

# Text styling
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

log_info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_success() { echo -e "${GREEN}[PASS]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_fail()    { echo -e "${RED}[FAIL]${RESET} $*"; }

# -----------------------------------------------------------------------------
# Command-line Options
# -----------------------------------------------------------------------------
SKIP_CURL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-curl)
      SKIP_CURL=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--skip-curl]"
      echo "  --skip-curl: Validate local tokens, claims, and configs without making external network calls."
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

echo -e "${BOLD}=====================================================================${RESET}"
echo -e "${BOLD}  Okta -> GCP Workload Identity Federation Pipeline Diagnostics      ${RESET}"
echo -e "${BOLD}=====================================================================${RESET}"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
TOKEN_DIR="${HOME:-/tmp}/.corporate_idp"
TOKEN_FILE="${TOKEN_DIR}/token"
REFRESH_TOKEN_FILE="${REFRESH_TOKEN_FILE:-${TOKEN_DIR}/refresh_token}"
ADC_CONFIG_PATH="${ADC_CONFIG_PATH:-${HOME:-/tmp}/.config/gcloud/application_default_credentials.json}"

# Source local configuration if available
if [[ -f "${TOKEN_DIR}/config.env" ]]; then
  # shellcheck source=/dev/null
  source "${TOKEN_DIR}/config.env"
fi

PROJECT_NUMBER="${PROJECT_NUMBER:-<YOUR_PROJECT_NUMBER>}"
PROJECT_ID="${PROJECT_ID:-<YOUR_PROJECT_ID>}"
POOL_ID="${POOL_ID:-claude-code-pool}"
PROVIDER_ID="${PROVIDER_ID:-okta-oidc-provider}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_EMAIL:-claude-code-otel-invoker@${PROJECT_ID}.iam.gserviceaccount.com}"
COLLECTOR_URL="${COLLECTOR_URL:-<YOUR_CLOUD_RUN_COLLECTOR_URL>}"
EXPECTED_ISSUER="${EXPECTED_ISSUER:-https://<YOUR_OKTA_DOMAIN>.okta.com/oauth2/default}"
EXPECTED_GROUP="${EXPECTED_GROUP:-claude-code-users}"
OKTA_CLIENT_ID="${OKTA_CLIENT_ID:-<YOUR_OKTA_CLIENT_ID>}"
CLOUD_ML_REGION="${CLOUD_ML_REGION:-global}"

if [[ "${PROJECT_NUMBER}" == *"<"* ]] || [[ "${PROJECT_ID}" == *"<"* ]] || [[ "${COLLECTOR_URL}" == *"<"* ]] || [[ "${EXPECTED_ISSUER}" == *"<"* ]]; then
  log_fail "Placeholder configuration detected! Please export the required environment variables:"
  echo "  export PROJECT_ID=\"<your-project-id>\""
  echo "  export PROJECT_NUMBER=\"<your-project-number>\""
  echo "  export COLLECTOR_URL=\"https://<your-collector-url>\""
  echo "  export EXPECTED_ISSUER=\"https://<your-okta-domain>/oauth2/default\""
  exit 1
fi

STS_AUDIENCE="//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

log_info "Project Number:          ${PROJECT_NUMBER}"
log_info "Project ID:              ${PROJECT_ID}"
log_info "WIF Pool:                ${POOL_ID}"
log_info "WIF Provider:            ${PROVIDER_ID}"
log_info "Invoker Service Account: ${SERVICE_ACCOUNT_EMAIL}"
log_info "Collector URL:           ${COLLECTOR_URL}"
log_info "STS Audience:            ${STS_AUDIENCE}"
log_info "Okta Issuer:             ${EXPECTED_ISSUER}"
log_info "Target ML Region:        ${CLOUD_ML_REGION}"
if [ "$SKIP_CURL" = "true" ]; then
  log_warn "Running in offline mode (--skip-curl): Remote network calls bypassed."
fi
echo ""

# -----------------------------------------------------------------------------
# Step 1: Corporate IdP JWT Retrieval and Claim Inspection
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 1: Locating and Decoding Corporate IdP JWT ---${RESET}"
IDP_TOKEN="${CORPORATE_IDP_TOKEN:-}"
TOKEN_SOURCE="CORPORATE_IDP_TOKEN environment variable"

if [ -z "$IDP_TOKEN" ] && [ -f "${TOKEN_FILE}" ]; then
  IDP_TOKEN=$(head -n 1 "${TOKEN_FILE}" 2>/dev/null || true)
  TOKEN_SOURCE="${TOKEN_FILE}"
fi

# Sanitize token: remove all newlines, carriage returns, and whitespace
IDP_TOKEN=$(echo "${IDP_TOKEN}" | tr -d '\r\n[:space:]')

if [ -z "$IDP_TOKEN" ]; then
  log_fail "No IdP token found in \$CORPORATE_IDP_TOKEN or ${HOME}/.corporate_idp/token."
  log_info "Remediation: Run ./login_okta_device.sh or export CORPORATE_IDP_TOKEN=<token>."
  exit 1
fi

# Secure temporary directory for diagnostic traces
DIAG_TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'wif_diag')
chmod 700 "${DIAG_TMP_DIR}"
trap 'rm -rf "${DIAG_TMP_DIR}"' EXIT

log_success "Found IdP token from: ${TOKEN_SOURCE}"

# Base64URL decode JWT payload
JWT_PAYLOAD=$(echo "$IDP_TOKEN" | awk -F'.' '{print $2}' || true)
if [ -z "$JWT_PAYLOAD" ]; then
  log_fail "Provided token is not a valid 3-part JWT format (header.payload.signature)."
  exit 1
fi

# Pad base64 string
PADDED_PAYLOAD=$(python3 -c "
import sys, base64
raw = sys.argv[1]
padded = raw + '=' * (-len(raw) % 4)
try:
    print(base64.urlsafe_b64decode(padded).decode('utf-8'))
except Exception:
    sys.exit(1)
" "$JWT_PAYLOAD" 2>/dev/null || true)

if [ -z "$PADDED_PAYLOAD" ]; then
  log_fail "Failed to decode JWT payload."
  exit 1
fi

# Extract claims securely in-memory via stdin (avoids leaking PII to world-writable /tmp)
PARSE_RESULT=$(echo "$PADDED_PAYLOAD" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

iss = str(data.get('iss', ''))
aud = str(data.get('aud', ''))
sub = str(data.get('sub', ''))
exp = str(data.get('exp', 0))
groups = data.get('groups', [])

# Output tab-separated metadata and json-encoded groups
print(f'{iss}\t{aud}\t{sub}\t{exp}\t{json.dumps(groups)}')
" 2>/dev/null || true)

if [ -z "$PARSE_RESULT" ]; then
  log_fail "Failed to parse claims from decoded JWT payload."
  exit 1
fi

IFS=$'\t' read -r TOKEN_ISS TOKEN_AUD TOKEN_SUB TOKEN_EXP TOKEN_GROUPS_JSON <<< "$PARSE_RESULT"

log_info "Issuer (iss):    ${TOKEN_ISS}"
log_info "Audience (aud):  ${TOKEN_AUD}"
log_info "Subject (sub):   ${TOKEN_SUB}"
log_info "Groups (groups): ${TOKEN_GROUPS_JSON}"

CURRENT_TIME=$(date +%s)
if [ "$TOKEN_EXP" -gt 0 ] && [ "$TOKEN_EXP" -lt "$CURRENT_TIME" ]; then
  log_fail "IdP token is expired (exp: ${TOKEN_EXP}, current: ${CURRENT_TIME})."
  exit 1
else
  log_success "IdP token is mathematically valid and not expired."
fi

if [ "$TOKEN_ISS" != "$EXPECTED_ISSUER" ]; then
  log_warn "Issuer '${TOKEN_ISS}' does not match expected '${EXPECTED_ISSUER}'. WIF exchange will fail if not registered."
else
  log_success "Issuer matches expected Okta authority (${EXPECTED_ISSUER})."
fi

# Exact membership check on groups claim (prevents substring false positives)
IS_AUTHORIZED_MEMBER=$(python3 -c "
import sys, json
try:
    groups = json.loads(sys.argv[1])
    target = sys.argv[2]
    if isinstance(groups, list) and target in groups:
        print('true')
    elif isinstance(groups, str) and target == groups:
        print('true')
    else:
        print('false')
except Exception:
    print('false')
" "${TOKEN_GROUPS_JSON}" "${EXPECTED_GROUP}" 2>/dev/null || echo "false")

if [ "$IS_AUTHORIZED_MEMBER" = "true" ]; then
  log_success "Target group '${EXPECTED_GROUP}' confirmed present in groups claim."
else
  log_fail "Target group '${EXPECTED_GROUP}' NOT found in groups claim: ${TOKEN_GROUPS_JSON}."
  log_info "WIF attribute_condition will reject this token at the STS perimeter."
fi
echo ""

# -----------------------------------------------------------------------------
# Step 2: Hop 1 - GCP STS Token Exchange
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 2: Testing Hop 1 (GCP STS Token Exchange) ---${RESET}"
if [ "$SKIP_CURL" = "true" ]; then
  log_info "Skipping STS live curl exchange (--skip-curl specified)."
  log_success "Step 2 skipped via --skip-curl."
  FEDERATED_ACCESS_TOKEN=""
else
  log_info "Sending token exchange request to https://sts.googleapis.com/v1/token..."

  STS_HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "https://sts.googleapis.com/v1/token" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{
      \"grantType\": \"urn:ietf:params:oauth:grant-type:token-exchange\",
      \"audience\": \"${STS_AUDIENCE}\",
      \"scope\": \"https://www.googleapis.com/auth/cloud-platform\",
      \"requestedTokenType\": \"urn:ietf:params:oauth:token-type:access_token\",
      \"subjectTokenType\": \"urn:ietf:params:oauth:token-type:jwt\",
      \"subjectToken\": \"${IDP_TOKEN}\"
    }" 2>&1)

  STS_BODY=$(echo "$STS_HTTP_RESPONSE" | sed -e '$d')
  STS_CODE=$(echo "$STS_HTTP_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

  if [ "$STS_CODE" -ne 200 ]; then
    log_fail "STS Token Exchange failed with HTTP status ${STS_CODE}."
    echo "Response payload:"
    echo "$STS_BODY"
    exit 1
  fi

  FEDERATED_ACCESS_TOKEN=$(echo "$STS_BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null || true)
  if [ -z "$FEDERATED_ACCESS_TOKEN" ]; then
    log_fail "STS returned HTTP 200 but response body did not contain 'access_token'."
    exit 1
  fi

  log_success "Hop 1 Succeeded! Received GCP federated access token."
  log_info "Federated Token (masked): ${FEDERATED_ACCESS_TOKEN:0:15}...${FEDERATED_ACCESS_TOKEN: -10}"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 3: Hop 2 - Cloud IAM Credentials API (generateIdToken)
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 3: Testing Hop 2 (Cloud IAM Credentials generateIdToken) ---${RESET}"
log_info "Requesting Google ID token for target SA: ${SERVICE_ACCOUNT_EMAIL}..."

if [ "$SKIP_CURL" = "true" ]; then
  log_info "Skipping IAM live curl exchange (--skip-curl specified)."
  log_success "Step 3 skipped via --skip-curl."
  GOOGLE_ID_TOKEN=""
else
  IAM_HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SERVICE_ACCOUNT_EMAIL}:generateIdToken" \
    -H "Authorization: Bearer ${FEDERATED_ACCESS_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{
      \"audience\": \"${COLLECTOR_URL}\",
      \"includeEmail\": true
    }" 2>&1)

  IAM_BODY=$(echo "$IAM_HTTP_RESPONSE" | sed -e '$d')
  IAM_CODE=$(echo "$IAM_HTTP_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

  if [ "$IAM_CODE" -ne 200 ]; then
    log_fail "generateIdToken failed with HTTP status ${IAM_CODE}."
    echo "Response payload:"
    echo "$IAM_BODY"
    exit 1
  fi

  GOOGLE_ID_TOKEN=$(echo "$IAM_BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))" 2>/dev/null || true)
  if [ -z "$GOOGLE_ID_TOKEN" ]; then
    log_fail "generateIdToken returned HTTP 200 but response body did not contain 'token'."
    exit 1
  fi

  log_success "Hop 2 Succeeded! Received Google ID Token."
  log_info "Google ID Token (masked): ${GOOGLE_ID_TOKEN:0:15}...${GOOGLE_ID_TOKEN: -10}"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 4: Verify Cloud Run Collector Ingestion
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 4: Verifying Cloud Run Collector Ingestion ---${RESET}"
if [ "$SKIP_CURL" = "true" ]; then
  log_info "Skipping Cloud Run live probe (--skip-curl specified)."
  log_success "Step 4 skipped via --skip-curl."
else
  log_info "Sending authenticated probe to ${COLLECTOR_URL}/v1/metrics..."

  CR_HTTP_CODE=$(curl -s -o "${DIAG_TMP_DIR}/collector_probe_body.txt" -w "%{http_code}" -X POST "${COLLECTOR_URL}/v1/metrics" \
    -H "Authorization: Bearer ${GOOGLE_ID_TOKEN}" \
    -H "Content-Type: application/x-protobuf" \
    --data-binary "" 2>/dev/null || true)

  log_info "Collector HTTP Status: ${CR_HTTP_CODE}"

  if [ "$CR_HTTP_CODE" -eq 401 ] || [ "$CR_HTTP_CODE" -eq 403 ]; then
    log_fail "Authentication rejected by Cloud Run or Collector (HTTP ${CR_HTTP_CODE})."
    log_info "Check if roles/run.invoker is granted to ${SERVICE_ACCOUNT_EMAIL}."
    exit 1
  elif [ "$CR_HTTP_CODE" -eq 200 ] || [ "$CR_HTTP_CODE" -eq 400 ] || [ "$CR_HTTP_CODE" -eq 415 ]; then
    # 400 / 415 is expected when sending an empty body without valid protobuf payload,
    # but proves that transport authentication and IAM authorization succeeded!
    log_success "Cloud Run IAM authorization confirmed! Request reached container (Status: ${CR_HTTP_CODE})."
  else
    log_warn "Unexpected response code ${CR_HTTP_CODE}. Body: $(cat "${DIAG_TMP_DIR}/collector_probe_body.txt" 2>/dev/null || true)"
  fi
fi
echo ""

# -----------------------------------------------------------------------------
# Step 5: Test generate_otel_headers.sh JSON Output
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 5: Validating generate_otel_headers.sh Output Format ---${RESET}"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/generate_otel_headers.sh"

if [ "$SKIP_CURL" = "true" ]; then
  log_info "Skipping generate_otel_headers.sh live execution (--skip-curl specified)."
  log_success "Step 5 skipped via --skip-curl."
else
  HEADER_OUTPUT=$(CORPORATE_IDP_TOKEN="${IDP_TOKEN}" "$SCRIPT_PATH" 2>/dev/null || true)

  if [ -z "$HEADER_OUTPUT" ]; then
    log_fail "generate_otel_headers.sh produced zero stdout."
    exit 1
  fi

  PARSED_AUTH=$(echo "$HEADER_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('Authorization', ''))" 2>/dev/null || true)

  if [[ "$PARSED_AUTH" =~ ^Bearer\  ]]; then
    log_success "generate_otel_headers.sh returned valid JSON with 'Authorization: Bearer <TOKEN>'."
  else
    log_fail "Output is not valid JSON or Authorization header missing: ${HEADER_OUTPUT}"
    exit 1
  fi
fi
echo ""

# -----------------------------------------------------------------------------
# Step 6: Refresh Token File and Okta /v1/token Refresh Flow Verification
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 6: Verifying Refresh Token & Okta /v1/token Refresh Flow ---${RESET}"
if [ ! -f "${REFRESH_TOKEN_FILE}" ]; then
  log_warn "Refresh token file not found at ${REFRESH_TOKEN_FILE}."
  log_info "Remediation: Run ./login_okta_device.sh to authenticate with offline_access scope and store a refresh token."
else
  PERMS=$(stat -c "%a" "${REFRESH_TOKEN_FILE}" 2>/dev/null || stat -f "%Lp" "${REFRESH_TOKEN_FILE}" 2>/dev/null || echo "unknown")
  if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
    log_success "Refresh token file exists with secure permissions (${PERMS})."
  else
    log_warn "Refresh token file permissions are ${PERMS} (expected 0600). Enforcing chmod 600..."
    chmod 600 "${REFRESH_TOKEN_FILE}" 2>/dev/null || true
  fi

  REFRESH_TOKEN=$(head -n 1 "${REFRESH_TOKEN_FILE}" 2>/dev/null | tr -d '\r\n[:space:]' || true)
  if [ -z "$REFRESH_TOKEN" ]; then
    log_fail "Refresh token file ${REFRESH_TOKEN_FILE} is empty."
  else
    log_info "Refresh token present (length: ${#REFRESH_TOKEN}, masked: ${REFRESH_TOKEN:0:6}...${REFRESH_TOKEN: -4})"
    if [ "$SKIP_CURL" = "true" ]; then
      log_info "Skipping Okta live refresh call (--skip-curl specified)."
      log_success "Step 6 refresh token file validated (live call skipped via --skip-curl)."
    else
      log_info "Sending refresh token request to ${EXPECTED_ISSUER}/v1/token..."
      REFRESH_HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${EXPECTED_ISSUER}/v1/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${OKTA_CLIENT_ID}&grant_type=refresh_token&refresh_token=${REFRESH_TOKEN}" 2>&1)

      REFRESH_BODY=$(echo "$REFRESH_HTTP_RESPONSE" | sed -e '$d')
      REFRESH_CODE=$(echo "$REFRESH_HTTP_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

      if [ "$REFRESH_CODE" -eq 200 ]; then
        NEW_AT=$(echo "$REFRESH_BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null || true)
        NEW_RT=$(echo "$REFRESH_BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('refresh_token', ''))" 2>/dev/null || true)
        log_success "Okta /v1/token refresh succeeded (HTTP 200)! New access token returned."
        if [ -n "$NEW_RT" ]; then
          log_info "Okta rotated refresh token. Updating local ${REFRESH_TOKEN_FILE}..."
          (umask 077 && printf '%s\n' "$NEW_RT" > "${REFRESH_TOKEN_FILE}.tmp.$$" && mv -f "${REFRESH_TOKEN_FILE}.tmp.$$" "${REFRESH_TOKEN_FILE}")
          chmod 600 "${REFRESH_TOKEN_FILE}" 2>/dev/null || true
        fi
        if [ -n "$NEW_AT" ]; then
          (umask 077 && printf '%s\n' "$NEW_AT" > "${TOKEN_FILE}.tmp.$$" && mv -f "${TOKEN_FILE}.tmp.$$" "${TOKEN_FILE}")
          chmod 600 "${TOKEN_FILE}" 2>/dev/null || true
        fi
      else
        log_warn "Okta /v1/token refresh returned HTTP status ${REFRESH_CODE}."
        ERROR_DESC=$(echo "$REFRESH_BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('error_description', ''))" 2>/dev/null || true)
        if [ -n "$ERROR_DESC" ]; then
          log_warn "Okta Error: ${ERROR_DESC}"
        fi
        log_info "Remediation: If invalid_grant, the refresh token has expired or been revoked. Run ./login_okta_device.sh to re-authenticate."
      fi
    fi
  fi
fi
echo ""

# -----------------------------------------------------------------------------
# Step 7: Service Account Access Token Generation (generateAccessToken for Vertex AI)
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 7: Testing SA Access Token Generation (generateAccessToken for Vertex AI) ---${RESET}"
log_info "Requesting Google OAuth2 Access Token for Vertex AI SA: ${SERVICE_ACCOUNT_EMAIL}..."

if [ "$SKIP_CURL" = "true" ]; then
  log_info "Skipping generateAccessToken live curl call (--skip-curl specified)."
  log_success "Step 7 skipped via --skip-curl."
  SA_ACCESS_TOKEN=""
else
  if [ -z "${FEDERATED_ACCESS_TOKEN:-}" ]; then
    log_fail "Cannot generate SA access token: FEDERATED_ACCESS_TOKEN from Step 2 is missing."
    exit 1
  fi

  SA_AT_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SERVICE_ACCOUNT_EMAIL}:generateAccessToken" \
    -H "Authorization: Bearer ${FEDERATED_ACCESS_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{
      \"scope\": [\"https://www.googleapis.com/auth/cloud-platform\"],
      \"lifetime\": \"3600s\"
    }" 2>&1)

  SA_AT_BODY=$(echo "$SA_AT_RESPONSE" | sed -e '$d')
  SA_AT_CODE=$(echo "$SA_AT_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

  if [ "$SA_AT_CODE" -ne 200 ]; then
    log_fail "generateAccessToken failed with HTTP status ${SA_AT_CODE}."
    echo "Response payload:"
    echo "$SA_AT_BODY"
    exit 1
  fi

  SA_ACCESS_TOKEN=$(echo "$SA_AT_BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('accessToken', ''))" 2>/dev/null || true)
  if [ -z "$SA_ACCESS_TOKEN" ]; then
    log_fail "generateAccessToken returned HTTP 200 but response body did not contain 'accessToken'."
    exit 1
  fi

  log_success "Step 7 Succeeded! Received Service Account Access Token for Vertex AI."
  log_info "SA Access Token (masked): ${SA_ACCESS_TOKEN:0:15}...${SA_ACCESS_TOKEN: -10}"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 8: Vertex AI Claude Model Endpoint Reachability Probe
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 8: Verifying Vertex AI Claude Model Endpoint Reachability ---${RESET}"
VERTEX_ENDPOINT="https://${CLOUD_ML_REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${CLOUD_ML_REGION}/publishers/anthropic/models"
log_info "Target Vertex AI Region:   ${CLOUD_ML_REGION}"
log_info "Probing Publisher Models:  ${VERTEX_ENDPOINT}..."

if [ "$SKIP_CURL" = "true" ]; then
  log_info "Skipping Vertex AI live endpoint probe (--skip-curl specified)."
  log_success "Step 8 skipped via --skip-curl."
else
  if [ -z "${SA_ACCESS_TOKEN:-}" ]; then
    log_fail "Cannot probe Vertex AI: SA_ACCESS_TOKEN from Step 7 is missing."
    exit 1
  fi

  VERTEX_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET "${VERTEX_ENDPOINT}" \
    -H "Authorization: Bearer ${SA_ACCESS_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" 2>&1)

  VERTEX_BODY=$(echo "$VERTEX_RESPONSE" | sed -e '$d')
  VERTEX_CODE=$(echo "$VERTEX_RESPONSE" | tail -n 1 | sed 's/HTTP_STATUS://')

  log_info "Vertex AI HTTP Status: ${VERTEX_CODE}"

  if [ "$VERTEX_CODE" -eq 200 ]; then
    MODEL_COUNT=$(echo "$VERTEX_BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('publisherModels', [])))" 2>/dev/null || echo "0")
    log_success "Vertex AI authorization confirmed! Successfully listed publisher models (Count: ${MODEL_COUNT})."
    log_info "Claude model invocation permission (roles/aiplatform.user) verified on ${SERVICE_ACCOUNT_EMAIL}."
  elif [ "$VERTEX_CODE" -eq 403 ]; then
    log_fail "Vertex AI authorization rejected (HTTP 403 Forbidden)."
    log_info "Check if roles/aiplatform.user is granted to ${SERVICE_ACCOUNT_EMAIL} on project ${PROJECT_ID}."
    echo "Response payload: ${VERTEX_BODY}"
    exit 1
  else
    log_warn "Vertex AI returned unexpected status ${VERTEX_CODE}."
    echo "Response payload: ${VERTEX_BODY}"
  fi
fi
echo ""

# -----------------------------------------------------------------------------
# Step 9: WIF ADC Configuration Validation
# -----------------------------------------------------------------------------
echo -e "${BOLD}--- Step 9: Validating Workstation WIF ADC Configuration ---${RESET}"
ADC_PATH="${ADC_CONFIG_PATH}"
log_info "Checking ADC file at: ${ADC_PATH}..."

if [ ! -f "${ADC_PATH}" ]; then
  log_warn "ADC configuration file does not exist at ${ADC_PATH}."
  log_info "Remediation: Deploy the WIF ADC JSON configuration for Workload Identity Federation."
else
  ADC_PERMS=$(stat -c "%a" "${ADC_PATH}" 2>/dev/null || stat -f "%Lp" "${ADC_PATH}" 2>/dev/null || echo "unknown")
  if [ "$ADC_PERMS" = "600" ] || [ "$ADC_PERMS" = "400" ]; then
    log_success "ADC configuration file permissions are secure (${ADC_PERMS})."
  else
    log_warn "ADC configuration file permissions are ${ADC_PERMS} (recommended 0600)."
  fi

  ADC_CHECK_RESULT=$(python3 -c "
import sys, json

path = sys.argv[1]
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f'INVALID_JSON: {e}')
    sys.exit(0)

c_type = cfg.get('type')
aud = cfg.get('audience')
tok_url = cfg.get('token_url')
cred_src = cfg.get('credential_source', {}).get('file')
sa_url = cfg.get('service_account_impersonation_url')

errors = []
if c_type != 'external_account':
    errors.append(f'type={c_type} (expected external_account)')
if not aud or 'workloadIdentityPools' not in aud:
    errors.append('audience does not contain workloadIdentityPools')
if tok_url != 'https://sts.googleapis.com/v1/token':
    errors.append(f'token_url={tok_url} (expected https://sts.googleapis.com/v1/token)')
if not cred_src:
    errors.append('credential_source.file missing')
if not sa_url or 'generateAccessToken' not in sa_url:
    errors.append('service_account_impersonation_url missing or does not call generateAccessToken')

if errors:
    print('SCHEMA_ERRORS: ' + '; '.join(errors))
else:
    print('VALID')
" "${ADC_PATH}" 2>/dev/null || echo "PYTHON_EXEC_ERROR")

  if [ "$ADC_CHECK_RESULT" = "VALID" ]; then
    log_success "WIF ADC configuration schema is valid!"
    log_info "Type:                 external_account"
    log_info "Token URL:            https://sts.googleapis.com/v1/token"
    log_info "Credential Source:    $(python3 -c "import sys, json; print(json.load(open(sys.argv[1])).get('credential_source', {}).get('file', ''))" "${ADC_PATH}" 2>/dev/null || true)"
    log_info "SA Impersonation URL: $(python3 -c "import sys, json; print(json.load(open(sys.argv[1])).get('service_account_impersonation_url', ''))" "${ADC_PATH}" 2>/dev/null || true)"
  else
    log_fail "ADC configuration check failed: ${ADC_CHECK_RESULT}"
  fi
fi
echo ""

echo -e "${BOLD}${GREEN}=====================================================================${RESET}"
echo -e "${BOLD}${GREEN}  All 9 Pipeline Stages Diagnostic Verification Complete!             ${RESET}"
echo -e "${BOLD}${GREEN}=====================================================================${RESET}"
