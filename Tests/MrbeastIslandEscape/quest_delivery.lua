local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
local function signal()
 local handlers={};return{Connect=function(_,fn)local x={fn=fn};handlers[#handlers+1]=x;return{Disconnect=function()x.off=true end}end,
 Fire=function(_,...)for _,x in ipairs(handlers)do if not x.off then x.fn(...)end end end}
end
local now,cfg,scene,queue,update,accepted,fetchResult,held,drops,calls,afterTravel,afterSubmit,bag,character
local function setup()
 now=0;os.clock=function()return now end;queue={};held={wood=0,stone=0,torch=0};drops={};calls={};bag={};afterTravel=nil;afterSubmit=nil
 flags={quest=true};opts={jobTimeout=15};due={};connections={};alive=true;motion={serial=1};character={};player={Name='Tester',Character=character,GetAttribute=function()end}
 cfg={item={byId={},byDisplayName={},byName={}},bag={byCn={}},mrbeastQuestList={list={{index=1,require='Woodx5|Stonex2',fixedReward='Better Axe'}}}}
 for id,name in pairs({wood='Wood',stone='Stone',torch='Torch'})do local it={id=id,displayName=name};cfg.item.byId[id]=it;cfg.item.byDisplayName[name]=it;cfg.item.byName[name]=it end
 config=function()return cfg end;count=function(name)return held[name:lower()]or 0 end
 local area={};local npc={FindFirstChild=function()return area end}
 scene={FindFirstChild=function(_,name)if name=='Mrbeast'then return npc elseif name=='DroppedItems'then return{GetChildren=function()return drops end}end end}
 world=function()return scene end
 update=signal();accepted=signal();local service={FindFirstChild=function(_,name)if name=='questUpdateRemote'then return{OnClientEvent=update}elseif name=='questSubmittedRemote'then return{OnClientEvent=accepted}end end}
 RS={Engine={Service={FindFirstChild=function()return service end}}}
 fetchResult={1,1,7}
 local q={getQuestRequirement=function(index,alt)return{itemId=alt==2 and'stone'or'wood',count=alt==2 and 2 or 5}end,
 client={fetchQuest=function()return table.unpack(fetchResult)end,submitQuest=function(models,revision)
  calls[#calls+1]={models=models,revision=revision};if afterSubmit then afterSubmit()end
 end}}
 module=function()return q end
 work={boundedRead=function(fn)return fn()end,sent=0,refreshAt=0,bagState=function()return 2,15 end,
 running=function()return not work.preempted end,questStatus='WORKING',invalidateInventory=function()end}
 task={spawn=function(fn)queue[#queue+1]=fn end,wait=function(n)now=now+(n or .05)end}
 work.await=function(_,fn,seconds)local deadline=now+seconds repeat if fn()then return true end;if work.preempted then return false end;task.wait()until now>=deadline;return false end
 tools=function()local out={}for _,t in ipairs(bag)do if t.Parent and held[t.id]>0 then out[#out+1]=t end end;return out end
 equip=function(t)t.Parent=player.Character end
 travel=function()if afterTravel then afterTravel()end;return true end
 note=function()end
 body('    function work.questCatalog(', '    local function questTick(')
 questTick=assert(load(extract('    local function questTick(', '    function work.waterDrop()')..'\nreturn questTick'))()
 work.batchDrop=function(tool,n)
  held[tool.id]=held[tool.id]-n
  for i=1,n do drops[#drops+1]={Name=tool.Name,Parent=true,IsA=function()return true end,GetAttribute=function(_,k)return k=='ownerName'and player.Name or false end}end
  return n
 end
 work.readQuest(true);queue[1]();queue={}
end
local function tool(id,n)
 held[id]=held[id]+n
 local t={id=id,Name=cfg.item.byId[id].displayName,Parent={},GetAttribute=function(_,k)if k=='count'then return n end end}
 bag[#bag+1]=t;return t
end
local function dropped(id,owner,collecting)
 local m={Name=cfg.item.byId[id].displayName,Parent=true,IsA=function()return true end,GetAttribute=function(_,k)if k=='ownerName'then return owner elseif k=='collecting'then return collecting end end}
 drops[#drops+1]=m;return m
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('a complete equipped native stack and explicit acceptance finish the quest',function()
 local t=tool('wood',5);afterSubmit=function()assert(t.Parent==character);accepted:Fire()end
 assert(questTick('quest',true)and #calls==1 and calls[1].revision==7 and not work.questSubmission)
end)
test('backpack contents must actually equip before the native submission',function()
 tool('wood',5);equip=function()end
 assert(not questTick('quest',true)and #calls==0)
end)
test('owned matching world drops plus one held stack satisfy the native request',function()
 tool('wood',2);for i=1,3 do dropped('wood','Tester')end
 afterSubmit=function()accepted:Fire()end
 assert(questTick('quest',true)and #calls[1].models==3)
end)
test('foreign drops and collecting models are never counted or submitted',function()
 dropped('wood','Other');dropped('wood','Tester',true);tool('wood',2)
 assert(work.questTotal(work.questRequirement)==2)
 assert(questTick('quest',true)and #calls==0 and #work.questDrops(work.questRequirement)==2)
end)
test('day or revision change without acceptance cannot fabricate quest completion',function()
 tool('wood',5);afterSubmit=function()update:Fire(2,2,8)end
 assert(not questTick('quest',true)and #calls==1 and work.questSubmission)
end)
test('a nil quest snapshot is not a successful delivery receipt',function()
 tool('wood',5);afterSubmit=function()update:Fire(nil,nil,8)end
 assert(not questTick('quest',true)and #calls==1)
end)
test('changed quest during travel prevents stale submission and stale dropping',function()
 tool('wood',2);afterTravel=function()update:Fire(2,2,8)end
 assert(not questTick('quest',true)and #calls==0 and held.wood==2 and #drops==0)
end)
test('unconfirmed submissions retain a lease and retry only after refreshing',function()
 tool('wood',5);work.preempted=true
 assert(not questTick('quest',true)and #calls==0)
 work.preempted=nil;afterSubmit=function()work.preempted=true end
 assert(not questTick('quest',true)and #calls==1 and work.questSubmission)
 work.preempted=nil;assert(not questTick('quest',true)and #calls==1)
 now=4;assert(not questTick('quest',true)and #calls==1 and not work.questSubmission and #queue>=1)
 afterSubmit=function()accepted:Fire()end
 assert(questTick('quest',true)and #calls==2)
end)
test('a late acceptance reconciles the pending submission without resending it',function()
 tool('wood',5);afterSubmit=function()work.preempted=true end
 assert(not questTick('quest',true)and #calls==1)
 accepted:Fire();work.preempted=nil;assert(questTick('quest',true)and #calls==1)
end)
test('server acceptance still counts if the next quest update arrives first',function()
 tool('wood',5);afterSubmit=function()update:Fire(2,2,8);accepted:Fire()end
 assert(questTick('quest',true)and work.questRequirement.itemId=='stone')
end)
test('older revisions cannot overwrite newer pushes',function()
 update:Fire(2,2,9);update:Fire(1,1,8);assert(work.questRequirement.itemId=='stone'and work.questCache.revision==9)
end)
test('a new scene rebinds the same native remote instead of keeping an obsolete closure',function()
 scene={FindFirstChild=function()return{}end};work.readQuest(true)
 update:Fire(2,2,9);assert(work.questRequirement.itemId=='stone'and work.questCache.revision==9)
end)
test('old asynchronous fetches cannot clear a newer scene fetch token',function()
 now=3;work.readQuest(true);local old=queue[#queue]
 scene={FindFirstChild=function()return{}end};work.readQuest(true);local token=work.questFetchPending
 old();assert(work.questFetchPending==token)
end)
test('live quest details show exact alternate quantity progress and preferred reward',function()
 tool('wood',2);dropped('wood','Tester')
 local text=work.questDetails(work.questRequirement,1,1,7)
 assert(text:find('GIVE 5 Wood',1,true)and text:find('MISSING 2',1,true)and text:find('Better Axe',1,true))
end)
test('a streamed-out NPC does not erase the requested materials or revision',function()
 scene.FindFirstChild=function()end
 local req,index,alt,revision=work.readQuest(true)
 assert(req and req.itemId=='wood'and index==1 and alt==1 and revision==7 and work.questRequirement==req)
end)
test('live catalogue preserves real requirements timing and pool metadata instead of inventing a fixed quest list',function()
 cfg.mrbeastQuestTiming={list={{apearDesc='Daytime',questResetRange='1 to 3'}}}
 cfg.mrbeastQuestPrior={list={{poolItems='Better Axe,Better Bag',weight=10,isEdge=false}}}
 local text=work.questCatalog()
 assert(text:find('Woodx5|Stonex2',1,true)and text:find('Better Axe,Better Bag',1,true)and text:find('Daytime',1,true))
end)
print(n..' native MrBeast submission, receipt, retry and scene lifecycle checks passed')
