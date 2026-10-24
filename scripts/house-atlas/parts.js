// Runs inside room/index.html (injected by export.swift in "parts" mode) and cuts the house into REUSABLE PARTS:
// every sprite is positioned against its own origin (a room's iso(0,0,0), the bathroom's origin for the village's
// bridges, stairs and lift, an anchor for a Clawd) instead of the screen, so a renderer can place them for any layout.
// Nothing here draws art of its own: every pixel comes from the page's own functions, wrapped so that each piece they
// draw lands in its own layer. Light: the page tints colours by the clock (lit()/emi() over AMBK), so every part is cut
// Output: files streamed to Swift with webkit.messageHandlers.out (parts.json, parts-N.png, check/*.png).
(() => {
  'use strict';
  const O = window.__HOUSE_EXPORT, posted = [];
  const post = (path, data) => { posted.push(path); window.webkit.messageHandlers.out.postMessage({ path, data }); };
  const T = 100000; // the moment every part is cut at (and every reference frame drawn at)
  const LOG = []; const log = (...a) => LOG.push(a.join(' '));
  const only = new Set((O.only || '').split(',').filter(Boolean)); // dev: restrict the stages
  const want = s => !only.size || only.has(s);

  // ---------- quiet page: no loop, no residents, no eggs, no seasons' particles, clear weather ----------
  setActive(false);
  weather = 'clear'; Q.set('season', O.season || 'autumn'); Q.set('moon', '.5');
  CAM.glide = null; CAM.follow = null; VIEW.zoom = 1; mouse = null; PAR.x = PAR.y = 0;
  CITY.lanes = [[], []]; CITY.nextCar = [Infinity, Infinity]; CITY.train = null; CITY.nextTrain = Infinity;
  // Pin CSS geometry and DPR as well as the WebView size: layout() must not depend on the host display.
  Object.defineProperty(window, 'innerWidth', { value: 1728, configurable: true });
  Object.defineProperty(window, 'innerHeight', { value: 1117, configurable: true });
  Object.defineProperty(window, 'devicePixelRatio', { value: 2, configurable: true });
  updateStairs = () => {}; updateResidents = () => {}; updateErrands = () => {}; updateScenes = () => {}; eggStep = () => {};
  eggSky = () => {}; eggOver = () => {}; eggItems = () => {}; drawSeason = () => {};
  METEORS.next = Infinity; METEORS.list = [];
  room.setInsets(O.insets);
  sprites.clear();

  const BUCKETS = AMBK.slice(0, 9).map(r => r[0]); // 0 5 6.5 8.5 12 16.5 18.5 20 21.5 (row 24 repeats row 0)
  const hourDate = h => { const d = new Date(2026, 9, 15); d.setHours(Math.floor(h), Math.floor((h % 1) * 60), Math.floor((h * 3600) % 60), 0); return d; };
  now = () => hourDate(fixedHour ?? 12); // reference frame and composer share the same calendar-dependent mist
  const setHour = h => { fixedHour = h; setTime(h); return hourDate(h); };
  // ---------- the light model: F/E renders and DARK variants ----------
  // every DARK comparison in room/index.html that reaches a room, a link, the lift or a Clawd: .2 .25 .3 .35 .4 .45 .5 .55 .6; and the
  // continuous DARK factors (sign colour 1 - DARK*.3) are kept under ~4/255 by cutting finer where they bite (.7 .8 .9)
  const THRESH = [.2, .25, .3, .35, .4, .45, .5, .55, .6, .7, .8, .9];
  const EDGES = [0, ...THRESH, 1];
  const VARS = EDGES.slice(0, -1).map((lo, i) => ({ lo, hi: EDGES[i + 1], d: i === 0 ? .02 : +((lo + EDGES[i + 1]) / 2).toFixed(4) }));
  // .3 has both > and >= tests on the page; sample equality itself instead of choosing either neighbour.
  const boundary30 = VARS.length; VARS.push({ lo: .3, hi: .3, d: .3, exact: true });
  const varOf = dark => { if (dark === .3) return boundary30; let i = 0; while (i < boundary30 - 1 && dark > VARS[i].hi) i++; return i; };
  const DSLOPE = .004; // a third cut at DARK + DSLOPE measures how each glow's alpha moves with DARK (k = a + b * DARK)
  const FA = .5; // F is cut at AMB = FA (not 1): lit() clamps at 255, so a colour with k > 1 would clamp in an AMB = 1 cut; at .5 nothing clamps
  let LM = 'F';
  const setLight = (mode, dark) => { LM = mode; const a = mode === 'F' ? FA : 0; AMB = [a, a, a]; DARK = dark; lightKey = mode + '|' + dark; };
  const parseCss = c => { const m = /rgba?\(([^)]+)\)/.exec(c); if (m) return m[1].split(',').slice(0, 3).map(Number); const n = parseInt(c.slice(1), 16); return [n >> 16, n >> 8 & 255, n & 255]; };
  const colorPair = (d, fn) => { setLight('F', d); const f = parseCss(fn()); setLight('E', d); const e = parseCss(fn()); return { F: f, E: e }; };

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
  // bake() only grows scratch on demand; the bathroom yard extends beyond its initial room-sized allocation.
  scratch.width = Math.max(scratch.width, CW); scratch.height = Math.max(scratch.height, CH);
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
  function cropRaw(rx = 0, ry = 0, w = raw.canvas.width, h = raw.canvas.height) {
    const px = raw.getImageData(rx, ry, w, h).data;
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0, i = y * w * 4 + 3; x < w; x++, i += 4) if (px[i]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 < 0) return null;
    x0 += rx; x1 += rx; y0 += ry; y1 += ry;
    const img = document.createElement('canvas'); img.width = x1 - x0 + 1; img.height = y1 - y0 + 1;
    img.getContext('2d').drawImage(raw.canvas, x0, y0, img.width, img.height, 0, 0, img.width, img.height);
    return { img, x: x0, y: y0 };
  }
  const withG = (ctx, fn) => { const saved = [g, R]; g = ctx; try { return fn(); } finally { [g, R] = saved; } };

  // ---------- sprites: every distinct image pair (F, E) once, packed at the end ----------
  // flag: 0 = general (out = E + (F - E) * AMB / FA), 1 = E is black (out = F * AMB / FA), 2 = constant (E is not stored; F is drawn as is)
  const frames = [], byHash = new Map();
  const words = c => { const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; return { d, u: new Uint32Array(d.buffer) }; };
  const hashU = u => { let a = 2166136261, b = 0; for (let i = 0; i < u.length; i++) { a = Math.imul(a ^ u[i], 16777619) >>> 0; b = (b + u[i] * (i % 251 + 1)) >>> 0; } return a + ':' + b; };
  function addPair(F, E) { // E null: constant
    const w = F.width, h = F.height, f = words(F);
    let flag = 2, e = null, key = w + 'x' + h + ':' + hashU(f.u);
    if (E) {
      if (E.width !== w || E.height !== h) throw new Error('F and E differ in size ' + w + 'x' + h + ' vs ' + E.width + 'x' + E.height);
      e = words(E); let same = true, black = true, alphaSame = true;
      for (let i = 0; i < f.d.length; i += 4) {
        if (f.d[i] !== e.d[i] || f.d[i + 1] !== e.d[i + 1] || f.d[i + 2] !== e.d[i + 2] || f.d[i + 3] !== e.d[i + 3]) same = false;
        if (f.d[i + 3] !== e.d[i + 3]) alphaSame = false;
        if (e.d[i + 3] && (e.d[i] || e.d[i + 1] || e.d[i + 2])) black = false;
      }
      flag = same ? 2 : black && alphaSame ? 1 : 0; if (flag === 2) e = null; else key += '|' + hashU(e.u);
    }
    let id = byHash.get(key);
    if (id === undefined) { id = frames.length; frames.push({ img: F, e: flag === 2 ? null : E, w, h, flag }); byHash.set(key, id); }
    return id;
  }
  const addConst = img => addPair(img, null);
  // a dual run: fn() is run under F, then E (and F at DARK + DSLOPE for the glows' slope); every image it asks for with ph() is paired.
  let CTX = null;
  const ph = img => { CTX.imgs.push(img); return { ph: CTX.imgs.length - 1 }; };
  function dual(d, fn, slope) {
    const run = (mode, dd) => { CTX = { imgs: [] }; setLight(mode, dd); const res = fn(); const imgs = CTX.imgs; CTX = null; return [res, imgs]; };
    const step = d === .3 ? -DSLOPE : DSLOPE; // stay on the same side of strict > .3 light tests
    const [res, fi] = run('F', d), [, ei] = run('E', d), r3 = slope ? run('F', d + step)[0] : null;
    if (fi.length !== ei.length) throw new Error('F and E cut a different number of images: ' + fi.length + ' vs ' + ei.length);
    const ids = fi.map((img, i) => addPair(img, ei[i]));
    const walk = (o, o3) => {
      if (Array.isArray(o)) return o.map((v, i) => walk(v, o3 && o3[i]));
      if (o && typeof o === 'object') {
        if ('ph' in o && Object.keys(o).length === 1) return ids[o.ph];
        const out = {}; for (const k of Object.keys(o)) out[k] = walk(o[k], o3 && o3[k]);
        if (slope && o3 && typeof o.k === 'number' && 'r' in o) { const b = (o3.k - o.k) / step; out.b = +b.toFixed(4); out.a = +(o.k - b * d).toFixed(4); delete out.k; }
        return out;
      }
      return o;
    };
    return walk(res, r3);
  }
  // the unit glow of a colour and radius (what glow() stamps at alpha k): it is the page's own gradient image
  const glowIds = new Map();
  function glowSprite(color, rad) {
    const r = Math.max(1, Math.round(rad)), key = color + '|' + r;
    let id = glowIds.get(key);
    if (id === undefined) {
      const tmp = document.createElement('canvas'); tmp.width = tmp.height = 4;
      withG(tmp.getContext('2d'), () => real.glow(8, 8, rad, color, 0)); // fills GLOWS for this colour and radius
      id = addConst(GLOWS.get(key)); glowIds.set(key, id);
    }
    return id;
  }
  const real = { blit, drawLifts, drawSign, glow, bakeWorld, drawLink, pane, still };
  const depthOf = it => typeof it.depth === 'function' ? it.depth() : it.depth;
  const round1 = v => Math.round(v * 1000) / 1000;

  // ---------- one room, cut the way drawRoom draws it: back layer, items by depth, lights, sign, lift slice ----------
  // Offsets are art pixels from iso(0, 0, 0) of the room. kind: back (under everything: shell A, window glass, shell B, clock,
  // sunlight), item (depth = the x+y the page sorts by), lift (the room's slice of the lift goes here), sign (the post or
  // the plaque is drawn by the renderer), and overlay (drawn after every room: the porch landing).
  let STACKED = false;
  function cutRoom(r) {
    const saved = [r.ox, r.oy, r.drop, R, g]; r.ox = OX; r.oy = OY; r.drop = 0;
    const cache = buildCache(r), byImage = new Map();
    for (const it of cache.items) if (!it.dyn) byImage.set(it.baked, it);
    const dynDraw = new Map(), layers = [], lights = [];
    let cur = { kind: 'back', depth: null }, inItem = false, curTag = null;
    const flush = () => {
      if (!dirty) return; dirty = false;
      const cut = cropRaw(); reset(raw); if (!cut) return;
      layers.push({ kind: cur.kind, depth: cur.depth, dyn: cur.dyn || undefined, sprite: ph(cut.img), x: cut.x - OX, y: cut.y - OY });
    };
    for (const it of cache.items) if (it.dyn) { const f = it.draw; dynDraw.set(it, f);
      it.draw = () => { flush(); cur = { kind: 'item', depth: depthOf(it), dyn: true }; inItem = true; f(); flush(); inItem = false; }; }
    blit = b => {
      if (!b) return; flush();
      const it = byImage.get(b); if (it) cur = { kind: 'item', depth: depthOf(it) };
      layers.push({ kind: cur.kind, depth: cur.depth, tag: curTag || undefined, sprite: ph(b.img), x: b.dx, y: b.dy });
    };
    still = (rr, name, key, paint) => { curTag = name; try { return real.still(rr, name, key, paint); } finally { curTag = null; } };
    pane = (pts, t, seed) => { flush(); layers.push({ kind: 'pane', pts: pts.map(q => [q[0] - OX, q[1] - OY]), fixedSeed: r.theme.pattern === 'glass' ? seed : undefined }); };
    drawSign = rr => { flush(); layers.push({ kind: 'sign', depth: rr.floor === 0 ? round1(rr.NX + rr.NY + 1.6) : null, variant: rr.floor === 0 ? 'post' : 'plaque' }); };
    drawLifts = (tt, f) => { flush(); layers.push({ kind: 'lift', room: 'self', depth: round1(LIFT.x0 + LIFT.y1 - LIFT.fl[f].yoff) }); };
    glow = (x, y, rad, color, k) => {
      flush(); // a glow inside a dynamic item is a light too (it is added, not painted over)
      lights.push({ sprite: glowSprite(color, rad), r: Math.max(1, Math.round(rad)), x: x - OX, y: y - OY, k, inItem: inItem || undefined });
    };
    reset(raw); dirty = false; g = cx;
    try { drawRoom(r, T, hourDate(fixedHour)); flush(); }
    finally {
      Object.assign(window, { blit: real.blit, drawSign: real.drawSign, drawLifts: real.drawLifts, glow: real.glow, pane: real.pane, still: real.still });
      for (const [it, f] of dynDraw) it.draw = f;
      [r.ox, r.oy, r.drop, R, g] = saved;
    }
    const sp = b => b ? { sprite: ph(b.img), x: b.dx, y: b.dy } : undefined;
    // stacked styles (no lift): the outside stairs of a stack go on top of every room, with the Clawds that are out on them between the two flights
    if (STACKED) return { layers, lights, overlay: [], esc: { back: sp(cache.escBack || cache.escTop), front: sp(cache.escFront) } };
    const overlay = cache.escTop ? [sp(cache.escTop)] : [];
    return { layers, lights, overlay };
  }
  const roomMeta = r => ({ growth: r.theme.shared ? undefined : growthLevel(r), clock: r.theme.clock || undefined, theme: themeOf(r), NX: r.NX, NY: r.NY, floor: r.floor, tower: r.tower, hub: r.theme.hub, lowH: r.theme.lowH, shared: !!r.theme.shared, open: !!r.theme.open });

  const result = { version: 4, S, WH, SLAB, FLOOR_STEP, buckets: BUCKETS, ambk: AMBK.slice(0, 9).map(r => ({ hour: r[0], amb: r[1], sky: [r[2], r[3]], dark: r[4] })) };
  const parts = result.rooms = {};
  if (want('rooms')) {
    const jobs = []; // [variant id, fixture projects, room key]
    fixture(natural(1)); jobs.push({ id: 'bath/g0', fx: natural(1), key: '__bath' }, { id: 'kitchen', fx: natural(1), key: '__kitchen' }, { id: 'roof', fx: natural(1), key: '__roof' });
    jobs.push({ id: 'bath/g1', fx: natural(2), key: '__bath' }, { id: 'bath/g2', fx: natural(3), key: '__bath' });
    for (const th of themeKeys) { const fx = [[NAMES[0], th], [NAMES[1], th]]; for (let gl = 0; gl < GROWTH_STEPS.length; gl++) jobs.push({ id: th + '/tower/g' + gl, fx, key: 'p:' + NAMES[0], gl }, { id: th + '/island/g' + gl, fx, key: 'p:' + NAMES[1], gl }); }
    const byFx = new Map();
    for (const j of jobs) { const k = JSON.stringify(j.fx); if (!byFx.has(k)) byFx.set(k, []); byFx.get(k).push(j); }
    for (const [, list] of byFx) {
      fixture(list[0].fx);
      for (const j of list) { const r = roomByKey.get(j.key);
        if (j.gl !== undefined) growth[r.name] = { n: GROWTH_STEPS[j.gl], ids: [] };
        parts[j.id] = { ...roomMeta(r), variants: [] };
        if (j.gl !== undefined) delete growth[r.name];
      }
      VARS.forEach((v, vi) => {
        fixedHour = 12;
        for (const j of list) { const r = roomByKey.get(j.key); if (j.gl !== undefined) growth[r.name] = { n: GROWTH_STEPS[j.gl], ids: [] }; parts[j.id].variants[vi] = dual(v.d, () => { r.cache = null; r.still = null; return cutRoom(r); }, true); if (j.gl !== undefined) delete growth[r.name]; }
      });
    }
    // The first shell must have the same silhouette as every later light cut (regression: clipped yard corner).
    const silhouettes = parts['bath/g0'].variants.map(v => {
      const f = frames[v.layers[0].sprite], { d } = words(f.img);
      return { w: f.w, h: f.h, mask: Array.from({ length: f.w * f.h }, (_, i) => d[i * 4 + 3] > 0 ? 1 : 0) };
    });
    const first = silhouettes[0];
    result.firstCutProof = { opaquePixels: silhouettes.map(s => s.mask.reduce((n, a) => n + a, 0)), sameSilhouette: silhouettes.every(s => s.w === first.w && s.h === first.h && s.mask.every((a, i) => a === first.mask[i])) };
    if (!result.firstCutProof.sameSilhouette) throw new Error('bath/g0 first cut silhouette differs across light variants');
    log('rooms', Object.keys(parts).length);
  }

  // ---------- the extra screens' islets: the page's isletDraw baked per light variant (clear weather), at the iso origin of the islet ----------
  // x, y are art pixels from that origin (bake's own dx, dy); the page puts the origin at (round(W * fx), round(H * fy + sin(t / 2600 + i * 2.1) * 2 * S)).
  // The camp's lamp glows (#ffc870, 30 * S) at alpha .1 + .25 * DARK while DARK > .3, at origin + the iso of lamp [x, y, z].
  if (want('islets')) {
    result.islets = ISLETS.map((it, i) => ({
      fx: it.fx, fy: it.fy, NX: it.NX, NY: it.NY, kind: it.kind, phase: +(i * 2.1).toFixed(4),
      lamp: it.lamp ? { x: round1((it.lamp[0] - it.lamp[1]) * 8 * S), y: round1((it.lamp[0] + it.lamp[1]) * 4 * S - it.lamp[2] * S), sprite: glowSprite('#ffc870', 30 * S), r: 30 * S, a: .1, b: .25, from: .3 } : undefined,
      variants: VARS.map(v => dual(v.d, () => { const b = bake(it, () => isletDraw(it)); return b ? { sprite: ph(b.img), x: b.dx, y: b.dy } : null; })),
    }));
    log('islets', result.islets.length);
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
    blit = b => { if (b) layers.push({ tag: name, sprite: ph(b.img), x: b.dx, y: b.dy }); };
    glow = (x, y, rad, color, k) => lights.push({ sprite: glowSprite(color, rad), r: Math.max(1, Math.round(rad)), x: x - WOX, y: y - WOY, k });
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
      const flush = () => { if (!dirty) return; dirty = false; const cut = cropRaw(); reset(raw); if (cut) out.push({ tag, sprite: ph(cut.img), x: cut.x - WOX, y: cut.y - WOY }); };
      blit = b => { if (!b) return; flush(); out.push({ tag: name, sprite: ph(b.img), x: b.dx, y: b.dy }); tag = 'after:' + name; };
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
    village.links = links.map((L, i) => ({ ...plan[i], variants: [] }));
    VARS.forEach((v, vi) => links.forEach((L, i) => {
      village.links[i].variants[vi] = dual(v.d, () => { L.bk = null; return L.kind === 'stair' ? { down: cutLinkAt(L, 0), up: cutLinkAt(L, 1) } : cutLinkAt(L, 0); }, true); L.lift = 0;
    }));
    // the plan must be a prefix of itself for every smaller count (a new project never moves the earlier ones)
    for (const n of [2, 3, 5, 8, 11]) { fixture(natural(n)); const p2 = links.map(linkRec); if (JSON.stringify(p2) !== JSON.stringify(plan.slice(0, p2.length))) log('PLAN NOT A PREFIX at', n); }
    // the lift for 3 floors (no project) and 4 (a project in the tower): its geometry, per bucket
    for (const n of [0, 1]) {
      fixture(natural(n)); wf0();
      const lift = { floors: LIFT.fl.length, shafts: LIFT.shafts.map(s => ({ cx: s.cx, cy: s.cy, x0: s.x0, x1: s.x1, y0: s.y0, y1: s.y1 })), x0: LIFT.x0, x1: LIFT.x1, y0: LIFT.y0, y1: LIFT.y1, top: LIFT.top,
        cageZ: liftZ(0), cageH: 28, fl: LIFT.fl.map(q => ({ room: q.r.key, yoff: q.yoff, z: q.z })), variants: [] };
      lift.variants = VARS.map(v => {
        const cut = dual(v.d, () => { LIFT.bk = new Map(); return cutLiftNow(); });
        const col = colorPair(v.d, () => lit('#3a2c20')), pul = [OUT, WOOD_L, WOOD].map(c => colorPair(v.d, () => lit(c)));
        return { ...cut, rope: col, pulley: pul };
      });
      village.lift['n' + LIFT.fl.length] = lift;
    }
    log('links', links.length, 'plan', plan.length);
  }

  // ---------- signs: the board is the page's pixel font, drawn from the text; the renderer draws it, we give the rules ----------
  const sign = result.sign = { font: SFONT, k: SK, rows: SH, post: 7 * S, src: { signImage: signImage.toString(), drawSign: drawSign.toString(), signText: signText.toString(), pfFit: pfFit.toString(), sfDraw: sfDraw.toString(), sfWidth: sfWidth.toString() }, variants: [] };
  sign.label = { note: 'r.label (a DOM div) is hidden by the page CSS ("rooms carry painted signs instead"); the sign is canvas art. If a DOM label is ever shown: font -apple-system,BlinkMacSystemFont,sans-serif 12px/1.3 weight 600, colour rgba(255,255,255,.9), background rgba(20,16,32,.55), padding 3px 9px, radius 999px.' };
  VARS.forEach((v, vi) => {
    const sl = (c, k = 1) => DARK > .3 ? emi(c, k * (1 - DARK * .3)) : lit(c, k); // the page's own (room/index.html:3633)
    const P = fn => colorPair(v.d, fn);
    const board = plaque => { const wood = plaque ? '#5a3a26' : '#b07a48', edge = plaque ? '#c89c60' : '#d8a870';
      return { rim: P(() => sl(OUT)), wood: P(() => sl(wood)), edge: P(() => sl(edge)), under: P(() => sl(wood, .78)), ink: P(() => sl('#fff0c8')), inkEdge: P(() => sl('#24161a')) }; };
    sign.variants[vi] = { sign: board(false), plaque: board(true), postRim: P(() => lit(OUT)), postWood: P(() => lit('#8a5a36')), shadow: 'rgba(0,0,0,.18)' };
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
      const back = paintS(() => bd.draw(T, d, P)); b.backdrop = back && { sprite: addConst(back.img), x: back.x, y: back.y };
      const cel = paintS(() => drawCelestial(T, d, P)); b.celestial = cel && { sprite: addConst(cel.img), x: cel.x, y: cel.y, sun: LAST_SUN };
      const cw = document.createElement('canvas'); cw.width = 12 * 131 * S + W + 80 * S; cw.height = H; const cwx = cw.getContext('2d', { willReadFrequently: true });
      const OFF = 80 * S; cwx.translate(OFF, 0); withG(cwx, () => drawClouds(0, { ...P, W: cw.width - 160 * S }));
      b.clouds = LAST_CLOUDS.map(([x, y, w], i) => { const c = document.createElement('canvas'); c.width = w + 2 * S; c.height = 12 * S;
        c.getContext('2d').drawImage(cw, x + OFF - S, y - 6 * S, c.width, c.height, 0, 0, c.width, c.height); return { i, w, y, sprite: addConst(c), dx: -S, dy: -6 * S }; });
      sky.buckets[bi] = b;
    });
    sky.rules = { clouds: 'cloud i is at x = round(((i*131*S + t*(.004+(i%3)*.002)*S) % (W+80*S)) - 60*S) + round(px*.8), y as recorded (cloud sprite i of the bucket: w, y); drawn with the sprite at (x+dx, y+dy); t in ms',
      gradient: 'vertical gradient SKY[0] -> SKY[1] over the screen height, then the sunrise glow bands of drawSky', sun: 'celestial layer is cut at its screen position for the screen size above; sun anchor in .sun' };
  }

  // ---------- Clawd and the residents: every pose, cut around its feet; ax, ay = the feet's offset inside the sprite ----------
  const poses = result.poses = { anchors: 'sprite drawn at (X - ax, Y - ay) where (X, Y) is the point drawClawd was given (the feet, iso of the spot)' };
  const poseProofJobs = [];
  if (want('poses')) {
    const fr = {}; // a stand-in room
    demo = false; // no hash-driven context batteries and drowsiness on the cut Clawds
    const base = (vendor, small, o) => ({ kind: 'agent', vendor, small, state: 'working', path: [], alpha: 1, moving: false, seated: false, waving: false, toss: 0, onBridge: null,
      seed: .3, goal: null, hold: null, fire: null, room: null, agent: { id: 'x', activity: 'Bash · ls' }, ...o });
    // The page draws a Clawd in phases: the shadow (pre), the body, the context battery and eyelids (info), the status marks (mark: the "!"
    // bubble, the error smoke, the Zs), drawBathing (bath: foam, towel; drawn by the scene as well) and drawProps (props: held things, the laptop, the fire).
    // The renderer draws the info and the marks itself (they follow the sprite while it walks), so bodies are cut WITHOUT them; "props" mode
    // cuts only what drawProps draws, for the overlays that ride on a plain body pose.
    const PH = { phase: 'pre' };
    const cut = (draw, mode = 'body') => {
      const layers = [];
      const dropped = mode === 'props' ? new Set(['pre', 'body', 'info', 'mark', 'bath']) : new Set(['info', 'mark', 'bath']);
      const flush = blend => { const c = cropRaw(100, 120, 400, 460); reset(raw); dirty = false;
        if (c) layers.push({ sprite: ph(c.img), ax: 300 - c.x, ay: 400 - c.y, blend }); };
      reset(raw); dirty = false;
      const saved = { drawBody, infoOverClawd, drawBathing }, fr = raw.fillRect;
      PH.phase = 'pre';
      raw.fillRect = function (...a) { if (!dropped.has(PH.phase)) fr.apply(this, a); };
      drawBody = (...a) => { PH.phase = 'body'; try { return mode === 'props' ? undefined : saved.drawBody(...a); } finally { PH.phase = 'info'; } };
      infoOverClawd = (...a) => { PH.phase = 'info'; try { return saved.infoOverClawd(...a); } finally { PH.phase = 'mark'; } };
      drawBathing = (...a) => { PH.phase = 'bath'; try { return saved.drawBathing(...a); } finally { PH.phase = 'props'; } };
      glow = (x, y, rad, color, k) => { if (dropped.has(PH.phase)) return; flush('normal'); withG(cx, () => real.glow(x, y, rad, color, mode === 'props' ? .3 : k)); flush('add'); };
      try { withG(cx, draw); flush('normal'); } finally { Object.assign(window, saved); delete raw.fillRect; glow = real.glow; }
      return layers.length ? { layers } : null;
    };
    const list = []; // [name, makeSprite, t]
    const add = (name, mk, ts) => (Array.isArray(ts) ? ts : [ts]).forEach((t, i) => list.push([ts.length > 1 || Array.isArray(ts) ? `${name}.${i}` : name, mk, t]));
    const frames_ = (n, period) => Array.from({ length: n }, (_, i) => Math.round(i * period / n));
    // waiting: the hop (round(|sin(t/260)|*3)) x the arm (sin > 0) make 14 steps of the 1634 ms cycle
    const waitB = [0, 0.1674, 0.5236, 0.9851, 2.1565, 2.618, 2.9742, Math.PI], waitCuts = [];
    for (let h = 0; h < 2; h++) for (let k = 0; k < 7; k++) waitCuts.push(Math.round((Math.PI * h + (waitB[k] + waitB[k + 1]) / 2) * 260));
    const looks = [['claude', false], ['claude', true], ['codex', false], ['codex', true]];
    const catalog = { // per look
      stand: [{}, [0]], walk: [{ moving: true }, [0, 110]], work: [{ seated: true }, [0, 160]],
      laptop: [{ goal: { cat: 'seat', room: fr }, room: fr }, [0, 700, 1400]],
      flask: [{ agent: { id: 'x', activity: 'Bash · pnpm test' } }, frames_(4, 800)], hammer: [{ agent: { id: 'x', activity: 'Edit · f.swift' } }, [0, 190]],
      binoculars: [{ agent: { id: 'x', activity: 'WebSearch · q' } }, [850, 0]], book: [{ agent: { id: 'x', activity: 'Read · f' } }, [0, 1976]],
      waiting: [{ state: 'waiting' }, waitCuts], waitwalk: [{ state: 'waiting', moving: true }, [10, 120, 880, 990]], // arm up/down (sin(t/260) > 0) x the walk's two hops
      error: [{ state: 'error' }, frames_(4, 1885)], sleep: [{ state: 'done' }, frames_(4, 1400)],
      shower: [{ state: 'shower' }, [0]], dry: [{ state: 'dry' }, [0]], fall: [{ state: 'fall' }, [0]], fallmv: [{ state: 'fall', moving: true }, [0, 110]],
      wave: [{ waving: true }, [0, 300]], toss: [{ toss: 800 }, [1000]],
      ext: [{ hold: { kind: 'ext', dir: 1 } }, [0]], extL: [{ hold: { kind: 'ext', dir: -1 } }, [0]], mail: [{ hold: { kind: 'mail', stage: 'go' } }, [0]], handover: [{ hold: { kind: 'handover', stage: 'walk' } }, [0]],
      fire: [{ fire: {} }, [0, 130]], fireFoam: [{ fire: { foamed: 900 } }, [1000]],
    };
    const homeCatalog = { stand: [{ state: 'idle' }, [0]], walk: [{ state: 'idle', moving: true }, [0, 110]], sleep: [{ state: 'idle-sleep' }, frames_(4, 1400)] };
    const jobs = []; // [name, () => sprite, t]
    for (const [v, small] of looks) for (const [k, [o, ts]] of Object.entries(catalog)) ts.forEach((t, i) => jobs.push([`${v}${small ? '-mini' : ''}/${k}.${i}`, () => base(v, small, o), t]));
    for (const [k, [o, ts]] of Object.entries(homeCatalog)) ts.forEach((t, i) => jobs.push([`home/${k}.${i}`, () => base('home', true, { kind: 'home', ...o }), t]));
    // ---- eggs: the page's eggLook() decides gold, raised arms and the April 1 eyes; cut through a stand-in that returns what the sprite carries ----
    for (const [v, small] of looks) {
      const L = `${v}${small ? '-mini' : ''}`, eg = e => o => ({ ...o, __egg: { dy: 0, ...e } });
      const gold = eg({ gold: GOLD }), arms = eg({ arms: 0 });
      for (const [k, [o, ts]] of Object.entries(catalog)) { ts.forEach((t, n) => jobs.push([`${L}/gold.${k}.${n}`, () => base(v, small, gold(o)), t])); }
      // raised arms (a high five: any still pose) and the April 1 eyes (any walk), each plain or golden: garms, geyep, geyen
      for (const g of ['', 'g']) {
        for (const k of ['stand', 'work', 'laptop', 'waiting']) { const [o, ts] = catalog[k]; ts.forEach((t, n) => jobs.push([`${L}/${g}arms.${k}.${n}`, () => base(v, small, g ? eg({ gold: GOLD, arms: 0 })(o) : arms(o)), t])); }
        for (const [tag, kk] of [['p', 1], ['n', -1]]) for (const k of ['walk', 'waitwalk']) { const [o, ts] = catalog[k]; ts.forEach((t, n) => jobs.push([`${L}/${g}eye${tag}.${k}.${n}`, () => base(v, small, eg(g ? { gold: GOLD, eye: kk } : { eye: kk })(o)), t])); }
      }
    }
    // the cat and the dog, both ways
    const pet = (kind, face, o) => ({ kind, alpha: 1, path: [], onBridge: null, moving: false, seed: 0, face, ...o });
    for (const face of [1, -1]) {
      const f = face > 0 ? 'r' : 'l';
      jobs.push([`cat/walk1.${f}`, () => pet('cat', face, { moving: true }), 0], [`cat/walk2.${f}`, () => pet('cat', face, { moving: true }), 120],
        [`cat/sit2.${f}`, () => pet('cat', face, { pose: 'sit' }), 0], [`cat/sit1.${f}`, () => pet('cat', face, { pose: 'sit' }), 700]);
      jobs.push([`cat/nap.${f}`, () => pet('cat', face, { pose: 'nap' }), 1799.9]); // the Zs are drawn by the scene: cut at k = .9999 (alpha 0)
      jobs.push([`dog/walk1.${f}`, () => pet('dog', face, { moving: true }), 0], [`dog/walk2.${f}`, () => pet('dog', face, { moving: true }), 120],
        [`dog/walk1ball.${f}`, () => pet('dog', face, { moving: true, ball: true }), 0], [`dog/walk2ball.${f}`, () => pet('dog', face, { moving: true, ball: true }), 120],
        [`dog/sit2.${f}`, () => pet('dog', face, { pose: 'sit' }), 0], [`dog/sit1.${f}`, () => pet('dog', face, { pose: 'sit' }), 900],
        [`dog/sit2ball.${f}`, () => pet('dog', face, { pose: 'sit', ball: true }), 0], [`dog/sit1ball.${f}`, () => pet('dog', face, { pose: 'sit', ball: true }), 900]);
      [0, 260, 520, 780].forEach((t, i) => jobs.push([`dog/bark.${f}.${i}`, () => pet('dog', face, { pose: 'bark' }), t]));
      jobs.push([`dog/nap.${f}`, () => pet('dog', face, { pose: 'nap' }), 1899.9]);
    }
    // ---- overlays: what drawProps draws on top of a plain body pose (cut with mode 'props', the body left out) ----
    // Held things (the page's drawProps chain: letter, paper, extinguisher) ride on stand/walk bodies: s = standing, w0/w1 = the two hops of a walk
    // (the body bobs by one cell every 110 ms). The fire's glow is cut at its brightest (.30); the renderer scales the layer's alpha by
    // (.22 + .08 sin(t/90)) / .30. A fire is two frames, floor(t/130 + seed*5) % 2 (the cut seed is .3: t = 0 is frame 1, t = 130 frame 0).
    const hops = [['s', {}, 0], ['w0', { moving: true }, 0], ['w1', { moving: true }, 110]];
    for (const [v, small] of looks) {
      const L = `${v}${small ? '-mini' : ''}`;
      for (const [k, hold] of Object.entries({ ext: { kind: 'ext', dir: 1 }, extL: { kind: 'ext', dir: -1 }, mail: { kind: 'mail', stage: 'go' }, handover: { kind: 'handover', stage: 'walk' } }))
        for (const [tag, extra, t] of hops) jobs.push([`${L}/o.${k}.${tag}`, () => base(v, small, { hold, ...extra }), t, 'props']);
      for (const [fk, fire] of [['fire', {}], ['fireS', { foamed: -100 }]])
        for (const [idx, t] of [[1, 0], [0, 130]]) jobs.push([`${L}/o.${fk}.${idx}`, () => base(v, small, { state: 'error', fire }), t, 'props']);
    }
    for (const [k, hold] of Object.entries({ ext: { kind: 'ext', dir: 1 }, extL: { kind: 'ext', dir: -1 } }))
      for (const [tag, extra, t] of hops) jobs.push([`home/o.${k}.${tag}`, () => base('home', true, { kind: 'home', state: 'idle', hold, ...extra }), t, 'props']);
    { const hm = o => () => base('home', true, { kind: 'home', state: 'idle', room: fr, ...o });
      frames_(4, 1100).forEach((t, i) => jobs.push([`home/o.mug.s${i}`, hm({ scene: 'coffee', goal: { cat: 'coffee', room: fr } }), t, 'props']));
      [0, 110].forEach((t, i) => jobs.push([`home/o.mug.w${i}`, hm({ scene: 'coffee', moving: true }), t, 'props']));
      jobs.push(['home/o.can.s', hm({ scene: 'water', goal: { cat: 'wash', room: fr } }), 0, 'props']);
      frames_(3, 600).forEach((t, i) => jobs.push([`home/o.can.p${i}`, hm({ scene: 'water', goal: { cat: 'water', room: fr } }), t, 'props']));
      [0, 110].forEach((t, i) => jobs.push([`home/o.can.w${i}`, hm({ scene: 'water', moving: true, goal: { cat: 'wash', room: fr } }), t, 'props']));
      [0, 1976].forEach((t, i) => jobs.push([`home/o.book.${i}`, hm({ scene: 'read', goal: { cat: 'read', room: fr } }), t, 'props'])); }
    for (const name of ['claude/stand.0', 'claude/walk.1', 'claude/work.1', 'claude/fire.1']) poseProofJobs.push(jobs.find(j => j[0] === name));
    poses.names = jobs.map(j => j[0]);
    poses.composition = 'Draw layers in order at (X-ax,Y-ay); blend normal = source-over, add = additive (SpriteKit .add). Fire glow is a separate add layer between the body and flames.';
    const realEggLook = eggLook; eggLook = sp => sp.__egg || null;
    poses.variants = VARS.map(v => dual(v.d, () => { const out = {};
      for (const [name, mk, t, mode] of jobs) { const sp = mk(); const c = cut(() => drawClawd(300, 400, sp, t), mode); if (c) out[name] = c; }
      return out; }));
    eggLook = realEggLook;
    poses.timing = { walk: 'frame = floor(t/110) % 2 (legs and hop)', work: 'frame = floor(t/160) % 2', waiting: 'sample i of 6 over 1634 ms: sin(t/260)', error: '4 over 1885 ms', sleep: '4 over 1400 ms (the Zs rise k=(t/1400+seed)%1)',
      shower: '6 over 9000 ms (k=(t/9000+seed)%1)', dry: '6 over 1382 ms', hammer: 'down = floor(t/190 + seed*3) % 2', cat: 'walk floor(t/120)%2; sit2 when floor(t/700+seed*7)%6==0; nap Zs (t/1800+seed)%1', dog: 'walk floor(t/120)%2 (90 when fast); sit2 when floor(t/900+seed*7)%6==0 (wag: floor(t/140)%2==0); bark: sit1/bark floor(t/260)%2 and the text on when floor(t/520)%2==0' };
    // the geometry the renderer needs to put marks over a Clawd (drawClawd: left = round(X - w*S/2), top = round(Y - (rows + legH)*S - hop), arm rows)
    poses.looks = Object.fromEntries([...looks.map(([v, small]) => [`${v}${small ? '-mini' : ''}`, { v, small }]), ['home', { v: 'home', small: true }]].map(([k, { v, small }]) => {
      const L = lookOf({ vendor: v, small }), eyes = [];
      L.rows.forEach((row, r) => [...row].forEach((ch, c) => { if (ch === 'E') eyes.push([c, r]); }));
      return [k, { w: L.rows[0].length, rows: L.rows.length, legH: small ? 1 : 2, arm: L.arm, lift: L.lift, body: VENDOR[v][0], eyes }]; }));
    // the desk lamp's glow over a busy desk at night (drawSceneOverlays): the page's own gradient, '#ffc870' at 26*S, stamped at alpha .55*(DARK-.3)
    poses.lamp = { sprite: glowSprite('#ffc870', 26 * S), r: 26 * S };
    log('poses', jobs.length);
  }


  // ---------- stacked styles: the rooms of 'steps' and 'towers' (stacks of three joined by outside stairs, no lift, yard or links) ----------
  // A room's art depends on its place in the stack: the ground floor has the grass and the post sign, a room with another above has
  // taller walls and the stairs' two flights (esc.back/front), the top one has the landing alone (esc.back), a lone ground room none.
  // Steps and towers draw each room the same way; only where the stacks stand differs (HouseLayout). Keys: theme/stk/role/gN, bath|kitchen|roof/stk.
  if (want('stacked')) {
    const saved = LAYOUT; LAYOUT = 'steps'; STACKED = true;
    try {
      const roleOf = r => r.floor === 0 ? (roomAt(r.tower, 1) ? 'g2' : 'g1') : (roomAt(r.tower, r.floor + 1) ? 'm' : 't');
      const cutStack = (th, wants) => { // five projects: tower 0 holds the first (middle), tower 1 three (ground, middle, top), tower 2 one (lone ground)
        fixture(NAMES.slice(0, 5).map(n => [n, th]));
        const out = [];
        for (const r of rooms) { const role = roleOf(r), id = r.theme.shared ? themeOf(r) + '/stk' : th + '/stk/' + role;
          if (r.theme.shared ? wants.shared : wants.role.includes(role) && (role !== 'm' || r.key === 'p:' + NAMES[2])) out.push({ id, r, role }); }
        return out;
      };
      for (const th of themeKeys) {
        for (let gl = 0; gl < GROWTH_STEPS.length; gl++) {
          const jobs = cutStack(th, { role: ['g1', 'g2', 'm', 't'], shared: th === themeKeys[0] && gl === 0 });
          for (const j of jobs) { const id = j.r.theme.shared ? j.id : j.id + '/g' + gl; if (!parts[id]) { if (!j.r.theme.shared) growth[j.r.name] = { n: GROWTH_STEPS[gl], ids: [] }; parts[id] = { ...roomMeta(j.r), role: j.role, variants: [] }; if (!j.r.theme.shared) delete growth[j.r.name]; } j.id = id; }
          VARS.forEach((v, vi) => {
            fixedHour = 12;
            for (const j of jobs) { const r = j.r; if (!r.theme.shared) growth[r.name] = { n: GROWTH_STEPS[gl], ids: [] }; parts[j.id].variants[vi] = dual(v.d, () => { r.cache = null; r.still = null; return cutRoom(r); }, true); if (!r.theme.shared) delete growth[r.name]; }
          });
        }
      }
    } finally { LAYOUT = saved; STACKED = false; }
    fixture(natural(1)); // back to the islands for what follows
    log('stacked', Object.keys(parts).filter(k => k.includes('/stk')).length);
  }

  // ---------- packing: shelves on pages of up to 4096 px, 2 px of air around each sprite; F pages and E pages share every rect ----------
  const PAGE = 4096, PAD = 2, pages = [], atlas = new Array(frames.length);
  const order = frames.map((f, i) => i).sort((a, b) => frames[b].h - frames[a].h || frames[b].w - frames[a].w);
  let pg = null, sx = 0, sy = 0, rowH = 0;
  const newPage = () => { const mk = () => { const c = document.createElement('canvas'); c.width = PAGE; c.height = PAGE; return c; }; pg = { cv: mk(), ev: mk(), h: 0 }; pg.ctx = pg.cv.getContext('2d'); pg.ectx = pg.ev.getContext('2d'); pages.push(pg); sx = PAD; sy = PAD; rowH = 0; };
  newPage();
  for (const i of order) {
    const { w, h, img, e, flag } = frames[i];
    if (sx + w + PAD > PAGE) { sx = PAD; sy += rowH + PAD; rowH = 0; }
    if (sy + h + PAD > PAGE) newPage();
    pg.ctx.drawImage(img, sx, sy); if (e) pg.ectx.drawImage(e, sx, sy);
    atlas[i] = [pages.length - 1, sx, sy, w, h, flag];
    sx += w + PAD; rowH = Math.max(rowH, h); pg.h = Math.max(pg.h, sy + h + PAD);
  }
  result.pages = pages.map((p, i) => {
    const hh = Math.min(PAGE, 1 << Math.ceil(Math.log2(p.h)));
    const c = document.createElement('canvas'); c.width = PAGE; c.height = hh; c.getContext('2d').drawImage(p.cv, 0, 0);
    const ce = document.createElement('canvas'); ce.width = PAGE; ce.height = hh; ce.getContext('2d').drawImage(p.ev, 0, 0);
    post(`parts-${i}.png`, c.toDataURL('image/png')); post(`parts-${i}-e.png`, ce.toDataURL('image/png'));
    return { file: `parts-${i}.png`, fileE: `parts-${i}-e.png`, w: PAGE, h: hh };
  });
  const flags = [0, 0, 0]; atlas.forEach(a => flags[a[5]]++);
  result.atlasStats = { sprites: atlas.length, general: flags[0], eBlack: flags[1], constant: flags[2] };

  // ---------- the proof: compose frames from the parts alone, as the renderer will, and compare with the page's own frame ----------
  // The composer takes from the page only the layout (rooms' ox/oy and tower/floor, links, LIFT, the draw order) and the uniforms the
  // renderer owns: AMB, DARK, SKY of the hour (setTime). Every room, link, lift, sign, glow and pane is drawn from the manifest and the
  // packed pages: lit sprites as out = E + (F - E) * AMB / FA per channel (alpha: Ea + (Fa - Ea) * AMB[0] / FA), the variant of the hour's DARK.
  const proof = result.proof = [];
  const readPage = (c, x, y, w, h) => c.getContext('2d').getImageData(x, y, w, h);
  let SH_CACHE = new Map(); // sprite id -> shaded canvas for the current AMB
  function shaded(id) {
    let c = SH_CACHE.get(id); if (c) return c;
    const [p, x, y, w, h, flag] = atlas[id], F = readPage(pages[p].cv, x, y, w, h);
    c = document.createElement('canvas'); c.width = w; c.height = h;
    if (flag === 2) { c.getContext('2d').putImageData(F, 0, 0); } else {
      const E = flag === 1 ? null : readPage(pages[p].ev, x, y, w, h), o = new ImageData(w, h), f = F.data, d = o.data;
      for (let i = 0; i < f.length; i += 4) {
        for (let k = 0; k < 3; k++) { const e = E ? E.data[i + k] : 0; d[i + k] = e + (f[i + k] - e) * AMB[k] / FA + .5 | 0; }
        d[i + 3] = E ? E.data[i + 3] + (f[i + 3] - E.data[i + 3]) * AMB[0] / FA + .5 | 0 : f[i + 3];
      }
      c.getContext('2d').putImageData(o, 0, 0);
    }
    SH_CACHE.set(id, c); return c;
  }
  const drawSpr = (ctx, id, x, y) => { if (!atlas[id]) throw new Error('no sprite ' + id); ctx.drawImage(shaded(id), x, y); };
  const mixCol = pr => 'rgb(' + [0, 1, 2].map(k => Math.max(0, Math.min(255, Math.round(pr.E[k] + (pr.F[k] - pr.E[k]) * AMB[k] / FA)))).join(',') + ')';
  const fitText = s => { s = String(s || '').toUpperCase().replace(/\s+/g, ' ').trim(); return [...s].length > 18 ? [...s].slice(0, 17).join('') + '…' : s; };
  const glyph = ch => (sign.font[ch] || sign.font[ch.toUpperCase()] || sign.font['?']).split('/');
  const sfW = s => [...s].reduce((w, ch, i) => w + glyph(ch)[0].length + (i ? 1 : 0), 0);
  function drawSignParts(ctx, room, vi) { // the page's signImage + drawSign, from the manifest's rules and colours
    const b = sign.variants[vi], text = fitText(room.theme.shared ? room.theme.name : room.name), plaque = room.floor > 0, c = plaque ? b.plaque : b.sign, C = {}; for (const k in c) C[k] = mixCol(c[k]);
    const tw = sfW(text) * sign.k, w = tw + 8, h = sign.rows * sign.k + 6, img = document.createElement('canvas'); img.width = w + 2; img.height = h + 2;
    const k = img.getContext('2d'), rc = (col, x, y, ww, hh) => { k.fillStyle = col; k.fillRect(x, y, ww, hh); };
    rc(C.rim, 0, 1, w + 2, h); rc(C.rim, 1, 0, w, h + 2); rc(C.wood, 1, 1, w, h); rc(C.edge, 2, 1, w - 2, 1); rc(C.under, 2, h, w - 2, 1);
    const stamp = (dx, dy, col) => { let x = 5 + dx; k.fillStyle = col; for (const ch of text) { const gl = glyph(ch); gl.forEach((row, r) => { for (let q = 0; q < row.length; q++) if (row[q] === '#') k.fillRect(x + q * sign.k, 4 + dy + r * sign.k, sign.k, sign.k); }); x += (gl[0].length + 1) * sign.k; } };
    for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]]) stamp(dx, dy, C.inkEdge);
    stamp(0, 0, C.ink);
    if (!plaque) {
      const [px, py] = [room.ox + (room.NX + .55 - (room.NY + .55)) * 8 * S, room.oy + (room.NX + .55 + room.NY + .55) * 4 * S + SLAB * S], X = Math.round(px), Y = Math.round(py), post = sign.post;
      ctx.fillStyle = mixCol(b.postRim); ctx.fillRect(X - S - 1, Y - post - 1, 2 * S + 2, post + 2);
      ctx.fillStyle = mixCol(b.postWood); ctx.fillRect(X - S, Y - post, 2 * S, post);
      ctx.fillStyle = b.shadow; ctx.fillRect(X - 3 * S, Y, 6 * S, 1);
      ctx.drawImage(img, X - (img.width >> 1), Y - post - img.height + 2 * S);
    } else {
      const px = room.ox + (room.NX * .78 - room.NY) * 8 * S, py = room.oy + (room.NX * .78 + room.NY) * 4 * S + SLAB / 2 * S;
      ctx.drawImage(img, Math.round(px - img.width / 2), Math.round(py - img.height / 2));
    }
  }
  const clockColors = result.clockColors = VARS.map(v => { const o = {}; for (const dk of [0, 1]) o[dk ? 'dark' : 'light'] = { out: colorPair(v.d, () => lit(OUT)), bg: colorPair(v.d, () => dk ? emi('#14141c') : lit('#f4f0e6')), fg: colorPair(v.d, () => dk ? emi('#ff5a4a') : lit('#3a2a2a')) }; return o; });
  result.clockFont = FONT;
  function drawClockParts(ctx, room, vi) { // the page's drawClock with the manifest's colours: the digits are the time of the frame
    const c = room.theme.clock, cc = clockColors[vi][c.dark ? 'dark' : 'light'], text = clockText(hourDate(fixedHour));
    const at = (col, row) => c.wall === 'L' ? isoAt(room.ox, room.oy, .03, c.at - col / 8, c.z - row) : isoAt(room.ox, room.oy, c.at + col / 8, .03, c.z - row);
    withG(ctx, () => { const saved = R; R = { ox: 0, oy: 0, drop: 0 };
      poly([at(-2, -2), at(20, -2), at(20, 7), at(-2, 7)].map(q => q), mixCol(cc.out)); poly([at(-1, -1), at(19, -1), at(19, 6), at(-1, 6)], mixCol(cc.bg));
      let col = 0; ctx.fillStyle = mixCol(cc.fg);
      for (const ch of text) { const f = FONT[ch]; for (let r = 0; r < 5; r++) for (let k = 0; k < 3; k++) if (f[r * 3 + k] === '1') { const [px, py] = at(col + k, r); rect(Math.round(px), Math.round(py), S, S); } col += ch === ':' || ch === ' ' ? 3 : 4; }
      R = saved; });
  }
  const seedForRoom = key => { let h = 7; for (const ch of key) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return key === '__yard' ? 11 : h % 97; };
  function drawPaneParts(ctx, room, l) { // the page's pane(): the sky outside (SKY uniform), stars when DARK > .55, a soft reflection; clear weather
    const pts = l.pts.map(q => [q[0] + room.ox, q[1] + room.oy]), seed = l.fixedSeed ?? seedForRoom(room.key);
    ctx.save(); ctx.beginPath(); pts.forEach((q, i) => i ? ctx.lineTo(Math.round(q[0]), Math.round(q[1])) : ctx.moveTo(Math.round(q[0]), Math.round(q[1]))); ctx.closePath(); ctx.clip();
    const ys = pts.map(q => q[1]), xs = pts.map(q => q[0]), top = Math.min(...ys), bot = Math.max(...ys), lft = Math.min(...xs), rgt = Math.max(...xs);
    const gr = ctx.createLinearGradient(0, top, 0, bot); gr.addColorStop(0, SKY[0]); gr.addColorStop(1, SKY[1]); ctx.fillStyle = gr; ctx.fillRect(lft, top, rgt - lft, bot - top);
    if (DARK > .55) for (let i = 0; i < (rgt - lft) / 4; i++) { const x = lft + ((i * 37 + seed) % (rgt - lft)), y = top + ((i * 53 + seed) % (bot - top)); ctx.fillStyle = `rgba(255,255,255,${.5 + .4 * Math.sin(T / 1500 + i)})`; ctx.fillRect(Math.round(x), Math.round(y), S, S); }
    ctx.fillStyle = 'rgba(255,255,255,.18)'; ctx.fillRect(lft + (rgt - lft) * .15, top, 3, bot - top);
    ctx.restore();
  }
  const isoAt = (ox, oy, x, y, z) => [ox + (x - y) * 8 * S, oy + (x + y) * 4 * S - z * S];
  function drawLiftSlice(ctx, wf, f, vi) { // one floor's piece of the lift: frame, ropes, cages standing in it, head and pulleys
    const lf = village.lift['n' + LIFT.fl.length], v = lf.variants[vi], fl = v.floors[f], cages = v.cages, items = [];
    for (const p of fl.pieces) items.push({ key: p.key, draw: () => drawSpr(ctx, p.sprite, wf.ox + p.x, wf.oy + p.y) });
    LIFT.cabins.forEach((c, i) => {
      const z = c.z, r0 = Math.max(fl.zlo, z + lf.cageH + 2), r1 = Math.min(fl.zhi, lf.top + 3);
      if (r1 > r0) items.push({ key: i * .01 + .001, draw: () => { const a = isoAt(wf.ox, wf.oy, lf.shafts[i].cx, lf.shafts[i].cy, r1), b = isoAt(wf.ox, wf.oy, lf.shafts[i].cx, lf.shafts[i].cy, r0);
        ctx.fillStyle = mixCol(v.rope); ctx.fillRect(Math.round(a[0]), Math.min(Math.round(a[1]), Math.round(b[1])), 1, Math.abs(Math.round(b[1]) - Math.round(a[1])) + 1); } });
      if (z >= fl.zlo && z < fl.zhi) for (const cg of cages) if (cg.shaft === i && (c.state === 'open' ? cg.part !== 'front' : cg.part !== 'frontOpen'))
        items.push({ key: cg.key, draw: () => drawSpr(ctx, cg.sprite, wf.ox + cg.x, wf.oy + cg.y - (z - lf.cageZ) * S) });
    });
    items.sort((a, b) => a.key - b.key).forEach(it => it.draw());
  }
  function roomPartOf(r) {
    if (r.key === '__bath') return parts['bath/g' + links.filter(L => L.a === YARD).length];
    if (r.theme.shared) return parts[r.key.slice(2)];
    return parts[themeOf(r) + (r.tower === 0 ? '/tower' : '/island') + '/g' + growthLevel(r)];
  }
  const glows = (ctx, list, ox, oy) => { ctx.save(); ctx.globalCompositeOperation = 'lighter';
    for (const l of list) { const k = Math.min(1, l.a + l.b * DARK); if (k <= 0) continue; ctx.globalAlpha = k; drawSpr(ctx, l.sprite, Math.round(ox + l.x) - l.r, Math.round(oy + l.y) - l.r); } ctx.restore(); };
  function drawRoomParts(ctx, r, vi, wf) {
    const v = roomPartOf(r).variants[vi]; let lit_ = false;
    for (const l of v.layers) {
      if (l.kind === 'sign' && l.variant === 'plaque' && !lit_) { glows(ctx, v.lights, r.ox, r.oy); lit_ = true; }
      if (l.kind === 'lift') drawLiftSlice(ctx, wf, village.lift['n' + LIFT.fl.length].fl.findIndex(q => q.room === r.key), vi);
      else if (l.kind === 'sign') drawSignParts(ctx, r, vi);
      else if (l.kind === 'pane') drawPaneParts(ctx, r, l);
      else if (l.tag === 'clock') drawClockParts(ctx, r, vi);
      else drawSpr(ctx, l.sprite, r.ox + l.x, r.oy + l.y);
    }
    if (!lit_) glows(ctx, v.lights, r.ox, r.oy);
  }
  const planIndex = L => village.plan.findIndex(q => q.kind === L.kind && JSON.stringify(q.A) === JSON.stringify(L.A) && JSON.stringify(q.B) === JSON.stringify(L.B));
  function drawLinkParts(ctx, L, vi, wf) {
    const i = planIndex(L); if (i < 0) throw new Error('link not in the plan');
    const b = village.links[i].variants[vi], d = L.kind === 'stair' ? (L.lift ? b.up : b.down) : b;
    for (const l of d.layers) drawSpr(ctx, l.sprite, wf.ox + l.x, wf.oy + l.y);
    glows(ctx, d.lights, wf.ox, wf.oy);
  }
  // the screen: sky from the parts at a bucket hour, else the page's own
  let OWNBG = null;
  function drawSkyParts(ctx, hour, ownSky) {
    const W = cv.width, H = cv.height, d = hourDate(hour);
    if (ownSky) { ctx.drawImage(OWNBG, 0, 0); return; }
    const b = sky.buckets[BUCKETS.indexOf(hour)], P = { W, H, ground: sky.ground, hr: hour, px: 0, py: 0 };
    withG(ctx, () => drawSky(P));
    if (b.backdrop) drawSpr(ctx, b.backdrop.sprite, b.backdrop.x, b.backdrop.y);
    if (b.celestial) drawSpr(ctx, b.celestial.sprite, b.celestial.x, b.celestial.y);
    for (const c of b.clouds) { const x = Math.round(((c.i * 131 * S + T * (.004 + (c.i % 3) * .002) * S) % (W + 80 * S)) - 60 * S); drawSpr(ctx, c.sprite, x + c.dx, c.y + c.dy); }
  }
  function composeFrame(hour, ownSky) {
    const c = document.createElement('canvas'); c.width = cv.width; c.height = cv.height; const ctx = c.getContext('2d');
    SH_CACHE = new Map(); const vi = varOf(DARK), wf = worldFrame();
    drawSkyParts(ctx, hour, ownSky);
    for (const it of drawOrder()) { if (it.room) drawRoomParts(ctx, it.room, vi, wf); else drawLinkParts(ctx, it.link, vi, wf); }
    for (const r of rooms) for (const o of roomPartOf(r).variants[vi].overlay) drawSpr(ctx, o.sprite, r.ox + o.x, r.oy + o.y);
    withG(ctx, () => drawMist(T, hourDate(hour))); // the dawn mist is a screen effect the renderer owns; the page's own pass is used here
    return { c, vi };
  }
  const grab = c => c.getContext('2d').getImageData(0, 0, c.width, c.height);
  if (want('proof')) for (const [n, hour] of [0, 1, 2, 3, 5, 14].flatMap(n => [0, 6.5, 10, 12, 19.25, 20, 21, 23].map(h => [n, h]))) {
    const exact = BUCKETS.includes(hour);
    fixture(natural(n)); for (const r of rooms) r.born = -1e9;
    const bgc = document.createElement('canvas'); bgc.width = cv.width; bgc.height = cv.height; const realBG = drawBackground;
    drawBackground = (t, d) => { realBG(t, d); bgc.getContext('2d').drawImage(cv, 0, 0); }; // the sky as the page's own frame drew it
    fixedHour = hour; try { frame(T); } finally { drawBackground = realBG; } // the page's own frame (nothing but the house: no agents, no residents); it leaves AMB, DARK, SKY of the hour set
    const ref = document.createElement('canvas'); ref.width = cv.width; ref.height = cv.height; ref.getContext('2d').drawImage(cv, 0, 0);
    const bg = bgc;
    const ownSky = !exact || cv.width !== sky.W || cv.height !== sky.H;
    OWNBG = bgc; const { c: ours, vi } = composeFrame(hour, ownSky);
    const poseCase = n === 2 && hour === 20;
    if (poseCase) {
      const reference = ref.getContext('2d'), ctx = ours.getContext('2d'), r = roomByKey.get('__bath');
      poseProofJobs.forEach(([name, mk, t], i) => {
        const X = r.ox - 100 + i * 65, Y = r.oy + 110;
        withG(reference, () => drawClawd(X, Y, mk(), t));
        for (const l of poses.variants[vi][name].layers) { ctx.save(); ctx.globalCompositeOperation = l.blend === 'add' ? 'lighter' : 'source-over'; drawSpr(ctx, l.sprite, X - l.ax, Y - l.ay); ctx.restore(); }
      });
    }
    const a = grab(ref).data, b = grab(ours).data, k = grab(bg).data, W = cv.width, H = cv.height, out = new ImageData(W, H);
    let diff = 0, house = 0, houseDiff = 0; const cells = new Map();
    for (let i = 0; i < a.length; i += 4) {
      const m = Math.max(Math.abs(a[i] - b[i]), Math.abs(a[i + 1] - b[i + 1]), Math.abs(a[i + 2] - b[i + 2])), isHouse = Math.abs(a[i] - k[i]) + Math.abs(a[i + 1] - k[i + 1]) + Math.abs(a[i + 2] - k[i + 2]) > 0;
      if (isHouse) house++; if (m > 24) { diff++; if (isHouse) { houseDiff++; const px = (i >> 2) % W, py = Math.floor((i >> 2) / W), ck = (px >> 5) + ',' + (py >> 5); const q = cells.get(ck) || { n: 0, ref: [a[i], a[i + 1], a[i + 2]], ours: [b[i], b[i + 1], b[i + 2]], x: px, y: py }; q.n++; cells.set(ck, q); } }
      out.data[i] = m > 24 ? 255 : a[i] >> 2; out.data[i + 1] = m > 24 ? 0 : a[i + 1] >> 2; out.data[i + 2] = m > 24 ? 0 : a[i + 2] >> 2; out.data[i + 3] = 255;
    }
    const dc = document.createElement('canvas'); dc.width = W; dc.height = H; dc.getContext('2d').putImageData(out, 0, 0);
    const tag = `n${n}-h${hour}`;
    post(`check/${tag}-page.png`, ref.toDataURL('image/png')); post(`check/${tag}-parts.png`, ours.toDataURL('image/png')); post(`check/${tag}-diff.png`, dc.toDataURL('image/png'));
    proof.push({ projects: n, hour, poses: poseCase ? poseProofJobs.map(j => j[0]) : undefined, dark: +DARK.toFixed(3), variant: vi, sky: ownSky ? "the page's own" : 'from parts', pixels: W * H, diffOver24: diff, pctWhole: +(100 * diff / (W * H)).toFixed(4),
      housePixels: house, houseDiffOver24: houseDiff, hot: [...cells.values()].sort((p, q) => q.n - p.n).slice(0, 8), pctHouse: +(100 * houseDiff / Math.max(1, house)).toFixed(4) });
    log(tag, 'var', vi, 'house', houseDiff + '/' + house, (100 * houseDiff / Math.max(1, house)).toFixed(4) + '%', 'whole', (100 * diff / (W * H)).toFixed(4) + '%');
  }
  result.proofNote = 'diff = pixels whose largest channel difference is > 24 against the page\'s own frame at t=100000 (no residents, clear weather; n2 h20 adds stand/walk/work/fire agents over the house); house = pixels the house changed against the sky-only frame. The sky is the page\'s own except at the bucket hours 12 and 20 (sky parts).';

  result.light = {
    model: 'out.rgb = clamp(E.rgb + (F.rgb - E.rgb) * AMB.rgb / FA) per channel; out.a = Ea + (Fa - Ea) * AMB.r / FA (only glass differs in alpha); FA = .5 (see fA). F = the piece cut with AMB = FA,FA,FA, E = with AMB = 0,0,0 (same DARK), same atlas rect in parts-N.png (F) and parts-N-e.png (E). Sprite flag (atlas[id][5]): 0 general, 1 E is black (out.rgb = F.rgb * AMB.rgb / FA, alpha = Fa: no E sample), 2 constant (E not stored: draw F as is; glows, sky).',
    ambAt: 'AMB, DARK and SKY for an hour come from ambk by linear interpolation between rows (setTime): AMB, SKY and DARK are mixed with t = (hour - a.hour)/(b.hour - a.hour); row 24 repeats row 0. DARK is ambk[].dark.',
    alpha: 'Textures store straight alpha. The light formula applies to unpremultiplied RGB, clamped to [0,1]. For a premultiplied renderer, unpremultiply the inputs, evaluate, then multiply by output alpha and clamp RGB to [0,alpha].',
    thresholds: THRESH, variants: VARS, variantOf: 'At DARK == .3 select the variant marked exact (the page mixes > .3 and >= .3); otherwise variant i is the first non-exact with DARK <= variants[i].hi; every layer list, light list, sign colour pair, lift colour and pose set is cut once per variant at DARK = variants[i].d',
    fA: FA,
    fWhy: 'F is cut at AMB = .5, not 1: lit() clamps at 255, so colours with k > 1 clamp in an AMB = 1 cut and come out up to 25/255 too dark at dusk. At .5 nothing clamps; the shader multiplies by AMB / fA (= 2 AMB) and the final clamp is the page\'s.',
    glows: 'a light is drawn with blend add at alpha min(1, a + b * DARK) (a, b measured by cutting at DARK and DARK + .004 (-.004 at the exact .3 boundary)), sprite = unit glow of its colour and radius, at (origin + x, origin + y) - r',
    clock: 'the clock face is the layer tagged "clock": cut at 12:00 (drawClock draws clockText(d)); the renderer re-draws the digits for another time',
    sunlight: 'the layer tagged "sunlight" is a floor patch of rgba(255,244,210,k), k = (1 - DARK/.4) * .12 (.05 clouds) while DARK < .4: baked at the variant DARK (error under 3/255)',
    pane: 'layer kind "pane" is a window glass polygon (unrounded pts relative to the room origin; round only the clipping path, use raw bounds for gradient/stars/reflection); the renderer draws it live: vertical gradient SKY[0] -> SKY[1] over the polygon bounds, stars when DARK > .55 (rgba(255,255,255,.5+.4*sin(t/1500+i)) for i < width/4 at x = lft + (i*37+seed) % w, y = top + (i*53+seed) % h, size S), then a 3 px reflection rgba(255,255,255,.18) at lft + .15*w. SKY is the sky colours of the hour (a uniform), not AMB-linear. Window seed comes from rules.seed; glass walls use their exported fixedSeed (7 left, 3 right), matching drawGlassWalls().',
    nonLinear: [
      { line: 'room/index.html:145,150', what: 'glass alpha .28 + .1 * AMB[0]', handle: 'alpha mixes with AMB[0] via Fa/Ea (above); colour is constant; the remaining quadratic term is under 6/255' },
      { line: 'room/index.html:512,2757,2772,2782,3214,4363', what: "emi(c, .7 + .3 * AMB[0]) and similar: brightness follows AMB[0] on every channel", handle: 'F/E interpolation uses AMB[c] per channel; error is (AMB[c] - AMB[0]) * .3 * c, under 12/255 at dusk, on small props' },
      { line: 'room/index.html:3633', what: 'sign colour DARK > .3 ? emi(c, k * (1 - DARK * .3)) : lit(c, k)', handle: 'sign colours are cut per variant as (F, E) pairs at the variant DARK; thresholds .7 .8 .9 keep the DARK factor within 4/255' },
      { line: 'room/index.html:3322-3323', what: 'sunlight k = (1 - DARK / .4) * .12 while DARK < .4', handle: 'baked per variant; layer tagged sunlight; error under 3/255' },
      { line: 'room/index.html:3337,1248,1323,1963,4083', what: 'glow alpha .06 + .26 * DARK, (.1 + .25 * DARK) * e, .1 + .3 * DARK...', handle: 'uniform: a + b * DARK per light in the manifest' },
      { line: 'room/index.html:604-608', what: 'pane(): SKY[0]/SKY[1] gradient and stars (DARK > .55) over time', handle: 'drawn by the renderer from the SKY and DARK uniforms (layer kind pane)' },
      { line: 'room/index.html:79,3313', what: 'lit() truncates (| 0) and clamps at 255; F is cut at AMB = .5 to avoid clamping colours with k > 1', handle: 'scale by AMB / .5, then clamp the final output' },
      { line: 'room/index.html:2179 (haze), 2290, 2402', what: 'sky and backdrop mix SKY[1] into colours (haze), alpha .82 - DARK * .4', handle: 'not part of any room piece: the sky is cut per AMBK bucket (sky.buckets), the renderer interpolates or owns it' },
      { line: 'room/index.html:577', what: 'clock text from the time', handle: 'layer tagged clock (see light.clock)' },
    ],
  };
  result.rules = {
    seed: "seed = key == '__yard' ? 11 : hashStr(key) % 97; hashStr(s): let h = 7; for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return h (iterate Unicode code points, use their first UTF-16 code unit).",
    rounding: 'Use JavaScript Math.round(x), equivalent to floor(x + .5) (ignoring signed zero). Swift rounded() defaults to ties away from zero: -1.5 becomes -2 instead of JS -1; use floor(x + .5) for parity.',
    capture: { season: O.season || 'autumn', width: 1728, height: 1117, dpr: 2, insets: O.insets, date: '2026-10-15 (local calendar)', moon: .5, traffic: 'cars and train disabled' },
    bridge: 'Bridges are exported as concrete configurations (village.links, plan prefix of 13 links, valid for 0..14 projects). Rules for a renderer that wants to repeat them: planks n = Math.max(3, Math.round((s1 - s0) / .3)), plank colour ["#c48c58","#b88250","#cc965e"][(i*2 + (i>>2)) % 3], seam line at each plank i>0 in #7a4a2a, nail on odd i; posts m = Math.max(1, Math.round((s1 - s0 - .3) / 1.0)) at s0+.15+(s1-s0-.3)*i/m, rope 6 segments per span with sag 6.6 - sin(u*PI)*1.6; lanterns at s0+.15 and s1-.15 (lit when DARK > .3, glow 20*S #ffc870). Source: room/index.html drawLink.',
    stair: 'Stairs are concrete (13 steps, W=.5, rope posts every 3rd step, lantern at the foot); the swing (L.lift) is only exported down/up. Source: room/index.html drawStair.',
    lift: 'Room layers with kind lift refer to room=self; find that room key in the selected lift.fl list (never reuse a cut-time absolute floor). The lift is exported per floor count (3 for 0 projects, 4 for >=1): shaft slices plus cage; pulleys are static. Source: room/index.html drawLifts.',
  };
  result.limits = ['one season per atlas (room/atlas is autumn, atlas-<season> the others), clear weather only', 'island layout only', 'no-yard (yardOn false) and other screens not covered', 'dynamic items frozen at t=100000, the clock at 12:00', 'stair swing only down/up, pulleys static', 'pose frames are sampled', 'sky cut for a ' + sky.W + 'x' + sky.H + ' canvas at the AMBK bucket hours; other sizes and hours need the page sky / the renderer\'s own formulas'];
  result.counts = { rooms: Object.keys(result.rooms).length, sprites: atlas.length };

  result.sprites = atlas; // [page, x, y, w, h, flag] by sprite id
  result.note = { sprites: '[page, x, y, w, h, flag] in the F page parts-N.png; the E page parts-N-e.png has the same rect (flag 0 and 1 only)', pad: PAD };
  result.proofGate = { maxPctHouse: .1, channelDifference: 24 };
  post('parts.json', JSON.stringify(result));
  const failed = proof.filter(p => p.houseDiffOver24 / Math.max(1, p.housePixels) > .001);
  if (failed.length) throw new Error('parts proof exceeds 0.1%: ' + failed.map(p => `n${p.projects} h${p.hour}: ${p.pctHouse}%`).join('; '));
  return JSON.stringify({ files: posted, summary: `parts: ${frames.length} sprites on ${pages.length} pages (flags ${flags.join('/')}); ${LOG.join('; ')}` });
})();
