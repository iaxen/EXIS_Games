-- Production native-rule, recovery and refuge helpers in deterministic fixtures.
local f=assert(io.open('Games/MrbeastIslandEscape.lua'));local source=f:read('*a');f:close()
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__mul=function(a,n)return vec(a.X*n,a.Y*n,a.Z*n)end
V.__div=function(a,n)return vec(a.X/n,a.Y/n,a.Z/n)end
V.Dot=function(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
Vector3={new=vec}
local now,r,h,cfg,rows,objects,tiles,scene,notes,requests,fights,moves
local function object(name,point)
 local m={Name=name,Parent=true,point=point or vec(0,3,0),attrs={}}
 function m:GetAttribute(k)return self.attrs[k]end
 function m:FindFirstChild(k)return self[k]end
 function m:FindFirstChildWhichIsA(k)return k=='ProximityPrompt'and self.prompt end
 function m:FindFirstChildOfClass(k)return k=='Humanoid'and self.human end
 function m:IsA(k)return k=='Model'end
 return m
end
local function setup()
 fireproximityprompt=nil
 now=0;os.clock=function()return now end;notes={};requests={};fights=0;moves=0;rows={};tiles={}
 objects={artifacts={},chests={},explore={}}
 cfg={mapLock={byCnId={}},mob={byName={['蜘蛛']={id='Spider'}},byId={Spider={id='Spider'},Bear={id='Bear'}}}}
 opts={jobTimeout=90,retreatHealth=55,health=75,combatMargin=.75,dangerRadius=24,shadowRadius=70,useRefuge=false,keepRefugeLocked=false,unlockObjectives=true,evadeMove='Teleport'}
 flags={artifacts=true,chests=true,combat=true,autoAttack=true,autoFarm=true}
 r={Position=vec(0,3,0),Size=vec(2,2,2)};h={Health=100,MaxHealth=100,HipHeight=2,GetAttribute=function()return 100 end}
 root=function()return r,h end;pos=function(m)return m.point end;config=function()return cfg end
 scene={Seed={Value=99},Tiles={GetChildren=function()return tiles end}}
 function scene:FindFirstChild(k)return self[k]end
 world=function()return scene end;player={Character={}};motion={serial=1,floor=function(p)return vec(p.X,0,p.Z)end}
 due={};failed={};toggles={};save=function()end;say=function()end
 note=function(k,v)notes[k]=v end
 travel=function(point,key,_,mode)moves=moves+1;r.Position=point;return true end
 work={artifacts={},models=function(k)return objects[k]or{}end,hostiles=function()return rows end,
  insideBorder=function()return true end,safeResource=function()return true end,safeWorkPoint=function()return true end,
  stormActive=function()return false end,lineOfSight=function()return false end,enemyReach=function()return 4 end,
  isShadow=function(m)return m.Name=='Shadow'end,
  mobInfo=function(m)return cfg.mob.byId[m.Name]end,isHostile=function(m)return m.Name~='Chicken'end,
  projectedEnemyGap=function(row,p)return(p-row.point).Magnitude end,
  chestKnowledgeFor=function(m)m.knowledge=m.knowledge or{};return m.knowledge end,chestOpened=function(m)return m.opened==true end,
  readChestField=function(m,field)return field=='opened'and m.opened==true or field=='locked'and m.locked~=false end,
  campDropAnchor=function()end,campDropPoint=function()end,
  interactPrompt=function()return true,true end,
  await=function(_,predicate,seconds)if predicate()then return true end;now=now+(seconds or 0);return predicate()end}
 defend=function(key)
  assert(key=='unlockObjective'and work.unlockWork);fights=fights+1
  for _,row in ipairs(rows)do if work.unlockTargetMatches(row.model,work.unlockWork)then row.human.Health=0;return true end end
  return false
 end
 call=function(service,op,m)requests[#requests+1]=op;if op=='requestSolve'then m.solved=true end;return op=='isSolved'and m.solved==true end
 body('    function work.unlockRule(', '    function work.artifactCandidate()')
end
local baseSetup=setup
local bag,camp
local function item(id,name)
 local row={id=id,displayName=name,isBagItem=true};cfg.item.byId[id]=row;cfg.item.byDisplayName[name]=row;cfg.item.byName[name]=row;return row
end
local function held(name,n)local m=object(name);m.attrs.count=n or 1;bag[#bag+1]=m;return m end
local function blueprint(id,asset,recipe)
 local info={assetId=asset,displayName=asset,recipe=recipe or{wood=5,stone=5}}
 cfg.build.byId[id]=info;local m=object(asset..'_Construct');scene.Buildings[m.Name]=m;return m,info
end
setup=function()
 baseSetup();bag={};camp=object('Campfire');campData={};opts.expeditionTribal=true;opts.expeditionPirates=true
 cfg.build={byId={}};cfg.item={byId={},byDisplayName={},byName={}};cfg.tool={byId={}};cfg.food={byId={}}
 cfg.chest={byId={}};cfg.worldResource={byId={}};cfg.itemDrop={byId={}};work.buildRemaining={}
 item('wood','Wood');item('stone','Stone');item('iron','Iron Ore')
 tools=function()local out={}for _,t in ipairs(bag)do if t.Parent then out[#out+1]=t end end return out end
 count=function(name)local n=0 for _,t in ipairs(tools())do if t.Name==name then n=n+(t.attrs.count or 1)end end return n end
 scene.Buildings={FindFirstChild=function(self,k)return self[k]end}
 built=function(asset)return scene.Buildings[asset]end
 work.recipeAmounts=function(info)return info.recipe end
 work.goalAmounts=function(goal)return goal.kind=='build'and work.recipeAmounts(goal.info,true)or goal.amounts end
 work.storageCount=function()return 0 end;work.campDropAnchor=function()return camp end
 work.goalRunnable=function()return true end;work.campfireGoal=function()end
 work.bagState=function()return 0,25 end
 work.canCollect=function()return true end;work.reclaimStorage=function()return false end
 work.submitGoal=function()return false end;work.unloadBag=function()return true end
 work.needItem=function(id,n,priority)work.needs[id]=priority;work.amounts[id]=n end
 pickups=function()return false end;gatherResource=function()return true end
 nearest=function(list,predicate)local result,best for _,m in ipairs(list)do if m.Parent and predicate(m)then
  local gap=(pos(m)-r.Position).Magnitude;if not best or gap<best then result,best=m,gap end
 end end return result end
 body('    function work.buildRank(', '    function work.contribute(')
 body('    function work.campInfrastructureGoal()', '    function work.questAcquireGoal()')
end
local passed=0
local function test(name,fn)setup();fn();passed=passed+1;print('PASS '..name)end

test('essential stations outrank optional chicken coops regardless of alphabetical ID',function()
 blueprint('aaa','ChickenCoop');blueprint('craft','CraftingTable');blueprint('furnace','Furnace');blueprint('storage','Storage')
 local goal=work.campInfrastructureGoal();assert(goal.info.assetId=='CraftingTable'and goal.campEssential)
 assert(work.buildRank(cfg.build.byId.furnace)<work.buildRank(cfg.build.byId.aaa))
end)
test('finished station blueprints advance to the next essential station',function()
 local first=blueprint('craft','CraftingTable');blueprint('furnace','Furnace');blueprint('storage','Storage')
 assert(work.campInfrastructureGoal().id=='craft')
 first.Parent=nil;scene.Buildings.CraftingTable_Construct=nil;scene.Buildings.CraftingTable=object('CraftingTable')
 assert(work.campInfrastructureGoal().id=='furnace')
end)
test('gatherer can read shared station shortages without enabling the builder role',function()
 flags.buildCamp=false;flags.roleBuilder=false;flags.roleGatherer=true
 blueprint('craft','CraftingTable');held('Wood',2)
 local needs=work.campPriorityNeeds();assert(needs.wood==3 and needs.stone==5)
end)
test('already staged camp materials reduce shortages even when another player dropped them',function()
 blueprint('craft','CraftingTable');held('Wood',3);held('Stone',5)
 local drop=object('Wood',vec(20,3,0));drop.attrs.count=2;drop.attrs.ownerName='OtherBuilder';objects.drops={drop}
 assert(not next(work.campPriorityNeeds()))
end)
test('routine smelting and crafting cannot consume the next station material reserve',function()
 flags.roleBuilder=true;blueprint('craft','CraftingTable');held('Wood',7)
 work.questReserved=function()return 1 end
 body('    function work.spendable(', '    function work.toolKeepCount(')
 assert(work.spendable('wood','smelt')==2 and work.spendable('wood','craft')==2 and work.spendable('wood','build')==2)
 assert(work.spendable('wood','campInfrastructure')==7)
 campData.isOnFire=false;assert(work.spendable('wood','fuel')==7)
end)
test('station work submits useful carried material before harvesting or unloading',function()
 blueprint('craft','CraftingTable');held('Wood',5)
 local submitted
 work.submitGoal=function(key,goal)assert(key=='campInfrastructure'and work.activeGoal==goal);submitted=goal;return true end
 gatherResource=function()error('must submit first')end
 assert(work.campInfrastructureTick()and submitted.id=='craft'and not work.activeGoal)
end)
test('station acquisition sets exact shortages and restores the previous active goal',function()
 blueprint('craft','CraftingTable');local previous={key='old'};work.activeGoal=previous
 gatherResource=function(key,needed)assert(key=='campInfrastructure'and needed and work.amounts.wood==5 and work.amounts.stone==5);return true end
 assert(work.campInfrastructureTick()and work.activeGoal==previous)
end)
test('campfire upgrades use the same confirmed material path as infrastructure work',function()
 local fuel={key='fire:3',kind='fuel',name='CAMPFIRE LEVEL 4',amounts={wood=10}}
 work.campfireGoal=function()return fuel end
 work.submitGoal=function(key,goal)assert(key=='campUpgrade'and goal==fuel);return true end
 assert(work.campUpgradeReady()and work.campUpgradeTick())
end)
test('core infrastructure ranks ahead of optional expedition and ordinary chest work',function()
 body('    function work.rank(job)', '    function work.pick(')
 assert(work.rank{key='campInfrastructure'}<work.rank{key='expedition'})
 assert(work.rank{key='expedition'}<work.rank{key='chests'})
 work.criticalMeal=function()return true end
 assert(work.rank{key='eat'}<work.rank{key='campInfrastructure'})
end)
test('tribal skull activation has an explicit native solve receipt',function()
 local skull=object('原始部落头骨');skull.attrs.MapLockTileId='原始部落'
 skull.prompt={Enabled=true,MaxActivationDistance=8,Parent=skull};objects.explore={skull};flags.puzzles=true
 work.interactPrompt=function()return false,true end
 assert(work.expeditionTick()and skull.solved and work.expeditionSolved[skull])
 assert(notes.expedition:find('SERVER SOLVE CONFIRMED',1,true))
end)
test('an interrupted skull hold never sends the native solve request',function()
 local skull=object('原始部落头骨');skull.prompt={Enabled=true,MaxActivationDistance=8,Parent=skull};objects.explore={skull};flags.puzzles=true
 work.interactPrompt=function()return false,false end
 assert(not work.expeditionTick()and not skull.solved and #requests==1)
end)
test('tribal skull stays untouched when the refuge lock switch protects that tile',function()
 local skull=object('原始部落头骨');skull.attrs.MapLockTileId='原始部落';skull.prompt={Enabled=true};objects.explore={skull};flags.puzzles=true
 opts.keepRefugeLocked=true;opts.refuge={x=0,y=3,z=0,seed=99,tileId='原始部落'}
 assert(not work.expeditionTarget())
end)
test('a native unlocked tribal chest is opened as the explicit target and its loot is confirmed',function()
 local chest=object('原始部落宝箱');chest.locked=false;objects.chests={chest};cfg.chest.byId[chest.Name]={}
 work.openChest=function(preferred)assert(preferred==chest);return true end
 assert(work.expeditionTick()and notes.expedition:find('ELIGIBLE LOOT CONFIRMED',1,true))
end)
test('pirate ship chests are identified by native tile metadata rather than guessed chest names',function()
 local chest=object('Kidnapped');chest.attrs.MapLockTileId='章鱼海盗船';chest.locked=false;objects.chests={chest}
 work.openChest=function(preferred)assert(preferred==chest);return true end
 assert(work.expeditionRegion(chest)=='pirates'and work.expeditionTick())
end)
test('a locked pirate chest queues native unlock work instead of faking an open receipt',function()
 local chest=object('Kidnapped');chest.attrs.MapLockTileId='章鱼海盗船';chest.attrs.MapLockCnId='ship';cfg.mapLock.byCnId.ship={unlockTrigger='击杀地块内任意怪物100%'};objects.chests={chest}
 work.openChest=function()error('must clear native lock first')end
 assert(not work.expeditionTick()and work.expeditionFocus==chest and due.unlockObjective==0)
 assert(work.expeditionBlocked[chest]>now)
end)
test('completed expedition chest loot is not opened repeatedly',function()
 local chest=object('原始部落宝箱');objects.chests={chest};work.chestStates={[chest]={complete=true}}
 assert(not work.expeditionTarget())
end)
test('material groups separate wood stone and iron while draining one group at a time',function()
 local a=held('Stone');local w1=held('Wood');local iron=held('Iron Ore');local w2=held('Wood')
 work.unloadCount=function()return 1 end
 body('    function work.itemGroup(', '    function work.campDropAnchor(')
 assert(work.itemGroup(a)=='stone'and work.itemGroup(iron)=='iron')
 assert(work.unloadCandidate()==w1);w1.Parent=nil
 assert(work.unloadCandidate('wood')==w2);w2.Parent=nil
 assert(work.unloadCandidate('wood')==a)
end)
test('gatherer first-pass targeting selects missing station materials before nearer unrelated resources',function()
 blueprint('craft','CraftingTable',{wood=5});held('Stone',5)
 cfg.worldResource.byId={tree={dropId='tree'},iron={dropId='ore'}}
 cfg.itemDrop.byId={tree={{itemCN='Wood'}},ore={{itemCN='Iron Ore'}}}
 local tree=object('Tree',vec(40,3,0));tree.attrs.resourceId='tree'
 local ore=object('Iron',vec(1,3,0));ore.attrs.resourceId='iron';objects.resources={ore,tree}
 work.resourceEligible=function()return true end
 body('    function work.resourceCandidate(', '    local function gatherResource(')
 assert(work.resourceCandidate('stockpile',false)==tree)
end)
test('harvest approach stops at the first safe nearest-side hit position instead of scanning 64 rays',function()
 r.Position=vec(50,3,0);local tree=object('Tree',vec(0,3,0));local floors=0
 work.resourceReach=function(point)return point.X<20 end
 motion.floor=function(point)floors=floors+1;return vec(point.X,0,point.Z)end
 opts.move='Teleport'
 body('    function work.harvestPosition(', '    function work.harvestTrace(')
 assert(work.harvestPosition(tree,{range=11})and floors==1)
end)
test('campfire upgrades outrank another wall craft while an owned wall places immediately',function()
 body('    function work.rank(job)', '    function work.pick(')
 work.wallSupplied=true;assert(work.rank{key='campUpgrade'}<work.rank{key='greatWall'})
 work.wallHaveItem=true;assert(work.rank{key='greatWall'}<work.rank{key='campUpgrade'})
end)
test('gathering does not reclaim station material piles it just staged at camp',function()
 flags.roleGatherer=true;blueprint('craft','CraftingTable')
 local drop=object('Wood',vec(20,3,0));drop.attrs.ownerName='Gatherer';objects.drops={drop}
 assert(work.campStageReserved(drop))
 scene.DroppedItems={GetChildren=function()return objects.drops end}
 work.dropAllowed=function()return true end;work.pickupEligible=function()return true end
 work.selectedCraftMaterialGoal=function()end;work.markCampDrop=function()return true end;work.taskDemand=function()return 5 end
 selectedEmpty=function()return true end;allowed=function()return true end
 body('    function work.pickupCandidate(', '    local function pickups(')
 assert(not work.pickupCandidate(false,'stockpile'))
 assert(work.pickupCandidate(true,'campInfrastructure')==drop)
end)
test('tribal guard clearing can use native tile geometry when the chest has no lock-ID attribute',function()
 local chest=object('原始部落宝箱');chest.prompt={Enabled=true};objects.chests={chest}
 work.safeResource=function()return false end;work.tileForPoint=function()return{Name='原始部落'}end
 local g=work.unlockCandidate();assert(g and g.tileId=='原始部落'and g.rule.kind=='guard_area')
end)
test('required utility stations receive priority over campfire expansion and another wall craft',function()
 body('    function work.rank(job)', '    function work.pick(')
 work.structurePriorityRole='buildingStation'
 assert(work.rank{key='structures'}<work.rank{key='campUpgrade'})
 work.structurePriorityRole='water';assert(work.rank{key='structures'}>work.rank{key='campUpgrade'})
end)
assert(load(source),'full module must compile')
print(passed..' expedition, infrastructure, station material, sorting and gather planning checks passed; module compiles')
