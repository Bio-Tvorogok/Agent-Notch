import React from 'react';
import {Composition, Still} from 'remotion';
import {Promo} from './Promo';
import {Hero} from './Hero';
import {Poster} from './Poster';

export const Root: React.FC = () => (
  <>
    <Composition id="Promo" component={Promo} durationInFrames={782} fps={30} width={1920} height={1080} />
    <Composition id="Hero" component={Hero} durationInFrames={300} fps={30} width={1920} height={1080} />
    <Still id="Poster" component={Poster} width={1280} height={640} />
  </>
);
