import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {C, Caption, Keycap, MONO, SANS, State, camAt, CamKey, clamp01, range, toScreen, win} from '../lib';
import {ASK_WING, Laptop, World, layoutWing, useV} from '../world';

const AL = layoutWing(ASK_WING);

/* ---------------- Trust ---------------- */
export const TRUST_LEN = 112;
export const Trust: React.FC = () => {
  const f = useCurrentFrame();
  const {V} = useV();
  const cam = camAt(f, [
    {f: 0, s: V ? 2.6 : 3.0, fx: 900, fy: 32, ax: V ? 540 : 960, ay: V ? 560 : 300},
    {f: TRUST_LEN, s: V ? 2.4 : 2.7, fx: 900, fy: 32, ax: V ? 540 : 960, ay: V ? 560 : 300},
  ]);
  const o = win(f, 0, TRUST_LEN, 10, 10);
  const L = V ? {x: 60, w: 960, size: 84} : {size: 96};
  return (
    <AbsoluteFill style={{background: C.bg}}>
      <AbsoluteFill style={{filter: 'blur(14px) brightness(0.5)', opacity: o}}>
        <World cam={cam} tone={0.6}>
          <Laptop clock="Tue 14:26" calm={1} wing={{items: ASK_WING, state: () => 'working'}} />
        </World>
      </AbsoluteFill>
      <Caption frame={f} from={4} to={58} y={V ? 760 : 400} {...L} segs={[{t: 'Nothing is approved'}, {t: 'without you.', c: C.text}]}
        sub={<>No answer in 100 s? The agent asks as usual.</>} />
      <Caption frame={f} from={58} to={TRUST_LEN} y={V ? 760 : 400} {...L} segs={[{t: '100% local.', c: C.green}, {t: 'No network.'}]}
        sub={<>Free and open source.</>} />
    </AbsoluteFill>
  );
};

/* ---------------- End: final approve + pulse -> end card ---------------- */
export const END_LEN = 165;
export const End: React.FC<{len?: number}> = ({len = END_LEN}) => {
  const f = useCurrentFrame();
  const {W, H, V} = useV();
  const press = 16;
  const keys: CamKey[] = V
    ? [
        {f: 0, s: 3.2, fx: 743, fy: 32, ax: 540, ay: 760},
        {f: press + 8, s: 3.3, fx: 743, fy: 32, ax: 540, ay: 760},
        {f: press + 50, s: 2.1, fx: 900, fy: 32, ax: 540, ay: 470},
      ]
    : [
        {f: 0, s: 3.6, fx: 743, fy: 32, ax: 960, ay: 420},
        {f: press + 8, s: 3.7, fx: 743, fy: 32, ax: 960, ay: 420},
        {f: press + 50, s: 2.2, fx: 900, fy: 32, ax: 960, ay: 190},
      ];
  const cam = camAt(f, keys);
  const done = f >= press + 2;
  const state = (i: number): State => (i === 0 && !done ? 'waiting' : 'working');
  const blink = (i: number) => (i === 0 && !done ? 0.5 + 0.5 * Math.cos((f / 30) * Math.PI * 2 * 1.2) : 1);
  const kp = range(f, press - 3, press) * (1 - range(f, press + 4, press + 10));
  const kOp = win(f, 0, press + 18, 6, 10);
  const mk = toScreen(cam, AL.marks[0].cx, 32);
  const pulses = [0, 7, 14].map((d) => range(f, press + 2 + d, press + 52 + d, (t) => 1 - Math.pow(1 - t, 2)));
  const flash = range(f, press + 1, press + 4) * (1 - range(f, press + 4, press + 24));
  const a = (s: number, e: number) => range(f, s, e);
  const row = (o: number, y = 30) => ({opacity: o, transform: `translateY(${(1 - o) * y}px)`, filter: `blur(${(1 - o) * 6}px)`});
  const cmd = 'brew install --cask forichok/tap/agent-notch';
  const typed = Math.round(cmd.length * range(f, 86, 118, (t) => t));
  const caret = f < 130 ? Math.floor(f / 8) % 2 === 0 : false;
  const T = V
    ? {title: 760, tag: 950, chip: 1110, badges: 1290, url: 1360, tSize: 150, cmdSize: 29}
    : {title: 400, tag: 590, chip: 690, badges: 850, url: 920, tSize: 168, cmdSize: 38};
  const endFade = 1 - range(f, len - 2, len);
  return (
    <AbsoluteFill style={{opacity: endFade}}>
      <World cam={cam} tone={1}>
        <Laptop clock="Tue 14:26" calm={1} wing={{items: ASK_WING, state, blink, glow: (i) => (i === 0 ? (done ? 1 - range(f, press + 10, press + 50) : 0.8) : 0)}} />
      </World>
      {/* pulse */}
      {pulses.map((t, k) => t > 0 && t < 1 && (
        <div key={k} style={{position: 'absolute', left: mk.x - 1600 * t, top: mk.y - 1600 * t, width: 3200 * t, height: 3200 * t, borderRadius: '50%',
          border: `${3 + 6 * (1 - t)}px solid ${k === 0 ? C.green : 'rgba(255,255,255,0.8)'}`, opacity: (1 - t) * (k === 0 ? 0.9 : 0.35), boxShadow: `0 0 80px ${C.green}55`}} />
      ))}
      <div style={{position: 'absolute', left: mk.x - 600, top: mk.y - 600, width: 1200, height: 1200, borderRadius: '50%', background: `radial-gradient(closest-side, ${C.green}66, transparent)`, opacity: flash}} />
      {/* key hint for the final approve */}
      <div style={{position: 'absolute', left: 0, right: 0, top: V ? 1060 : 720, display: 'flex', justifyContent: 'center', gap: 16, opacity: kOp}}>
        <Keycap pressed={kp} size={84}>⌃</Keycap><Keycap pressed={kp} size={84}>⌥</Keycap><Keycap pressed={kp} size={84}>Y</Keycap>
      </div>
      {/* end card */}
      <div style={{position: 'absolute', left: 0, right: 0, top: T.title, textAlign: 'center', fontFamily: SANS, fontWeight: 700, fontSize: T.tSize, letterSpacing: -T.tSize * 0.04, color: C.text, ...row(a(54, 80), 40)}}>Agent Notch</div>
      <div style={{position: 'absolute', left: V ? 60 : 0, right: V ? 60 : 0, top: T.tag, textAlign: 'center', fontFamily: SANS, fontWeight: 500, fontSize: V ? 46 : 48, color: '#b4b4ba', letterSpacing: -0.5, lineHeight: 1.25, ...row(a(66, 90))}}>
        Every Claude Code &amp; Codex agent,{V ? <br /> : ' '}in your MacBook notch.
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: T.chip, display: 'flex', justifyContent: 'center', ...row(a(78, 100))}}>
        <div style={{fontFamily: MONO, fontSize: T.cmdSize, color: C.text, padding: V ? '20px 30px' : '24px 46px', borderRadius: 999, background: 'rgba(255,255,255,0.07)',
          boxShadow: '0 0 0 1px rgba(255,255,255,0.16) inset, 0 20px 60px rgba(0,0,0,0.5)', display: 'flex', gap: 16, whiteSpace: 'pre'}}>
          <span style={{color: C.green}}>$</span>
          <span style={{position: 'relative'}}>
            <span style={{visibility: 'hidden'}}>{cmd}</span>
            <span style={{position: 'absolute', left: 0, top: 0}}>{cmd.slice(0, typed)}<span style={{opacity: caret ? 1 : 0, color: C.green}}>▍</span></span>
          </span>
        </div>
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: T.badges, textAlign: 'center', fontFamily: SANS, fontWeight: 600, fontSize: V ? 38 : 38, color: C.text, ...row(a(112, 134), 16)}}>
        Free <span style={{color: C.dim}}>·</span> Open source <span style={{color: C.dim}}>·</span> 100% local
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: T.url, textAlign: 'center', fontFamily: MONO, fontSize: V ? 30 : 30, color: C.dim, ...row(a(122, 144), 12)}}>github.com/Forichok/Agent-Notch</div>
      {W && H && null}
    </AbsoluteFill>
  );
};
export {clamp01};
