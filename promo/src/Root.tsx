import React from 'react';
import {Composition, Still} from 'remotion';
import {Promo, Vertical, PROMO_LEN, VERTICAL_LEN} from './Promo';
import {Hero, HERO_LEN} from './Hero';
import {Poster} from './Poster';

export const Root: React.FC = () => (
  <>
    <Composition id="Promo" component={Promo} durationInFrames={PROMO_LEN} fps={30} width={1920} height={1080} />
    <Composition id="Vertical" component={Vertical} durationInFrames={VERTICAL_LEN} fps={30} width={1080} height={1920} />
    <Composition id="Hero" component={Hero} durationInFrames={HERO_LEN} fps={30} width={1920} height={1080} />
    <Still id="Poster" component={Poster} width={1280} height={640} />
  </>
);
