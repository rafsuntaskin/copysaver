#!/usr/bin/env python3
"""Exercise probe admission guards only; never authenticate or access Keychain."""
import subprocess
import sys
from pathlib import Path

binary = Path(sys.argv[1]).resolve(strict=True)
assert not any(part.endswith(".app") for part in binary.parts), "Admission checks require an unbundled executable; never run them on a signed owner fixture"
owner = ["--owner-bundle-id", "org.copysaver.CopySaver.dev"]
fixture = ["--synthetic-vault-id", "0DDAB6CE-C530-4371-A611-D986E68B0D53"]
cases = [
    (["--help"], 0, "Manual signed probe"),
    ([], 1, "Invalid arguments"),
    (["--owner-bundle-id", "org.copysaver.CopySaver"] + fixture + ["--confirm-synthetic-vault"], 1, "Invalid arguments"),
    (owner + fixture, 1, "Invalid arguments"),
    (owner + ["--synthetic-vault-id", "invalid", "--confirm-synthetic-vault"], 1, "Invalid arguments"),
    (owner + fixture + ["--confirm-synthetic-vault"], 1, "valid development-signed helper app"),
    (owner + ["--cleanup-control"], 1, "valid development-signed helper app"),
    (["--owner-fixture", "create", "--confirm-synthetic-vault"], 1, "valid development-signed helper app"),
    (["--owner-fixture", "verify", "--confirm-synthetic-vault"], 1, "valid development-signed helper app"),
    (["--owner-fixture", "cancel", "--confirm-synthetic-vault"], 1, "valid development-signed helper app"),
    (["--owner-fixture", "cleanup", "--confirm-synthetic-vault", "--confirm-delete-fixture"], 1, "valid development-signed helper app"),
    (["--owner-fixture", "create"], 1, "Invalid arguments"),
    (["--owner-fixture", "cleanup", "--confirm-synthetic-vault"], 1, "Invalid arguments"),
    (["--owner-fixture", "unknown", "--confirm-synthetic-vault"], 1, "Invalid arguments"),
    (["--owner-fixture", "create", "--confirm-synthetic-vault", "/tmp/other-vault"], 1, "Invalid arguments"),
]
for arguments, expected_status, expected_message in cases:
    result = subprocess.run([str(binary), *arguments], capture_output=True, text=True, timeout=10)
    assert result.returncode == expected_status, "Probe guard returned an unexpected status"
    assert expected_message in result.stdout + result.stderr, "Probe guard returned an unexpected diagnostic"
    assert fixture[1] not in result.stdout + result.stderr, "Probe leaked query metadata"
print(f"Keychain probe admission guards passed ({len(cases)} cases; no Keychain operations).")
