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
 local human={Health=100,MaxHealth=100,HipHeight=2};human.MoveTo=function(_,goal)human.goal=goal end
 local app={alive=true,next={},mode='MATCH',rejected={}}
 local hits,shots,moves,stops=0,0,{},0
 local nav={hull={{x=-50,y=0,z=-50},{x=50,y=0,z=-50},{x=50,y=0,z=50},{x=-50,y=0,z=50}},spawns={},filters={{border=true}}}
 local workspace={CurrentCamera={CFrame=cf(root.Position)}}
 workspace.FindFirstChild=function()return nil end
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
 app.groundRoute=function()return true end
 app.turretAnchor=function()return nil end
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
test('legacy teleport settings still use grounded native walking',function()
 local h=setup();local goal=vec(-20,10,0);h.app.move(goal,.02)
 assert(h.root.CFrame.Position.X==-30 and h.human.goal==goal and not h.app.flight)
end)
test('teleport cannot take a clear-ended route over a swarm',function()
 local h=setup();h.app.enemyRows=function()return{{x=0,z=0,range=3}}end
 local before=h.root.CFrame;h.app.move(vec(30,20,0),.02);assert(h.root.CFrame==before)
end)
test('physical route checks sweep character size with the real collision group',function()
 local h=setup();h.app.travelHit(vec(0,3,0),vec(10,0,0));local q=h.world.last
 assert(q.size.X==3 and q.size.Y==4 and q.params.RespectCanCollide and q.params.CollisionGroup=='Characters')
 assert(q.params.FilterDescendantsInstances[1]==h.nav.filters[1])
end)
test('ground destinations need playable floor support',function()
 local h=setup();assert(h.app.flightPoint(vec(70,5,0))==nil)
 assert(h.app.flightPoint(vec(10,5,0))==nil)
end)
test('movement point stays at native standing height under a cave ceiling',function()
 local h=setup();h.app.raycast=function(origin)return{Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material='Concrete'}end
 local goal=h.app.flightPoint(vec(10,4,0));assert(goal and goal.Y==3)
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
test('smooth movement walks without flight constraints or position jumps',function()
 local h=setup();h.cfg.moveMode='Smooth';local before=h.root.CFrame;h.app.move(vec(-20,10,0),.02)
 assert(h.root.CFrame==before and not h.app.flight and h.human.goal)
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
test('ground route rejects holes water steep surfaces and excessive drops',function()
 for _,mode in ipairs({'hole','water','slope','drop'})do
  local h=setup()
  assert(load(extract('    function app.groundRoute(', '    function app.placementRegion()'),'support','t',h.env))()
  h.app.raycast=function(origin)
   if origin.X>4 then
    if mode=='hole'then return nil end
    return{Position=vec(origin.X,mode=='drop'and -10 or 0,origin.Z),Normal=vec(0,mode=='slope'and .2 or 1,0),Material=mode=='water'and'Water'or'Concrete'}
   end
   return{Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material='Concrete'}
  end
  assert(not h.app.groundRoute(vec(0,3,0),vec(12,3,0)),mode)
 end
end)
test('safe ground support queries are cached and bounded',function()
 local h=setup();local queries=0
 assert(load(extract('    function app.groundRoute(', '    function app.placementRegion()'),'support','t',h.env))()
 h.app.raycast=function(origin)queries=queries+1;return{Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material='Concrete'}end
 assert(h.app.groundRoute(vec(0,3,0),vec(12,3,0)));local initial=queries
 assert(h.app.groundRoute(vec(0,3,0),vec(12,3,0))and queries==initial)
 assert(not h.app.groundRoute(vec(0,3,0),vec(200,3,0))and queries==initial)
end)
local function groundPlanner()
 local h=setup();h.root.Position=vec(0,3,0)
 assert(load(extract('    function app.safeAirGoal(', '    function app.combatTick('),'ground-plan','t',h.env))()
 h.cfg.turretLeash=20;h.app.flightPoint=function(p)return vec(p.X,3,p.Z)end
 h.app.routeHop=function(p)return p end
 return h
end
test('safe player holds inside turret coverage instead of orbiting the zombies',function()
 local h=groundPlanner();h.root.Position=vec(10,3,0)
 h.app.turretAnchor=function()return{point=vec(0,3,0),radius=20}end
 assert(h.app.safeAirGoal()==h.root.Position)
end)
test('outside player returns to turret coverage using a safe candidate',function()
 local h=groundPlanner();h.root.Position=vec(45,3,0)
 h.app.turretAnchor=function()return{point=vec(0,3,0),radius=20}end
 local point=h.app.safeAirGoal();assert(point and math.sqrt(point.X^2+point.Z^2)<=20.01)
end)
test('dodge never crosses a swarm just to stay beside the turret',function()
 local h=groundPlanner();h.app.turretAnchor=function()return{point=vec(0,3,0),radius=20}end
 h.app.airRisk=function(p)return math.abs(p.X)<5 and 100 or 0 end
 h.app.routeHop=function(p)if p.X<0 then return p end end
 local point=h.app.safeAirGoal();assert(point and point.X<0 and h.app.airRisk(point)==0)
end)
test('no turret and no threat means no aimless movement',function()
 local h=groundPlanner();h.app.turretAnchor=function()return nil end
 assert(h.app.safeAirGoal()==h.root.Position)
end)
test('stopping automation cancels an outstanding native walk',function()
 local h=setup();h.app.walkGoal=vec(10,3,0);h.cfg.fight,h.cfg.autoPlace=false,false
 h.app.combatTick(.02);assert(h.human.goal==h.root.Position and not h.app.walkGoal)
end)
test('movement commands are throttled while safety is rechecked every tick',function()
 local h=setup();local commands=0;h.human.MoveTo=function()commands=commands+1 end
 local goal=vec(-20,3,0);h.app.move(goal,.02);h.app.move(goal,.02);assert(commands==1)
 h.advance(.21);h.app.move(goal,.02);assert(commands==2)
end)
test('turret anchor favors nearby owned live turrets and respects coverage range',function()
 local h=setup();h.root.Position=vec(0,3,0);h.cfg.turretLeash=20
 h.env.player={UserId=1};h.env.defs={Types={AutoTurret={Targeting={Range=42}}}}
 local function turret(x,owner,dead)
  local attrs={TypeName='AutoTurret',OwnerUserId=owner,Destroyed=dead,Health=100}
  return{Parent=true,PrimaryPart={Position=vec(x,0,0)},IsA=function(_,kind)return kind=='Model'end,GetAttribute=function(_,key)return attrs[key]end}
 end
 local own,ally,dead=turret(10,1),turret(5,2),turret(1,1,true)
 h.world.FindFirstChild=function()return{GetChildren=function()return{dead,ally,own}end}end
 assert(load(extract('    function app.turretAnchor(', '    function app.safeAirGoal('),'turrets','t',h.env))()
 local chosen=h.app.turretAnchor();assert(chosen.model==own and chosen.radius==20)
 own.Parent=nil;h.world.FindFirstChild=function()return{GetChildren=function()return{dead,ally}end}end
 assert(h.app.turretAnchor().model==ally)
end)
test('turret disappearance or destruction cannot retain a stale fight anchor',function()
 local h=setup();h.root.Position=vec(0,3,0);h.env.player={UserId=1};h.env.defs={Types={}}
 h.app.turretCache={untilTime=99,model={Parent=true,GetAttribute=function(_,k)return k=='Destroyed'and true or 0 end}}
 assert(load(extract('    function app.turretAnchor(', '    function app.safeAirGoal('),'turrets','t',h.env))()
 assert(h.app.turretAnchor()==nil)
end)
test('a selected building floor outside the spawn hull is allowed only for its active approach',function()
 local h=setup();h.app.buildGoal=vec(80,3,0)
 h.app.placementRegion=function()return{points={{x=60,y=0,z=-20},{x=100,y=0,z=-20},{x=100,y=0,z=20},{x=60,y=0,z=20}}}end
 assert(h.app.inPlayableMap(vec(80,3,0)))
 assert(not h.app.inPlayableMap(vec(110,3,0)))
 assert(not h.app.inPlayableMap(vec(80,30,0)))
 h.app.buildGoal=nil;assert(not h.app.inPlayableMap(vec(80,3,0)))
end)
test('a destination cannot fall from a roof to distant lower terrain',function()
 local h=setup();h.root.Position=vec(0,33,0)
 h.app.raycast=function(origin,direction,filters,solid)
  assert(direction.Y>=-12 and solid==true)
  return{Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material='Concrete'}
 end
 assert(h.app.flightPoint(vec(20,33,0))==nil)
end)
test('walking routes reject unsupported shoulders even with floor beneath the centerline',function()
 local h=setup()
 assert(load(extract('    function app.groundRoute(', '    function app.placementRegion()'),'route','t',h.env))()
 h.app.raycast=function(origin)
  if origin.Z>1 then return nil end
  return{Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material='Concrete'}
 end
 assert(not h.app.groundRoute(vec(0,3,0),vec(12,3,0)))
end)
test('an unsafe blocked route cancels horizontal momentum while preserving gravity',function()
 local h=setup();h.root.AssemblyLinearVelocity=vec(24,-5,0);h.app.routeHop=function()return nil end
 h.app.move(vec(20,3,0),.02)
 assert(h.root.AssemblyLinearVelocity.X==0 and h.root.AssemblyLinearVelocity.Y==-5)
end)
test('support rays require collidable terrain in the real character collision group',function()
 local h=setup();local captured
 h.env.player={Character={}}
 h.world.Raycast=function(_,origin,direction,params)captured=params;return nil end
 assert(load(extract('    function app.raycast(', '    function app.stopMapView()'),'raycast','t',h.env))()
 h.app.raycast(vec(0,5,0),vec(0,-9,0),{{floor=true}},true)
 assert(captured.RespectCanCollide and captured.CollisionGroup=='Characters')
end)
test('long walking corridors bound their physical support query count',function()
 local h=setup();local queries=0
 assert(load(extract('    function app.groundRoute(', '    function app.placementRegion()'),'route','t',h.env))()
 h.app.raycast=function(origin)queries=queries+1;return{Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material='Concrete'}end
 assert(h.app.groundRoute(vec(0,3,0),vec(128,3,0))and queries<=210)
end)
print(tests..' playable-space movement and live-editor combat checks passed')
