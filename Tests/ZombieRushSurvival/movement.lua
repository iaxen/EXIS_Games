local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local Core=assert(load(source:sub(1,assert(source:find('-- Runtime adapters.',1,true))-1)..'\nreturn Core'))()
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
V.Dot=function(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
V.Lerp=function(a,b,t)return a+(b-a)*t end
local CF={};CF.__index=CF;CF.__mul=function(a)return a end
local function cf(p)return setmetatable({Position=p,Rotation={}},CF)end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function setup()
 local now=0
 local cfg={fly=true,moveMode='Teleport',clearance=14,flyHeight=14,flySpeed=32,fight=true,autoPlace=true,bossFirst=true,headAim=true,enabled=true}
 local root={Position=vec(-30,3,0),Size=vec(2,2,2),CFrame=cf(vec(-30,3,0)),CollisionGroup='Characters'}
 local human={Health=100,MaxHealth=100,HipHeight=2,MoveTo=function()end}
 local app={alive=true,next={},mode='MATCH',rejected={}}
 local hits,shots,moves,stops=0,0,{},0
 local nav={hull={{x=-50,y=0,z=-50},{x=50,y=0,z=-50},{x=50,y=0,z=50},{x=-50,y=0,z=50}},spawns={},filters={{border=true}}}
 local workspace={CurrentCamera={CFrame=cf(root.Position)}}
 workspace.Blockcast=function(_,frame,size,delta,params)hits=hits+1;workspace.last={frame=frame,size=size,delta=delta,params=params};return nil end
 local env=setmetatable({app=app,cfg=cfg,Core=Core,workspace=workspace,Vector3={new=vec},CFrame={new=cf},
  RaycastParams={new=function()return{}end},Enum={RaycastFilterType={Include='Include'},Material={Water='Water'}},
  os={clock=function()return now end}},{__index=_G})
 app.root=function()return root,human end;app.navigation=function()return nav end
 app.note=function()end;app.enemyRows=function()return{}end
 app.airRisk=function(p)return Core.airRisk({x=p.X,z=p.Z},app.enemyRows(),cfg.clearance)end
 app.airRoute=function(a,b)return Core.escapeRoute({x=a.X,z=a.Z},{x=b.X,z=b.Z},app.enemyRows(),cfg.clearance)end
 assert(load(extract('    function app.inPlayableMap(', '    function app.placementRegion()'),'borders','t',env))()
 assert(load(extract('    function app.routeHop(', '    function app.resolveSurface()'),'routing','t',env))()
 assert(load(extract('    function app.move(', '    function app.enemyRows()'),'move','t',env))()
 assert(load(extract('    function app.flightPoint(', '    function app.safeAirGoal('),'ground','t',env))()
 assert(load(extract('    function app.combatTick(', '    function app.aimTick()'),'combat','t',env))()
 app.ensureFlight=function()app.flight=app.flight or{velocity={VectorVelocity=vec(0,0,0)}}end
 app.stopFlight=function()stops=stops+1;app.flight=nil end
 app.mapFilters=function()return{}end;app.active=function()return cfg.enabled end
 app.raycast=function()return nil end;app.releaseFire=function()end
 return{app=app,cfg=cfg,root=root,human=human,env=env,nav=nav,world=workspace,
  advance=function(t)now=now+t end,hits=function()return hits end,stops=function()return stops end}
end
test('checked teleport cannot leave the native spawn-area hull',function()
 local h=setup();local before=h.root.CFrame;h.app.move(vec(80,10,0),.02);assert(h.root.CFrame==before)
end)
test('checked teleport cannot cross a player-blocking border wall',function()
 local h=setup();h.world.Blockcast=function()return{Normal=vec(-1,0,0)}end
 local before=h.root.CFrame;h.app.move(vec(30,10,0),.02);assert(h.root.CFrame==before)
end)
test('clear teleport uses a checked destination and keeps hover between hops',function()
 local h=setup();local goal=vec(-20,10,0);h.app.move(goal,.02)
 assert(h.root.CFrame.Position==goal and h.app.flight and h.app.flight.velocity.VectorVelocity.Magnitude==0)
 assert(h.root.AssemblyLinearVelocity.Magnitude==0)
end)
test('teleport cannot take a clear-ended route over a swarm',function()
 local h=setup();h.app.enemyRows=function()return{{x=0,z=0,range=3}}end
 local before=h.root.CFrame;h.app.move(vec(30,20,0),.02);assert(h.root.CFrame==before)
end)
test('physical route checks sweep character size with the real collision group',function()
 local h=setup();h.app.travelHit(vec(0,3,0),vec(10,0,0));local q=h.world.last
 assert(q.size.X==3 and q.size.Y==4 and q.params.RespectCanCollide and q.params.CollisionGroup=='Characters')
 assert(q.params.FilterDescendantsInstances==h.nav.filters)
end)
test('flight destinations need playable ground support',function()
 local h=setup();assert(h.app.flightPoint(vec(70,5,0))==nil)
 assert(h.app.flightPoint(vec(10,5,0))==nil)
end)
test('flight height fits under a cave ceiling instead of flying into it',function()
 local h=setup();local n=0;h.app.raycast=function()n=n+1;if n==1 then return{Position=vec(10,0,0),Normal=vec(0,1,0),Material='Concrete'}end;return{Position=vec(10,10,0)}end
 local goal=h.app.flightPoint(vec(10,4,0));assert(goal and goal.Y==6.5)
end)
test('a stale blocked placement approach is released rather than held forever',function()
 local h=setup();h.app.routeHop=function()return nil end;h.app.placementTask={key='slot1'}
 h.app.move(vec(20,5,0),.02);h.advance(1.1);h.app.move(vec(20,5,0),.02)
 assert(not h.app.placementTask and h.app.rejected.slot1>1.1)
end)
test('combat keeps moving and firing while the replica selector is open',function()
 local h=setup();h.app.editing=true;local model={Parent=true};h.app.target={model=model,boss=false}
 local point=vec(-10,3,0);h.app.head=function()return point end
 h.app.weapon=function()return{},{}end;h.app.reload=function()return false end
 h.app.orbitGoal=function()return vec(-20,15,10)end
 local moved,fired=0,0;h.app.move=function()moved=moved+1 end;h.app.holdFire=function()fired=fired+1 end
 h.app.buildGoal=vec(1,3,1);h.app.combatTick(.02)
 assert(moved==1 and fired==1 and h.app.editing and h.cfg.fight)
end)
test('movement and firing stop when both task toggles are off even inside danger',function()
 local h=setup();h.cfg.fight=false;h.cfg.autoPlace=false;h.app.airRisk=function()return 100 end
 h.app.flight={velocity={VectorVelocity=vec(30,0,0)}};h.app.combatTick(.02);assert(not h.app.flight and h.stops()==1)
end)
test('taking damage invalidates the old orbit and changes the relocation direction',function()
 local h=setup();h.app.observedHealth=100;h.human.Health=90;h.app.airGoal={point=vec(1,2,3)}
 h.app.orbitGoal=function()return nil end;h.app.move=function()end;h.app.combatTick(.02)
 assert(not h.app.airGoal and h.app.orbitDirection==-1 and h.app.damageEvadeUntil>0)
end)
test('smooth flight changes velocity without an instant position jump',function()
 local h=setup();h.cfg.moveMode='Smooth';local before=h.root.CFrame;h.app.move(vec(-20,10,0),.02)
 assert(h.root.CFrame==before and h.app.flight.velocity.VectorVelocity.Magnitude>0)
end)
test('a blocked direct route can use a clear supported map waypoint',function()
 local h=setup();h.nav.spawns={{point=vec(-30,0,30)}}
 h.app.flightPoint=function(p)return vec(p.X,10,p.Z)end
 h.app.travelHit=function(a,d)
  local b=a+d
  if math.abs(a.Z)<1 and math.abs(b.Z)<1 and a.X<0 and b.X>0 then return{}end
 end
 local hop=h.app.routeHop(vec(30,10,0));assert(hop and hop.Z==30 and hop.X==-30)
end)
test('danger never turns a disabled auto-fight option back on',function()
 local h=setup();h.cfg.fight=false;h.cfg.autoPlace=true;h.app.airRisk=function()return 100 end
 local shots=0;h.app.orbitGoal=function()return nil end;h.app.move=function()end;h.app.holdFire=function()shots=shots+1 end
 h.app.combatTick(.02);assert(not h.cfg.fight and shots==0)
end)
print(tests..' playable-space movement and live-editor combat checks passed')
