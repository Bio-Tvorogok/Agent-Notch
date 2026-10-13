import React from 'react';
import {Cfg, NotchStory, markX} from './NotchStory';
import {C, MONO} from './ui';

const m3 = markX(3);
const Cmd: React.FC<{children: React.ReactNode}> = ({children}) => (
  <span style={{fontFamily: MONO, fontWeight: 600, color: C.red, background: 'rgba(255,69,58,0.12)', padding: '0 22px', borderRadius: 18, fontSize: '0.86em'}}>{children}</span>
);
const cfg: Cfg = {
  wingIn: 4, popStart: 20, popGap: 9, yellow: 112,
  panelOpen: 164, keysIn: 186, cursorIn: 194, click: 226, panelClose: 250, green: 256,
  cam: {f: [0, 100, 122, 142, 164], s: [2.2, 2.0, 2.8, 2.8, 1.0], fx: [795, 795, m3, m3, 960], cy: [400, 400, 400, 400, 29]},
  captions: [
    {from: 14, to: 104, y: 640, size: 84, node: <>7 agents. One glance.</>},
    {from: 118, to: 166, y: 640, size: 80, node: <>Codex wants to run <Cmd>rm -rf</Cmd></>},
    {from: 176, to: 270, y: 880, size: 72, node: <>Approve from the notch.</>},
  ],
  fadeEnds: true,
};
export const Hero: React.FC = () => <NotchStory cfg={cfg} />;
