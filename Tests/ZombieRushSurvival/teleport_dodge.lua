local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local Core=assert(load(source:sub(1,assert(source:find('-- Runtime adapters.',1,true))-1)..'\nreturn Core'))()
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local V={};V.__index=function(p,k)if k=='Magnitude'then return math.sqrt(p.X*p.X+p.Y*p.Y+p.Z*p.Z)end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
local CF={};CF.__mul=function(a)return a end
local function frame(p)return setmetatable({Position=p,Rotation={}},CF)end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function setup()
 local now,teleports,commands=0,0,0
 local props={Position=vec(0,3,0),Size=vec(2,2,2),CFrame=frame(vec(0,3,0)),CollisionGroup='Characters'}
 local root=setmetatable({},{__index=props,__newindex=function(_,key,value)props[key]=value;if key=='CFrame'then props.Position=value.Position;teleports=teleports+1 end end})
 local human={Health=100,MaxHealth=100,HipHeight=2,GetState=function()return'Running'end,MoveTo=function()commands=commands+1 end}
 local cfg={enabled=true,fight=true,dodgeTeleport=true,dodgeClearance=35,dodgeInterval=.3}
 local app={next={},alive=true,dodgeHistory={}}
 local mobs={{x=0,z=0,range=3,vx=0,vz=0}}
 local hull={{x=-100,y=0,z=-100},{x=100,y=0,z=-100},{x=100,y=0,z=100},{x=-100,y=0,z=100}}
 app.root=function()return root,human end;app.active=function()return cfg.enabled end
 app.enemyRows=function()return mobs end
 app.inPlayableMap=function(p)return Core.inside({x=p.X,z=p.Z},hull)end
 app.navigation=function()return{hull=hull,spawns={{point=vec(80,3,80)},{point=vec(-80,3,-80)}},filters={{map=true}}}end
 app.turretAnchor=function()return{point=vec(0,3,0),radius=20}end
 app.note=function(key,text)app.noteText=text end
 local env=setmetatable({app=app,cfg=cfg,Core=Core,Vector3={new=vec},CFrame={new=frame},
  Enum={HumanoidStateType={Physics='Physics',Ragdoll='Ragdoll',Dead='Dead'},RaycastFilterType={Include='Include'},Material={Water='Water'}},
  os={clock=function()return now end}},{__index=_G})
 assert(load(extract('    function app.teleportDodgeTick()', '    function app.combatTick('),'dodge','t',env))()
 app.teleportLanding=function(p)return vec(p.X,3,p.Z)end
 return{app=app,cfg=cfg,root=root,human=human,env=env,mobs=mobs,
  advance=function(dt)now=now+dt end,teleports=function()return teleports end,commands=function()return commands end}
end

test('ground TP leaves a crowded turret and prefers thirty to forty studs of clearance',function()
 local h=setup();assert(h.app.teleportDodgeTick())
 local p=h.root.Position;local clearance=Core.teleportClearance({x=p.X,z=p.Z},h.mobs,.3)
 assert(clearance>=35 and math.sqrt(p.X*p.X+p.Z*p.Z)>20 and p.Y==3)
 assert(h.teleports()==1 and h.commands()==1 and h.root.AssemblyLinearVelocity.Magnitude==0)
end)
test('Fight keeps relocating instead of camping one previously safe spot',function()
 local h=setup();assert(h.app.teleportDodgeTick());local old=h.root.Position
 h.advance(.31);assert(h.app.teleportDodgeTick()and(h.root.Position-old).Magnitude>=10 and h.teleports()==2)
end)
test('ordinary teleports obey the selected interval while threat checks keep running',function()
 local h=setup();assert(h.app.teleportDodgeTick());h.advance(.11)
 assert(not h.app.teleportDodgeTick()and h.teleports()==1)
end)
test('a new close threat can trigger an emergency relocation before the ordinary cooldown',function()
 local h=setup();assert(h.app.teleportDodgeTick())
 h.mobs[1].x,h.mobs[1].z=h.root.Position.X,h.root.Position.Z
 h.advance(.13);assert(h.app.teleportDodgeTick()and h.teleports()==2)
end)
test('a small opening can be used when it still lies outside native attack reach',function()
 local h=setup();h.app.inPlayableMap=function(p)return math.abs(p.X-12)<.01 and math.abs(p.Z)<.01 end
 assert(h.app.teleportDodgeTick());assert(math.abs(h.root.Position.X-12)<.01)
end)
test('boss reach prevents choosing an opening that is empty but still within its attack radius',function()
 local h=setup();h.mobs[1].range=40
 h.app.inPlayableMap=function(p)return math.abs(p.X-12)<.01 and math.abs(p.Z)<.01 end
 assert(not h.app.teleportDodgeTick()and h.teleports()==0)
end)
test('motion prediction rejects a point a fast incoming zombie will reach during the dodge interval',function()
 local clear,margin=Core.teleportClearance({x=12,z=0},{{x=0,z=0,vx=30,vz=0,range=3}},.3)
 assert(clear==3 and margin<0)
end)
test('an enemy arriving during destination validation cancels the teleport',function()
 local h=setup();local landing
 h.app.teleportLanding=function(p)landing=p;return vec(p.X,3,p.Z)end
 h.app.enemyRows=function()return landing and{{x=landing.X,z=landing.Z,range=3}}or h.mobs end
 assert(not h.app.teleportDodgeTick()and h.teleports()==0)
end)
test('blocked landings are skipped and temporarily rejected instead of repeatedly occupying a wall',function()
 local h=setup();h.app.teleportLanding=function()return nil end
 assert(not h.app.teleportDodgeTick()and h.teleports()==0 and next(h.app.dodgeRejected))
end)
test('paused off anchored and ragdolled states cannot issue teleport movement',function()
 for _,mode in ipairs({'paused','off','anchor','ragdoll','seat'})do
  local h=setup()
  if mode=='paused'then h.cfg.enabled=false elseif mode=='off'then h.cfg.fight=false elseif mode=='anchor'then h.root.Anchored=true
  elseif mode=='seat'then h.human.Sit=true else h.human.GetState=function()return'Ragdoll'end end
  assert(not h.app.teleportDodgeTick()and h.teleports()==0,mode)
 end
end)
test('no enemies means no needless teleports while a safe build destination can still progress',function()
 local h=setup();h.mobs[1]=nil;assert(not h.app.teleportDodgeTick())
 h.app.buildGoal=vec(20,3,20);h.advance(.11);assert(h.app.teleportDodgeTick()and h.root.Position.X==20 and h.root.Position.Z==20)
end)
local function landingHarness()
 local h=setup();local world={parts={},FindFirstChild=function()return nil end}
 world.GetPartBoundsInBox=function(_,cf,size,params)world.last={cf=cf,size=size,params=params};return world.parts end
 h.env.workspace=world;h.env.OverlapParams={new=function()return{}end}
 h.app.flightPoint=function(p)return p end;h.app.mapFilters=function()return{{floor=true}}end
 h.app.raycast=function(origin)return{Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material='Concrete'}end
 assert(load(extract('    function app.teleportLanding(', '    function app.teleportDodgeTick()'),'landing','t',h.env))()
 h.world=world;return h
end
test('ground landings check a body volume with the player collision group',function()
 local h=landingHarness();local p=vec(20,3,20);assert(h.app.teleportLanding(p)==p)
 assert(h.world.last.size.X==3 and h.world.last.size.Y==4 and h.world.last.params.CollisionGroup=='Characters')
 h.world.parts={{CanCollide=true}};assert(not h.app.teleportLanding(p))
end)
test('holes water ledges and steep support cannot become a teleport destination',function()
 for _,mode in ipairs({'hole','water','ledge','steep'})do
  local h=landingHarness()
  h.app.raycast=function(origin)
   if mode=='hole'then return nil end
   return{Position=vec(origin.X,mode=='ledge'and -8 or 0,origin.Z),Normal=vec(0,mode=='steep'and .2 or 1,0),Material=mode=='water'and'Water'or'Concrete'}
  end
  assert(not h.app.teleportLanding(vec(20,3,20)),mode)
 end
end)
test('teleport combat continues firing and does not resume the obsolete turret walk',function()
 local h=setup();local calls={tp=0,walk=0,fire=0}
 h.app.mode='MATCH';h.cfg.autoPlace=true;h.cfg.bossFirst=true
 h.app.target={model={Parent=true},boss=false};h.app.buildGoal=vec(20,3,20)
 h.app.teleportDodgeTick=function()calls.tp=calls.tp+1 end
 h.app.stopWalk=function()end;h.app.releaseFire=function()error('should keep firing with a target')end
 h.app.stopFlight=function()end;h.app.move=function()calls.walk=calls.walk+1 end
 h.app.weapon=function()return{},{}end;h.app.reload=function()return false end;h.app.head=function()return vec(1,3,1)end
 h.env.workspace={CurrentCamera={CFrame=frame(vec(0,3,0))}}
 h.app.raycast=function()return nil end;h.app.mapFilters=function()return{}end
 h.app.holdFire=function()calls.fire=calls.fire+1 end
 assert(load(extract('    function app.combatTick(', '    function app.aimTick()'),'combat','t',h.env))()
 h.app.combatTick(.02);assert(calls.tp==1 and calls.walk==0 and calls.fire==1)
end)
print(tests..' simulated ground teleport, landing, prediction and firing checks passed')
