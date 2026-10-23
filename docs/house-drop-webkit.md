# Dropping WebKit from the house

Owner decision: SpriteKit is the only renderer. No setting falls back to WebKit. `room/index.html` stays in the repo as the art
source and test oracle (`scripts/house-atlas/export.swift` renders it at build time) and never ships in a bundle.
Line numbers are for the tree this branch started from (`ef6d738`).

## Dependencies and what replaces them

| # | Where | What | Replacement | Status |
|---|---|---|---|---|
| 1 | `Sources/AgentsNotch/RoomWallpaper.swift:7,16,94-106,114,418,438-458,481-491,541-547,673-698` | `import WebKit`, `WKWebView` host, `MessageProxy` JS bridge, `push()`, `syncInsets()`, `received()`, `didFinish` | `startSpriteKit` only; the bridge carried `growth`, `jsError`, `tip`, `open`, all of which the scene already delivers by callbacks (`onDelivered`, `onTip`, `onOpen`) | this branch, commit a |
| 2 | `RoomWallpaper.swift:220-223` | `houseRenderer` default and `HOUSE_RENDERER` env | deleted | this branch, commit a |
| 3 | `RoomWallpaper.swift:80-92,365-397` | `forceWeb`, `fallBackToPage`, season/layout gate (`HouseSpriteKitRules`) | atlas failure or a second stall stops the wallpaper (logged); a too-short screen waits for another geometry | this branch, commit a |
| 4 | `RoomWallpaper.swift:659-670` | `page` finds `room/index.html` | `atlasDirectory` finds `room/atlas`; `page` remains only for RoomScreens | this branch, commit a |
| 5 | `Sources/AgentsNotch/HouseScene2Growth.swift:5,60-70` | page `localStorage` (`room.growth.v1`) seeded and merged through the bridge | native `houseGrowth.v1` is the only store; one-time import of the page's saved count from WebKit's `localstorage.sqlite3` | this branch, commit b |
| 6 | `Sources/AgentNotchSaver/HouseSaverView.swift:4,15,59,118-261` | `WKWebView` fallback, `WKNavigationDelegate`, occlusion hack | `SaverSpriteHouse` only; on failure a plain dark frame | this branch, commit c |
| 7 | `Sources/AgentsNotch/RoomSaverFeed.swift:70` | `renderer` field depends on `houseRenderer` | always `"spritekit"` (an older installed saver still reads it) | this branch, commit a |
| 8 | `scripts/build.sh:36` | saver links `-framework WebKit` | dropped | this branch, commit d |
| 9 | `scripts/build.sh:38` (saver), `:88` (app) | `cp room/index.html` into both bundles | removed; `room/atlas/parts.json` + `parts-*.png` still copied (`HouseScene2.load` reads only those) | this branch, commit d |
| 10 | `Sources/AgentsNotch/RoomScreens.swift:3,52,73,81,127` and `:24` (`web?.evaluateJavaScript`), `:29` (`Self.page`) | extra-screen windows in `WKWebView` | SpriteKit extra screen, `HouseScene2.extraScreen` (already exists, proven by `extra-proof.sh`) | **blocked** on `claude/house-port-interact` |
| 11 | `Sources/AgentsNotch/RoomWallpaperLegacyWeb.swift` | `web` stub (always nil) so RoomScreens compiles | delete with RoomScreens | with #10 |

## Removal order

1. Docs (this file).
2. Wallpaper: SpriteKit only (1-4, 7).
3. Growth: native only, import once (5).
4. Saver: SpriteKit only (6).
5. Build: stop copying `room/index.html`, drop the saver's WebKit link (8, 9).
6. When `claude/house-port-interact` lands the SpriteKit extra screens: delete `RoomScreens.swift`'s WKWebView class,
   `RoomWallpaperLegacyWeb.swift`, `RoomWallpaper.page`, `pushRoomConfig` (10, 11). Then `otool -L` shows no WebKit at all.

## Until step 6

- Extra screens are not created from the app bundle: `RoomWallpaper.page` looks for `room/index.html`, which the bundle no longer
  has. A `swift run` from the repo still finds it. Multi-screen users lose the extra-screen houses until #10 lands.
- The app binary still links WebKit through RoomScreens.

## Parity gaps (not removed by this work)

- The atlas draws the islands layout in autumn only. `HouseSpriteKitRules` used to send other layouts and months to the page.
  Now the autumn islands house is drawn regardless; the `layout` setting and the season are ignored until the atlas is exported
  for them.
- Page-only features without a SpriteKit counterpart are gone with the page: `room.backdrop` and the `room.egg.*` localStorage keys.
