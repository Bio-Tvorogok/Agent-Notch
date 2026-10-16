# AN-0.6-9 performance budget

The limits are idle CPU <1% of one core, active CPU <5%, and RSS <150 MB with 200 live-looking sessions and 10,000 archived logs. A successful fallback benchmark does not establish live FSEvents delivery or latency.

## Watch and scan cadence

File-level FSEvents use 0.3s latency and a bounded 0.1s batch window. Event paths retain the canonical spelling supplied by FSEvents, including `/private/tmp` and `/private/var`. Scanner keys and interests use `ConfigRoots.physical`.

Existing log trees stay on separate file-event roots. Missing config/log roots use their nearest existing ancestor on a directory-event stream, without `kFSEventStreamCreateFlagFileEvents`. Symlink entries also get a directory-level parent watch. Creating a missing root or replacing a symlink refreshes the watch plan. Claude interests cover only the config root itself, `projects/` and `sessions/`; events under `todos`, `debug`, `history` and `file-history` are discarded before subtree-rescan flags are interpreted. Lost-event flags still request a full scan.

Codex exec stdout interests are exact log paths, even when stdout lives directly in the home directory. An underlying stream may watch the containing directory, but sibling files do not join the interest set. Process events are coalesced into a trailing refresh, with at least 1.5s between refreshes. Exec and rollout discovery share an argv/environment cache keyed by PID and process start time. Exit, PID reuse and observed exec invalidate it; unchanged PIDs do not reread `KERN_PROCARGS2`. Process names remain cached between repairs.

With working file streams, a 1.5s tick checks cached liveness while agents or hook requests are active. Once all rows are finished, a one-shot timer runs at their next retention expiry. If any file stream fails to start, the 1.5s timer instead performs full scans, including when no agents are live. The 30s safety scan retries stream startup and repairs process registrations. Watch recreation is gated by changed paths/roots, so a failed startup callback cannot cause a tight retry loop.

## Reproduce outside the sandbox

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" NOTCH_REQUIRE_FSEVENTS=1 sh scripts/test.sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" BENCH_BASE=origin/master sh scripts/bench-sessions.sh --duration 40
```

The first command requires the real `/tmp` FileWatcher check to start its streams and deliver all three JSONL paths within 2s: a new Claude project, a new Codex date tree, and exec stdout. Without `NOTCH_REQUIRE_FSEVENTS=1`, denied startup is explicitly reported as NOT verified, while canonical-path and other core checks still run.

The benchmark makes no network requests and does not install or launch the app. It archives the local baseline and writes fixtures, binaries and results under `/tmp/an06-bench`; reruns replace that directory's benchmark files. Each fixture has 100 Claude logs with live-status JSON, 100 Codex rollouts, and 5,000 archived files for each vendor. Claude status files use the controller PID; this measures 200 session records rather than 200 agent runtimes. Startup must publish 200 working rows.

After a 3s settle, each binary runs 40s idle and 40s at 20 appends/s, rotating over all 200 logs every 10s. A 2s drain follows. CPU is `getrusage` CPU-time delta divided by wall time; 100% means one core. RSS is peak `ru_maxrss`, in decimal MB, including startup. Both variants inspect real host processes; exec log reads are restricted to the fixture. The event variant enables production file/process watchers and uses full 1.5s scans when stream startup fails, matching Store's fallback cadence.

Timestamp markers in session titles measure append-to-snapshot latency. Exit 0 requires the resource limits and at least 90% marker delivery. Always inspect `after.event_stream_started` in `results.json`: `false` labels the result as fallback, even when the delivery check passes. The measurement excludes SwiftUI, usage scans, card readers, hooks, sound and window publication. No latency budget was specified.

## Measurements

Measured on 16 October 2026, arm64, with the 40s phases above. Baseline: local `origin/master` at `d2af2908cc24196e6d96be5d8fe110cf4cf1ae44`; no fetch was made because network access was forbidden. **No live FSEvents measurement was obtained.** `after.event_stream_started` was `false`.

| Metric | master polling | branch fallback (full scans every 1.5s) | Budget |
|---|---:|---:|---:|
| Idle CPU, one core | 1.692% | 7.304% | <1% |
| Append-load CPU, one core | 1.640% | 7.856% | <5% |
| Peak RSS, decimal MB | 35.996 | 41.632 | <150 |
| Snapshot latency p50 / p95 / max, ms | 774.9 / 1435.4 / 1574.5 | 745.1 / 1441.7 / 1530.2 | reported |
| Observed append markers | 800/800 | 800/800 | >=720/800 |
| Published snapshots | 57 | 68 | reported |

Benchmark exit: **1**. Fallback delivery and RSS pass; both fallback CPU limits fail. The earlier pre-review fallback run delivered only 200/800 markers. Restoring full 1.5s fallback scans recovers delivery but does not establish the live event CPU budget. Process churn is bounded by a deterministic cadence check; this workload does not isolate a controlled 51-node-process churn test.

The binaries saw 860 / 871 host processes. Measured core/harness source SHA-256: `5ef1f95dfae68ac51ab336053aea730efce5d3a4ab725eabba17df5586cb5d2c`. JSON: `/tmp/an06-bench/results.json`; output: `/tmp/an06-t9-benchmark.log`. These are temporary local artifacts.

## Verification limits

The sandbox denies `FSEventStreamStart`, so live delivery must be rerun outside it. A direct probe against the pre-fix source reproduced `/private/tmp` being rewritten to `/tmp`; the revised source preserves it. Core checks also cover process batching, cache reuse/invalidation, watch roots/interests and the next finished-row expiry.

The cached Sparkle archive passed its checksum, and `scripts/build.sh` compiled NotchCore, then exited 1 at `Theme.swift`'s SwiftUI `@Entry` macro: `sandbox-exec: sandbox_apply: Operation not permitted`. There is no fresh app executable to inspect. Nothing was installed or published; user configuration and `/Applications` were not changed.

## Check results

- `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" sh scripts/test.sh`: exit 0; 239 core checks, Keep awake checks, 16 updater tests and eight release-skill tests. The live watcher check explicitly skipped denied startup; its existing canonical-path check passed.
- Pre-fix canonical-path probe: exit 1; same probe against revised sources: exit 0.
- `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" sh scripts/test-app-features.sh`: exit 0; Prompts tab present in the newly compiled module.
- `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" sh scripts/build.sh`: exit 1; sandboxed SwiftUI macro failure described above.
- `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" BENCH_BASE=origin/master sh scripts/bench-sessions.sh --duration 40`: exit 1; fallback results above.
- Store Swift parse, Python syntax, shell syntax and `git diff --check`: exit 0.
- Fresh independent source review: no open defects after correcting a failed-start retry loop. The reviewer did not run the app or live FSEvents.

Verified through temporary session files, compiled core/module checks and the headless fallback benchmark. NOT verified on a running FSEvents stream or app UI: stream startup and the SwiftUI macro plugin were denied by the sandbox.
