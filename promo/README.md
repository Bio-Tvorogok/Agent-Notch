# Agent Notch promo (Remotion)
Install once: `cd promo && npm install`
Promo video (1920x1080, 32 s): `npx remotion render src/index.ts Promo out/agent-notch-promo.mp4 --codec=h264 --crf=20`
Hero cut: `npx remotion render src/index.ts Hero out/agent-notch-hero.mp4 --codec=h264 --crf=20 --scale=0.6667`, then GIF: `ffmpeg -i out/agent-notch-hero.mp4 -vf "fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" -loop 0 out/agent-notch.gif`
Poster (1280x640): `npx remotion still src/index.ts Poster out/poster.png`
Preview/edit: `npx remotion studio`; screenshots live in `public/`, timings in `src/Promo.tsx` and `src/Hero.tsx`.
