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
 function m:FindFirstChild(k)return self[k]end
 function m:FindFirstChildOfClass(k)return self[k]end
 return m
end
local function setup()
 now=0;inventory={Wood=0,Stone=0,Ore=0,Coal=0,Ingot=0,Meat=0};sceneRows={entities={},drops={},chests={}};schedule={};events={};status={};buildingSet={}
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
 work.recordPickup=function(m)events[#events+1]='pickup:'..m.Name end
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
test('spiders and the Shadow still remain threats',function()
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
 call=function(_,op)
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
 call=function(_,op)
  events[#events+1]=op
  if op=='isOpened'then return accepted elseif op=='isLocked'then return false end
  if op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now;later(.2,function()work.preempted=true end)end
 end
 assert(not work.openChest());assert(not work.chestState(m).complete)
 work.preempted=nil;local d=model('Stone');d.attrs.ownerName=player.Name;sceneRows.drops={d}
 assert(work.openChest());assert(countEvent('requestOpen')==1)
end)
test('locked chests do not send an open request',function()
 chest();call=function(_,op)events[#events+1]=op;return op=='isLocked'end
 assert(not work.openChest()and countEvent('requestOpen')==0)
end)
test('chest with no loot receipt stays pending and retryable rather than falsely complete',function()
 local m=chest();local accepted=false
 call=function(_,op)if op=='isOpened'then return accepted end;if op=='requestOpen'then accepted=true;work.chestState(m).acceptedAt=now end end
 assert(not work.openChest()and not work.chestState(m).complete and now>=15)
end)
test('chest travels within the actual configured opening distance',function()
 chest();local radius
 travel=function(_,key,value)assert(key=='chests');radius=value;return false end
 call=function()return false end
 assert(not work.openChest()and radius==7)
end)
test('an already-open chest is cached and not revisited as if closed',function()
 local m=chest();call=function(_,op)return op=='isOpened'end
 assert(work.openChest()and work.chestState(m).complete and not work.chestCandidate())
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
os.clock=realClock
assert(loadfile(path))
print(passed..' AFK transaction checks passed; complete module compiles')
