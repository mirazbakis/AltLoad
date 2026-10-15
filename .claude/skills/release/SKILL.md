---
name: release
description: Publish a new AltLoad version (bump version, release notes, CI release run). Use when asked to release, ship or publish a version of AltLoad.
---

# Releasing AltLoad

1. **Version.** In `project.yml` set `MARKETING_VERSION` to the new version and increase `CURRENT_PROJECT_VERSION` by one.
2. **Notes.** Write `docs/releases/v<version>.md`, starting with `## AltLoad <version>`, then `### New`, `### Fixed`, `### Changed` sections as needed. Short bullets, bold lead-ins, user-facing language. If the owner gives their own notes, use them word for word.
3. **Check it builds:** `bash scripts/build-rust.sh` (only if `rust/` changed), `xcodegen generate`, then the simulator `xcodebuild` from CLAUDE.md.
4. **Commit** as `Release v<version>`, authored by the owner, no trailers.
5. **Push** through GitHub Desktop (Repository › Push). The shell has no GitHub credentials.
6. **Run CI:** GitHub › Actions › Build IPA › Run workflow, branch `main`, "What to do with the IPA" = **Release**, tag `v<version>`. The run creates the tag, publishes the release as latest and attaches `AltLoad.ipa`. **Nightly** instead replaces the Nightly build; **Build only** leaves an artifact on the run.
7. **Verify** with the GitHub API: the release exists and is latest, the body matches the notes, and the IPA's `Info.plist` has the new `CFBundleShortVersionString` and `CFBundleVersion`. Also check `https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa` returns 200 (the website's Download button).

Don't push a `v*` tag by itself: tags no longer start CI.
