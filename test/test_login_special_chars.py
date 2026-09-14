import base64
import json
import subprocess
import time
import os

now = int(time.time())
header = base64.urlsafe_b64encode(json.dumps({"alg": "RS256", "typ": "JWT"}).encode()).decode().rstrip("=")

# Claims with special characters that would break direct string interpolation:
# - single quotes: O'Connor
# - escaped backslashes: test\user
# - quotes inside fields
payload = base64.urlsafe_b64encode(json.dumps({
    "iss": "https://example.okta.com/oauth2/default",
    "aud": "api://default",
    "sub": "developer.o'connor@example.com",
    "email": "developer.o'connor@example.com",
    "groups": ["claude-code-users", "dev's group"],
    "iat": now,
    "exp": now + 3600
}).encode()).decode().rstrip("=")

token = f"{header}.{payload}.mock_sig"

proc = subprocess.run(
    ["./idp-federation/scripts/login_okta_device.sh", token],
    capture_output=True,
    text=True
)

print("Exit code:", proc.returncode)
print("Stdout:\n", proc.stdout)
print("Stderr:\n", proc.stderr)

# Verify ~/.corporate_idp/token exists and matches
token_path = os.path.expanduser("~/.corporate_idp/token")
assert os.path.exists(token_path), "Token file must exist"
with open(token_path) as f:
    saved = f.read().strip()
assert saved == token, "Saved token must match input token"
print("Verification: Token successfully saved and verified!")
