import assert from 'node:assert/strict';
import {scene,fixture} from './scene.mjs';
const s=scene();fixture(s);s.frame(10100);s.count();s.frame(10100);
assert.equal(s.calls.main,0,'identical retained frame does not submit paint');
s.count();for(let i=1;i<=100;i++)s.frame(10100+i*100);
assert.ok(s.calls.main/10<18000,`working submissions bounded: ${s.calls.main/10}/s`);
assert.deepEqual(s.errors,[]);console.log(JSON.stringify({check:'retained house',calls:s.calls}));
