-- Runs extracted production helpers with delayed receipts and native API shapes.
math.clamp = function(x,a,b) return math.max(a,math.min(b,x)) end
local sourcePath = (arg and arg[1]) or os.getenv('EXIS_MRBEAST_SOURCE') or 'Games/MrbeastIslandEscape.lua'
local f=assert(io.open(sourcePath));local source=f:read('*a');f:close()
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local chunks={
 extract('    function work.submitUnits(', '    function work.bagState()'),
 extract('    function work.contribute(', '    local function craftTick()'),
 extract('    function work.goalRunnable(', '    function work.planProgression()'),
 extract('    function work.bagSubmissionReady()', '    function work.shelterNeeded()'),
 extract('    function work.nightPaused(', '    function work.resourceKind('),
 extract('    function work.cookCompatible(', '    function work.fuelItem()'),
}
local now,inventory,events,scheduled,configData,buildings,counts
local realClock=os.clock
local function setup()
 now=0; inventory={Wood=0,Stone=0,Ore=0,Coal=0,Meat=0};events={};scheduled={};counts={yield=0}
 os.clock=function()return now end
 flags={autoFarm=true,tidyBag=true,progression=true,smelt=true,cook=true};opts={jobTimeout=15}
 work={needs={},amounts={},resourceNeeds={},buildRemaining={},sent=0,preempted=nil,
  goalAmounts=function(goal)return goal.amounts end,
  stationGoal=function(goal)if goal.kind=='bag'then return goal end end,
  submitGoal=function()return false end}
 player={Character={}};motion={serial=1};campData={};furnaceData={};due={};selected={}
 configData={item={byId={wood={id='wood',displayName='Wood'},stone={id='stone',displayName='Stone'},ore={id='ore',displayName='Ore'},coal={id='coal',displayName='Coal'},meat={id='meat',displayName='Meat'}}},recipe={byId={}},build={byId={}},misc={furnaceMatter1Id='ore',furnaceMatter2Id='coal'},worldResource={byId={}}}
 configData.item.byName={}
 config=function()return configData end
 count=function(name)return inventory[name]or 0 end
 buildings={};world=function()return{FindFirstChild=function(_,name)if name=='Buildings'then return{FindFirstChild=function(_,id)return buildings[id]end}end end}end
 built=function(name)return buildings[name] end
 allowed=function()return true end
 note=function()end
 travel=function()return true end
 task={wait=function()
  counts.yield=counts.yield+1;now=now+.01
  for _,e in ipairs(scheduled)do if not e.done and now>=e.at then e.done=true;e.run()end end
 end}
 call=function(name,action,argument)events[#events+1]={name=name,action=action,argument=argument,at=now};work.sent=work.sent+1 end
 work.signature=function()local t={}for k,v in pairs(inventory)do t[#t+1]=k..v end table.sort(t);return table.concat(t,'|')end
 work.running=function()return not work.preempted end
 work.await=function(key,predicate,seconds)local deadline=now+(seconds or 3)repeat if predicate()then return true end if not work.running()then return false end task.wait()until now>=deadline return false end
 work.bagState=function()return 10,10 end
 work.canCollect=function()local n,c=work.bagState();return n<c end
 work.missing=function(amounts)local m={}for id,n in pairs(amounts)do local i=configData.item.byId[id];local d=n-count(i and i.displayName or'');if d>0 then m[id]=d end end return m end
 work.buildRank=function(info)return info.rank or 1 end
 work.remaining=function(info,id,total)return (work.buildRemaining[info.assetId]or{})[id]or total end
 work.boatId=function()return'boat'end
 work.recipeAmounts=function(info)return info.amounts or{}end
 work.stationTick=function()return false end
 work.bagGoal=function()end
 work.fuelItem=function()end
 work.maintenanceGoal=function()end
 work.pickupCandidate=function()end
 work.resourceCandidate=function()end
 work.isNight=function()return false end
 work.foodAllowed=function(_,id)return id=='meat'end
 blueprintReady=function()return false end
 questTick=function()return false end
 work.huntCandidate=function()end
 for _,chunk in ipairs(chunks)do assert(load(chunk))()end
 return inventory,events
end
local passed=0
local function test(name,fn)setup();fn();passed=passed+1;print('PASS '..name)end
local function receipt(name,action,inventoryName,delay)
 call=function(service,op,arg)
  events[#events+1]={name=service,action=op,argument=arg,at=now};work.sent=work.sent+1
  assert(service==name and op==action)
  scheduled[#scheduled+1]={at=now+delay,run=function()inventory[inventoryName]=inventory[inventoryName]-1 end}
 end
end
test('all 21 food units submit with frame bursts, not 21 receipt round trips',function()
 inventory.Meat=21;receipt('MakeFire','addFood','Meat',.2)
 assert(work.submitUnits('cook','MakeFire','addFood',{meat=21},'meat'))
 assert(#events==21 and inventory.Meat==0)
 assert(events[8].at==0 and events[9].at==.01 and events[17].at==.02)
 assert(now<.3)
end)
test('native actions are capped to the actual stock and requested need',function()
 inventory.Ore=5;receipt('Furnace','addMatter','Ore',0)
 assert(work.submitUnits('smelt','Furnace','addMatter',{ore=3},'matter1'))
 assert(#events==3 and inventory.Ore==2)
end)
test('unconfirmed batch is not resent immediately',function()
 inventory.Meat=4
 work.await=function()return false end
 assert(not work.submitUnits('cook','MakeFire','addFood',{meat=4},'meat'))
 local n=#events
 assert(not work.submitUnits('cook','MakeFire','addFood',{meat=4},'meat'))
 assert(#events==n)
end)
test('rejected batch can retry after receipt timeout instead of remaining stuck forever',function()
 inventory.Meat=2;work.await=function()return false end
 work.submitUnits('cook','MakeFire','addFood',{meat=2},'meat')
 now=4;receipt('MakeFire','addFood','Meat',0)
 work.await=function(_,predicate)task.wait();return predicate()end
 assert(work.submitUnits('cook','MakeFire','addFood',{meat=2},'meat'))
 assert(inventory.Meat==0 and #events==4)
end)
test('higher priority interruption stops the remaining bursts',function()
 inventory.Meat=25
 local wait=task.wait;task.wait=function()wait();work.preempted=true end
 work.submitUnits('cook','MakeFire','addFood',{meat=25},'meat')
 assert(#events==8)
end)
test('furnace drains both available ingredient stacks including unmatched leftovers',function()
 buildings.Furnace={};inventory.Ore=6;inventory.Coal=2
 call=function(name,action,arg)
  assert(name=='Furnace' and action=='addMatter');events[#events+1]=arg
  local k=arg=='matter1'and'Ore'or'Coal';scheduled[#scheduled+1]={at=now+.01,run=function()inventory[k]=inventory[k]-1 end}
 end
 assert(work.smeltBag('smelt'));assert(inventory.Ore==0 and inventory.Coal==0 and #events==8)
end)
test('one construction job submits all matching materials to all blueprints',function()
 configData.build.byId={a={assetId='A',recipeId='ra'},b={assetId='B',recipeId='rb'}}
 configData.recipe.byId={ra={require_wood=4},rb={require_stone=3}}
 buildings.A_Construct={Parent=true};buildings.B_Construct={Parent=true};inventory.Wood=4;inventory.Stone=3
 call=function(name,action,id)
  events[#events+1]=id
  local k=id=='a'and'Wood'or'Stone';inventory[k]=0
  buildings[(id=='a'and'A'or'B')..'_Construct'].Parent=nil
 end
 assert(work.contribute('tidyBag',false))
 assert(#events==2 and inventory.Wood==0 and inventory.Stone==0)
end)
test('failed travel to one blueprint does not prevent the next destination',function()
 configData.build.byId={a={assetId='A',recipeId='ra'},b={assetId='B',recipeId='rb'}}
 configData.recipe.byId={ra={require_wood=4},rb={require_stone=3}}
 buildings.A_Construct={Parent=true,id='a'};buildings.B_Construct={Parent=true,id='b'};inventory.Wood=4;inventory.Stone=3
 travel=function(target)return target.id~='a'end
 call=function(_,_,id)events[#events+1]=id;inventory.Stone=0;buildings.B_Construct.Parent=nil end
 assert(work.contribute('tidyBag',false));assert(#events==1 and events[1]=='b')
end)
test('blocked highest upgrade yields to the next reachable upgrade',function()
 local a={key='locked',amounts={ore=3},kind='craft'};local b={key='ready',amounts={wood=2},kind='craft'}
 inventory.Wood=2;work.bagState=function()return 2,10 end
 work.upgradeCandidates=function()return{a,b}end
 assert(work.chooseUpgrade()==b)
end)
test('missing supplies use safe resource candidates and restore the active need tables',function()
 work.bagState=function()return 0,10 end
 local original=work.needs
 work.resourceCandidate=function(key,needed)assert(key=='progression'and needed and work.needs.wood==100);return{}end
 assert(work.goalRunnable{kind='craft',amounts={wood=3}})
 assert(work.needs==original)
end)
test('partial blueprint supplies are actionable before the bag is full',function()
 inventory.Wood=2
 assert(work.goalRunnable{kind='build',amounts={wood=20}})
end)
test('batch tidy keeps processing after a destination frees the first slot',function()
 local sequence={};inventory.Ore=3;flags.fuel=true;flags.quest=true
 work.fuelItem=function()return configData.item.byId.wood end;inventory.Wood=3
 work.maintenanceGoal=function()return{amounts={wood=3}}end
 work.addFireWood=function()sequence[#sequence+1]='fuel';inventory.Wood=0;return true end
 work.questRequirement={itemId='stone'};inventory.Stone=1
 questTick=function()sequence[#sequence+1]='quest';inventory.Stone=0;return true end
 work.bagGoal=function()return{amounts={ore=3}}end
 work.stationTick=function()sequence[#sequence+1]='bag';return true end
 work.contribute=function()sequence[#sequence+1]='build';return true end
 buildings.Furnace={};work.smeltBag=function()sequence[#sequence+1]='smelt';return true end
 work.cookReady=function()return false end
 assert(work.tidyBag());assert(table.concat(sequence,',')=='fuel,quest,bag,build,smelt')
end)
test('tidy sweep stops immediately for a higher priority interruption',function()
 flags.fuel=true;inventory.Wood=2
 work.fuelItem=function()return configData.item.byId.wood end
 work.maintenanceGoal=function()return{amounts={wood=2}}end
 work.addFireWood=function()work.preempted=true;return true end
 work.contribute=function()error('must not continue while interrupted')end
 assert(work.tidyBag())
end)
test('non-full bags can submit when enabled and a destination has demand',function()
 blueprintReady=function()return true end
 assert(work.bagSubmissionReady())
end)
test('morning is never paused by saved night settings',function()
 flags.holdNight=true;flags.nightHover=true
 assert(not work.nightPaused{key='gather'})
end)
test('hover alone does not pause safe night work',function()
 flags.nightHover=true;work.isNight=function()return true end
 assert(not work.nightPaused{key='gather'})
end)
test('optional night hold pauses gathering but allows defence and fire',function()
 flags.holdNight=true;work.isNight=function()return true end
 assert(work.nightPaused{key='gather'})
 assert(not work.nightPaused{key='combat'} and not work.nightPaused{key='fuel'})
end)
test('cooking respects the current native cooking food ID',function()
 campData.currentFoodId='other'
 assert(not work.cookCompatible('meat'))
 campData.currentFoodId='meat';assert(work.cookCompatible('meat'))
 campData.readyCount=1;campData.readyFoodId='other';assert(not work.cookCompatible('meat'))
end)
test('bag sweep keeps its starting priority after freeing slots',function()
 assert(load(extract('    function work.rank(job)', '    function work.pick(')))()
 work.bagState=function()return 2,10 end
 work.active='tidyBag';work.bagSweepRank=4
 assert(work.rank{key='tidyBag'}==4)
 work.active=nil;assert(work.rank{key='tidyBag'}==5.8)
end)
test('upgrade candidates include active camp buildings and only the next tool and armour tiers',function()
 assert(load(extract('    function work.upgradeCandidates()', '    function work.goalRunnable(')))()
 configData.tool={byId={axe2={lvl=2,toolType='axe',useDmg=5},axe3={lvl=3,toolType='axe',useDmg=10}},byDisplayName={Axe={lvl=1,toolType='axe'}}}
 configData.armour={byId={armour2={lvl=2},armour3={lvl=3}},byDisplayName={Armour={lvl=1}}}
 for _,id in ipairs({'axe2','axe3','armour2','armour3'})do configData.item.byId[id]={id=id,recipeId=id,displayName=id}end
 configData.build.byId={bench={assetId='Bench'},furnace={assetId='Furnace'}}
 buildings.Bench_Construct={};buildings.Furnace_Construct={}
 tools=function()return{{Name='Axe'},{Name='Armour'}}end
 itemLabel=function(_,id)return id end
 work.campfireGoal=function()end
 local found={};for _,goal in ipairs(work.upgradeCandidates())do found[goal.key]=true end
 assert(found['build:bench'] and found['build:furnace'] and found['craft:axe2'] and found['armour:armour2'])
 assert(not found['craft:axe3'] and not found['armour:armour3'])
end)
test('fuel batch is capped to current fire capacity and confirms the full deduction',function()
 assert(load(extract('    function work.addFireWood(', '    local function eat()')))()
 inventory.Wood=12;local remaining=0
 work.fuelItem=function()return configData.item.byId.wood end
 work.firePendingReady=function()return true end
 work.fireState=function()return{fire={},remaining=remaining,cap=6,burn=1,level=1,on=true}end
 work.fireReceipt=function(before,after)return after.remaining>before.remaining end
 call=function()events[#events+1]=true;inventory.Wood=inventory.Wood-1;remaining=remaining+1 end
 assert(work.addFireWood('progression',30))
 assert(#events==6 and inventory.Wood==6 and work.fuelPending==nil)
end)
os.clock=realClock
test('a crafted MrBeast request produces a native recipe goal before delivery',function()
 assert(load(extract('    function work.upgradeCandidates()', '    function work.goalRunnable(')))()
 flags.quest=true;configData.tool={byId={},byDisplayName={}};configData.armour={byId={},byDisplayName={}}
 configData.item.byId.requested={id='requested',displayName='Requested',recipeId='requestedRecipe'}
 work.questRequirement={itemId='requested',count=3};work.questDrops=function()return{}end
 work.questTotal=function()return inventory.Requested or 0 end;work.campfireGoal=function()end
 work.recipeAmounts=function()return{wood=2}end
 local found
 for _,goal in ipairs(work.upgradeCandidates())do if goal.questFor then found=goal end end
 assert(found and found.kind=='craft'and found.id=='requested'and found.amounts.wood==2)
 inventory.Requested=1
 for _,goal in ipairs(work.upgradeCandidates())do assert(not goal.questFor)end
end)
local function questReserve(id,n)
 flags.quest=true;work.questRequirement={itemId=id,count=n};work.questDrops=function()return{}end
 assert(load(extract('    function work.questReserved(', '    function work.toolKeepCount(')))()
end
test('routine native submission spends surplus while preserving the requested quest quantity',function()
 inventory.Meat=12;questReserve('meat',5);receipt('MakeFire','addFood','Meat',.1)
 assert(work.submitUnits('cook','MakeFire','addFood',{meat=12},'meat')and #events==7 and inventory.Meat==5)
end)
test('all-requested raw food cannot be cooked away by a false ready job',function()
 inventory.Meat=5;questReserve('meat',5);buildings.Campfire={};assert(not work.cookReady())
 assert(not work.submitUnits('cook','MakeFire','addFood',{meat=5},'meat')and #events==0)
end)
test('critical fire maintenance may override the fuel reserve needed for a quest',function()
 inventory.Wood=3;questReserve('wood',3);campData.isOnFire=false
 assert(work.spendable('wood','fuel')==3 and work.spendable('wood','cook')==0)
end)
test('optional construction cannot consume quest stock through its whole-recipe native call',function()
 inventory.Wood=10;questReserve('wood',7)
 configData.build.byId={a={assetId='A',recipeId='r'}};configData.recipe.byId.r={require_wood=5};buildings.A_Construct={Parent=true}
 assert(not work.contribute('build',false)and #events==0 and inventory.Wood==10)
end)
print(passed..' production-helper regression checks passed')
