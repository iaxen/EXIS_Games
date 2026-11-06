local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local core=assert(load(source:sub(1,assert(source:find('-- Runtime adapters.',1,true))-1)..'\nreturn Core'))()
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function node(class,value,children)
 local n={class=class,Value=value,children=children or{},Parent=true}
 n.IsA=function(self,c)return self.class==c or(c=='ValueBase'and self.class:find('Value')~=nil)end
 n.FindFirstChild=function(self,key)return self.children[key]end
 n.GetChildren=function(self)local out={}for name,c in pairs(self.children)do c.Name=name;out[#out+1]=c end return out end
 return n
end
local function setup()
 local now,requests=0,{}
 local cfg={enabled=true,reserveCash=0,buyClasses={},upgradeClasses={},buyWeapons={},upgradeWeapons={},loadout={},autoLoadout=false,bossFirst=true}
 local data=node('Folder',nil,{Stats=node('Folder',nil,{Cash=node('IntValue',1000),Zombux=node('IntValue',1000)}),
  Classes=node('Folder',nil,{Equipped=node('StringValue','Rookie'),Owned=node('Folder',nil,{Rookie=node('BoolValue',true)}),DeployableLevels=node('Folder')}),
  Weapons=node('Folder'),CurrentLoadout=node('Folder',nil,{TierSlots=node('Folder',nil,{Tier1=node('StringValue','Pistol')})})})
 local remote=node('RemoteFunction')
 local events=node('Folder',nil,{Actions=node('Folder',nil,{PurchaseUpgrade=remote}),Communication=node('Folder',nil,{AutoSkipToggle=remote})})
 local RS=node('Folder',nil,{ClientData=node('Folder',nil,{Tester=data}),ClassSystem_Remotes=node('Folder',nil,{Request=remote}),WeaponProgression_Remotes=node('Folder',nil,{Request=remote}),Events=events})
 local classes={Order={'Rookie','Medic'},DefaultClass='Rookie',Get=function(name)return{Price=name=='Medic'and 500 or 0}end,
 GetPrice=function(row)return'Zombux',row.Price end,IsPurchasable=function()return true end,GetDeployableSlots=function()return{'AutoTurret','Barricade'}end}
 local deployUpgrades={IsAtMaxLevel=function(_,level)return level>=3 end,GetPrice=function()return'Zombux',100 end}
 local progression={MaxWeaponLevel=2,WeaponPrices={Pistol=100,Shotgun=500},WeaponTiers={{Weapons={'Pistol'}},{Weapons={'Shotgun'}}},
 GetWeaponPrice=function(name)return'Zombux',name=='Pistol'and 100 or 500 end,GetWeaponUpgradePrice=function()return'Zombux',200 end}
 local upgrades={Types={Health={},PurchaseWeaponTierUpgrade={},MeleeUpgrade={}},WeaponTierUpgradeTypeName='PurchaseWeaponTierUpgrade',MeleeUpgradeTypeName='MeleeUpgrade',
 GetPlayerLevel=function()return 0 end,IsAtMaxLevel=function()return false end,GetPrice=function()return'Cash',100 end}
 local env=setmetatable({Core=core,app={alive=true,next={},notes={},cache={},className='Rookie',mode='LOBBY',mapId='Lobby'},cfg=cfg,RS=RS,
  classes=classes,deployUpgrades=deployUpgrades,progression=progression,modules={},player={Name='Tester'},
  os={clock=function()return now end},warn=function()end,pg=node('Folder')},{__index=_G})
 local app=env.app
 assert(load(extract('    function app.find(', '    function app.module('),'helpers','t',env))()
 assert(load(extract('    function app.ownedClass(', '    function app.region()'),'adapters','t',env))()
 app.note=function(k,v)app.notes[k]=v end
 app.module=function()return upgrades end
 app.root=function()return{}, {Health=100,MaxHealth=100}end
 app.active=function()return true end
 app.invoke=function(key,r,...)
  requests[#requests+1]={key=key,args={...}};app.next[key]=now+1
  return {ok=true}
 end
 return{env=env,app=app,cfg=cfg,data=data,RS=RS,classes=classes,upgrades=upgrades,requests=requests,
  advance=function(n)now=now+n end,node=node}
end

test('fair shuffle gives every continuously ready job one turn before repeating',function()
 local state,keys={}, {'place:Turret','place:Wall','health','gun','melee'}
 for cycle=1,4 do
  local seen={}
  for i=1,#keys do local key=core.fairChoice(state,keys);assert(not seen[key]);seen[key]=true;core.finishChoice(state,key)end
 end
end)
test('disabled jobs are pruned and newly ready jobs join the mixed cycle',function()
 local state={};local key=core.fairChoice(state,{'gun','health'},function()return 1 end);assert(key=='gun');core.finishChoice(state,key)
 assert(core.fairChoice(state,{'health','place:Turret'},function(a,b)return b end)=='place:Turret')
 core.finishChoice(state,'place:Turret');assert(core.fairChoice(state,{'health'})=='health')
end)
test('zombie danger is horizontal and height never makes a swarm column safe',function()
 local mobs={{x=0,z=0,range=3}}
 assert(core.airRisk({x=0,z=0,y=500},mobs,14)>0)
 assert(core.airRisk({x=30,z=0,y=0},mobs,14)==0)
end)
test('routes with clear endpoints cannot cross above a swarm',function()
 local mobs={{x=0,z=0,range=3}}
 assert(not core.airRoute({x=-30,z=0},{x=30,z=0},mobs,14))
 assert(core.airRoute({x=-30,z=20},{x=30,z=20},mobs,14))
end)
test('escape can move away from an existing crowd but cannot cross through it',function()
 local mobs={{x=0,z=0,range=3}}
 assert(core.escapeRoute({x=-5,z=0},{x=-30,z=0},mobs,14))
 assert(not core.escapeRoute({x=-5,z=0},{x=30,z=0},mobs,14))
end)
test('boss attack range expands clearance beyond the configured minimum',function()
 assert(core.airRisk({x=30,z=0},{{x=0,z=0,range=35}},14)>0)
 assert(core.airRisk({x=40,z=0},{{x=0,z=0,range=35}},14)==0)
end)
test('spawn hull contains the playable points without accepting distant outside terrain',function()
 local p={{x=0,y=0,z=0},{x=40,y=0,z=0},{x=40,y=0,z=40},{x=0,y=0,z=40},{x=20,y=0,z=20}}
 local hull=core.hull(p);assert(#hull==4);assert(core.inside({x=20,z=20},hull));assert(not core.inside({x=70,z=20},hull))
end)
test('automatic spawn-area layout is clipped inside the playable hull',function()
 local hull=core.hull({{x=0,y=0,z=0},{x=40,y=0,z=0},{x=40,y=0,z=40},{x=0,y=0,z=40}})
 local rect={{x=-10,y=0,z=-10},{x=30,y=0,z=-10},{x=30,y=0,z=30},{x=-10,y=0,z=30}}
 local poly=core.clipPolygon(rect,hull);assert(core.validPolygon(poly))
 for _,p in ipairs(poly)do assert(core.inside(p,hull))end
end)
test('viewport pixel rays honor aspect ratio and reject clicks outside the replica',function()
 local x,y,z=core.mapPixelDirection(320,200,640,400,50);assert(x==0 and y==0 and z==-1)
 assert(core.mapPixelDirection(-1,0,640,400,50)==nil)
 local right=core.mapPixelDirection(640,200,640,400,50);assert(right>0)
end)
test('first affordable turret is placed before ordinary upgrades',function()
 local h=setup();h.cfg.autoPlace=true;h.cfg.gun=true;h.cfg.health=true
 h.app.turretEstablished=function()return false end
 h.app.getPlacement=function(role,allow)assert(role=='turret'and allow);return{affordable=true,slot={role='turret'}}end
 local placed=0;h.app.placeTick=function()placed=placed+1;return true end
 h.app.matchTick();assert(placed==1 and #h.requests==0)
end)
test('cash is reserved for the first eligible turret instead of spent on upgrades',function()
 local h=setup();h.cfg.autoPlace=true;h.cfg.gun=true
 h.app.turretEstablished=function()return false end
 h.app.getPlacement=function()return{affordable=false,slot={role='turret'}}end
 h.app.placeTick=function()error('cannot place without cash')end
 h.app.matchTick();assert(#h.requests==0 and h.app.notes.economy:find('SAVING'))
end)
test('low health remains an urgent exception to the initial turret order',function()
 local h=setup();h.cfg.autoPlace=true;h.cfg.health=true;h.app.root=function()return{},{Health=10,MaxHealth=100}end
 h.app.turretEstablished=function()error('health should run first')end
 h.app.matchTick();assert(h.requests[1].args[1]=='Health')
end)
test('an accepted placement finishes its approach before another ordinary job interrupts',function()
 local h=setup();h.cfg.autoPlace=true;h.cfg.gun=true;h.app.turretEstablished=function()return true end
 local pending={slot={role='wall'}};h.app.placementTask=pending;h.app.placeTick=function()return nil end
 h.app.matchTick();assert(h.app.placementTask==pending and #h.requests==0)
end)
test('boss combat prevents placement approaches while upgrades can still run',function()
 local h=setup();h.cfg.autoPlace=true;h.cfg.gun=true;h.cfg.fight=true;h.app.target={boss=true}
 h.app.getPlacement=function()error('no placement during boss engagement')end
 h.app.matchTick();assert(h.requests[1].args[1]=='PurchaseWeaponTierUpgrade')
end)
print(tests..' smart scheduling and route-geometry checks passed')
