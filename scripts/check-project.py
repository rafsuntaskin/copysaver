#!/usr/bin/env python3
"""Static source/project/privacy checks; does not claim signed OS enforcement."""
import json
import plistlib
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
project = root / "CopySaver.xcodeproj/project.pbxproj"
data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
objects = data["objects"]
assert all(re.fullmatch(r"[0-9A-F]{24}", key) for key in objects)
references = set(re.findall(r"\b[0-9A-F]{24}\b", project.read_text()))
assert references <= set(objects), f"Unresolved project references: {references - set(objects)}"
assert objects[data["rootObject"]]["isa"] == "PBXProject"
project_configurations = objects[objects[data["rootObject"]]["buildConfigurationList"]]["buildConfigurations"]
for configuration in project_configurations:
    configuration = objects[configuration]
    expected = "YES" if configuration["name"] == "Debug" else "NO"
    assert configuration["buildSettings"].get("ONLY_ACTIVE_ARCH", "NO") == expected, "Debug app/extension and Swift package architectures must agree"
for source in ["App/CopySaverMain.swift", "Widget/CopySaverWidgetMain.swift", "TestsSupport/KeychainProbe/KeychainBoundaryProbeMain.swift"]:
    assert (root / source).is_file(), source
for folder, entitlement in [("App", "CopySaver.entitlements"), ("Widget", "CopySaverWidget.entitlements"),
                            ("TestsSupport/KeychainProbe", "CopySaverKeychainProbe.entitlements")]:
    expected_entitlements = {"com.apple.security.app-sandbox": True}
    if folder == "App":
        expected_entitlements["com.apple.security.network.client"] = True
    if folder != "Widget":
        expected_entitlements["keychain-access-groups"] = ["$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"]
    assert plistlib.loads((root / folder / entitlement).read_bytes()) == expected_entitlements
    plistlib.loads((root / folder / "Info.plist").read_bytes())
assert plistlib.loads((root / "App/CopySaverPreview.entitlements").read_bytes()) == {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True}
assert "--entitlements App/CopySaverPreview.entitlements" in (root / "scripts/build-app.sh").read_text()

app_info = plistlib.loads((root / "App/Info.plist").read_bytes())
assert app_info.get("CFBundleIconFile") == "AppIcon"
assert (root / "App/Resources/AppIcon.icns").read_bytes()[:4] == b"icns"
assert "AppIcon.icns" in (root / "scripts/build-app.sh").read_text()

app_id = "E00000000000000000000001"
widget_id = "E00000000000000000000002"
for target_id in [app_id, widget_id]:
    target = objects[target_id]
    configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
    settings = [objects[c]["buildSettings"] for c in configurations]
    assert len({s["PRODUCT_BUNDLE_IDENTIFIER"] for s in settings}) == 2
    assert all(s["ENABLE_APP_SANDBOX"] == "YES" and s["ENABLE_HARDENED_RUNTIME"] == "YES" for s in settings)
    if target_id == widget_id:
        assert all(s["APPLICATION_EXTENSION_API_ONLY"] == "YES" and s["SKIP_INSTALL"] == "YES" for s in settings)
assert any(objects[dep]["target"] == widget_id for dep in objects[app_id]["dependencies"])
phases = [objects[p] for p in objects[app_id]["buildPhases"]]
assert any(objects[objects[f]["fileRef"]].get("path") == "Resources/AppIcon.icns"
           for p in phases if p["isa"] == "PBXResourcesBuildPhase" for f in p["files"])

assert any(p["isa"] == "PBXCopyFilesBuildPhase" and p["dstSubfolderSpec"] == "13" for p in phases)
probe_id = "E10000000000000000000001"
probe = objects[probe_id]
for configuration in objects[probe["buildConfigurationList"]]["buildConfigurations"]:
    settings = objects[configuration]["buildSettings"]
    assert settings["PRODUCT_BUNDLE_IDENTIFIER"].endswith(".dev.BoundaryProbe")
    assert all(settings[key] == "YES" for key in ["ENABLE_APP_SANDBOX", "ENABLE_HARDENED_RUNTIME", "SKIP_INSTALL"])
product_targets = set()
pending = [app_id, widget_id]
while pending:
    target_id = pending.pop()
    if target_id in product_targets:
        continue
    product_targets.add(target_id)
    pending.extend(objects[dep]["target"] for dep in objects[target_id]["dependencies"])
assert probe_id not in product_targets, "Integration probe must not enter the product dependency graph"
for target_id in product_targets:
    for phase_id in objects[target_id]["buildPhases"]:
        for build_file in objects[phase_id]["files"]:
            assert objects[build_file].get("fileRef") not in {
                "B10000000000000000000001", "B10000000000000000000004"
            }, "Integration probe must never be compiled into or embedded in the product"
for scheme_path in (root / "CopySaver.xcodeproj/xcshareddata/xcschemes").glob("*.xcscheme"):
    scheme = ET.parse(scheme_path)
    assert all(node.attrib["BlueprintIdentifier"] in objects for node in scheme.findall(".//BuildableReference"))
    if scheme_path.stem == "CopySaver":
        assert all(node.attrib["BlueprintIdentifier"] != probe_id for node in scheme.findall(".//BuildableReference"))
    elif scheme_path.stem == "CopySaverKeychainProbe":
        assert all(node.attrib["BlueprintIdentifier"] == probe_id for node in scheme.findall(".//BuildableReference"))
        assert all(entry.attrib["buildForArchiving"] == "NO" for entry in scheme.findall(".//BuildActionEntry"))

package = (root / "Package.swift").read_text()
assert '.target(name: "CopySaverWidgets")' in package, "Widget must have no app/vault dependencies"
for source in (root / "Sources/CopySaverWidgets").glob("*.swift"):
    text = source.read_text()
    assert set(re.findall(r"^import (\w+)", text, re.M)) <= {"Foundation", "SwiftUI", "WidgetKit"}
    for forbidden in ["NSPasteboard", "SecItem", "UserDefaults", "FileManager", "URLSession", "CopySaverVault", "CopySaverPlatform"]:
        assert forbidden not in text, f"Widget privacy regression: {forbidden}"

spec = (root / "spec.md").read_text()
tasks = re.findall(r"^- \[([ x])\] \*\*([A-Z]+\d?-\d+)\*\*", spec, re.M)
assert len(tasks) == len({identifier for _, identifier in tasks}), "Duplicate checklist ID"
links = 0
for source in root.rglob("*.md"):
    if any(part.startswith(".") for part in source.relative_to(root).parts):
        continue
    for target in re.findall(r"!?\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)", source.read_text()):
        if "://" in target or target.startswith("mailto:"):
            continue
        path, _, anchor = unquote(target).partition("#")
        destination = source.parent / path if path else source
        assert destination.exists(), f"Broken local link: {source.relative_to(root)} -> {target}"
        if anchor and destination.suffix == ".md":
            headings = re.findall(r"^#{1,6}\s+(.+)$", destination.read_text(), re.M)
            slugs = {re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-") for heading in headings}
            assert anchor in slugs, f"Missing heading: {target}"
        links += 1
print(f"Static checks passed: {len(objects)} project objects, app/widget separation, {len(tasks)} task IDs, {links} local links.")
