import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
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

// Run with CANVAS_MODULE pointing to @napi-rs/canvas for pixel checks as well as the DOM checks above.
if (process.env.CANVAS_MODULE) {
  const {createCanvas}=createRequire(import.meta.url)(process.env.CANVAS_MODULE);
  const raster=scene(undefined,undefined,createCanvas);fixture(raster);
  raster.run(`const probe=[...sprites.values()].find(sp=>sp.vendor==='claude');
    g=main;main.clearRect(0,0,cv.width,cv.height);setTime(5);drawClawd(100,100,probe,11000);
    main.clearRect(0,0,cv.width,cv.height);setTime(5.0216667);drawClawd(100,100,probe,11000);`);
  const pixel=raster.ctx.document.getElementById('c').getContext('2d').getImageData(92,86,1,1).data;
  assert.deepEqual([...pixel],[80,43,48,255],'a warm body cache follows dawn light within a quantized light key');
  assert.deepEqual(raster.errors,[]);
  console.log('OK warm body cache follows dawn lighting');
}
