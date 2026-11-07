local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local V={};V.__index=function(p,k)if k=='Magnitude'then return math.sqrt(p.X*p.X+p.Y*p.Y+p.Z*p.Z)end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
local now,cfg,bag,drops,r,h,camp,events,scene
local function model(name,point,attrs)
 local m={Name=name,point=point or vec(10,0,0),Parent=true,attrs=attrs or{}}
 function m:GetAttribute(k)return self.attrs[k]end
 function m:IsA(k)return k=='Model'end
 function m:FindFirstChildWhichIsA()return nil end
 function m:GetChildren()return{}end
 return m
end
local function tool(id,n)
 local item=cfg.item.byId[id];local t=model(item.displayName,nil,{count=n or 1});t.Parent=player.Character
 function t:Activate()self.attrs.count=self.attrs.count-1;if self.attrs.count==0 then self.Parent=nil end;h.attrs.hunger=math.min(100,h.attrs.hunger+40)end
 bag[#bag+1]=t;return t
end
local function setup()
 now=0;bag={};drops={};events={};os.clock=function()return now end
 flags={cook=true,autoFarm=true,unloadBag=true,stormStock=true,killFoodOnSight=true,useStorage=true,quest=true}
 opts={jobTimeout=15,health=50,hunger=40,foodReserve=8,stormReserve=20,enemyReach=4,combatMargin=1,shadowRadius=20,hoverHeight=8}
 cfg={item={byId={},byDisplayName={}},food={byId={raw={canCook=true,cookTargetId='cooked'},cooked={canCook=false}}},tool={byId={},byDisplayName={}},
  bag={byId={}},armour={byId={}},build={byId={campfire={assetId='Campfire'}}},misc={collectRadius=3},freeBuild={byCnId={}}}
 for id,name in pairs({raw='Raw',cooked='Cooked',wood='Wood',axe='Axe',axe2='Axe2',torch='Torch'})do
  local item={id=id,displayName=name,isBagItem=id~='axe'and id~='axe2'and id~='torch',type=(id=='axe'or id=='axe2'or id=='torch')and'tool'or'material'}
  cfg.item.byId[id]=item;cfg.item.byDisplayName[name]=item
 end
 cfg.item.byId.torch.isLightSource=true
 for id,row in pairs({axe={toolType='axe',lvl=1,atkDmg=5},axe2={toolType='axe',lvl=2,atkDmg=10},torch={toolType='torch',lvl=1,atkDmg=1}})do cfg.tool.byId[id]=row;cfg.tool.byDisplayName[cfg.item.byId[id].displayName]=row end
 player={Name='Tester',Character={},GetAttribute=function()return nil end};motion={serial=0};alive=true;campData={};due={};failed={}
 r={Position=vec(10,3,0),Size=vec(2,2,2),Parent=true,CollisionGroup='Characters'}
 h={Health=100,MaxHealth=100,HipHeight=2,attrs={hunger=100,maxHunger=100},GetAttribute=function(self,k)return self.attrs[k]end}
 camp=model('Campfire',vec(0,0,0));scene={Day={Value=1},IsRaining={Value=false}}
 scene.FindFirstChild=function(self,k)if k=='DroppedItems'then return{GetChildren=function()return drops end}end return self[k]end
 config=function()return cfg end;root=function()return r,h end;world=function()return scene end;pos=function(m)return m.point or m.Position end;built=function(name)return name=='Campfire'and camp end
 tools=function()local rows={}for _,t in ipairs(bag)do if t.Parent then rows[#rows+1]=t end end return rows end
 count=function(name)local n=0;for _,t in ipairs(tools())do if t.Name==name then n=n+t.attrs.count end end return n end
 selectedEmpty=function()return true end;allowed=function()return true end
 nearest=function(list,fn)for _,m in ipairs(list)do if m.Parent and fn(m)then return m end end end
 note=function(key,text)events[#events+1]=key..':'..text end
 Vector3={new=vec};task={wait=function()now=now+.02 end}
 RS={FindFirstChild=function()return nil end};workspace={GetServerTimeNow=function()return now end}
 work={models=function(k)return k=='drops'and drops or{}end,selectedCraftMaterialGoal=function()end,
  safeResource=function()return true end,safeWorkPoint=function()return true end,insideBorder=function()return true end,
  stationGoal=function()end,taskDemand=function()return 0 end,goalAmounts=function(goal)return goal.amounts or{}end,
  invalidateInventory=function()end,running=function()return not work.preempted end,checkpoint=function()return not work.preempted end,
  tidyBag=function()return false end,submitGoal=function()return false end,cookReady=function()return false end,
  noFood=function()return count('Cooked')==0 end,rawFoodOwned=function()return count('Raw')>0 end,
  interactPrompt=function()return nil end,recordPickup=function()end,findStructure=function()return model('Storage')end}
 work.bagState=function()local used=0;for _,t in ipairs(tools())do if cfg.item.byDisplayName[t.Name].isBagItem then used=used+t.attrs.count end end return used,15 end
 work.canCollect=function()return work.bagState()<15 end
 work.await=function(_,predicate,seconds)local untilTime=now+(seconds or 3)repeat if predicate()then return true end;task.wait()until now>=untilTime or work.preempted;return false end
 travel=function(target,key)events[#events+1]='travel:'..key;if target.X then r.Position=target end;return true end
 call=function(service,action,arg)
  events[#events+1]=service..':'..action
  if action=='dropItem'then
   arg.attrs.count=arg.attrs.count-1;if arg.attrs.count==0 then arg.Parent=nil end
   drops[#drops+1]=model(arg.Name,vec(r.Position.X,0,r.Position.Z),{ownerName='Tester'})
  elseif service=='MakeFire'and action=='collectFood'then campData.readyCount=campData.readyCount-1;tool('cooked',1)
  elseif service=='ItemCollect'then arg.Parent=nil;tool(cfg.item.byDisplayName[arg.Name].id,1)
  elseif service=='Storage'and action=='takeItem'then
   local slot=work.storageSnapshot[tostring(arg)];local id=cfg.item.byDisplayName[slot.displayName].id;tool(id,slot.count);work.storageSnapshot[tostring(arg)]=nil
  end
 end
 body('    function work.markCampDrop(', '    function work.collectModel(')
 body('    function work.collectModel(', '    function work.treeDropContext(')
 body('    function work.batchDrop(', '    function work.watchLateDrops(')
 body('    function work.stormActive()', '    local jobsList = {')
 body('    function work.foodAllowed(', '    function work.cookCompatible(')
 work.findStructure=function()return model('Storage')end
 work.foodCachePoint=function()return vec(10,3,0)end
 work.campDropPoint=work.foodCachePoint;work.campDropClear=function()return true end
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
local function eventCount(value)local n=0;for _,e in ipairs(events)do if e==value then n=n+1 end end return n end

test('a bag full of cooked food is emptied into the camp pile using acknowledged one-unit drops',function()
 tool('cooked',20);assert(work.cacheFood()and count('Cooked')==0 and #drops==20)
 assert(eventCount('PlayerInventory:dropItem')==20 and work.foodCounts()==20)
end)
test('a healthy player keeps no carried meals even across separate stacks',function()
 tool('cooked',1);tool('cooked',2);tool('cooked',3)
 assert(work.cacheFood()and count('Cooked')==0 and #drops==6)
end)
test('a hungry player retains exactly one meal across all stacks',function()
 local first=tool('cooked',3);tool('cooked',4);h.attrs.hunger=10
 assert(work.foodKeepCount('cooked',first)==1)
 assert(work.cacheFood()and count('Cooked')==1 and #drops==6)
end)
test('healthy on-sight mode does not pick its cooked camp stockpile back up',function()
 tool('cooked',3);assert(work.cacheFood());local drop=drops[1]
 assert(work.markCampDrop(drop)and not work.dropAllowed(drop)and not work.pickupEligible(drop))
 h.attrs.hunger=10;assert(work.dropAllowed(drop)and work.pickupEligible(drop))
end)
test('one collected meal closes the pickup gate until it has been eaten',function()
 h.attrs.hunger=10;local drop=model('Cooked',vec(10,0,0),{ownerName='Tester'});drops={drop}
 assert(work.takeMeal('eat')and count('Cooked')==1)
 local nextDrop=model('Cooked',vec(10,0,0),{ownerName='Tester'});assert(not work.foodPickupWanted(nextDrop,'cooked'))
end)
test('the native cooked-food request is dispatched only once and grants one meal',function()
 h.attrs.hunger=10;campData.readyCount=10;campData.readyFoodId='cooked'
 assert(work.takeMeal('eat')and count('Cooked')==1 and campData.readyCount==9)
 assert(work.takeMeal('eat')and eventCount('MakeFire:collectFood')==1)
end)
test('a delayed cooked-food receipt retains its lease instead of sending duplicate collects',function()
 campData.readyCount=10;campData.readyFoodId='cooked';call=function(service,action)events[#events+1]=service..':'..action end
 assert(not work.collectCookedUnit('eat'));assert(not work.collectCookedUnit('eat'))
 assert(eventCount('MakeFire:collectFood')==1)
 tool('cooked',1);assert(work.collectCookedUnit('eat')and eventCount('MakeFire:collectFood')==1)
end)
test('native ownerless cooked drops at the fire count as stock without being claimed prematurely',function()
 drops={model('Cooked',vec(4,0,0),{})};assert(work.foodCounts()==1 and not work.dropAllowed(drops[1]))
 h.attrs.hunger=10;assert(work.dropAllowed(drops[1]))
end)
test('raw food staging leaves room for quest materials instead of filling the bag',function()
 local raw=model('Raw',vec(60,0,0),{})
 assert(work.foodPickupWanted(raw,'raw'));tool('raw',4);assert(not work.foodPickupWanted(raw,'raw'))
 work.questRequirement={itemId='raw',count=10};work.questTotal=function()return 4 end
 assert(work.foodPickupWanted(raw,'raw'))
end)
test('food in legacy whole-stack storage is moved to camp instead of becoming a permanent carry ration',function()
 work.storageSnapshot={['1']={displayName='Cooked',count=10}}
 assert(work.foodCacheReady()and work.cacheFood())
 assert(count('Cooked')==0 and #drops==10 and work.storageSnapshot['1']==nil)
end)
test('ordinary supplies are dropped while current recipe quantities alone are retained',function()
 tool('wood',20);work.objective={kind='craft',amounts={wood=5}}
 assert(work.unloadBag()and count('Wood')==5 and #drops==15)
end)
test('duplicate tools and every torch are stockpiled while the best working axe stays available',function()
 tool('axe',1);tool('axe2',1);tool('axe2',1);tool('torch',5)
 assert(work.unloadBag());assert(count('Axe')==0 and count('Axe2')==1 and count('Torch')==0)
end)
test('world food reserves follow native one-unit collection rather than an uncollectable stack attribute',function()
 drops={model('Cooked',vec(4,0,0),{count=99})};assert(work.foodCounts()==1)
end)
test('health-only eating rejects a zero-healing meal while hunger eating still permits it',function()
 cfg.food.byId.cooked.healthRegen=0;h.Health=30
 assert(not work.foodAllowed('food','cooked'))
 h.attrs.hunger=10;assert(work.foodAllowed('food','cooked'))
 cfg.food.byId.cooked.healthRegen=-5;assert(not work.foodAllowed('food','cooked'))
end)
test('eating waits for the native animation receipt instead of giving up after three seconds',function()
 h.attrs.hunger=10;local meal=tool('cooked',1);local receiptAt
 meal.Activate=function()receiptAt=now+4.5 end
 local sleep=task.wait
 task.wait=function()sleep();if receiptAt and now>=receiptAt then meal.Parent=nil;h.attrs.hunger=80;receiptAt=nil end end
 work.pause=function(_,duration)local untilTime=now+duration;repeat task.wait()until now>=untilTime;return true end
 work.signature=function()return tostring(count('Cooked'))end;equip=function()end
 local eat=assert(load(extract('    local function eat()', '    function work.markCampDrop(')..'\nreturn eat'))()
 assert(eat()and now>=4.5 and now<5 and work.interaction==nil)
end)
print(n..' camp stockpile, one-meal, tool overflow and native receipt checks passed')
