const canvas = document.querySelector("#city");
const ctx = canvas.getContext("2d");
const ui = {
  lobby: document.querySelector("#lobby"), game: document.querySelector("#game"),
  name: document.querySelector("#playerName"), code: document.querySelector("#roomCode"),
  message: document.querySelector("#lobbyMessage"), dot: document.querySelector("#connectionDot"),
  connection: document.querySelector("#connectionText"), badge: document.querySelector("#roomBadge"),
  coins: document.querySelector("#coinCount"), title: document.querySelector("#cityTitle"),
  partner: document.querySelector("#partnerStatus"), list: document.querySelector("#playerList"),
  prompt: document.querySelector("#actionPrompt"), toast: document.querySelector("#toast")
};
const WORLD = {w:1600,h:1100};
const keys = new Set();
let ws = null, roomCode = "", myId = "", players = [], homes = {}, jobs = [], properties = [];
let accountKey = localStorage.getItem("twoKeysAccountKey");
if (!accountKey) {
  accountKey = crypto.randomUUID();
  localStorage.setItem("twoKeysAccountKey", accountKey);
}
let lastSend = 0, lastFrame = 0, nearest = null, toastTimer = 0;
const buildings = [
  {x:55,y:65,w:270,h:135,c:"#d4c4a7",n:"MARKET STREET"},
  {x:430,y:65,w:225,h:135,c:"#d5a98c",n:"CANAL LOFT"},
  {x:790,y:65,w:300,h:135,c:"#c8d2bc",n:"OLD TOWN"},
  {x:1160,y:65,w:370,h:135,c:"#d7c7a5",n:"RIVERSIDE"},
  {x:55,y:345,w:270,h:255,c:"#bdcbb4",n:"LIBRARY"},
  {x:430,y:345,w:225,h:255,c:"#dfc9ac",n:"BAKERY"},
  {x:790,y:345,w:300,h:255,c:"#c7b1a0",n:"TOWN HALL"},
  {x:1160,y:345,w:370,h:255,c:"#c3d0c6",n:"COMMUNITY"},
  {x:55,y:735,w:270,h:295,c:"#d8be9e",n:"GARDEN WARD"},
  {x:430,y:735,w:225,h:295,c:"#b8c8bb",n:"STUDIO"},
  {x:790,y:735,w:300,h:295,c:"#d2bea3",n:"CINEMA"},
  {x:1160,y:735,w:370,h:295,c:"#c8cbb3",n:"HARBOR"}
];
function connect(kind, code="") {
  if (ws) ws.close();
  ui.message.classList.remove("error");
  ui.message.textContent = "Connecting to your city…";
  const scheme = location.protocol === "https:" ? "wss:" : "ws:";
  ws = new WebSocket(`${scheme}//${location.host}/ws`);
  ws.onopen = () => ws.send(JSON.stringify({type:kind, room:code, name:ui.name.value.trim() || "Player", account:accountKey}));
  ws.onmessage = event => {
    const data = JSON.parse(event.data);
    if (data.type === "error") {
      if (!ui.game.classList.contains("hidden")) showToast(data.message);
      else { ui.message.textContent = data.message; ui.message.classList.add("error"); }
      return;
    }
    if (data.type === "welcome") {
      roomCode = data.room; myId = data.player;
      ui.lobby.classList.add("hidden"); ui.game.classList.remove("hidden");
      ui.badge.textContent = roomCode; ui.connection.textContent = "City connected"; ui.code.value = roomCode;
      ui.dot.classList.add("online"); ui.title.textContent = "ROOM " + roomCode;
    }
    if (data.type === "state") {
      players = data.players || []; homes = data.homes || {};
      jobs = data.jobs || []; properties = data.properties || [];
      updateHud();
      if (data.notice) showToast(data.notice.text);
    }
  };
  ws.onclose = () => {
    ui.dot.classList.remove("online");
    if (!ui.game.classList.contains("hidden")) {
      ui.connection.textContent = "Connection lost";
      showToast("Connection lost. Return to the lobby and create a new room.");
    }
  };
  ws.onerror = () => { ui.message.textContent = "Could not reach the game server."; ui.message.classList.add("error"); };
}
function updateHud() {
  const me = players.find(p => p.id === myId);
  if (me) ui.coins.textContent = me.coins;
  const partner = players.find(p => p.id !== myId);
  ui.partner.textContent = partner ? `Playing together with ${partner.name}` : "Waiting for your person… share the room code";
  ui.list.innerHTML = "";
  players.forEach((p,index) => {
    const chip = document.createElement("span");
    chip.className = "player-chip";
    chip.textContent = (index === 0 ? "● " : "● ") + p.name;
    chip.style.color = index === 0 ? "#527c5b" : "#bb765c";
    ui.list.appendChild(chip);
  });
}
function me() { return players.find(p => p.id === myId); }
function showToast(text) {
  ui.toast.textContent = text; ui.toast.classList.add("show");
  clearTimeout(toastTimer); toastTimer = setTimeout(() => ui.toast.classList.remove("show"), 2600);
}
function dist(a,b) { return Math.hypot(a.x-b.x,a.y-b.y); }
function interact() {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  const player = me();
  if (player?.inside) { ws.send(JSON.stringify({type:"exit"})); return; }
  if (!nearest) return;
  if (nearest.type === "job") ws.send(JSON.stringify({type:"work",job:nearest.item.id}));
  else if (homes[nearest.item.id]) ws.send(JSON.stringify({type:"enter",home:nearest.item.id}));
  else ws.send(JSON.stringify({type:"buy",home:nearest.item.id}));
}
function calcNearest(player) {
  nearest = null;
  if (player.inside) { ui.prompt.textContent = "E  ·  Step back outside"; return; }
  let best = 76;
  for (const item of jobs) {
    const d = dist(player,item);
    if (d < best) {best=d;nearest={type:"job",item};}
  }
  for (const item of properties) {
    const d = dist(player,item);
    if (d < best) {best=d;nearest={type:"home",item};}
  }
  if (!nearest) ui.prompt.textContent = "";
  else if (nearest.type === "job") ui.prompt.textContent = `E  ·  ${nearest.item.name}  ·  +${nearest.item.reward} coins`;
  else if (homes[nearest.item.id]) ui.prompt.textContent = `⌂  ${nearest.item.name}  ·  couple home owned`;
  else ui.prompt.textContent = `E  ·  Buy ${nearest.item.name}  ·  ${nearest.item.cost} coins`;
}
function collides(x,y) {
  if (me()?.inside) return false;
  const r=15;
  return buildings.some(b => x+r>b.x && x-r<b.x+b.w && y+r>b.y && y-r<b.y+b.h);
}
function move(dt) {
  const p=me(); if(!p)return;
  let dx=(keys.has("d")?1:0)-(keys.has("a")?1:0), dy=(keys.has("s")?1:0)-(keys.has("w")?1:0);
  const mag=Math.hypot(dx,dy)||1; dx=dx/mag*230*dt; dy=dy/mag*230*dt;
  let nx=Math.max(25,Math.min(WORLD.w-25,p.x+dx));
  if(!collides(nx,p.y))p.x=nx;
  let ny=Math.max(25,Math.min(WORLD.h-25,p.y+dy));
  if(!collides(p.x,ny))p.y=ny;
  const now=performance.now();
  if(now-lastSend>45 && ws?.readyState===WebSocket.OPEN){
    ws.send(JSON.stringify({type:"move",x:p.x,y:p.y}));lastSend=now;
  }
}
function roundRect(x,y,w,h,r,fill,stroke=null){
  ctx.beginPath();ctx.roundRect(x,y,w,h,r);ctx.fillStyle=fill;ctx.fill();
  if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=2;ctx.stroke();}
}
function drawWorld() {
  const p=me(); if(!p)return;
  if (p.inside) { drawInterior(p); calcNearest(p); return; }
  const scale=Math.min(canvas.width/850,canvas.height/550);
  const camX=Math.max(0,Math.min(WORLD.w-canvas.width/scale,p.x-canvas.width/scale/2));
  const camY=Math.max(0,Math.min(WORLD.h-canvas.height/scale,p.y-canvas.height/scale/2));
  ctx.setTransform(scale,0,0,scale,-camX*scale,-camY*scale);
  ctx.fillStyle="#dce6d4";ctx.fillRect(camX,camY,WORLD.w,WORLD.h);
  // Streets and sidewalks
  ctx.fillStyle="#c5d3c2";ctx.fillRect(0,0,WORLD.w,WORLD.h);
  ctx.fillStyle="#808982";ctx.fillRect(0,278,WORLD.w,54);ctx.fillRect(0,642,WORLD.w,54);
  ctx.fillStyle="#9ba69b";ctx.fillRect(0,270,WORLD.w,8);ctx.fillRect(0,332,WORLD.w,8);ctx.fillRect(0,634,WORLD.w,8);ctx.fillRect(0,696,WORLD.w,8);
  ctx.fillStyle="#f0d99b";ctx.fillRect(0,304,WORLD.w,2);ctx.fillRect(0,668,WORLD.w,2);
  for(let x=20;x<WORLD.w;x+=90){ctx.fillStyle="#d9d8bf";ctx.fillRect(x,296,38,2);ctx.fillRect(x,660,38,2);}
  // green pocket parks
  roundRect(680,220,70,105,12,"#a5c59b");roundRect(680,670,70,105,12,"#a5c59b");
  ctx.fillStyle="#6f9a70";for(const [x,y] of [[700,245],[730,275],[700,700],[730,735]]){ctx.beginPath();ctx.arc(x,y,9,0,Math.PI*2);ctx.fill();}
  // city blocks
  buildings.forEach(b=>{
    roundRect(b.x+6,b.y+10,b.w,b.h,5,"#00000018");
    roundRect(b.x,b.y,b.w,b.h,5,b.c,"#ffffff70");
    ctx.fillStyle="#6b8173";
    const cols=Math.floor(b.w/48), rows=Math.floor(b.h/50);
    for(let i=0;i<cols;i++)for(let j=0;j<rows;j++){
      roundRect(b.x+14+i*40,b.y+17+j*42,20,22,2,"#e7e4ce");
      ctx.fillStyle="#78907b";ctx.fillRect(b.x+20+i*40,b.y+22+j*42,3,12);
      ctx.fillStyle="#6b8173";
    }
    ctx.fillStyle="#394940";ctx.font="10px monospace";ctx.fillText(b.n,b.x+12,b.y+b.h-12);
  });
  // jobs
  jobs.forEach(job=>{
    roundRect(job.x-31,job.y-26,62,52,10,"#477557","#ecf1df");
    ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="bold 21px sans-serif";ctx.fillText("✦",job.x,job.y+7);
    ctx.fillStyle="#365343";ctx.font="10px sans-serif";ctx.fillText(job.name,job.x,job.y+43);
  });
  // homes with purchase / ownership signs
  properties.forEach(home=>{
    const owned=homes[home.id];
    roundRect(home.x-48,home.y-34,96,68,7,owned?"#73987c":"#d2ad60","#fff3d4");
    ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="bold 17px sans-serif";ctx.fillText(owned?"⌂":"$",home.x,home.y+5);
    ctx.fillStyle="#4b4435";ctx.font="10px sans-serif";
    ctx.fillText(owned?"OUR HOME":home.name,home.x,home.y+49);
  });
  // players
  players.forEach((pl,index)=>{
    if(pl.inside)return;
    const col=pl.id===myId?"#527e61":"#bf735b";
    ctx.fillStyle="#17231e30";ctx.beginPath();ctx.ellipse(pl.x,pl.y+15,13,5,0,0,Math.PI*2);ctx.fill();
    ctx.fillStyle=col;ctx.beginPath();ctx.arc(pl.x,pl.y,12,0,Math.PI*2);ctx.fill();
    ctx.strokeStyle="#fff";ctx.lineWidth=3;ctx.stroke();
    ctx.fillStyle="#fff";ctx.font="bold 11px sans-serif";ctx.textAlign="center";ctx.fillText(pl.name.slice(0,1).toUpperCase(),pl.x,pl.y+4);
    ctx.fillStyle="#23362a";ctx.font="11px sans-serif";ctx.fillText(pl.name,pl.x,pl.y-20);
  });
  ctx.setTransform(1,0,0,1,0,0);ctx.textAlign="start";
  calcNearest(p);
}
function drawInterior(player) {
  const scale=Math.min(canvas.width/650,canvas.height/440);
  const camX=player.x-canvas.width/scale/2, camY=player.y-canvas.height/scale/2;
  ctx.setTransform(scale,0,0,scale,-camX*scale,-camY*scale);
  ctx.fillStyle="#877b66";ctx.fillRect(camX,camY,WORLD.w,WORLD.h);
  roundRect(600,390,400,320,18,"#e9dfc9","#fff6e2");
  // warm floorboards
  ctx.save();ctx.beginPath();ctx.roundRect(600,390,400,320,18);ctx.clip();
  for(let y=410;y<710;y+=34){ctx.strokeStyle="#d7c8ac";ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(600,y);ctx.lineTo(1000,y);ctx.stroke();}
  ctx.restore();
  // cozy rug and coffee table
  roundRect(700,500,200,120,24,"#a9bca0");
  roundRect(755,530,92,55,12,"#bd8c67","#f8edda");
  ctx.fillStyle="#6b4835";ctx.beginPath();ctx.arc(800,557,15,0,Math.PI*2);ctx.fill();
  // sofa
  roundRect(635,420,145,52,12,"#668775");
  roundRect(645,425,42,40,9,"#7f9b85");roundRect(694,425,42,40,9,"#7f9b85");roundRect(743,425,29,40,9,"#7f9b85");
  // bookshelf and plant
  roundRect(850,410,115,28,5,"#9a6c4b");
  for(let i=0;i<5;i++){ctx.fillStyle=["#d8a969","#87a7a0","#b87865","#d4c28c","#789071"][i];ctx.fillRect(858+i*20,414,12,20);}
  ctx.fillStyle="#567f61";ctx.beginPath();ctx.arc(925,650,18,0,Math.PI*2);ctx.fill();
  ctx.fillStyle="#99754c";ctx.fillRect(915,662,20,20);
  // door and little title
  ctx.fillStyle="#694d38";ctx.fillRect(775,686,50,24);
  ctx.fillStyle="#394a3d";ctx.textAlign="center";ctx.font="bold 13px monospace";ctx.fillText("A PLACE THAT'S OURS",800,380);
  ctx.fillStyle="#fff";ctx.font="11px sans-serif";ctx.fillText("E to head back to the street",800,738);
  // only draw a partner who is in this same home
  players.filter(other=>other.id!==player.id && other.inside===player.inside).forEach(other=>{
    ctx.fillStyle="#bd735b";ctx.beginPath();ctx.arc(other.x,other.y,12,0,Math.PI*2);ctx.fill();
    ctx.fillStyle="#26372c";ctx.font="11px sans-serif";ctx.fillText(other.name,other.x,other.y-19);
  });
  ctx.fillStyle="#527e61";ctx.beginPath();ctx.arc(player.x,player.y,12,0,Math.PI*2);ctx.fill();
  ctx.fillStyle="#fff";ctx.font="bold 11px sans-serif";ctx.fillText(player.name.slice(0,1).toUpperCase(),player.x,player.y+4);
  ctx.setTransform(1,0,0,1,0,0);ctx.textAlign="start";
}
function frame(now){
  const dt=Math.min((now-lastFrame)/1000||0,0.05);lastFrame=now;
  if(!ui.game.classList.contains("hidden")){move(dt);drawWorld();}
  requestAnimationFrame(frame);
}
document.querySelector("#createButton").onclick=()=>connect("create");
document.querySelector("#joinButton").onclick=()=>connect("join",ui.code.value.trim().toUpperCase());
document.querySelector("#leaveButton").onclick=()=>{ws?.close();location.reload();};
document.addEventListener("keydown",e=>{
  const key=e.key.toLowerCase();
  if(["w","a","s","d","e","arrowup","arrowdown","arrowleft","arrowright"].includes(key))e.preventDefault();
  if(["w","a","s","d"].includes(key))keys.add(key);
  if(key==="e"&&!e.repeat)interact();
});
document.addEventListener("keyup",e=>keys.delete(e.key.toLowerCase()));
window.addEventListener("blur",()=>keys.clear());
ui.code.addEventListener("input",()=>ui.code.value=ui.code.value.toUpperCase().replace(/[^A-Z0-9]/g,"").slice(0,8));
requestAnimationFrame(frame);
