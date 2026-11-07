local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
Core=assert(loadfile('Games/StealAnEgg.lua'))('EXIS_TEST')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local code=extract('local function pickupReady(', 'local function plantOrHatch(')..'\nreturn stealEgg'
local V={};V.__index=function(t,k)if k=='Magnitude'then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
local function frame(p)return{Position=p,PointToObjectSpace=function(_,v)return v-p end,PointToWorldSpace=function(_,v)return v+p end}end
Vector3={new=vec};CFrame={new=frame}
local now,r,h,c,carry,records,owned,dispatched,returned,teleports,pathChecks,step,afterPause,deny,noPath
local function egg(uid,category,size,x)
 return{Uid=uid,AreaId='Forest',NestId='Slot_001',AssetCategory=category,State='Slot',Version=1,AssetScale=size/4,
 BottomCFrame=frame(vec(x or 20,0,0)),BoundsCFrame=frame(vec(x or 20,3,0)),BoundsSize=vec(size,6,size)}
end
local function setup()
 now=0;os.clock=function()return now end;carry={IsCarrying=false};owned={};dispatched={};returned=nil;teleports=0;pathChecks=0;afterPause=nil;deny=false;noPath=false
 state={claimed=0};options={master=true,steal=true,excluded={},excludedPets={},eggTypes={},rarities={}};blocked={};cooldown={};pending={};player={UserId=1};c={GetAttribute=function()end}
 r=setmetatable({pos=vec(0,3,0)},{__index=function(t,k)if k=='Position'then return t.pos end end,__newindex=function(t,k,v)
  assert(k=='CFrame'and not carry.IsCarrying,'only approach may teleport');rawset(t,'pos',v.Position);teleports=teleports+1
 end})
 h={WalkSpeed=16,MoveTo=function()end,UnequipTools=function()end};character=function()return r,h,c end;active=function()return true end;carrying=function()return carry end;note=function()end
 records={egg('low','CommonPet',4,5),egg('small-rare','RarePet',4,20),egg('big-rare','RarePet',20,100)}
 api={balance={},assets={Directory={CommonPet={Rarity={_id='Common',Rank=1}},RarePet={Rarity={_id='Secret',Rank=10}}}},eggs={}}
 api.eggs.ReadFieldEggs=function()return{Records=records}end
 api.eggs.ReadFieldEgg=function(uid)for _,e in ipairs(records)do if e.Uid==uid then return e end end end
 api.eggs.ReadOwnerEggs=function()return owned end
 api.eggs.CarryFieldEgg=function(uid,slot)
  assert(not carry.IsCarrying and slot==Core.firstSlot(api.eggs.ReadFieldEgg(uid)));dispatched[#dispatched+1]=uid
  if deny then return false,'native denial'end
  carry={IsCarrying=true,Uid=uid,AssetCategory=api.eggs.ReadFieldEgg(uid).AssetCategory};return true
 end
 bestEgg=assert(load(extract('local function bestEgg()', 'local function newEggOpportunity()')..'\nreturn bestEgg'))()
 plot=function()return{PetArea={Position=vec(0,0,0)}}end;stopTraining=function()return true end
 prepareReturnPath=function()pathChecks=pathChecks+1;return not noPath end
 pause=function(n)now=now+n;if afterPause then afterPause()end;return true end
 task={wait=function(n)now=now+(n or .03)end}
 await=function(fn,seconds)local untilTime=now+seconds repeat if fn()then return true end;now=now+.05 until now>=untilTime;return false end
 call=function(key,fn,...)assert(key=='carry');return fn(...)end
 walk=function(_,uid)
  assert(carry.IsCarrying and uid==carry.Uid);returned=uid;owned={[uid]={AssetCategory=carry.AssetCategory}};carry={IsCarrying=false};return true
 end
 workspace={StreamingEnabled=false,GetAttribute=function()return false end,FindFirstChild=function()end}
 step=assert(load(code))()
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('production selection approach hold native pickup and return deliver the largest rarest spawn',function()
 assert(step()and #dispatched==1 and dispatched[1]=='big-rare'and returned=='big-rare'and state.claimed==1)
 assert(teleports==1 and r.Position.X==87 and pathChecks>=1 and now>=1.2)
end)
test('native denial never runs home or counts a successful steal',function()
 deny=true;assert(not step()and #dispatched==1 and not returned and state.claimed==0 and not state.pickupPending)
end)
test('missing home route tries other egg surfaces without sending a pickup',function()
 noPath=true;assert(not step()and #dispatched==0 and not returned and teleports==4)
end)
test('a refreshed higher target during approach cancels before the old egg request',function()
 local once=false;afterPause=function()if not once then once=true;records[#records+1]=egg('even-bigger','RarePet',40,200)end end
 assert(not step()and #dispatched==0 and not returned and state.eggUrgent and teleports==1)
 afterPause=nil;assert(step()and dispatched[1]=='even-bigger'and returned=='even-bigger')
end)
test('removed highest egg is never dispatched from a stale snapshot',function()
 afterPause=function()records={}end
 assert(not step()and #dispatched==0 and not returned)
end)
test('full egg inventory allows hatching instead of interrupting it indefinitely',function()
 for i=1,115 do owned[tostring(i)]={}end
 local opportunity=assert(load(extract('local function newEggOpportunity()', 'local function guardianRows()')..'\nreturn newEggOpportunity'))()
 assert(not opportunity()and not step()and #dispatched==0 and teleports==0)
end)
test('sealed native reset wall prevents approach until it opens',function()
 local sealed=true;api.eggWall={IsSealed=function()return sealed end}
 assert(not step()and teleports==0 and #dispatched==0)
 sealed=false;assert(step()and returned=='big-rare')
end)
print(n..' complete collection flow and priority conflict checks passed')
