# House eggs checkpoint

The task is to replace every egg drawn by room/index.html with native NotchCore logic, atlas art and HouseScene2 drawing. Acceptance requires scripts/test.sh, scripts/build.sh, the live proof and an eggs proof to exit zero, with side-by-side images inspected.

The first checkpoint adds opt-in HouseEggs state and tests for calendar boundaries, UFO timing, party expiry and click timers. HouseBehaviour has four small integration points. The scene does not enable this state yet, so the installed behavior is unaffected.

Implementation stopped after two offscreen WebKit export attempts failed to connect to macOS services in the execution sandbox. The bounded retry exited 1 with `export timed out`. No frames were produced. The original atlas was restored; unverified atlas edits were removed. Parts-mode export no longer orders a window, and the export command stages its output before publishing validated files to room/atlas.

Remaining work: complete the page/native logic comparison, export the page's stamps and holiday props, implement HouseScene2Eggs.swift, connect agent looks and pointer handling, apply the fps policy, add fixture-driven eggs-proof.sh and the harness eggs case, inspect the images, then rerun all acceptance checks. Keep the live-ref.js egg stubs until that proof passes with eggs enabled.

No app launch, installation, push, PR, merge or release is authorized.
