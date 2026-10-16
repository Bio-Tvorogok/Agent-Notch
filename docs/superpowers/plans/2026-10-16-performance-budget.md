# AN-0.6-9 performance budget

The task card supplies the design and authorizes implementation on this branch.

- Add a file-level FSEvents stream on both configured roots, with a 0.3-second latency and bounded burst coalescing. Treat dropped events, changed roots and stream failure as full-scan requests. Watch existing ancestors so roots created after launch are found.
- Keep the existing scanner API for callers and checks. Add explicit full, changed-path and liveness requests, merging concurrent requests without losing paths. Target Claude parent/subagent logs, live-status files and Codex rollouts. Refresh cached process liveness without rereading session files.
- Replace Store's 1.5-second disk timer with event requests, a 30-second full scan and a live-session-only 1.5-second liveness tick. Preserve status aging and hook expiry.
- Add CoreChecks for targeted discovery, bounded reads, status updates, deletions, liveness and drop recovery. Run the checks before and after implementation.
- Generate 200 sessions and 10,000 archives under /tmp/an06-bench. Compare a common optimized harness built from origin/master and this branch. Measure steady-state idle/load CPU, peak RSS and append-to-snapshot latency; enforce <1%, <5%, <150 MB. Report startup separately and identify harness limits.
- Run test.sh, build.sh and test-app-performance.sh, obtain one independent review, address defects, record evidence in docs/performance.md and commit. No push, merge, install, network, dependencies or changes to user configuration. Existing hidden-panel animation schedules stay unchanged unless measurements justify a change.

Verification uses real temporary log files and real FSEvents delivery. The headless workload is permitted by the card; full-app/UI measurements require a runnable app and are reported separately.
