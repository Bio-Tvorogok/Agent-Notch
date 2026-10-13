import React from 'react';
import {AbsoluteFill, Img, staticFile, useVideoConfig} from 'remotion';
import {C, Cam, MONO, Mark, SANS, State, clamp01} from './lib';

/*
 * Stage coordinates = pixel coordinates of the app screenshots in public/ (1280 px wide, @2x).
 * In those shots the menu bar is 64 px tall, the black notch bar ends at x = 1159 and the panel
 * occupies x 401..1158 from y = 77. The hardware notch is ~[792, 1160], so the screen centre is x ≈ 975.
 */
export const BAR = 64;
export const NOTCH_L = 792;
export const NOTCH_R = 1160;
export const SCREEN_W = 3024;
export const SCREEN_H = 1964;
export const SX0 = 975 - SCREEN_W / 2; // -537
export const SX1 = SX0 + SCREEN_W;
export const PANEL_X = 401;
export const PANEL_Y = 77;
export const PANEL_W = 758;

/* ---------- wing ---------- */
export type WingItem = {v: 'claude' | 'codex'; st: State; dim?: boolean; sub?: boolean; count?: number};
export const HEAVY_WING: WingItem[] = [
  {v: 'claude', st: 'working', count: 7},
  {v: 'codex', st: 'working', count: 7},
  {v: 'codex', st: 'stuck'},
  {v: 'claude', st: 'stuck'},
  {v: 'codex', st: 'waiting', dim: true},
];
export const ASK_WING: WingItem[] = [
  {v: 'claude', st: 'waiting'},
  {v: 'claude', st: 'working', sub: true},
  {v: 'codex', st: 'waiting'},
];
export type WingLayout = {left: number; marks: {cx: number; size: number; textX?: number}[]};
export const layoutWing = (items: WingItem[]): WingLayout => {
  const marks: WingLayout['marks'] = new Array(items.length);
  let right = 780;
  for (let i = items.length - 1; i >= 0; i--) {
    const it = items[i];
    const size = it.sub ? 10 : 14;
    const w = size + (it.count ? 18 : 0);
    const l = right - w;
    marks[i] = {cx: l + size / 2, size, textX: it.count ? l + size + 5 : undefined};
    right = l - (it.sub ? 7 : 16);
  }
  return {left: marks[0].cx - marks[0].size / 2 - 24, marks};
};

export type WingProps = {
  items: WingItem[];
  grow?: number; // 0..1 how far the black wing is extended
  pop?: (i: number) => number; // 0..1+ spring scale per mark
  state?: (i: number) => State;
  blink?: (i: number) => number; // opacity multiplier
  glow?: (i: number) => number;
  rings?: {i: number; t: number; color: string}[];
};
export const Wing: React.FC<WingProps> = ({items, grow = 1, pop, state, blink, glow, rings = []}) => {
  const L = layoutWing(items);
  const left = NOTCH_L - (NOTCH_L - L.left) * clamp01(grow);
  const r = 16;
  return (
    <>
      <svg width={2000} height={200} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}}>
        <path d={`M ${left + r} ${BAR} Q ${left} ${BAR} ${left} ${BAR - r} L ${left} -1 L ${NOTCH_R} -1 L ${NOTCH_R} ${BAR - r} Q ${NOTCH_R} ${BAR} ${NOTCH_R - r} ${BAR} Z`} fill="#000" />
      </svg>
      {items.map((it, i) => {
        const m = L.marks[i];
        const p = pop ? pop(i) : 1;
        if (p <= 0.001) return null;
        const st = state ? state(i) : it.st;
        return (
          <React.Fragment key={i}>
            {rings.filter((rg) => rg.i === i && rg.t > 0 && rg.t < 1).map((rg, k) => (
              <div key={k} style={{position: 'absolute', left: m.cx - 14, top: BAR / 2 - 14, width: 28, height: 28, borderRadius: '50%', border: `1.2px solid ${rg.color}`, opacity: (1 - rg.t) * 0.9, transform: `scale(${0.35 + rg.t * 1.3})`}} />
            ))}
            <div style={{position: 'absolute', left: m.cx - m.size / 2, top: BAR / 2 - m.size / 2, transform: `scale(${p})`, opacity: clamp01(p * 2) * (blink ? blink(i) : 1)}}>
              <Mark vendor={it.v} size={m.size} state={st} dim={it.dim} glow={glow ? glow(i) : 0} />
            </div>
            {m.textX && (
              <div style={{position: 'absolute', left: m.textX, top: BAR / 2 - 13, fontFamily: SANS, fontWeight: 650, fontSize: 20, color: '#fff', opacity: clamp01(p * 2), lineHeight: '26px'}}>{it.count}</div>
            )}
          </React.Fragment>
        );
      })}
    </>
  );
};

/* ---------- screenshot panel ---------- */
export const panelH = (imgH: number) => imgH - 98;
export const SHOTS = {
  ask: {src: 'ask.png', h: 712},
  question: {src: 'question.png', h: 684},
  plan: {src: 'plan.png', h: 624},
  heavy: {src: 'heavy.png', h: 1084},
  projects: {src: 'projects.png', h: 822},
};
export type Shot = keyof typeof SHOTS;
export const Panel: React.FC<{layers: {shot: Shot; o: number}[]; reveal: number; spot?: {y0: number; y1: number; a: number}}> = ({layers, reveal, spot}) => {
  if (reveal <= 0.001) return null;
  const h = layers.reduce((s, l) => s + panelH(SHOTS[l.shot].h) * l.o, 0) / Math.max(0.0001, layers.reduce((s, l) => s + l.o, 0));
  const rv = clamp01(reveal);
  return (
    <div style={{position: 'absolute', left: PANEL_X, top: PANEL_Y, width: PANEL_W, height: h, borderRadius: 21, transformOrigin: '50% 0',
      transform: `translateY(${(1 - rv) * -24}px) scale(${0.94 + 0.06 * rv})`, opacity: clamp01(reveal * 1.8),
      clipPath: `inset(0 0 ${(1 - rv) * 100}% 0 round 21px)`,
      boxShadow: '0 40px 90px rgba(0,0,0,0.65), 0 0 0 1px rgba(255,255,255,0.09)'}}>
      <div style={{position: 'absolute', inset: 0, overflow: 'hidden', borderRadius: 21, background: '#1c1c1c'}}>
        {layers.filter((l) => l.o > 0.001).map((l) => (
          <Img key={l.shot} src={staticFile(SHOTS[l.shot].src)} style={{position: 'absolute', left: -PANEL_X, top: -PANEL_Y, width: 1280, height: SHOTS[l.shot].h, opacity: l.o}} />
        ))}
        {spot && spot.a > 0.001 && (
          <div style={{position: 'absolute', left: 6, right: 6, top: spot.y0 - PANEL_Y, height: spot.y1 - spot.y0, borderRadius: 14,
            boxShadow: `0 0 0 3000px rgba(0,0,0,${0.58 * spot.a}), 0 0 0 2px rgba(255,255,255,${0.35 * spot.a}) inset`}} />
        )}
      </div>
    </div>
  );
};

/* ---------- laptop ---------- */
const Wallpaper: React.FC<{calm?: number}> = ({calm = 0}) => (
  <div style={{position: 'absolute', inset: 0, background: '#0b0b12', overflow: 'hidden'}}>
    <div style={{position: 'absolute', left: -600, top: -900, width: 2600, height: 2200, background: 'radial-gradient(closest-side, rgba(94,80,220,0.55), transparent)'}} />
    <div style={{position: 'absolute', left: 1500, top: 600, width: 2400, height: 2000, background: 'radial-gradient(closest-side, rgba(232,96,60,0.38), transparent)'}} />
    <div style={{position: 'absolute', left: 300, top: 1100, width: 2200, height: 1600, background: 'radial-gradient(closest-side, rgba(20,120,255,0.28), transparent)'}} />
    <div style={{position: 'absolute', inset: 0, background: `rgba(4,4,8,${0.25 + 0.4 * calm})`}} />
  </div>
);

const MenuBar: React.FC<{clock: string}> = ({clock}) => (
  <div style={{position: 'absolute', left: 0, top: 0, width: SCREEN_W, height: BAR, background: 'rgba(22,22,28,0.72)', fontFamily: SANS, color: '#f2f2f5'}}>
    <div style={{position: 'absolute', left: 44, top: 0, height: BAR, display: 'flex', alignItems: 'center', gap: 40, fontSize: 27, fontWeight: 500}}>
      <svg width="26" height="30" viewBox="0 0 26 30"><path d="M21.5 16c0-3.6 3-5.3 3.1-5.4-1.7-2.5-4.3-2.8-5.2-2.8-2.2-.2-4.3 1.3-5.4 1.3-1.1 0-2.8-1.3-4.7-1.2C6.9 8 4.6 9.4 3.4 11.6c-2.6 4.4-.7 11 1.8 14.6 1.2 1.8 2.7 3.7 4.6 3.6 1.8-.1 2.5-1.2 4.8-1.2 2.2 0 2.9 1.2 4.8 1.1 2 0 3.2-1.8 4.4-3.6 1.4-2 2-4 2-4.1-.1 0-3.9-1.5-4.3-6zM17.9 5.3c1-1.2 1.7-2.9 1.5-4.6-1.4.1-3.2 1-4.2 2.2-.9 1.1-1.7 2.8-1.5 4.4 1.6.1 3.2-.8 4.2-2z" fill="#f2f2f5" /></svg>
      <span style={{fontWeight: 700}}>Terminal</span>
      {['Shell', 'Edit', 'View', 'Window', 'Help'].map((t) => <span key={t}>{t}</span>)}
    </div>
    <div style={{position: 'absolute', right: 44, top: 0, height: BAR, display: 'flex', alignItems: 'center', gap: 34, fontSize: 27, fontWeight: 500}}>
      <svg width="34" height="24" viewBox="0 0 34 24"><path d="M17 22 l4-4.5a6 6 0 0 0-8 0z M17 9.5a12 12 0 0 1 8.6 3.6l2.6-2.9A16 16 0 0 0 17 5.5a16 16 0 0 0-11.2 4.7l2.6 2.9A12 12 0 0 1 17 9.5z" fill="#f2f2f5" /></svg>
      <svg width="46" height="22" viewBox="0 0 46 22"><rect x="1" y="1" width="38" height="20" rx="5" fill="none" stroke="#bdbdc2" strokeWidth="2" /><rect x="4" y="4" width="26" height="14" rx="3" fill="#f2f2f5" /><rect x="41" y="7" width="3" height="8" rx="1.5" fill="#bdbdc2" /></svg>
      <span style={{fontVariantNumeric: 'tabular-nums'}}>{clock}</span>
    </div>
  </div>
);

export const Laptop: React.FC<{clock?: string; calm?: number; under?: React.ReactNode; wing?: WingProps; over?: React.ReactNode; glow?: number}> = ({clock = 'Tue 14:02', calm, under, wing, over, glow = 0}) => (
  <>
    {/* base + shadow (seen only in the wide shot) */}
    <div style={{position: 'absolute', left: SX0 - 420, top: SCREEN_H + 70, width: SCREEN_W + 840, height: 120, borderRadius: '50%', background: 'radial-gradient(closest-side, rgba(0,0,0,0.85), transparent)'}} />
    <div style={{position: 'absolute', left: SX0 - 260, top: SCREEN_H + 36, width: SCREEN_W + 520, height: 62,
      background: 'linear-gradient(#d5d6db, #9b9ca2 45%, #5f6066)', clipPath: 'polygon(3% 0, 97% 0, 100% 62%, 99% 100%, 1% 100%, 0 62%)'}} />
    <div style={{position: 'absolute', left: 975 - 260, top: SCREEN_H + 36, width: 520, height: 16, borderRadius: '0 0 18px 18px', background: 'linear-gradient(#77787e, #a4a5ab)'}} />
    {/* lid */}
    <div style={{position: 'absolute', left: SX0 - 38, top: -38, width: SCREEN_W + 76, height: SCREEN_H + 76, borderRadius: 56, background: 'linear-gradient(#7c7d83, #4a4b50 3%, #3a3b40 60%, #6d6e74)', boxShadow: '0 60px 160px rgba(0,0,0,0.7)'}} />
    <div style={{position: 'absolute', left: SX0 - 34, top: -34, width: SCREEN_W + 68, height: SCREEN_H + 68, borderRadius: 52, background: '#060607'}} />
    <div style={{position: 'absolute', left: SX0, top: 0, width: SCREEN_W, height: SCREEN_H, borderRadius: '22px 22px 6px 6px', overflow: 'hidden'}}>
      <Wallpaper calm={calm} />
      <div style={{position: 'absolute', left: -SX0, top: 0}}>{under}</div>
      <MenuBar clock={clock} />
    </div>
    {glow > 0.001 && <div style={{position: 'absolute', left: 300, top: -420, width: 1000, height: 900, borderRadius: '50%', opacity: glow, background: 'radial-gradient(closest-side, rgba(255,190,120,0.55), rgba(120,110,255,0.25) 50%, transparent)'}} />}
    {/* notch (+ wing) */}
    {wing ? <Wing {...wing} /> : <Wing items={ASK_WING} grow={0} pop={() => 0} />}
    {/* camera dot */}
    <div style={{position: 'absolute', left: 975 - 5, top: 14, width: 10, height: 10, borderRadius: '50%', background: '#15151c', boxShadow: '0 0 0 2px #0b0b10'}} />
    {over}
  </>
);

/* ---------- world: backdrop + camera ---------- */
export const Backdrop: React.FC<{tone?: number}> = ({tone = 1}) => (
  <AbsoluteFill style={{background: C.bg}}>
    <div style={{position: 'absolute', left: '50%', top: '-40%', width: 2200, height: 1500, transform: 'translateX(-50%)', opacity: tone,
      background: 'radial-gradient(closest-side, rgba(96,86,230,0.22), rgba(224,88,58,0.07) 60%, transparent)'}} />
  </AbsoluteFill>
);

export const World: React.FC<{cam: Cam; children: React.ReactNode; tone?: number}> = ({cam, children, tone}) => {
  const {s, fx, fy, ax, ay, rx = 0} = cam;
  const tf = Math.abs(rx) > 0.01
    ? `translate(${ax}px, ${ay}px) scale(${s}) rotateX(${rx}deg) translate(${-fx}px, ${-fy}px)`
    : `translate(${ax}px, ${ay}px) scale(${s}) translate(${-fx}px, ${-fy}px)`;
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Backdrop tone={tone} />
      <div style={{position: 'absolute', inset: 0, perspective: 3200, perspectiveOrigin: `${ax}px ${ay}px`}}>
        <div style={{position: 'absolute', left: 0, top: 0, width: 1, height: 1, transformOrigin: '0 0', transform: tf, transformStyle: 'preserve-3d'}}>
          {children}
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const useV = () => {
  const {width, height} = useVideoConfig();
  return {W: width, H: height, V: height > width};
};

export {MONO};
