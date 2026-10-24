import fs from 'node:fs';
import vm from 'node:vm';
export function scene(file='room/index.html', search='?nodemo=1&hour=12&season=summer&backdrop=city', canvasFactory=null) {
 let tick=0,id=1,seed=173;const timers=new Map(),rafs=new Map(),calls={main:0,offscreen:0};let counting=false;
 class Context {
  constructor(canvas){this.canvas=canvas;this.globalAlpha=1;this.globalCompositeOperation='source-over';this.states=[];}
  save(){this.states.push([this.globalAlpha,this.globalCompositeOperation,this.fillStyle]);}
  restore(){if(this.states.length)[this.globalAlpha,this.globalCompositeOperation,this.fillStyle]=this.states.pop();}
  count(){if(counting)calls[this.canvas.id==='c'?'main':'offscreen']++;}
  fillRect(){this.count();}clearRect(){this.count();}drawImage(){this.count();}fill(){this.count();}stroke(){this.count();}fillText(){this.count();}strokeText(){this.count();}putImageData(){this.count();}
  beginPath(){}closePath(){}moveTo(){}lineTo(){}clip(){}arc(){}rect(){}setTransform(){}translate(){}scale(){}
  createLinearGradient(){return {addColorStop(){}};}createRadialGradient(){return {addColorStop(){}};}
 }
 class Element {
  constructor(tag='div',id=''){
   if(tag==='canvas' && canvasFactory){
    const c=canvasFactory(300,150);Object.assign(c,{id,style:{},addEventListener(){},dispatchEvent(){}});
    const get=c.getContext.bind(c);let context;
    c.getContext=()=>{if(context)return context;context=get('2d');for(const name of ['fillRect','clearRect','drawImage','fill','stroke','fillText','strokeText','putImageData']){const raw=context[name].bind(context);context[name]=(...a)=>{if(counting)calls[id==='c'?'main':'offscreen']++;return raw(...a);};}return context;};return c;
   }
   this.tagName=tag;this.id=id;this.style={};this.dataset={};this.hidden=true;this.width=300;this.height=150;this.classList={toggle(){},add(){},remove(){},contains(){return false;}};}
  getContext(){return this.ctx??=new Context(this);}addEventListener(){}appendChild(){}append(){}remove(){}dispatchEvent(){}
  querySelector(){return new Element();}querySelectorAll(){return [];}
 }
 const epoch=new Date('2026-10-22T12:00:00+03:00').getTime();
 class FixedDate extends Date{constructor(...a){super(...(a.length?a:[epoch]));}static now(){return epoch;}}
 const els=new Map(),errors=[],math=Object.create(Math);math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
 const ctx=vm.createContext({console:{log(){},error(e){errors.push(String(e));}},Math:math,Date:FixedDate,URLSearchParams,CanvasRenderingContext2D:Context,
  document:{visibilityState:'visible',getElementById(id){if(!els.has(id))els.set(id,new Element(id==='c'?'canvas':'div',id));return els.get(id);},createElement(tag){return new Element(tag);},body:new Element(),activeElement:null,addEventListener(){}},
  location:{search},innerWidth:1440,innerHeight:900,devicePixelRatio:2,performance:{now:()=>tick},localStorage:{getItem:()=>null,setItem(){}},
  setTimeout(fn,ms){const n=id++;timers.set(n,{fn,at:tick+ms,ms});return n;},clearTimeout(n){timers.delete(n);},setInterval:()=>0,clearInterval(){},
  requestAnimationFrame(fn){const n=id++;rafs.set(n,fn);return n;},cancelAnimationFrame(n){rafs.delete(n);},addEventListener(){},Image:class{},MouseEvent:class{}});
 ctx.window=ctx;
 vm.runInContext(fs.readFileSync(file,'utf8').match(/<script>([\s\S]*?)<\/script>/)[1],ctx,{filename:file});
 const run=code=>vm.runInContext(code,ctx);
 function advance(ms){const end=tick+ms;let guard=0;while(++guard<100000){let next=[...timers].filter(([,t])=>t.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(rafs.size && (!next||tick+1000/60<=next[1].at)){tick+=1000/60;if(tick>end)break;const all=[...rafs.values()];rafs.clear();for(const f of all)f(tick);}else if(next){tick=Math.max(tick,next[1].at);timers.delete(next[0]);next[1].fn();}else break;}tick=end;}
 function frame(t){tick=t;run(`frame(${t})`);}
 return {ctx,run,frame,advance,timers,rafs,calls,errors,get tick(){return tick;},count(on=true){calls.main=calls.offscreen=0;counting=on;}};
}
export function fixture(s,mode='working',projects=2){
 s.run(`active=false;looping=false;clearTimeout(nap);demo=false;fixedHour=Number(Q.get('hour')||12);
 room.setAgents(${mode==='idle'?'[]':`DEMO_PROJECTS.slice(0,${projects}).flatMap((p,i)=>[{id:'a'+i,title:'Read',project:p,vendor:'claude',state:'working',activity:'Read · Model.swift'},{id:'b'+i,title:'Build',project:p,vendor:'codex',state:'working',activity:'Bash · swift build'}])`});`);
 s.run(`updateResidents=()=>{};updateErrands=()=>{};updateScenes=()=>{};updateLifts=()=>{};updateStairs=()=>{};demoTick=()=>{};
 CAM.glide=CAM.follow=null;for(const r of rooms)r.born=-100000;for(const L of links)L.turn=null;if(LIFT)for(const c of LIFT.cabins)c.state="idle";
 for(const sp of [...sprites.values()]){
  if(sp.kind!=='agent'){sprites.delete(sp.id);continue;}
  sp.path=[];sp.onBridge=null;sp.moving=false;sp.hold=null;sp.fall=null;sp.alpha=sp.fade=1;
  if(sp.goal){sp.room=sp.goal.room;[sp.x,sp.y,sp.z]=sp.goal.p;sp.state='working';sp.seated=sp.z>3;}
 }`);
 for(let i=1;i<=60;i++)s.frame(i*1000/6);
 s.run(`${mode==='walking'?`const walkStep=stepSprites;stepSprites=dt=>{for(const sp of sprites.values())if(sp.kind==='agent'&&!sp.path.length){const r=sp.room;sp.path=[{r,p:[sp.x>r.NX/2?1:r.NX-1,sp.y,0]}];}walkStep(dt);};`:''}`);
 s.frame(10000);s.count();
}
