local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function v(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return v(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return v(a.X/b,a.Y/b,a.Z/b)end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function setup()
 local now=0
 local app={mapId='Map1',mode='MATCH',className='Medic',revision=1,next={},alive=true,rejected={}}
 local cfg={fight=false,autoPlace=true,bossFirst=true,enabled=true}
 local events={};local enum={UserInputType={MouseButton1=1},UserInputState={Begin=1},KeyCode={Unknown=0}}
 local environment=setmetatable({app=app,cfg=cfg,Core={fits=function()return true end},Vector3={new=v},Enum=enum,
  os={clock=function()return now end},RS={},UIS={InputEnded='ended'},player={},classes={},maps={AvailableData={Map1={DisplayName='Skyline'},Map2={DisplayName='Crystal Cave'}}},
  game={PlaceId=87413622775071},workspace={GetAttribute=function()return'Map2'end},
  firesignal=function(signal,token)events[#events+1]={signal=signal,token=token}end},{__index=_G})
 app.root=function()return{Position=v(7,3,0),Size=v(2,2,2)},{HipHeight=2}end
 app.module=function()return{}end;app.find=function()return{}end
 app.note=function()end;app.region=function()return{points={}}end
 app.occupied=function()return false end;app.active=function()return true end
 app.ground=function(x,z,y)return{Position=v(x,y,z)}end
 app.invoke=function(key,remote,...)events[#events+1]={key=key,args={...}};return{ok=true}end
 local spec={facing=2};local slot={name='PulseTurret',spec=spec,w=3,d=3}
 local candidate={key='slot1',slot=slot,point=v(0,0,0),class='Medic',map='Map1',revision=1}
 app.getPlacement=function()return candidate end
 assert(load(extract('    function app.placeTick()', '    function app.weapon()'),'placement','t',environment))()
 assert(load(extract('    function app.fireButton()', '    function app.stopFlight()'),'fire','t',environment))()
 app.fireButton=function()return{InputBegan='begin'}end
 local tool={Parent=true,Deactivate=function()events[#events+1]={signal='deactivate'}end}
 return{app=app,cfg=cfg,env=environment,events=events,candidate=candidate,tool=tool,advance=function(n)now=now+n end}
end
test('placement calls the native type point and facing signature',function()
 local h=setup();h.app.placeTick();assert(#h.events==1)
 local a=h.events[1].args;assert(a[1]=='PulseTurret'and a[2]==h.candidate.point and a[3].Facing==2)
 assert(h.app.pendingPlacements.slot1)
end)
test('a pending boss suppresses placement while fight mode is enabled',function()
 local h=setup();h.app.target={boss=true};h.cfg.fight=true;h.app.placeTick();assert(#h.events==0)
end)
test('a class map or region change cancels a stale placement',function()
 for _,key in ipairs({'class','map','revision'})do
  local h=setup();h.candidate[key]='old';h.app.placeTick();assert(#h.events==0)
 end
end)
test('placement moves into native range before spending currency',function()
 local h=setup();h.app.root=function()return{Position=v(100,30,0),Size=v(2,2,2)},{HipHeight=2}end
 h.app.placeTick();assert(h.app.buildGoal and #h.events==0)
end)
test('full-footprint boundary failure blocks a placement request',function()
 local h=setup();h.env.Core.fits=function()return false end;h.app.placeTick();assert(#h.events==0)
end)
test('placement rejection backs off without disabling auto place',function()
 local h=setup();h.app.invoke=function()return{ok=false,reason='occupied'}end
 h.app.placeTick();assert(h.app.rejected.slot1==8 and h.cfg.autoPlace)
end)
test('automatic guns hold native fire without extra signal spam',function()
 local h=setup();h.app.holdFire(h.tool,{Automatic=true,FireRate=600});h.advance(2);h.app.holdFire(h.tool,{Automatic=true,FireRate=600})
 assert(#h.events==1 and h.events[1].signal=='begin')
end)
test('semi auto repulses after native rate and interaction unlock',function()
 local h=setup();local info={Automatic=false,FireRate=300};h.app.holdFire(h.tool,info);h.advance(.21);h.app.holdFire(h.tool,info)
 assert(not h.app.held);local n=#h.events;h.advance(.05);h.app.holdFire(h.tool,info);assert(#h.events==n)
 h.advance(.1);h.app.holdFire(h.tool,info);assert(h.app.held and h.events[#h.events].signal=='begin')
end)
test('stopping fire releases only the token created by this script',function()
 local h=setup();h.app.holdFire(h.tool,{Automatic=true});local token=h.app.held.token;h.app.releaseFire()
 assert(h.events[2].signal=='ended'and h.events[2].token==token and not h.app.held)
end)
test('missing executor fire signals does not fabricate a damage remote',function()
 local h=setup();h.env.firesignal=false;local text;h.app.note=function(_,value)text=value end
 h.app.holdFire(h.tool,{Automatic=true});assert(not h.app.held and #h.events==0 and text:find('UNSUPPORTED'))
end)
test('actual map detection uses Workspace.MapId not the shared gameplay place',function()
 local h=setup();h.app.data=function()return{}end;h.app.value=function()return'Medic'end
 assert(load(extract('    function app.detect()', '    function app.root()'),'detect','t',h.env))()
 h.app.detect();assert(h.app.mapId=='Map2'and h.app.mapName=='Crystal Cave'and h.app.className=='Medic'and h.app.mode=='MATCH')
end)
test('lobby place detection switches to lobby context',function()
 local h=setup();h.app.data=function()return{}end;h.app.value=function()return'Rookie'end;h.env.game.PlaceId=82457571485380
 assert(load(extract('    function app.detect()', '    function app.root()'),'detect','t',h.env))()
 h.app.detect();assert(h.app.mode=='LOBBY'and h.app.mapId=='Lobby')
end)
test('native mouse mode works without a mobile fire button',function()
 local h=setup();h.cfg.fireInput='Native';h.env.UIS.InputBegan='nativeBegin';h.app.fireButton=function()return nil end
 h.app.holdFire(h.tool,{Automatic=true});assert(h.app.held and h.events[1].signal=='nativeBegin')
end)
print(tests..' movement / placement / input checks passed')
