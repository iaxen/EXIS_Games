-- Production adapters with delayed native receipts; no live Roblox claims.
local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
V.Dot=function(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
Vector3={new=vec}
local now,cfg,bag,models,scene,events,schedule,r,h,shots
local function item(id,name,extra)
 local row={id=id,displayName=name,stackCap=99,isBagItem=true};for k,v in pairs(extra or{})do row[k]=v end
 cfg.item.byId[id]=row;cfg.item.byDisplayName[name]=row;cfg.item.byName[name]=row;return row
end
local function model(name,point)
 local m={Name=name,Parent=true,point=point or vec(0,0,0),attrs={},children={}}
 function m:GetAttribute(k)return self.attrs[k]end
 function m:IsA(k)return k=='Model'end
 function m:FindFirstChildOfClass(k)return self[k]end
 function m:FindFirstChildWhichIsA(k)return self[k]end
 function m:GetChildren()return self.children end
 function m:GetDescendants()return self.children end
 return m
end
local function held(name,n)
 local t=model(name);t.Parent=player.Character;t.attrs.count=n;t.Activate=function()shots=shots+1 end;bag[#bag+1]=t;return t
end
local function setup()
 workspace={};now=0;bag={};models={drops={},entities={},stations={},artifacts={}};events={};schedule={};shots=0
 os.clock=function()return now end
 cfg={item={byId={},byDisplayName={},byName={}},food={byId={raw={canCook=true,cookTargetId='cooked'},cooked={canCook=false},fruit={canCook=false}}},
  tool={byId={},byDisplayName={}},mob={byId={Chicken={dropId='chicken'},Crab={dropId='crab'},Spider={}}},itemDrop={byId={chicken={{itemCN='Raw'}},crab={{itemCN='Raw'}}}},
  misc={},build={byId={}},freeBuildList={list={}},freeBuild={byCnId={}}}
 item('raw','Raw');item('cooked','Cooked');item('fruit','Fruit');item('wood','Wood');item('crystal','Crystal')
 flags={cook=true,autoFarm=true,stormStock=true,killFoodOnSight=true,useStorage=true,structureCraft=true,autoAttack=true};opts={jobTimeout=15,foodReserve=8,stormReserve=20,carryFood=3,huntRadius=40,dangerRadius=20,combatMargin=.75,enemyReach=4,retreatHealth=35,guardRadius=14,chestHoldPadding=1.5}
 player={Character={},Name='Tester',GetAttribute=function()return nil end};motion={serial=0};campData={};furnaceData={};connections={};alive=true;failed={};due={}
 scene={Day={Value=1},IsRaining={Value=false},FindFirstChild=function(self,n)return self[n]end}
 world=function()return scene end;config=function()return cfg end;pos=function(m)return m.point end
 tools=function()local out={}for _,t in ipairs(bag)do if t.Parent then out[#out+1]=t end end return out end
 count=function(name)local n=0 for _,t in ipairs(tools())do if t.Name==name then n=n+(t:GetAttribute('count')or 1)end end return n end
 r={Position=vec(5.25,3,0),Size=vec(2,2,2)};h={Health=100,MaxHealth=100,HipHeight=2}
 root=function()return r,h end;note=function(k,v)events[#events+1]=k..':'..v end
 nearest=function(list,pred)for _,m in ipairs(list)do if pred(m)then return m end end end
 work={bagState=function()return 0,15 end,models=function(k)return models[k]or{}end,markCampDrop=function(m)return m.stashed end,
  isHostile=function(m)return m.Name=='Spider'end,canCollect=function()return true end,
  safeResource=function()return true end,insideBorder=function()return true end,lineOfSight=function()return true end,
  hostiles=function()return{}end,danger=function()return 0,nil,0 end,meleeClearance=function()return .5 end,
  foodAllowed=function(kind,id)return kind=='food'and id=='cooked'end,rawFoodOwned=function()return count('Raw')>0 end,noFood=function()return count('Cooked')==0 end,
  cookReady=function()return false end,pause=function(_,n)now=now+n;for _,e in ipairs(schedule)do if not e.done and now>=e.at then e.done=true;e.fn()end end return not work.preempted end,
  unloadCount=function(t)return t.attrs.count end,running=function()return not work.preempted end,
  await=function(key,predicate,seconds)local stop=now+(seconds or 3)repeat if predicate()then return true end;if work.preempted then return false end;now=now+.02;for _,e in ipairs(schedule)do if not e.done and now>=e.at then e.done=true;e.fn()end end until now>=stop;return false end}
 task={wait=function()now=now+.02 end,spawn=function(fn)schedule[#schedule+1]={at=now,fn=fn}end}
 RS={Engine={FindFirstChild=function()return nil end}};pg={GetDescendants=function()return{}end,FindFirstChild=function()return nil end}
 travel=function(_,key)events[#events+1]='travel:'..key;return true end
 call=function(name,action,arg)events[#events+1]=name..':'..action end
 body('    function work.stormActive()', '    local jobsList = {')
 body('    function work.mobDropsFood(', '    function work.bagSubmissionReady()')
 body('    function work.mobYields(', '    function work.mobDropsFood(')
 body('    function work.meleeWeapon(key)', '    function work.clearSceneIndex()')
 body('    function work.stanceScore(', '    function work.combatPosition(')
 body('    function work.interactPrompt(', '    function work.collectModel(')
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('day five and six raise cooked reserve before a seventh-day storm',function()
 assert(work.foodReserveTarget()==8);scene.Day.Value=5;assert(work.foodReserveTarget()==20);scene.Day.Value=6;assert(work.foodReserveTarget()==20);scene.Day.Value=7;assert(work.foodReserveTarget()==20);scene.Day.Value=8;assert(work.foodReserveTarget()==8)
end)
test('seventh-day rain and explicit storm flag block cooking assumptions',function()
 scene.Day.Value=7;scene.IsRaining.Value=true;assert(work.stormActive());scene.Day.Value=8;assert(not work.stormActive());scene.IsStorm={Value=true};assert(work.stormActive())
end)
test('cooked whitelist comes from native cook targets and excludes all raw food and uncookable fruit',function()
 assert(work.isCookedFood('cooked')and not work.isCookedFood('raw')and not work.isCookedFood('fruit'))
end)
test('food stock counts carried stored stashed ready and queued supplies',function()
 held('Cooked',2);held('Raw',1);work.storageSnapshot={['1']={displayName='Cooked',count=4}}
 local d=model('Cooked');d.attrs.ownerName='Tester';d.attrs.count=3;d.stashed=true;models.drops={d};campData.readyCount=2;campData.pendingCookCount=5
 local cooked,raw,carry=work.foodCounts();assert(cooked==9 and raw==6 and carry==2)
end)
test('raw food in the bag no longer stops on-sight chicken or crab hunting',function()
 held('Raw',10);local chicken=model('Chicken');chicken.Humanoid={Health=10};models.entities={chicken}
 item('axe','Axe');cfg.tool.byDisplayName.Axe={atkDmg=10,useCd=.5,range=6,toolType='axe'};held('Axe',1)
 assert(work.isPassiveFood(chicken)and work.foodHuntCandidate()==chicken)
 assert(work.isPassiveFood(model('Crab'))and not work.isPassiveFood(model('Spider')))
end)
test('animal display names and native ID attributes resolve the configured food drop instead of disappearing from creature scans',function()
 body('    function work.mobInfo(', '    function work.isHostile(')
 cfg.mob.byId.small_crab={displayName='Beach Crab',dropId='crab',passive=true}
 local displayed=model('Beach Crab');assert(work.mobInfo(displayed)==cfg.mob.byId.small_crab and work.mobDropsFood(displayed))
 local renamed=model('Creature');renamed.attrs.mobId='small_crab';assert(work.mobInfo(renamed)==cfg.mob.byId.small_crab)
 local unknown=model('Unknown Monster');assert(work.mobInfo(unknown)==nil)
 local chicken=model('Chicken');cfg.mob.byId.Chicken=nil;work.mobLookupSource=nil
 assert(work.mobInfo(chicken).passive and work.isPassiveFood(chicken))
end)
test('disabling on-sight hunting permits the reserve target to stop additional hunts',function()
 flags.killFoodOnSight=false;held('Cooked',8);assert(not work.foodShortage());scene.Day.Value=6;assert(work.foodShortage())
end)
test('healthy food stock is unloaded completely and a hungry meal keeps only one',function()
 local t=held('Cooked',20);assert(work.foodKeepCount('cooked',t)==0)
 h.GetAttribute=function(_,key)return key=='hunger'and 10 or 100 end
 assert(work.foodKeepCount('cooked',t)==1 and work.foodKeepCount('raw')==0)
end)
test('food supply does not refill a healthy carried ration',function()
 held('Cooked',2);assert(work.foodSupplyGoal().amounts.cooked==nil)
end)
test('short animal melee position is accepted by horizontal native reach',function()
 local chicken=model('Chicken');assert(work.stanceScore(r.Position,chicken,{range=6,toolType='axe'}))
 assert(not work.stanceScore(r.Position,chicken,{range=6,toolType='gun'}))
end)
test('a short passive animal is approached inside the native three-dimensional overlap sphere',function()
 body('    function work.hitVerticalGap(', '    function work.stanceScore(')
 body('    function work.combatPosition(', '    function work.attackPlan(')
 local chicken=model('Chicken',vec(0,0,0))
 chicken.GetBoundingBox=function()return{Position=vec(0,1,0)},vec(2,2,2)end
 motion.floor=function(point)return vec(point.X,0,point.Z)end;motion.clearSegment=function()return true end
 local point=work.combatPosition(chicken,{range=3,toolType='axe'})
 assert(point and work.stanceScore(point,chicken,{range=3,toolType='axe'}))
 local gap=work.hitVerticalGap(point,chicken)
 assert(math.sqrt(point.X^2+point.Z^2+gap^2)<2.75)
 assert(not work.stanceScore(vec(2.8,3,0),chicken,{range=3,toolType='axe'}))
end)
test('crab approach moves inward until actual native parts overlap the attack sphere',function()
 body('    function work.hitVerticalGap(', '    function work.stanceScore(')
 body('    function work.combatPosition(', '    function work.attackPlan(')
 local crab=model('Crab',vec(0,0,0))
 crab.GetBoundingBox=function()return{Position=vec(0,1,0)},vec(8,2,8)end
 OverlapParams={new=function()return{}end};Enum={RaycastFilterType={Include=1}}
 local part={FindFirstAncestorOfClass=function()return crab end}
 workspace.GetPartBoundsInRadius=function(_,point,range,params)
  assert(params.FilterDescendantsInstances[1]==crab)
  return math.sqrt(point.X^2+point.Z^2)<=.8 and{part}or{}
 end
 motion.floor=function(point)return vec(point.X,0,point.Z)end;motion.clearSegment=function()return true end
 assert(not work.stanceScore(vec(2,3,0),crab,{range=3,toolType='axe'}))
 local point=work.combatPosition(crab,{range=3,toolType='axe'})
 assert(point and work.stanceScore(point,crab,{range=3,toolType='axe'}))
 r.Position=point
 local heldPoint=work.combatPosition(crab,{range=3,toolType='axe'})
 assert(heldPoint==point,'already hittable passive targets must not cause another reposition')
end)
test('passive hunting prefers a working melee tool even when low health would favor a gun in combat',function()
 cfg.tool.byDisplayName.Axe={atkDmg=20,useCd=.5,range=3,toolType='axe'}
 cfg.tool.byDisplayName.Gun={atkDmg=10,useCd=1,range=40,toolType='gun'}
 local axe=held('Axe',1);local gun=held('Gun',1);gun.attrs.ammo=5;h.Health=50
 work.danger=function()return 100,nil,3 end
 assert(work.meleeWeapon('foodHunt')==axe and work.meleeWeapon('combat')==gun)
end)
test('on-sight food hunting is high priority at action boundaries while survival and MrBeast requests go first',function()
 body('    function work.rank(job)', '    function work.pick(')
 assert(work.rank{key='eat'}<work.rank{key='foodHunt'})
 assert(work.rank{key='quest'}<work.rank{key='foodHunt'})
 assert(work.rank{key='foodHunt'}<work.rank{key='cook'})
 assert(not work.interruptsInteraction{key='foodHunt'})
end)
test('a food hunt finishes one animal then clears its temporary targeting mode even on failure',function()
 local text=extract('        {key="foodHunt"', '        {key="foodCache"')
 local jobs=assert(load('return{'..text..'}'))();local job=jobs[1]
 defend=function(key)assert(key=='foodHunt'and work.huntingPassive);return true end
 assert(job.run()and not work.huntingPassive and work.foodHuntAt>now)
 defend=function()error('native input failed')end
 assert(not pcall(job.run)and not work.huntingPassive)
end)
test('crowded combat prefers an available ranged weapon and rejects empty guns',function()
 cfg.tool.byDisplayName.Axe={atkDmg=20,useCd=.5,range=6,toolType='axe'};cfg.tool.byDisplayName.Gun={atkDmg=10,useCd=1,range=40,toolType='gun'}
 local axe=held('Axe',1);local gun=held('Gun',1);gun.attrs.ammo=2;work.danger=function()return 100,nil,3 end
 assert(work.meleeWeapon()==gun);gun.attrs.ammo=0;assert(work.meleeWeapon()==axe)
end)
test('native ranged lock must match the target before firing',function()
 local t=held('Gun',1);local target=model('Spider');assert(not work.activateWeapon(t,{toolType='gun'},target,'combat')and shots==0)
 pg.FindFirstChild=function()return{Name='Aim',Parent=true,Enabled=true,Adornee=target,IsA=function(_,k)return k=='BillboardGui'end}end
 assert(work.activateWeapon(t,{toolType='gun'},target,'combat')and shots==1)
end)
test('an unbound mobile button cannot swallow the equipped tool activation',function()
 local t=held('Axe',1);local clicks=0
 pg.FindFirstChild=function()return{FindFirstChild=function()return{Visible=true,Activated={}}end}end
 firesignal=function()clicks=clicks+1 end
 assert(work.activateWeapon(t,{toolType='axe'},model('Chicken'),'foodHunt')and shots==1 and clicks==0)
 flags.autoAttack=false
 assert(work.activateWeapon(t,{toolType='axe'},model('Chicken'),'hunt')and shots==2 and clicks==0);firesignal=nil
end)
test('chest padding holds through the extra one and a half seconds',function()
 local m=model('Box');local receipt,released
 m.ProximityPrompt={Enabled=true,HoldDuration=3.5,Triggered={Connect=function(_,fn)receipt=fn;return{Disconnect=function()end}end},InputHoldBegin=function()schedule[#schedule+1]={at=3.5,fn=function()receipt()end}end,InputHoldEnd=function()released=now end}
 work.setSprint=function()end
 assert(work.interactPrompt(m,'chests',1.5)and released>=5)
end)
test('the same padding is not applied to ordinary pickup prompts',function()
 local m=model('Raw');local receipt
 m.ProximityPrompt={Enabled=true,HoldDuration=0,Triggered={Connect=function(_,fn)receipt=fn;return{Disconnect=function()end}end},InputHoldBegin=function()receipt()end,InputHoldEnd=function()end}
 work.setSprint=function()end;assert(work.interactPrompt(m,'foodPickup')and now==0)
end)
test('storage takes the native whole-stack call and requires inventory confirmation',function()
 local t=held('Wood',5);work.findStructure=function()return model('Storage')end
 call=function(name,action,arg)assert(name=='Storage'and action=='storeItem'and arg==t);t.Parent=nil end
 assert(work.storeBag('unloadBag')and count('Wood')==0)
end)
test('unconfirmed or full storage falls through to overflow instead of reporting success',function()
 held('Wood',5);work.findStructure=function()return model('Storage')end
 assert(not work.storeBag('unloadBag')and work.storageBlockedAt>now)
end)
test('storage reclaim uses numeric native slot and confirms receipt',function()
 work.findStructure=function()return model('Storage')end;work.storageSnapshot={['2']={displayName='Crystal',count=4}}
 call=function(name,action,index)assert(name=='Storage'and action=='takeItem'and index==2);held('Crystal',4)end
 assert(work.reclaimStorage({amounts={crystal=3}},'progression')and count('Crystal')==4)
end)
test('storage stack containing protected carry ration is not wholly stored',function()
 held('Cooked',6);work.findStructure=function()return model('Storage')end;work.unloadCount=function()return 3 end
 call=function()error('must not store whole stack')end;assert(not work.storeBag('unloadBag'))
end)
test('storage and furnace structures are prioritized before optional builds',function()
 item('storage','Storage',{recipeId='r'});item('furnace','Furnace',{recipeId='r'});item('wall','Wall',{recipeId='r'})
 cfg.freeBuildList.list={{itemId='wall'},{itemId='furnace'},{itemId='storage'}};cfg.freeBuild.byCnId={wall={},furnace={},storage={}}
 work.recipeAmounts=function()return{wood=10}end;work.findStructure=function()return nil end
 assert(work.structureGoal().id=='storage');work.structureFailed={storage=99};assert(work.structureGoal().id=='furnace')
end)
test('observed attack windup strike and recovery are distinguished without an invisible AI claim',function()
 local m=model('Spider');local track={Name='Attack',Animation={Name='Bite'},Length=1,TimePosition=.1}
 m.Humanoid={FindFirstChildOfClass=function()return{GetPlayingAnimationTracks=function()return{track}end}end}
 assert(work.attackPhase(m)=='windup');track.TimePosition=.5;assert(work.attackPhase(m)=='strike');track.TimePosition=.9;assert(work.attackPhase(m)=='recovery')
end)
test('routine food hunts rewards and crafting cannot cut a protected E hold short',function()
 h.GetAttribute=function(_,k)return k=='hunger'and 80 or 100 end;opts.retreatHealth=35
 for _,key in ipairs({'hunt','foodSupply','mrbeastReward','quest','craft','structures','stockpile'})do assert(not work.interruptsInteraction{key=key},key)end
 assert(work.interruptsInteraction{key='combat'}and work.interruptsInteraction{key='evade'})
 h.GetAttribute=function(_,k)return k=='hunger'and 10 or 100 end
 assert(work.interruptsInteraction{key='foodSupply'})
end)
test('the production picker enforces the interaction whitelist rather than rank alone',function()
 body('    function work.pick(', '    function work.checkpoint(')
 work.rank=function(job)return job.rank end;work.jobEnabled=function()return true end
 local jobs={{key='hunt',rank=3.3},{key='mrbeastReward',rank=3.25},{key='quest',rank=3.35}}
 h.GetAttribute=function(_,k)return k=='hunger'and 80 or 100 end
 assert(not work.pick(jobs,now,3.5,true))
 jobs[#jobs+1]={key='combat',rank=1.5};assert(work.pick(jobs,now,3.5,true).key=='combat')
end)
test('native building station uses its own stock and craft event',function()
 body('    function work.stationTick(', '    function work.choiceScore(')
 local material=held('Wood',2);item('storage','Storage',{recipeId='r'})
 local goal={id='storage',info=cfg.item.byId.storage,recipe={wood=2},stationKind='building'}
 work.buildingStock={};work.stationStock={wood=99};work.structureStation=function()return{},{}end
 work.insideStation=function()return true end;work.sent=0
 work.batchDrop=function(tool,missing)assert(tool==material and missing==2);tool.Parent=nil;work.buildingStock.wood=2;return 2 end
 work.net=function(name)assert(name=='BuildingStationCraft');return{FireServer=function(_,id)assert(id=='storage');held('Storage',1)end}end
 assert(work.stationTick(goal,'structures')and count('Storage')==1 and work.stationStock.wood==99)
end)
test('an unconfirmed station deposit is not repeated with the next bag of wood',function()
 body('    function work.stationTick(', '    function work.choiceScore(')
 local material=held('Wood',8);item('wall','Wooden Wall')
 local zone={};local goal={id='wall',info=cfg.item.byId.wall,recipe={wood=3},stationKind='building'}
 work.buildingStock={};work.structureStation=function()return{},zone end;work.insideStation=function()return true end
 local sent=0;work.batchDrop=function(tool,n)sent=sent+n;tool.attrs.count=tool.attrs.count-n;return n end
 work.net=function()return{FireServer=function()end}end
 assert(work.stationTick(goal,'greatWall')and sent==3 and count('Wood')==5)
 assert(not work.stationTick(goal,'greatWall')and sent==3 and count('Wood')==5)
 work.buildingStock.wood=3;work.sent=0
 work.net=function(name)return{FireServer=function()assert(name=='BuildingStationCraft');held('Wooden Wall',1);work.buildingStock.wood=0 end}end
 assert(work.stationTick(goal,'greatWall')and sent==3 and count('Wooden Wall')==1)
end)
test('shared stock funding the recipe releases an obsolete higher deposit expectation',function()
 body('    function work.stationTick(', '    function work.choiceScore(')
 item('wall','Wooden Wall');local zone={}
 work.buildingStock={wood=3};work.structureStation=function()return{},zone end;work.insideStation=function()return true end
 work.stationDeposits={buildingStock={id='wood',zone=zone,expected=6}}
 work.net=function(name)assert(name=='BuildingStationCraft');return{FireServer=function()held('Wooden Wall',1)end}end
 work.sent=0;work.batchDrop=function()error('funded recipe must not drop more wood')end
 assert(work.stationTick({id='wall',info=cfg.item.byId.wall,recipe={wood=3},stationKind='building'},'greatWall'))
 assert(not work.stationDeposits.buildingStock)
end)
test('a concurrent bag upgrade does not falsely confirm a crafted wall output',function()
 body('    function work.stationTick(', '    function work.choiceScore(')
 item('wall','Wooden Wall');work.buildingStock={wood=3};work.structureStation=function()return{},{}end
 work.insideStation=function()return true end;work.sent=0
 local bagId='old';player.GetAttribute=function(_,k)if k=='bagId'then return bagId end end
 work.net=function(name)assert(name=='BuildingStationCraft');return{FireServer=function()bagId='upgraded' end}end
 assert(not work.stationTick({id='wall',kind='structure',info=cfg.item.byId.wall,recipe={wood=3},stationKind='building'},'greatWall'))
end)
test('unsafe native drop geometry never spends station materials',function()
 body('    function work.stationTick(', '    function work.choiceScore(')
 held('Wood',3);item('wall','Wooden Wall')
 work.buildingStock={};work.structureStation=function()return{},{}end;work.insideStation=function()return true end
 work.prepareStationDrop=function()return false end
 work.batchDrop=function()error('unsafe deposit must not send')end
 assert(not work.stationTick({id='wall',info=cfg.item.byId.wall,recipe={wood=3},stationKind='building'},'greatWall'))
 assert(count('Wood')==3)
end)
test('wall materials use building stock instead of unrelated crafting table stock',function()
 body('    function work.stationGoal(', '    function work.supplyAmounts(')
 work.buildingStock={wood=1};work.stationStock={wood=99}
 local goal={kind='structure',stationKind='building',recipe={wood=3}}
 assert(work.stationGoal(goal)==goal and work.goalAmounts(goal).wood==2)
end)
test('station approach accounts for the native forward throw and rejects vertical misses',function()
 body('    function work.prepareStationDrop(', '    function work.stationTick(')
 work.nativeDropReach=function()return 5 end
 work.safeWorkPoint=function()return true end
 motion.floor=function()return vec(5,0,0)end
 travel=function(point)r.Position=point;return true end
 CFrame={lookAt=function()return{}end}
 local head={Position=vec(5,4,0),CFrame={LookVector=vec(-1,0,0)}}
 player.Character.FindFirstChild=function()return head end
 local zone={Position=vec(0,0,0),Size=vec(10,10,10),CFrame={PointToObjectSpace=function(_,v)return v end}}
 assert(work.prepareStationDrop(zone,cfg.item.byId.wood,'craft'))
 head.Position=vec(5,20,0)
 assert(not work.prepareStationDrop(zone,cfg.item.byId.wood,'craft'))
end)
test('a destroyed weapon is rejected before EquipTool can reparent it',function()
 local equip=assert(load(extract('    local function equip(t)','    local function nearest(')..'\nreturn equip'))()
 local backpack={};player.FindFirstChildOfClass=function()return backpack end
 h.EquipTool=function()error('must not equip stale weapon')end
 local tool=held('Wood',1);tool.Parent=nil
 assert(equip(tool)==false)
end)
test('a weapon destroyed during EquipTool is handled without crashing the job',function()
 local equip=assert(load(extract('    local function equip(t)','    local function nearest(')..'\nreturn equip'))()
 local backpack={};player.FindFirstChildOfClass=function()return backpack end
 local tool=held('Wood',1);tool.Parent=backpack
 h.EquipTool=function()tool.Parent=nil;error('Parent locked')end
 assert(equip(tool)==false and not work.attackPlanCache)
end)
test('an unavailable structure recipe cannot keep interrupting productive work',function()
 item('storage','Storage');work.structureGoal=function()return{id='storage',info=cfg.item.byId.storage,stationKind='building'}end
 work.structureStation=function()return{}end;work.buildingSynced=true;work.goalRunnable=function()return false end
 assert(not work.structureReady());held('Storage',1);assert(work.structureReady())
end)
test('storage planning finds an empty site and places the owned native item there',function()
 item('storage','Storage');held('Storage',1)
 local fire=model('Campfire');built=function()return fire end;work.findStructure=function()return nil end
 work.safeWorkPoint=function()return true end;work.campDropAnchor=function()return fire end
 motion.floor=function(p)return vec(p.X,0,p.Z)end
 Enum={RaycastFilterType={Include='Include'}};OverlapParams={new=function()return{}end}
 CFrame={new=function(p)return{Position=p}end};workspace={GetPartBoundsInBox=function()return{}end}
 local free={checkOverlap=function()return false end};module=function()return free end
 local assets={getFreeBuildModelByCnId=function(id)assert(id=='storage');return{FindFirstChild=function()return{Size=vec(4,4,4)}end,Destroy=function()end}end}
 RS.Assets={AssetsManager=assets};local original=require;require=function(api)return api end
 local goal={id='storage',info=cfg.item.byId.storage,role='storage'}
 work.inBaseBeach=function()return true end
 local frame=work.structurePlacement(goal);assert(frame and work.storagePlannedFrame==frame and math.abs(frame.Position.X)>=31)
 local placed=false
 call=function(name,action,id,cf)assert(name=='FreeBuild'and action=='requestPlace'and id=='storage'and cf==frame);placed=true;bag[1].Parent=nil end
 work.findStructure=function(_,id)if placed and id=='storage'then return{}end end
 assert(work.placeStructure(goal,'structures'));require=original
end)
test('harvested crystal nodes are eligible for stockpile mode even with no active recipe demand',function()
 body('    function work.resourceEligible(', '    function work.alternativeWork(')
 body('    function work.resourceAllowed(', '    function work.resourceTool(')
 cfg.worldResource={byId={crystalNode={requireToolType='pickaxe'}}};work.resourceNeeds={};motion.blocked={};opts.onlyNeeded=true;flags.gather=true
 work.resourceTool=function()return{}end;work.resourceKind=function()return'other'end
 selectedEmpty=function()return true end;allowed=function()return true end
 local crystal=model('Crystal');crystal.attrs.resourceId='crystalNode';crystal.attrs.hp=20
 assert(work.resourceEligible(crystal,'stockpile',false)and not work.resourceEligible(crystal,'gather',false))
end)
test('footprint route progresses toward its owning chest then opens it',function()
 local chest=model('Chest',vec(0,0,0));local a=model('footprint',vec(20,0,0));local b=model('footprint',vec(10,0,0));chest.children={b,a}
 work.chestCandidate=function()return chest end;local state={};work.chestState=function()return state end;local steps={}
 travel=function(mark,key)assert(key=='chests');steps[#steps+1]=mark;return true end
 work.openChest=function()return true end
 assert(work.followTrail()and steps[1]==a and steps[2]==b and state.trailIndex==2 and work.chestResume==chest)
end)
test('artifact collection holds the verified native five seconds before confirming',function()
 body('    function work.fetchArtifact()', '    work.artifacts = {}')
 local m=model('Map');local receipt
 local prompt={Enabled=true,HoldDuration=5,MaxActivationDistance=10,
  Triggered={Connect=function(_,fn)receipt=fn;return{Disconnect=function()end}end},InputHoldBegin=function()schedule[#schedule+1]={at=5,fn=function()receipt();work.artifacts.Map=true end}end,InputHoldEnd=function()end}
 m.ProximityPrompt=prompt;m.FindFirstChild=function()return{FindFirstChildOfClass=function()return prompt end}end
 work.artifactCandidate=function()return m end;work.artifacts={};work.setSprint=function()end
 assert(work.fetchArtifact()and now>=5 and work.artifacts.Map)
end)
test('native loaded artifact hint text is read and shown with the footprint objective',function()
 local m=model('Map');models.artifacts={m};work.artifacts={};cfg.mapProp={byCnId={Map={hint='Find the cave entrance'}}}
 flags.followFootprints=true;work.hintLabel={};work.readObjectiveHints()
 assert(work.hintLabel.Text:find('Find the cave entrance',1,true)and work.hintLabel.Text:find('FOOTPRINTS',1,true))
end)
test('repeated melee cycles attack again after cooldown and repositioning',function()
 body('    function work.strike(', '    local function blueprintReady(')
 local defend=assert(load(extract('    local function defend(', '    function work.pickupCandidate(')..'\nreturn defend'))()
 local target=model('Spider');target.Humanoid={Health=30};local t=held('Axe',1);local stats={range=6,toolType='axe',useCd=1,windup=.1,capAOE=1}
 opts.jobTimeout=15;work.sent=0;work.meleeWeapon=function()return t,stats end
 equip=function()end;work.setSprint=function()end;work.checkpoint=function()return true end;work.recordGuard=function()end;work.personalThreat=function()return nil end
 work.attackPhase=function()return'unknown'end
 work.attackPlan=function()if target.Humanoid.Health>0 then return target,vec(5.25,3,0)end end
 travel=function(point)r.Position=point;return true end
 CFrame={lookAt=function(a,b)return{LookVector=(b-a).Unit}end}
 local times={};work.activateWeapon=function()times[#times+1]=now;target.Humanoid.Health=target.Humanoid.Health-10;return true end
 work.kite=function()r.Position=vec(9,3,0)end
 assert(defend('combat')and #times==3 and times[2]-times[1]>=1 and times[3]-times[2]>=1)
end)
test('daytime Shadow cannot contaminate danger checks but becomes hostile at night',function()
 body('    function work.isHostile(', '    function work.creatures(')
 local shadow=model('Shadow');work.isNight=function()return false end
 assert(not work.isHostile(shadow,{atkDmg=100,mobClass='Shadow'}))
 work.isNight=function()return true end;assert(work.isHostile(shadow,{atkDmg=100}))
end)
test('retaliation uses native reach even when every surrounding stance is unsafe',function()
 local target=model('Spider',vec(0,0,0));local neighbour=model('Spider',vec(5,3,0))
 work.hostiles=function()return{{model=neighbour,point=neighbour.point,human={Health=100}}}end
 work.enemyReach=function()return 5 end
 local stats={range=6,toolType='axe'}
 assert(not work.stanceScore(r.Position,target,stats))
 assert(work.stanceScore(r.Position,target,stats,true))
 assert(not work.stanceScore(vec(30,3,0),target,stats,true))
end)
test('automatic catalogue normalizes deduplicates and reads nested native code records',function()
 body('    function work.codeCatalogue()', '    function work.redeemTick()')
 cfg.codes={list={{code=' hello '},'SECOND'},byCode={THIRD={grantReward={}}}};opts.codes='HELLO;FOURTH'
 local codes=work.codeCatalogue();local found={}for _,v in ipairs(codes)do found[v]=true end
 assert(#codes==4 and found.HELLO and found.SECOND and found.THIRD and found.FOURTH)
end)
test('raw storage reclaim continues until cooked reserves meet the target',function()
 held('Cooked',8);assert(work.foodSupplyGoal().amounts.raw==nil)
 bag={};work.storageSnapshot={{displayName='Raw',count=20}}
 assert(work.foodSupplyGoal().amounts.raw==1)
end)
test('only nighttime enables low hover even if the old emergency flag was saved',function()
 body('    function work.shelterNeeded()', '    function work.releaseHover(')
 flags.holdNight=true;flags.nightHover=true;flags.emergencyHover=true
 local night=false;work.isNight=function()return night end
 assert(not work.shelterNeeded());night=true;assert(work.shelterNeeded())
 night=false;h.Health=20;assert(not work.shelterNeeded());h.Health=100
 work.danger=function()return 1,nil,4 end;assert(not work.shelterNeeded())
end)
test('hover uses checked positions and lowers its height rather than climbing after unexplained damage',function()
 body('    function work.releaseHover(', '    function work.evaluateLost()')
 local mt={__add=function(a,b)return setmetatable({Position=a.Position+b},getmetatable(a))end}
 CFrame={new=function(p)return setmetatable({Position=p},mt)end}
 local fire=model('Campfire');built=function()return fire end
 r.Parent=true;r.Anchored=false;r.CFrame=CFrame.new(r.Position)
 motion.floor=function(p)return vec(p.X,0,p.Z)end
 work.hoverBodyClear=function()return true end;work.hoverClearance=function()return 20 end
 work.hoverDestination=function(_,height)return{land=vec(12,3,0),point=vec(12,3+height,0)}end
 flags.nightHover=true;opts.hoverHeight=8;work.shelterNeeded=function()return true end
 assert(work.nightHold()and r.Anchored and work.hover.height==8)
 h.Health=90;now=1;assert(work.nightHold()and work.hover.height==6 and r.CFrame.Position.Y==9)
 assert(not work.releaseHover()and r.Anchored)
 work.shelterNeeded=function()return false end;work.safeWorkPoint=function()return false end
 assert(not work.releaseHover()and r.Anchored)
 work.safeWorkPoint=function()return true end
 assert(work.releaseHover()and not r.Anchored and not work.hover and r.CFrame.Position.Y==3)
end)
test('stopping automation always releases its owned hover anchor',function()
 body('    function work.releaseHover(', '    function work.nightHold()')
 r.Parent=true;r.Anchored=true;work.hover={root=r,anchored=false,character=player.Character,land={Position=vec(0,3,0)}}
 assert(work.releaseHover(true)and not r.Anchored and not work.hover)
end)
test('a stalled native read yields the queue within seven seconds',function()
 body('    function work.recordCost(', '    local function module(')
 local cancelled=false
 task.spawn=function()return'pending'end;task.cancel=function(t)assert(t=='pending');cancelled=true end
 local ok,err=pcall(work.boundedRead,function()end,'chest')
 assert(not ok and tostring(err):find('timed out')and cancelled and now>=6.5 and now<7)
end)
test('bounded native reads preserve false and multiple return values',function()
 body('    function work.recordCost(', '    local function module(')
 task.spawn=function(fn)fn();return'finished'end
 local first,second=work.boundedRead(function()return false,'locked'end,'chest')
 assert(first==false and second=='locked')
end)
assert(loadfile('Games/MrbeastIslandEscape.lua'))
print(n..' storm food, native interaction, combat and storage checks passed; module compiles')
