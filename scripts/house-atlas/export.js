// Runs inside room/index.html (injected by export.swift after the page has loaded) and cuts the house into sprites
// for the SpriteKit renderer. Nothing here draws art of its own: every pixel comes from the page's own functions,
// which are wrapped so that each piece they draw lands in its own layer. The result is one JSON object with the
// atlas pages as PNG data URLs, the static layers (where and at what depth each one goes), the lift's parts, the
// agents' poses and the routes the page plans for two scripted agents.
//
// Phase 0 limits, on purpose: one light (the export hour), clear weather, no residents (cat, dog), no eggs or
// seasons, the backdrop frozen at one moment, laid out for the screen the export ran on.
(() => {
  'use strict';
  const O = window.__HOUSE_EXPORT;
  const t = 100000, d = now();

  // the page's loop and everything the prototype does not port stay out of it
  setActive(false);
  weather = 'clear';
  updateResidents = () => {}; updateErrands = () => {}; updateScenes = () => {}; eggStep = () => {};
  eggSky = () => {}; eggOver = () => {}; eggItems = () => {}; drawSeason = () => {};
  METEORS.next = Infinity; METEORS.list = [];
  room.setInsets(O.insets);
  room.setAgents(O.agents.map(a => ({ id: a.id, title: a.id, project: O.project, vendor: a.vendor, state: 'working', activity: 'Edit · x' })));
  for (const [id, sp] of [...sprites]) if (sp.kind !== 'agent') sprites.delete(id);
  setTime(d.getHours() + d.getMinutes() / 60 + d.getSeconds() / 3600);
  for (const r of rooms) { r.born = -1e9; r.drop = 0; }
  const agents = new Map([...sprites]); // put aside while the still parts are cut
  sprites.clear();
  // a reference picture: the page's own frame of the same still scene, before anything below wraps its functions
  const refT = performance.now(); frame(refT);
  const reference = cv.toDataURL('image/png');

  const W = cv.width, H = cv.height;
  const cap = document.createElement('canvas'); cap.width = W; cap.height = H;
  const cx = cap.getContext('2d', { willReadFrequently: true });
  const reset = c => { c.setTransform(1, 0, 0, 1, 0, 0); c.globalAlpha = 1; c.globalCompositeOperation = 'source-over'; c.clearRect(0, 0, c.canvas.width, c.canvas.height); };
  const clear = c => { c.save(); c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, c.canvas.width, c.canvas.height); c.restore(); };
  // the drawn part of a canvas, cut out: { img, x, y } in its pixels, or null when nothing was drawn
  function crop(c) {
    const w = c.canvas.width, h = c.canvas.height, px = c.getImageData(0, 0, w, h).data;
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0, i = y * w * 4 + 3; x < w; x++, i += 4) if (px[i]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 < 0) return null;
    const img = document.createElement('canvas'); img.width = x1 - x0 + 1; img.height = y1 - y0 + 1;
    img.getContext('2d').drawImage(c.canvas, x0, y0, img.width, img.height, 0, 0, img.width, img.height);
    return { img, x: x0, y: y0 };
  }
  function paint(fn, c = cx) { reset(c); const saved = [g, R]; g = c; try { fn(); } finally { [g, R] = saved; } return crop(c); }

  const frames = []; // every sprite image, packed into the atlas at the end
  const addFrame = (name, img) => { frames.push({ name, img }); return name; };
  const layers = [];
  const layer = (name, cut, z, extra) => { if (cut) layers.push({ sprite: addFrame(name, cut.img), x: cut.x, y: cut.y, z, ...extra }); };

  // ----- one room: the page's drawRoom, split wherever it starts the next piece of its back-to-front list -----
  const real = { blit, drawLifts, drawSign, glow, bakeWorld };
  function cutRoom(r, zBase) {
    const cache = buildCache(r), byImage = new Map(), meta = { liftDepth: null };
    for (const it of cache.items) if (!it.dyn) byImage.set(it.baked, it);
    const dynDraw = new Map();
    for (const it of cache.items) if (it.dyn) { const f = it.draw; dynDraw.set(it, f); it.draw = () => { mark(depthOf(it), 'dyn'); f(); }; }
    let cur = { depth: -1, kind: 'back' }, n = 0, lightsOn = false;
    const flush = () => {
      const cut = crop(cx); clear(cx);
      if (!cut) return;
      const z = cur.kind === 'back' ? zBase : cur.kind === 'lights' ? zBase + 90 : cur.kind === 'top' ? zBase + 95 : zBase + 10 + cur.depth + (n++) * 1e-3;
      layer(`${r.key}/${cur.kind}${layers.length}`, cut, z, cur.kind === 'lights' ? { blend: 'add' } : {});
    };
    const mark = (depth, kind) => { flush(); cur = { depth, kind }; };
    const depthOf = it => typeof it.depth === 'function' ? it.depth() : it.depth;
    blit = b => { const it = byImage.get(b); if (it) mark(depthOf(it), 'item'); real.blit(b); };
    drawSign = (rr, tt) => { mark(rr.floor === 0 ? rr.NX + rr.NY + 1.6 : 0, rr.floor === 0 ? 'item' : 'top'); real.drawSign(rr, tt); };
    drawLifts = (tt, f) => { meta.liftDepth = LIFT.x0 + LIFT.y1 - LIFT.fl[f].yoff; mark(meta.liftDepth, 'lift'); };
    glow = (...a) => { if (!lightsOn) { lightsOn = true; mark(0, 'lights'); } real.glow(...a); };
    reset(cx); const saved = g; g = cx;
    try { drawRoom(r, t, d); flush(); }
    finally { g = saved; Object.assign(window, { blit: real.blit, drawSign: real.drawSign, drawLifts: real.drawLifts, glow: real.glow });
      for (const [it, f] of dynDraw) it.draw = f; }
    return meta;
  }

  // ----- the lift: its frame a floor at a time, the cages once, at the bottom, closed and open -----
  function cutLift(zBaseOf) {
    if (!LIFT) return null;
    const pieces = [];
    let name = '';
    bakeWorld = (store, nm, key, box, fn) => { name = nm; return real.bakeWorld(store, nm, key, box, fn); };
    const sliceCut = (f, keep) => { // drawLifts(f) with every blit cut apart and tagged by the piece it is
      const out = []; let tag = 'start';
      const flush = () => { const cut = crop(cx); clear(cx); if (cut) out.push({ tag, cut }); };
      blit = b => { flush(); tag = name; real.blit(b); flush(); tag = 'after:' + name; };
      reset(cx); const saved = g; g = cx;
      try { real.drawLifts(t, f); flush(); } finally { g = saved; blit = real.blit; }
      return out.filter(p => keep(p.tag));
    };
    const park = (z, state) => LIFT.cabins.forEach(c => { c.z = z; c.level = 0; c.state = state; });
    park(-1e6, 'idle'); // out of every slice: the frame alone
    const floors = LIFT.fl.map((q, f) => {
      const zb = zBaseOf(q.r), depth = LIFT.x0 + LIFT.y1 - q.yoff, [zlo, zhi] = liftSlice(f);
      for (const p of sliceCut(f, tag => !/rope/.test(tag))) { // ropes are drawn by the scene, as a line
        const m = /^(\d+)(back|front|head)(\d?)$/.exec(p.tag), shaft = m && m[3] !== '' ? +m[3] : 0;
        const order = !m ? 9 : m[2] === 'back' ? 0 : m[2] === 'front' ? 5 : 8; // pulleys come after the head
        const z = zb + 10 + depth + (m && m[2] === 'head' ? .03 : !m ? .04 : shaft * .01 + order * .001);
        layer(`lift/${f}/${p.tag}`, p.cut, z);
      }
      return { level: f, z: liftZ(f), room: q.r.key, zlo, zhi: zhi === Infinity ? 1e9 : zhi, depth, zBase: zb };
    });
    const z0 = liftZ(0), cages = [];
    for (const state of ['idle', 'open']) {
      park(-1e6, 'idle'); LIFT.cabins.forEach(c => { c.z = z0; c.state = state; });
      for (const p of sliceCut(0, tag => /cage(Back|Front)\d/.test(tag))) {
        const [, part, i] = /cage(Back|Front)(\d)/.exec(p.tag);
        if (state === 'open' && part === 'Back') continue;
        cages.push({ shaft: +i, part: part === 'Back' ? 'back' : state === 'open' ? 'frontOpen' : 'front', sprite: addFrame(`lift/cage${part}${i}-${state}`, p.cut.img), x: p.cut.x, y: p.cut.y });
      }
    }
    bakeWorld = real.bakeWorld;
    park(z0, 'idle');
    const wf = worldFrame();
    return { origin: [wf.ox, wf.oy], cageZ: z0, cageH: 28, top: LIFT.top, rope: lit('#3a2c20'),
      shafts: LIFT.shafts.map(s => ({ cx: s.cx, cy: s.cy })), floors, cages };
  }

  // ----- the sky: the gradient is the scene's, from the page's own colour table; sun, backdrop and clouds are cut -----
  const bd = BACKDROPS[BACKDROP] || BACKDROPS.city;
  const P = { px: 0, py: 0, W, H, ground: bd.ground ? bd.ground(W, H - insetBottom()) : bdGround(H - insetBottom()), hr: d.getHours() + d.getMinutes() / 60 };
  layer('sky/backdrop', paint(() => bd.draw(t, d, P)), -900);
  const sunCut = paint(() => drawCelestial(t, d, P));
  const sun = sunCut && LAST_SUN ? { sprite: addFrame('sky/sun', sunCut.img), ax: LAST_SUN[0] - sunCut.x, ay: LAST_SUN[1] - sunCut.y } : null;
  const cw = document.createElement('canvas'); cw.width = 12 * 131 * S + W + 80 * S; cw.height = H; const cwx = cw.getContext('2d', { willReadFrequently: true });
  const wide = { ...P, W: cw.width - 160 * S }; let clouds = [];
  const OFF = 80 * S; reset(cwx); cwx.translate(OFF, 0); { const saved = g; g = cwx; try { drawClouds(0, wide); } finally { g = saved; } }
  clouds = LAST_CLOUDS.map(([x, y, w], i) => {
    const c = document.createElement('canvas'); c.width = w + 2 * S; c.height = 12 * S;
    c.getContext('2d').drawImage(cw, x + OFF - S, y - 6 * S, c.width, c.height, 0, 0, c.width, c.height);
    return { i, w, y, sprite: addFrame('sky/cloud' + i, c), dx: -S, dy: -6 * S };
  });

  // ----- the rooms, back to front, then what the page draws over all of them -----
  const order = drawOrder().filter(it => it.room), zBase = new Map();
  order.forEach((it, i) => zBase.set(it.room, i * 100));
  const roomMeta = order.map(({ room: r }) => {
    const m = cutRoom(r, zBase.get(r));
    return { key: r.key, theme: Object.keys(THEMES).find(k => THEMES[k] === r.theme), ox: r.ox, oy: r.oy, floor: r.floor, tower: r.tower,
      NX: r.NX, NY: r.NY, zBase: zBase.get(r), hub: r.theme.hub, spots: r.theme.spots, liftDepth: m.liftDepth };
  });
  const lift = cutLift(r => zBase.get(r));
  layer('house/escapes', paint(() => drawEscapes(t)), order.length * 100);

  // ----- the agents: a cloned resident in each pose, cut around its feet -----
  const poses = {};
  for (const sp0 of agents.values()) {
    const v = sp0.vendor; if (poses[v]) continue;
    const pose = (nm, o, tt) => {
      const sp = { ...sp0, path: [], alpha: 1, moving: false, seated: false, waving: false, toss: 0, onBridge: null, ...o };
      const X = 200, Y = 200, cut = paint(() => drawClawd(X, Y, sp, tt));
      return { sprite: addFrame(`agent/${v}/${nm}`, cut.img), ax: X - cut.x, ay: Y - cut.y };
    };
    poses[v] = { stand: [pose('stand', { state: 'working' }, 0)],
      walk: [pose('walk0', { state: 'working', moving: true }, 0), pose('walk1', { state: 'working', moving: true }, 110)],
      work: [pose('work0', { state: 'working', seated: true }, 0), pose('work1', { state: 'working', seated: true }, 160)] };
  }

  // ----- two scripted agents: the routes the page itself plans between their spots -----
  const proj = roomByKey.get('p:' + O.project), kitchen = shared('kitchen');
  const dump = path => path.map(n => n.lift ? { lift: n.lift } : { room: n.r.key, p: n.p.slice(0, 3).map(v => v || 0), jump: !!n.jump });
  const legs = (sp, list) => list.map(([fromRoom, from, toRoom, to]) => {
    Object.assign(sp, { room: fromRoom, x: from[0], y: from[1], z: from[2] || 0, path: [], onBridge: null });
    routeTo(sp, toRoom, to.slice(0, 3)); return { to: toRoom.key, nodes: dump(sp.path) };
  });
  const [a1, a2] = O.agents.map(a => agents.get(a.id)), sp1 = proj.theme.spots, kw = kitchen.theme.spots.wait;
  const routes = [
    { id: a1.id, vendor: a1.vendor, seed: a1.seed, start: { room: proj.key, p: proj.theme.hub },
      legs: legs(a1, [[proj, proj.theme.hub, proj, sp1.work[0]], [proj, sp1.work[0], proj, sp1.read[0]], [proj, sp1.read[0], proj, sp1.work[0]]]), loopFrom: 1 },
    { id: a2.id, vendor: a2.vendor, seed: a2.seed, start: { room: proj.key, p: proj.theme.hub },
      legs: legs(a2, [[proj, proj.theme.hub, proj, sp1.work[1]], [proj, sp1.work[1], kitchen, kw[0]], [kitchen, kw[0], proj, sp1.work[1]]]), loopFrom: 1 },
  ];


  // ----- packing: shelves on pages of up to 4096 px, 2 px of air around each sprite -----
  const PAGE = 4096, PAD = 2, pages = [], atlas = {};
  frames.sort((a, b) => b.img.height - a.img.height);
  let pg = null, sx = 0, sy = 0, rowH = 0;
  const newPage = () => { pg = { cv: document.createElement('canvas'), list: [], h: 0 }; pg.cv.width = PAGE; pg.cv.height = PAGE; pages.push(pg); sx = PAD; sy = PAD; rowH = 0; };
  newPage();
  for (const f of frames) {
    const w = f.img.width, h = f.img.height;
    if (sx + w + PAD > PAGE) { sx = PAD; sy += rowH + PAD; rowH = 0; }
    if (sy + h + PAD > PAGE) newPage();
    pg.cv.getContext('2d').drawImage(f.img, sx, sy);
    atlas[f.name] = { page: pages.length - 1, x: sx, y: sy, w, h };
    sx += w + PAD; rowH = Math.max(rowH, h); pg.h = Math.max(pg.h, sy + h + PAD);
  }
  const pageURLs = pages.map(p => { const c = document.createElement('canvas'); c.width = PAGE; c.height = Math.min(PAGE, 1 << Math.ceil(Math.log2(p.h)));
    c.getContext('2d').drawImage(p.cv, 0, 0); return { url: c.toDataURL('image/png'), w: c.width, h: c.height }; });

  return JSON.stringify({
    version: 1, hour: P.hr, weather, canvas: { w: W, h: H }, pxd: PXD, dpr: DPR, S, insets: O.insets,
    sky: { ambk: AMBK, ground: P.ground, sun, clouds, cloudAlpha: .82 }, rooms: roomMeta, lift, poses, routes, layers, sprites: atlas,
    pages: pageURLs, reference, refT, walk: { speed: 1.9, small: 2.3 },
  });
})();
