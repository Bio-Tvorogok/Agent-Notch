# Agent Notch promo (Remotion)
Install once: `cd promo && npm install`

Compositions (all in `src/Root.tsx`):
- `Promo` — 1920x1080, ~38 s: `npx remotion render src/index.ts Promo out/agent-notch-promo.mp4 --codec=h264 --crf=20`
- `Vertical` — 1080x1920, ~25 s for X/Shorts/Reels: `npx remotion render src/index.ts Vertical out/agent-notch-vertical.mp4 --codec=h264 --crf=21`
- `Hero` — 9 s seamless loop, rendered at 1280x720: `npx remotion render src/index.ts Hero out/agent-notch-hero.mp4 --codec=h264 --crf=20 --scale=0.6667`, then GIF: `ffmpeg -i out/agent-notch-hero.mp4 -vf "fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" -loop 0 out/agent-notch.gif`
- `Poster` — 1280x640 social card: `npx remotion still src/index.ts Poster out/poster.png`

Copy to the repo: `cp out/agent-notch.gif ../assets/demo.gif && cp out/agent-notch-promo.mp4 ../assets/ && cp out/poster.png ../assets/social-preview.png`

Layout: `src/lib.tsx` (marks, cursor, keycaps, kinetic captions, camera), `src/world.tsx` (MacBook, menu bar, notch wing, screenshot panel),
`src/scenes/` (Opening, Panels, Finale, Terminals), `src/Promo.tsx` (scene chains for Promo and Vertical), `src/Hero.tsx`, `src/Poster.tsx`.
Stage coordinates equal the pixel coordinates of the screenshots in `public/` (rendered by the app from fixture data), so cursor
targets are the button centres measured in those images. Screenshots are shown at 1.0x (1.1x in the vertical cut), never more.
Preview/edit: `npx remotion studio`.
