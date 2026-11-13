#!/usr/bin/env python3
"""Inspect a built community app; this is not a Gatekeeper or Keychain runtime test."""
import plistlib
import re
import subprocess
import sys
from pathlib import Path

def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(len(sys.argv) == 2, "Usage: scripts/check-community-artifact.py /path/to/CopySaver.app")
app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
require(info["CFBundleIdentifier"] == "org.copysaver.CopySaver.community", "Unexpected community app identity.")
require(info["CopySaverStorageProfile"] == "automatic", "Automatic storage profile required.")
require("NSFaceIDUsageDescription" not in info, "Community app must not advertise device-owner authentication.")
require(info["CopySaverURLScheme"] == "copysaver-community", "Unexpected community navigation scheme.")
require(info.get("CFBundleIconFile") == "AppIcon", "Layered C app icon required.")
require((app / "Contents/Resources/AppIcon.icns").read_bytes()[:4] == b"icns", "Valid bundled icon required.")
require((app / "Contents/Resources/LICENSE").read_bytes() == (Path(__file__).resolve().parent.parent / "LICENSE").read_bytes(), "App must carry the MIT copyright/license notice.")
widget = app / "Contents/PlugIns/CopySaverWidget.appex"
widget_info = plistlib.loads((widget / "Contents/Info.plist").read_bytes())
require(widget_info["CFBundleIdentifier"] == info["CFBundleIdentifier"] + ".Widget", "Unexpected widget identity.")
require(widget_info["CopySaverCommunityBuild"] is True, "Community widget routing required.")
for key in ["CFBundleVersion", "CFBundleShortVersionString", "CopySaverReleaseChannel", "CopySaverReleaseLabel"]:
    require(info[key] == widget_info[key], "App and widget versions must match.")
for bundle, executable in [(app, info["CFBundleExecutable"]), (widget, widget_info["CFBundleExecutable"])]:
    require(not (bundle / "Contents/embedded.provisionprofile").exists(), "Provisioning profile must not be embedded.")
    require({p.name for p in (bundle / "Contents/MacOS").iterdir()} == {executable}, "Unexpected executable in product bundle.")
    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
    signature = subprocess.run(["codesign", "-d", "--verbose=4", str(bundle)], capture_output=True, check=True).stderr.decode()
    require("Signature=adhoc" in signature and re.search(r"flags=0x[0-9a-fA-F]+\([^)]*\bruntime\b", signature), "Ad-hoc hardened runtime required.")
    require("Authority=" not in signature and "TeamIdentifier=not set" in signature, "Apple-issued signing authority must not be used.")
    entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)], capture_output=True, check=True).stdout
    expected = {"com.apple.security.app-sandbox": True}
    if bundle == app: expected["com.apple.security.network.client"] = True
    require(plistlib.loads(entitlements) == expected, "Only sandbox and parent-app outgoing preview access are allowed.")
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(bundle / "Contents/MacOS" / executable)], text=True).split()
    require(set(architectures) == {"arm64", "x86_64"}, "Both Apple silicon and Intel slices required.")
require(info["CopySaverReleaseChannel"] == "beta", "Community release channel must remain beta until stable acceptance passes.")
subprocess.run(["codesign", "--verify", "--strict", "--deep", str(app)], check=True)
print("Community app/widget: ad-hoc, sandboxed, hardened, universal; no Apple authority, provisioning or restricted entitlements.")
