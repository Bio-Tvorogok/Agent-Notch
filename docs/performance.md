# AN-0.6-9 performance budget

The owner’s limits are idle CPU <1% of one core, active CPU <5%, and RSS <150 MB, with 200 live-looking sessions and 10,000 archived logs. A full safety scan runs every 30 seconds.

Store now uses file-level FSEvents with 0.3s latency and a bounded 0.1s coalescing window. File and directory events discover only the affected paths; live-status JSON is cached between events. A 1.5s tick checks cached PIDs and ages statuses while live sessions or hook requests exist. It stops when everything is finished. Dropped events, root changes and stream startup failure request a full scan. The safety tick retries a failed stream.

Codex exec stdout may live outside either config root. Kernel fork/exec/exit sources discover these streams, and their parent directories join the file watch. Process names are cached; unrelated process changes do not publish scanner snapshots. Registration reconciles the PID set twice, and the safety tick repairs it. This preserves detection of runs lasting at least the old discovery interval; it does not promise lossless capture of subsecond processes. Exit notifications drain stdout before removing its watch.

Configured roots and independently symlinked projects/status directories are watched together. Physical paths use `realpath` because Foundation can spell a path `/tmp` while enumeration and FSEvents report `/private/tmp`. Missing roots use an existing ancestor, unrelated paths are filtered, and the watch narrows as roots appear. Requests arriving during a scan are merged; a queued full rescan cannot be downgraded by another request.

## Reproduce

```sh
sh scripts/bench-sessions.sh
# An alternative local baseline, without fetching:
BENCH_BASE=origin/master sh scripts/bench-sessions.sh --duration 40
```

The script builds the same optimized Swift harness against the local `origin/master` snapshot and the working tree. It makes no network requests and does not launch or replace the installed app. Everything it generates is under `/tmp/an06-bench`; a rerun replaces its own fixtures and baseline source directory. The controller rejects fixture roots outside `/tmp/an06-*`.

Each fixture has 100 Claude logs with live-status JSON, 100 Codex rollouts, and 5,000 archived files for each vendor. Archived files have old mtimes and small synthetic contents. Claude live-status files use the controller’s PID; this measures 200 session records, not 200 separate agent runtimes. Codex sessions begin with `task_started`. Startup must yield exactly 200 working rows.

After a three-second settle, each process runs 40s without fixture writes and 40s at 20 appends/s, rotating through all 200 logs every ten seconds. A final two-second drain accommodates the old polling interval. CPU comes from `getrusage` CPU-time deltas divided by elapsed wall time; 100% means one core. RSS is `ru_maxrss`, in decimal MB, and includes startup. Sampling uses stdin rather than spawning `ps`. Unrelated host process activity is still observed by the process watcher.

Both harnesses run production process inspection. Exec streams are filtered to the fixture so no real user log is read. The event variant enables ProcessWatcher and FileWatcher. Timestamp markers in published session titles measure append-to-snapshot latency. Besides the owner’s resource limits, the script requires at least 90% of markers to be observed; otherwise a silent watcher could pass simply by doing no work. No owner latency threshold was supplied. Results include p50, p95 and maximum latency, stream startup status, process visibility, and a hash of the measured core/harness sources. Exit 0 requires the event variant’s resource limits and delivery check to pass.

## Measurements

Measured on 16 October 2026, arm64. Baseline is the local `origin/master` at `d2af2908cc24196e6d96be5d8fe110cf4cf1ae44`; it was not fetched because this task forbids network calls. The working-tree result and exact source hash follow below.

| Metric | master | branch (fallback) | Budget |
|---|---:|---:|---:|
| Idle CPU, one core | 1.651% | 0.601% | <1% |
| Append-load CPU, one core | 1.611% | 0.568% | <5% |
| Peak RSS, decimal MB | 29.917 | 32.555 | <150 |
| Snapshot latency p50 / p95 / max, ms | 780.0 / 1438.0 / 1583.7 | 5264.1 / 9765.8 / 10208.5 | reported |
| Observed append markers | 800/800 | 200/800 | >=720/800 validity check |
| Published snapshots | 57 | 61 | reported |

The branch meets the resource limits in fallback mode, but the delivery check fails: 25% of markers were observed, a gap of 520 markers to the 90% validity threshold. Normal FSEvents delivery remains NOT verified. Benchmark exit code: 1. The final process-watcher filtering reduced measured idle CPU from the first version’s 4.844% to 0.601%.

The final run saw 695 / 697 host processes. Measured source SHA-256: `df24f2525aa91f112ab4fb4d94280d89104bafb087bd5f77f4aa7a63aeed01b3`. Full JSON from this run: `/tmp/an06-bench/results.json`; console output: `/tmp/an06-benchmark-release.log`.

## Verification limits

The sandbox probe returned `FSEventStreamStart == false`. The event variant therefore measures the recovery path. These results cannot establish successful FSEvents delivery or its normal latency, even if the CPU/RSS limits pass. Re-run the benchmark outside this sandbox to establish the event budget.

The first measured process-watcher version published 619 snapshots and used 4.844% idle CPU because unrelated process events repeatedly triggered full process inspection and snapshot construction. That measurement led to candidate filtering and cached names; the results below use the filtered version.

This is a headless scanner benchmark. It excludes SwiftUI, UsageModel’s spend/context scans, card readers, hook sockets, sound playback and window publication. Hidden list timelines already use the paused SurfaceSchedule. No animation, visual, setting, localization or approval behavior was changed. Hidden-wing CPU was not profiled because the app could not be built here.

`build.sh` stopped before compilation because the pinned Sparkle archive was absent. Downloads were blocked with a local curl stub to honor the no-network constraint (exit 69). This was a missing offline dependency, not a SwiftUI compiler result. The final core sources compiled in `test.sh`. `test-app-performance.sh` passed its card publication/reopening checks, then failed at SwiftUI’s `@Entry` expansion with `sandbox_apply: Operation not permitted` (exit 1). The separate timestamp performance check passed.

Supply the pinned Sparkle 2.10.0 archive offline at `.build/sparkle/2.10.0/archive.tar.xz`, then run outside this sandbox:

```sh
sh scripts/test.sh
sh scripts/build.sh
sh scripts/test-app-performance.sh
sh scripts/bench-sessions.sh
build/AgentsNotch.app/Contents/MacOS/AgentsNotch --snapshot /tmp/an06-performance
```

The last command is a fixture screenshot command for the lead; it was not run here. There is no built UI artifact to inspect. Nothing was installed, pushed, merged, tagged or published. User configuration and `/Applications` were not touched.

## Check results

- `sh scripts/test.sh`: exit 0; 233 core checks, Keep awake checks, 16 updater tests and eight release-skill tests. The seven added watcher checks cover path discovery, liveness without disk reads, drop flags, queued full-rescan preservation, symlink remapping, and external exec discovery/exit draining.
- `sh scripts/build.sh` with downloads blocked: exit 69, pinned Sparkle archive unavailable offline.
- `sh scripts/test-app-performance.sh`: exit 1, sandboxed SwiftUI macro failure after card checks passed.
- Separate `date-performance-checks`: exit 0; 20,000 timestamps took 1009.8ms with the legacy formatter; a complete optimized JSONL scan took 66.9ms.
- `sh scripts/bench-sessions.sh`: exit 1; resource limits pass in fallback mode, delivery validity fails as described above.
- Python syntax check, shell syntax check, Store Swift parse and `git diff --check`: exit 0.
- One independent reviewer checked the final source changes and reported no remaining P0, P1 or serious P2 findings. The reviewer did not run the app or repeat the measurements.

Verified on temporary session files through the compiled core checks and headless benchmark. NOT verified on the app UI or a running FSEvents stream: offline Sparkle dependency and sandbox restrictions block those checks.
