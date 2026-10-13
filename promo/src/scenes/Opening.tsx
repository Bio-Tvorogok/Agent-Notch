import React from 'react';
import {AbsoluteFill, spring, useCurrentFrame} from 'remotion';
import {C, Caption, SANS, camAt, CamKey, clamp01, easeIn, lerp, range, toScreen, win} from '../lib';
import {HEAVY_WING, Laptop, World, layoutWing, useV} from '../world';
import {PROMPT_I, TERMS, Terminal} from './Terminals';

/* Cold open (chaos of terminals, a buried prompt) -> windows collapse into the notch -> laptop reveal -> counter -> decode. */
export const openingLength = (V: boolean) => (V ? 352 : 440);

export const Opening: React.FC = () => {
  const f = useCurrentFrame();
  const {W, H, V} = useV();
  const fps = 30;
  const gap = V ? 6 : 8;
  const appear = (i: number) => 4 + i * gap;
  const T = V
    ? {c1: [8, 56], xr: 58, c2: [58, 106], c3: [106, 152], tm: [60, 140], K: 152}
    : {c1: [10, 66], xr: 70, c2: [70, 124], c3: [126, 178], tm: [74, 160], K: 180};
  const K = T.K;

  const keys: CamKey[] = V
    ? [
        {f: 0, s: 0.6, fx: 900, fy: 980, ax: 540, ay: 960},
        {f: 56, s: 0.64, fx: 900, fy: 960, ax: 540, ay: 960},
        {f: 130, s: 0.98, fx: 910, fy: 860, ax: 540, ay: 860},
        {f: K, s: 1.0, fx: 910, fy: 860, ax: 540, ay: 860},
        {f: K + 36, s: 0.36, fx: 975, fy: 1000, ax: 540, ay: 960},
        {f: K + 78, s: 0.32, fx: 975, fy: 1050, ax: 540, ay: 860, rx: 22},
        {f: K + 84, s: 0.32, fx: 975, fy: 1050, ax: 540, ay: 860, rx: 22},
        {f: K + 122, s: 3.0, fx: 688, fy: 32, ax: 540, ay: 700},
      ]
    : [
        {f: 0, s: 0.54, fx: 975, fy: 1000, ax: 960, ay: 540},
        {f: 66, s: 0.6, fx: 975, fy: 990, ax: 960, ay: 540},
        {f: 150, s: 0.9, fx: 910, fy: 830, ax: 960, ay: 470},
        {f: K, s: 0.93, fx: 910, fy: 830, ax: 960, ay: 470},
        {f: K + 40, s: 0.54, fx: 975, fy: 1000, ax: 960, ay: 540},
        {f: K + 90, s: 0.34, fx: 975, fy: 1050, ax: 960, ay: 470, rx: 22},
        {f: K + 98, s: 0.34, fx: 975, fy: 1050, ax: 960, ay: 470, rx: 22},
        {f: K + 140, s: 3.4, fx: 688, fy: 32, ax: 960, ay: 400},
      ];
  const cam = camAt(f, keys);

  // x-ray on the buried prompt
  const xr = range(f, T.xr, T.xr + 14) * (1 - range(f, K, K + 10));
  const tp = range(f, T.tm[0], T.tm[1], (t) => t);
  const secs = Math.round(1421 * tp);
  const timer = `${String(Math.floor(secs / 60)).padStart(2, '0')}:${String(secs % 60).padStart(2, '0')}`;
  const clock = `Tue 14:${String(2 + Math.round(23 * tp)).padStart(2, '0')}`;
  const blinkOn = Math.floor(f / 15) % 2 === 0;

  // collapse into the notch
  const fly = (i: number) => range(f, K + 2 + (TERMS.length - 1 - i) * 1.6, K + 24 + (TERMS.length - 1 - i) * 1.6, easeIn);
  const wingGrow = spring({frame: f - (K + 20), fps, config: {damping: 16, stiffness: 120}});
  const pop = (i: number) => spring({frame: f - (K + 28 + i * 5), fps, config: {damping: 10, stiffness: 170, mass: 0.6}});
  const waitingIdx = 4;
  const blink = (i: number) => (i === waitingIdx && f > K + 60 ? 0.6 + 0.4 * Math.cos(((f - K) / fps) * Math.PI * 2 * 1.2) : 1);

  const termEls = TERMS.map((t, i) => {
    const a = clamp01((f - appear(i)) / 7);
    if (a <= 0) return null;
    const p = fly(i);
    if (p >= 1) return null;
    const cx = t.x + t.w / 2, cy = t.y + t.h / 2;
    const dx = lerp(0, 700 - cx, p), dy = lerp(0, 32 - cy, p);
    const sc = (0.9 + 0.1 * a) * lerp(1, 0.015, p);
    const op = Math.min(a, 1 - range(p, 0.6, 1, (x) => x));
    return (
      <div key={i} style={{position: 'absolute', left: 0, top: 0, opacity: op, transform: `translate(${dx}px, ${dy}px)`}}>
        <div style={{position: 'absolute', left: 0, top: 0, transformOrigin: `${cx}px ${cy}px`, transform: `scale(${sc})`}}>
          <Terminal t={t} f={f - appear(i)} cursorOn={blinkOn} />
        </div>
      </div>
    );
  });
  const pt = TERMS[PROMPT_I];

  const xray = xr > 0.001 && (
    <>
      <div style={{position: 'absolute', left: -600, top: 0, width: 3200, height: 2000, background: `rgba(3,3,6,${0.62 * xr})`}} />
      <div style={{position: 'absolute', left: 0, top: 0, opacity: xr}}>
        <div style={{position: 'absolute', left: pt.x - 6, top: pt.y - 6, width: pt.w + 12, height: pt.h + 12, borderRadius: 24, boxShadow: `0 0 0 4px ${C.yellow}, 0 0 120px 10px rgba(255,179,31,0.35)`}} />
        <Terminal t={pt} f={0} cursorOn={blinkOn} />
        <div style={{position: 'absolute', left: pt.x + pt.w - 300, top: pt.y - 84, height: 62, padding: '0 26px', borderRadius: 31, background: C.yellow, color: '#1a1200',
          fontFamily: SANS, fontWeight: 700, fontSize: 32, whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: 12, fontVariantNumeric: 'tabular-nums'}}>
          waiting {timer}
        </div>
      </div>
    </>
  );

  // decode callouts (horizontal only)
  const L = layoutWing(HEAVY_WING);
  const callouts = !V && f > K + 196 && (() => {
    const lab = [
      {i: [0], t: 'Claude Code', c: C.text, row: 0},
      {i: [1], t: 'Codex', c: C.text, row: 1},
      {i: [2, 3], t: 'stuck on errors', c: C.red, row: 0},
      {i: [4], t: 'waiting for you', c: C.yellow, row: 1},
    ];
    return lab.map((l, k) => {
      const p = range(f, K + 202 + k * 6, K + 222 + k * 6);
      const o = p * (1 - range(f, K + 250, K + 260));
      const xs = l.i.map((i) => toScreen(cam, L.marks[i].cx, 32).x);
      const x = (Math.min(...xs) + Math.max(...xs)) / 2;
      const top = toScreen(cam, 0, 32).y + 34;
      const ly = 590 + l.row * 86;
      return (
        <React.Fragment key={k}>
          <div style={{position: 'absolute', left: x - 1, top, width: 2, height: (ly - top - 8) * p, background: 'rgba(255,255,255,0.45)', opacity: o}} />
          {l.i.length > 1 && <div style={{position: 'absolute', left: Math.min(...xs), top: top - 2, width: Math.max(...xs) - Math.min(...xs), height: 2, background: 'rgba(255,255,255,0.45)', opacity: o}} />}
          <div style={{position: 'absolute', left: x - 200, width: 400, top: ly, textAlign: 'center', fontFamily: SANS, fontWeight: 650, fontSize: 38, color: l.c, opacity: o, transform: `translateY(${(1 - p) * 14}px)`}}>{l.t}</div>
        </React.Fragment>
      );
    });
  })();

  const counter = (() => {
    const a = V ? K + 124 : K + 128;
    const b = V ? K + 200 : K + 200;
    const o = win(f, a, b, 14, 12);
    if (o <= 0) return null;
    const n = (target: number, d: number) => Math.round(target * range(f, a + d, a + d + 26));
    const items = [
      {n: n(17, 0), t: 'agents', c: C.text},
      {n: n(3, 6), t: 'projects', c: C.text},
      {n: n(1, 12), t: 'needs you', c: C.yellow},
    ];
    return (
      <div style={{position: 'absolute', left: 0, right: 0, top: V ? 940 : 590, display: 'flex', flexDirection: V ? 'column' : 'row', alignItems: 'center', justifyContent: 'center', gap: V ? 6 : 34,
        fontFamily: SANS, fontWeight: 680, fontSize: V ? 92 : 76, letterSpacing: -2.5, color: C.text, opacity: o}}>
        {items.map((it, k) => {
          const p = range(f, a + k * 6, a + k * 6 + 18);
          return (
            <React.Fragment key={k}>
              {!V && k > 0 && <span style={{color: '#55555c', opacity: p}}>·</span>}
              <span style={{opacity: p, transform: `translateY(${(1 - p) * 30}px)`, display: 'inline-block', filter: `blur(${(1 - p) * 8}px)`}}>
                <span style={{fontVariantNumeric: 'tabular-nums', color: it.c}}>{it.n}</span> <span style={{color: k === 2 ? C.yellow : '#c7c7cc', fontWeight: 600}}>{it.t}</span>
              </span>
            </React.Fragment>
          );
        })}
      </div>
    );
  })();

  const capProps = V ? {x: 70, w: W - 140, align: 'center' as const, size: 82} : {size: 88};
  const capY = V ? 1520 : 880;
  const scrim = Math.max(win(f, 0, K + 4, 1, 10), 0);

  return (
    <AbsoluteFill>
      <World cam={cam} tone={range(f, K, K + 60)}>
        <Laptop clock={clock} glow={win(f, K + 30, K + 120, 20, 20)} calm={range(f, K, K + 40)} under={<>{termEls}{xray}</>}
          wing={{items: HEAVY_WING, grow: wingGrow, pop, blink,
            rings: f > K + 60 ? [{i: waitingIdx, t: ((f - K - 60) % 45) / 45, color: C.yellow}] : []}} />
      </World>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: H * 0.45, opacity: scrim, background: 'linear-gradient(transparent, rgba(0,0,0,0.85))'}} />
      <Caption frame={f} from={T.c1[0]} to={T.c1[1]} y={capY} {...capProps} segs={[{t: '17 agents.'}, {t: '14 terminals.', c: '#a1a1a8'}]} />
      <Caption frame={f} from={T.c2[0]} to={T.c2[1]} y={capY} {...capProps} segs={[{t: 'One is'}, {t: 'waiting', c: C.yellow}, {t: 'for you.'}]} />
      <Caption frame={f} from={T.c3[0]} to={T.c3[1]} y={capY} {...capProps} segs={[{t: 'For'}, {t: '23 minutes.', c: C.yellow}]} />
      <Caption frame={f} from={K + (V ? 40 : 48)} to={K + (V ? 94 : 102)} y={V ? 1420 : 920} {...capProps} segs={[{t: 'Meet'}, {t: 'Agent Notch.'}]} />
      {counter}
      {!V && <Caption frame={f} from={K + 200} to={K + 260} y={830} size={80} segs={[{t: 'Read it at a glance.'}]} />}
      {!V && f > K + 206 && (
        <div style={{position: 'absolute', left: 0, right: 0, top: 960, textAlign: 'center', fontFamily: SANS, fontSize: 34, fontWeight: 500, color: '#9a9aa0',
          opacity: win(f, K + 214, K + 260, 14, 10)}}>logo = vendor · dimmed = light model · smaller = subagent</div>
      )}
      {callouts}
    </AbsoluteFill>
  );
};
