import base64
import json
import subprocess
import time

now = int(time.time())
header = base64.urlsafe_b64encode(json.dumps({"alg": "RS256", "typ": "JWT"}).encode()).decode().rstrip("=")
payload = base64.urlsafe_b64encode(json.dumps({
    "iss": "https://example.okta.com/oauth2/default",
    "aud": "api://default",
    "sub": "some.unauthorized.user@example.com",
    "groups": ["marketing", "sales"],
    "iat": now,
    "exp": now + 3600
}).encode()).decode().rstrip("=")
token = f"{header}.{payload}.mock_sig"

proc = subprocess.run(
    ["./idp-federation/scripts/test_token_pipeline.sh"],
    env={"CORPORATE_IDP_TOKEN": token, "PATH": "/usr/local/bin:/usr/bin:/bin"},
    capture_output=True,
    text=True
)

print("Exit code:", proc.returncode)
print("Stdout:\n", proc.stdout)
print("Stderr:\n", proc.stderr)
