import subprocess
import json

# Simulate device flow response without verification_uri_complete
device_resp = json.dumps({
    "device_code": "dev-12345",
    "user_code": "ABCD-EFGH",
    "verification_uri": "https://example.okta.com/activate",
    "interval": 5
})

# Test the exact extraction logic from login_okta_device.sh
cmd = 'python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get(\'verification_uri_complete\') or data.get(\'verification_uri\', \'\'))"'
proc = subprocess.run(
    cmd,
    shell=True,
    input=device_resp,
    text=True,
    capture_output=True
)

print("Exit code:", proc.returncode)
print("Extracted URI:", proc.stdout.strip())
assert proc.returncode == 0
assert proc.stdout.strip() == "https://example.okta.com/activate"
print("Verification: Device code URI extraction without verification_uri_complete succeeded!")
