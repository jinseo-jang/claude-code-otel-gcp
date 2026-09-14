#!/usr/bin/env bash
# =============================================================================
# generate_otel_headers.sh
#
# Obtains corporate IdP (Okta) JWT, performs 2-hop token exchange via GCP STS
# and Cloud IAM Credentials API, and outputs JSON Authorization header for
# Claude Code OTel exporter.
#
# CRITICAL REQUIREMENT:
# Must exit silently with zero stdout on any failure. Non-JSON stdout permanently
# causes Claude Code's internal JSON.parse() to throw, silently dropping telemetry.
# =============================================================================

set -euo pipefail

# Trap all errors and unhandled signals to exit silently without emitting text
trap 'exit 0' ERR EXIT

# -----------------------------------------------------------------------------
# Configuration (Can be overridden via environment variables or local config)
# -----------------------------------------------------------------------------
TOKEN_DIR="${HOME:-/tmp}/.corporate_idp"
TOKEN_FILE="${TOKEN_DIR}/token"
REFRESH_TOKEN_FILE="${TOKEN_DIR}/refresh_token"
LOCK_FILE="${TOKEN_DIR}/.refresh.lock"

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

ISSUER_URI="${ISSUER_URI:-https://<YOUR_OKTA_DOMAIN>.okta.com/oauth2/default}"
OKTA_CLIENT_ID="${OKTA_CLIENT_ID:-<YOUR_OKTA_CLIENT_ID>}"
TOKEN_ENDPOINT="${ISSUER_URI}/v1/token"
EXPIRY_BUFFER_SECONDS="${EXPIRY_BUFFER_SECONDS:-300}"
REFRESH_TOKEN_FILE="${TOKEN_DIR}/refresh_token"
LOCK_FILE="${TOKEN_DIR}/.refresh.lock"

# Exit silently if required placeholders have not been replaced
if [[ "${PROJECT_NUMBER}" == *"<"* ]] || [[ "${PROJECT_ID}" == *"<"* ]] || [[ "${COLLECTOR_URL}" == *"<"* ]] || [[ "${ISSUER_URI}" == *"<"* ]] || [[ "${OKTA_CLIENT_ID}" == *"<"* ]]; then
  exit 0
fi

# Helper: Robust JSON field extractor (jq -> python3 -> sed fallback)
extract_json_field() {
  local json="$1"
  local field="$2"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r ".${field} // empty" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    echo "$json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('${field}', ''))" 2>/dev/null || true
  else
    echo "$json" | grep -o "\"${field}\": *\"[^\"]*\"" | sed "s/\"${field}\": *\"//;s/\"//" 2>/dev/null || true
  fi
}

# Helper: Fast token expiration check (in-memory base64 decode + exp claim comparison)
is_token_expiring() {
  local token="$1"
  local buffer="${2:-300}"
  local payload
  payload=$(echo "$token" | cut -d'.' -f2 2>/dev/null || true)
  [ -z "$payload" ] && return 0

  local padded
  case $(( ${#payload} % 4 )) in
    2) padded="${payload}==" ;;
    3) padded="${payload}=" ;;
    *) padded="${payload}" ;;
  esac

  local exp="0"
  local decoded
  decoded=$(echo "$padded" | tr -- '-_' '+/' | base64 -d 2>/dev/null || true)
  if [ -n "$decoded" ]; then
    if command -v jq >/dev/null 2>&1; then
      exp=$(echo "$decoded" | jq -r '.exp // 0' 2>/dev/null || echo "0")
    else
      exp=$(echo "$decoded" | grep -o '"exp": *[0-9]*' | awk -F':' '{print $2}' | tr -d ' ' 2>/dev/null || echo "0")
    fi
  fi

  if ! [[ "$exp" =~ ^[0-9]+$ ]] || [ "$exp" -eq 0 ]; then
    return 0
  fi

  local now
  now=$(date +%s)
  if [ "$((now + buffer))" -ge "$exp" ]; then
    return 0 # Expired or expiring within buffer
  else
    return 1 # Valid
  fi
}

# 1. Retrieve Corporate IdP JWT from environment or local credential store
IDP_TOKEN="${CORPORATE_IDP_TOKEN:-}"
if [ -z "$IDP_TOKEN" ] && [ -f "${TOKEN_FILE}" ]; then
  IDP_TOKEN=$(head -n 1 "${TOKEN_FILE}" 2>/dev/null || true)
fi

# Sanitize token: remove all newlines, carriage returns, and whitespace
IDP_TOKEN=$(echo "${IDP_TOKEN}" | tr -d '\r\n[:space:]')

# Check if token is expired or nearing expiration within buffer (now + 300 >= exp)
if [ -z "$IDP_TOKEN" ] || is_token_expiring "${IDP_TOKEN}" "${EXPIRY_BUFFER_SECONDS}"; then
  if [ -f "${REFRESH_TOKEN_FILE}" ]; then
    mkdir -p "${TOKEN_DIR}" 2>/dev/null || true
    touch "${LOCK_FILE}" 2>/dev/null || true
    chmod 600 "${LOCK_FILE}" 2>/dev/null || true

    if exec 200>"${LOCK_FILE}"; then
      if flock -x -w 10 200 2>/dev/null; then
        # Double-checked locking: re-read TOKEN_FILE from disk
        DISK_TOKEN=""
        if [ -f "${TOKEN_FILE}" ]; then
          DISK_TOKEN=$(head -n 1 "${TOKEN_FILE}" 2>/dev/null | tr -d '\r\n[:space:]' || true)
        fi

        if [ -n "$DISK_TOKEN" ] && ! is_token_expiring "$DISK_TOKEN" "${EXPIRY_BUFFER_SECONDS}"; then
          IDP_TOKEN="$DISK_TOKEN"
        else
          # Still expired or missing, execute refresh call to Okta /v1/token
          REFRESH_TOKEN=$(head -n 1 "${REFRESH_TOKEN_FILE}" 2>/dev/null | tr -d '\r\n[:space:]' || true)
          if [ -n "$REFRESH_TOKEN" ]; then
            REFRESH_RESP=$(curl -s -f -X POST "${TOKEN_ENDPOINT}" \
              -H "Content-Type: application/x-www-form-urlencoded" \
              -d "client_id=${OKTA_CLIENT_ID}&grant_type=refresh_token&refresh_token=${REFRESH_TOKEN}" 2>/dev/null || true)

            if [ -n "$REFRESH_RESP" ]; then
              NEW_ACCESS_TOKEN=$(extract_json_field "$REFRESH_RESP" "access_token")
              NEW_REFRESH_TOKEN=$(extract_json_field "$REFRESH_RESP" "refresh_token")

              if [ -n "$NEW_ACCESS_TOKEN" ]; then
                (umask 077 && printf '%s\n' "$NEW_ACCESS_TOKEN" > "${TOKEN_FILE}.tmp.$$" && mv -f "${TOKEN_FILE}.tmp.$$" "${TOKEN_FILE}")
                chmod 600 "${TOKEN_FILE}" 2>/dev/null || true
                IDP_TOKEN="$NEW_ACCESS_TOKEN"
              fi

              # Handle refresh token rotation
              if [ -n "$NEW_REFRESH_TOKEN" ]; then
                (umask 077 && printf '%s\n' "$NEW_REFRESH_TOKEN" > "${REFRESH_TOKEN_FILE}.tmp.$$" && mv -f "${REFRESH_TOKEN_FILE}.tmp.$$" "${REFRESH_TOKEN_FILE}")
                chmod 600 "${REFRESH_TOKEN_FILE}" 2>/dev/null || true
              fi
            fi
          fi
        fi
        flock -u 200 2>/dev/null || true
      fi
      exec 200>&- 2>/dev/null || true
    fi
  fi
fi

# Exit silently if token is absent
if [ -z "$IDP_TOKEN" ]; then
  exit 0
fi

STS_AUDIENCE="//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

# 2. Hop 1: GCP STS Token Exchange
# Exchange Okta JWT for a federated GCP OAuth2 access token
STS_RESPONSE=$(curl -s -f -X POST "https://sts.googleapis.com/v1/token" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "{
    \"grantType\": \"urn:ietf:params:oauth:grant-type:token-exchange\",
    \"audience\": \"${STS_AUDIENCE}\",
    \"scope\": \"https://www.googleapis.com/auth/cloud-platform\",
    \"requestedTokenType\": \"urn:ietf:params:oauth:token-type:access_token\",
    \"subjectTokenType\": \"urn:ietf:params:oauth:token-type:jwt\",
    \"subjectToken\": \"${IDP_TOKEN}\"
  }" 2>/dev/null || true)

if [ -z "$STS_RESPONSE" ]; then
  exit 0
fi

FEDERATED_ACCESS_TOKEN=$(extract_json_field "$STS_RESPONSE" "access_token")

if [ -z "$FEDERATED_ACCESS_TOKEN" ]; then
  exit 0
fi

# 3. Hop 2: Generate Google ID Token
# Impersonate intermediate invoker SA to generate an OIDC ID token targeting Cloud Run
ID_TOKEN_RESPONSE=$(curl -s -f -X POST "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SERVICE_ACCOUNT_EMAIL}:generateIdToken" \
  -H "Authorization: Bearer ${FEDERATED_ACCESS_TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "{
    \"audience\": \"${COLLECTOR_URL}\",
    \"includeEmail\": true
  }" 2>/dev/null || true)

if [ -z "$ID_TOKEN_RESPONSE" ]; then
  exit 0
fi

GOOGLE_ID_TOKEN=$(extract_json_field "$ID_TOKEN_RESPONSE" "token")

if [ -z "$GOOGLE_ID_TOKEN" ]; then
  exit 0
fi

# Remove trap so clean exit 0 succeeds with stdout intact
trap - ERR EXIT

# 4. Output valid JSON header object
printf '{"Authorization": "Bearer %s"}\n' "${GOOGLE_ID_TOKEN}"
