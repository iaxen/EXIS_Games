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
test('class buying uses native PurchaseAndEquip and restores the original class',function()
 local h=setup();h.cfg.buyClasses.Medic=true;assert(h.app.classTick())
 assert(h.requests[1].args[1]=='PurchaseAndEquip'and h.requests[1].args[2]=='Medic')
 assert(h.requests[2].args[1]=='Equip'and h.requests[2].args[2]=='Rookie')
end)
test('class purchase selection and ownership are respected',function()
 local h=setup();assert(not h.app.classTick()and #h.requests==0)
 h.cfg.buyClasses.Medic=true;h.data.children.Classes.children.Owned.children.Medic=node('BoolValue',true)
 assert(not h.app.classTick()and #h.requests==0)
end)
test('insufficient lobby currency does not send a buy request',function()
 local h=setup();h.cfg.buyClasses.Medic=true;h.data.children.Stats.children.Zombux.Value=10
 assert(not h.app.classTick()and #h.requests==0)
end)
test('class upgrades use class and deployable as separate native arguments',function()
 local h=setup();h.cfg.upgradeClasses.Rookie=true;assert(h.app.classTick())
 local a=h.requests[1].args;assert(a[1]=='UpgradeDeployable'and a[2]=='Rookie'and a[3]=='AutoTurret')
end)
test('unowned classes and maximum defense levels are not upgraded',function()
 local h=setup();h.cfg.upgradeClasses.Medic=true;assert(not h.app.classTick())
 h.cfg.upgradeClasses.Rookie=true;h.data.children.Classes.children.DeployableLevels.children.AutoTurret=node('IntValue',3)
 h.data.children.Classes.children.DeployableLevels.children.Barricade=node('IntValue',3)
 assert(not h.app.classTick())
end)
test('weapon auto purchase uses only selected missing weapons',function()
 local h=setup();h.cfg.buyWeapons.Shotgun=true;assert(h.app.weaponTick())
 local a=h.requests[1].args;assert(a[1]=='Purchase'and a[2]=='Shotgun')
end)
test('weapon upgrade reads its individual owned level',function()
 local h=setup();h.cfg.upgradeWeapons.Pistol=true
 h.data.children.Weapons.children.Pistol=node('Folder',nil,{Level=node('IntValue',1)})
 assert(h.app.weaponTick());assert(h.requests[1].args[1]=='Upgrade'and h.requests[1].args[2]=='Pistol')
end)
test('a max-level weapon does not keep purchasing upgrades',function()
 local h=setup();h.cfg.upgradeWeapons.Pistol=true
 h.data.children.Weapons.children.Pistol=node('Folder',nil,{Level=node('IntValue',2)})
 assert(not h.app.weaponTick()and #h.requests==0)
end)
test('weapon choice equips the selected tier slot without buying an unselected item',function()
 local h=setup();h.cfg.autoLoadout=true;h.cfg.loadout['2']='Shotgun'
 h.data.children.Weapons.children.Shotgun=node('Folder',nil,{Level=node('IntValue',1)})
 assert(h.app.weaponTick());local a=h.requests[1].args;assert(a[1]=='EquipWeaponInSlot'and a[2]=='Shotgun'and a[3]==2)
end)
test('tier selection waits for ownership rather than buying implicitly',function()
 local h=setup();h.cfg.autoLoadout=true;h.cfg.loadout['2']='Shotgun';assert(not h.app.weaponTick())
end)
test('cash reserve is enforced without reducing Zombux balance',function()
 local h=setup();h.cfg.reserveCash=950;assert(not h.app.afford('Cash',100));assert(h.app.afford('Zombux',100))
end)
test('missing balances do not authorize purchases',function()
 local h=setup();h.data.children.Stats.children.Zombux=nil;h.cfg.buyClasses.Medic=true;assert(not h.app.classTick())
end)
test('match gun upgrade uses PurchaseUpgrade with native tier type',function()
 local h=setup();h.cfg.gun=true;assert(h.app.upgradeTick());assert(h.requests[1].args[1]=='PurchaseWeaponTierUpgrade')
end)
test('critical health upgrade outranks gun and melee purchases',function()
 local h=setup();h.cfg.gun=true;h.cfg.health=true;h.cfg.melee=true
 h.app.root=function()return{},{Health=20,MaxHealth=100}end
 h.app.matchTick();assert(h.requests[1].args[1]=='Health')
end)
test('ordinary upgrades are mixed without repeating a ready type before the others',function()
 local h=setup();h.cfg.gun=true;h.cfg.health=true;h.cfg.melee=true
 local seen={}
 for i=1,3 do h.app.matchTick();local kind=h.requests[#h.requests].args[1];assert(not seen[kind]);seen[kind]=true;h.advance(2)end
 assert(seen.Health and seen.PurchaseWeaponTierUpgrade and seen.MeleeUpgrade)
end)
test('upgrade maximum and all-off settings suppress remote calls',function()
 local h=setup();assert(not h.app.upgradeTick());h.cfg.gun=true;h.upgrades.IsAtMaxLevel=function()return true end
 assert(not h.app.upgradeTick())
end)
test('native auto skip result is retained instead of toggling repeatedly',function()
 local h=setup();h.app.mode='MATCH';h.cfg.autoSkip=true
 h.RS.children.RoundInfo=node('Folder',nil,{Wave=node('IntValue',4)})
 h.app.invoke=function()h.requests[#h.requests+1]={};return{enabled=true}end
 h.app.skipTick();h.app.skipTick();assert(#h.requests==1 and h.app.skipKnown==true)
end)
test('turning auto skip off only sends the necessary native toggle',function()
 local h=setup();h.app.mode='MATCH';h.cfg.autoSkip=false;h.app.skipKnown=true
 h.RS.children.RoundInfo=node('Folder',nil,{Wave=node('IntValue',4)})
 h.app.invoke=function()h.requests[#h.requests+1]={};return{enabled=false}end
 h.app.skipTick();h.app.skipTick();assert(#h.requests==1 and h.app.skipKnown==false)
end)
test('auto skip does not vote in the lobby or before the first wave',function()
 local h=setup();h.cfg.autoSkip=true;h.app.skipTick();assert(#h.requests==0)
 h.app.mode='MATCH';h.app.skipTick();assert(#h.requests==0)
end)
test('failed purchases back off while preserving the enabled selection',function()
 local h=setup();h.cfg.buyClasses.Medic=true
 assert(load(extract('    function app.invoke(', '    function app.ownedClass('),'request','t',h.env))()
 local remote=node('RemoteFunction');remote.InvokeServer=function()return{ok=false,reason='funds'}end
 local result=h.app.invoke('buy',remote,'Purchase','Medic');assert(result.reason=='funds')
 assert(h.app.next.buy==3 and h.cfg.buyClasses.Medic)
 assert(h.app.invoke('buy',remote,'Purchase','Medic')==nil)
end)
print(tests..' native adapter checks passed')
