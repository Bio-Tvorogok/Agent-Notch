// Runs inside room/index.html loaded with ?scene=extra (export.swift, HOUSE_SCENE=extra, HOUSE_REF_ONLY=1) and records the page's OWN frame of an
// extra screen for the SpriteKit proof: sky, city and the three islets (no sun or moon, no house). window.__REF_FIXTURES = [hour, ...] is prepended by extra-proof.sh.
// Output: ref-x{hour}.png (the whole frame) and ref-x{hour}.json (canvas, PXD, DPR, insets, day).
(() => {
  'use strict';
  const O = window.__HOUSE_EXPORT, post = (path, data) => window.webkit.messageHandlers.out.postMessage({ path, data });
  if (SCENE !== 'extra') throw new Error('not the extra scene');
  const T = 100000;
  setActive(false);
  weather = 'clear';
  eggSky = () => {}; eggOver = () => {}; eggItems = () => {}; eggStep = () => {}; drawSeason = () => {};
  METEORS.next = Infinity; METEORS.list = [];
  const files = [], out = [];
  for (const hour of window.__REF_FIXTURES) {
    fixedHour = hour; frame(T);
    const d = now(), tag = 'x' + hour, day = Math.floor((d - new Date(d.getFullYear(), 0, 1)) / 864e5);
    const meta = { hour, W: cv.width, H: cv.height, PXD, DPR, insets: INSETS, day, mist: mistAmount(d), T, innerH: innerHeight, innerW: innerWidth, rooms: rooms.length };
    for (const [f, data] of [['.png', cv.toDataURL('image/png')], ['.json', JSON.stringify(meta)]]) { post('check/ref-' + tag + f, data); files.push('check/ref-' + tag + f); }
    out.push(tag);
  }
  return JSON.stringify({ files, summary: 'extra ref frames: ' + out.join(' ') });
})();
