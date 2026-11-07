-- Run from repo root: lua Tests/MrbeastIslandEscape/craft_reclaim.lua
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local path=os.getenv('EXIS_MRBEAST_SOURCE')or'Games/MrbeastIslandEscape.lua'
local f=assert(io.open(path));local source=f:read('*a');f:close()
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
local now,stock,cfg,ground,goals,zone,events
local function setup()
 now=10;stock={Wood=0,Stone=0,Axe2=0};ground={};goals={};zone=nil;events={}
 os.clock=function()return now end
 flags={autoFarm=true,craft=false,progression=true};opts={onlyNeeded=true,health=50,hunger=40,jobTimeout=15}
 selected={craft={}};failed={};due={};campData={isOnFire=true};furnaceData={};alive=true
 cfg={item={byId={},byName={},byDisplayName={}},misc={},worldResource={byId={}},itemDrop={byId={}},craftingContent={list={}},bag={byId={}},food={byId={}}}
 for id,name in pairs({wood='Wood',stone='Stone',axe2='Axe2'})do local i={id=id,displayName=name,isBagItem=id~='axe2'};cfg.item.byId[id]=i;cfg.item.byName[name]=i;cfg.item.byDisplayName[name]=i end
 cfg.item.byId.axe2.recipeId='r';cfg.item.byId.axe2.recipe={wood=4}
 config=function()return cfg end
 count=function(name)return stock[name]or 0 end
 tools=function()return{}end
 player={Name='Tester',Character={}};root=function()return{},{}end
 workspace={GetServerTimeNow=function()return now end}
 world=function()return{FindFirstChild=function(_,key)if key=='DroppedItems'then return{GetChildren=function()return ground end}end end}end
 selectedEmpty=function()return true end;allowed=function()return true end
 nearest=function(list,predicate)for _,m in ipairs(list)do if predicate(m)then return m end end end
 note=function()end
 built=function()end
 pos=function(m)return m.point end
 work={models=function()return ground end,boatId=function()return'boat'end,needs={},amounts={},resourceNeeds={},sent=0,campStash={},
  pickupEligible=function()return true end,safeResource=function()return true end,noFood=function()return false end,
  bagState=function()return 0,10 end,canCollect=function()return true end,
  station=function()return zone,zone end,fireState=function()return{level=1}end,
  bagRank=function()return 10 end,buildRank=function(info)return info.assetId=='Campfire'and 0 or 2 end,
  resourceCandidate=function()end,signature=function()return'bag'end,
  upgradeCandidates=function()return goals end,
  recipeAmounts=function(info)return info.recipe or{}end,
  missing=function(amounts)local out={}for id,n in pairs(amounts)do local have=count(cfg.item.byId[id].displayName);if have<n then out[id]=n-have end end return out end}
 body('    function work.markCampDrop(', '    function work.collectModel(')
 body('    function work.stationGoal(', '    function work.goalRunnable(')
 body('    function work.goalRunnable(', '    function work.planProgression()')
 body('    function work.pickupCandidate(', '    local function pickups(')
end
local function craftGoal()
 return{key='craft:axe2',kind='craft',id='axe2',rank=3,info=cfg.item.byId.axe2,amounts={wood=4}}
end
local function drop(name,stash)
 local m={Name=name,Parent=true,GetAttribute=function(_,key)if key=='ownerName'then return player.Name end end}
 ground[#ground+1]=m
 if stash then work.campStash[m]={id=cfg.item.byDisplayName[name].id}end
 return m
end
local passed=0
local function test(name,fn)setup();fn();passed=passed+1;print('PASS '..name)end
test('candidate planning can reclaim a camp supply that the previous task did not need',function()
 work.objective={kind='craft',info=cfg.item.byId.axe2,amounts={wood=4}}
 local m=drop('Stone',true);local nextGoal={kind='craft',info=cfg.item.byId.axe2,amounts={stone=2}}
 assert(work.goalRunnable(nextGoal));assert(work.probingGoal==nil)
 assert(work.objective.amounts.wood==4 and work.needs.stone==nil)
end)
test('needed camp stock is selected before ordinary fresh drops',function()
 work.objective=craftGoal();work.needs.wood=100
 local fresh=drop('Wood',false);local camp=drop('Wood',true)
 assert(work.pickupCandidate(true)==camp and camp~=fresh)
end)
test('unneeded stored items cannot start a pickup and unload loop',function()
 opts.onlyNeeded=false;drop('Stone',true)
 assert(not work.pickupCandidate(false))
end)
test('a selected-only craft setup can reclaim stock without auto progression',function()
 flags.progression=false;flags.craft=true;selected.craft.axe2=true;stock.Wood=1
 local m=drop('Wood',true);work.needs.wood=100
 assert(work.taskDemand('wood','progression')==3 and work.pickupCandidate(true)==m)
end)
test('selected-only crafting ingredients stay reserved when unloading',function()
 flags.progression=false;flags.craft=true;selected.craft.axe2=true
 local tool={Name='Wood',Parent=true,GetAttribute=function()return 2 end}
 assert(work.unloadCount(tool)==0)
end)
test('failed goal probes restore the prior probe and live material tables',function()
 local old={kind='quest'};work.probingGoal=old
 local needs=work.needs;drop('Wood',true)
 work.resourceCandidate=function()error('simulated probe failure')end
 work.pickupCandidate=function()return nil end
 assert(not pcall(work.goalRunnable,craftGoal()))
 assert(work.probingGoal==old and work.needs==needs)
end)
test('ready automatic tool crafting runs even without the manual craft toggle',function()
 stock.Wood=4;goals={craftGoal()}
 assert(not flags.craft and work.nextReadyCraft()==goals[1])
end)
test('missing materials do not create a false ready-craft job',function()
 stock.Wood=3;goals={craftGoal()}
 assert(work.nextReadyCraft()==nil)
end)
test('station contributions make a tool craft ready without filling the carried bag',function()
 goals={craftGoal()};work.stationSynced=true;zone={};work.stationStock={wood=4}
 cfg.craftingContent.list={{itemName='Axe2',campfireLvl=1}}
 assert(work.nextReadyCraft()==goals[1])
 work.safeResource=function()return false end;assert(not work.nextReadyCraft())
end)
test('owned outputs are not crafted again',function()
 stock.Wood=4;stock.Axe2=1;goals={craftGoal()}
 assert(work.nextReadyCraft()==nil)
end)
test('ready crafting follows survival and equipment rewards before ordinary unloading',function()
 body('    function work.rank(job)', '    function work.pick(')
 assert(work.rank{key='craft'}>work.rank{key='fuel'})
 work.foodHuntReady=function()return true end
 assert(work.rank{key='craft'}>work.rank{key='hunt'})
 assert(work.rank{key='mrbeastReward'}<work.rank{key='craft'})
 for _,key in ipairs({'unloadBag','gather','chests'})do assert(work.rank{key='craft'}<work.rank{key=key})end
end)
test('craft execution uses the station/direct submission adapter and the correct job key',function()
 stock.Wood=4;goals={craftGoal()}
 work.submitGoal=function(key,goal)assert(key=='craft'and goal.id=='axe2');stock.Wood=0;stock.Axe2=1;return true end
 local tick=assert(load(extract('    local function craftTick()', '    local function buildTick()')..'\nreturn craftTick'))()
 assert(tick()and stock.Axe2==1)
end)
test('essential camp dependencies precede optional tool tier material goals',function()
 local craft=craftGoal();local building={key='build:bench',kind='build',rank=1,info={assetId='Bench'}}
 goals={building,craft};work.goalRunnable=function()return true end
 assert(work.chooseUpgrade()==building)
end)
test('emergency fire maintenance remains ahead of crafting material goals',function()
 local craft=craftGoal();local survival={key='fuel',kind='fuel',maintenance=true,rank=2}
 goals={craft,survival};work.goalRunnable=function()return true end
 assert(work.chooseUpgrade()==survival)
end)
test('a ready automatic craft takes over stalled gathering without enabling the manual toggle',function()
 stock.Wood=4;goals={craftGoal()}
 body('    function work.jobEnabled(', '    local function blueprintReady(')
 work.roundLost=function()return false end;work.nightPaused=function()return false end
 work.isNight=function()return false end;work.signature=function()return '' end
 work.interruptsInteraction=function()return false end
 local craft={key='craft',enabled=function()return flags.progression end,ready=function()return work.nextReadyCraft()~=nil end}
 work.jobs={craft};work.jobsByKey={craft=craft};work.currentJob={key='gather'};work.active='gather'
 motion={cancel=function()events[#events+1]='cancel' end}
 work.checkpoint('gather');now=18
 assert(not work.checkpoint('gather')and work.preempted.to=='craft'and not flags.craft)
end)
test('bag upgrades alone do not activate a disabled manual selected craft',function()
 flags.progression=false;flags.craft=false;flags.bagUpgrade=true
 local goal=craftGoal();goal.key='selected:axe2';goals={goal};stock.Wood=4
 assert(work.nextReadyCraft()==nil)
end)
test('a new MrBeast request takes over from a pinned optional upgrade at the next action boundary',function()
 local current=craftGoal();current.key='current'
 local queued={key='quest:new',kind='quest',rank=-100,amounts={},info={}}
 goals={current,queued};work.objective=current;work.objectiveSignature=work.signature();work.objectiveProgressAt=now
 work.goalRunnable=function()return true end
 assert(work.chooseUpgrade().key=='quest:new')
end)
test('quest collection and delivery precede routine hunting cooking and unloading',function()
 body('    function work.rank(job)', '    function work.pick(')
 work.objective={kind='quest'};work.foodHuntReady=function()return true end
 for _,key in ipairs({'hunt','cook','cooked','unloadBag','structures','craft'})do
  assert(work.rank{key='quest'}<work.rank{key=key})
  assert(work.rank{key='progression'}<work.rank{key=key})
 end
 assert(work.rank{key='fuel'}<work.rank{key='quest'})
end)
test('a failed MrBeast goal returns after its retry backoff and displaces an optional upgrade',function()
 local request={key='quest:wood',kind='quest',itemId='wood',amounts={wood=4},info={}}
 local other=craftGoal();goals={request,other};work.goalRunnable=function()return true end
 work.upgradeBlocked={[request.key]=now+1};assert(work.chooseUpgrade()==other)
 now=now+1.1;assert(work.chooseUpgrade()==request)
end)
assert(loadfile(path))
print(passed..' reclaim and crafting-priority checks passed; complete module compiles')
