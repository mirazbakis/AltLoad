# Signed OTA installs

Signs the latest **non-beta** AltLoad release with your own ad-hoc certificates and
publishes a tap-to-install page to GitHub Pages — one **Install** button per cert
pack (sideinstaller.net style), each the same app under its own bundle id.

```
ota/
  certs/<N>/<N>.p12              signing certificate + private key   (N = 1..11)
  certs/<N>/<N>.mobileprovision  ad-hoc provisioning profile (its UDIDs)
  scripts/resign.sh              re-sign + rewrite bundle id to com.mirazbakis.altload<N>
  scripts/build-manifest.sh      per slot: copy IPA + write manifest.plist + meta.txt
  scripts/build-site.sh          copy web/ into _site + write installs/index.json
web/
  index.html  terms.html  assets/  AltLoad.png   the Pages site (buttons built from the JSON)
.github/workflows/sign-ota.yml   the pipeline (macOS runner)
```

## How it runs

1. Downloads `https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa`.
   `releases/latest` is the latest **non-prerelease** release, so beta/rc and the
   `nightly` tag are excluded automatically.
2. For each `ota/certs/<N>/`, imports the cert into a throwaway keychain, re-signs the
   IPA with it, rewrites the bundle id to `com.mirazbakis.altload<N>` (and the widget
   to `…altload<N>.widgets`), and writes `_site/installs/altload<N>/{app.ipa,manifest.plist}`.
3. Builds `_site/installs/index.json`; `web/index.html` fetches it and renders a button
   per slot pointing at `itms-services://…/manifest.plist`.
4. Deploys `_site` to GitHub Pages at `https://mirazbakis.github.io/AltLoad/`.

Triggers: **Actions → "Sign IPAs & Deploy OTA" → Run workflow**, or any push under
`ota/**`, `web/**`, or the workflow file.

## One-time setup

1. **Pages source must be GitHub Actions.**
   Settings → Pages → Build and deployment → **Source: GitHub Actions**. (If it is
   currently "Deploy from a branch", switch it, or the deploy step fails.)
2. **Password.** The `.p12` password defaults to `WSF`. To change it, set a repo
   secret `P12_PASSWORD` (Settings → Secrets and variables → Actions). All packs use
   the same password.
3. Push, then run the workflow.

## Limits (ad-hoc, no enterprise cert)

- A device installs a slot **only if its UDID is in that slot's profile**. Other
  devices get an install error — that's expected for ad-hoc distribution.
- OTA needs **HTTPS** (Pages provides it) and **Safari** on the device.
- The main app is what the link installs; on a single-app explicit profile the widget
  extension may not activate. Certificates/profiles **expire** — re-run with fresh
  packs when they do.

## Note on committed keys

The `.p12` files and their password are committed to this **public** repo on purpose
(owner's choice). Anyone can download them and sign with these identities, but because
the profiles are ad-hoc they only produce installs for the already-registered UDIDs.
GitHub secret scanning may still flag them. To rotate: replace the packs under
`ota/certs/` and re-run.
