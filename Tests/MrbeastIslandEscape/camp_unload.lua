-- Run from repo root: lua Tests/MrbeastIslandEscape/camp_unload.lua
-- Executes production storage/drop helpers against native one-unit drop semantics.
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local path=os.getenv('EXIS_MRBEAST_SOURCE')or'Games/MrbeastIslandEscape.lua'
local f=assert(io.open(path));local source=f:read('*a');f:close()
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
Vector3={new=vec}
local oldClock=os.clock
local now,held,drops,cfg,events,scheduled,rootPart,camp
local function model(name,owner)
 local m={Name=name,Parent=true,point=vec(0,0,9),attrs={ownerName=owner}}
 function m:GetAttribute(k)return self.attrs[k]end
 return m
end
local function setup()
 now=0;held={};drops={};events={};scheduled={};rootPart={Position=vec(0,0,9)};camp={point=vec(0,0,0)}
 os.clock=function()return now end
 flags={unloadBag=true,tidyBag=true};opts={jobTimeout=15,onlyNeeded=true,health=50,hunger=40}
 cfg={item={byId={},byDisplayName={}},build={byId={campfire={assetId='Campfire'}}},tool={byId={}},bag={byId={}},armour={byId={}},food={byId={}}}
 config=function()return cfg end
 player={Name='Tester',Character={}};motion={serial=0};workspace={GetServerTimeNow=function()return now end}
 root=function()return rootPart,{Health=100,MaxHealth=100,GetAttribute=function(_,k)return 100 end}end
 pos=function(m)return m.point end
 tools=function()local a={}for _,t in ipairs(held)do if t.Parent then a[#a+1]=t end end return a end
 count=function(name)local n=0 for _,t in ipairs(tools())do if t.Name==name then n=n+(t.attrs.count or 1)end end return n end
 built=function(name)if name=='Campfire'then return camp end end
 world=function()return{FindFirstChild=function()end}end
 note=function()end
 travel=function(_,key,radius)events[#events+1]='travel';assert(key=='unloadBag'and radius==9);return true end
 task={wait=function()now=now+.02 for _,e in ipairs(scheduled)do if not e.done and now>=e.at then e.done=true;e.run()end end end}
 work={selectedCraftMaterialGoal=function()end,sent=0,artifactNames={Compass=true},models=function()return drops end,safeResource=function()return true end,
  running=function()return not work.preempted end,checkpoint=function()return not work.preempted end,
  invalidateInventory=function()end,stationGoal=function()end,taskDemand=function()return 0 end,
  noFood=function()return false end,submitGoal=function()return false end,goalAmounts=function(g)return g.amounts or{}end,
  tidyBag=function()events[#events+1]='submit';return false end}
 work.bagState=function()local n=0 for _,t in ipairs(tools())do local i=cfg.item.byDisplayName[t.Name];if i and i.isBagItem then n=n+(t.attrs.count or 1)end end return n,5 end
 work.await=function(key,predicate,seconds)local deadline=now+(seconds or 3)repeat if predicate()then return true end if work.preempted then return false end task.wait()until now>=deadline return false end
 call=function(service,action,tool)
  assert(service=='PlayerInventory'and action=='dropItem');events[#events+1]='drop:'..tool.Name
  tool.attrs.count=tool.attrs.count-1;if tool.attrs.count==0 then tool.Parent=nil end
  drops[#drops+1]=model(tool.Name,player.Name)
 end
 body('    function work.markCampDrop(', '    function work.collectModel(')
 body('    function work.batchDrop(', '    function work.watchLateDrops(')
end
local function tool(id,name,n,extra)
 local item={id=id,displayName=name,isBagItem=true};for k,v in pairs(extra or{})do item[k]=v end
 cfg.item.byId[id]=item;cfg.item.byDisplayName[name]=item
 local t=model(name);t.attrs.count=n;held[#held+1]=t;return t
end
local passed=0
local function test(name,fn)setup();fn();passed=passed+1;print('PASS '..name)end
local function eventCount(prefix)local n=0 for _,v in ipairs(events)do if v:sub(1,#prefix)==prefix then n=n+1 end end return n end
test('usable submission is attempted before camp travel and leftover drops',function()
 tool('wood','Wood',3);assert(work.unloadBag())
 assert(events[1]=='submit'and events[2]=='travel'and eventCount('drop:')==3)
 local used=work.bagState();assert(used==0 and #drops==3)
end)
test('items successfully submitted are not dropped a second time',function()
 local t=tool('wood','Wood',3)
 work.tidyBag=function()events[#events+1]='submit';t.Parent=nil;return true end
 assert(work.unloadBag());assert(#events==1)
end)
test('an absent campfire never causes drops at an arbitrary location',function()
 tool('wood','Wood',3);camp=nil
 assert(not work.unloadBag()and eventCount('drop:')==0)
end)
test('unsafe campfire defers unloading without spending inventory',function()
 tool('wood','Wood',3);work.safeResource=function()return false end
 assert(not work.unloadBag()and count('Wood')==3 and #events==0)
end)
test('tools, spare bags, armour and escape artifacts are protected',function()
 cfg.tool.byId.axe={};cfg.bag.byId.bag2={};cfg.armour.byId.vest={}
 tool('axe','Axe',1);tool('bag2','Bag2',1);tool('vest','Vest',1);tool('compass','Compass',1)
 assert(work.unloadCandidate()==nil and not work.unloadBag()and eventCount('drop:')==0)
end)
test('current direct-craft ingredients stay in the bag until the recipe can be crafted',function()
 tool('wood','Wood',3);tool('stone','Stone',2)
 work.objective={kind='craft',amounts={wood=5}}
 assert(work.unloadBag());assert(count('Wood')==3 and count('Stone')==0)
end)
test('a stack of eleven uses acknowledged eight-plus-three native drop batches',function()
 tool('wood','Wood',11);assert(work.unloadBag())
 assert(count('Wood')==0 and eventCount('drop:')==11 and #drops==11)
end)
test('urgent interruption stops the remaining unload batches',function()
 tool('wood','Wood',11);local wait=task.wait
 task.wait=function()wait();work.preempted=true end
 assert(work.unloadBag());assert(eventCount('drop:')==8 and count('Wood')==3)
end)
test('unclassified inventory and non-bag equipment are never discarded',function()
 tool('axe','Axe',1,{isBagItem=false});held[#held+1]=model('Unknown')
 assert(work.unloadCandidate()==nil)
end)
test('own camp stash is excluded from gathering even when needed-only is off',function()
 tool('wood','Wood',2);assert(work.unloadBag());opts.onlyNeeded=false
 assert(work.campStash[drops[1]]and not work.dropAllowed(drops[1]))
end)
test('pre-existing camp loot is never reclassified as an unload drop',function()
 local original=model('Wood',player.Name);drops[1]=original
 tool('wood','Wood',1);assert(work.unloadBag())
 assert(not work.campStash[original]and work.dropAllowed(original))
end)
test('another player\'s protected drops are not marked or collected',function()
 local foreign=model('Wood','Other');foreign.attrs.protectEndTick=100;drops[1]=foreign
 tool('wood','Wood',1);assert(work.unloadBag())
 assert(not work.campStash[foreign]and not work.dropAllowed(foreign))
end)
test('stashed ingredients become available when a safe future blueprint needs them',function()
 tool('wood','Wood',1);assert(work.unloadBag())
 local target={};work.objective={kind='build',info={assetId='Bench'}};work.taskDemand=function()return 2 end
 world=function()return{FindFirstChild=function()return{FindFirstChild=function()return target end}end}end
 assert(work.dropAllowed(drops[1]))
 work.safeResource=function()return false end;assert(not work.dropAllowed(drops[1]))
end)
test('late camp drop replication is captured without guessing pre-existing ownership',function()
 tool('wood','Wood',1)
 call=function(_,_,t)t.attrs.count=0;t.Parent=nil;scheduled[#scheduled+1]={at=now+.2,run=function()drops[#drops+1]=model('Wood',player.Name)end}end
 assert(work.unloadBag());while now<.25 do task.wait()end
 work.captureCampDrops();assert(work.campStash[drops[1]]and not work.dropAllowed(drops[1]))
end)
test('failed drop acknowledgement cannot resend a pending native batch',function()
 tool('wood','Wood',2);local n=0
 call=function()n=n+1 end
 assert(not work.unloadBag());assert(n==2)
 work.unloadBag();assert(n==2)
end)
test('full-bag unloading ranks before resuming chest loot collection',function()
 body('    function work.rank(job)', '    function work.pick(')
 tool('wood','Wood',5);work.chestResume={}
 assert(work.rank{key='unloadBag'}<work.rank{key='chests'})
 work.active='unloadBag';work.unloadRank=3.9;held={}
 assert(work.rank{key='unloadBag'}==3.9)
end)
os.clock=oldClock
assert(loadfile(path))
print(passed..' camp unload checks passed; complete module compiles')
