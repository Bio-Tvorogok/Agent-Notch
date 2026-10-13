import React from 'react';
import {Easing, interpolate} from 'remotion';

export const SANS = '-apple-system, "SF Pro Display", "Inter", system-ui, "Helvetica Neue", sans-serif';
export const MONO = '"SF Mono", ui-monospace, Menlo, monospace';
export const C = {
  bg: '#050507',
  text: '#f5f5f7',
  dim: '#8e8e94',
  green: '#34c759',
  yellow: '#ffb31f',
  red: '#ff453a',
  grey: '#8e8e93',
  blue: '#5e6bff',
};
export type State = 'working' | 'waiting' | 'stuck' | 'done';
export const stateColor = (s: State) => ({working: C.green, waiting: C.yellow, stuck: C.red, done: C.grey}[s]);

export const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
export const ease = Easing.bezier(0.22, 1, 0.36, 1);
export const easeIO = Easing.bezier(0.65, 0, 0.35, 1);
export const easeIn = Easing.bezier(0.55, 0, 0.9, 0.4);
/** 0..1 progress between frames a and b. */
export const range = (f: number, a: number, b: number, e: (t: number) => number = ease) =>
  interpolate(f, [a, b], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: e});
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
/** Window: fades in over [a, a+i], out over [b-o, b]. */
export const win = (f: number, a: number, b: number, i = 10, o = 10) => Math.min(range(f, a, a + i), 1 - range(f, b - o, b));

/* ---------- camera ---------- */
export type Cam = {s: number; fx: number; fy: number; ax: number; ay: number; rx?: number};
export type CamKey = Cam & {f: number};
/** Piecewise camera between keys (ease in-out between each consecutive pair). */
export const camAt = (frame: number, keys: CamKey[]): Cam => {
  if (frame <= keys[0].f) return keys[0];
  for (let i = 1; i < keys.length; i++) {
    const a = keys[i - 1], b = keys[i];
    if (frame <= b.f) {
      const t = easeIO(clamp01((frame - a.f) / Math.max(1, b.f - a.f)));
      // interpolate scale geometrically so zooms feel even
      const s = Math.exp(lerp(Math.log(a.s), Math.log(b.s), t));
      return {s, fx: lerp(a.fx, b.fx, t), fy: lerp(a.fy, b.fy, t), ax: lerp(a.ax, b.ax, t), ay: lerp(a.ay, b.ay, t), rx: lerp(a.rx ?? 0, b.rx ?? 0, t)};
    }
  }
  return keys[keys.length - 1];
};
/** Stage point -> screen point (ignores tilt). */
export const toScreen = (cam: Cam, x: number, y: number) => ({x: (x - cam.fx) * cam.s + cam.ax, y: (y - cam.fy) * cam.s + cam.ay});

/* ---------- vendor mark (vector redraw of the app's marks) ---------- */
export const Mark: React.FC<{vendor: 'claude' | 'codex'; size: number; state: State; dim?: boolean; dotOpacity?: number; glow?: number}> = ({vendor, size, state, dim, dotOpacity = 1, glow = 0}) => {
  const dot = Math.max(6, size * 0.43);
  const col = stateColor(state);
  return (
    <div style={{position: 'relative', width: size, height: size}}>
      <svg width={size} height={size} viewBox="0 0 100 100" style={{display: 'block', filter: dim ? 'brightness(0.55) saturate(0.8)' : undefined}}>
        {vendor === 'claude' ? (
          <>
            <defs>
              <linearGradient id="mk-cl" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#ee6a47" />
                <stop offset="1" stopColor="#cf4a2a" />
              </linearGradient>
            </defs>
            <rect width="100" height="100" rx={24} fill="url(#mk-cl)" />
            <g stroke="#fbe9e2" strokeWidth="7" strokeLinecap="round" transform="translate(50 50)">
              {Array.from({length: 12}).map((_, i) => (
                <line key={i} x1="0" y1={i % 2 ? -19 : -14} x2="0" y2="-34" transform={`rotate(${i * 30})`} />
              ))}
              <circle r="12" fill="#fbe9e2" stroke="none" />
            </g>
          </>
        ) : (
          <>
            <defs>
              <radialGradient id="mk-cx" cx="0.45" cy="0.3" r="0.8">
                <stop offset="0" stopColor="#b3bcff" />
                <stop offset="0.55" stopColor="#4a55ff" />
                <stop offset="1" stopColor="#2a24d8" />
              </radialGradient>
            </defs>
            <rect width="100" height="100" rx={24} fill="#17171e" stroke="#2c2c38" strokeWidth="3" />
            <circle cx="50" cy="50" r="33" fill="url(#mk-cx)" />
            <path d="M33 40 L43 50 L33 60" fill="none" stroke="#e8ecff" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />
            <line x1="49" y1="61" x2="65" y2="61" stroke="#e8ecff" strokeWidth="6" strokeLinecap="round" />
          </>
        )}
      </svg>
      <div style={{position: 'absolute', left: size - dot / 2 - size * 0.04, top: size - dot / 2 - size * 0.04, width: dot, height: dot, borderRadius: '50%',
        background: col, boxShadow: `0 0 0 ${dot * 0.18}px #000${glow > 0 ? `, 0 0 ${dot * 2.2}px ${dot * 0.4}px ${col}${Math.round(glow * 160).toString(16).padStart(2, '0')}` : ''}`, opacity: dotOpacity}} />
    </div>
  );
};

/* ---------- pointer ---------- */
export const Cursor: React.FC<{x: number; y: number; press?: number; opacity?: number; size?: number}> = ({x, y, press = 0, opacity = 1, size = 44}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={{position: 'absolute', left: x - size * 0.17, top: y - size * 0.08, opacity, transform: `scale(${1 - 0.14 * press})`, transformOrigin: `${size * 0.17}px ${size * 0.08}px`, filter: 'drop-shadow(0 4px 6px rgba(0,0,0,0.55))', overflow: 'visible'}}>
    <path d="M4 2 L4 19 L8.6 14.8 L11.6 21.6 L14.4 20.4 L11.4 13.8 L17.6 13.6 Z" fill="#fff" stroke="#000" strokeWidth="1.3" strokeLinejoin="round" />
  </svg>
);

export const Ripple: React.FC<{x: number; y: number; t: number; color?: string; r?: number}> = ({x, y, t, color = '#fff', r = 34}) =>
  t <= 0 || t >= 1 ? null : (
    <div style={{position: 'absolute', left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: '50%', border: `3px solid ${color}`, opacity: (1 - t) * 0.9, transform: `scale(${0.3 + t * 1.2})`}} />
  );

export const Keycap: React.FC<{children: React.ReactNode; pressed?: number; size?: number}> = ({children, pressed = 0, size = 64}) => (
  <div style={{display: 'inline-flex', alignItems: 'center', justifyContent: 'center', minWidth: size, height: size, padding: `0 ${size * 0.2}px`, borderRadius: size * 0.24,
    fontFamily: SANS, fontSize: size * 0.46, fontWeight: 600, color: C.text, background: pressed > 0.5 ? 'linear-gradient(#3d3d44, #2c2c31)' : 'linear-gradient(#34343a, #26262b)',
    boxShadow: `0 ${size * 0.1 * (1 - pressed * 0.7)}px 0 #0d0d10, 0 0 0 1px rgba(255,255,255,0.13) inset${pressed > 0.5 ? `, 0 0 30px ${C.green}55` : ''}`, transform: `translateY(${pressed * size * 0.07}px)`}}>{children}</div>
);

/* ---------- kinetic caption ---------- */
export type Seg = {t: string; c?: string; mono?: boolean; bg?: string; br?: boolean};
export const Caption: React.FC<{
  frame: number; from: number; to: number; segs: Seg[];
  x?: number; y: number; w?: number; align?: 'left' | 'center'; size?: number; weight?: number; color?: string; sub?: React.ReactNode;
}> = ({frame, from, to, segs, x = 0, y, w, align = 'center', size = 84, weight = 680, color = C.text, sub}) => {
  const out = range(frame, to - 12, to, easeIn);
  if (frame < from || frame > to) return null;
  const words: {w: string; s: Seg; br?: boolean}[] = [];
  segs.forEach((s) => {
    if (s.br && words.length) words[words.length - 1].br = true;
    (s.mono ? [s.t] : s.t.split(' ')).forEach((wd) => wd && words.push({w: wd, s}));
  });
  const subIn = range(frame, from + 10 + words.length * 3, from + 28 + words.length * 3);
  return (
    <div style={{position: 'absolute', left: x, top: y, width: w ?? (align === 'center' ? '100%' : undefined), textAlign: align, fontFamily: SANS, fontWeight: weight, fontSize: size,
      letterSpacing: -size * 0.032, color, lineHeight: 1.08, opacity: 1 - out, transform: `translateY(${-out * 18}px)`, filter: `blur(${out * 8}px)`}}>
      {words.map(({w: wd, s, br}, i) => {
        const p = range(frame, from + i * 3, from + i * 3 + 16);
        return (
          <React.Fragment key={i}>
          <span style={{display: 'inline-block', marginRight: size * 0.24, opacity: p, transform: `translateY(${(1 - p) * size * 0.45}px)`, filter: `blur(${(1 - p) * 10}px)`,
            color: s.c ?? color, fontFamily: s.mono ? MONO : SANS, fontSize: s.mono ? size * 0.82 : size, fontWeight: s.mono ? 600 : weight, letterSpacing: s.mono ? -size * 0.01 : undefined,
            background: s.bg, padding: s.bg ? `0 ${size * 0.18}px` : undefined, borderRadius: s.bg ? size * 0.16 : undefined}}>{wd}</span>
          {br && <br />}
          </React.Fragment>
        );
      })}
      {sub && <div style={{marginTop: size * 0.32, fontSize: size * 0.4, fontWeight: 500, letterSpacing: -0.2, color: '#a1a1a8', opacity: subIn, transform: `translateY(${(1 - subIn) * 14}px)`, lineHeight: 1.35}}>{sub}</div>}
    </div>
  );
};
