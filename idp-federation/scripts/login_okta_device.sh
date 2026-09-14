#!/usr/bin/env bash
# =============================================================================
# login_okta_device.sh
#
# Helper script to authenticate developer workstations with Okta and cache
# the resulting JWT at ~/.corporate_idp/token (permissions 0600).
#
# Supports:
#  1. Interactive token paste / CLI argument input
#  2. RFC 8628 OAuth 2.0 Device Authorization Grant (when OKTA_CLIENT_ID is supplied)
# =============================================================================

set -euo pipefail

TOKEN_DIR="${HOME:-/tmp}/.corporate_idp"
TOKEN_FILE="${TOKEN_DIR}/token"
REFRESH_TOKEN_FILE="${TOKEN_DIR}/refresh_token"

# Source local configuration if available
if [[ -f "${TOKEN_DIR}/config.env" ]]; then
  # shellcheck source=/dev/null
  source "${TOKEN_DIR}/config.env"
fi

ISSUER_URI="${ISSUER_URI:-<YOUR_OKTA_ISSUER_URI>}"
if [[ "${ISSUER_URI}" == *"<"* ]]; then
  echo "[ERROR] Please configure ISSUER_URI or set export ISSUER_URI=\"https://your-domain.okta.com/oauth2/default\"" >&2
  exit 1
fi
DEVICE_AUTH_ENDPOINT="${ISSUER_URI}/v1/device/authorize"
TOKEN_ENDPOINT="${ISSUER_URI}/v1/token"

mkdir -p "${TOKEN_DIR}"
chmod 700 "${TOKEN_DIR}"

inspect_and_save_token() {
  local token="$1"
  local refresh_token="${2:-}"
  token=$(echo "$token" | tr -d '\r\n[:space:]')
  refresh_token=$(echo "$refresh_token" | tr -d '\r\n[:space:]')

  if [ -z "$token" ]; then
    echo "[ERROR] Token is empty." >&2
    exit 1
  fi

  # Basic JWT structure check (header.payload.signature)
  local parts
  parts=$(echo "$token" | awk -F'.' '{print NF}')
  if [ "$parts" -ne 3 ]; then
    echo "[ERROR] Input is not a valid 3-part JWT (expected header.payload.signature)." >&2
    exit 1
  fi

  # Decode payload to verify claims
  local payload
  payload=$(echo "$token" | awk -F'.' '{print $2}')
  local decoded
  decoded=$(python3 -c "
import sys, base64, json
raw = sys.argv[1]
padded = raw + '=' * (-len(raw) % 4)
try:
    print(base64.urlsafe_b64decode(padded).decode('utf-8'))
except Exception as e:
    sys.exit(1)
" "$payload" 2>/dev/null || true)

  if [ -z "$decoded" ]; then
    echo "[ERROR] Failed to decode JWT payload." >&2
    exit 1
  fi

  # Atomically save access token with permissions 0600
  (umask 077 && printf '%s\n' "$token" > "${TOKEN_FILE}.tmp.$$" && mv -f "${TOKEN_FILE}.tmp.$$" "${TOKEN_FILE}")
  chmod 600 "${TOKEN_FILE}"

  # If refresh token is present, atomically save with permissions 0600
  if [ -n "$refresh_token" ]; then
    (umask 077 && printf '%s\n' "$refresh_token" > "${REFRESH_TOKEN_FILE}.tmp.$$" && mv -f "${REFRESH_TOKEN_FILE}.tmp.$$" "${REFRESH_TOKEN_FILE}")
    chmod 600 "${REFRESH_TOKEN_FILE}"
  fi

  echo ""
  echo "====================================================================="
  echo "  Okta Access Token Successfully Stored at:  ${TOKEN_FILE}"
  if [ -n "$refresh_token" ]; then
    echo "  Okta Refresh Token Successfully Stored at: ${REFRESH_TOKEN_FILE}"
  elif [ -f "${REFRESH_TOKEN_FILE}" ]; then
    echo "  Existing Refresh Token Present at:         ${REFRESH_TOKEN_FILE}"
  fi
  echo "====================================================================="

  echo "$decoded" | python3 -c "
import sys, json, time, os
try:
    data = json.load(sys.stdin)
except Exception as e:
    sys.exit(0)

sub = data.get('sub', 'N/A')
email = data.get('email', data.get('preferred_username', 'N/A'))
groups = data.get('groups', [])
exp = data.get('exp', 0)
remaining = int(exp - time.time()) if exp else 0
expected_group = os.environ.get('AUTHORIZED_GROUP', 'claude-code-users')

print(f'  Subject:      {sub}')
print(f'  Email:        {email}')
print(f'  Groups:       {groups}')
print(f'  Expires in:   {remaining // 60} minutes ({remaining} seconds)')

is_member = False
if isinstance(groups, list):
    is_member = expected_group in groups
elif isinstance(groups, str):
    is_member = expected_group == groups

if is_member:
    print(f'  Status:       [PASS] Member of authorized group {expected_group}')
else:
    print(f'  Status:       [WARN] {expected_group} NOT found in groups claim')
"
  echo "====================================================================="
}

# Mode 1: Argument supplied
if [ $# -ge 1 ] && [ -n "$1" ]; then
  inspect_and_save_token "$1" "${2:-}"
  exit 0
fi

# Mode 2: Device Authorization Flow (if OKTA_CLIENT_ID is provided)
OKTA_CLIENT_ID="${OKTA_CLIENT_ID:-<YOUR_OKTA_CLIENT_ID>}"
if [[ -n "${OKTA_CLIENT_ID:-}" && "${OKTA_CLIENT_ID}" != *"<"* ]]; then
  echo "Initiating Okta Device Authorization Flow..."
  echo "Issuer: ${ISSUER_URI}"
  echo "Client ID: ${OKTA_CLIENT_ID}"

  DEVICE_RESP=$(curl -s -X POST "${DEVICE_AUTH_ENDPOINT}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${OKTA_CLIENT_ID}&scope=openid%20profile%20email%20offline_access")

  if echo "$DEVICE_RESP" | grep -q '"error"'; then
    echo "[ERROR] Device authorization failed: ${DEVICE_RESP}" >&2
    exit 1
  fi

  DEVICE_CODE=$(echo "$DEVICE_RESP" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('device_code', ''))")
  USER_CODE=$(echo "$DEVICE_RESP" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('user_code', ''))")
  VERIF_URI=$(echo "$DEVICE_RESP" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('verification_uri_complete') or data.get('verification_uri', ''))")
  INTERVAL=$(echo "$DEVICE_RESP" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('interval', 5))")

  echo ""
  echo "---------------------------------------------------------------------"
  echo " Please authenticate via browser:"
  echo " URL:       ${VERIF_URI}"
  echo " User Code: ${USER_CODE}"
  echo "---------------------------------------------------------------------"
  echo "Waiting for browser confirmation..."

  while true; do
    sleep "${INTERVAL}"
    TOKEN_RESP=$(curl -s -X POST "${TOKEN_ENDPOINT}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=${OKTA_CLIENT_ID}&grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=${DEVICE_CODE}" 2>/dev/null || true)

    ERROR=$(echo "$TOKEN_RESP" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('error', ''))" 2>/dev/null || true)

    if [ "$ERROR" = "authorization_pending" ]; then
      continue
    elif [ "$ERROR" = "slow_down" ]; then
      INTERVAL=$((INTERVAL + 5))
      continue
    elif [ -n "$ERROR" ]; then
      echo "[ERROR] Okta returned error: ${TOKEN_RESP}" >&2
      exit 1
    fi

    # Retrieve access_token or id_token, and refresh_token
    RECEIVED_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('access_token') or data.get('id_token', ''))" 2>/dev/null || true)
    REFRESH_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('refresh_token', ''))" 2>/dev/null || true)

    if [ -n "$RECEIVED_TOKEN" ]; then
      inspect_and_save_token "$RECEIVED_TOKEN" "$REFRESH_TOKEN"
      if [ -z "$REFRESH_TOKEN" ]; then
        echo "  [WARN] No refresh_token returned by Okta. Verify offline_access scope in Okta application."
      fi
      exit 0
    fi
  done
fi

# Mode 3: Interactive paste
echo "====================================================================="
echo "  Okta JWT Credential Setup for Claude Code OTel                     "
echo "====================================================================="
echo "No OKTA_CLIENT_ID set for device flow. Falling back to token paste."
echo ""
echo "Paste your Okta JWT token below and press ENTER:"
read -r -s INPUT_TOKEN
echo ""

inspect_and_save_token "${INPUT_TOKEN}"
