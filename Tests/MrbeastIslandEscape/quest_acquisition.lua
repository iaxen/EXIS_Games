-- Production quest acquisition with native output/ingredient mappings and receipts.
local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
local cfg,stock,scene,drops,events,buildings,now,creatures
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.abs(v.x)end end;V.__sub=function(a,b)return setmetatable({x=a.x-b.x},V)end
local function point(x)return setmetatable({x=x},V)end
local function item(id,name)local i={id=id,displayName=name};cfg.item.byId[id]=i;cfg.item.byName[name]=i;cfg.item.byDisplayName[name]=i;return i end
local function setup()
 now=0;os.clock=function()return now end;stock={};drops={};events={};buildings={Campfire={}};creatures={}
 cfg={item={byId={},byName={},byDisplayName={}},food={byId={}},build={byId={furnace={assetId='Furnace',recipe={wood=3,stone=2}},campfire={assetId='Campfire',recipe={wood=5}}}},
  misc={furnaceMatter1Id='ore',furnaceMatter2Id='wood',furnaceResultId='ingot'},worldResource={byId={Tree={dropId='tree'},Stone={dropId='stone'},Iron={dropId='iron'}}},
  itemDrop={byId={tree={{itemCN='Wood'}},stone={{itemCN='Stone'}},iron={{itemCN='Iron Ore'}},chicken={{itemCN='Feather'},{itemCN='Meat'}},spider={{itemCN='Web'}},snake={{itemCN='Tooth'}},bear={{itemCN='Pelt'}},crab={{itemCN='Raw Crab'}}}},
  mob={byId={Chicken={dropId='chicken'},Spider={dropId='spider'},Snake={dropId='snake'},Bear={dropId='bear'},Crab={dropId='crab'}}}}
 for id,name in pairs({wood='Wood',stone='Stone',ore='Iron Ore',ingot='Iron Ingot',feather='Feather',web='Web',tooth='Tooth',pelt='Pelt',crab='Raw Crab',meat='Meat',cookedCrab='Cooked Crab',cookedMeat='Cooked Meat'})do item(id,name)end
 cfg.food.byId={crab={canCook=true,cookTargetId='cookedCrab'},meat={canCook=true,cookTargetId='cookedMeat'},cookedCrab={},cookedMeat={}}
 scene={FindFirstChild=function(_,name)if name=='Buildings'then return{FindFirstChild=function()return{}end}end end}
 flags={quest=true,killFoodOnSight=true,hunt=false};opts={huntRadius=40};failed={};campData={};furnaceData={};motion={}
 config=function()return cfg end;world=function()return scene end;built=function(name)return buildings[name]end
 count=function(name)return stock[name]or 0 end;root=function()return{Position=point(0)},{Health=100,MaxHealth=100}end
 pos=function(m)return m.point end;note=function(k,message)events[#events+1]={kind='note',message=message}end
 work={questRequirement={itemId='feather',count=1},questCache={revision=1},sent=0,creatures=function()return creatures end,
  models=function()return drops end,canCollect=function()return true end,storageCount=function()return 0 end,
  questTotal=function(req)local i=cfg.item.byId[req.itemId];return count(i.displayName)end,
  dropAllowed=function()return true end,safeResource=function()return true end,insideBorder=function()return true end,
  meleeWeapon=function()return{},{range=6}end,recipeAmounts=function(info)return info.recipe or{}end,
  goalAmounts=function(goal)return goal.amounts end,goalRunnable=function()return true end,
  cookCompatible=function(id)return not campData.currentFoodId or campData.currentFoodId==id end,stormActive=function()return false end,
  isCookedFood=function(id)return id=='cookedCrab'or id=='cookedMeat'end,
  needItem=function(id,n)if count(cfg.item.byId[id].displayName)<n then work.needs[id]=100;work.amounts[id]=n end end,
  reclaimStorage=function()return false end,batchReady=function()return true end,
  submitGoal=function(_,goal)events[#events+1]={kind='build',id=goal.id};return true end,
  collectCookedUnit=function()events[#events+1]={kind='cooked'};stock[cfg.item.byId[campData.readyFoodId].displayName]=1;campData.readyCount=0;return true end,
  submitUnits=function(_,service,action,amounts,arg)events[#events+1]={kind='cook',service=service,action=action,amounts=amounts,id=arg};return true end,
  smeltBag=function(_,supply)events[#events+1]={kind='smelt',amounts=supply};return true end,
  request=function(_,service,action)events[#events+1]={kind='request',service=service,action=action};return true end,
  unloadBag=function()events[#events+1]={kind='unload'};return true end,
  missing=function(amounts)local out={}for id,n in pairs(amounts)do if count(cfg.item.byId[id].displayName)<n then out[id]=n-count(cfg.item.byId[id].displayName)end end return out end}
 body('    function work.supplyAmounts(', '    function work.taskDemand(')
 body('    function work.mobYields(', '    function work.mobDropsFood(')
 body('    function work.questAcquireGoal(', '    function work.criticalMeal(')
 travel=function()return true end
 pickups=function()return false end
 gatherResource=function()events[#events+1]={kind='gather',wood=work.needs.wood,stone=work.needs.stone,ore=work.needs.ore};return true end
 defend=function(key)events[#events+1]={kind='hunt',key=key,feather=work.huntingNeeds.feather,web=work.huntingNeeds.web,tooth=work.huntingNeeds.tooth,pelt=work.huntingNeeds.pelt};return true end
end
local function mob(name)
 local m={Name=name,Parent=true,point=point(5)}
 creatures[#creatures+1]={model=m,human={Health=10},point=m.point,attackable=true};return m
end
local function event(kind)for i=#events,1,-1 do if events[i].kind==kind then return events[i]end end end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('wood stone and ore quests create exact acquisition needs rather than waiting for carried items',function()
 for _,id in ipairs({'wood','stone','ore'})do
  work.questRequirement={itemId=id,count=3};assert(work.questAcquireReady()and work.questAcquireTick())
  assert(event('gather')[id]==100 and not event('hunt'))
 end
end)
test('chicken feathers are actively hunted even with general hunt disabled and crabs nearby',function()
 mob('Crab');local chicken=mob('Chicken');assert(work.huntCandidate({feather=1})==chicken)
 gatherResource=function()return false end
 assert(work.questAcquireTick()and event('hunt').feather==100 and event('hunt').key=='questAcquire')
 assert(not work.huntingNeeds and not work.questWork)
end)
test('hostile mob sources use a safe combat stance instead of rejecting their own danger area',function()
 work.questRequirement={itemId='web',count=1};local spider=mob('Spider')
 work.safeResource=function()return false end;work.combatPosition=function()return point(9),1 end
 assert(work.huntCandidate({web=1})==spider)
 work.combatPosition=function()end;assert(not work.huntCandidate({web=1}))
end)
test('web tooth and pelt requests select only mobs whose native drop tables supply them',function()
 local spider,snake,bear=mob('Spider'),mob('Snake'),mob('Bear')
 assert(work.huntCandidate({web=1})==spider and work.huntCandidate({tooth=1})==snake and work.huntCandidate({pelt=1})==bear)
end)
test('cooked crab quests acquire raw crab and cook it instead of a different owned raw food',function()
 work.questRequirement={itemId='cookedCrab',count=1};stock.Meat=20;stock['Raw Crab']=1
 local goal=work.questAcquireGoal();assert(goal.mode=='cook'and goal.amounts.crab==1 and not goal.amounts.meat)
 assert(work.questAcquireTick());local e=event('cook');assert(e.id=='crab'and e.amounts.crab==1 and e.service=='MakeFire')
end)
test('a matching queued cooking batch waits instead of hunting and submitting another raw unit',function()
 work.questRequirement={itemId='cookedCrab',count=1};campData.currentFoodId='crab';campData.pendingCookCount=1
 stock['Raw Crab']=1;assert(not work.questAcquireReady())
end)
test('ready cooked quest output is collected for delivery',function()
 work.questRequirement={itemId='cookedCrab',count=1};campData.readyFoodId='cookedCrab';campData.readyCount=1
 assert(work.questAcquireReady()and work.questAcquireTick()and event('cooked')and stock['Cooked Crab']==1)
 assert(not work.questAcquireReady(),'completed carried output belongs to submission, not another acquisition')
end)
test('previous ready food can be cleared so the requested cooking batch is not blocked forever',function()
 work.questRequirement={itemId='cookedCrab',count=1};campData.readyFoodId='cookedMeat';campData.readyCount=1
 assert(work.questAcquireReady()and work.questAcquireTick()and event('cooked')and not event('cook'))
end)
test('iron ingot quests build the furnace prerequisite before requesting smelting',function()
 work.questRequirement={itemId='ingot',count=2}
 local g=work.questAcquireGoal();assert(g.mode=='build'and g.id=='furnace'and g.amounts.stone==2)
 assert(work.questAcquireTick()and event('build').id=='furnace'and not event('smelt'))
end)
test('iron ingot quests expand into native ore and fuel ingredients and submit the carried batch',function()
 work.questRequirement={itemId='ingot',count=2};buildings.Furnace={};stock['Iron Ore']=2;stock.Wood=2
 assert(work.questAcquireTick());local e=event('smelt');assert(e.amounts.ore==2 and e.amounts.wood==2)
end)
test('queued iron batches wait and ready ingots are collected through the native furnace',function()
 work.questRequirement={itemId='ingot',count=2};buildings.Furnace={};furnaceData.matter1Count=2;furnaceData.matter2Count=2
 assert(not work.questAcquireReady());furnaceData.readyCount=2
 assert(work.questAcquireReady()and work.questAcquireTick()and event('request').action=='collectResult')
end)
test('exact requested outputs in storage are reclaimed before another hunting or mining trip',function()
 work.storageCount=function()return 1 end;work.reclaimStorage=function(goal)assert(goal.amounts.feather==1);return true end
 assert(work.questAcquireTick()and not event('gather')and not event('hunt'))
end)
test('a changed quest during travel cancels the old cooking action before dispatch',function()
 work.questRequirement={itemId='cookedCrab',count=1};stock['Raw Crab']=1
 travel=function()work.questRequirement={itemId='feather',count=1};work.questCache.revision=2;return true end
 assert(not work.questAcquireTick()and not event('cook')and not work.questWork)
end)
test('same-item revision changes also invalidate the previous acquisition plan',function()
 local goal=work.questAcquireGoal();assert(work.questPlanCurrent(goal));work.questCache.revision=2;assert(not work.questPlanCurrent(goal))
end)
test('no safe native source leaves an explicit wait reason without claiming completion',function()
 work.goalRunnable=function()return false end;assert(not work.questAcquireReady())
 assert(event('note').message:find('NO SAFE LOADED SOURCE',1,true))
end)
test('acquisition keeps the active quest on errors and clears temporary hunt state',function()
 gatherResource=function()error('native request failed')end
 assert(not pcall(work.questAcquireTick)and work.questRequirement.itemId=='feather'and not work.questWork and not work.huntingNeeds)
end)
test('a pending submission does not start another acquisition of the old request',function()
 work.questSubmission={at=now};assert(not work.questAcquireGoal()and not work.questAcquireReady())
end)
test('background progression planning preserves the active quest ingredient demand',function()
 body('    function work.planProgression()', '    function work.progressionTick()')
 work.questRequirement={itemId='cookedCrab',count=1};work.active='questAcquire';work.activeGoal=work.questAcquireGoal()
 work.chooseUpgrade=function()error('active quest acquisition must not be replaced by a camp upgrade')end
 work.needs={};work.amounts={};itemLabel=function(_,id)return id end
 work.planProgression();assert(work.needs.crab==100 and not work.needs.wood)
end)
assert(loadfile('Games/MrbeastIslandEscape.lua'))
print(n..' quest acquisition, exact hunt, cooking, furnace prerequisite and stale-request checks passed; module compiles')
