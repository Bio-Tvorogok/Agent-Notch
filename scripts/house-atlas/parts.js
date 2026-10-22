// Runs inside room/index.html (injected by export.swift in "parts" mode) and cuts the house into REUSABLE PARTS:
// every sprite is positioned against its own origin (a room's iso(0,0,0), the bathroom's origin for the village's
// bridges, stairs and lift, an anchor for a Clawd) instead of the screen, so a renderer can place them for any layout.
// Nothing here draws art of its own: every pixel comes from the page's own functions, wrapped so that each piece they
// draw lands in its own layer. Light: the page tints colours by the clock (lit()/emi() over AMBK), so every part is cut
// once per AMBK row ("bucket") and the renderer cross-fades the two buckets around the hour.
// Output: files streamed to Swift with webkit.messageHandlers.out (parts.json, parts-N.png, check/*.png).
(() => {
  'use strict';
  const O = window.__HOUSE_EXPORT, post = (path, data) => window.webkit.messageHandlers.out.postMessage({ path, data });
  const T = 100000; // the moment every part is cut at (and every reference frame drawn at)
  const LOG = []; const log = (...a) => LOG.push(a.join(' '));
  const only = new Set((O.only || '').split(',').filter(Boolean)); // dev: restrict the stages
  const want = s => !only.size || only.has(s);

  // ---------- quiet page: no loop, no residents, no eggs, no seasons' particles, clear weather ----------
  setActive(false);
  weather = 'clear';
  updateResidents = () => {}; updateErrands = () => {}; updateScenes = () => {}; eggStep = () => {};
  eggSky = () => {}; eggOver = () => {}; eggItems = () => {}; drawSeason = () => {};
  METEORS.next = Infinity; METEORS.list = [];
  room.setInsets(O.insets);
  sprites.clear();

  const BUCKETS = AMBK.slice(0, 9).map(r => r[0]); // 0 5 6.5 8.5 12 16.5 18.5 20 21.5 (row 24 repeats row 0)
  const hourDate = h => { const d = new Date(); d.setHours(Math.floor(h), Math.floor((h % 1) * 60), Math.floor((h * 3600) % 60), 0); return d; };
  const setHour = h => { fixedHour = h; setTime(h); return hourDate(h); };

  // ---------- a fixture: the page's own layout for a list of projects ----------
  function fixture(projects) { // [[name, themeKey|null], ...]
    for (const r of rooms) r.label.remove();
    rooms.length = 0; roomByKey.clear(); sprites.clear(); links = []; LIFT = null; PLAN = { hulls: [] };
    ensureRoom('__bath', 'Ванная', 'bath'); ensureRoom('__kitchen', 'Кухня', 'kitchen'); ensureRoom('__roof', 'Крыша', 'roof');
    for (const [n, th] of projects) ensureRoom('p:' + n, n, th || undefined);
    for (const r of rooms) { r.born = -1e9; r.drop = 0; r.cache = null; }
  }
  const NAMES = ['Agent-Notch', 'hexhaven', 'world', 't2', 'decide', 'trailby', 'arena', 'confetti', 'hall', 'lessons', 'life-os', 'screens', 'tank-hero', 'av-wt'];
  const natural = n => NAMES.slice(0, n).map(x => [x, null]); // the page's own theme choice by name
  const themeKeys = Object.keys(THEMES).filter(k => !THEMES[k].shared);
  const themeOf = r => Object.keys(THEMES).find(k => THEMES[k] === r.theme);

  // ---------- capture machinery: a proxied canvas that knows when something was drawn on it ----------
  const CW = 1000, CH = 1400, OX = 500, OY = 700, WOX = 500, WOY = 1000; // room origin and the bathroom's (world) origin on it
  const cap = document.createElement('canvas'); cap.width = CW; cap.height = CH;
  const raw = cap.getContext('2d', { willReadFrequently: true });
  let dirty = false;
  const DRAWS = new Set(['fillRect', 'drawImage', 'fill', 'stroke', 'strokeRect', 'fillText', 'putImageData']);
  const watch = ctx => new Proxy(ctx, {
    get(t, p) { const v = t[p]; return typeof v === 'function' ? (...a) => { if (DRAWS.has(p)) dirty = true; return v.apply(t, a); } : v; },
    set(t, p, v) { t[p] = v; return true; },
  });
  const cx = watch(raw);
  const reset = c => { c.setTransform(1, 0, 0, 1, 0, 0); c.globalAlpha = 1; c.globalCompositeOperation = 'source-over'; c.clearRect(0, 0, c.canvas.width, c.canvas.height); };
  // the drawn part of the capture canvas, cut out: { img, x, y } in canvas pixels, or null
  function cropRaw() {
    const w = raw.canvas.width, h = raw.canvas.height, px = raw.getImageData(0, 0, w, h).data;
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0, i = y * w * 4 + 3; x < w; x++, i += 4) if (px[i]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 < 0) return null;
    const img = document.createElement('canvas'); img.width = x1 - x0 + 1; img.height = y1 - y0 + 1;
    img.getContext('2d').drawImage(raw.canvas, x0, y0, img.width, img.height, 0, 0, img.width, img.height);
    return { img, x: x0, y: y0 };
  }
  const withG = (ctx, fn) => { const saved = [g, R]; g = ctx; try { return fn(); } finally { [g, R] = saved; } };

  // ---------- sprites: every distinct image once, packed at the end ----------
  const frames = [], byHash = new Map();
  function addSprite(img) {
    const w = img.width, h = img.height, d = img.getContext('2d').getImageData(0, 0, w, h).data;
    let a = 2166136261, b = 0;
    for (let i = 0; i < d.length; i++) { a = Math.imul(a ^ d[i], 16777619) >>> 0; b = (b + d[i] * (i % 251 + 1)) >>> 0; }
    const key = w + 'x' + h + ':' + a + ':' + b;
    let id = byHash.get(key);
    if (id === undefined) { id = frames.length; frames.push({ img, w, h }); byHash.set(key, id); }
    return id;
  }
  // the unit glow of a colour and radius (what glow() stamps at alpha k): it is the page's own gradient image
  const glowIds = new Map();
  function glowSprite(color, rad) {
    const r = Math.max(1, Math.round(rad)), key = color + '|' + r;
    let id = glowIds.get(key);
    if (id === undefined) {
      const tmp = document.createElement('canvas'); tmp.width = tmp.height = 4;
      withG(tmp.getContext('2d'), () => real.glow(8, 8, rad, color, 0)); // fills GLOWS for this colour and radius
      id = addSprite(GLOWS.get(key)); glowIds.set(key, id);
    }
    return id;
  }
  const real = { blit, drawLifts, drawSign, glow, bakeWorld, drawLink };
  const depthOf = it => typeof it.depth === 'function' ? it.depth() : it.depth;
  const round1 = v => Math.round(v * 1000) / 1000;

  // ---------- one room, cut the way drawRoom draws it: back layer, items by depth, lights, sign, lift slice ----------
  // Offsets are art pixels from iso(0, 0, 0) of the room. kind: back (under everything: shell A, window glass, shell B, clock,
  // sunlight), item (depth = the x+y the page sorts by), lift (the room's slice of the lift goes here), sign (the post or
  // the plaque is drawn by the renderer), and overlay (drawn after every room: the porch landing).
  function cutRoom(r) {
    const saved = [r.ox, r.oy, r.drop, R, g]; r.ox = OX; r.oy = OY; r.drop = 0;
    const cache = buildCache(r), byImage = new Map();
    for (const it of cache.items) if (!it.dyn) byImage.set(it.baked, it);
    const dynDraw = new Map(), layers = [], lights = [];
    let cur = { kind: 'back', depth: null }, inItem = false;
    const flush = () => {
      if (!dirty) return; dirty = false;
      const cut = cropRaw(); reset(raw); if (!cut) return;
      layers.push({ kind: cur.kind, depth: cur.depth, dyn: cur.dyn || undefined, sprite: addSprite(cut.img), x: cut.x - OX, y: cut.y - OY });
    };
    for (const it of cache.items) if (it.dyn) { const f = it.draw; dynDraw.set(it, f);
      it.draw = () => { flush(); cur = { kind: 'item', depth: depthOf(it), dyn: true }; inItem = true; f(); flush(); inItem = false; }; }
    blit = b => {
      if (!b) return; flush();
      const it = byImage.get(b); if (it) cur = { kind: 'item', depth: depthOf(it) };
      layers.push({ kind: cur.kind, depth: cur.depth, sprite: addSprite(b.img), x: b.dx, y: b.dy });
    };
    drawSign = rr => { flush(); layers.push({ kind: 'sign', depth: rr.floor === 0 ? round1(rr.NX + rr.NY + 1.6) : null, variant: rr.floor === 0 ? 'post' : 'plaque' }); };
    drawLifts = (tt, f) => { flush(); layers.push({ kind: 'lift', floor: f, depth: round1(LIFT.x0 + LIFT.y1 - LIFT.fl[f].yoff) }); };
    glow = (x, y, rad, color, k) => {
      if (inItem) return real.glow(x, y, rad, color, k);
      flush(); lights.push({ sprite: glowSprite(color, rad), r: Math.max(1, Math.round(rad)), x: x - OX, y: y - OY, k: round1(k * 1000) / 1000 });
    };
    reset(raw); dirty = false; g = cx;
    try { drawRoom(r, T, hourDate(fixedHour)); flush(); }
    finally {
      Object.assign(window, { blit: real.blit, drawSign: real.drawSign, drawLifts: real.drawLifts, glow: real.glow });
      for (const [it, f] of dynDraw) it.draw = f;
      [r.ox, r.oy, r.drop, R, g] = saved;
    }
    const overlay = cache.escTop ? [{ sprite: addSprite(cache.escTop.img), x: cache.escTop.dx, y: cache.escTop.dy }] : [];
    return { layers, lights, overlay };
  }
  const roomMeta = r => ({ theme: themeOf(r), NX: r.NX, NY: r.NY, floor: r.floor, tower: r.tower, hub: r.theme.hub, lowH: r.theme.lowH, shared: !!r.theme.shared, open: !!r.theme.open });

  const result = { version: 2, S, WH, SLAB, FLOOR_STEP, buckets: BUCKETS, ambk: AMBK.slice(0, 9).map(r => ({ hour: r[0], amb: r[1], sky: [r[2], r[3]], dark: r[4] })) };
  const parts = result.rooms = {};
  if (want('rooms')) {
    const jobs = []; // [variant id, fixture projects, room key]
    fixture(natural(1)); jobs.push({ id: 'bath/g0', fx: natural(1), key: '__bath' }, { id: 'kitchen', fx: natural(1), key: '__kitchen' }, { id: 'roof', fx: natural(1), key: '__roof' });
    jobs.push({ id: 'bath/g1', fx: natural(2), key: '__bath' }, { id: 'bath/g2', fx: natural(3), key: '__bath' });
    for (const th of themeKeys) { const fx = [[NAMES[0], th], [NAMES[1], th]]; jobs.push({ id: th + '/tower', fx, key: 'p:' + NAMES[0] }, { id: th + '/island', fx, key: 'p:' + NAMES[1] }); }
    const byFx = new Map();
    for (const j of jobs) { const k = JSON.stringify(j.fx); if (!byFx.has(k)) byFx.set(k, []); byFx.get(k).push(j); }
    for (const [, list] of byFx) {
      fixture(list[0].fx);
      for (const j of list) { const r = roomByKey.get(j.key); parts[j.id] = { ...roomMeta(r), buckets: [] }; }
      BUCKETS.forEach((h, bi) => {
        setHour(h);
        for (const j of list) { const r = roomByKey.get(j.key); r.cache = null; parts[j.id].buckets[bi] = cutRoom(r); }
      });
    }
    log('rooms', Object.keys(parts).length);
  }

  // ---------- the village: links (bridges, stairs) and the lift, in the bathroom's frame ----------
  // Their shapes depend on the layout, and the layout (islandPlan) depends only on how many projects there are: every island is
  // 10x8 whatever its theme, and a new project never moves the earlier ones. So the links that occur for 0..14 projects are one
  // list of 13 concrete links (links[i] is the same link for every count that has it), cut exactly as the page draws them
  // (the pixel phase of a plank or a step depends on the fractional tile position, so a repeated sprite would not match).
  // Offsets are art pixels from iso(0, 0, 0) of the bathroom (the world origin).
  const wf0 = () => { const b = roomByKey.get('__bath'); b.ox = WOX; b.oy = WOY; b.drop = 0; return b; };
  const linkRec = L => ({ kind: L.kind, axis: L.axis, A: L.A, B: L.B, len: round1(L.len), z: L.z, z0: L.z0, rise: L.rise, steps: L.steps, ang: L.ang, pa: L.pa.kind, pb: L.pb.kind });
  function cutLinkAt(L, lift) {
    const layers = [], lights = []; let name = '';
    L.lift = lift; L.turn = null;
    bakeWorld = (store, nm, key, box, fn) => { name = nm; return real.bakeWorld(store, nm, key, box, fn); };
    blit = b => { if (b) layers.push({ tag: name, sprite: addSprite(b.img), x: b.dx, y: b.dy }); };
    glow = (x, y, rad, color, k) => lights.push({ sprite: glowSprite(color, rad), r: Math.max(1, Math.round(rad)), x: x - WOX, y: y - WOY, k: round1(k * 1000) / 1000 });
    reset(raw); dirty = false;
    try { withG(cx, () => real.drawLink(L, T)); } finally { Object.assign(window, { blit: real.blit, glow: real.glow, bakeWorld: real.bakeWorld }); }
    if (dirty) { dirty = false; reset(raw); throw new Error('a link drew something directly'); }
    return { layers, lights };
  }
  // the lift: the frame a floor at a time, the cages once at the bottom (closed and open); every translate by z is exact
  // (z is a whole number of units, S pixels each)
  function cutLiftNow() {
    let name = '';
    bakeWorld = (store, nm, key, box, fn) => { name = nm; return real.bakeWorld(store, nm, key, box, fn); };
    const sliceCut = (f, keep) => {
      const out = []; let tag = 'start';
      const flush = () => { if (!dirty) return; dirty = false; const cut = cropRaw(); reset(raw); if (cut) out.push({ tag, sprite: addSprite(cut.img), x: cut.x - WOX, y: cut.y - WOY }); };
      blit = b => { if (!b) return; flush(); out.push({ tag: name, sprite: addSprite(b.img), x: b.dx, y: b.dy }); tag = 'after:' + name; };
      reset(raw); dirty = false;
      try { withG(cx, () => real.drawLifts(T, f)); flush(); } finally { blit = real.blit; }
      return out.filter(p => keep(p.tag));
    };
    const park = (z, state) => LIFT.cabins.forEach(c => { c.z = z; c.level = 0; c.state = state; });
    park(-1e6, 'idle');
    const floors = LIFT.fl.map((q, f) => {
      const depth = LIFT.x0 + LIFT.y1 - q.yoff, [zlo, zhi] = liftSlice(f), pieces = [];
      for (const p of sliceCut(f, tag => !/rope/.test(tag))) {
        const m = /^(\d+)(back|front|head)(\d?)$/.exec(p.tag), shaft = m && m[3] !== '' ? +m[3] : 0;
        const key = m && m[2] === 'head' ? .03 : !m ? .04 : shaft * .01 + (m[2] === 'back' ? 0 : .005);
        pieces.push({ part: m ? m[2] : 'pulley', shaft, key, sprite: p.sprite, x: p.x, y: p.y });
      }
      return { level: f, room: q.r.key, z: liftZ(f), zlo, zhi: zhi === Infinity ? 1e9 : zhi, depth: round1(depth), pieces };
    });
    const z0 = liftZ(0), cages = [];
    for (const state of ['idle', 'open']) {
      park(-1e6, 'idle'); LIFT.cabins.forEach(c => { c.z = z0; c.state = state; });
      for (const p of sliceCut(0, tag => /cage(Back|Front)\d/.test(tag))) {
        const [, part, i] = /cage(Back|Front)(\d)/.exec(p.tag);
        if (state === 'open' && part === 'Back') continue;
        cages.push({ shaft: +i, part: part === 'Back' ? 'back' : state === 'open' ? 'frontOpen' : 'front', key: +i * .01 + (part === 'Back' ? .002 : .004), sprite: p.sprite, x: p.x, y: p.y });
      }
    }
    bakeWorld = real.bakeWorld; park(z0, 'idle');
    return { floors, cages };
  }
  const village = result.village = { links: [], lift: {}, bridgeKit: null };
  if (want('world')) {
    fixture(natural(14)); wf0();
    const plan = links.map(linkRec); village.plan = plan;
    village.links = links.map((L, i) => ({ ...plan[i], buckets: [] }));
    BUCKETS.forEach((h, bi) => {
      setHour(h);
      links.forEach((L, i) => { village.links[i].buckets[bi] = L.kind === 'stair' ? { down: cutLinkAt(L, 0), up: cutLinkAt(L, 1) } : cutLinkAt(L, 0); L.lift = 0; });
    });
    // the plan must be a prefix of itself for every smaller count (a new project never moves the earlier ones)
    for (const n of [2, 3, 5, 8, 11]) { fixture(natural(n)); const p2 = links.map(linkRec); if (JSON.stringify(p2) !== JSON.stringify(plan.slice(0, p2.length))) log('PLAN NOT A PREFIX at', n); }
    // the lift for 3 floors (no project) and 4 (a project in the tower): its geometry, per bucket
    for (const n of [0, 1]) {
      fixture(natural(n)); wf0();
      const lift = { floors: LIFT.fl.length, shafts: LIFT.shafts.map(s => ({ cx: s.cx, cy: s.cy, x0: s.x0, x1: s.x1, y0: s.y0, y1: s.y1 })), x0: LIFT.x0, x1: LIFT.x1, y0: LIFT.y0, y1: LIFT.y1, top: LIFT.top,
        cageZ: liftZ(0), cageH: 28, fl: LIFT.fl.map(q => ({ room: q.r.key, yoff: q.yoff, z: q.z })), buckets: [] };
      BUCKETS.forEach((h, bi) => { setHour(h); LIFT.bk = new Map(); lift.buckets[bi] = { ...cutLiftNow(), rope: lit('#3a2c20'), pulley: [lit(OUT), lit(WOOD_L), lit(WOOD)] }; });
      village.lift['n' + LIFT.fl.length] = lift;
    }
    log('links', links.length, 'plan', plan.length);
  }

  // ---------- signs: the board is the page's pixel font, drawn from the text; the renderer draws it, we give the rules ----------
  const sign = result.sign = { font: SFONT, k: SK, rows: SH, post: 7 * S, src: { signImage: signImage.toString(), drawSign: drawSign.toString(), signText: signText.toString(), pfFit: pfFit.toString(), sfDraw: sfDraw.toString(), sfWidth: sfWidth.toString() }, buckets: [] };
  sign.label = { note: 'r.label (a DOM div) is hidden by the page CSS ("rooms carry painted signs instead"); the sign is canvas art. If a DOM label is ever shown: font -apple-system,BlinkMacSystemFont,sans-serif 12px/1.3 weight 600, colour rgba(255,255,255,.9), background rgba(20,16,32,.55), padding 3px 9px, radius 999px.' };
  BUCKETS.forEach((h, bi) => {
    setHour(h);
    const sl = (c, k = 1) => DARK > .3 ? emi(c, k * (1 - DARK * .3)) : lit(c, k);
    const board = plaque => { const wood = plaque ? '#5a3a26' : '#b07a48', edge = plaque ? '#c89c60' : '#d8a870';
      return { rim: sl(OUT), wood: sl(wood), edge: sl(edge), under: sl(wood, .78), ink: sl('#fff0c8'), inkEdge: sl('#24161a') }; };
    sign.buckets[bi] = { sign: board(false), plaque: board(true), postRim: lit(OUT), postWood: lit('#8a5a36'), shadow: 'rgba(0,0,0,.18)' };
  });

  // ---------- the sky: backdrop, sun/moon/stars and clouds, per bucket (the gradient is the page's drawSky from AMBK) ----------
  const sky = result.sky = { W: cv.width, H: cv.height, ground: null, buckets: [], src: { drawSky: drawSky.toString(), drawClouds: drawClouds.toString(), sunX: sunX.toString() } };
  if (want('sky')) {
    const W = cv.width, H = cv.height, scap = document.createElement('canvas'); scap.width = W; scap.height = H;
    const sraw = scap.getContext('2d', { willReadFrequently: true });
    const cropOf = c => { const w = c.canvas.width, h = c.canvas.height, px = c.getImageData(0, 0, w, h).data; let x0 = w, y0 = h, x1 = -1, y1 = -1;
      for (let y = 0; y < h; y++) for (let x = 0, i = y * w * 4 + 3; x < w; x++, i += 4) if (px[i]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
      if (x1 < 0) return null; const img = document.createElement('canvas'); img.width = x1 - x0 + 1; img.height = y1 - y0 + 1;
      img.getContext('2d').drawImage(c.canvas, x0, y0, img.width, img.height, 0, 0, img.width, img.height); return { img, x: x0, y: y0 }; };
    const paintS = fn => { reset(sraw); withG(sraw, fn); return cropOf(sraw); };
    const bd = BACKDROPS[BACKDROP] || BACKDROPS.city;
    sky.backdrop = BACKDROP;
    BUCKETS.forEach((h, bi) => {
      const d = setHour(h), P = { px: 0, py: 0, W, H, ground: bd.ground ? bd.ground(W, H - insetBottom()) : bdGround(H - insetBottom()), hr: h };
      sky.ground = P.ground;
      const b = { sky: SKY.slice(), dark: DARK };
      const back = paintS(() => bd.draw(T, d, P)); b.backdrop = back && { sprite: addSprite(back.img), x: back.x, y: back.y };
      const cel = paintS(() => drawCelestial(T, d, P)); b.celestial = cel && { sprite: addSprite(cel.img), x: cel.x, y: cel.y, sun: LAST_SUN };
      const cw = document.createElement('canvas'); cw.width = 12 * 131 * S + W + 80 * S; cw.height = H; const cwx = cw.getContext('2d', { willReadFrequently: true });
      const OFF = 80 * S; cwx.translate(OFF, 0); withG(cwx, () => drawClouds(0, { ...P, W: cw.width - 160 * S }));
      b.clouds = LAST_CLOUDS.map(([x, y, w], i) => { const c = document.createElement('canvas'); c.width = w + 2 * S; c.height = 12 * S;
        c.getContext('2d').drawImage(cw, x + OFF - S, y - 6 * S, c.width, c.height, 0, 0, c.width, c.height); return { i, w, y, sprite: addSprite(c), dx: -S, dy: -6 * S }; });
      sky.buckets[bi] = b;
    });
    sky.rules = { clouds: 'cloud i is at x = round(((i*131*S + t*(.004+(i%3)*.002)*S) % (W+80*S)) - 60*S) + round(px*.8), y as recorded (cloud sprite i of the bucket: w, y); drawn with the sprite at (x+dx, y+dy); t in ms',
      gradient: 'vertical gradient SKY[0] -> SKY[1] over the screen height, then the sunrise glow bands of drawSky', sun: 'celestial layer is cut at its screen position for the screen size above; sun anchor in .sun' };
  }

  // ---------- Clawd and the residents: every pose, cut around its feet; ax, ay = the feet's offset inside the sprite ----------
  const poses = result.poses = { anchors: 'sprite drawn at (X - ax, Y - ay) where (X, Y) is the point drawClawd was given (the feet, iso of the spot)', buckets: [] };
  if (want('poses')) {
    const fr = {}; // a stand-in room
    const base = (vendor, small, o) => ({ kind: 'agent', vendor, small, state: 'working', path: [], alpha: 1, moving: false, seated: false, waving: false, toss: 0, onBridge: null,
      seed: .3, goal: null, hold: null, fire: null, room: null, agent: { id: 'x', activity: 'Bash · ls' }, ...o });
    const cut = (draw) => { reset(raw); dirty = false; withG(cx, draw); dirty = false; const c = cropRaw(); reset(raw); return c && { sprite: addSprite(c.img), ax: 300 - c.x, ay: 400 - c.y }; };
    const list = []; // [name, makeSprite, t]
    const add = (name, mk, ts) => (Array.isArray(ts) ? ts : [ts]).forEach((t, i) => list.push([ts.length > 1 || Array.isArray(ts) ? `${name}.${i}` : name, mk, t]));
    const frames_ = (n, period) => Array.from({ length: n }, (_, i) => Math.round(i * period / n));
    const looks = [['claude', false], ['claude', true], ['codex', false], ['codex', true]];
    const catalog = { // per look
      stand: [{}, [0]], walk: [{ moving: true }, [0, 110]], work: [{ seated: true }, [0, 160]],
      laptop: [{ goal: { cat: 'seat', room: fr }, room: fr }, [0, 700, 1400]],
      flask: [{ agent: { id: 'x', activity: 'Bash · pnpm test' } }, frames_(4, 800)], hammer: [{ agent: { id: 'x', activity: 'Edit · f.swift' } }, [0, 190]],
      binoculars: [{ agent: { id: 'x', activity: 'WebSearch · q' } }, [0, 1700 * .15 - 1 + 1700 * 0]], book: [{ agent: { id: 'x', activity: 'Read · f' } }, [0, 2600 * .06]],
      waiting: [{ state: 'waiting' }, frames_(6, 1634)], error: [{ state: 'error' }, frames_(4, 1885)], sleep: [{ state: 'done' }, frames_(4, 1400)],
      shower: [{ state: 'shower' }, frames_(6, 9000)], dry: [{ state: 'dry' }, frames_(6, 1382)], towel: [{ towel: 1e12 }, [0]], fall: [{ state: 'fall' }, [0]],
      wave: [{ waving: true }, [0, 300]], toss: [{ toss: 100 }, [1000]],
      ext: [{ hold: { kind: 'ext', dir: 1 } }, [0]], extL: [{ hold: { kind: 'ext', dir: -1 } }, [0]], mail: [{ hold: { kind: 'mail', stage: 'go' } }, [0]], handover: [{ hold: { kind: 'handover', stage: 'walk' } }, [0]],
      fire: [{ fire: {} }, [0, 130]], fireFoam: [{ fire: { foamed: 900 } }, [1000]],
    };
    const homeCatalog = { stand: [{ state: 'idle' }, [0]], walk: [{ state: 'idle', moving: true }, [0, 110]], sleep: [{ state: 'idle-sleep' }, frames_(4, 1400)],
      coffee: [{ state: 'idle', scene: 'coffee', goal: { cat: 'coffee', room: fr }, room: fr }, frames_(4, 1100)], water: [{ state: 'idle', scene: 'water', goal: { cat: 'wash', room: fr }, room: fr }, [0]],
      pour: [{ state: 'idle', scene: 'water', goal: { cat: 'water', room: fr }, room: fr }, frames_(3, 600)], read: [{ state: 'idle', scene: 'read', goal: { cat: 'read', room: fr }, room: fr }, [0, 2600 * .06]] };
    const jobs = []; // [name, () => sprite, t]
    for (const [v, small] of looks) for (const [k, [o, ts]] of Object.entries(catalog)) ts.forEach((t, i) => jobs.push([`${v}${small ? '-mini' : ''}/${k}.${i}`, () => base(v, small, o), t]));
    for (const [k, [o, ts]] of Object.entries(homeCatalog)) ts.forEach((t, i) => jobs.push([`home/${k}.${i}`, () => base('home', true, { kind: 'home', ...o }), t]));
    // the cat and the dog, both ways
    const pet = (kind, face, o) => ({ kind, alpha: 1, path: [], onBridge: null, moving: false, seed: 0, face, ...o });
    for (const face of [1, -1]) {
      const f = face > 0 ? 'r' : 'l';
      jobs.push([`cat/walk1.${f}`, () => pet('cat', face, { moving: true }), 0], [`cat/walk2.${f}`, () => pet('cat', face, { moving: true }), 120],
        [`cat/sit2.${f}`, () => pet('cat', face, { pose: 'sit' }), 0], [`cat/sit1.${f}`, () => pet('cat', face, { pose: 'sit' }), 700]);
      frames_(4, 1800).forEach((t, i) => jobs.push([`cat/nap.${f}.${i}`, () => pet('cat', face, { pose: 'nap' }), t]));
      jobs.push([`dog/walk1.${f}`, () => pet('dog', face, { moving: true }), 0], [`dog/walk2.${f}`, () => pet('dog', face, { moving: true }), 120],
        [`dog/walk1ball.${f}`, () => pet('dog', face, { moving: true, ball: true }), 0], [`dog/walk2ball.${f}`, () => pet('dog', face, { moving: true, ball: true }), 120],
        [`dog/sit2.${f}`, () => pet('dog', face, { pose: 'sit' }), 0], [`dog/sit1.${f}`, () => pet('dog', face, { pose: 'sit' }), 900]);
      [0, 260, 520, 780].forEach((t, i) => jobs.push([`dog/bark.${f}.${i}`, () => pet('dog', face, { pose: 'bark' }), t]));
      frames_(4, 1900).forEach((t, i) => jobs.push([`dog/nap.${f}.${i}`, () => pet('dog', face, { pose: 'nap' }), t]));
    }
    poses.names = jobs.map(j => j[0]);
    BUCKETS.forEach((h, bi) => {
      setHour(h); const out = {};
      for (const [name, mk, t] of jobs) { const sp = mk(); const c = cut(() => drawClawd(300, 400, sp, t)); if (c) out[name] = c; }
      poses.buckets[bi] = out;
    });
    poses.timing = { walk: 'frame = floor(t/110) % 2 (legs and hop)', work: 'frame = floor(t/160) % 2', waiting: 'sample i of 6 over 1634 ms: sin(t/260)', error: '4 over 1885 ms', sleep: '4 over 1400 ms (the Zs rise k=(t/1400+seed)%1)',
      shower: '6 over 9000 ms (k=(t/9000+seed)%1)', dry: '6 over 1382 ms', hammer: 'down = floor(t/190 + seed*3) % 2', cat: 'walk floor(t/120)%2; sit2 when floor(t/700+seed*7)%6==0; nap Zs (t/1800+seed)%1', dog: 'walk floor(t/120)%2 (90 when fast); sit2 when floor(t/900+seed*7)%6==0 (wag: floor(t/140)%2==0); bark: sit1/bark floor(t/260)%2 and the text on when floor(t/520)%2==0' };
    log('poses', jobs.length);
  }

  // ---------- packing: shelves on pages of up to 4096 px, 2 px of air around each sprite ----------
  const PAGE = 4096, PAD = 2, pages = [], atlas = new Array(frames.length);
  const order = frames.map((f, i) => i).sort((a, b) => frames[b].h - frames[a].h || frames[b].w - frames[a].w);
  let pg = null, sx = 0, sy = 0, rowH = 0;
  const newPage = () => { pg = { cv: document.createElement('canvas'), h: 0 }; pg.cv.width = PAGE; pg.cv.height = PAGE; pg.ctx = pg.cv.getContext('2d'); pages.push(pg); sx = PAD; sy = PAD; rowH = 0; };
  newPage();
  for (const i of order) {
    const { w, h, img } = frames[i];
    if (sx + w + PAD > PAGE) { sx = PAD; sy += rowH + PAD; rowH = 0; }
    if (sy + h + PAD > PAGE) newPage();
    pg.ctx.drawImage(img, sx, sy);
    atlas[i] = [pages.length - 1, sx, sy, w, h];
    sx += w + PAD; rowH = Math.max(rowH, h); pg.h = Math.max(pg.h, sy + h + PAD);
  }
  result.pages = pages.map((p, i) => {
    const c = document.createElement('canvas'); c.width = PAGE; c.height = Math.min(PAGE, 1 << Math.ceil(Math.log2(p.h)));
    c.getContext('2d').drawImage(p.cv, 0, 0);
    post(`parts-${i}.png`, c.toDataURL('image/png')); return { file: `parts-${i}.png`, w: c.width, h: c.height };
  });
  // ---------- the proof: re-compose frames from the parts alone, using the page's live layout, and compare ----------
  // What the composer takes from the page: the layout (rooms' ox/oy and tower/floor, links, LIFT, the draw order) and, for hours
  // that are not a bucket (the cross-fade case), the sky (the sun's arc is a formula the Swift scene owns). Every room, link,
  // lift, sign, light and the sky at a bucket hour comes from the manifest and the packed pages only.
  const proof = result.proof = [];
  const checkPages = pages; // the packed canvases: the composer draws from these, exactly what Swift will load
  const drawSpr = (ctx, id, x, y) => { if (!atlas[id]) throw new Error('no sprite ' + id + ' ' + new Error().stack.split('\n').slice(1, 4).join('|')); const [p, sx0, sy0, w, h] = atlas[id]; ctx.drawImage(checkPages[p].cv, sx0, sy0, w, h, x, y, w, h); };
  const hourPasses = h => { // the two buckets around the hour and the weight of the second
    let i = 0; while (i + 1 < BUCKETS.length && BUCKETS[i + 1] <= h) i++;
    const h1 = i + 1 < BUCKETS.length ? BUCKETS[i + 1] : 24, u = (h - BUCKETS[i]) / (h1 - BUCKETS[i]);
    return u < 1e-6 ? [{ bi: i, w: 1 }] : [{ bi: i, w: 1 }, { bi: (i + 1) % BUCKETS.length, w: u }];
  };
  const fitText = s => { s = String(s || '').toUpperCase().replace(/\s+/g, ' ').trim(); return [...s].length > 18 ? [...s].slice(0, 17).join('') + '…' : s; };
  const glyph = ch => (sign.font[ch] || sign.font[ch.toUpperCase()] || sign.font['?']).split('/');
  const sfW = s => [...s].reduce((w, ch, i) => w + glyph(ch)[0].length + (i ? 1 : 0), 0);
  function drawSignParts(ctx, room, bi, alpha, pass) { // the page's signImage + drawSign, from the manifest's rules and colours
    const b = sign.buckets[bi], text = fitText(room.theme.shared ? room.theme.name : room.name), plaque = room.floor > 0, c = plaque ? b.plaque : b.sign;
    const tw = sfW(text) * sign.k, w = tw + 8, h = sign.rows * sign.k + 6, img = document.createElement('canvas'); img.width = w + 2; img.height = h + 2;
    const k = img.getContext('2d'), rc = (col, x, y, ww, hh) => { k.fillStyle = col; k.fillRect(x, y, ww, hh); };
    rc(c.rim, 0, 1, w + 2, h); rc(c.rim, 1, 0, w, h + 2); rc(c.wood, 1, 1, w, h); rc(c.edge, 2, 1, w - 2, 1); rc(c.under, 2, h, w - 2, 1);
    const stamp = (dx, dy, col) => { let x = 5 + dx; k.fillStyle = col; for (const ch of text) { const gl = glyph(ch); gl.forEach((row, r) => { for (let q = 0; q < row.length; q++) if (row[q] === '#') k.fillRect(x + q * sign.k, 4 + dy + r * sign.k, sign.k, sign.k); }); x += (gl[0].length + 1) * sign.k; } };
    for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]]) stamp(dx, dy, c.inkEdge);
    stamp(0, 0, c.ink);
    ctx.globalAlpha = alpha;
    if (!plaque) {
      const [px, py] = [room.ox + (room.NX + .55 - (room.NY + .55)) * 8 * S, room.oy + (room.NX + .55 + room.NY + .55) * 4 * S + SLAB * S], X = Math.round(px), Y = Math.round(py), post = sign.post;
      ctx.fillStyle = b.postRim; ctx.fillRect(X - S - 1, Y - post - 1, 2 * S + 2, post + 2);
      ctx.fillStyle = b.postWood; ctx.fillRect(X - S, Y - post, 2 * S, post);
      ctx.fillStyle = b.shadow; ctx.fillRect(X - 3 * S, Y, 6 * S, 1);
      ctx.drawImage(img, X - (img.width >> 1), Y - post - img.height + 2 * S);
    } else {
      const px = room.ox + (room.NX * .78 - room.NY) * 8 * S, py = room.oy + (room.NX * .78 + room.NY) * 4 * S + SLAB / 2 * S;
      ctx.drawImage(img, Math.round(px - img.width / 2), Math.round(py - img.height / 2));
    }
    ctx.globalAlpha = 1;
  }
  const isoAt = (ox, oy, x, y, z) => [ox + (x - y) * 8 * S, oy + (x + y) * 4 * S - z * S];
  function drawLiftSlice(ctx, wf, f, bi, alpha) { // one floor's piece of the lift: frame, ropes, cages standing in it, head and pulleys
    const lf = village.lift['n' + LIFT.fl.length], fl = lf.buckets[bi].floors[f], cages = lf.buckets[bi].cages, items = [];
    ctx.globalAlpha = alpha;
    for (const p of fl.pieces) items.push({ key: p.key, draw: () => drawSpr(ctx, p.sprite, wf.ox + p.x, wf.oy + p.y) });
    LIFT.cabins.forEach((c, i) => {
      const z = c.z, r0 = Math.max(fl.zlo, z + lf.cageH + 2), r1 = Math.min(fl.zhi, lf.top + 3);
      if (r1 > r0) items.push({ key: i * .01 + .001, draw: () => { const a = isoAt(wf.ox, wf.oy, lf.shafts[i].cx, lf.shafts[i].cy, r1), b = isoAt(wf.ox, wf.oy, lf.shafts[i].cx, lf.shafts[i].cy, r0);
        ctx.fillStyle = lf.buckets[bi].rope; ctx.fillRect(Math.round(a[0]), Math.min(Math.round(a[1]), Math.round(b[1])), 1, Math.abs(Math.round(b[1]) - Math.round(a[1])) + 1); } });
      if (z >= fl.zlo && z < fl.zhi) for (const cg of cages) if (cg.shaft === i && (c.state === 'open' ? cg.part !== 'front' : cg.part !== 'frontOpen'))
        items.push({ key: cg.key, draw: () => drawSpr(ctx, cg.sprite, wf.ox + cg.x, wf.oy + cg.y - (z - lf.cageZ) * S) });
    });
    items.sort((a, b) => a.key - b.key).forEach(it => it.draw());
    ctx.globalAlpha = 1;
  }
  function roomPartOf(r) {
    if (r.key === '__bath') return parts['bath/g' + links.filter(L => L.a === YARD).length];
    if (r.theme.shared) return parts[r.key.slice(2)];
    return parts[themeOf(r) + (r.tower === 0 ? '/tower' : '/island')];
  }
  function drawRoomParts(ctx, r, passes, wf, stats) {
    const part = roomPartOf(r); let ps = passes;
    const A = part.buckets[ps[0].bi], B = ps[1] && part.buckets[ps[1].bi];
    if (B && !(A.layers.length === B.layers.length && A.layers.every((l, k) => l.kind === B.layers[k].kind))) { stats.fallback++; ps = [ps[1].w >= .5 ? ps[1] : ps[0]]; }
    const bs = ps.map(p => part.buckets[p.bi]);
    const lights = () => ps.forEach((p, i) => { ctx.save(); ctx.globalCompositeOperation = 'lighter';
      for (const l of bs[i].lights) { if (l.k * p.w <= 0) continue; ctx.globalAlpha = Math.min(1, l.k * p.w); drawSpr(ctx, l.sprite, Math.round(r.ox + l.x) - l.r, Math.round(r.oy + l.y) - l.r); } ctx.restore(); });
    let lit_ = false;
    bs[0].layers.forEach((l, k) => {
      if (l.kind === 'sign' && l.variant === 'plaque' && !lit_) { lights(); lit_ = true; }
      ps.forEach((p, i) => {
        const bl = bs[i].layers[k], alpha = i ? p.w : 1;
        if (l.kind === 'lift') drawLiftSlice(ctx, wf, l.floor, p.bi, alpha);
        else if (l.kind === 'sign') drawSignParts(ctx, r, p.bi, alpha);
        else { ctx.globalAlpha = alpha; drawSpr(ctx, bl.sprite, r.ox + bl.x, r.oy + bl.y); ctx.globalAlpha = 1; }
      });
    });
    if (!lit_) lights();
  }
  const planIndex = L => village.plan.findIndex(q => q.kind === L.kind && JSON.stringify(q.A) === JSON.stringify(L.A) && JSON.stringify(q.B) === JSON.stringify(L.B));
  function drawLinkParts(ctx, L, passes, wf) {
    const i = planIndex(L); if (i < 0) throw new Error('link not in the plan');
    ps_: for (const p of passes) {
      const alpha = p === passes[0] ? 1 : p.w, b = village.links[i].buckets[p.bi], d = L.kind === 'stair' ? (L.lift ? b.up : b.down) : b;
      for (const l of d.layers) { ctx.globalAlpha = alpha; drawSpr(ctx, l.sprite, wf.ox + l.x, wf.oy + l.y); }
      ctx.globalAlpha = 1;
      ctx.save(); ctx.globalCompositeOperation = 'lighter';
      for (const l of d.lights) { ctx.globalAlpha = Math.min(1, l.k * p.w); drawSpr(ctx, l.sprite, Math.round(wf.ox + l.x) - l.r, Math.round(wf.oy + l.y) - l.r); }
      ctx.restore();
    }
  }
  // the screen: sky from the parts at a bucket hour, else the page's own
  function drawSkyParts(ctx, hour, passes, ownSky) {
    const W = cv.width, H = cv.height, d = hourDate(hour);
    if (ownSky) { withG(ctx, () => drawBackground(T, d)); return; }
    const b = sky.buckets[passes[0].bi], P = { W, H, ground: sky.ground, hr: hour, px: 0, py: 0 };
    withG(ctx, () => drawSky(P));
    if (b.backdrop) drawSpr(ctx, b.backdrop.sprite, b.backdrop.x, b.backdrop.y);
    if (b.celestial) drawSpr(ctx, b.celestial.sprite, b.celestial.x, b.celestial.y);
    ctx.save(); ctx.globalAlpha = 1;
    for (const c of b.clouds) { const x = Math.round(((c.i * 131 * S + T * (.004 + (c.i % 3) * .002) * S) % (W + 80 * S)) - 60 * S); drawSpr(ctx, c.sprite, x + c.dx, c.y + c.dy); }
    ctx.restore();
  }
  function composeFrame(hour, ownSky) {
    const c = document.createElement('canvas'); c.width = cv.width; c.height = cv.height; const ctx = c.getContext('2d');
    const passes = hourPasses(hour), stats = { fallback: 0 }, wf = worldFrame();
    drawSkyParts(ctx, hour, passes, ownSky);
    for (const it of drawOrder()) { if (it.room) drawRoomParts(ctx, it.room, passes, wf, stats); else drawLinkParts(ctx, it.link, passes, wf); }
    for (const r of rooms) { const part = roomPartOf(r); for (const p of passes) for (const o of part.buckets[p.bi].overlay) { ctx.globalAlpha = p === passes[0] ? 1 : p.w; drawSpr(ctx, o.sprite, r.ox + o.x, r.oy + o.y); ctx.globalAlpha = 1; } }
    return { c, stats };
  }
  const grab = c => c.getContext('2d').getImageData(0, 0, c.width, c.height);
  if (want('proof')) for (const [n, hour] of [[2, 12], [5, 12], [2, 19.25], [5, 19.25], [5, 20], [14, 12]]) {
    const exact = BUCKETS.includes(hour);
    fixture(natural(n)); for (const r of rooms) r.born = -1e9;
    fixedHour = hour; frame(T); // the page's own frame (nothing but the house: no agents, no residents)
    const ref = document.createElement('canvas'); ref.width = cv.width; ref.height = cv.height; ref.getContext('2d').drawImage(cv, 0, 0);
    const bg = document.createElement('canvas'); bg.width = cv.width; bg.height = cv.height; withG(bg.getContext('2d'), () => drawBackground(T, hourDate(hour)));
    const { c: ours, stats } = composeFrame(hour, !exact || cv.width !== sky.W || cv.height !== sky.H);
    const a = grab(ref).data, b = grab(ours).data, k = grab(bg).data, W = cv.width, H = cv.height, out = new ImageData(W, H);
    let diff = 0, house = 0, houseDiff = 0, sum = 0;
    for (let i = 0; i < a.length; i += 4) {
      const m = Math.max(Math.abs(a[i] - b[i]), Math.abs(a[i + 1] - b[i + 1]), Math.abs(a[i + 2] - b[i + 2])), isHouse = Math.abs(a[i] - k[i]) + Math.abs(a[i + 1] - k[i + 1]) + Math.abs(a[i + 2] - k[i + 2]) > 0;
      if (isHouse) house++; if (m > 24) { diff++; if (isHouse) houseDiff++; }
      out.data[i] = m > 24 ? 255 : a[i] >> 2; out.data[i + 1] = m > 24 ? 0 : a[i + 1] >> 2; out.data[i + 2] = m > 24 ? 0 : a[i + 2] >> 2; out.data[i + 3] = 255;
    }
    const dc = document.createElement('canvas'); dc.width = W; dc.height = H; dc.getContext('2d').putImageData(out, 0, 0);
    const tag = `n${n}-h${hour}`;
    post(`check/${tag}-page.png`, ref.toDataURL('image/png')); post(`check/${tag}-parts.png`, ours.toDataURL('image/png')); post(`check/${tag}-diff.png`, dc.toDataURL('image/png'));
    proof.push({ projects: n, hour, bucketHour: exact, sky: exact && cv.width === sky.W && cv.height === sky.H ? 'from parts' : "the page's own (the sun's arc is the renderer's formula)", pixels: W * H, diffOver24: diff, pctWhole: +(100 * diff / (W * H)).toFixed(4),
      housePixels: house, houseDiffOver24: houseDiff, pctHouse: +(100 * houseDiff / Math.max(1, house)).toFixed(4), crossFadeFallbacks: stats.fallback });
    log(tag, 'diff', diff, (100 * diff / (W * H)).toFixed(4) + '%', 'house', houseDiff + '/' + house);
  }
  result.proofNote = 'diff = pixels whose largest channel difference is > 24 against the page\'s own frame at t=100000 (no agents, no residents, clear weather, nothing animated differs: both frames are drawn at the same t); house = pixels the house changed against the sky-only frame';

  result.rules = {
    bridge: 'Bridges are exported as concrete configurations (result.links, plan prefix of 13 links, valid for 0..14 projects). Rules for a renderer that wants to repeat them: planks n = Math.max(3, Math.round((s1 - s0) / .3)), plank colour ["#c48c58","#b88250","#cc965e"][(i*2 + (i>>2)) % 3], seam line at each plank i>0 in #7a4a2a, nail on odd i; posts m = Math.max(1, Math.round((s1 - s0 - .3) / 1.0)) at s0+.15+(s1-s0-.3)*i/m, rope 6 segments per span with sag 6.6 - sin(u*PI)*1.6; lanterns at s0+.15 and s1-.15 (lit when DARK > .3, glow 20*S #ffc870). Source: room/index.html drawLink.',
    stair: 'Stairs are concrete (13 steps, W=.5, rope posts every 3rd step, lantern at the foot); the swing (L.lift) is only exported down/up. Source: room/index.html drawStair.',
    lift: 'The lift is exported per floor count (3 for 0 projects, 4 for >=1): shaft slices plus cage; pulleys are static. Source: room/index.html drawLifts.',
    crossFade: 'Draw bucket A layer k, then bucket B layer k at alpha u, pairing by index. Layer counts differ by one between some buckets (night vs day art), so the pairing is not valid there; see limits.'
  };
  result.limits = ['one season (autumn), clear weather only', 'island layout only', 'dynamic items frozen at t=100000, clock and window panes at the bucket hour', 'stair swing only down/up, pulleys static', 'pose frames are sampled', 'sky cut for a ' + sky.W + 'x' + sky.H + ' canvas; other canvas sizes need the page sky',
    'cross-fade at a non-bucket hour (19.25 in the proof) does NOT reproduce the page: lit()/DARK-conditional art is not a linear blend of two buckets; measured exactly at bucket hours only'];
  result.counts = { rooms: Object.keys(result.rooms).length, sprites: atlas.length };

  result.sprites = atlas; // [page, x, y, w, h] by sprite id
  result.note = { sprites: '[page, x, y, w, h] in the page PNG; ids index this array', pad: PAD };
  post('parts.json', JSON.stringify(result));
  return `parts: ${frames.length} sprites on ${pages.length} pages; ${LOG.join('; ')}`;
})();
