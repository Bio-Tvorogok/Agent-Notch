import React from 'react';
import {AbsoluteFill} from 'remotion';
import {C, Glow, MONO, SANS, Mark} from './ui';
import {AGENTS, BAR_H, NOTCH_L, NOTCH_R, WING_L, markX} from './NotchStory';

export const Poster: React.FC = () => {
  const cx = (WING_L + NOTCH_R) / 2;
  return (
    <AbsoluteFill style={{background: C.bg}}>
      <div style={{transform: 'scale(0.667)', transformOrigin: '0 0', width: 1920, height: 960, position: 'absolute', left: 0, top: 0}}><Glow /></div>
      <div style={{position: 'absolute', left: 0, top: 0, width: 1280, height: 200, transformOrigin: `${cx}px 0`, transform: `translateX(${640 - cx}px) scale(1.5)`}}>
        <div style={{position: 'absolute', left: -600, right: -600, top: -4, height: BAR_H + 4, background: 'linear-gradient(#3c3c41,#303034)', WebkitMaskImage: 'linear-gradient(90deg, transparent, #000 30%, #000 70%, transparent)'}} />
        <svg width={1920} height={120} style={{position: 'absolute', left: 0, top: 0}}>
          <path d={`M ${WING_L + 22} ${BAR_H} Q ${WING_L} ${BAR_H} ${WING_L} ${BAR_H - 22} L ${WING_L} 0 L ${NOTCH_R} 0 L ${NOTCH_R} ${BAR_H - 22} Q ${NOTCH_R} ${BAR_H} ${NOTCH_R - 22} ${BAR_H} Z`} fill="#000" />
        </svg>
        {AGENTS.map((a, i) => {
          const size = a.sub ? 25 : 35;
          return <div key={i} style={{position: 'absolute', left: markX(i) - size / 2, top: BAR_H / 2 - size / 2 - 1}}><Mark vendor={a.vendor} state={i === 3 ? 'waiting' : i === 6 ? 'done' : 'working'} size={size} weight={a.weight} /></div>;
        })}
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 185, textAlign: 'center', fontFamily: SANS, fontWeight: 700, fontSize: 112, letterSpacing: -4, color: C.text}}>Agent Notch</div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 322, textAlign: 'center', fontFamily: SANS, fontWeight: 500, fontSize: 36, color: '#b4b4ba'}}>Claude Code &amp; Codex agents, in your MacBook notch</div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 430, display: 'flex', justifyContent: 'center'}}>
        <div style={{fontFamily: MONO, fontSize: 26, color: C.text, padding: '16px 32px', borderRadius: 999, background: 'rgba(255,255,255,0.07)', boxShadow: '0 0 0 1px rgba(255,255,255,0.16) inset', display: 'flex', gap: 12}}>
          <span style={{color: C.dim}}>$</span><span>brew install --cask forichok/tap/agent-notch</span>
        </div>
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 534, textAlign: 'center', fontFamily: SANS, fontWeight: 600, fontSize: 26, color: C.dim}}>Free · Open source · 100% local</div>
    </AbsoluteFill>
  );
};
