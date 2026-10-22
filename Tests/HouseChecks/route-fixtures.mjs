import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { scene } from './scene.mjs';

// Stage 2a: execute the unmodified page, without its renderer or decision loops.
// Nodes are interned losslessly; route arrays index `nodes`, not rounded geometry.
// Trace rows use the schemas below to keep four 60-second runs under 3 MB.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
process.chdir(root);
const dir = 'Tests/Fixtures/house-routes', check = process.argv.includes('--check');
if (!check) fs.mkdirSync(dir, {recursive:true});
let count=0, bytes=0, routeCount=0;
// 'frames' runs one trace the way the page does: irregular frame deltas, a negative
// first one and a 4 s stall (see frameDeltas); the others step a fixed 50 ms.
for (const [n,style,mode] of [[2,'islands'],[5,'islands'],[14,'islands'],[5,'towers'],[5,'islands','frames']]) {
 const frames=mode==='frames';
 const s=scene();
 s.run(`active=false;looping=false;demo=false;sprites.clear();LAYOUT=${JSON.stringify(style)};
  for(const p of DEMO_PROJECTS.slice(0,${n}))ensureRoom('p:'+p,p);
  LIFT=null;links=[];PLAN={hulls:[]};layout();
  globalThis.routeTime=0;performance.now=()=>routeTime;
  globalThis.routeSeed=173;Math.random=()=>{routeSeed=(Math.imul(routeSeed,1664525)+1013904223)>>>0;return routeSeed/4294967296;};
  globalThis.nodeJSON=n=>{const o={};for(const k of ['r','p','bridge','to','from','call','aim','side','lift','jump','poof','wait','until','since','cab'])
    if(k in n)o[k]=['r','bridge','call','cab'].includes(k)?(n[k].key||n[k].id):n[k];return o;};
  globalThis.getRoom=k=>k==='__yard'?YARD:roomByKey.get(k);
  globalThis.makeNode=o=>Object.fromEntries(Object.entries(o).map(([k,v])=>[k,k==='r'?getRoom(v):['bridge','call','cab'].includes(k)?[...links,...(LIFT?.cabins||[])].find(l=>l.id===v):v]));`);
 const projects=Array.from(s.run(`DEMO_PROJECTS.slice(0,${n})`));
 const geometry=s.run(`({rooms:rooms.map(r=>r.key),stairs:links.filter(l=>l.kind==='stair').map(l=>({id:l.id,a:l.a.key,b:l.b.key,q:l.pa.q,qb:l.pb.q})),bridges:links.filter(l=>l.kind!=='stair').map(l=>({id:l.id,a:l.a.key,b:l.b.key,q:l.pa.q,qb:l.pb.q})), first:rooms.find(r=>r.tower>0)?.key})`);
 const output=frames?{catalog:{},origins:[],nodes:[],routes:[]}:s.run(`(()=>{
  const catalog=Object.fromEntries([...Object.entries(THEMES),['yard',YARD_THEME]].map(([k,t])=>[k,{hub:t.hub,spots:t.spots}]));
  const origins=[];for(const r of [...rooms,YARD]){origins.push({room:r.key,p:r.theme.hub,tag:'hub'});
   for(const [cat,list]of Object.entries(r.theme.spots))list.forEach((p,i)=>origins.push({room:r.key,p,tag:cat+':'+i}));}
  const nodes=[],intern=new Map(),routes=[];
  const nodeIndex=n=>{const o=nodeJSON(n),k=JSON.stringify(o);if(!intern.has(k)){intern.set(k,nodes.length);nodes.push(o);}return intern.get(k);};
  for(let i=0;i<origins.length;i++){
   const a=origins[i],other=rooms[(rooms.findIndex(r=>r.key===a.room)+1)%rooms.length];
   const targets=['__yard','__roof','__kitchen',other.key];
   for(const key of [...new Set(targets)]){const j=origins.findIndex(o=>o.room===key&&o.tag!=='hub');const b=origins[j];
    const sp={id:'route',room:getRoom(a.room),homeRoom:getRoom(a.room),x:a.p[0],y:a.p[1],z:a.p[2],path:[],seed:.371};
    routeTo(sp,getRoom(b.room),b.p);routes.push([i,j,sp.path.map(nodeIndex)]);
   }
  }
  return {catalog,origins,nodes,routes};})()`);
 const setup=[],events=[],stairInit=[];
 const add=(id,room,options={},goal=null,path=null)=>setup.push({id,room,options,...(goal?{goal}:{}),...(path?{path}:{})});
 const goal=(room,p)=>({room,p,cat:'fixture',i:-1});
 // Real spawn (including the floor-below rule), small agents, drowsiness and speed.
 add('spawn😀','__roof',{kind:'agent',small:true},goal('__kitchen',[.8,2.6,6.6]));
 add('resident','__roof',{kind:'home'},goal('__bath',[3.3,1.75,0]));
 add('walker',geometry.first,{kind:'agent',context:.95,speed:1.3},goal('__roof',[3,2.2,4.4]));
 add('yard','__yard',{kind:'agent'},goal(geometry.first,[5,3,0]));
 add('jumper','__bath',{kind:'agent',x:2,y:5.9,alpha:1,exit:true});
 add('fade','__bath',{kind:'agent',alpha:1,fade:0,leaving:true});
 add('frozen','__kitchen',{kind:'home',frozenUntil:1250},goal('__bath',[3.3,1.75,0]));
 if(style==='islands') {
  // Seven simultaneous calls exceed both cages' combined capacity.
  for(let i=0;i<7;i++)add('queue'+i,'__yard',{kind:'agent',x:10.6+i*.1,y:.8},goal(i%2?'__roof':'__kitchen',i%2?[5,2.2,4.4]:[.8,2.6,6.6]));
 } else {
  add('escape-up','__bath',{kind:'home'},goal('__roof',[7,2.2,4.4]));
  add('escape-down','__roof',{kind:'home'},goal('__bath',[3.3,1.75,0]));
  // Disconnected stacks must poof to the destination hub.
  add('disconnected',geometry.first,{kind:'home'},goal('__kitchen',[6.8,5.6,11.6]));
 }
 if(geometry.stairs.length) {
  const l=geometry.stairs[0];
  add('stair-up',l.a,{kind:'home',x:l.q[0],y:l.q[1],z:-6},goal(l.b,[5,3,0]));
  add('stair-down',l.b,{kind:'home',small:true},goal(l.a,[8,2.3,6.6]));
  add('stair-sit',l.a,{kind:'home',x:l.q[0],y:l.q[1],z:-6},null,
   [{call:l.id,aim:0,side:'lo'},{bridge:l.id,to:.35},{wait:900},{bridge:l.id,to:0},{r:l.a,p:[...l.q,-6],jump:true}]);
  events.push({at:3500,id:'stair-sit',goal:goal('__bath',[3.3,1.75,0])});
 }
 events.push({at:3000,id:'yard',goal:goal('__kitchen',[4.8,5.6,11.6])},
  {at:8000,id:'spawn😀',goal:goal('__yard',[15.55,6.95,0])},
  {at:18000,id:'walker',goal:goal(geometry.first,[8,2.3,6.6])},
  {at:32000,id:'resident',goal:goal('__yard',[10.7,7.05,4.5])},
  {at:44000,id:'yard',goal:goal('__roof',[7,2.2,4.4])});
 // The frame after a crossing or a lift exit has no room and no bridge (the jump node
 // has not run yet): a goal set exactly then used to crash both ports. `when` holds an
 // event until the sprite is in that state (limbo / on a lift / on a bridge or stair),
 // from `at` on, so the fixture pins the tick as well as the path.
 if(style==='islands') {
  const l=geometry.bridges[0];
  add('limbo-bridge',l.a,{kind:'home',x:l.q[0],y:l.q[1],z:-6},goal(l.b,[5,3,0]));
  events.push({at:500,id:'limbo-bridge',when:'limbo',goal:goal('__kitchen',[.8,2.6,6.6])});
  add('mid-bridge',l.b,{kind:'home',x:l.qb[0],y:l.qb[1],z:-6},goal(l.a,[5,3,0]));
  events.push({at:500,id:'mid-bridge',when:'bridge',goal:goal(l.b,[3,2.2,0])});
  add('limbo-lift','__kitchen',{kind:'home'},goal('__yard',[15.55,6.95,0]));
  events.push({at:500,id:'limbo-lift',when:'limbo',goal:goal('__roof',[5,2.2,4.4])});
  add('ride-reroute','__bath',{kind:'home'},goal('__roof',[7,2.2,4.4]));
  events.push({at:500,id:'ride-reroute',when:'lift',goal:goal('__kitchen',[.8,2.6,6.6])});
 }
 // A raised first node is kept by a reroute; a jump node is not. Only a hand-built
 // path puts a jump with a raised z in the sprite's own room.
 add('keep-raised',geometry.first,{kind:'home'},null,[{r:geometry.first,p:[3,3,47]},{r:geometry.first,p:[6,5,0]}]);
 add('drop-jump',geometry.first,{kind:'home'},null,[{r:geometry.first,p:[3,3,47],jump:true},{r:geometry.first,p:[6,5,0]}]);
 events.push({at:50,id:'keep-raised',goal:goal('__kitchen',[.8,2.6,6.6])},{at:50,id:'drop-jump',goal:goal('__roof',[7,2.2,4.4])});
 // A route planned while a stair is raised crosses it (a call node, wave it down): the
 // raise fraction is not a lift trip. Two callers wanting different ends of a stair
 // that is neither up nor down: the one waiting longest decides.
 if(geometry.stairs[1]) {
  const m=geometry.stairs[1];
  stairInit.push({id:m.id,aim:1,lift:1,next:1e9});
  add('raised-walker',m.a,{kind:'home',x:m.q[0],y:m.q[1],z:-6},goal(m.b,[5,3,0]));
  events.push({at:50,id:'raised-late',spawn:{room:m.b,options:{kind:'home',x:m.qb[0],y:m.qb[1],z:-6}},goal:goal(m.a,[8,2.3,6.6])});
 }
 if(geometry.stairs[2]) {
  const o=geometry.stairs[2];
  stairInit.push({id:o.id,aim:-1,lift:1,next:1e9});
  add('caller-new',o.a,{kind:'home',x:o.q[0],y:o.q[1],z:-6},null,[{call:o.id,aim:1,side:'lo',since:5000},{bridge:o.id,to:1},{r:o.b,p:[...o.qb,-6],jump:true}]);
  add('caller-old',o.b,{kind:'home',x:o.qb[0],y:o.qb[1],z:-6},null,[{call:o.id,aim:0,side:'hi',since:1000},{bridge:o.id,to:0},{r:o.a,p:[...o.q,-6],jump:true}]);
 }
 // Exercise the transit recovery branch without fabricating a navigation choice.
 events.push({at:1000,id:'orphan',spawn:{room:geometry.first,options:{kind:'home'}},orphan:true,goal:goal('__bath',[3.3,1.75,0])});
 // Frame deltas as the page's rAF delivers them: the first stamp can precede wake()'s
 // (negative), most are ~60 fps, some late, and one 4 s stall.
 const deltas=[-30];
 if(frames) {
  const menu=[16.7,16.6,16.7,33.4,16.7,8.3,50,49.9,50.1,120,16.7,16.7,250,16.7,700,1500,1501,0,3.2,16.7,16.7,16.7];
  let lcg=12345,clock=0;
  while(clock<60000){lcg=(Math.imul(lcg,1664525)+1013904223)>>>0;let d=menu[lcg%menu.length];if(deltas.length===150)d=4000;deltas.push(d);clock+=d;}
 }
 // A one-frame state can slip between two long frames: the limbo goals belong to the 50 ms traces.
 if(frames)events.splice(0,events.length,...events.filter(e=>e.when!=='limbo'));
 const sim={setup,events,stairInit,dt:50,duration:60000,sample:250,seed:173,...(frames?{frames:{deltas,sample:5}}:{})};
 s.ctx.routeSetup=setup;s.ctx.routeEvents=events;s.ctx.stairInit=stairInit;s.ctx.frameDeltas=deltas;s.ctx.frameMode=frames;
 s.run(`for(const si of stairInit){const L=links.find(l=>l.id===si.id);for(const k of ['aim','lift','next'])if(k in si)L[k]=si[k];}
  globalThis.applyGoal=(sp,g)=>setGoal(sp,{...g,room:getRoom(g.room)});
  globalThis.addSprite=o=>{const v={...o.options};delete v.context;delete v.frozenUntil;
    const sp=spawn(o.id,getRoom(o.room),v);if('context'in o.options)sp.agent={context:o.options.context};
    if(o.options.frozenUntil)sp.hi5={until:o.options.frozenUntil};
    if(o.path)sp.path=o.path.map(makeNode);if(o.goal)applyGoal(sp,o.goal);return sp;};
  routeSetup.forEach(addSprite);
  globalThis.sampleRoutes=()=>({clock:routeTime,
   sprites:[...sprites.values()].map(sp=>[sp.id,sp.room?.key??null,sp.x,sp.y,sp.z,sp.alpha,sp.fade,sp.moving,sp.seated??null,sp.waving??null,sp.state??null,sp.path.length,
    sp.onBridge?[sp.onBridge.pair.kind,sp.onBridge.pair.id,sp.onBridge.u,sp.onBridge.forward??null]:null,
    sp.path[0]?.lift?[sp.path[0].lift.from,sp.path[0].lift.to,sp.path[0].since??null,sp.path[0].cab?.id??null]:null,
    sp.fall?[sp.fall.x,sp.fall.y,sp.fall.t0,sp.fall.seed]:null]),
   cabins:(LIFT?.cabins||[]).map(c=>[c.id,c.z,c.level,c.state,c.t,c.stop]),
   stairs:links.filter(l=>l.kind==='stair').map(l=>[l.id,l.ang,l.lift,l.aim,l.turn?[l.turn.a0,l.turn.a1,l.turn.to,l.turn.t0,l.turn.ms]:null,l.next,l.since??null]),rng:routeSeed});
  globalThis.snapshots=[[0,sampleRoutes()]];globalThis.eventPaths=[];globalThis.firedEvents=new Set();
  // An event fires on the first tick or frame whose clock has reached its time (and, with
  // \`when\`, the sprite its state); the fixture records that clock with the path.
  globalThis.ready=(e,sp)=>e.when==='limbo'?(!sp.room&&!sp.onBridge):e.when==='lift'?sp.onBridge?.pair.kind==='lift':e.when==='bridge'?(!!sp.onBridge&&sp.onBridge.pair.kind!=='lift'):true;
  globalThis.fire=clock=>{for(const e of routeEvents){
    if(firedEvents.has(e)||e.at>clock)continue;
    let sp=sprites.get(e.id);if(!e.spawn&&!sp)continue;if(e.when&&!ready(e,sp))continue;
    firedEvents.add(e);if(e.spawn)sp=addSprite({id:e.id,...e.spawn});
    if(e.orphan){sp.onBridge={pair:links[0]||(LIFT?.cabins[0])||{kind:'bridge',id:'orphan'},u:.5};sp.room=null;sp.path=[];}
    if(e.goal)applyGoal(sp,e.goal);eventPaths.push([clock,e.id,sp.path.map(nodeJSON)]);}};
  if(!frameMode)for(routeTime=50;routeTime<=60000;routeTime+=50){
   fire(routeTime);
   stepSprites(50);updateLifts(routeTime,50);updateStairs(routeTime);
   if(routeTime%250===0)snapshots.push([routeTime,sampleRoutes()]);
  }
  else {
   // frame() of the page: the clock follows the stamps, motion is clamped to [0, 1500] ms and cut into
   // 50 ms substeps (sprites, then lifts at the substep's end), stairs once per frame.
   let clock=0;
   frameDeltas.forEach((raw,i)=>{
    clock+=Math.max(0,raw);routeTime=clock;fire(clock);
    const dt=Math.min(1500,Math.max(0,raw));
    for(let left=dt;left>0;){const step=Math.min(50,left);left-=step;stepSprites(step);updateLifts(clock-left,step);}
    updateStairs(clock);
    if(i%${5}===${5}-1)snapshots.push([i,sampleRoutes()]);
   });
  }`);
 output.trace=s.run('snapshots');output.eventPaths=s.run('eventPaths');
 // Every event must fire, or the fixture pins nothing.
 assert.equal(output.eventPaths.length,events.length,`${n}-${style}${frames?'-frames':''}: events that never fired: ${events.filter(e=>!output.eventPaths.some(p=>p[1]===e.id)).map(e=>e.id)}`);
 assert.deepEqual(s.errors,[]);
 const fixture={input:{projects,layout:style,sim},schema:{sprite:['id','room','x','y','z','alpha','fade','moving','seated','waving','state','pathCount','onBridge(kind,id,u,forward)','lift(from,to,since,cab)','fall(x,y,t0,seed)'],cabin:['id','z','level','state','t','stop'],stair:['id','ang','lift','aim','turn(a0,a1,to,t0,ms)','next','since']},output};
 const json=JSON.stringify(fixture)+'\n',name=`${String(n).padStart(2,'0')}-${style}${frames?'-frames':''}.json`,file=path.join(dir,name);
 if(check)assert.equal(fs.readFileSync(file,'utf8'),json,`${name}: JS routes/traces changed`);else fs.writeFileSync(file,json);
 count++;bytes+=Buffer.byteLength(json);routeCount+=output.routes.length;
}
assert.ok(bytes<3_000_000,`fixtures too large: ${bytes}`);
console.log(`house-routes: ${count} fixtures, ${routeCount} routes, ${bytes} bytes`);
