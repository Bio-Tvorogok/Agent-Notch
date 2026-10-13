import React from 'react';
import {AbsoluteFill, interpolate, spring, staticFile, useCurrentFrame} from 'remotion';
import {C, Cursor, Key, Mark, MONO, PanelShot, SANS, State, clamp01, ease, easeIO, range, Caption, Glow} from './ui';

export const BAR_H = 58;
export const NOTCH_L = 810;
export const NOTCH_R = 1110;
const PAD = 26;
const GAP = 13;

type Agent = {vendor: 'claude' | 'codex'; sub?: boolean; weight: number; base: State};
export const AGENTS: Agent[] = [
  {vendor: 'claude', weight: 1, base: 'working'},
  {vendor: 'claude', sub: true, weight: 0.8, base: 'working'},
  {vendor: 'claude', sub: true, weight: 0.5, base: 'working'},
  {vendor: 'codex', weight: 1, base: 'working'}, // the one that asks
  {vendor: 'codex', weight: 0.85, base: 'working'},
  {vendor: 'claude', weight: 0.8, base: 'working'},
  {vendor: 'codex', sub: true, weight: 0.5, base: 'done'},
];
const sz = (a: Agent) => (a.sub ? 25 : 35);
const total = AGENTS.reduce((s, a) => s + sz(a), 0) + GAP * (AGENTS.length - 1);
export const WING_W = total + PAD * 2;
export const WING_L = NOTCH_L - WING_W;
export const markX = (i: number) => {
  let x = WING_L + PAD;
  for (let k = 0; k < i; k++) x += sz(AGENTS[k]) + GAP;
  return x + sz(AGENTS[i]) / 2;
};

export type Cfg = {
  wingIn: number;
  popStart: number;
  popGap: number;
  yellow: number;
  panelOpen: number;
  keysIn: number;
  cursorIn: number;
  click: number;
  panelClose: number;
  green: number;
  cam: {f: number[]; s: number[]; fx: number[]; cy: number[]};
  legend?: [number, number];
  captions: {from: number; to: number; y: number; size?: number; node: React.ReactNode}[];
  fadeEnds?: boolean;
};

const MenuBar: React.FC = () => (
  <div style={{position: 'absolute', left: -400, right: -400, top: -4, height: BAR_H + 4,
    background: 'linear-gradient(#3c3c41, #303034)', borderBottom: '1px solid rgba(255,255,255,0.06)',
    WebkitMaskImage: 'linear-gradient(90deg, transparent, #000 22%, #000 78%, transparent)'}}>
    <div style={{position: 'absolute', left: 520, top: 21, display: 'flex', gap: 22, alignItems: 'center'}}>
      <div style={{width: 16, height: 18, borderRadius: 8, background: '#cfcfd4'}} />
      {[54, 34, 38, 42].map((w, i) => <div key={i} style={{width: w, height: 10, borderRadius: 5, background: '#8d8d93'}} />)}
    </div>
    <div style={{position: 'absolute', left: 1400, top: 21, display: 'flex', gap: 20, alignItems: 'center'}}>
      {[18, 22, 18].map((w, i) => <div key={i} style={{width: w, height: 12, borderRadius: 4, background: '#8d8d93'}} />)}
      <div style={{width: 64, height: 11, borderRadius: 5, background: '#cfcfd4'}} />
    </div>
  </div>
);

export const Legend: React.FC<{frame: number; from: number; to: number; y: number}> = ({frame, from, to, y}) => {
  const items: {vis: React.ReactNode; k: string; v: string}[] = [
    {vis: <><Mark vendor="claude" state="working" size={72} /><Mark vendor="codex" state="working" size={72} /></>, k: 'shape', v: 'vendor'},
    {vis: <><Mark vendor="claude" state="working" size={72} weight={1} dotOpacity={0} /><Mark vendor="claude" state="working" size={72} weight={0.7} dotOpacity={0} /><Mark vendor="claude" state="working" size={72} weight={0.4} dotOpacity={0} /></>, k: 'fill', v: 'model'},
    {vis: <><Mark vendor="codex" state="working" size={72} /><Mark vendor="codex" state="waiting" size={72} /><Mark vendor="codex" state="stuck" size={72} /><Mark vendor="codex" state="done" size={72} /></>, k: 'color', v: 'state'},
  ];
  const out = range(frame, to - 14, to);
  return (
    <div style={{position: 'absolute', left: 0, right: 0, top: y, display: 'flex', justifyContent: 'center', gap: 120, opacity: 1 - out}}>
      {items.map((it, i) => {
        const p = range(frame, from + i * 14, from + i * 14 + 26);
        return (
          <div key={i} style={{width: 420, textAlign: 'center', opacity: p, transform: `translateY(${(1 - p) * 30}px)`}}>
            <div style={{height: 96, display: 'flex', gap: 28, justifyContent: 'center', alignItems: 'center'}}>{it.vis}</div>
            <div style={{marginTop: 28, fontFamily: SANS, fontSize: 40, color: C.dim, fontWeight: 500}}>
              <span style={{color: C.text, fontWeight: 650}}>{it.k}</span> = {it.v}
            </div>
          </div>
        );
      })}
    </div>
  );
};

export const NotchStory: React.FC<{cfg: Cfg}> = ({cfg}) => {
  const frame = useCurrentFrame();
  const fps = 30;
  const {cam} = cfg;
  const ip = (arr: number[]) => interpolate(frame, cam.f, arr, {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: easeIO});
  const s = ip(cam.s), fx = ip(cam.fx), cy = ip(cam.cy);

  const wingP = spring({frame: frame - cfg.wingIn, fps, config: {damping: 18, stiffness: 120}});
  const wingW = WING_W * clamp01(wingP) + 0; // grows leftwards
  const wingL = NOTCH_L - wingW;

  const markState = (i: number): State => {
    if (i !== 3) return AGENTS[i].base;
    if (frame >= cfg.green) return 'working';
    if (frame >= cfg.yellow) return 'waiting';
    return 'working';
  };
  const blink = frame >= cfg.yellow && frame < cfg.click + 6 ? 0.55 + 0.45 * Math.cos(((frame - cfg.yellow) / fps) * Math.PI * 2 * 1.4) : 1;
  const pulse = frame >= cfg.yellow ? ((frame - cfg.yellow) % 40) / 40 : -1;
  const greenFlash = range(frame, cfg.green, cfg.green + 30);

  // panel
  const openP = spring({frame: frame - cfg.panelOpen, fps, config: {damping: 20, stiffness: 140, mass: 0.9}});
  const closeP = range(frame, cfg.panelClose, cfg.panelClose + 16, easeIO);
  const PS = 1.1, PH = 614;
  const panelLeft = 960 - (760 * PS) / 2, panelTop = BAR_H + 20;
  const reveal = clamp01(openP) * (1 - closeP);
  const panelVisible = frame >= cfg.panelOpen - 1 && closeP < 1;

  // cursor
  // Allow button of the rm -rf row in ask.png: centre (501, 474) of the 1280px image; panel crop origin is (400, 76)
  const allow = {x: panelLeft + (501 - 400) * PS, y: panelTop + (474 - 76) * PS};
  const cp = range(frame, cfg.cursorIn, cfg.click - 4, easeIO);
  const curX = interpolate(cp, [0, 1], [allow.x + 420, allow.x]);
  const curY = interpolate(cp, [0, 1], [allow.y + 300, allow.y]);
  const press = range(frame, cfg.click - 3, cfg.click + 1) * (1 - range(frame, cfg.click + 1, cfg.click + 8));
  const cursorOp = range(frame, cfg.cursorIn, cfg.cursorIn + 8) * (1 - range(frame, cfg.click + 12, cfg.click + 24));
  const ripple = range(frame, cfg.click, cfg.click + 22);
  const toast = range(frame, cfg.click + 6, cfg.click + 22);
  const toastOut = range(frame, cfg.panelClose + 10, cfg.panelClose + 28);
  const keys = range(frame, cfg.keysIn, cfg.keysIn + 20) * (1 - range(frame, cfg.click - 2, cfg.click + 8));

  const stageTf = `translate(960px, ${cy}px) scale(${s}) translate(${-fx}px, ${-BAR_H / 2}px)`;
  const bigOp = cfg.fadeEnds ? Math.min(range(frame, 0, 10), 1 - range(frame, 282, 298)) : 1;

  return (
    <AbsoluteFill style={{background: C.bg, opacity: bigOp}}>
      <Glow />
      <div style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, transformOrigin: '0 0', transform: stageTf}}>
        <MenuBar />
        {/* notch + wing */}
        <svg width={1920} height={200} viewBox="0 0 1920 200" style={{position: 'absolute', left: 0, top: -4, overflow: 'visible'}}>
          <path d={`M ${wingL + 22} ${4 + BAR_H} Q ${wingL} ${4 + BAR_H} ${wingL} ${4 + BAR_H - 22} L ${wingL} 0 L ${NOTCH_R} 0 L ${NOTCH_R} ${4 + BAR_H - 22} Q ${NOTCH_R} ${4 + BAR_H} ${NOTCH_R - 22} ${4 + BAR_H} Z`} fill="#000" />
        </svg>
        {/* marks */}
        {AGENTS.map((a, i) => {
          const p = spring({frame: frame - (cfg.popStart + i * cfg.popGap), fps, config: {damping: 11, stiffness: 160, mass: 0.7}});
          const size = sz(a);
          const isTarget = i === 3;
          return (
            <div key={i} style={{position: 'absolute', left: markX(i) - size / 2, top: BAR_H / 2 - size / 2 - 1, transform: `scale(${Math.max(0, p)})`, opacity: clamp01(p * 2)}}>
              {isTarget && pulse >= 0 && frame < cfg.click + 6 && (
                <div style={{position: 'absolute', left: size / 2 - 40, top: size / 2 - 40, width: 80, height: 80, borderRadius: '50%', border: `2px solid ${C.yellow}`, opacity: (1 - pulse) * 0.8, transform: `scale(${0.3 + pulse * 1.1})`}} />
              )}
              {isTarget && greenFlash > 0 && greenFlash < 1 && (
                <div style={{position: 'absolute', left: size / 2 - 40, top: size / 2 - 40, width: 80, height: 80, borderRadius: '50%', border: `2px solid ${C.green}`, opacity: (1 - greenFlash) * 0.9, transform: `scale(${0.3 + greenFlash * 1.1})`}} />
              )}
              <Mark vendor={a.vendor} state={markState(i)} size={size} weight={a.weight} dotOpacity={isTarget ? blink : 1} />
            </div>
          );
        })}
        {/* panel */}
        {panelVisible && (
          <div style={{position: 'absolute', left: panelLeft, top: panelTop, transformOrigin: '50% 0',
            opacity: clamp01(reveal * 1.6), transform: `translateY(${(1 - reveal) * -28}px) scale(${0.9 + 0.1 * reveal})`,
            clipPath: `inset(0 0 ${(1 - clamp01(reveal)) * 100}% 0 round 22px)`}}>
            <PanelShot src={staticFile('ask.png')} h={PH} scale={PS} />
          </div>
        )}
      </div>

      {/* overlays in screen space */}
      {cfg.legend && <Legend frame={frame} from={cfg.legend[0]} to={cfg.legend[1]} y={560} />}
      {cfg.captions.map((c, i) => <Caption key={i} frame={frame} from={c.from} to={c.to} y={c.y} size={c.size}>{c.node}</Caption>)}

      {/* key hint + toast */}
      <div style={{position: 'absolute', left: 0, right: 0, top: 800, display: 'flex', justifyContent: 'center', gap: 28, alignItems: 'center', fontFamily: SANS, fontSize: 30, color: C.dim, opacity: keys, transform: `translateY(${(1 - keys) * 16}px)`}}>
        <span>or press</span><Key>⌃ ⌥ Y</Key><span>allow</span><span style={{width: 18}} /><Key>⌃ ⌥ N</Key><span>deny</span>
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 796, display: 'flex', justifyContent: 'center', opacity: toast * (1 - toastOut), transform: `translateY(${(1 - toast) * 16}px) scale(${0.94 + 0.06 * toast})`}}>
        <div style={{fontFamily: SANS, fontWeight: 600, fontSize: 34, color: '#fff', padding: '16px 34px', borderRadius: 999, background: 'rgba(52,199,89,0.16)', boxShadow: `0 0 0 1px ${C.green}88 inset, 0 0 60px ${C.green}33`, display: 'flex', gap: 14, alignItems: 'center'}}>
          <span style={{color: C.green}}>✓</span> Allowed · agent continues
        </div>
      </div>
      {cfg.click > 0 && (
        <>
          {ripple > 0 && ripple < 1 && (
            <div style={{position: 'absolute', left: allow.x - 36, top: allow.y - 36, width: 72, height: 72, borderRadius: '50%', border: '3px solid rgba(255,255,255,0.8)', opacity: 1 - ripple, transform: `scale(${0.3 + ripple})`}} />
          )}
          <Cursor x={curX} y={curY} press={press} opacity={cursorOp} />
        </>
      )}
    </AbsoluteFill>
  );
};
