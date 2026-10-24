// Runs inside room/index.html (export.swift in "parts" mode, HOUSE_REF_ONLY=1) and records the page's OWN frames for the live-agents
// proof of the SpriteKit scene: every case replays a behaviour fixture's rows timeline (Tests/Fixtures/house-behaviour/*.json, the
// same timeline HouseBehaviour is driven with) through the page's real setAgents and 50 ms steps, with the fixtures' seeded
// Math.random and a clock that is the timeline's, then draws the page's frame at each sample time. Per sample: the whole frame, the
// frame without any agent drawn (the mask of the agents' pixels), the sky-only frame, and the numbers the Swift side needs.
// window.__LIVE_CASES = [{name, seed, hour, samples: [ms...], events: [{at, rows}]}] is prepended by scripts/house-atlas/live-proof.sh.
// Output: live-<case>-t<ms>.png / -bare.png / -sky.png / .json
(() => {
  'use strict';
  const O = window.__HOUSE_EXPORT, post = (path, data) => window.webkit.messageHandlers.out.postMessage({ path, data });
  setActive(false);
  weather = 'clear';
  // The life layer (residents, the cat and the dog, scenes), the speech bubbles, the marks over the Clawds and the scene overlays are all
  // live now, and so are the sky life (birds, a plane, a balloon: HouseSkyLife draws the same numbers) and the case's season (leaves,
  // snow, flowers). Not drawn by the SpriteKit house and so off here: the eggs. No demo: the context batteries come from the rows only.
  demo = false;
  // The eggs are drawn by the SpriteKit house too (HouseScene2Eggs.swift) in the cases that name some (c.egg: trigger names and date=YYYY-MM-DD);
  // every other case keeps them off.
  const EGGFN = { eggStep, eggSky, eggOver, eggItems };
  const eggMem = {}; eggStore.get = k => eggMem[k] ?? null; eggStore.set = (k, v) => { eggMem[k] = v; };
  const eggOff = () => { eggStep = () => {}; eggSky = () => {}; eggOver = () => {}; eggItems = () => {}; EGG.on = false; };
  eggOff();
  METEORS.next = Infinity; METEORS.list = [];
  room.setInsets(O.insets);
  sprites.clear();
  let bt = 0;
  performance.now = () => bt;
  const real = { drawClawd, drawBackground };
  // the frame is drawn at t=100000 (the atlas cut the rooms' animated items there); what the Clawds, the life layer and the overlays show
  // follows the sim's time, so they get bt. The frame's own update calls must not advance the life a second time.
  const life = { updateResidents, updateScenes, updateErrands };
  { const rc = drawClawd; drawClawd = (X, Y, sp, t) => rc(X, Y, sp, bt); real.drawClawd = drawClawd; const rb = drawBackground; real.drawBackground = (t, d) => rb(bt, d); const rf = drawFallers; drawFallers = () => rf(bt);
    const rco = drawChats; drawChats = () => rco(bt); const rso = drawSceneOverlays; drawSceneOverlays = () => rso(bt); }
  const out = [], files = [];
  for (const c of window.__LIVE_CASES) {
    // a fresh house: the three shared rooms, no project, no growth, the fixture's random numbers
    for (const r of rooms) r.label.remove();
    rooms.length = 0; roomByKey.clear(); sprites.clear(); links = []; LIFT = null; PLAN = { hulls: [] };
    growth = {};
    SC.ball = null; SC.puffs = []; SC.fireworks = []; SC.papers = []; SC.mailFlag = -1e9; // nothing of the last case's life layer carries over
    Object.assign(SKYLIFE, { birds: [], plane: null, balloon: null, next: null, last: 0 }); // a fresh sky per case, like the fresh HouseBehaviour
    ensureRoom('__bath', 'Ванная', 'bath'); ensureRoom('__kitchen', 'Кухня', 'kitchen'); ensureRoom('__roof', 'Крыша', 'roof');
    for (const r of rooms) { r.born = -1e9; r.drop = 0; r.cache = null; }
    let bs = c.seed;
    Math.random = () => { bs = (Math.imul(bs, 1664525) + 1013904223) >>> 0; return bs / 4294967296; };
    {
      const names = (c.egg || []).filter(n => !n.startsWith('date=')), dq = (c.egg || []).find(n => n.startsWith('date='));
      Object.assign(EGG, { shades: 0, rain: new Map(), purr: 0, purrNext: 0, catClicks: [], letter: null, tipN: 0, hearts: [], heartNext: 0, stars: [], ufo: null, ufoTry: 0, whale: null, ghost: null, party: false, partyUntil: 0, fwNext: 0, seen: null, want: null });
      for (const k of Object.keys(eggMem)) delete eggMem[k];
      Q.set('date', dq ? dq.slice(5) : '');
      if (c.egg) { EGG.on = true; eggStep = () => {}; eggItems = EGGFN.eggItems; eggSky = (t, d) => EGGFN.eggSky(bt, d); eggOver = () => EGGFN.eggOver(bt); } else eggOff();
      c.__eggNames = names;
    }
    Q.set('season', c.season || 'autumn'); weather = c.weather || 'clear';
    fixedHour = c.hour; setTime(c.hour);
    const end = Math.max(...c.samples);
    for (bt = 0; bt <= end; bt += 50) {
      for (const e of c.events.filter(e => e.at === bt)) if (e.rows) room.setAgents(e.rows);
      if (c.egg && bt === 1000) for (const n of c.__eggNames) eggTrigger(n);
      if (c.egg && bt) EGGFN.eggSky(bt, now());
      if (bt) {
        updateResidents(bt); updateErrands(bt); stepSprites(50); updateLifts(bt, 50);
        updateScenes(bt, now()); if (c.egg) EGGFN.eggStep(bt); updateStairs(bt);
        // the page turns a pet toward where it walks when it DRAWS it (drawCat/drawDog), every frame; the sim loop here draws only at the samples
        for (const sp of sprites.values()) if (sp.kind === 'cat' || sp.kind === 'dog') { const n = sp.path[0];
          if (sp.onBridge) sp.face = sp.onBridge.forward ? 1 : -1;
          else if (n && n.p) { const dx = (n.p[0] - sp.x) - (n.p[1] - sp.y); if (Math.abs(dx) > .05) sp.face = Math.sign(dx); }
          else if (sp.kind === 'dog' && sp.look) { const dx = (sp.look[0] - sp.x) - (sp.look[1] - sp.y); if (Math.abs(dx) > .05) sp.face = Math.sign(dx); } }
        for (const r of rooms) r.drop = Math.round(-Math.pow(1 - Math.min(1, Math.max(0, (bt - r.born) / 900)), 3) * 140);
        drawFallers(bt);
        if (c.egg) EGGFN.eggOver(bt);
      }
      if (!c.samples.includes(bt)) continue;
      const rngKept = bs; // drawing a frame must not use up the sim's random numbers: the scene draws without any
      const bgc = document.createElement('canvas'); bgc.width = cv.width; bgc.height = cv.height;
      // the yard's moving things (the ball in flight, the mailbox flag) are drawn by the room at t=100000: show them at the sim's time
      const draw = () => { last = 100000; performance.now = () => 100000;
        const shift = 100000 - bt, ball = SC.ball, flag = SC.mailFlag;
        if (ball) SC.ball = Object.assign(Object.create(Object.getPrototypeOf(ball)), ball, { t0: ball.t0 + shift, t1: (ball.t1 ?? 0) + shift });
        SC.mailFlag = flag + shift;
        updateResidents = () => false; updateScenes = () => { drawSkyLife(bt); return false; }; // the sky life is drawn by the frame at the sim's time (no step: the sim loop moved it)
        try { frame(100000); } finally { performance.now = () => bt; SC.ball = ball; SC.mailFlag = flag; updateResidents = life.updateResidents; updateScenes = life.updateScenes; } }; // the atlas cut the room's animated items at t=100000; the Clawds keep the sample time (drawClawd below)
      drawBackground = (t, d) => { real.drawBackground(t, d); bgc.getContext('2d').drawImage(cv, 0, 0); };
      try { draw(); } finally { drawBackground = real.drawBackground; }
      const full = cv.toDataURL('image/png');
      drawClawd = () => {};
      try { draw(); } finally { drawClawd = real.drawClawd; }
      const bare = cv.toDataURL('image/png');
      bs = rngKept;
      const d = now(), tag = `${c.name}-t${bt}`;
      const day = Math.floor((d - new Date(d.getFullYear(), 0, 1)) / 864e5);
      const sky = { birds: SKYLIFE.birds.map(f => [f.x, f.y, f.dir, f.v, f.n, f.seed]), plane: SKYLIFE.plane && [SKYLIFE.plane.x, SKYLIFE.plane.y], balloon: SKYLIFE.balloon && [SKYLIFE.balloon.x, SKYLIFE.balloon.y, SKYLIFE.balloon.seed] };
      const meta = { case: c.name, egg: c.egg || null, ufoT: EGG.ufo && [EGG.ufo.target.id, EGG.ufo.target.x, EGG.ufo.target.y, EGG.ufo.target.z], ufo: EGG.ufo && [EGG.ufo.x, EGG.ufo.y, EGG.ufo.lift, EGG.ufo.beam, ...(EGG.ufo.at || [])], sky, t: bt, hour: c.hour, season: c.season || 'autumn', weather: c.weather || 'clear', W: cv.width, H: cv.height, PXD, DPR, insets: INSETS, day, mist: mistAmount(d), T: bt, dark: DARK,
        rooms: rooms.map(r => ({ key: r.key, ox: r.ox, oy: r.oy, theme: Object.keys(THEMES).find(k => THEMES[k] === r.theme), NX: r.NX, NY: r.NY, floor: r.floor, tower: r.tower, growth: r.theme.shared ? 0 : growthLevel(r) })),
        agents: [...sprites.values()].filter(sp => sp.kind === 'agent').length, falling: [...sprites.values()].filter(sp => sp.fall).length, links: links.map(L => L.id + ':' + L.kind + ':' + (L.lift ?? '') + ':' + (L.aim ?? '')), sprites: [...sprites.values()].map(sp => [sp.id, sp.kind, sp.state || '', (sp.room && sp.room.key) || sp.room || '-', Math.round(sp.x), Math.round(sp.y), Math.round(sp.alpha * 100), sp.moving ? 'mv' : 'st', sp.seated ? 'seat' : '-', sp.waving ? 'wave' : '-'].join('|')), cabins: LIFT ? LIFT.cabins.map(c => [Math.round(c.z * 10) / 10, c.state]) : [] };
      for (const [f, data] of [['.png', full], ['-bare.png', bare], ['-sky.png', bgc.toDataURL('image/png')], ['.json', JSON.stringify(meta)]]) {
        post('check/live-' + tag + f, data); files.push('check/live-' + tag + f);
      }
      out.push(tag);
    }
  }
  return JSON.stringify({ files, summary: 'live ref frames: ' + out.join(' ') });
})();
