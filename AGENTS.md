# GitHub Actions billing exception

Owner instruction: ignore GitHub Actions failures caused solely by an account billing lock when deciding whether to merge. Confirm the billing cause in the check annotations, and require the corresponding local checks and independent review to pass. Actual test or build failures still block merging. Keep branch approval requirements; if GitHub refuses the merge, stop and report without bypassing protection.

# Updating the installed app

Before replacing `/Applications/Agent Notch.app`, fetch `origin` and check that the build's source includes the fresh remote default branch. Resolve the default branch through `origin/HEAD`; do not assume the current checkout is up to date. If `git merge-base --is-ancestor origin/HEAD HEAD` fails, integrate the missing changes in the feature branch and verify them before installing.

An older branch passing its own tests does not prove that it preserves the installed app's features. In particular, keep the Prompts card tab, custom sound library, Codex command log and Keep awake control together.

Run `scripts/test.sh` and `scripts/build.sh`. The build runs `scripts/test-app-features.sh` against its compiled NotchCore module; a missing Prompts tab blocks the build. Before installing, also render the Prompts card from a real session log and inspect it. Preserve the user's tab visibility preferences.

After installation, compare the installed executable with the verified artifact, restart the installed copy, and check the real card and Keep awake control. Read `AgentNotchSourceRevision` and `AgentNotchBaseRevision` from the app's Info.plist when diagnosing a version mismatch. A version label such as `0.3.0` alone cannot identify a development build.
