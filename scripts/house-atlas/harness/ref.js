// Runs inside room/index.html (export.swift in "parts" mode) and records the page's OWN frames for the SpriteKit scene proof:
// for every fixture [projects, hour] the whole frame, the sky-only frame (the page's drawBackground), and the numbers the
// Swift side needs to build the same layout (canvas size, PXD, DPR, insets, every room's origin, the mist's day).
// window.__REF_FIXTURES = [[n, hour], ...] is prepended by scripts/house-atlas/scene-proof.sh.
// Run with HOUSE_REF_ONLY=1 (export.swift then expects exactly the files returned in the manifest).
// Output (through webkit.messageHandlers.out, "check/" goes to the check dir): ref-n{n}-h{hour}.png / -sky.png / .json
(() => {
  'use strict';
  const O = window.__HOUSE_EXPORT, post = (path, data) => window.webkit.messageHandlers.out.postMessage({ path, data });
  const T = 100000; // the moment every frame is drawn at (the clouds, the mist's wisps)
  setActive(false);
  weather = 'clear';
  updateResidents = () => {}; updateErrands = () => {}; updateScenes = () => {}; eggStep = () => {};
  eggSky = () => {}; eggOver = () => {}; eggItems = () => {}; drawSeason = () => {};
  METEORS.next = Infinity; METEORS.list = [];
  room.setInsets(O.insets);
  sprites.clear();
  const NAMES = ['Agent-Notch', 'hexhaven', 'world', 't2', 'decide', 'trailby', 'arena', 'confetti', 'hall', 'lessons', 'life-os', 'screens', 'tank-hero', 'av-wt'];
  function fixture(projects) {
    for (const r of rooms) r.label.remove();
    rooms.length = 0; roomByKey.clear(); sprites.clear(); links = []; LIFT = null; PLAN = { hulls: [] };
    ensureRoom('__bath', 'Ванная', 'bath'); ensureRoom('__kitchen', 'Кухня', 'kitchen'); ensureRoom('__roof', 'Крыша', 'roof');
    for (const [n, th] of projects) ensureRoom('p:' + n, n, th || undefined);
    for (const r of rooms) { r.born = -1e9; r.drop = 0; r.cache = null; }
  }
  const out = [], files = [];
  for (const [n, hour] of window.__REF_FIXTURES) {
    fixture(NAMES.slice(0, n).map(x => [x, null]));
    const bgc = document.createElement('canvas'); bgc.width = cv.width; bgc.height = cv.height; const realBG = drawBackground;
    drawBackground = (t, d) => { realBG(t, d); bgc.getContext('2d').drawImage(cv, 0, 0); }; // the sky as the page's own frame drew it
    fixedHour = hour; try { frame(T); } finally { drawBackground = realBG; }
    const d = now(), tag = `n${n}-h${hour}`;
    const day = Math.floor((d - new Date(d.getFullYear(), 0, 1)) / 864e5);
    const meta = { n, hour, W: cv.width, H: cv.height, PXD, DPR, insets: INSETS, day, mist: mistAmount(d), T,
      rooms: rooms.map(r => ({ key: r.key, ox: r.ox, oy: r.oy, theme: Object.keys(THEMES).find(k => THEMES[k] === r.theme), NX: r.NX, NY: r.NY, floor: r.floor, tower: r.tower, growth: r.theme.shared ? 0 : growthLevel(r) })),
      world: worldFrame(), links: links.map(L => L.id) };
    for (const [f, data] of [['.png', cv.toDataURL('image/png')], ['-sky.png', bgc.toDataURL('image/png')], ['.json', JSON.stringify(meta)]]) {
      post('check/ref-' + tag + f, data); files.push('check/ref-' + tag + f);
    }
    out.push(tag);
  }
  return JSON.stringify({ files, summary: 'ref frames: ' + out.join(' ') });
})();
