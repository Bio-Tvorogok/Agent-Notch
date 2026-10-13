import React from 'react';
import {AbsoluteFill} from 'remotion';
import {C, MONO, SANS} from './lib';
import {HEAVY_WING, Laptop, Panel, World} from './world';

export const Poster: React.FC = () => (
  <AbsoluteFill style={{background: C.bg}}>
    <World cam={{s: 0.78, fx: 780, fy: 0, ax: 950, ay: 46}}>
      <Laptop clock="Tue 14:25" calm={1} glow={0.5} wing={{items: HEAVY_WING}} over={<Panel layers={[{shot: 'heavy', o: 1}]} reveal={1} />} />
    </World>
    <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 200, background: 'linear-gradient(transparent, #050507)'}} />
    <div style={{position: 'absolute', left: 0, top: 0, bottom: 0, width: 700, background: 'linear-gradient(90deg, #050507 78%, transparent)'}} />
    <div style={{position: 'absolute', left: 64, top: 170, fontFamily: SANS, fontWeight: 700, fontSize: 92, letterSpacing: -3.6, color: C.text}}>Agent Notch</div>
    <div style={{position: 'absolute', left: 66, top: 290, width: 520, fontFamily: SANS, fontWeight: 500, fontSize: 31, lineHeight: 1.3, color: '#b4b4ba'}}>
      Every Claude Code &amp; Codex agent, in your MacBook notch.
    </div>
    <div style={{position: 'absolute', left: 64, top: 410, fontFamily: MONO, fontSize: 19, color: C.text, padding: '13px 22px', borderRadius: 999, background: 'rgba(255,255,255,0.07)',
      boxShadow: '0 0 0 1px rgba(255,255,255,0.16) inset', display: 'flex', gap: 10, whiteSpace: 'pre'}}>
      <span style={{color: C.green}}>$</span><span>brew install --cask forichok/tap/agent-notch</span>
    </div>
    <div style={{position: 'absolute', left: 66, top: 500, fontFamily: SANS, fontWeight: 600, fontSize: 24, color: C.text}}>
      Free <span style={{color: C.dim}}>·</span> Open source <span style={{color: C.dim}}>·</span> 100% local
    </div>
  </AbsoluteFill>
);
