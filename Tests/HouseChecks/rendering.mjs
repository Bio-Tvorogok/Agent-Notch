import assert from 'node:assert/strict';
import {scene,fixture} from './scene.mjs';
const s=scene();fixture(s);s.frame(10100);
// A paint loop must not serialize thousands of individual drawing commands.
// CPU acceptance is measured separately in a real WKWebView, not by canvas call counts.
s.run('let serializations=0;const stringify=JSON.stringify;JSON.stringify=(...a)=>{serializations++;return stringify(...a);};');
s.frame(10200);
assert.ok(s.run('serializations')<16,`frame serialized ${s.run('serializations')} values`);
assert.ok(s.run('[...sprites.values()].filter(sp=>sp.kind==="agent").every(sp=>sp.hit && sp.hit[2]>0 && sp.hit[3]>0)'),'paint preserves agent hit regions');
assert.deepEqual(s.errors,[]);
console.log('OK house renders without command serialization and preserves hit regions');
