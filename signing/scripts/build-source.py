#!/usr/bin/env python3
#
# Write the AltStore / SideStore source (source.json, kept at the repo root and
# served from raw.githubusercontent.com).
# Lists every stable (non-prerelease) GitHub release that has an AltLoad.ipa,
# newest first, pointing at the official release download. App info
# (bundle id, privacy strings) is read from the given IPA. The minimum iOS is
# MIN_IOS, not the IPA's: pairing on the device needs iOS 27.
#
# Usage:
#   build-source.py <ipa> <out_dir>
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

IPA, OUT_DIR = sys.argv[1], sys.argv[2]
REPO = os.environ.get("GITHUB_REPOSITORY", "mirazbakis/AltLoad")
RAW = f"https://raw.githubusercontent.com/{REPO}/main"
ASSET = "AltLoad.ipa"
MIN_IOS = "27.0"


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
        "minOSVersion": MIN_IOS,
    }
    versions.append(v)

if not versions:
    sys.exit("No stable release with AltLoad.ipa found")

icon = f"{RAW}/docs/assets/logo.png"
source = {
    "name": "AltLoad",
    "identifier": "com.mirazbakis.altload.source",
    "subtitle": "Official AltLoad builds.",
    "description": "The official source for AltLoad by mirazbakis. "
                   "Builds come straight from https://github.com/mirazbakis/AltLoad/releases.",
    "iconURL": icon,
    "website": f"https://github.com/{REPO}",
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
