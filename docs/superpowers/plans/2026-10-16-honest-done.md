# AN-0.6-7 implementation plan

Goal: Show helper activity as work; require completion evidence; summarize the session's own plan and commit.

Constraints: Swift, macOS 14+, existing Loc EN/RU, no dependencies or network calls. Work and commit on feat/0.6-t7. No push, merge, tags, installation, or user config writes.

1. Add CoreChecks and log fixtures for silent and interrupted sessions, two live helpers, child hooks, incomplete plans, and commit output whose hash differs from repository HEAD. Run them before implementation and against origin/master.
2. Update SessionLog completion rules, helper aggregation in Tree, and hook overlays. Preserve explicit human requests; do not let child completion end a parent. Suppress interrupted completion notifications.
3. Parse git commit output through DetailReader and include remaining plan counts in FinishSummary. Remove repository HEAD lookup. Keep toast text readable.
4. Add a fixture snapshot command for the parent row and toast in EN/RU. Run scripts/test.sh and scripts/build.sh, inspect screenshots if rendering is available, and request a fresh independent review. Commit verified changes.

Review focus: stale Stop versus later log activity; child hooks without an agent id; explicit parent asks while helpers run; abort/process exit without success; failed or uncorrelated commit output.

Verification: Regression checks fail on the old core, then pass on this branch. Both scripts must exit 0, subject to the task's sandbox exception. Screenshots go to /tmp/an06-t7-shots; if blocked, return exact lead commands. No release or installed-app verification is in scope.

Baseline proof: `origin/master` resolved locally to `d2af2908cc24196e6d96be5d8fe110cf4cf1ae44`, also this task's starting HEAD. Archived it under `.build/master-regression`, copied the first compatible regression checks and fixtures into that copy, and ran its `scripts/test.sh`. It exited 1 with 14 assertions failing across silence, interrupted exit, helpers, child hooks and both toast readers. No branch checkout or history change was used.

The app build uses the cached pinned Sparkle archive; no download is needed. In this sandbox, the existing `@Entry` in `Theme.swift:279` fails because `swift-plugin-server` cannot apply its sandbox. The production views therefore still need the lead's build and screenshot check.

Run from this checkout outside the restricted sandbox:

```sh
mkdir -p /tmp/an06-t7-fixtures
TMPDIR=/tmp/an06-t7-fixtures CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" sh scripts/test.sh
TMPDIR=/tmp/an06-t7-fixtures CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" sh scripts/build.sh
CFFIXED_USER_HOME=/tmp/an06-t7-fixtures build/AgentsNotch.app/Contents/MacOS/AgentsNotch --snapshot-honest-done /tmp/an06-t7-shots
```

Inspect `helpers-en.png`, `helpers-ru.png`, `toast-en.png` and `toast-ru.png`. The parent must remain working with two helpers; the toast must show two of seven items left and commit `a1b2c3d` from the fixture log. The snapshot command exits before hooks, monitoring or updates start.
