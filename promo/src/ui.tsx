import React from 'react';
import {Easing, interpolate} from 'remotion';

export const SANS = '-apple-system, "SF Pro Display", "Inter", system-ui, "Helvetica Neue", sans-serif';
export const MONO = '"SF Mono", ui-monospace, Menlo, monospace';
export const C = {
  bg: '#050506',
  text: '#f5f5f7',
  dim: '#86868b',
  green: '#34c759',
  yellow: '#ffb31f',
  red: '#ff453a',
  grey: '#8e8e93',
  claude: '#e0583a',
};
export type State = 'working' | 'waiting' | 'stuck' | 'done';
export const stateColor = (s: State) => ({working: C.green, waiting: C.yellow, stuck: C.red, done: C.grey}[s]);

export const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
export const ease = Easing.bezier(0.22, 1, 0.36, 1);
export const easeIO = Easing.bezier(0.65, 0, 0.35, 1);
export const range = (f: number, a: number, b: number, e = ease) =>
  interpolate(f, [a, b], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: e});

/** Vendor mark: Claude = orange tile with burst, Codex = dark tile with blue orb. */
export const Mark: React.FC<{
  vendor: 'claude' | 'codex';
  state: State;
  size: number;
  weight?: number; // 0..1 model weight -> fill brightness
  dotOpacity?: number;
}> = ({vendor, state, size, weight = 1, dotOpacity = 1}) => {
  const r = size * 0.24;
  const dot = size * 0.34;
  const b = 0.45 + 0.55 * weight;
  return (
    <div style={{position: 'relative', width: size, height: size, filter: `brightness(${b})`}}>
      <svg width={size} height={size} viewBox="0 0 100 100" style={{display: 'block'}}>
        {vendor === 'claude' ? (
          <>
            <defs>
              <linearGradient id="cg" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#ee6a47" />
                <stop offset="1" stopColor="#cf4a2a" />
              </linearGradient>
            </defs>
            <rect width="100" height="100" rx={24} fill="url(#cg)" />
            <g stroke="#fbe9e2" strokeWidth="6.5" strokeLinecap="round" transform="translate(50 50)">
              {Array.from({length: 12}).map((_, i) => (
                <line key={i} x1="0" y1={i % 2 ? -19 : -14} x2="0" y2="-33" transform={`rotate(${i * 30})`} />
              ))}
              <circle r="11" fill="#fbe9e2" stroke="none" />
            </g>
          </>
        ) : (
          <>
            <defs>
              <radialGradient id="xg" cx="0.45" cy="0.3" r="0.8">
                <stop offset="0" stopColor="#a9b4ff" />
                <stop offset="0.55" stopColor="#4a55ff" />
                <stop offset="1" stopColor="#2a24d8" />
              </radialGradient>
            </defs>
            <rect width="100" height="100" rx={24} fill="#15151c" stroke="#2b2b36" strokeWidth="3" />
            <circle cx="50" cy="50" r="31" fill="url(#xg)" />
            <path d="M33 41 L43 50 L33 59" fill="none" stroke="#e8ecff" strokeWidth="5.5" strokeLinecap="round" strokeLinejoin="round" />
            <line x1="49" y1="60" x2="64" y2="60" stroke="#e8ecff" strokeWidth="5.5" strokeLinecap="round" />
          </>
        )}
      </svg>
      <div
        style={{
          position: 'absolute',
          right: -dot * 0.28,
          bottom: -dot * 0.28,
          width: dot,
          height: dot,
          borderRadius: '50%',
          background: stateColor(state),
          boxShadow: `0 0 0 ${size * 0.07}px #000, 0 0 ${size * 0.5}px ${stateColor(state)}66`,
          opacity: dotOpacity,
          filter: `brightness(${1 / b})`,
        }}
      />
    </div>
  );
};

export const Glow: React.FC<{opacity?: number}> = ({opacity = 1}) => (
  <div style={{position: 'absolute', inset: 0, overflow: 'hidden', opacity}}>
    <div style={{position: 'absolute', left: '50%', top: '-35%', width: 1800, height: 1400, transform: 'translateX(-50%)',
      background: 'radial-gradient(closest-side, rgba(88,86,214,0.30), rgba(224,88,58,0.10) 55%, transparent 100%)'}} />
    <div style={{position: 'absolute', left: '-10%', bottom: '-40%', width: 1200, height: 900,
      background: 'radial-gradient(closest-side, rgba(10,132,255,0.10), transparent 100%)'}} />
  </div>
);

/** Screenshot cropped to the panel, shown at native pixels. */
export const PanelShot: React.FC<{src: string; h: number; scale?: number}> = ({src, h, scale = 1}) => (
  <div style={{width: 760 * scale, height: h * scale, borderRadius: 22 * scale, overflow: 'hidden', position: 'relative',
    boxShadow: '0 40px 120px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.10)'}}>
    <img src={src} style={{position: 'absolute', left: -400 * scale, top: -76 * scale, width: 1280 * scale, imageRendering: 'auto'}} />
  </div>
);

export const Caption: React.FC<{frame: number; from: number; to: number; y: number; size?: number; children: React.ReactNode}> = ({frame, from, to, y, size = 92, children}) => {
  const inn = range(frame, from, from + 18);
  const out = range(frame, to - 12, to, Easing.in(Easing.quad));
  const o = inn * (1 - out);
  if (o <= 0.001) return null;
  return (
    <div style={{position: 'absolute', left: 0, right: 0, top: y, textAlign: 'center', fontFamily: SANS, fontWeight: 650, fontSize: size,
      letterSpacing: -size * 0.03, color: C.text, opacity: o, transform: `translateY(${(1 - inn) * 26 - out * 14}px)`, filter: `blur(${(1 - inn) * 8 + out * 6}px)`, lineHeight: 1.08}}>
      {children}
    </div>
  );
};

export const Cursor: React.FC<{x: number; y: number; press: number; opacity?: number}> = ({x, y, press, opacity = 1}) => (
  <svg width="64" height="64" viewBox="0 0 24 24" style={{position: 'absolute', left: x - 6, top: y - 4, opacity, transform: `scale(${1 - 0.12 * press})`, transformOrigin: '6px 4px', filter: 'drop-shadow(0 6px 10px rgba(0,0,0,0.6))'}}>
    <path d="M4 2 L4 19 L8.6 14.8 L11.6 21.6 L14.4 20.4 L11.4 13.8 L17.6 13.6 Z" fill="#fff" stroke="#000" strokeWidth="1.3" strokeLinejoin="round" />
  </svg>
);

export const Key: React.FC<{children: React.ReactNode; pressed?: number}> = ({children, pressed = 0}) => (
  <div style={{display: 'inline-flex', alignItems: 'center', justifyContent: 'center', minWidth: 64, height: 64, padding: '0 18px', borderRadius: 16,
    fontFamily: SANS, fontSize: 30, fontWeight: 600, color: C.text, background: `linear-gradient(#34343a, #26262b)`,
    boxShadow: `0 ${6 - pressed * 4}px 0 #101013, 0 0 0 1px rgba(255,255,255,0.12) inset`, transform: `translateY(${pressed * 4}px)`}}>{children}</div>
);
