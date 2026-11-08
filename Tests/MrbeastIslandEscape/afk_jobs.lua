-- Run from repo root: lua Tests/MrbeastIslandEscape/afk_jobs.lua
-- Uses production function bodies; no Roblox session or executor is required.
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local path=os.getenv('EXIS_MRBEAST_SOURCE')or'Games/MrbeastIslandEscape.lua'
local file=assert(io.open(path));local source=file:read('*a');file:close()
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
Vector3={new=vec}
local function loadBody(a,b)assert(load(extract(a,b)))()end
local realClock=os.clock
local now,inventory,sceneRows,cfg,schedule,events,status,r,buildingSet
local function model(name,point)
 local m={Name=name,Parent=true,point=point or vec(0,0,0),attrs={}}
 function m:GetAttribute(k)return self.attrs[k]end
 function m:IsA(c)return c=='Model'end
 function m:FindFirstChildWhichIsA()return nil end
 function m:FindFirstChild(k)return self[k]end
 function m:FindFirstChildOfClass(k)return self[k]end
 return m
end
local function setup()
 due={};now=0;inventory={Wood=0,Stone=0,Ore=0,Coal=0,Ingot=0,Meat=0};sceneRows={entities={},drops={},chests={}};schedule={};events={};status={};buildingSet={}
 os.clock=function()return now end
 opts={jobTimeout=15,onlyNeeded=true,settleTime=0,guardRadius=14,huntRadius=40}
 flags={autoFarm=true,progression=true,choiceRewards=true,smelt=true,tidyBag=true}
 player={Character={},Name='Tester',GetAttribute=function()return nil end};motion={serial=0}
 r={Position=vec(0,0,0)};root=function()return r,{Health=100,MaxHealth=100}end
 pos=function(m)return m.point end
 cfg={misc={collectRadius=3,furnaceMatter1Id='ore',furnaceMatter2Id='coal',furnaceResultId='ingot'},item={byId={},byDisplayName={},byName={}},mob={byId={}},chest={byId={Box={openDistance=8}}},food={byId={}},bag={byId={}},worldResource={byId={}},craftingContent={list={}}}
 for id,name in pairs({wood='Wood',stone='Stone',ore='Ore',coal='Coal',ingot='Ingot',meat='Meat'})do
  local item={id=id,displayName=name,isBagItem=true};cfg.item.byId[id]=item;cfg.item.byDisplayName[name]=item;cfg.item.byName[name]=item
 end
 config=function()return cfg end
 count=function(name)return inventory[name]or 0 end
 work={needs={},amounts={},resourceNeeds={},sent=0,waiting={},objective=nil}
 work.models=function(key)return sceneRows[key]or{}end
 work.canCollect=function()local total=0 for _,n in pairs(inventory)do total=total+n end return total<5 end
 work.bagState=function()local total=0 for _,n in pairs(inventory)do total=total+n end return total,5 end
 work.running=function()return not work.preempted end
 work.checkpoint=function()return not work.preempted end
 work.isNight=function()return false end
 work.keyEnabled=function()return true end
 work.safeResource=function()return true end
 work.safeWorkPoint=function()return true end
 work.dropAllowed=function(m)return m.Parent==true and not m.attrs.collecting end
 work.signature=function()local rows={}for n,v in pairs(inventory)do rows[#rows+1]=n..v end table.sort(rows);return table.concat(rows,',')end
 work.missing=function(a)local out={}for id,n in pairs(a)do if n>count(cfg.item.byId[id].displayName)then out[id]=n-count(cfg.item.byId[id].displayName)end end return out end
 work.recipeAmounts=function(info)return info.amounts or{}end
 work.station=function()return nil end
 work.bagRank=function()return nil end
 work.questDrops=function()return{}end
 work.fireState=function()return{level=1}end
 work.maintenanceGoal=function()return nil end
 work.campfireGoal=function()return nil end
 work.fuelItem=function()return cfg.item.byId.wood end
 work.noFood=function()return false end
 work.rawFoodOwned=function()return false end
 work.interactPrompt=function()return nil end
 work.huntCandidate=function()end
 work.recordPickup=function(m)events[#events+1]='pickup:'..m.Name end
 work.pause=function(key,seconds)local stop=now+seconds;while now<stop do if work.preempted then return false end task.wait()end return true end
 work.await=function(key,predicate,seconds)local untilTime=now+(seconds or 3)repeat if predicate()then return true end if work.preempted then return false end task.wait()until now>=untilTime return false end
 task={wait=function()now=now+.02 for _,e in ipairs(schedule)do if not e.done and now>=e.at then e.done=true;e.run()end end end}
 travel=function(target,key,radius)events[#events+1]='travel:'..key;return true end
 call=function(name,action,arg)
  events[#events+1]=name..':'..action
  if name=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false end
 end
 note=function(key,message)status[key]=message end
 nearest=function(list,predicate)for _,m in ipairs(list)do if m.Parent and predicate(m)then return m end end end
 built=function(name)return buildingSet[name]end
 Players={GetPlayerFromCharacter=function()return nil end}
 failed={};campData={};furnaceData={};selected={};pg={FindFirstChild=function()end}
 questTick=function()return false end
 loadBody('    function work.isHostile(', '    function work.danger(')
 loadBody('    function work.stationGoal(', '    function work.goalRunnable(')
 loadBody('    function work.collectModel(', '    function work.treeDropContext(')
 loadBody('    function work.chestState(', '    local function exploreTick(')
 loadBody('    function work.choicePanel()', '    local fish =')
end
local passed=0
local function test(name,fn)setup();fn();passed=passed+1;print('PASS '..name)end
local function creature(name,info)
 local m=model(name);m.Humanoid={Health=100};m.HumanoidRootPart={AssemblyLinearVelocity=vec(0,0,0)};cfg.mob.byId[name]=info or{};sceneRows.entities[#sceneRows.entities+1]=m;return m
end
local function buildGoal(n)
 local info={assetId='Camp',amounts={wood=n}};local goal={key='build:camp',kind='build',id='camp',info=info,amounts=info.amounts}
 work.objective=goal;return goal
end
local function chest()
 local m=model('Box');sceneRows.chests={m};return m
end
local function later(delay,fn)schedule[#schedule+1]={at=now+delay,run=fn}end
local function countEvent(value)local n=0 for _,v in ipairs(events)do if v==value then n=n+1 end end return n end
test('chickens and crabs are passive threats even when their health is positive',function()
 local a=creature('Chicken',{mobClass='Chicken'});local b=creature('Crab',{mobClass='Crab'})
 assert(not work.isHostile(a,cfg.mob.byId.Chicken)and not work.isHostile(b,cfg.mob.byId.Crab))
 assert(#work.creatures()==2 and #work.hostiles()==0)
end)
test('config and attributes classify other passive creatures without a food-name guess',function()
 local m=creature('UnfamiliarWildlife',{canAttack=false});assert(not work.isHostile(m,cfg.mob.byId[m.Name]))
 assert(not work.isHostile(m,{atkDmg=0}))
 m.attrs.Hostile=false;assert(not work.isHostile(m,{atkDmg=10}))
end)
test('spiders and nighttime Shadow remain threats',function()
 work.isNight=function()return true end
 creature('Spider',{atkDmg=10});local shadow=creature('Shadow',{atkDmg=0,mobClass='Shadow'});shadow.Humanoid.Health=1000000
 local rows=work.hostiles();assert(#rows==2 and not rows[2].attackable)
end)
test('passive food wildlife remains visible to hunting logic',function()
 creature('Chicken',{mobClass='Chicken'});creature('Spider',{atkDmg=10})
 assert(#work.creatures()==2 and #work.hostiles()==1)
end)
test('the current objective rejects unrelated drops even when stockpiling was saved on',function()
 buildGoal(3);opts.onlyNeeded=false
 assert(work.needsDrop('wood','progression')and not work.needsDrop('stone','progression'))
end)
test('live construction progress stops excess pickup after enough materials were submitted',function()
 local goal=buildGoal(3);inventory.Wood=1
 assert(work.taskDemand('wood','progression')==2)
 goal.info.amounts.wood=1;assert(work.taskDemand('wood','progression')==0)
end)
test('station inventory reduces task demand without filling the bag first',function()
 work.objective={kind='bag',id='bag2',info={displayName='Bag'},recipe={wood=10},amounts={wood=10}}
 work.bagRank=function()return 10 end;work.stationStock={wood=7};inventory.Wood=1
 assert(work.taskDemand('wood','progression')==2)
end)
test('furnace input demand accounts for queued ingredients and ready ingots',function()
 local goal={kind='craft',info={displayName='Axe2'},amounts={ingot=6}};work.objective=goal;buildingSet.Furnace={}
 furnaceData={readyCount=1,matter1Count=3,matter2Count=1};inventory.Ore=1
 assert(work.taskDemand('ore','progression')==1 and work.taskDemand('coal','progression')==4)
end)
test('one confirmed material is submitted immediately during the same pickup job',function()
 local goal=buildGoal(4);local drop=model('Wood')
 work.contribute=function(key,_,id)assert(key=='progression'and id=='camp');events[#events+1]='deposit';inventory.Wood=0;goal.info.amounts.wood=3;return true end
 assert(work.collectModel(drop,'progression'))
 assert(inventory.Wood==0 and events[#events]=='deposit'and countEvent('pickup:Wood')==1)
end)
test('an unnecessary progression drop never receives a collection request',function()
 buildGoal(4);work.contribute=function()error('must not submit')end
 assert(not work.collectModel(model('Stone'),'progression'))
 assert(#events==0)
end)
test('partial quest supplies are deposited without requiring a full bag',function()
 work.questRequirement={itemId='wood',count=10};work.objective={kind='quest',itemId='wood',amounts={wood=10}};inventory.Wood=1
 questTick=function(key,partial)assert(key=='progression'and partial);inventory.Wood=0;return true end
 assert(work.submitGoal('progression',work.objective)and inventory.Wood==0)
end)
test('partial tool recipe supplies go to the native station instead of waiting for a larger bag',function()
 local item={id='axe2',displayName='Axe2'};cfg.item.byName.Axe2=item;cfg.craftingContent.list={{itemName='Axe2',campfireLvl=1}}
 work.stationSynced=true;work.station=function()return{}end
 work.recipeAmounts=function()return{wood=10}end
 local goal={kind='craft',id='axe2',info=item,amounts={wood=10}};inventory.Wood=1
 work.stationTick=function(station,key)assert(station.id=='axe2'and key=='progression');inventory.Wood=0;return true end
 assert(work.submitGoal('progression',goal))
end)
test('reward choices rank above routine progression but below immediate defence',function()
 loadBody('    function work.rank(job)', '    function work.pick(')
 work.baseThreat=function()return{}end;work.boatId=function()return'boat'end;flags.combat=true
 assert(work.rank{key='combat'}<work.rank{key='mrbeastReward'})
 assert(work.rank{key='mrbeastReward'}<work.rank{key='progression'})
end)
test('chest opening waits for animation and delayed loot instead of only isOpened',function()
 local m=chest();local accepted=false
 work.chestDuration=function()return 2 end
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
  events[#events+1]=op
  if op=='isOpened'then return accepted elseif op=='isLocked'then return false end
  if op=='requestOpen'then
   later(.1,function()accepted=true;work.chestState(m).acceptedAt=now end)
   later(1.9,function()local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}end)
  end
 end
 assert(work.openChest());assert(now>=2.1 and countEvent('requestOpen')==1 and work.chestState(m).complete)
end)
test('chest interruption preserves its opening state and never sends a duplicate open request',function()
 local m=chest();local accepted=false
 work.chestDuration=function()return 1 end
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
  events[#events+1]=op
  if op=='isOpened'then return accepted elseif op=='isLocked'then return false end
  if op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now;later(.2,function()work.preempted=true end)end
 end
 assert(not work.openChest());assert(not work.chestState(m).complete)
 work.preempted=nil;local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}
 assert(work.openChest());assert(countEvent('requestOpen')==1)
end)
test('locked chests do not send an open request',function()
 chest();call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
 events[#events+1]=op;return op=='isLocked'end
 assert(not work.openChest()and countEvent('requestOpen')==0)
end)
test('chest with no loot receipt stays pending and retryable rather than falsely complete',function()
 local m=chest();local accepted=false
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
 if op=='isOpened'then return accepted end;if op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now end end
 assert(not work.openChest()and not work.chestState(m).complete and now>=15)
end)
test('chest travels within the actual configured opening distance',function()
 chest();local radius
 travel=function(_,key,value)assert(key=='chests');radius=value;return false end
 call=function()return false end
 assert(not work.openChest()and radius==7)
end)
test('an already-open chest recovers its remaining owned loot without reopening',function()
 local m=chest();local loot=model('Stone');loot.attrs.ownerName=player.Name;sceneRows.drops={loot}
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
  assert(op~='requestOpen');return op=='isOpened'
 end
 assert(work.openChest()and inventory.Stone==1 and work.chestState(m).complete and not work.chestCandidate())
end)
local function rewardUI()
 local background={Visible=true};local cells={}
 local scroll={GetChildren=function()return cells end};local panel={FindFirstChild=function(_,n)if n=='BadgeScroll'then return scroll end end}
 background.FindFirstChild=function(_,n)if n=='RootPanel'then return panel end end
 local screen={FindFirstChild=function(_,n)if n=='Background'then return background end end}
 pg={FindFirstChild=function(_,n)if n=='MrbeastChoice'then return screen end end}
 local function cell(text,visible)
  cells[#cells+1]={Name='itemCell',Visible=true,FindFirstChild=function(_,n)if n=='text'then return{Text=text}elseif n=='ReceiveButton'then return{Visible=visible}end end}
 end
 return background,cell
end
test('late-loaded reward UI recovers visible choices with the original server indices',function()
 local _,cell=rewardUI();cell('Wood',false);cell('Stone',true);cell('Meat',true)
 work.recoverChoices();assert(#work.choices==2 and work.choices[1].serverIndex==2 and work.choices[2].serverIndex==3)
end)
test('reward selection uses the recovered server index and closes only confirmed current UI',function()
 local background,cell=rewardUI();cell('Wood',false);cell('Stone',true);cell('Meat',true)
 work.recoverChoices();work.choiceScore=function(c)return c.itemId=='meat'and 100 or 10 end
 RS={Engine={Service={FindFirstChild=function()return{FindFirstChild=function()return{FireServer=function(_,index)events[#events+1]=index;inventory.Meat=1 end}end}end}}}
 assert(work.rewardChoiceTick());assert(events[1]==3 and not background.Visible and work.choices==nil)
end)
test('a queued next reward survives confirmation of the previous reward',function()
 local background=rewardUI();work.choices={{itemId='wood',count=1}};work.choiceVersion=1;work.choiceScore=function()return 10 end
 RS={Engine={Service={FindFirstChild=function()return{FindFirstChild=function()return{FireServer=function()work.choiceVersion=2;work.choices={{itemId='stone',count=1}}end}end}end}}}
 assert(work.rewardChoiceTick());assert(work.choices[1].itemId=='stone'and background.Visible)
end)
test('an unconfirmed reward retains its choice for retry and does not hide the UI',function()
 local background=rewardUI();work.choices={{itemId='wood',count=1}};work.choiceVersion=1;work.choiceScore=function()return 10 end
 RS={Engine={Service={FindFirstChild=function()return{FindFirstChild=function()return{FireServer=function()end}end}end}}}
 assert(not work.rewardChoiceTick());assert(work.choices and background.Visible)
end)
test('full progression bag returns to submission under the same job key immediately',function()
 loadBody('    function work.progressionTick()', '    function work.refreshNeeds()')
 local goal=buildGoal(10);inventory.Stone=5
 work.refreshNeeds=function()end
 work.submitGoal=function()return false end
 work.tidyBag=function(key)assert(key=='progression');events[#events+1]='tidy';return true end
 assert(work.progressionTick()and events[1]=='tidy'and now==0)
end)
test('full bag with no safe usable destination exits the job rather than spinning',function()
 loadBody('    function work.progressionTick()', '    function work.refreshNeeds()')
 buildGoal(10);inventory.Stone=5
 work.refreshNeeds=function()end;work.submitGoal=function()return false end
 work.tidyBag=function()return false end
 assert(not work.progressionTick()and now==0 and status.progression:find('NO VALID DEPOSIT',1,true))
end)
test('refined-material goal does not make an empty trip to the furnace',function()
 local goal={kind='craft',info={displayName='Axe2'},amounts={ingot=6}};buildingSet.Furnace={}
 work.smeltBag=function()error('no input is owned; must not travel')end
 assert(not work.submitGoal('progression',goal))
end)
test('needed-only chest gathering stops once the task inventory is sufficient',function()
 buildGoal(1);inventory.Wood=1
 assert(not work.needsDrop('wood','chests'))
end)
test('recovering four wood drops collects and immediately deposits only the two still needed',function()
 loadBody('    function work.drainTreeDrops(', '    function work.recoverTreeDrops()')
 local goal=buildGoal(2);local drops={model('Wood'),model('Wood'),model('Wood'),model('Wood')}
 world=function()return{FindFirstChild=function(_,key)if key=='DroppedItems'then return{GetChildren=function()return drops end}end end}end
 work.watchLateDrops=function()end
 work.contribute=function()inventory.Wood=0;goal.info.amounts.wood=goal.info.amounts.wood-1;events[#events+1]='deposit';return true end
 assert(work.drainTreeDrops({center=vec(0,0,0),wanted={wood=true},before={}},'progression'))
 assert(countEvent('pickup:Wood')==2 and countEvent('deposit')==2)
 assert(drops[3].Parent and drops[4].Parent and inventory.Wood==0)
end)
test('an impossible direct craft does not collect a recipe larger than the bag can hold',function()
 loadBody('    function work.goalRunnable(', '    function work.chooseUpgrade()')
 work.goalAmounts=function()return{wood=10}end
 assert(not work.goalRunnable{kind='craft',amounts={wood=10},info={displayName='Axe2'}})
end)
test('chest collection bypasses needed-only filtering for its own loot',function()
 local m=chest();local accepted=false
 work.needsDrop=function()return false end
 work.chestDuration=function()return .1 end
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
  if op=='isOpened'then return accepted elseif op=='isLocked'then return false end
  if op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now;later(.2,function()local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}end)end
 end
 assert(work.openChest()and inventory.Stone==1)
end)
test('full chest bag stays pending, then returns to collect the remaining drops without reopening',function()
 local m=chest();local accepted=false;local requests=0
 work.chestDuration=function()return .1 end
 work.needsDrop=function()return false end
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
  if op=='isOpened'then return accepted elseif op=='isLocked'then return false end
  if op=='requestOpen'then
   requests=requests+1;accepted=true;work.chestState(m).acceptedAt=now
   later(.2,function()for i=1,6 do local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops[#sceneRows.drops+1]=d end end)
  end
 end
 assert(not work.openChest()and inventory.Stone==5 and work.chestResume==m and not work.chestState(m).complete)
 inventory.Stone=0
 assert(work.openChest()and inventory.Stone==1 and work.chestResume==nil and requests==1)
end)
test('a rejected chest pickup stays pending until a later collection succeeds',function()
 local m=chest();local accepted=false;local attempts=0
 work.chestDuration=function()return .1 end
 call=function(service,op,arg)
  if service=='ItemCollect'then
   attempts=attempts+1
   if attempts>1 then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false end
   return
  end
  if op=='isOpened'then return accepted elseif op=='isLocked'then return false end
  if op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now;later(.2,function()local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}end)end
 end
 assert(work.openChest()and attempts==2 and inventory.Stone==1)
end)
test('native chest E hold finishes before opening and looting',function()
 local m=chest();local accepted=false;local triggered=0
 local receipt
 local prompt={Enabled=true,HoldDuration=.8,MaxActivationDistance=7,Triggered={Connect=function(_,fn)receipt=fn;return{Disconnect=function()end}end},
 InputHoldBegin=function()events[#events+1]='Ebegin';later(.82,function()receipt();triggered=triggered+1;accepted=true;later(.2,function()local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}end)end)end,InputHoldEnd=function()events[#events+1]='Eend'end}
 m.FindFirstChildWhichIsA=function()return prompt end
 loadBody('    function work.interactPrompt(', '    function work.collectModel(')
 fireproximityprompt=function(p)
  assert(p==prompt and now>=.8);triggered=triggered+1;accepted=true
  later(.2,function()local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}end)
 end
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=(inventory[arg.Name]or 0)+1;arg.Parent=false;return end
  assert(op~='requestOpen');return op=='isOpened'and accepted
 end
 assert(work.openChest()and inventory.Stone==1 and triggered==1)
 fireproximityprompt=nil
end)
test('native pickup E prompt collects before completion is reported',function()
 local d=model('Stone');local pressed=0
 local receipt
 local prompt={Enabled=true,HoldDuration=0,MaxActivationDistance=5,Triggered={Connect=function(_,fn)receipt=fn;return{Disconnect=function()end}end},InputHoldBegin=function()later(.02,function()receipt();pressed=pressed+1;inventory.Stone=1;d.Parent=false end)end,InputHoldEnd=function()end}
 d.FindFirstChildWhichIsA=function()return prompt end
 loadBody('    function work.interactPrompt(', '    function work.collectModel(')
 fireproximityprompt=function(p)assert(p==prompt);pressed=pressed+1;inventory.Stone=1;d.Parent=false end
 call=function()error('pickup prompt must be used')end
 assert(work.collectModel(d,'chests',false,true)and pressed==1)
 fireproximityprompt=nil
end)
test('already-open empty chests finish after checking for remaining loot',function()
 local m=chest();call=function(_,op)assert(op~='requestOpen');return op=='isOpened'end
 assert(work.openChest()and work.chestState(m).complete and now>=1)
end)
test('a delayed Triggered receipt keeps E down beyond the exact hold deadline',function()
 local d=model('Stone');local receipt,endedAt
 local p={Enabled=true,HoldDuration=2,Triggered={Connect=function(_,fn)receipt=fn;return{Disconnect=function()end}end},
  InputHoldBegin=function()later(2.04,function()receipt()end)end,InputHoldEnd=function()endedAt=now end}
 d.FindFirstChildWhichIsA=function()return p end
 loadBody('    function work.interactPrompt(', '    function work.collectModel(')
 fireproximityprompt=function()error('must not fake a zero-duration trigger')end
 assert(work.interactPrompt(d,'chests')and endedAt>=2.04 and endedAt<2.4 and work.interaction==nil)
 fireproximityprompt=nil
end)
test('a missing E receipt releases the hold and reports failure',function()
 local d=model('Stone');local ended,disconnected=false,false
 local p={Enabled=true,HoldDuration=1,Triggered={Connect=function()return{Disconnect=function()disconnected=true end}end},
  InputHoldBegin=function()end,InputHoldEnd=function()ended=true end}
 d.FindFirstChildWhichIsA=function()return p end
 loadBody('    function work.interactPrompt(', '    function work.collectModel(')
 assert(not work.interactPrompt(d,'chests')and ended and disconnected and now>=1.35 and now<1.5 and not work.interaction)
end)
test('disabled pickup initialization does not fall through to the collect remote',function()
 local d=model('Stone');d.FindFirstChildWhichIsA=function()return{Enabled=false}end
 loadBody('    function work.interactPrompt(', '    function work.collectModel(')
 call=function()error('disabled prompt cannot collect')end
 assert(not work.collectModel(d,'chests',false,true)and inventory.Stone==0)
end)
test('a chest batch never deposits its first item midway through looting',function()
 buildGoal(3);local d=model('Wood')
 work.submitGoal=function()error('must finish the chest batch before departing')end
 assert(work.collectModel(d,'chests',false,true)and inventory.Wood==1)
end)
test('chest approach uses the prompt anchor instead of a remote model pivot',function()
 local m=chest();local anchor=model('UpperTorso',vec(20,0,0))
 m.FindFirstChildWhichIsA=function()return{Enabled=true,MaxActivationDistance=5,Parent=anchor}end
 travel=function(target,_,radius)assert(target==anchor and radius==4);return false end
 call=function()return false end
 assert(not work.openChest())
end)
test('pickup approach uses its actual activation anchor too',function()
 local d=model('Stone');local anchor=model('Handle',vec(20,0,0))
 d.FindFirstChildWhichIsA=function()return{Enabled=true,MaxActivationDistance=3,Parent=anchor}end
 travel=function(target,_,radius)assert(target==anchor and radius==2);return false end
 assert(not work.collectModel(d,'chests',false,true))
end)
test('routine crafting cannot interrupt a live hold but defence can',function()
 loadBody('    function work.checkpoint(', '    function work.pause(')
 work.active='chests';work.currentJob={key='chests'};work.jobs={};work.rank=function()return 8 end
 work.nightPaused=function()return false end;work.interaction={key='chests',untilTime=10}
 local nextRank=3.5
 work.pick=function(_,_,ceiling,urgent)assert(ceiling==8 and urgent);if nextRank<3.5 then return{key='combat'},nextRank end end
 motion.cancel=function()motion.serial=motion.serial+1 end
 assert(work.checkpoint('chests')and not work.preempted)
 now=.05;nextRank=1.5
 assert(not work.checkpoint('chests')and work.preempted.to=='combat')
end)
test('the optional night pause waits for a valid interaction hold to finish',function()
 loadBody('    function work.checkpoint(', '    function work.pause(')
 work.active='chests';work.currentJob={key='chests'};work.jobs={};work.rank=function()return 8 end
 work.nightPaused=function()return true end;work.interaction={key='chests',untilTime=5}
 work.pick=function()return nil end;motion.cancel=function()end
 assert(work.checkpoint('chests')and not work.preempted)
 now=5.1;assert(not work.checkpoint('chests')and work.preempted.to=='nightHold')
end)
test('routine work queues until seven seconds without progress',function()
 loadBody('    function work.checkpoint(', '    function work.pause(')
 work.active='chests';work.currentJob={key='chests'};work.jobs={};work.rank=function()return 8 end
 work.nightPaused=function()return false end;work.interaction={key='chests',untilTime=-1}
 work.pick=function(_,_,ceiling,urgent)if not urgent then assert(work.skipJob=='chests');return{key='craft'},3.5 end end
 motion.cancel=function()end
 assert(work.checkpoint('chests')and not work.preempted)
 now=6.99;assert(work.checkpoint('chests')and not work.preempted)
 now=7.1;assert(not work.checkpoint('chests')and work.preempted.to=='craft')
end)
test('a ready food hunt interrupts lower-priority travel even while movement makes progress',function()
 loadBody('    function work.checkpoint(', '    function work.pause(')
 work.active='stockpile';work.currentJob={key='stockpile'};work.jobs={};work.rank=function()return 7.8 end
 work.nightPaused=function()return false end;motion.owner='stockpile'
 work.pick=function(_,_,ceiling,urgent)
  assert(ceiling==7.8)
  if not urgent then return{key='foodHunt'},3.025 end
 end
 motion.cancel=function()motion.serial=motion.serial+1 end
 work.progressAt=0;now=.05
 assert(not work.checkpoint('stockpile')and work.preempted.to=='foodHunt')
 assert(work.pendingHandoff=='foodHunt'and work.suspended.stockpile)
end)
test('travel cannot let a routine quest cut a live native interaction short',function()
 loadBody('    function work.checkpoint(', '    function work.pause(')
 work.active='chests';work.currentJob={key='chests'};work.jobs={};work.rank=function()return 8 end
 work.nightPaused=function()return false end;motion.owner='chests';work.interaction={key='chests',untilTime=10}
 work.pick=function(_,_,_,urgent)assert(urgent,'protected hold must only check emergencies')end
 motion.cancel=function()error('hold was interrupted')end
 assert(work.checkpoint('chests')and not work.preempted)
end)
test('higher-priority travel uses the production picker and does not reverse the ranking',function()
 loadBody('    function work.pick(', '    function work.nextQueuedJob(')
 loadBody('    function work.checkpoint(', '    function work.pause(')
 local hunt={key='foodHunt',rank=3.025,ready=function()return true end}
 local quest={key='quest',rank=3.01,ready=function()return true end}
 work.rank=function(job)return job.rank end;work.jobEnabled=function()return true end
 work.interruptsInteraction=function()return false end;work.nightPaused=function()return false end
 work.active='foodHunt';work.currentJob=hunt;work.jobs={hunt,quest};motion.owner='foodHunt'
 motion.cancel=function()end
 assert(not work.checkpoint('foodHunt')and work.preempted.to=='quest')
 work.preempted=nil;work.pendingHandoff=nil;work.nextPriorityCheck=0
 work.active='quest';work.currentJob=quest;motion.owner='quest';now=.05
 assert(work.checkpoint('quest')and not work.preempted,'a lower-priority hunt must wait for quest travel')
end)
test('known animation with currency-only or empty loot does not wait forever',function()
 local m=chest();local accepted=false
 work.chestDuration=function()return 1 end
 call=function(_,op)if op=='isOpened'then return accepted elseif op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now end end
 assert(work.openChest()and now>=2 and now<3 and work.chestState(m).complete)
end)
test('unconfirmed loot wait defers the chest so other jobs can progress',function()
 local m=chest();local accepted=false
 call=function(_,op)if op=='isOpened'then return accepted elseif op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now end end
 assert(not work.openChest()and failed[m]>now and not work.chestCandidate()and not work.interaction)
 now=failed[m]+.01;assert(work.chestCandidate()==m)
end)
test('native auto-equipped armour confirms without waiting for an inventory Tool',function()
 cfg.misc.useArmourCollectEquip=true;cfg.item.byDisplayName.Stone.type='armour'
 local d=model('Stone');work.canCollect=function()return false end
 call=function()d.Parent=false end
 assert(work.collectModel(d,'chests',false,true)and inventory.Stone==0)
end)
test('inferior bags and swap tools are left on the ground without blocking chest completion',function()
 cfg.bag.byId={old={lvl=1},new={lvl=2}};player.GetAttribute=function()return'new'end
 cfg.item.byDisplayName.Stone.id='old';assert(not work.pickupEligible(model('Stone')))
 cfg.tool={byDisplayName={Stone={useSwapUpgrade=true,toolType='axe',lvl=1},Axe={useSwapUpgrade=true,toolType='axe',lvl=2}}}
 cfg.item.byDisplayName.Stone.id='stone';tools=function()return{{Name='Axe'}}end
 assert(not work.pickupEligible(model('Stone')))
 cfg.tool.byDisplayName.Stone.lvl=3;assert(work.pickupEligible(model('Stone')))
end)
test('executor without prompt dispatch uses the native open call only after the full hold',function()
 local m=chest();local accepted=false;local requestedAt
 local p={Enabled=true,HoldDuration=2,MaxActivationDistance=8,
  Triggered={Connect=function()return{Disconnect=function()end}end},InputHoldBegin=function()end,InputHoldEnd=function()end}
 m.FindFirstChildWhichIsA=function()return p end
 loadBody('    function work.interactPrompt(', '    function work.collectModel(')
 work.chestDuration=function()return .1 end
 call=function(service,op,arg)
  if service=='ItemCollect'then inventory[arg.Name]=1;arg.Parent=false;return end
  if op=='isOpened'then return accepted elseif op=='requestOpen'then
   assert(now>=2.35);requestedAt=now;accepted=true
   later(.2,function()local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}end)
  end
 end
 assert(work.openChest()and requestedAt and inventory.Stone==1)
end)
test('survival interruption never falls through to a native open fallback',function()
 local m=chest()
 m.FindFirstChildWhichIsA=function()return{Enabled=true,HoldDuration=2,MaxActivationDistance=8,
  Triggered={Connect=function()return{Disconnect=function()end}end},InputHoldBegin=function()later(.2,function()work.preempted=true end)end,InputHoldEnd=function()end}end
 loadBody('    function work.interactPrompt(', '    function work.collectModel(')
 call=function(_,op)assert(op~='requestOpen');return false end
 assert(not work.openChest()and now<2 and not work.interaction)
end)
test('unknown animation cannot monopolize the default 90-second job budget',function()
 opts.jobTimeout=90;local m=chest();local accepted=false
 call=function(_,op)if op=='isOpened'then return accepted elseif op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now end end
 assert(not work.openChest()and now>=15 and now<16 and not work.chestState(m).complete)
end)
test('an observed long animation extends the wait instead of being abandoned at 15 seconds',function()
 opts.jobTimeout=90;local m=chest();local accepted=false
 work.chestDuration=function()return 20 end
 call=function(_,op)if op=='isOpened'then return accepted elseif op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now end end
 assert(work.openChest()and now>=21 and now<22 and work.chestState(m).complete)
end)
test('a stalled task yields to its queued successor even when its own rank is higher',function()
 loadBody('    function work.nextQueuedJob(', '    function work.checkpoint(')
 local current={key='chests'};local nextJob={key='craft'}
 work.pendingHandoff='craft';work.jobsByKey={craft=nextJob}
 work.pick=function(jobs,_,_,urgent)
  if urgent then return end
  if #jobs==1 then return jobs[1],3.5 end
  return current,1
 end
 assert(work.nextQueuedJob({current,nextJob},now)==nextJob and not work.pendingHandoff)
end)
test('emergency takes priority without discarding the pending routine handoff',function()
 loadBody('    function work.nextQueuedJob(', '    function work.checkpoint(')
 local emergency={key='eat'};work.pendingHandoff='craft'
 work.pick=function(_,_,_,urgent)assert(urgent);return emergency,2 end
 assert(work.nextQueuedJob({},now)==emergency and work.pendingHandoff=='craft')
end)
test('a disabled queued successor cannot lock the scheduler',function()
 loadBody('    function work.nextQueuedJob(', '    function work.checkpoint(')
 local disabled={key='craft'};local fallback={key='stockpile'}
 work.pendingHandoff='craft';work.jobsByKey={craft=disabled}
 work.pick=function(jobs,_,_,urgent)
  if urgent or jobs[1]==disabled then return end
  return fallback,7.8
 end
 assert(work.nextQueuedJob({fallback},now)==fallback and not work.pendingHandoff)
end)
test('resource recovery waits for delayed drops and retries one rejected pickup before completing',function()
 loadBody('    function work.drainTreeDrops(', '    function work.recoverTreeDrops()')
 local drops={};world=function()return{FindFirstChild=function()return{GetChildren=function()return drops end}end}end
 work.needsDrop=function()return true end;work.watchLateDrops=function()end
 local collect=work.collectModel;local attempts=0
 work.collectModel=function(...)
  attempts=attempts+1;if attempts==1 then return false end;return collect(...)
 end
 later(1.2,function()drops[#drops+1]=model('Wood')end)
 later(1.8,function()drops[#drops+1]=model('Wood')end)
 local context={center=vec(0,0,0),wanted={wood=true},before={}}
 assert(work.drainTreeDrops(context,'questAcquire'))
 assert(attempts==3 and inventory.Wood==2 and now>=2.55 and context.seen and not context.noLoot)
end)
test('resource depletion without a loot receipt waits then reports no observed loot honestly',function()
 loadBody('    function work.drainTreeDrops(', '    function work.recoverTreeDrops()')
 world=function()return{FindFirstChild=function()return{GetChildren=function()return{}end}end}end
 local watched=false;work.watchLateDrops=function()watched=true end
 local context={center=vec(0,0,0),wanted={wood=true},before={}}
 assert(work.drainTreeDrops(context,'questAcquire')and now>=4 and context.noLoot and watched)
 assert(status.questAcquire:find('NO ELIGIBLE LOOT OBSERVED',1,true))
end)
test('missing dropped-item replication retains resource recovery rather than completing',function()
 loadBody('    function work.drainTreeDrops(', '    function work.recoverTreeDrops()')
 world=function()return nil end
 assert(not work.drainTreeDrops({center=vec(0,0,0)},'questAcquire'))
end)
test('a full resource bag retains its loot batch for an unloading handoff',function()
 loadBody('    function work.drainTreeDrops(', '    function work.recoverTreeDrops()')
 inventory.Stone=5;local drop=model('Wood');work.needsDrop=function()return true end
 world=function()return{FindFirstChild=function()return{GetChildren=function()return{drop}end}end}end
 assert(not work.drainTreeDrops({center=vec(0,0,0),wanted={wood=true},before={}},'questAcquire')and drop.Parent)
end)
test('chest loot rejects equal or weaker equipped and carried armour but accepts upgrades',function()
 cfg.armour={byId={old={typeCN='body',lvl=1},best={typeCN='body',lvl=3}}}
 cfg.item.byDisplayName.Stone.id='old';work.equippedArmour={body='best'}
 tools=function()return{}end
 assert(not work.pickupEligible(model('Stone')))
 work.equippedArmour={};cfg.item.byDisplayName.Best={id='best'}
 tools=function()return{{Name='Best'}}end
 assert(not work.pickupEligible(model('Stone')))
 cfg.armour.byId.old.lvl=4;assert(work.pickupEligible(model('Stone')))
end)
test('non-bag gear can be collected with a full material bag and needs an inventory receipt',function()
 inventory.Wood=5;cfg.item.byDisplayName.Stone.isBagItem=false
 local d=model('Stone');assert(work.collectModel(d,'chests',false,true)and inventory.Stone==1)
 local other=model('Stone');call=function()other.Parent=false end
 assert(not work.collectModel(other,'chests',false,true))
end)
test('new safe chests outrank routine acquisition while resumed full-bag chests yield to unloading',function()
 loadBody('    function work.rank(job)', '    function work.pick(')
 assert(work.rank{key='mrbeastReward'}<work.rank{key='chests'})
 assert(work.rank{key='chests'}<work.rank{key='questAcquire'})
 work.chestResume=model('Box');inventory.Wood=5
 assert(work.rank{key='unloadBag'}<work.rank{key='chests'})
end)
test('chest completion waits for a second delayed drop after the first receipt',function()
 local m=chest();local accepted=false;work.chestDuration=function()return .1 end
 call=function(service,op,arg)
  if op=='isLocked'then return false elseif op=='isOpened'then return accepted
  elseif op=='requestOpen'then
   accepted=true;work.chestState(m).acceptedAt=now
   later(.2,function()local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops[#sceneRows.drops+1]=d end)
   later(.9,function()local d=model('Wood');d.attrs.ownerName=player.Name;sceneRows.drops[#sceneRows.drops+1]=d end)
  elseif service=='ItemCollect'then inventory[arg.Name]=inventory[arg.Name]+1;arg.Parent=false end
 end
 assert(work.openChest()and inventory.Stone==1 and inventory.Wood==1 and now>=1.9)
end)
test('a disappearing resource drop without an inventory receipt is never reported collected',function()
 loadBody('    function work.drainTreeDrops(', '    function work.recoverTreeDrops()')
 local drop=model('Wood');work.needsDrop=function()return true end;work.watchLateDrops=function()end
 world=function()return{FindFirstChild=function()return{GetChildren=function()return{drop}end}end}end
 work.collectModel=function()drop.Parent=false;return false end
 local context={center=vec(0,0,0),wanted={wood=true},before={}}
 assert(work.drainTreeDrops(context,'questAcquire')and context.noLoot and not context.seen and now>=4)
 assert(status.questAcquire:find('LOOT RECEIPT UNCONFIRMED',1,true))
end)
os.clock=realClock
assert(loadfile(path))
print(passed..' AFK transaction checks passed; complete module compiles')
