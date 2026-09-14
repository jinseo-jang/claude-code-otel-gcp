import base64
import json
import time
import urllib.request

now = int(time.time())
header = base64.urlsafe_b64encode(json.dumps({"alg": "RS256", "typ": "JWT"}).encode()).decode().rstrip("=")
payload = base64.urlsafe_b64encode(json.dumps({
    "iss": "https://example.okta.com/oauth2/default",
    "aud": "wrong-audience",
    "sub": "developer@example.com",
    "groups": ["claude-code-users"],
    "iat": now,
    "exp": now + 3600
}).encode()).decode().rstrip("=")
mock_token = f"{header}.{payload}.fake_sig"

sts_url = "https://sts.googleapis.com/v1/token"
req_body = {
    "grantType": "urn:ietf:params:oauth:grant-type:token-exchange",
    "audience": "//iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/claude-code-pool/providers/okta-oidc-provider",
    "scope": "https://www.googleapis.com/auth/cloud-platform",
    "requestedTokenType": "urn:ietf:params:oauth:token-type:access_token",
    "subjectTokenType": "urn:ietf:params:oauth:token-type:jwt",
    "subjectToken": mock_token
}

req = urllib.request.Request(
    sts_url,
    data=json.dumps(req_body).encode("utf-8"),
    headers={"Content-Type": "application/json; charset=utf-8"}
)

try:
    with urllib.request.urlopen(req) as resp:
        print("HTTP Status:", resp.status)
        print("Response:", resp.read().decode())
except urllib.error.HTTPError as e:
    print("HTTP Status:", e.code)
    print("Error Body:", e.read().decode())
