import React from 'react';
import {AbsoluteFill, Sequence, useCurrentFrame} from 'remotion';
import {range} from './lib';
import {Opening, openingLength} from './scenes/Opening';
import {Overview, OVERVIEW_LEN, Approvals, approvalsLength} from './scenes/Panels';
import {Trust, TRUST_LEN, End, END_LEN} from './scenes/Finale';

const X = 6; // crossfade frames
const Fade: React.FC<{dur: number; first?: boolean; children: React.ReactNode}> = ({dur, first, children}) => {
  const f = useCurrentFrame();
  return <AbsoluteFill style={{opacity: first ? 1 : range(f, 0, X, (t) => t)}}>{children}</AbsoluteFill>;
};
type Part = {C: React.FC; len: number};
const chain = (parts: Part[]) => {
  let at = 0;
  return parts.map((p, i) => {
    const from = at;
    at += p.len - X;
    return {...p, from, first: i === 0};
  });
};
const total = (parts: Part[]) => parts.reduce((s, p) => s + p.len, 0) - X * (parts.length - 1);

const H_PARTS: Part[] = [
  {C: Opening, len: openingLength(false)},
  {C: Overview, len: OVERVIEW_LEN},
  {C: Approvals, len: approvalsLength(false)},
  {C: Trust, len: TRUST_LEN},
  {C: End, len: END_LEN},
];
const V_END = 140;
const VEnd: React.FC = () => <End len={V_END} />;
const V_PARTS: Part[] = [
  {C: Opening, len: openingLength(true)},
  {C: Approvals, len: approvalsLength(true)},
  {C: VEnd, len: V_END},
];
export const PROMO_LEN = total(H_PARTS);
export const VERTICAL_LEN = total(V_PARTS);

const Chain: React.FC<{parts: Part[]}> = ({parts}) => (
  <AbsoluteFill style={{background: '#050507'}}>
    {chain(parts).map(({C, len, from, first}, i) => (
      <Sequence key={i} from={from} durationInFrames={len}>
        <Fade dur={len} first={first}><C /></Fade>
      </Sequence>
    ))}
  </AbsoluteFill>
);
export const Promo: React.FC = () => <Chain parts={H_PARTS} />;
export const Vertical: React.FC = () => <Chain parts={V_PARTS} />;
