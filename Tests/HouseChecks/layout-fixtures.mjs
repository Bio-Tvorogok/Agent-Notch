import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { scene } from './scene.mjs';

// Stage 1a plan: extract fresh JS geometry, compare every field in Swift, then
// regenerate twice and run scripts/test.sh. No simulation or renderer changes.
// scene() seeds Math.random (173). Layout itself must never consume it: the
// trap below covers ensureRoom/projectTheme/layout/liftPlan/islandPlan/applyView,
// yard geometry, escape() and drawOrder(). No seeded RNG is needed in Swift.
// References are room keys, absent JS fields stay absent, and Infinity in the
// final liftSlice is JSON null (an unbounded upper clipping plane).
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
process.chdir(root);
const dir = 'Tests/Fixtures/house-layout';
const check = process.argv.includes('--check');
if (!check) fs.mkdirSync(dir, { recursive: true });
let count = 0, bytes = 0;
for (const n of [0, 1, 2, 3, 5, 8, 14]) for (const layout of ['islands', 'towers', 'steps'])
for (const [width, height] of [[1440, 900], [1728, 1117]]) for (const insets of [{top:38,bottom:73,right:120}, {top:0,bottom:0,right:0}]) {
  const s = scene(); // no browser (and therefore no audio)
  s.run(`active=false; looping=false; demo=false; sprites.clear();
    innerWidth=${width}; innerHeight=${height}; devicePixelRatio=2;
    LAYOUT=${JSON.stringify(layout)}; INSETS=${JSON.stringify(insets)};
    Math.random=()=>{throw new Error('layout consumed Math.random');};
    for (const p of DEMO_PROJECTS.slice(0,${n})) ensureRoom('p:'+p,p);
    LIFT=null; links=[]; PLAN={hulls:[]}; layout();`);
  const output = s.run(`(() => {
    const roomGeometry = r => ({key:r.key,name:r.name,theme:THEME_KEY.get(r.theme)||'yard',NX:r.NX,NY:r.NY,
      tower:r.tower,floor:r.floor,tx:r.tx,ty:r.ty,tz:r.tz,ox:r.ox,oy:r.oy,drop:r.drop,wx:r.wx,wy:r.wy});
    const linkGeometry = L => {const o={};for(const k of ['kind','id','axis','A','B','z','len','ang','rise','steps','z0','pa','pb'])
      if(k in L)o[k]=L[k];for(const k of ['a','b','lo','hi'])if(L[k])o[k]=L[k].key;
      if(L.targets)o.targets=L.targets.map(t=>t.room?{room:t.room.key}:{up:t.up});return o;};
    const escapeShapes={}, escapes=[];
    // Capture the real drawing function's geometry, without rasterization, in
    // local art pixels for lines/polygons and tile units for B (boxes).
    const save={B,line,poly,R};
    for(const r of rooms){
      const above=roomAt(r.tower,r.floor+1), layers=[];
      if(above&&!LIFT)layers.push('back','front');
      if(LIFT?r.key==='__bath':!above&&r.floor>0)layers.push('top');
      for(const layer of layers){const shape=r.NY+':'+layer;escapes.push({room:r.key,layer,shape});
        if(escapeShapes[shape])continue;
        const ops=[];B=(...a)=>ops.push({kind:'box',points:[a.slice(0,6)]});
        line=(a,b)=>ops.push({kind:'line',points:[a,b]});poly=p=>ops.push({kind:'polygon',points:p});
        R={ox:0,oy:0,drop:0};escape(r,layer);escapeShapes[shape]=ops;}
    }
    ({B,line,poly,R}=save);
    return {rooms:rooms.map(roomGeometry),lift:LIFT?{
      fl:LIFT.fl.map((q,k)=>({room:q.r.key,f:q.f,yoff:q.yoff,z:q.z,levelZ:liftZ(k),slice:liftSlice(k)})),
      shafts:LIFT.shafts,cabins:LIFT.cabins.map(c=>({kind:c.kind,id:c.id,sh:c.sh,z:c.z,level:c.level,len:c.len})),
      x0:LIFT.x0,x1:LIFT.x1,y0:LIFT.y0,y1:LIFT.y1,top:LIFT.top}:null,
      links:links.map(linkGeometry),hulls:PLAN.hulls,
      yard:{on:yardOn(),room:roomGeometry(YARD),YD,YW,YUP,YGATE,ports:Object.fromEntries(Object.entries(YARD_PORTS).map(([k,v])=>[k,v()])),
        ground:[-1.2,-1.2,-SLAB-14,YD.x1,shared('bath').NY+2,-SLAB],
        gates:{Yl:gateUsed('Yl'),Yr:gateUsed('Yr')}},
      escapes,escapeShapes,drawOrder:drawOrder().map(q=>({key:q.room?.key||q.link.id,...('depth'in q?{depth:q.depth}:{})})),
      view:{PXD,DPR,width:cv.width,height:cv.height,cssWidth:cv.width*PXD/DPR,cssHeight:cv.height*PXD/DPR,base:VIEW.base,home:VIEW.home,at:VIEW.at},
      worldFrame:worldFrame()};
  })()`);
  assert.deepEqual(s.errors, []);
  const fixture = {input:{projects:Array.from(s.run(`DEMO_PROJECTS.slice(0,${n})`)),layout,canvas:{width,height,dpr:2},insets},output};
  const json = JSON.stringify(fixture) + '\n';
  const name = `${String(n).padStart(2,'0')}-${layout}-${width}x${height}-${insets.top?'insets':'zero'}.json`;
  const file = path.join(dir,name);
  if (check) assert.equal(fs.readFileSync(file,'utf8'),json, `${name}: current JS geometry differs; regenerate fixtures`);
  else fs.writeFileSync(file,json);
  count++; bytes+=Buffer.byteLength(json);
}
assert.equal(count,84);
assert.ok(bytes<2_000_000, `fixtures too large: ${bytes}`);
console.log(`house-layout: ${count} fixtures, ${bytes} bytes; layout makes zero Math.random calls`);
