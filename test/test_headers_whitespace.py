import subprocess
import json

# Test generate_otel_headers.sh with whitespace around token
token_with_whitespace = "   eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.sig\r\n  \n "

proc = subprocess.run(
    ["./idp-federation/scripts/generate_otel_headers.sh"],
    env={"CORPORATE_IDP_TOKEN": token_with_whitespace, "PATH": "/usr/local/bin:/usr/bin:/bin"},
    capture_output=True,
    text=True
)

print("Exit code:", proc.returncode)
print("Stdout:", repr(proc.stdout))
print("Stderr:", repr(proc.stderr))

# Must exit 0 and have silent/empty stdout on invalid token
assert proc.returncode == 0
assert proc.stdout == ""
print("Verification: Whitespace-padded invalid token exited cleanly with code 0 and empty stdout!")
