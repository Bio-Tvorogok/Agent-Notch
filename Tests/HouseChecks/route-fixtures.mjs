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
for (const [n,style] of [[2,'islands'],[5,'islands'],[14,'islands'],[5,'towers']]) {
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
 const geometry=s.run(`({rooms:rooms.map(r=>r.key),stairs:links.filter(l=>l.kind==='stair').map(l=>({id:l.id,a:l.a.key,b:l.b.key,q:l.pa.q})), first:rooms.find(r=>r.tower>0)?.key})`);
 const output=s.run(`(()=>{
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
 const setup=[],events=[];
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
 // Exercise the transit recovery branch without fabricating a navigation choice.
 events.push({at:1000,id:'orphan',spawn:{room:geometry.first,options:{kind:'home'}},orphan:true,goal:goal('__bath',[3.3,1.75,0])});
 const sim={setup,events,dt:50,duration:60000,sample:250,seed:173};
 s.ctx.routeSetup=setup;s.ctx.routeEvents=events;
 s.run(`globalThis.applyGoal=(sp,g)=>setGoal(sp,{...g,room:getRoom(g.room)});
  globalThis.addSprite=o=>{const v={...o.options};delete v.context;delete v.frozenUntil;
    const sp=spawn(o.id,getRoom(o.room),v);if('context'in o.options)sp.agent={context:o.options.context};
    if(o.options.frozenUntil)sp.hi5={until:o.options.frozenUntil};
    if(o.path)sp.path=o.path.map(makeNode);if(o.goal)applyGoal(sp,o.goal);return sp;};
  routeSetup.forEach(addSprite);
  globalThis.sampleRoutes=()=>({
   sprites:[...sprites.values()].map(sp=>[sp.id,sp.room?.key??null,sp.x,sp.y,sp.z,sp.alpha,sp.fade,sp.moving,sp.seated??null,sp.waving??null,sp.state??null,sp.path.length,
    sp.onBridge?[sp.onBridge.pair.kind,sp.onBridge.pair.id,sp.onBridge.u,sp.onBridge.forward??null]:null,
    sp.path[0]?.lift?[sp.path[0].lift.from,sp.path[0].lift.to,sp.path[0].since??null,sp.path[0].cab?.id??null]:null,
    sp.fall?[sp.fall.x,sp.fall.y,sp.fall.t0,sp.fall.seed]:null]),
   cabins:(LIFT?.cabins||[]).map(c=>[c.id,c.z,c.level,c.state,c.t,c.stop]),
   stairs:links.filter(l=>l.kind==='stair').map(l=>[l.id,l.ang,l.lift,l.aim,l.turn?[l.turn.a0,l.turn.a1,l.turn.to,l.turn.t0,l.turn.ms]:null,l.next,l.since??null]),rng:routeSeed});
  globalThis.snapshots=[[0,sampleRoutes()]];globalThis.eventPaths=[];
  for(routeTime=50;routeTime<=60000;routeTime+=50){
   for(const e of routeEvents.filter(e=>e.at===routeTime)){
    let sp=sprites.get(e.id);if(e.spawn)sp=addSprite({id:e.id,...e.spawn});
    if(e.orphan){sp.onBridge={pair:links[0]||(LIFT?.cabins[0])||{kind:'bridge',id:'orphan'},u:.5};sp.room=null;sp.path=[];}
    if(e.goal)applyGoal(sp,e.goal);eventPaths.push([routeTime,e.id,sp.path.map(nodeJSON)]);
   }
   stepSprites(50);updateLifts(routeTime,50);updateStairs(routeTime);
   if(routeTime%250===0)snapshots.push([routeTime,sampleRoutes()]);
  }`);
 output.trace=s.run('snapshots');output.eventPaths=s.run('eventPaths');
 assert.deepEqual(s.errors,[]);
 const fixture={input:{projects,layout:style,sim},schema:{sprite:['id','room','x','y','z','alpha','fade','moving','seated','waving','state','pathCount','onBridge(kind,id,u,forward)','lift(from,to,since,cab)','fall(x,y,t0,seed)'],cabin:['id','z','level','state','t','stop'],stair:['id','ang','lift','aim','turn(a0,a1,to,t0,ms)','next','since']},output};
 const json=JSON.stringify(fixture)+'\n',name=`${String(n).padStart(2,'0')}-${style}.json`,file=path.join(dir,name);
 if(check)assert.equal(fs.readFileSync(file,'utf8'),json,`${name}: JS routes/traces changed`);else fs.writeFileSync(file,json);
 count++;bytes+=Buffer.byteLength(json);routeCount+=output.routes.length;
}
assert.ok(bytes<3_000_000,`fixtures too large: ${bytes}`);
console.log(`house-routes: ${count} fixtures, ${routeCount} routes, ${bytes} bytes`);
