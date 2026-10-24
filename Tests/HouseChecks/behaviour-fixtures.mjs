import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {scene} from './scene.mjs';

process.chdir(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..'));
const dir=process.env.BEH_DIR||'Tests/Fixtures/house-behaviour', check=process.argv.includes('--check');
if(!check)fs.mkdirSync(dir,{recursive:true});
const row=(id,project='alpha',state='working',extra={})=>({id,project,state,vendor:'claude',title:'Agent '+id,...extra});
const cases=[];
for(const n of [1,3,6,14]) {
 const rows=Array.from({length:n},(_,i)=>row('a'+i,'project-'+i,'idle',{vendor:i%2?'codex':'claude',activity:'Read · Model.swift',context:i===2?.95:.2}));
 const events=[{at:0,rows}, {at:1000,rows:rows.map(r=>({...r,state:'working'}))},
  {at:5000,rows:rows.map(r=>({...r,state:'waiting'}))},
  {at:10000,rows:rows.map(r=>({...r,state:'done'}))},
  {at:45000,rows:rows.map(r=>({...r,state:'working',activity:'WebFetch · docs'}))},
  {at:47000,rows:rows.slice(1).map(r=>({...r,state:'error'}))}, {at:49000,rows:[]}];
 cases.push({name:`${String(n).padStart(2,'0')}-projects`,seed:173,duration:n===14?55000:65000,events});
}
// Crowding includes seat/cowork overflow, spot jitter, all activity categories,
// shower contention, full wash/dry/towel chain and stable repeat deliveries.
const crowd=Array.from({length:14},(_,i)=>row('c'+i,'crowd','working',{activity:'Bash · build'}));
cases.push({name:'crowding-bath',seed:173,duration:95000,events:[{at:0,rows:crowd},
 {at:15000,rows:crowd.map(r=>({...r,state:'done'}))},
 {at:16000,rows:crowd.map(r=>({...r,state:'done'}))},
 {at:90000,rows:crowd.map((r,i)=>({...r,state:'working',activity:['Grep','Search','Task','Agent','LS'][i%5]}))}]});
const parent=row('parent','family'), child=(id,extra={})=>row(id,'family','working',{parentId:'parent',...extra});
cases.push({name:'subagents-return',seed:173,duration:65000,events:[{at:0,rows:[parent]},
 {at:3000,rows:[parent,child('child'),child('second')]},
 {at:7000,rows:[parent,child('child',{state:'done'}),child('second')]},
 {at:9000,rows:[parent,child('child',{state:'done'})]},
 {at:12000,rows:[parent]}, {at:16000,rows:[parent,child('child')]},
 {at:17000,rows:[parent,child('child',{state:'done'})]},
 {at:17500,rows:[parent,child('child')]},
 {at:20000,rows:[parent,child('orphan',{parentId:'absent'})]},
 {at:22000,rows:[parent]}, {at:30000,rows:[]},
 {at:36000,rows:[parent]}, {at:39000,rows:[]}]});
// Reappearance while fading, walking out, and falling; new rooms during transit.
cases.push({name:'churn-growth',seed:173,duration:55000,events:[{at:0,rows:[row('fast','')]},
 {at:50,rows:[]},{at:100,rows:[row('fast','')]},
 {at:2000,rows:[row('fast',''),row('new','beta')]},
 {at:4000,rows:[row('fast',''),row('new','beta'),row('third','gamma')]},
 {at:7000,rows:[row('new','beta')]}, {at:7500,rows:[row('fast',''),row('new','beta')]},
 {at:9000,rows:[]}, {at:18000,rows:[row('new','beta')]},
 {at:25000,rows:[]}, {at:28500,rows:[row('new','beta')]},
 {at:30000,rows:[]}]});
cases.push({name:'growth-ring',seed:173,duration:8500,events:[
 ...Array.from({length:152},(_,i)=>({at:i*50,rows:[row('g'+i,'growth','working',{vendor:'unknown',activity:i%2?'Glob · *':'Bash',model:'model',ask:'question',context:.95})]})),
 {at:7600,rows:[row('g1','growth')]},{at:7650,rows:[row('g150','growth')]},{at:8000,rows:[]}]});
// Layout changes in transit (`inject` spawns before the tick's rows). The lift's floors are numbered from the bathroom up, so the
// first project to join (the tower has no project floor yet) shifts the roof by one:
// riders and waiters start over. Injected 'home' sprites stand in for agents that were
// already in the tower: an agent only exists once its project's room does.
const inject=(id,room,goal)=>({id,room,kind:'home',goal});
const riders=[inject('rider-up','__kitchen',{room:'__roof',p:[7,2.2,4.4],cat:'fixture'}),
 inject('rider-down','__roof',{room:'__bath',p:[3.3,1.75,0],cat:'fixture'}),
 inject('walker-up','__bath',{room:'__roof',p:[5,2.2,4.4],cat:'fixture'}),
 inject('yard-up','__yard',{room:'__kitchen',p:[.8,2.6,6.6],cat:'fixture'})];
for(const [name,join] of [['relayout-lift-a',1200],['relayout-lift-b',5000],['relayout-lift-c',7500]])
 cases.push({name,seed:173,duration:join+8500,events:[{at:0,rows:[],inject:riders},
  {at:join,rows:[row('a0','alpha')]},{at:join+2500,rows:[row('a0','alpha'),row('b0','beta')]},
  {at:join+5000,rows:[row('a0','alpha'),row('b0','beta'),row('c0','gamma')]},
  {at:join+6500,rows:[row('b0','beta')]}]});
// Bridges and stairs rebuilt under walkers: a new project every 1.5 s, agents sent across
// the yard and the islands by state changes, then leaving (rooms stay; agents parachute).
{
 const names=['alpha','beta','gamma','delta','eps','zeta','eta','theta'],at=(t,i)=>row('w'+i,names[i],t<(i*1500+2500)?'working':(Math.floor((t-i*1500)/2500)%2?'working':'waiting'),{activity:'Read · x'});
 const events=[];
 for(let t=0;t<=15000;t+=500){
  const rows=names.map((_,i)=>i*1500<=t?at(t,i):null).filter(Boolean);
  if(t>=12000)rows.splice(0,Math.min(rows.length,Math.floor((t-10500)/1500)));
  // A walker bound for the yard leaves the island of the project that joined last.
  const k=Math.floor(t/1500),crossers=t%1500===500&&k<names.length?[inject('cross'+t,'p:'+names[k],{room:'__yard',p:[10.7,7.05,0],cat:'fixture'})]:[];
  events.push({at:t,rows,...(crossers.length?{inject:crossers}:{})});
 }
 cases.push({name:'relayout-bridges',seed:173,duration:18000,events});
}
// Churn from the behaviour review: unicode projects, unknown states, parents, many rooms joining mid-transit. churn-10 reaches the
// frame in which a sprite has just left a bridge (no room yet) while setAgents routes it; yard-exit sends agents off from the yard.
{
 const names=i=>['проект-'+i,'🚀rocket'+i,'école'+i,'école'+i,'项目'+i,'a/b c'+i,''][i%7];
 for(const seed of [5,10]){let st=seed*7919;const rnd=()=>{st=(Math.imul(st,1103515245)+12345)>>>0;return st/4294967296;};
 const ids=Array.from({length:18},(_,i)=>'r'+i),events=[];
 for(let at=0;at<=50000;at+=50*Math.max(1,Math.floor(rnd()*60))){
  const rows=[];for(const id of ids)if(rnd()<.6){const i=Number(id.slice(1));
   rows.push(row(id,names(Math.floor(rnd()*(4+at/5000))),['working','waiting','done','error','working','done'][Math.floor(rnd()*6)],
    {vendor:rnd()<.5?'codex':'claude',activity:['Read','Grep · x','Search','Agent','Bash · git push','',null][Math.floor(rnd()*7)]??undefined,
     parentId:i>=12?'r'+(i%6):undefined,context:rnd()}));}
  if(events.length&&events.at(-1).at===at)continue;events.push({at,rows});
 }
 cases.push({name:'churn-'+seed,seed:seed*31,duration:55000,sample:+(process.env.BEH_SAMPLE||1000),events});
 }
 const y=Array.from({length:12},(_,i)=>row('y'+i,'yardp','working',{activity:'Bash'}));
 cases.push({name:'yard-exit',seed:99,duration:40000,sample:500,events:[{at:0,rows:y},{at:3000,rows:y.map(r=>({...r,state:'done'}))},
  {at:26000,rows:[]},{at:33000,rows:y.slice(0,6)},{at:37000,rows:[]}]});
 // projects named after Object.prototype members (growth must keep them as own keys)
 const odd=['constructor','toString','__proto__','hasOwnProperty'].map((p,i)=>row('o'+i,p));
 cases.push({name:'odd-projects',seed:7,duration:12000,sample:500,events:[{at:0,rows:odd},{at:5000,rows:odd.map(r=>({...r,state:'done'}))},{at:9000,rows:[]}]});
 // an errand that never arrives (no goal): after 120 s the errand is given up and the sprite goes home
 cases.push({name:'lost-errand',seed:5,duration:125000,sample:2500,events:[{at:0,rows:[],inject:[{id:'lost',room:'__kitchen',kind:'home',goal:null,errand:{room:'__bath',cat:'shower',dur:20000}}]}]});
}
if(process.env.BEH_EXTRA)cases.push(...(await import(process.env.BEH_EXTRA)).cases);
if(process.env.BEH_ONLY){const only=process.env.BEH_ONLY.split(',');cases.splice(0,cases.length,...cases.filter(c=>only.includes(c.name)));}
let bytes=0;
const coverage=new Set();
for(const input of cases) {
 const s=scene();s.ctx.behaviourInput=input;
 s.run(`active=false;looping=false;demo=false;sprites.clear();growth={};
  globalThis.bt=0;performance.now=()=>bt;
  globalThis.bs=behaviourInput.seed;Math.random=()=>{bs=(Math.imul(bs,1664525)+1013904223)>>>0;return bs/4294967296;};
  // Stage 2c disabled. Keep the page's subagent tracking/holds and yard physics.
  updateResidents=()=>false;startCelebrate=()=>false;startMail=()=>false;dogGreet=()=>false;
  updateScenes=()=>false;
  globalThis.fallPoints=new Map();
  drawClawd=(x,y,sp,t)=>{if(sp.fall){const r=rooms[0];fallPoints.set(sp.id,[x-r.ox+r.wx,y-r.oy+r.wy]);}};
  globalThis.renderBehaviour=sp=>{
   const f=sp.fall,age=f?(bt-f.t0)/1000:0,r=rooms[0],raw=f?fallPoints.get(sp.id):scPos(sp);
   const pos=f?(raw??[f.x,f.y]):raw?[raw[0]-r.ox+r.wx,raw[1]-r.oy+r.wy]:[0,0];
   const pose=sp.state==='fall'?'fall':sp.moving?'walk':['shower','dry'].includes(sp.state)?sp.state:['done','idle-sleep'].includes(sp.state)?'sleep':sp.state==='waiting'?'wait':sp.state==='error'?'error':sp.state==='working'&&sp.seated?'work':'stand';
   return [sp.id,pose,1,pos,sp.alpha,sp.small,sp.vendor,drowsy(sp)?.5:1,f?(age<.35?'hop':age<.75?'freefall':age<1.05?'opening':'parachute'):null,f?Math.max(0,Math.min(1,(age-.75)/.3)):0,!!sp.seated,!!sp.waving,sp.towel??null];
  };
  globalThis.sampleBehaviour=()=>({sprites:[...sprites.values()].map(sp=>{
   const f=sp.fall,age=f?(bt-f.t0)/1000:0;
   return [sp.id,sp.room?.key??null,sp.homeRoom.key,sp.x,sp.y,sp.z,sp.goal?[sp.goal.room.key,sp.goal.cat,sp.goal.i,sp.goal.p]:null,
    sp.errand?[sp.errand.room.key,sp.errand.cat,sp.errand.dur??null,Number.isFinite(sp.errand.until)?sp.errand.until:null,sp.errand.since??null,sp.errand.t0??null,sp.errand.lost??false]:null,
    sp.state??null,sp.leaving??false,sp.exit??false,f?[f.x,f.y,f.t0,f.seed,age<.35?'hop':age<.75?'freefall':age<1.05?'opening':'parachute',Math.max(0,Math.min(1,(age-.75)/.3)),fallPoints.get(sp.id)??[f.x,f.y]]:null,
    sp.alpha,sp.fade,sp.small,sp.vendor,sp.moving,sp.seated??null,sp.waving??null,sp.path.length,sp.restOnRoof??false,sp.restInYard??false,sp.towel??null,
    sp.hold?[sp.hold.parent,sp.hold.vanish,sp.hold.stage,sp.hold.t0,sp.hold.t1??null]:null,sp.handed??false,sp.popped??false];}),
   render:[...sprites.values()].map(renderBehaviour),
   cabins:(LIFT?.cabins||[]).map(c=>[c.id,c.z,c.level??null,c.state,c.t,c.stop??null]),
   growth:Object.entries(growth).map(([p,e])=>[p,e.n,e.ids.slice(),growthLevel(roomByKey.get('p:'+p))]),rng:bs,
   puffs:SC.puffs.map(p=>[p.room.key,p.x,p.y,p.z,p.t0,p.col,p.seed]),papers:SC.papers.map(p=>[p.from.id,p.to.id,p.t0])});
  globalThis.relayoutCover=[];
  { const original=layout;
   layout=function(){const all=[...sprites.values()];
    relayoutCover.push([bt,all.filter(x=>x.onBridge?.pair?.kind==='lift').length,all.filter(x=>!x.onBridge&&x.path.some(n=>n.lift)).length,
     all.filter(x=>x.onBridge&&x.onBridge.pair?.kind!=='lift').length,all.filter(x=>!x.room&&!x.onBridge&&!x.fall).length]);
    return original.apply(this,arguments);};}
  globalThis.getRoom=k=>k==='__yard'?YARD:roomByKey.get(k);
  globalThis.trace=[];globalThis.nonfinite=[];
  // NaN and Infinity become null in JSON: a trace must never need them (the checker cannot tell them from null).
  globalThis.bad=o=>typeof o==='number'?!Number.isFinite(o):Array.isArray(o)?o.some(bad):false;
  for(bt=0;bt<=behaviourInput.duration;bt+=50){
   for(const e of behaviourInput.events.filter(e=>e.at===bt)){
    for(const j of e.inject||[]){const sp=spawn(j.id,getRoom(j.room),{kind:j.kind,vendor:'claude',small:false});if(j.errand)sp.errand={room:getRoom(j.errand.room),cat:j.errand.cat,dur:j.errand.dur,until:Infinity,since:bt};if(j.goal)setGoal(sp,{i:-1,...j.goal,room:getRoom(j.goal.room)});}
    if(e.rows)room.setAgents(e.rows);}
   if(bt){updateResidents(bt);updateErrands(bt);stepSprites(50);updateLifts(bt,50);
    updateYard(bt);for(const sp of [...sprites.values()])if(sp.hold?.kind==='handover')stepHold(sp,bt);updateStairs(bt);
    // drawRoom's only simulation mutation; no drawing or unrelated scene RNG.
    for(const r of rooms)r.drop=Math.round(-Math.pow(1-Math.min(1,Math.max(0,(bt-r.born)/900)),3)*140);
    drawFallers(bt);drawSceneOverlays(bt);
   }
   for(const sp of sprites.values())if(sp.errand?.lost)globalThis.lostSeen=true;
   globalThis.lastRoom=globalThis.lastRoom||new Map();for(const sp of sprites.values()){if(sp.fall&&lastRoom.get(sp.id)===YARD)globalThis.yardFall=true;if(sp.room)lastRoom.set(sp.id,sp.room);}
   if(bt%(behaviourInput.sample||250)===0){const f=sampleBehaviour();if(bad(f.sprites)||bad(f.render))nonfinite.push(bt);trace.push([bt,f]);}
  }`);
 const trace=JSON.parse(s.run('JSON.stringify(trace)'));
 if(input.name==='subagents-return') {
  assert.ok(trace.some(([,f])=>f.puffs.length),'must sample a puff');
  assert.ok(trace.some(([,f])=>f.papers.length),'must sample handback paper');
  assert.equal(trace.at(-1)[1].puffs.length,0);assert.equal(trace.at(-1)[1].papers.length,0);
 }
 if(input.name==='growth-ring') {
  const growth=trace.at(-1)[1].growth[0];assert.equal(growth[1],153);assert.equal(growth[2].length,150);
 }
 for(const [,frame]of trace)for(const sp of frame.sprites){
  if(sp[7])coverage.add('errand:'+sp[7][1]);if(sp[11])coverage.add('fall:'+sp[11][4]);
  if(sp[6])coverage.add('goal:'+sp[6][1]);if(sp[22])coverage.add('towel');if(sp[23])coverage.add('handover:'+sp[23][2]);
  if(sp[0].includes('#fall'))coverage.add('fall-return');
 }
 if(s.run('!!globalThis.lostSeen'))coverage.add('errand:lost');
 if(s.run('!!globalThis.yardFall'))coverage.add('fall:yard');
 assert.deepEqual(JSON.parse(s.run('JSON.stringify(nonfinite)')),[],input.name+': non-finite sprite or render values');
 assert.deepEqual(s.errors,[]);
  if(process.env.COVER)console.log(input.name,s.run('JSON.stringify(relayoutCover)'));
 for(const [,riding,waiting,bridging,limbo] of JSON.parse(s.run('JSON.stringify(relayoutCover)'))){
  if(riding)coverage.add('relayout:riding');if(waiting)coverage.add('relayout:waiting');if(bridging)coverage.add('relayout:bridge');if(limbo)coverage.add('relayout:limbo');}
 // Intern complete frames and sprite rows: stationary samples remain explicit
 // time entries without duplicating their entire payload.
 const values=[],index=new Map();
 const intern=o=>{const k=JSON.stringify(o);if(!index.has(k)){index.set(k,values.length);values.push(o);}return index.get(k);};
 const output=trace.map(([t,f])=>[t,intern({...f,sprites:f.sprites.map(intern),render:f.render.map(intern)})]);
 const schema={sprite:['id','room','homeRoom','x','y','z','goal(room,cat,i,p)','errand(room,cat,dur,until,since,t0,lost)','state','leaving','exit','fall(x,y,t0,seed,phase,open,worldPosition)','alpha','fade','small','vendor','moving','seated','waving','pathCount','restOnRoof','restInYard','towelUntil','handover(parent,vanish,stage,t0,t1)','handed','popped'],render:['id','pose','facing','worldPosition','alpha','small','vendor','animationRate','parachutePhase','parachuteOpen','seated','waving','towelUntil'],growth:['project','n','recentIds','level'],cabin:['id','z','level','state','t','stop'],puff:['room','x','y','z','t0','color','seed'],paper:['fromId','toId','t0'],nonfinite:'NaN/Infinity are JSON null; values interns sprite/render rows and complete frames; trace is [time,frameIndex]'};
 const json=JSON.stringify({input,schema,values,trace:output})+'\n',file=path.join(dir,input.name+'.json');
 if(check)assert.equal(fs.readFileSync(file,'utf8'),json,input.name+': JS behaviour changed');else fs.writeFileSync(file,json);
 bytes+=Buffer.byteLength(json);
}
if(!process.env.BEH_ONLY)for(const key of ['errand:shower','errand:wash','errand:dry','towel','fall:hop','fall:freefall','fall:opening','fall:parachute','handover:walk','handover:give','fall-return','goal:seat','goal:cowork','relayout:riding','relayout:waiting','relayout:bridge','errand:lost','fall:yard'])assert.ok(coverage.has(key),'missing coverage '+key);
assert.ok(process.env.BEH_EXTRA||process.env.BEH_ONLY||bytes<5_000_000,`fixtures too large: ${bytes}`); // 3 MB before the relayout traces
console.log(`house-behaviour: ${cases.length} fixtures, ${bytes} bytes; ${[...coverage].sort().join(', ')}`);
