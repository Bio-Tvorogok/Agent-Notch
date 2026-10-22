import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {scene} from './scene.mjs';
process.chdir(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..'));
const dir=process.env.LIFE_DIR||'Tests/Fixtures/house-life',check=process.argv.includes('--check');
if(!check)fs.mkdirSync(dir,{recursive:true});
const row=(id,state='working',extra={})=>({id,project:'alpha',state,vendor:'claude',activity:'Bash · build',...extra});
const cases=[
 {name:'unicode-residents',seed:173,duration:15000,events:[{at:0,rows:[row('a','working',{project:'é'}),row('b','working',{project:'e\u0301'})]},{at:1000,rows:[row('a','working',{project:'é'})]}]},
 {name:'quiet-day',seed:173,duration:240000,events:[{at:0,rows:[row('a')]},{at:1000,rows:[]},{at:45000,hour:8},{at:95000,hour:14},{at:145000,hour:20},{at:195000,hour:0,dark:.8},{at:230000,rows:[row('a')]}]},
 {name:'shower-escort',seed:173,duration:180000,events:[{at:0,rows:Array.from({length:5},(_,i)=>row('wash'+i))},{at:15000,rows:Array.from({length:5},(_,i)=>row('wash'+i,i<2?'done':'working'))}]},
 {name:'pets-work',seed:31,duration:260000,events:[{at:0,rows:[row('a')]},{at:180000,rows:[row('a','done')]},{at:245000,rows:[]}]},
 {name:'celebrate-mail-leave',seed:173,duration:85000,events:[{at:0,rows:[row('a')]},{at:1000,rows:[row('a')]},{at:10000,rows:[row('a','done')]},{at:11000,rows:[]},{at:22000,rows:[row('b')]},{at:24000,rows:[row('b','working',{activity:'Bash · git commit -m x'})]},{at:40000,rows:[row('b','working',{activity:'Bash · git push'})]},{at:41000,rows:[]}]},
 {name:'fire-handover',seed:99,duration:95000,events:[{at:0,rows:[row('parent'),row('child','working',{parentId:'parent'}),row('fire')]},{at:5000,rows:[row('parent'),row('child','working',{parentId:'parent'}),row('fire','error')]},{at:10000,rows:[row('parent'),row('child','done',{parentId:'parent'}),row('fire','error')]},{at:20000,rows:[row('parent'),row('fire','error')]},{at:24000,rows:[row('parent','working',{parentId:'boss'}),row('fire','error'),row('boss','working',{project:'beta'})]},{at:25000,rows:[row('parent','done',{parentId:'boss'}),row('fire','error'),row('boss','working',{project:'beta'})]},{at:28000,rows:[row('parent','working',{parentId:'boss',activity:'Bash · git push'}),row('fire','error'),row('boss','working',{project:'beta'})]},{at:30000,rows:[row('fire','error'),row('boss','working',{project:'beta'})]},{at:35000,rows:[row('parent'),row('fire')]},{at:60000,rows:[]}]},
 {name:'yard-fetch',seed:7,duration:300000,events:[{at:0,rows:[row('a'),...Array.from({length:12},(_,i)=>row('yard'+i))]},{at:15000,rows:[row('a'),...Array.from({length:12},(_,i)=>row('yard'+i,'done'))]},{at:250000,rows:[]}]},
 {name:'irregular-frame',seed:5,duration:40000,frame:[17,33,100,250,1600,50,450,50],events:[{at:0,rows:[row('a')]},{at:10000,rows:[row('a','error')]},{at:25000,rows:[row('a','done')]}]}
];
if(process.env.LIFE_ONLY){const names=process.env.LIFE_ONLY.split(',');cases.splice(0,cases.length,...cases.filter(c=>names.includes(c.name)));}
const coverage=new Set();let bytes=0;
for(const input of cases){
 const s=scene();s.ctx.lifeInput=input;
 s.run(`active=false;looping=false;demo=false;sprites.clear();growth={};
 globalThis.lt=0;performance.now=()=>lt;globalThis.ls=lifeInput.seed;Math.random=()=>{ls=(Math.imul(ls,1664525)+1013904223)>>>0;return ls/4294967296;};
 // Stage 3 is deliberately excluded, including its random stream.
 drawSkyLife=()=>{};drawSeason=()=>{};globalThis.hour=12;DARK=0;
 globalThis.lifeRender=sp=>{const r=rooms[0],raw=scPos(sp),p=raw?[raw[0]-r.ox+r.wx,raw[1]-r.oy+r.wy]:[0,0];
 const pet=sp.kind==='cat'||sp.kind==='dog';const n=sp.path[0];if(pet){if(sp.onBridge)sp.face=sp.onBridge.forward?1:-1;else if(n&&n.p){const dx=(n.p[0]-sp.x)-(n.p[1]-sp.y);if(Math.abs(dx)>.05)sp.face=Math.sign(dx);}else if(sp.kind==='dog'&&sp.look){const dx=(sp.look[0]-sp.x)-(sp.look[1]-sp.y);if(Math.abs(dx)>.05)sp.face=Math.sign(dx);}}
 const pose=pet?(sp.moving?'walk':sp.pose||'sit'):sp.state==='fall'?'fall':sp.moving?'walk':['shower','dry'].includes(sp.state)?sp.state:['done','idle-sleep'].includes(sp.state)?'sleep':sp.state==='waiting'?'wait':sp.state==='error'?'error':sp.state==='working'&&sp.seated?'work':'stand';
 const h=sp.hold;const prop=h?.kind==='ext'?'ext':h?.kind==='mail'&&h.stage==='go'?'letter':h?.kind==='handover'&&h.stage==='walk'?'paper':sp.kind==='home'?(sp.scene==='coffee'?'mug':sp.scene==='water'?'can':sp.scene==='read'&&scArrived(sp)&&sp.goal.cat==='read'?'book':null):null;
 return [sp.id,sp.kind,pose,pet?(sp.face||1):1,p,sp.alpha,sp.scene??null,prop,sp.ball??false,sp.wag??false,sp.fire?.t0??null,sp.fire?.foamed??null,h?.spraying??false,h?.target??null,sp.toss??null,h?.dir??1,sp.kind==='home'&&sp.scene==='water'&&scArrived(sp)&&sp.goal.cat==='water'];};
 globalThis.sampleLife=()=>({rng:ls,sprites:[...sprites.values()].map(sp=>[sp.id,sp.kind,sp.room?.key??null,sp.homeRoom.key,sp.x,sp.y,sp.z,sp.alpha,sp.fade,sp.state??null,sp.path.length,sp.goal?[sp.goal.room.key,sp.goal.cat,sp.goal.i,sp.goal.p]:null,
 sp.errand?[sp.errand.room.key,sp.errand.cat,sp.errand.dur??null,Number.isFinite(sp.errand.until)?sp.errand.until:null,sp.errand.since??null,sp.errand.t0??null]:null,
 sp.scene??null,sp.arriveState??null,sp.pose??null,sp.want??null,Number.isFinite(sp.next)?sp.next:null,sp.rNext??null,sp.deskOf??null,sp.fireOf??null,sp.look??null,sp.wag??false,sp.ball??false,sp.toss??null,sp.workSince??null,sp.mailAct??null,
 sp.fire?[sp.fire.t0,sp.fire.helper??null,sp.fire.retry??null,sp.fire.foamed??null]:null,
 sp.hold?[sp.hold.kind,sp.hold.stage??null,sp.hold.t0,sp.hold.t1??null,sp.hold.target??null,sp.hold.state??null,sp.hold.dir??null,sp.hold.spraying??null,sp.hold.sprayFrom??null,sp.hold.z0??null,sp.hold.start??null,sp.hold.parent??null,sp.hold.vanish??null]:null,
 sp.greet?[sp.greet.id,sp.greet.stage,sp.greet.t0,sp.greet.t1??null,sp.greet.re??null]:null,sp.leaving??false,sp.exit??false,sp.moving,sp.seated??null,sp.waving??null,sp.handed??false,sp.popped??false,sp.towel??null]),render:[...sprites.values()].filter(sp=>!sp.fall).map(lifeRender),
 ball:SC.ball?[SC.ball.by,SC.ball.n,SC.ball.of,SC.ball.t0,SC.ball.ms,SC.ball.from,SC.ball.to,SC.ball.held,SC.ball.stage,SC.ball.t1??null,ballAt(SC.ball,lt)]:null,
 mailFlag:SC.mailFlag,fireworks:SC.fireworks.map(f=>[f.room.key,f.t0,f.seed]),puffs:SC.puffs.map(p=>[p.room.key,p.x,p.y,p.z,p.t0,p.col,p.seed]),papers:SC.papers.map(p=>[p.from.id,p.to.id,p.t0])});
 globalThis.trace=[];globalThis.cov=new Set();globalThis.bad=x=>typeof x==='number'?!Number.isFinite(x):Array.isArray(x)?x.some(bad):x&&typeof x==='object'?Object.values(x).some(bad):false;
 globalThis.sample=()=>{const f=sampleLife();if(bad(f))throw Error('nonfinite at '+lt);trace.push([lt,f]);};
 globalThis.one=(dt)=>{updateResidents(lt);updateErrands(lt);for(let left=dt;left>0;){const step=Math.min(50,left);left-=step;stepSprites(step);updateLifts(lt-left,step);}const d=new Date(2026,9,22,Math.floor(hour),Math.floor(hour%1*60));updateScenes(lt,d);updateStairs(lt);for(const r of rooms)r.drop=Math.round(-Math.pow(1-Math.min(1,Math.max(0,(lt-r.born)/900)),3)*140);drawFallers(lt);drawSceneOverlays(lt);for(const sp of sprites.values())if(!sp.fall)lifeRender(sp);};
 globalThis.event=e=>{if(e.hour!==undefined)hour=e.hour;if(e.dark!==undefined)DARK=e.dark;if(e.rows)room.setAgents(e.rows);};
 for(const e of lifeInput.events.filter(e=>e.at===0))event(e);sample();
 if(!lifeInput.frame){for(lt=50;lt<=lifeInput.duration;lt+=50){for(const e of lifeInput.events.filter(e=>e.at===lt))event(e);one(50);if(lt%250===0)sample();}}
 else {let i=0,prev=0;while(lt<lifeInput.duration){const old=lt;lt=Math.min(lifeInput.duration,lt+lifeInput.frame[i++%lifeInput.frame.length]);for(const e of lifeInput.events.filter(e=>e.at>old&&e.at<=lt))event(e);one(Math.min(1500,lt-old));sample();}}
 `);
 const trace=JSON.parse(s.run('JSON.stringify(trace)'));
 if(input.name==='unicode-residents')assert.ok(trace.some(([,f])=>f.sprites.some(s=>s[0]==='home:p:e\u0301')),'canonically equivalent project remains distinct');
 if(input.name==='fire-handover'){
  const at=t=>trace.find(e=>e[0]===t)[1].sprites.find(s=>s[0]==='parent');
  assert.equal(at(25000)[28][0],'ext','ext hold must block subagent handover');
  assert.equal(at(25000)[25],null,'workSince cleared even when ext blocks handover');
  assert.equal(at(28000)[25],28000,'workSince runs under ext hold');
  assert.equal(at(28000)[26],null,'ext blocks mail while bookkeeping still runs');
  assert.equal(at(30000)[28][0],'handover','leaving releases ext before handover');
 }
 if(input.name==='celebrate-mail-leave'){
  assert.ok(trace.some(([,f])=>f.mailFlag>0),'must reach mailbox');
  const gone=trace.find(e=>e[0]===11000)[1].sprites.find(s=>s[0]==='a');assert.equal(gone[28],null,'leaving root releases celebration');
 }

 for(const [,f]of trace){for(const sp of f.sprites){coverage.add('kind:'+sp[1]);if(sp[11])coverage.add('goal:'+sp[11][1]);if(sp[13])coverage.add('scene:'+sp[13]);if(sp[15])coverage.add(sp[1]+':'+sp[15]);if(sp[19])coverage.add('cat:keyboard');if(sp[20])coverage.add('dog:fire');if(sp[27])coverage.add('fire');if(sp[28])coverage.add('hold:'+sp[28][0]);if(sp[29]){coverage.add('greet:'+sp[29][1]);const a=f.sprites.find(s=>s[0]===sp[29][0]);if(a?.[12]?.[1]==='shower')coverage.add('greet:shower');}if(sp[9]==='idle-sleep')coverage.add('resident:sleep');}if(f.ball)coverage.add('fetch:'+f.ball[8]);}
 const values=[],index=new Map(),intern=o=>{const k=JSON.stringify(o);if(!index.has(k)){index.set(k,values.length);values.push(o);}return index.get(k);};
 const output=trace.map(([t,f])=>[t,intern({...f,sprites:f.sprites.map(intern),render:f.render.map(intern)})]);
 const schema={sprite:['id','kind','room','homeRoom','x','y','z','alpha','fade','state','pathCount','goal(room,cat,i,p)','errand(room,cat,dur,until,since,t0)','scene','arriveState','pose','want','next','routineNext','deskOf','fireOf','look','wag','carryingBall','tossAt','workSince','mailAct','fire(t0,helper,retry,foamed)','hold(kind,stage,t0,t1,target,state,dir,spraying,sprayFrom,z0,start,parent,vanish)','greet(id,stage,t0,t1,re)','leaving','exit','moving','seated','waving','handed','popped','towelUntil'],render:['id','kind','pose','facing','worldPosition','alpha','scene','prop','carryingBall','wagging','fireSince','foamedAt','spraying','sprayTarget','tossAt','propFacing','pouring'],ball:['by','n','of','t0','ms','from','to','held','stage','t1','position'],exception:'all scheduling Infinity values are explicit null'};
 const json=JSON.stringify({input,schema,values,trace:output})+'\n',file=path.join(dir,input.name+'.json');
 if(check)assert.equal(fs.readFileSync(file,'utf8'),json,input.name+': JS life changed');else fs.writeFileSync(file,json);bytes+=Buffer.byteLength(json);assert.deepEqual(s.errors,[]);
}
console.log(`house-life: ${cases.length} fixtures, ${bytes} bytes; ${[...coverage].sort().join(', ')}`);
if(!process.env.LIFE_ONLY)for(const key of ['kind:home','cat:nap','cat:keyboard','cat:sit','dog:nap','dog:sit','dog:fire','greet:meet','greet:along','greet:wait','greet:shower','fetch:come','fetch:throw','fetch:fly','fetch:back','scene:coffee','scene:water','scene:read','resident:sleep','hold:celebrate','hold:mail','hold:ext','hold:handover'])assert.ok(coverage.has(key),'missing coverage '+key);
assert.ok(bytes<5_000_000,`fixtures too large: ${bytes}`);
