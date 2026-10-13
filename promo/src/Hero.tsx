import React from 'react';
import {AbsoluteFill, spring, useCurrentFrame} from 'remotion';
import {C, Caption, Cursor, Keycap, Ripple, State, camAt, range, win} from './lib';
import {ASK_WING, Laptop, Panel, World} from './world';
import {cursorState} from './scenes/Panels';

/* 9 s seamless loop for the README: calm -> two agents wait -> approve from the notch -> calm. */
export const HERO_LEN = 270;
const CLOSE = {s: 3.4, fx: 743, fy: 32, ax: 960, ay: 400};
export const Hero: React.FC = () => {
  const f = useCurrentFrame();
  const cam = camAt(f, [
    {f: 0, ...CLOSE},
    {f: 66, ...CLOSE, s: 3.6},
    {f: 94, s: 1.0, fx: 780, fy: 0, ax: 960, ay: 130},
    {f: 186, s: 1.0, fx: 780, fy: 0, ax: 960, ay: 130},
    {f: 222, ...CLOSE},
  ]);
  const reveal = spring({frame: f - 80, fps: 30, config: {damping: 20, stiffness: 150, mass: 0.9}}) * (1 - range(f, 180, 194));
  const codexOk = f >= 152, claudeOk = f >= 176;
  const waiting = (i: number) => f >= 20 && ((i === 2 && !codexOk) || (i === 0 && !claudeOk));
  const state = (i: number): State => (waiting(i) ? 'waiting' : 'working');
  const blink = (i: number) => (waiting(i) ? 0.5 + 0.5 * Math.cos(((f - 20) / 30) * Math.PI * 2 * 1.2) : 1);
  const rings = f >= 20 && f < 80 ? [0, 2].map((i) => ({i, t: ((f - 20 + i * 10) % 40) / 40, color: C.yellow})) : [];
  const cur = cursorState(f, 120, 146, 150, {x: 860, y: 720}, {x: 501, y: 474}, 166);
  const kp = range(f, 173, 176) * (1 - range(f, 180, 186));
  const kOp = win(f, 160, 200, 8, 10);
  return (
    <AbsoluteFill>
      <World cam={cam}>
        <Laptop clock="Tue 14:25" calm={1}
          wing={{items: ASK_WING, state, blink, rings: [...rings, {i: 2, t: range(f, 152, 182, (t) => t), color: C.green}, {i: 0, t: range(f, 176, 206, (t) => t), color: C.green}],
            glow: (i) => (waiting(i) && f < 80 ? 0.8 : 0)}}
          over={<>
            <Panel layers={[{shot: 'ask', o: 1}]} reveal={reveal} spot={{y0: 380, y1: 504, a: win(f, 104, 176, 10, 10)}} />
            <Ripple x={cur.x} y={cur.y} t={cur.ripple} r={30} />
            <Cursor x={cur.x} y={cur.y} press={cur.press} opacity={cur.op} size={40} />
          </>} />
      </World>
      <Caption frame={f} from={22} to={76} y={720} size={92} segs={[{t: 'Two agents are'}, {t: 'waiting.', c: C.yellow}]} />
      <Caption frame={f} from={100} to={206} y={900} size={80} segs={[{t: 'Approve from'}, {t: 'the notch.'}]} />
      <div style={{position: 'absolute', right: 120, top: 560, display: 'flex', gap: 14, opacity: kOp}}>
        <Keycap pressed={kp} size={76}>⌃</Keycap><Keycap pressed={kp} size={76}>⌥</Keycap><Keycap pressed={kp} size={76}>Y</Keycap>
      </div>
    </AbsoluteFill>
  );
};
