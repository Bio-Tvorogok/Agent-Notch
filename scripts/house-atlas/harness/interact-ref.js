// Runs inside room/index.html (export.swift in "parts" mode, HOUSE_REF_ONLY=1) and records the page's OWN answers to a pointer / pinch /
// scroll / click sequence for the interaction proof of the SpriteKit scene (see interact-proof.sh). The house is the behaviour fixture's
// at one sample time (the agents stand still from then on: only the camera moves). Every step is an op the Swift harness replays on the
// scene verbatim; after the ops that matter the page records its camera (VIEW.zoom, VIEW.at), the overview button, the hovered agent and
// the hover card it would send; two settled views are also drawn (full / without agents / sky only) for a pixel comparison.
// window.__LIVE_CASES = [{name, seed, hour, samples: [ms], events}] is prepended by interact-proof.sh (only the first case is used).
// Output: interact.json (the ops and the records), interact-<frame>.png / -bare.png / -sky.png / -meta.json
(() => {
  'use strict';
  const O = window.__HOUSE_EXPORT, post = (path, data) => window.webkit.messageHandlers.out.postMessage({ path, data });
  setActive(false);
  weather = 'clear';
  updateResidents = () => false; startCelebrate = () => false; startMail = () => false; dogGreet = () => false; updateScenes = () => false;
  eggStep = () => {}; eggSky = () => {}; eggOver = () => {}; eggItems = () => {}; drawSeason = () => {};
  // the marks over the Clawds, the speech bubbles and the scene overlays are drawn by the SpriteKit house now (as in live-ref.js);
  // the life layer stays off on both sides (the harness does not enable it). No demo: the context batteries come from the rows only.
  demo = false; drawSkyLife = () => {};
  METEORS.next = Infinity; METEORS.list = [];
  room.setInsets(O.insets);
  sprites.clear();
  let bt = 0, VT = 1e6;
  performance.now = () => bt;
  const real = { drawClawd, drawBackground };
  { const rc = drawClawd; drawClawd = (X, Y, sp, t) => rc(X, Y, sp, bt); real.drawClawd = drawClawd; const rb = drawBackground; real.drawBackground = (t, d) => rb(bt, d); const rf = drawFallers; drawFallers = () => rf(bt);
    const rco = drawChats; drawChats = () => rco(bt); const rso = drawSceneOverlays; drawSceneOverlays = () => rso(bt); }

  const c = window.__LIVE_CASES[0], T0 = c.samples[0];
  for (const r of rooms) r.label.remove();
  rooms.length = 0; roomByKey.clear(); sprites.clear(); links = []; LIFT = null; PLAN = { hulls: [] };
  growth = {};
  ensureRoom('__bath', 'Ванная', 'bath'); ensureRoom('__kitchen', 'Кухня', 'kitchen'); ensureRoom('__roof', 'Крыша', 'roof');
  for (const r of rooms) { r.born = -1e9; r.drop = 0; r.cache = null; }
  let bs = c.seed;
  Math.random = () => { bs = (Math.imul(bs, 1664525) + 1013904223) >>> 0; return bs / 4294967296; };
  fixedHour = c.hour;
  for (bt = 0; bt <= T0; bt += 50) {
    for (const e of c.events.filter(e => e.at === bt)) if (e.rows) room.setAgents(e.rows);
    if (bt) {
      updateResidents(bt); updateErrands(bt); stepSprites(50); updateLifts(bt, 50);
      updateYard(bt); for (const sp of [...sprites.values()]) if (sp.hold?.kind === 'handover') stepHold(sp, bt); updateStairs(bt);
      for (const r of rooms) r.drop = Math.round(-Math.pow(1 - Math.min(1, Math.max(0, (bt - r.born) / 900)), 3) * 140);
      drawFallers(bt);
    }
  }
  bt = T0; // the agents stand here from now on; the Clawds are drawn at this time, the camera runs on VT
  performance.now = () => VT;
  const draw = () => {
    last = 100000; const keep = performance.now; performance.now = () => 100000;
    try { frame(100000); } finally { performance.now = keep; }
  };
  const hex = s => { const m = /(\d+)\D+(\d+)\D+(\d+)/.exec(s || ''); return m ? '#' + [1, 2, 3].map(i => (+m[i]).toString(16).padStart(2, '0')).join('') : null; };
  const ops = [], recs = [], frames = [], files = [];
  let opened = null; { const cl = console.log; console.log = (...a) => { if (a[0] === 'open') opened = a[1].open; else cl(...a); }; } // the page's {open: id} outside the app
  const rec = name => {
    const T = viewTarget(), on = tip.style.opacity !== '0' && tip.style.opacity !== '';
    recs.push({ name, zoom: VIEW.zoom, at: [VIEW.at[0], VIEW.at[1]], tz: T.zoom, home: homeBtn.classList.contains('on'),
      opened, hovered: hovered && hovered.agent ? hovered.agent.id : null, mouse: mouse ? [mouse[2], mouse[3]] : null,
      tip: on ? { title: tip.querySelector('b').textContent, status: tip.querySelector('.s').textContent, detail: tip.querySelector('.act').textContent,
        color: hex(tip.querySelector('.st').style.background) } : null });
    opened = null;
  };
  const exec = op => {
    ops.push(op);
    switch (op.op) {
      case 'pointer': room.pointer(op.x, op.y); updateTip(); break;
      case 'leave': room.leave(); updateTip(); break;
      case 'zoom': room.zoom(op.f, op.x, op.y); break;
      case 'pan': room.pan(op.dx, op.dy); break;
      case 'click': room.click(op.x, op.y); break;
      case 'reset': room.resetView(); break;
      case 'ticks': for (let i = 0; i < op.n; i++) { VT += op.dt; stepCamera(VT, op.dt); } break;
      case 'draw': draw(); break;
      case 'record': rec(op.name); break;
      case 'frame': {
        const bgc = document.createElement('canvas'); bgc.width = cv.width; bgc.height = cv.height;
        drawBackground = (t, d) => { real.drawBackground(t, d); bgc.getContext('2d').drawImage(cv, 0, 0); };
        try { draw(); } finally { drawBackground = real.drawBackground; }
        const full = cv.toDataURL('image/png');
        drawClawd = () => {}; try { draw(); } finally { drawClawd = real.drawClawd; }
        const bare = cv.toDataURL('image/png');
        draw(); // the hover state of the full frame again
        const meta = { name: op.name, W: cv.width, H: cv.height, PXD, DPR, zoom: VIEW.zoom, at: VIEW.at.slice(), insets: INSETS };
        for (const [f, data] of [['.png', full], ['-bare.png', bare], ['-sky.png', bgc.toDataURL('image/png')], ['-meta.json', JSON.stringify(meta)]]) {
          post('check/interact-' + op.name + f, data); files.push('check/interact-' + op.name + f);
        }
        frames.push(op.name); break;
      }
    }
  };
  const css = (px, py) => [px * PXD / DPR, py * PXD / DPR];
  // a Clawd that no other Clawd's rectangle overlaps: the pointer rests on its middle
  const pickAgent = () => {
    const all = [...sprites.values()].filter(s => s.agent && s.hit && s.alpha >= .5);
    const ok = all.filter(s => all.every(o => o === s || s.hit[0] + s.hit[2] < o.hit[0] || o.hit[0] + o.hit[2] < s.hit[0] || s.hit[1] + s.hit[3] < o.hit[1] || o.hit[1] + o.hit[3] < s.hit[1]));
    const s = (ok.length ? ok : all)[0];
    return s ? css(s.hit[0] + s.hit[2] / 2, s.hit[1] + s.hit[3] / 2) : [100, 100];
  };
  // a spot on a project's room that no Clawd covers, found on the overview
  const pickRoomSpot = () => {
    for (const r of rooms) {
      if (r.theme.shared) continue;
      const pts = roomOutline(r, false, true), cx = pts.reduce((a, p) => a + p[0], 0) / pts.length, cy = pts.reduce((a, p) => a + p[1], 0) / pts.length;
      for (const dy of [0, -8, 8, -16, 16]) {
        const x = cx, y = cy + dy; if (roomUnder(x, y) !== r) continue;
        if ([...sprites.values()].some(s => s.agent && s.hit && x >= s.hit[0] - 2 && x <= s.hit[0] + s.hit[2] + 2 && y >= s.hit[1] - 2 && y <= s.hit[1] + s.hit[3] + 2)) continue;
        return css(x, y);
      }
    }
    return [innerWidth / 2, innerHeight / 2];
  };
  const settle = () => { exec({ op: 'ticks', n: 80, dt: 40 }); };
  const sky = [20, innerHeight * 0.45];

  exec({ op: 'draw' });
  // 1. hover: an agent, nothing, leave
  const a0 = pickAgent();
  exec({ op: 'pointer', x: a0[0], y: a0[1] }); exec({ op: 'record', name: 'hover-agent' });
  exec({ op: 'pointer', x: sky[0], y: sky[1] }); exec({ op: 'record', name: 'hover-sky' });
  exec({ op: 'leave' }); exec({ op: 'record', name: 'leave' });
  // 2. pinch at the agent: factor 2 (zoom 2 exactly), watched while it glides and settled
  exec({ op: 'pointer', x: a0[0], y: a0[1] });
  exec({ op: 'zoom', f: 2, x: a0[0], y: a0[1] });
  exec({ op: 'ticks', n: 3, dt: 40 }); exec({ op: 'record', name: 'zoom-mid' });
  settle(); exec({ op: 'record', name: 'zoom-2' });
  exec({ op: 'draw' });
  const a1 = pickAgent();
  exec({ op: 'pointer', x: a1[0], y: a1[1] }); exec({ op: 'record', name: 'hover-zoomed' });
  exec({ op: 'frame', name: 'zoom2' });
  // 3. two-finger scroll while zoomed
  exec({ op: 'pan', dx: 40, dy: -30 }); exec({ op: 'ticks', n: 4, dt: 40 }); exec({ op: 'record', name: 'pan-mid' });
  settle(); exec({ op: 'record', name: 'pan' });
  exec({ op: 'draw' });
  const a2 = pickAgent();
  exec({ op: 'pointer', x: a2[0], y: a2[1] }); exec({ op: 'record', name: 'hover-panned' });
  exec({ op: 'frame', name: 'pan2' });
  // 4. a second pinch (fractional zoom), then the pinch out past the overview
  exec({ op: 'zoom', f: 1.6, x: 700, y: 500 }); settle(); exec({ op: 'record', name: 'zoom-3.2' });
  exec({ op: 'zoom', f: 0.2, x: 700, y: 500 }); settle(); exec({ op: 'record', name: 'pinch-out' });
  // 5. double tap / Esc: back to the overview with a glide
  exec({ op: 'zoom', f: 2, x: 900, y: 400 }); settle();
  exec({ op: 'reset' }); exec({ op: 'ticks', n: 5, dt: 40 }); exec({ op: 'record', name: 'reset-mid' });
  exec({ op: 'ticks', n: 12, dt: 40 }); exec({ op: 'record', name: 'reset-end' });
  exec({ op: 'draw' });
  // 6. click on a room (not on a Clawd) flies to it; the overview button shows
  const rs = pickRoomSpot();
  exec({ op: 'click', x: rs[0], y: rs[1] }); exec({ op: 'record', name: 'click-room-0' });
  exec({ op: 'ticks', n: 5, dt: 40 }); exec({ op: 'record', name: 'click-room-mid' });
  exec({ op: 'ticks', n: 12, dt: 40 }); exec({ op: 'record', name: 'click-room-end' });
  exec({ op: 'draw' });
  // 7. click on a Clawd opens it (the page's {open: id}); a click beside the room, zoomed in, goes back
  const a3 = pickAgent();
  exec({ op: 'click', x: a3[0], y: a3[1] }); exec({ op: 'record', name: 'click-agent' });
  exec({ op: 'click', x: 6, y: innerHeight - 6 }); exec({ op: 'ticks', n: 5, dt: 40 }); exec({ op: 'record', name: 'click-off-mid' });
  exec({ op: 'ticks', n: 12, dt: 40 }); exec({ op: 'record', name: 'click-off-end' });
  // 8. the overview button
  exec({ op: 'draw' });
  const rs2 = pickRoomSpot();
  exec({ op: 'click', x: rs2[0], y: rs2[1] }); exec({ op: 'ticks', n: 14, dt: 40 }); exec({ op: 'record', name: 'before-home-button' });
  exec({ op: 'click', x: 40, y: 58 }); exec({ op: 'ticks', n: 14, dt: 40 }); exec({ op: 'record', name: 'home-button' });
  // 9. thirty seconds untouched: back to the overview by itself
  exec({ op: 'zoom', f: 2, x: 900, y: 400 }); settle(); exec({ op: 'record', name: 'auto-0' });
  exec({ op: 'ticks', n: 28, dt: 1000 }); exec({ op: 'record', name: 'auto-28s' });
  exec({ op: 'ticks', n: 3, dt: 1000 }); exec({ op: 'record', name: 'auto-31s' });
  exec({ op: 'ticks', n: 14, dt: 40 }); exec({ op: 'record', name: 'auto-end' });

  const info = { case: c.name, seed: c.seed, hour: c.hour, T0, W: 0, ops, recs, frames, insets: INSETS, innerWidth, innerHeight, DPR, base: VIEW.base };
  post('check/interact.json', JSON.stringify(info)); files.push('check/interact.json');
  return JSON.stringify({ files, summary: 'interact ref: ' + recs.length + ' records, frames ' + frames.join(' ') });
})();
