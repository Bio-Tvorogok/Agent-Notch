# Self-update implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement task by task.

**Goal:** Check stable updates automatically and manually; install after user confirmation.
**Architecture:** Sparkle 2.10.0 owns scheduling, presentation, archive validation and installation. One app controller supplies the menu and settings. Existing shell packaging embeds the pinned framework and produces a signed GitHub release feed.
**Tech Stack:** Swift/AppKit/SwiftUI, Sparkle 2.10.0, shell, Python 3 build checks.
**Spec:** docs/self-update-design.md

## Global constraints
- macOS 14+, Apple Silicon; preserve prompts, vault, custom sounds, command log, Keep awake and visibility preferences.
- Background checks every 86400 seconds, switchable; never automatically download or install.
- Stable GitHub Releases only, HTTPS in production, Ed25519 signed archives.
- Work in codex/self-update based on fc1a6fd; no merge to master, publication or installed-app replacement without approval.

## Review focus
- Missing/malformed key: fail build before producing a distribution archive.
- Local high build counters: compare marketing versions consistently across CI and local builds.
- Snapshot/fixture invocations: no updater scheduling or preference writes.
- Download failure/corruption: keep installed app; use Sparkle validation.
- Homebrew/read-only install: preserve preferences and show framework's manual-check error.

### Task 1: Build configuration and pinned framework
Files: scripts/update-config.py, scripts/fetch-sparkle.sh, scripts/build.sh, Package.swift, Tests/UpdateChecks/test_config.py.
Interfaces: update-config.py writes Sparkle plist keys after validating environment; fetch-sparkle.sh prints one verified distribution path.
- [x] Add subprocess tests: missing/invalid key and production HTTP feed fail, valid key produces public-key/feed/daily-check/manual-install plist values; legacy high BUILD_NUMBER does not reorder versions; only isolated test bundle accepts localhost HTTP.
- [x] Run `python3 -m unittest discover -s Tests/UpdateChecks`; observe missing script failures.
- [x] Implement config validation, dependency download with pinned SHA256, framework copying/linking and bundle signing. Pin the same exact package version.
- [x] Run config tests and `scripts/build.sh`.

### Task 2: Application integration
Files: Sources/AgentsNotch/AppUpdates.swift, SettingsUpdates.swift, SettingsSystem.swift, NotchController.swift, main.swift, Sources/NotchCore/UpdateLaunchPolicy.swift, Tests/CoreChecks/UpdateChecks.swift.
Interfaces: AppUpdates.shared.start(), checkForUpdates(_:), automaticallyChecksForUpdates, canCheckForUpdates and errorMessage; UpdateLaunchPolicy.shouldStart(arguments:).
- [x] Add launch-policy checks for normal, fixture, hook and snapshot modes; run scripts/test.sh and observe missing policy failure.
- [x] Implement policy and single observable controller wrapping SPUStandardUpdaterController; observe KVO canCheck and automatic preference changes. Start only on normal launch. Keep downloads disabled.
- [x] Add localized settings section and context-menu action using the same controller; no AppSettings Codable change.
- [x] Run scripts/test.sh and scripts/build.sh; render settings and real Prompts card, inspect images.

### Task 3: Signed release pipeline and end-to-end proof
Files: scripts/appcast.sh, .github/workflows/release.yml, scripts/package.sh, packaging/updates-public-key.txt, docs/self-updates.md, Tests/UpdateChecks/test_appcast.py.
Interfaces: appcast.sh VERSION ARCHIVE_DIRECTORY NOTES_FILE; reads private key from stdin via secret environment or Keychain account, never logs it; produces appcast.xml beside final archive.
- [x] Add real artifact tests rejecting missing ZIP or malformed version; build two isolated test versions with separate bundle ID, feed and signing key.
- [x] Generate appcast via Sparkle with embedded notes; verify enclosure signature against built bundle public key. Publish only after all assets exist, using draft release then publish.
- [x] Document key bootstrap, CI secret, release and Homebrew behavior. Do not change GitHub secrets or publish a release in this task.
- [x] Open the older test app, check feed, install newer app and inspect restarted bundle version; test damaged download with the same app.
- [x] Run full local checks, build, independent fresh reviewer; resolve visible defects. Commit and open PR if checks/review pass; master merge requires owner approval.

## Execution record
User approved design and explicitly requested implementation in a separate worktree. Execute inline; a fresh reviewer checks the final branch. Public signing key can be generated locally; CI private-key setup remains an explicit owner step, never place private material in repository or logs.

## Verification record
See docs/self-update-verification.md. Ruling: production Keychain access and GitHub secret configuration are owner release steps; do not retry cancelled access or publish. Production signing was not verified. Homebrew installation and disconnected-server UI are explicitly unverified; no installed app replacement is included.

## Owner adjustment: local releases
The owner confirmed Actions are unavailable. Replace the release workflow with scripts/prepare-release.sh: clean-source check, stable changelog notes, tests, package, Keychain-signed appcast, rendered Homebrew cask. No tag, push or publication. GitHub private-key secret is no longer required. Targeted subprocess tests cover successful preparation and fail-closed paths; full production preparation still requires owner Keychain access and a release-version decision.
