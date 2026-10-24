# Native house layouts implementation plan

Goal: draw islands, steps and towers from the page's existing art and geometry in SpriteKit.

The task description is the spec. Keep the current month rule, avoid other workers' scene code where possible, and use only offscreen harnesses. No push, PR, merge, installation or app launch.

- [ ] Parameterize static and live proofs by layout. Keep all current pixel gates; add a three-layout matrix with empty, partial and full stacks, growth, daylight and night samples. Run steps first to expose the missing art.
- [ ] Add logic checks for stacked room part selection and renderer eligibility. Extend page-derived route fixtures to steps. Existing 84 layout fixtures already cover all three geometries; only change geometry or simulation if a fixture demonstrates a gap.
- [ ] Export stacked bathroom, kitchen, roof and project rooms (ground single, ground with floor above, middle, top; all growth/light variants) through parts.js. Export the page's escape back/front/top pieces and preserve agent ordering between them.
- [ ] Select these parts in a new scene extension, with minimal calls from HouseScene2.swift and HouseScene2Movers.swift. Preserve islands' lift and bridges.
- [ ] Run scripts/test.sh, scripts/build.sh, live-proof.sh, scene-proof.sh and layouts-proof.sh. Inspect one side-by-side PNG for each layout. Obtain fresh independent review and commit small verified units.

Review focus: partial final stacks; growth changing a room's cuts; walkers on either stair flight; no lift or yard in stacked styles; sky/city fitting a wider canvas. Stop after two failed fixes of the same problem.

Execution stopped before renderer work: the offscreen WebKit exporter produced no files and logged sandbox-extension failures for `com.apple.webkit.mach-bootstrap` and invalid XPC connections. The first proof was interrupted (130); a bounded diagnostic exited 1 with `export timed out`. No graphics retry after those two attempts.

Prepared: layout parameters, original viewport metadata, a three-layout proof matrix, fail-closed empty-fixture checks and a steps route fixture. The 84 geometry fixtures and six route fixtures reproduce the page in Node. Native renderer eligibility, atlas and shared scene files are unchanged.

Independent review found one P2: canvas dimensions cannot recover the original viewport after ceil/round. The references now export original viewport dimensions, and the harness uses them for layout and sky inputs. No other findings.

Commit attempt blocked: `git add` exited 128 because the sandbox refused `/Users/nikita/Projects/agents-notch/.git/worktrees/house-layouts/index.lock`. HEAD remains `ef6d7382b8413fe1a4d923a4acb50f98ea43d0aa`; preparatory changes are unstaged.

Final checks: `scripts/test.sh` exited 0 (286 core checks, keep-awake, pointer wiring, 16 update tests and nine release-skill tests). `scripts/build.sh` exited 1: Sparkle's Clang module-cache output was denied by the sandbox, followed by `could not build Objective-C module 'Sparkle'`. The changed proof harness passed Swift type-checking (0). Static/live proofs were not retried after the graphics stop; no side-by-side PNGs exist.
