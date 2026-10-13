import React from 'react';
import {AbsoluteFill, spring, useCurrentFrame} from 'remotion';
import {C, Caption, Cursor, Keycap, Ripple, SANS, State, camAt, CamKey, clamp01, easeIO, lerp, range, toScreen, win} from '../lib';
import {ASK_WING, HEAVY_WING, Laptop, Panel, World, useV} from '../world';

/** Cursor that glides from `a` to `b` (stage coords), arriving at `arrive`, clicking at `click`. */
export const cursorState = (f: number, start: number, arrive: number, click: number, a: {x: number; y: number}, b: {x: number; y: number}, fadeOut = click + 20) => {
  const p = range(f, start, arrive, easeIO);
  // slight arc
  const x = lerp(a.x, b.x, p) + Math.sin(p * Math.PI) * 30;
  const y = lerp(a.y, b.y, p) - Math.sin(p * Math.PI) * 20;
  const press = range(f, click - 3, click) * (1 - range(f, click + 1, click + 7));
  const op = range(f, start, start + 6) * (1 - range(f, fadeOut, fadeOut + 10));
  const ripple = range(f, click, click + 20, (t) => t);
  return {x, y, press, op, ripple};
};

const blinkAt = (f: number, from: number) => (f < from ? 1 : 0.5 + 0.5 * Math.cos(((f - from) / 30) * Math.PI * 2 * 1.2));

/* ---------------- Overview: heavy.png ---------------- */
export const OVERVIEW_LEN = 140;
export const Overview: React.FC = () => {
  const f = useCurrentFrame();
  const keys: CamKey[] = [
    {f: 0, s: 1.0, fx: 780, fy: 0, ax: 1400, ay: 70},
    {f: 60, s: 1.0, fx: 780, fy: 0, ax: 1400, ay: 70},
    {f: 128, s: 1.0, fx: 780, fy: 0, ax: 1400, ay: -6},
  ];
  const cam = camAt(f, keys);
  const reveal = spring({frame: f - 16, fps: 30, config: {damping: 20, stiffness: 150, mass: 0.9}});
  const cur = cursorState(f, 0, 12, 14, {x: 980, y: 300}, {x: 688, y: 34}, 22);
  const s1 = win(f, 26, 84, 10, 6), s2 = range(f, 80, 92);
  const spot = s2 > 0
    ? {y0: lerp(160, 426, s2), y1: lerp(418, 1052, s2), a: 1 - range(f, 128, 140)}
    : {y0: 160, y1: 418, a: s1};
  const ring = range(f, 14, 34, (t) => t);
  return (
    <AbsoluteFill>
      <World cam={cam} tone={1}>
        <Laptop clock="Tue 14:25" calm={1}
          wing={{items: HEAVY_WING, blink: (i) => (i === 4 ? blinkAt(f, 0) : 1), rings: [{i: 4, t: ring, color: '#fff'}]}}
          over={<>
            <Panel layers={[{shot: 'heavy', o: 1}]} reveal={reveal} spot={spot} />
            <Ripple x={688} y={34} t={cur.ripple} r={26} />
            <Cursor x={cur.x} y={cur.y} press={cur.press} opacity={cur.op} size={40} />
          </>} />
      </World>
      <Caption frame={f} from={22} to={82} x={110} y={380} w={820} align="left" size={84} segs={[{t: 'What'}, {t: 'needs you', c: C.yellow}, {t: 'comes first.', br: true}]} />
      <Caption frame={f} from={84} to={140} x={110} y={360} w={820} align="left" size={84} segs={[{t: 'Every project.'}, {t: 'Every subagent.', br: true}]}
        sub={<>Grouped by project, with model names.</>} />
    </AbsoluteFill>
  );
};

/* ---------------- Approvals: ask -> question -> plan ---------------- */
export const APPROVALS_LEN = 316;
export const approvalsLength = (V: boolean) => (V ? APPROVALS_LEN - 58 : APPROVALS_LEN);
export const Approvals: React.FC = () => {
  const raw = useCurrentFrame();
  const {V} = useV();
  // the vertical cut skips the keyboard beat (frames 80..138)
  const f = V && raw >= 80 ? raw + 58 : raw;
  const keys: CamKey[] = V
    ? [
        {f: 0, s: 3.0, fx: 743, fy: 32, ax: 540, ay: 700},
        {f: 46, s: 3.1, fx: 743, fy: 32, ax: 540, ay: 700},
        {f: 72, s: 1.1, fx: 780, fy: 0, ax: 540, ay: 420},
      ]
    : [
        {f: 0, s: 3.4, fx: 743, fy: 32, ax: 960, ay: 380},
        {f: 46, s: 3.55, fx: 743, fy: 32, ax: 960, ay: 380},
        {f: 72, s: 1.0, fx: 780, fy: 0, ax: 1400, ay: 150},
      ];
  const cam = camAt(f, keys);
  const reveal = spring({frame: f - 60, fps: 30, config: {damping: 20, stiffness: 150, mass: 0.9}});
  const toQ = range(f, 196, 206, easeIO), toP = range(f, 252, 262, easeIO);
  const layers = [
    {shot: 'ask' as const, o: 1 - toQ},
    {shot: 'question' as const, o: toQ * (1 - toP)},
    {shot: 'plan' as const, o: toP},
  ];

  // spotlight per beat
  const spots: [number, number, number, number][] = [
    // from, to, y0, y1
    [80, 136, 162, 372],
    [138, 196, 380, 504],
    [200, 252, 160, 474],
    [258, 316, 160, 416],
  ];
  const sp = spots.find(([a, b]) => f >= a - 4 && f < b) ?? spots[0];
  const spot = {y0: sp[2], y1: sp[3], a: win(f, sp[0], sp[1], 10, 8)};

  // wing states: both waiting, codex done waiting once rm -rf is allowed
  const state = (i: number): State => (i === 2 && f >= 178 ? 'working' : ASK_WING[i].st);
  const blink = (i: number) => (state(i) === 'waiting' ? blinkAt(f, 4) : 1);
  const rings = f < 60 ? [0, 2].map((i) => ({i, t: ((f + i * 10) % 40) / 40, color: C.yellow})) : [];
  const greenRing = {i: 2, t: range(f, 178, 210, (t) => t), color: C.green};

  // keyboard beat
  const yPress = range(f, 110, 113) * (1 - range(f, 118, 124));
  const kOp = win(f, 88, 136, 10, 8);
  const flash = range(f, 113, 133, (t) => t);

  // cursor beats
  const c1 = cursorState(f, 146, 172, 176, {x: 820, y: 700}, {x: 501, y: 474}, 192);
  const c2 = cursorState(f, 210, 232, 236, {x: 600, y: 520}, {x: 783, y: 282}, 250);
  const c3 = cursorState(f, 266, 288, 292, {x: 800, y: 520}, {x: 517, y: 386}, 312);
  const cur = f < 200 ? c1 : f < 258 ? c2 : c3;

  const capL = V ? {x: 60, w: 960, align: 'center' as const, size: 74} : {x: 110, w: 800, align: 'left' as const, size: 84};
  const capY = V ? 1300 : 330;
  const keyRow = (
    <div style={{position: 'absolute', left: V ? 0 : 110, right: V ? 0 : undefined, top: V ? 1380 : 600, display: 'flex', justifyContent: V ? 'center' : 'flex-start', gap: 16, alignItems: 'center',
      fontFamily: SANS, fontSize: 32, color: '#a1a1a8', opacity: kOp, transform: `translateY(${(1 - kOp) * 14}px)`}}>
      <Keycap pressed={yPress}>⌃</Keycap><Keycap pressed={yPress}>⌥</Keycap><Keycap pressed={yPress}>Y</Keycap><span style={{marginRight: 26}}>allow</span>
      <Keycap>⌃</Keycap><Keycap>⌥</Keycap><Keycap>N</Keycap><span>deny</span>
    </div>
  );
  return (
    <AbsoluteFill>
      <World cam={cam} tone={1}>
        <Laptop clock="Tue 14:25" calm={1}
          wing={{items: ASK_WING, state, blink, rings: [...rings, greenRing], glow: (i) => (state(i) === 'waiting' && f < 60 ? 0.8 : 0)}}
          over={<>
            <Panel layers={layers} reveal={reveal} spot={spot} />
            <Ripple x={501} y={344} t={flash} color={C.green} r={40} />
            <Ripple x={cur.x} y={cur.y} t={cur.ripple} color={'#fff'} r={30} />
            <Cursor x={cur.x} y={cur.y} press={cur.press} opacity={cur.op} size={40} />
          </>} />
      </World>
      <Caption frame={f} from={4} to={60} y={V ? 1000 : 700} size={V ? 80 : 88} x={V ? 60 : 0} w={V ? 960 : undefined} segs={[{t: 'Two agents are'}, {t: 'waiting.', c: C.yellow}]} />
      <Caption frame={f} from={80} to={136} y={capY} {...capL} segs={[{t: 'Answer from'}, {t: 'the keyboard.', br: !V}]} />
      {keyRow}
      <Caption frame={f} from={138} to={196} y={capY} {...capL} segs={[{t: 'Risky ones', c: C.red}, {t: 'need a click.', br: !V}]}
        sub={V ? undefined : <>rm -rf, git push --force: no hotkey.</>} />
      <Caption frame={f} from={200} to={254} y={capY} {...capL} segs={[{t: 'Questions get'}, {t: 'buttons.', br: !V}]} />
      <Caption frame={f} from={258} to={316} y={capY} {...capL} segs={[{t: 'Plans are approved'}, {t: 'in place.', br: true}]} />
    </AbsoluteFill>
  );
};
