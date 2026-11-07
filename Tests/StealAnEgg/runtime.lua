local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
local function extract(a,b)local x=assert(source:find(a,1,true));local y=assert(source:find(b,x+#a,true));return source:sub(x,y-1)end
local function fn(name,nextName)return assert(load(extract('local function '..name..'(',nextName)..'\nreturn '..name))()end
Core=assert(loadfile('Games/StealAnEgg.lua'))('EXIS_TEST')
local now,r,c,owned,walked,carry,notes
local function setup()
 now=0;os.clock=function()return now end;owned={};walked=false;carry={IsCarrying=true,Uid='u'};notes={}
 state={claimed=0,training=false};player={UserId=1};options={};pending={};alive=true
 note=function(v)notes[#notes+1]=v end
 carrying=function()return carry end;stopTraining=function()return true end
 Vector3={new=function()return 0 end};plot=function()return{PetArea={Position=10}}end
 walk=function(goal,uid)assert(goal==10 and uid=='u');walked=true;carry={IsCarrying=false};return true end
 await=function(predicate)return predicate()end
 api={eggs={ReadOwnerEggs=function()return owned end}}
end
local n=0
local function test(name,f)setup();f();n=n+1;print('PASS '..name)end
test('carry loss is not reported as successful delivery',function()
 local run=fn('returnEgg','local function stealEgg(')
 assert(not run()and walked and state.claimed==0)
end)
test('delivery requires an owned egg receipt after walking',function()
 local calls=0;api.eggs.ReadOwnerEggs=function()calls=calls+1;if calls==1 then return{}end return{u={}}end
 assert(fn('returnEgg','local function stealEgg(')()and walked and state.claimed==1)
end)
test('no base waits instead of teleporting away with the egg',function()
 plot=function()return nil end;assert(not fn('returnEgg','local function stealEgg(')()and not walked)
end)
test('treadmill exit rejection prevents return movement',function()
 stopTraining=function()return false end;assert(not fn('returnEgg','local function stealEgg(')()and not walked)
end)
test('an uncertain carry call prevents a second teleport and pickup',function()
 pending.carry={};character=function()error('must not move or select')end
 assert(not fn('stealEgg','local function plantOrHatch(')())
end)
test('an uncertain placement call prevents another placement',function()
 pending.plant={};plot=function()error('must not place twice')end
 assert(not fn('plantOrHatch','local function equipBest(')())
end)
test('treadmill state only clears after native exit confirmation',function()
 state.training=true;rpc=function()return false end
 assert(not fn('stopTraining','local function returnEgg(')()and state.training)
 rpc=function()return true end
 assert(fn('stopTraining','local function returnEgg(')()and not state.training)
end)
test('timed-out requests retain their in-flight lease and block duplicate mutations',function()
 local callbacks={};task={spawn=function(f)callbacks[#callbacks+1]=f end,wait=function()now=now+.1 end}
 local bounded=fn('bounded','local function loadAPI(')
 local called=0
 local ok,message=bounded('carry',function()called=called+1;return true end)
 assert(not ok and pending.carry and called==0 and now>=6.5)
 local second,why=bounded('carry',function()error('duplicate')end)
 assert(not second and why=='request still pending')
 callbacks[1]();callbacks[2]();assert(not pending.carry and called==1)
end)
test('native rarity and biome directories drive the selection UI',function()
 assert(source:find('pairs(api.areas.Directory)',1,true)and source:find('api.rarity.Rarities[a].Rank',1,true))
end)
test('startup waits for native modules that arrive after execution',function()
 startup={};local lookups=0
 resolve=function()lookups=lookups+1;if lookups>=3 then return{}end end
 task={wait=function()now=now+.1 end};bounded=function()return{ready=true}end
 local loadAPI=fn('loadAPI','loadAPI("eggs"')
 loadAPI('sample','Client.Sample');assert(api.sample.ready and lookups==3 and now>=.2)
end)
test('missing native module names the startup failure after a bounded wait',function()
 startup={};resolve=function()end;task={wait=function()now=now+.1 end}
 local loadAPI=fn('loadAPI','loadAPI("eggs"')
 local ok,message=pcall(loadAPI,'missing','Client.Missing')
 assert(not ok and tostring(message):find('Client.Missing',1,true)and now>=15 and now<16)
end)
test('a failed return route retries without waiting while still carrying',function()
 walk=function()return false end
 await=function()error('must not stand waiting with a chasing guardian')end
 assert(not fn('returnEgg','local function stealEgg(')()and carry.IsCarrying)
end)
test('confirmed carry starts its return during guardian waking instead of waiting',function()
 carry.RunBackWakeDelayRequired=true;carry.AreaId='Forest'
 workspace={FindFirstChild=function()error('must not wait for Chasing')end}
 local calls=0;api.eggs.ReadOwnerEggs=function()calls=calls+1;return calls==1 and{}or{u={}}end
 assert(fn('returnEgg','local function escapePreflight(')()and walked and now==0)
end)
test('late carry acknowledgement during streaming cancels the next teleport approach',function()
 local egg={Uid='next',AreaId='Forest'}
 local old=Core.choose;Core.choose=function()return egg end
 local root=setmetatable({Position=0},{__newindex=function(_,key)error('must not teleport a carried egg: '..key)end})
 character=function()return root,{}end;active=function()return true end;escapePreflight=function()return true end;blocked={}
 api.eggs.ReadFieldEggs=function()return{Records={egg}}end;api.assets={Directory={}}
 workspace={StreamingEnabled=true};player.RequestStreamAroundAsync=function()carry={IsCarrying=true,Uid='late'}end
 egg.BottomCFrame={Position=0};carry={IsCarrying=false}
 local ok,result=pcall(fn('stealEgg','local function plantOrHatch('));Core.choose=old
 assert(ok and not result and carry.Uid=='late')
end)
assert(loadfile('Games/StealAnEgg.lua'))
print(n..' native transaction and scheduler guard checks passed; module compiles')
