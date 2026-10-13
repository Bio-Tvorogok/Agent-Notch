import React from 'react';
import {AbsoluteFill, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, Glow, MONO, SANS, Mark, PanelShot, Caption, clamp01, ease, easeIO, range} from './ui';
import {AGENTS, Cfg, NOTCH_L, NOTCH_R, NotchStory, WING_L, markX, BAR_H} from './NotchStory';

const m3 = markX(3);
const Cmd: React.FC<{children: React.ReactNode}> = ({children}) => (
  <span style={{fontFamily: MONO, fontWeight: 600, color: C.red, background: 'rgba(255,69,58,0.12)', padding: '0 22px', borderRadius: 18, fontSize: '0.86em'}}>{children}</span>
);

const cfg: Cfg = {
  wingIn: 95, popStart: 112, popGap: 11, yellow: 275,
  panelOpen: 408, keysIn: 452, cursorIn: 484, click: 524, panelClose: 560, green: 566,
  cam: {
    f: [0, 90, 200, 270, 330, 390, 414],
    s: [2.8, 2.3, 1.95, 1.95, 3.1, 3.1, 1.0],
    fx: [795, 795, 795, 795, m3, m3, 960],
    cy: [400, 400, 380, 380, 400, 400, 29],
  },
  legend: [180, 270],
  captions: [
    {from: 8, to: 98, y: 640, size: 84, node: <>7 agents running. Where are they?</>},
    {from: 108, to: 176, y: 640, size: 84, node: <>Every agent. One glance.</>},
    {from: 282, to: 392, y: 640, size: 80, node: <>Codex wants to run <Cmd>rm -rf dist build</Cmd></>},
    {from: 424, to: 492, y: 880, size: 72, node: <>Risky commands glow red.</>},
    {from: 496, to: 598, y: 880, size: 72, node: <>Approve from the notch.</>},
  ],
};

const Fade: React.FC<{inF?: number; outF?: number; dur: number; children: React.ReactNode}> = ({inF = 12, outF = 12, dur, children}) => {
  const f = useCurrentFrame();
  const o = Math.min(range(f, 0, inF), 1 - range(f, dur - outF, dur));
  return <AbsoluteFill style={{opacity: o}}>{children}</AbsoluteFill>;
};

const Directory: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: f - 6, fps, config: {damping: 20, stiffness: 90}});
  const rot = (1 - clamp01(p)) * -14;
  const l1 = range(f, 10, 34), l2 = range(f, 26, 50), l3 = range(f, 60, 84);
  const hl = range(f, 70, 90) * (0.65 + 0.35 * Math.sin(f / 7));
  return (
    <AbsoluteFill style={{background: C.bg}}>
      <Glow />
      <div style={{position: 'absolute', left: 130, top: 330, fontFamily: SANS, fontWeight: 680, fontSize: 118, letterSpacing: -4, color: C.text, lineHeight: 1.05}}>
        <div style={{opacity: l1, transform: `translateY(${(1 - l1) * 40}px)`}}>Every project.</div>
        <div style={{opacity: l2, transform: `translateY(${(1 - l2) * 40}px)`}}>Every subagent.</div>
        <div style={{opacity: l3, transform: `translateY(${(1 - l3) * 20}px)`, fontSize: 40, fontWeight: 500, letterSpacing: -0.5, color: C.dim, marginTop: 36, lineHeight: 1.35}}>
          Claude Code and Codex, grouped by project.<br />Subagents nest under their parent.
        </div>
      </div>
      <div style={{position: 'absolute', left: 980, top: 46, perspective: 2400, opacity: clamp01(p * 1.5)}}>
        <div style={{transform: `rotateY(${rot}deg) translateX(${(1 - clamp01(p)) * 80}px)`, transformOrigin: '0 50%', position: 'relative'}}>
          <PanelShot src={staticFile('heavy.png')} h={988} />
          <div style={{position: 'absolute', left: 14, top: 532, width: 720, height: 222, borderRadius: 16, border: `2px solid rgba(255,255,255,${0.55 * hl})`, boxShadow: `0 0 50px rgba(120,140,255,${0.35 * hl})`}} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const EndMark: React.FC<{scale?: number}> = ({scale = 1}) => {
  const L = WING_L, W = NOTCH_R - L + 0;
  return (
    <div style={{position: 'relative', width: 1920, height: 120, transform: `scale(${scale})`, transformOrigin: '0 0'}}>
      <svg width={1920} height={120} style={{position: 'absolute', left: 0, top: 0}}>
        <path d={`M ${L + 22} ${BAR_H} Q ${L} ${BAR_H} ${L} ${BAR_H - 22} L ${L} 0 L ${NOTCH_R} 0 L ${NOTCH_R} ${BAR_H - 22} Q ${NOTCH_R} ${BAR_H} ${NOTCH_R - 22} ${BAR_H} Z`} fill="#000" />
      </svg>
      {AGENTS.map((a, i) => {
        const size = a.sub ? 25 : 35;
        return <div key={i} style={{position: 'absolute', left: markX(i) - size / 2, top: BAR_H / 2 - size / 2 - 1}}><Mark vendor={a.vendor} state={i === 6 ? 'done' : 'working'} size={size} weight={a.weight} /></div>;
      })}
    </div>
  );
};

const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const a = (s: number, e: number) => range(f, s, e);
  const sp = spring({frame: f - 4, fps, config: {damping: 16, stiffness: 100}});
  const row = (o: number, y = 30) => ({opacity: o, transform: `translateY(${(1 - o) * y}px)`});
  return (
    <AbsoluteFill style={{background: C.bg}}>
      <Glow />
      <div style={{position: 'absolute', left: 0, top: 130, width: 1920, height: 140, transformOrigin: `${(WING_L + NOTCH_R) / 2}px 0`, transform: `translateX(${960 - (WING_L + NOTCH_R) / 2}px) scale(${1.9 * (0.85 + 0.15 * clamp01(sp))})`, opacity: clamp01(sp * 2)}}>
        <EndMark />
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 330, textAlign: 'center', fontFamily: SANS, fontWeight: 700, fontSize: 168, letterSpacing: -6, color: C.text, ...row(a(14, 40))}}>Agent Notch</div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 540, textAlign: 'center', fontFamily: SANS, fontWeight: 500, fontSize: 48, color: '#b4b4ba', letterSpacing: -0.5, ...row(a(30, 56))}}>Claude Code &amp; Codex in your MacBook notch</div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 650, display: 'flex', justifyContent: 'center', ...row(a(46, 72))}}>
        <div style={{fontFamily: MONO, fontSize: 38, color: C.text, padding: '24px 46px', borderRadius: 999, background: 'rgba(255,255,255,0.07)', boxShadow: '0 0 0 1px rgba(255,255,255,0.16) inset', display: 'flex', gap: 18}}>
          <span style={{color: C.dim}}>$</span><span>brew install --cask forichok/tap/agent-notch</span>
        </div>
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 810, textAlign: 'center', fontFamily: SANS, fontWeight: 600, fontSize: 38, color: C.text, letterSpacing: 0.3, ...row(a(62, 88), 16)}}>
        Free <span style={{color: C.dim}}>·</span> Open source <span style={{color: C.dim}}>·</span> 100% local
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 890, textAlign: 'center', fontFamily: MONO, fontSize: 28, color: C.dim, ...row(a(74, 100), 12)}}>github.com/Forichok/Agent-Notch</div>
    </AbsoluteFill>
  );
};

export const Promo: React.FC = () => (
  <AbsoluteFill style={{background: C.bg}}>
    <Sequence from={0} durationInFrames={612}>
      <Fade inF={1} outF={12} dur={612}><NotchStory cfg={cfg} /></Fade>
    </Sequence>
    <Sequence from={600} durationInFrames={192}>
      <Fade dur={192}><Directory /></Fade>
    </Sequence>
    <Sequence from={780} durationInFrames={180}>
      <Fade inF={14} outF={1} dur={180}><EndCard /></Fade>
    </Sequence>
  </AbsoluteFill>
);
