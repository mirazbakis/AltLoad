# Signed OTA installs

Signs the latest **non-beta** AltLoad release with your own ad-hoc certificates and
publishes a tap-to-install page to GitHub Pages — one **Install** button per cert
pack (sideinstaller.net style), each the same app under its own bundle id.

```
signing/
  certs/<N>/<N>.p12              signing certificate + private key   (N = 1..11)
  certs/<N>/<N>.mobileprovision  ad-hoc provisioning profile (its UDIDs)
  scripts/sign-pack.sh           sign one IPA with one pack (keychain, identity, rcodesign fallback)
  scripts/resign.sh              re-sign + rewrite bundle id
  scripts/build-manifest.sh      per slot: copy IPA + write manifest.plist + meta.txt
  scripts/build-site.sh          copy site/ into _site + write installs/index.json
site/
  index.html  terms.html  assets/  AltLoad.png  AltLoadDNS.mobileconfig
.github/workflows/sign-ota.yml   every pack → the install page (macOS runner)
.github/workflows/sign-ipa.yml   any IPA, one pack → a downloadable artifact
```

## How it runs

1. Downloads `https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa`.
   `releases/latest` is the latest **non-prerelease** release, so beta/rc and the
   `nightly` tag are excluded automatically.
2. For each `signing/certs/<N>/`, imports the cert into a throwaway keychain, re-signs the
   IPA with it, rewrites the bundle id to `com.mirazbakis.altload<N>` (and the widget
   to `…altload<N>.widgets`), and writes `_site/installs/altload<N>/{app.ipa,manifest.plist}`.
3. Builds `_site/installs/index.json`; `site/index.html` fetches it and renders a button
   per slot pointing at `itms-services://…/manifest.plist`.
4. Deploys `_site` to GitHub Pages at `https://mirazbakis.github.io/AltLoad/`.

Triggers: **Actions → "Sign IPAs & Deploy OTA" → Run workflow**, any push under
`signing/**`, `site/**` or the workflow file, every published release, and once a
week (Monday 04:17 UTC) so the signatures, every `manifest.plist` and
`installs/index.json` are refreshed without anyone doing anything.

## Signing any IPA

**Actions → "Sign IPA" → Run workflow** takes an IPA link, a pack number and an
optional new bundle id. It signs the IPA with that pack and uploads `app.ipa` and
`manifest.plist` as the `signed-ipa` artifact. It doesn't touch the site.

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
`signing/certs/` and re-run.
