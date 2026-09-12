"""Package the signed helper from a Kipple release without embedding credentials."""

import argparse
import json
import plistlib
from pathlib import Path
import subprocess
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("build/Kipple.mcpb"))
    args = parser.parse_args()
    helper = args.helper.resolve(strict=True)
    subprocess.run(["codesign", "--verify", "--strict", str(helper)], check=True)
    identity = subprocess.run(
        ["codesign", "-d", "--verbose=4", str(helper)], capture_output=True, text=True, check=True,
    )
    if "TeamIdentifier=R7LKF73J2W" not in identity.stderr:
        parser.error("Use a release helper signed by the Kipple team; an ad-hoc helper cannot access the App Group.")
    entitlements = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(helper)], capture_output=True, check=True,
    )
    try:
        permissions = plistlib.loads(entitlements.stdout)
    except (plistlib.InvalidFileException, ValueError):
        parser.error("The helper has no valid signed entitlements.")
    if (permissions.get("com.apple.security.app-sandbox") is not True or
            "R7LKF73J2W.com.nissy.Kipple" not in permissions.get("com.apple.security.application-groups", [])):
        parser.error("The helper must be sandboxed and signed with the Kipple App Group entitlement.")
    project = Path(__file__).resolve().parents[1]
    manifest = json.loads((project / "MCPBundle/manifest.json").read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
        binary = zipfile.ZipInfo("server/KippleMCP")
        binary.external_attr = 0o100755 << 16
        bundle.writestr(binary, helper.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
        bundle.write(project / "MCP.md", "README.md")
        bundle.write(project / "Kipple/Resources/MCP-ThirdPartyNotices.txt", "THIRD_PARTY_NOTICES.txt")
    print(args.output.resolve())


if __name__ == "__main__":
    main()
