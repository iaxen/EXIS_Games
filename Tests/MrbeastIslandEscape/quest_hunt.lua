-- Executes production quest synchronization, hunting selection, prompt and camp-storage helpers.
local path=os.getenv('EXIS_MRBEAST_SOURCE') or 'Games/MrbeastIslandEscape.lua'
local source=assert(io.open(path)):read('*a')
local function body(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));assert(load(source:sub(i,j-1)))()end
local V={};V.__index=function(t,k)if k=='Magnitude'then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
local now,cfg,held,scene,rows,ground,hunger,queue,handler,fetchResult,promptCalls
local function setup()
 note=function()end
 due={};now=0;os.clock=function()return now end;held={};rows={};ground={};queue={};promptCalls={};hunger=true
 flags={quest=true,huntFood=false,autoFarm=true};opts={huntRadius=50};alive=true;connections={}
 cfg={item={byId={},byName={},byDisplayName={}},food={byId={}},mob={byId={}},itemDrop={byId={}}}
 for _,id in ipairs({'wood','crab','meat','stone'})do local item={id=id,displayName=id};cfg.item.byId[id]=item;cfg.item.byName[id]=item;cfg.item.byDisplayName[id]=item end
 cfg.mob.byId.Chicken={dropId='chickenDrops'};cfg.mob.byId.Crab={dropId='crabDrops'}
 cfg.itemDrop.byId.chickenDrops={{itemCN='meat'}};cfg.itemDrop.byId.crabDrops={{itemCN='crab'}};cfg.food.byId.meat={};cfg.food.byId.crab={}
 config=function()return cfg end;count=function(id)return held[id]or 0 end;pos=function(m)return m.point end
 player={Name='Tester',Character={}};root=function()return{Position=vec(0,0,0)}end
 scene={FindFirstChild=function(_,n)if n=='Mrbeast'then return{}end end,GetDescendants=function()return{}end}
 world=function()return scene end;task={spawn=function(fn)queue[#queue+1]=fn end}
 nearest=function(list,pred)for _,m in ipairs(list)do if pred(m)then return m end end end
 work={boundedRead=function(fn)return fn()end,noFood=function()return hunger end,rawFoodOwned=function()return false end,canCollect=function()return true end,
  meleeWeapon=function()return{},{}end,creatures=function()return rows end,insideBorder=function()return true end,
  safeResource=function()return true end,safeWorkPoint=function()return true end,progressionEnabled=function()return false end,
  questDrops=function()return{}end,questTotal=function(req)return count(req.itemId)end,
  dropAllowed=function()return true end,taskDemand=function()return 0 end,models=function()return ground end,
  pause=function(_,duration)now=now+duration;return not work.preempted end,buildRank=function(info)return info.rank or 2 end,boatId=function()return'boat'end}
 campData={};failed={};Vector3={new=vec}
 local event={OnClientEvent={Connect=function(_,fn)handler=fn;return{}end}}
 RS={Engine={Service={FindFirstChild=function()return{FindFirstChild=function(_,name)if name=='questUpdateRemote'then return event end end}end}}}
 local q={client={fetchQuest=function()return table.unpack(fetchResult or{1,1,1})end},getQuestRequirement=function(index,alt)return{itemId=alt==2 and'crab'or'wood',count=index}end}
 module=function()return q end
 body('    function work.readQuest(', '    function work.questDrops(')
 body('    function work.mobYields(', '    function work.mobDropsFood(')
 body('    function work.foodDropCandidate()', '    function work.collectHuntedFood()')
 body('    function work.interactPrompt(', '    function work.collectModel(')
 body('    function work.campIntakeZones()', '    function work.unloadBag()')
 body('    function work.goalQueueRank(', '    function work.chooseUpgrade()')
end
local passed=0
local function test(name,fn)setup();fn();passed=passed+1;print('PASS '..name)end
local function animal(name,x)
 local m={Name=name,Parent=true,point=vec(x or 2,0,0)};rows[#rows+1]={model=m,point=m.point,human={Health=10},attackable=true};return m
end
local function drop(id)local m={Name=id,Parent=true,point=vec(2,0,0)};ground[#ground+1]=m;return m end
test('quest fetch resolves the selected alternate, not alternate one',function()fetchResult={4,2,3};work.readQuest();queue[1]();assert(work.readQuest().itemId=='crab')end)
test('quest push immediately changes the requested collection ID',function()work.readQuest();handler(5,2,8);assert(work.questRequirement.itemId=='crab'and work.questRequirement.count==5 and work.refreshAt==0)end)
test('a slower fetch cannot overwrite a newer quest push',function()work.readQuest();handler(5,2,8);queue[1]();assert(work.readQuest().itemId=='crab')end)
test('nil quest push clears the request instead of retaining stale collection',function()work.readQuest();handler(nil,nil,9);queue[1]();assert(work.readQuest()==nil)end)
test('quest updates invalidate old candidate and attack caches',function()work.readQuest();work.goalProbes={};work.attackPlanCache={};handler(1,2,2);assert(work.goalProbes==nil and work.attackPlanCache==nil)end)
test('quest mode hunts the exact animal yield',function()work.questRequirement={itemId='crab',count=2};local chicken=animal('Chicken');local crab=animal('Crab');assert(work.huntCandidate(work.huntWanted())==crab and not work.huntEligible(chicken))end)
test('request quota prevents unnecessary extra hunting',function()work.questRequirement={itemId='crab',count=2};held.crab=2;animal('Crab');assert(not work.huntCandidate(work.huntWanted()))end)
test('current quest hunting remains active while another upgrade is selected',function()work.questRequirement={itemId='crab',count=2};work.progressionEnabled=function()return true end;work.objective={kind='build'};assert(work.huntWanted().crab==2)end)
test('active material hunt stays exact even with unrestricted hunt enabled',function()flags.hunt=true;work.huntingNeeds={crab=1};assert(not work.huntEligible(animal('Chicken'))and work.huntEligible(animal('Crab')))end)
test('empty food inventory can hunt chickens or crabs',function()flags.huntFood=true;assert(work.huntEligible(animal('Chicken'))and work.huntEligible(animal('Crab')))end)
test('raw food already in bag stops more food hunting',function()flags.huntFood=true;work.rawFoodOwned=function()return true end;assert(not work.huntEligible(animal('Chicken')))end)
test('unsafe hunting targets are rejected',function()animal('Crab');work.safeResource=function()return false end;assert(not work.huntCandidate({crab=1}))end)
test('out of border hunting targets are rejected',function()animal('Crab');work.insideBorder=function()return false end;assert(not work.huntCandidate({crab=1}))end)
test('no weapon or bag space prevents hunting',function()animal('Crab');work.canCollect=function()return false end;assert(not work.huntCandidate({crab=1}))end)
test('quest collection ignores other animals food and unrelated materials',function()work.questRequirement={itemId='crab',count=2};drop('meat');drop('stone');local crab=drop('crab');assert(work.foodDropCandidate()==crab)end)
test('food pickup accepts food but skips wood',function()flags.huntFood=true;drop('wood');local meat=drop('meat');assert(work.foodDropCandidate()==meat)end)
test('expired kill drop records are removed',function()work.huntLoot={{expires=-1}};work.foodDropCandidate();assert(#work.huntLoot==0)end)
local function promptModel(duration)
 local callback;local prompt={Enabled=true,HoldDuration=duration,Triggered={Connect=function(_,fn)callback=fn;return{Disconnect=function()end}end},InputHoldBegin=function()promptCalls[#promptCalls+1]='begin';if callback then callback()end end,InputHoldEnd=function()promptCalls[#promptCalls+1]='end'end}
 return{Parent=true,FindFirstChildWhichIsA=function()return prompt end}
end
test('E interaction holds for native duration before completing',function()fireproximityprompt=function()promptCalls[#promptCalls+1]='trigger'end;assert(work.interactPrompt(promptModel(2),'chests'));assert(now==2 and table.concat(promptCalls,',')=='begin,end')end)
test('native E trigger is not fired again through the executor',function()
 local fn;local disconnected=false
 local prompt={Enabled=true,HoldDuration=.1,Triggered={Connect=function(_,callback)fn=callback;return{Disconnect=function()disconnected=true end}end},InputHoldBegin=function()fn()end,InputHoldEnd=function()end}
 fireproximityprompt=function()error('duplicate trigger')end
 assert(work.interactPrompt({Parent=true,FindFirstChildWhichIsA=function()return prompt end},'chests')and disconnected)
end)
test('a hold error still releases E and disconnects its receipt',function()
 local released,disconnected=false,false
 local prompt={Enabled=true,HoldDuration=.1,Triggered={Connect=function()return{Disconnect=function()disconnected=true end}end},InputHoldBegin=function()end,InputHoldEnd=function()released=true end}
 work.pause=function()error('interrupted runtime')end
 assert(not pcall(work.interactPrompt,{Parent=true,FindFirstChildWhichIsA=function()return prompt end},'chests'))
 assert(released and disconnected)
end)
test('interrupted hold releases E without opening',function()work.preempted=true;fireproximityprompt=function()error('must not trigger')end;assert(work.interactPrompt(promptModel(2),'chests')==false and #promptCalls==2)end)
test('no prompt signals native remote fallback',function()assert(work.interactPrompt({FindFirstChildWhichIsA=function()end},'chests')==nil)end)
local function zone(name,x,size)
 return{Name=name,Parent=true,Size=vec(size,10,size),CFrame={PointToObjectSpace=function(_,p)return p-vec(x,0,0)end},IsA=function(_,kind)return kind=='BasePart'end}
end
test('drop spot is outside fire auto intake plus scatter margin',function()scene.GetDescendants=function()return{zone('fireZone',0,30)}end;local camp={point=vec(0,0,0)};assert(not work.campDropClear(vec(24,0,0),camp));assert(work.campDropClear(vec(32,0,0),camp))end)
test('drop spot excludes crafting suction zones too',function()scene.GetDescendants=function()return{zone('吸入范围',32,10)}end;assert(not work.campDropClear(vec(32,0,0),{point=vec(0,0,0)}))end)
test('drop spot never uses unsafe terrain',function()work.safeWorkPoint=function()return false end;assert(not work.campDropClear(vec(32,0,0),{point=vec(0,0,0)}))end)
test('intake zone discovery is cached across route samples',function()local calls=0;scene.GetDescendants=function()calls=calls+1;return{}end;work.campIntakeZones();work.campIntakeZones();assert(calls==1);now=1;work.campIntakeZones();assert(calls==2)end)
test('workbench and furnace precede optional tool ladder materials',function()local craft={kind='craft',rank=3};assert(work.goalQueueRank({kind='build',id='bench',info={assetId='Workbench',rank=1}})<work.goalQueueRank(craft));assert(work.goalQueueRank({kind='build',id='furnace',info={assetId='Furnace'}})<work.goalQueueRank(craft))end)
test('other native camp dependencies also precede optional tiers',function()assert(work.goalQueueRank({kind='build',id='water',info={assetId='WaterMaker'}})<work.goalQueueRank({kind='craft',rank=3}))end)
test('survival fire stays ahead of essential structures',function()assert(work.goalQueueRank({kind='fuel',maintenance=true})<work.goalQueueRank({kind='build',id='furnace',info={assetId='Furnace'}}))end)
local function threatSetup()
 local r,h={Position=vec(0,0,0)},{Health=100,MaxHealth=100}
 root=function()return r,h end
 flags.combat=true;opts.avoidEnemies=true;opts.dangerRadius=20;opts.retreatHealth=30
 local enemy={Name='Spider',point=vec(10,0,0)}
 work.shadowThreat=function()end;work.danger=function()return 100,enemy,1 end
 work.combatClear=function()return false end;work.stanceScore=function()return nil end
 work.attackPlan=function()return enemy,vec(12,0,0)end
 body('    function work.personalThreat()', '    function work.baseThreat()')
 return h,enemy
end
test('a healthy player engages from a checked stance instead of endlessly evading',function()threatSetup();assert(work.personalThreat()==nil)end)
test('an active fight can reposition even when the current position is unsafe',function()threatSetup();work.active='combat';assert(work.personalThreat()==nil)end)
test('an isolated hit does not interrupt an otherwise manageable active fight',function()local h=threatSetup();work.active='combat';work.observedHealth=100;h.Health=95;assert(work.personalThreat()==nil)end)
test('low health overrides combat and retreats',function()local h,enemy=threatSetup();work.active='combat';h.Health=20;assert(work.personalThreat()==enemy)end)
test('damage while surrounded triggers retreat',function()local h,enemy=threatSetup();work.active='combat';work.observedHealth=100;h.Health=95;work.danger=function()return 100,enemy,3 end;assert(work.personalThreat()==enemy)end)
test('Shadow avoidance stays above attempts to fight',function()local h,enemy=threatSetup();work.shadowThreat=function()return enemy end;assert(work.personalThreat()==enemy)end)
test('on-sight food mode cannot replace the exact material hunt for MrBeast',function()
 flags.killFoodOnSight=true;work.isPassiveFood=function()return true end
 work.huntingNeeds={crab=1}
 assert(not work.huntEligible(animal('Chicken'))and work.huntEligible(animal('Crab')))
end)
test('a quest read timeout clears pending state so the next poll can retry',function()
 fetchResult={1,1,1}
 work.boundedRead=function()error('read timed out')end
 work.readQuest(true);queue[1]();assert(not work.questFetchPending)
 work.boundedRead=function(fn)return fn()end
 work.readQuest(true);assert(#queue==1);now=now+5.1
 work.readQuest(true);queue[2]();assert(work.questCache and work.questRequirement.itemId=='wood')
end)
test('quest scheduler dispatches partial delivery instead of a false ready loop',function()
 local a=assert(source:find('            key = "quest",',1,true))
 local b=assert(source:find('        {\n            key = "drops",',a,true))
 local job=assert(load('return {\n'..source:sub(a,b-1):gsub('},%s*$','}')))()
 questTick=function(key,partial)assert(key=='quest'and partial==true)return true end
 assert(job.run())
end)
test('native quest delivery stages a partial stack before the bag is full',function()
 math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
 local a=assert(source:find('    local function questTick(',1,true))
 local b=assert(source:find('    function work.waterDrop()',a,true))
 local tick=assert(load(source:sub(a,b-1)..'\nreturn questTick'))()
 local req={itemId='wood',count=5};local staged={};held.wood=2
 questInfo={};itemLabel=function(_,_,item)return item.displayName end
 work.readQuest=function()return req,1,1,7,{}end
 work.questDrops=function()return staged end;work.questTotal=function()return held.wood+#staged end
 work.bagState=function()return held.wood,15 end
 work.running=function()return true end
 local tool={Name='wood',GetAttribute=function()return held.wood end}
 tools=function()return held.wood>0 and {tool}or{}end
 scene.FindFirstChild=function()return{FindFirstChild=function()return{}end}end
 travel=function()return true end;work.batchDrop=function(_,n)held.wood=held.wood-n;for j=1,n do staged[#staged+1]={}end;return n end
 work.await=function(_,predicate)return predicate()end;motion={serial=1};opts.jobTimeout=15
 assert(tick('quest',true)and held.wood==0 and #staged==2)
end)
test('failed quest refresh retains the active request and the next poll retries it',function()
 work.readQuest();handler(2,2,3)
 work.boundedRead=function()error('temporary fetch failure')end;queue[1]()
 assert(work.readQuest().itemId=='crab'and work.questRequirement.count==2)
 now=now+3;fetchResult={5,2,4};work.boundedRead=function(fn)return fn()end
 work.readQuest(true);queue[#queue]();assert(work.readQuest().itemId=='crab'and work.questRequirement.count==5)
end)
assert(loadfile(path));print(passed..' quest, wildlife, prompt, storage and essential-base checks passed; full module compiles')
