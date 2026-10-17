#!/usr/bin/env python3
#
# Write the AltStore / SideStore source (source.json) for the Pages site.
# Lists every stable (non-prerelease) GitHub release that has an AltLoad.ipa,
# newest first, pointing at the official release download. App info
# (bundle id, minimum iOS, privacy strings) is read from the given IPA.
#
# Usage:
#   build-source.py <ipa> <out_dir> <base_url>
#
# Reads GITHUB_REPOSITORY (default mirazbakis/AltLoad) and, if set,
# GITHUB_TOKEN for the releases API.

import json
import os
import plistlib
import re
import sys
import urllib.request
import zipfile

IPA, OUT_DIR, BASE_URL = sys.argv[1], sys.argv[2], sys.argv[3].rstrip("/")
REPO = os.environ.get("GITHUB_REPOSITORY", "mirazbakis/AltLoad")
ASSET = "AltLoad.ipa"


def app_info(ipa):
    with zipfile.ZipFile(ipa) as z:
        name = next(n for n in z.namelist()
                    if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n))
        return plistlib.loads(z.read(name))


def releases():
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/releases?per_page=100",
        headers={"Accept": "application/vnd.github+json"})
    if os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", f"Bearer {os.environ['GITHUB_TOKEN']}")
    with urllib.request.urlopen(req) as r:
        return json.load(r)


info = app_info(IPA)
latest = info.get("CFBundleShortVersionString", "")

versions = []
for rel in releases():
    if rel["draft"] or rel["prerelease"]:
        continue
    asset = next((a for a in rel["assets"] if a["name"] == ASSET), None)
    if not asset:
        continue
    version = rel["tag_name"].lstrip("v")
    v = {
        "version": version,
        "date": rel["published_at"],
        "localizedDescription": (rel.get("body") or "").strip() or f"AltLoad {version}",
        "downloadURL": asset["browser_download_url"],
        "size": asset["size"],
    }
    if version == latest and info.get("MinimumOSVersion"):
        v["minOSVersion"] = info["MinimumOSVersion"]
    versions.append(v)

if not versions:
    sys.exit("No stable release with AltLoad.ipa found")

icon = f"{BASE_URL}/AltLoad.png"
source = {
    "name": "AltLoad",
    "identifier": "com.mirazbakis.altload.source",
    "subtitle": "Official AltLoad builds.",
    "description": "The official source for AltLoad by mirazbakis. "
                   "Builds come straight from https://github.com/mirazbakis/AltLoad/releases.",
    "iconURL": icon,
    "website": f"{BASE_URL}/",
    "tintColor": "#4C8DFF",
    "featuredApps": [info["CFBundleIdentifier"]],
    "apps": [{
        "name": "AltLoad",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "mirazbakis",
        "subtitle": "Your iPhone is the computer now.",
        "localizedDescription": "AltLoad pairs your iPhone with itself, signs AltStore, "
                                "SideStore or LiveContainer with your Apple ID, and installs it. "
                                "No Mac, no PC, no subscription.",
        "iconURL": icon,
        "tintColor": "#4C8DFF",
        "category": "developer",
        "versions": versions,
        "appPermissions": {
            "entitlements": [],
            "privacy": {k: v for k, v in info.items() if k.endswith("UsageDescription")},
        },
    }],
    "news": [],
}

path = os.path.join(OUT_DIR, "source.json")
with open(path, "w") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f">> Wrote {path} with {len(versions)} version(s)")
