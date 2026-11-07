local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
Core=assert(loadfile('Games/StealAnEgg.lua'))('EXIS_TEST')
local a=assert(source:find('local function pickupReady(',1,true));local b=assert(source:find('local function returnEgg()',a,true))
local chunk=source:sub(a,b-1)..'\nreturn pickupEgg'
local V={};V.__index=function(t,k)if k=='Magnitude'then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(x,y)return vec(x.X-y.X,x.Y-y.Y,x.Z-y.Z)end
local function frame(point)return{Position=point,PointToObjectSpace=function(_,p)return p-point end}end
local now,carry,r,h,c,egg,live,dispatches,accepted,message,onWait,fast,readyPath,notes
local function setup()
 now=0;carry={IsCarrying=false};dispatches=0;accepted=true;message=nil;onWait=nil;fast=false;readyPath=true;notes={}
 os.clock=function()return now end;state={};player={};options={excluded={},excludedPets={},eggTypes={},rarities={}};pending={}
 active=function()return true end;note=function(v)notes[#notes+1]=v end;prepareReturnPath=function()return readyPath end
 r={Position=vec(5,3,0)};c={GetAttribute=function()end};h={UnequipTools=function()end,MoveTo=function(_,p)assert(p==r.Position)end};character=function()return r,h,c end
 egg={Uid='u',Version=1,AssetCategory='Chicken',State='Slot',AreaId='Forest',NestId='Slot_001',BottomCFrame=frame(vec(0,0,0)),BoundsCFrame=frame(vec(0,3,0)),BoundsSize=vec(4,6,4)};live=egg
 carrying=function()return carry end;bestEgg=function()return live end
 api={assets={Directory={Chicken={Rarity={_id='Common',Rank=1}},Dragon={Rarity={_id='Secret',Rank=10}}}},eggs={ReadFieldEgg=function(uid)assert(uid==egg.Uid);return live end}}
 api.eggs.CarryFieldEgg=function(uid,slot)
  dispatches=dispatches+1;assert(uid==egg.Uid and slot==Core.firstSlot(egg));state.dispatchedAt=now
  if accepted then carry={IsCarrying=true,Uid=uid}end
  return accepted,message
 end
 call=function(key,fn,...)assert(key=='carry');return fn(...)end
 workspace={GetAttribute=function(_,key)assert(key=='FastEggPickupTime');return fast end,FindFirstChild=function()end,
  GetDescendants=function()error('native SmartPromptPart is detached from the UID model; no ancestry scan')end}
 task={wait=function(n)now=now+(n or .03);if onWait then onWait()end end}
 await=function(predicate,seconds)local limit=now+seconds repeat if predicate()then return true end;task.wait(.05)until now>=limit;return false end
 fireproximityprompt=function()error('no duplicate prompt dispatch')end;firesignal=fireproximityprompt
end
local n=0
local function test(name,fn)setup();fn(assert(load(chunk))());n=n+1;print('PASS '..name)end
test('detached SmartPromptPart no longer prevents the native carry call',function(pickup)
 assert(pickup(egg)and dispatches==1 and state.dispatchedAt>=1.2 and state.lastPickupVerdict=='confirmed u'and not state.pickupPending)
end)
test('native fast-pickup flag preserves its quarter-second hold',function(pickup)
 fast=true;assert(pickup(egg)and state.dispatchedAt>=.25 and state.dispatchedAt<.3)
end)
test('first-area eggs submit the exact native slot key',function(pickup)
 egg.Uid='FirstAreaEgg_1_Slot_001';assert(pickup(egg)and dispatches==1)
end)
test('ordinary eggs omit the optional first-area slot key',function(pickup)
 assert(pickup(egg)and dispatches==1 and Core.firstSlot(egg)==nil)
end)
test('native denial reports its reason without inventing carry or waiting twelve seconds',function(pickup)
 accepted=false;message='TooFar';assert(not pickup(egg)and dispatches==1 and not state.pickupPending and now<2)
 assert(notes[#notes]:find('TooFar',1,true))
end)
test('accepted mutation still requires exact carry acknowledgement',function(pickup)
 api.eggs.CarryFieldEgg=function()dispatches=dispatches+1;return true end
 assert(not pickup(egg)and dispatches==1 and state.pickupPending.uid=='u')
end)
test('carry acknowledgement for another egg never confirms this pickup',function(pickup)
 api.eggs.CarryFieldEgg=function()dispatches=dispatches+1;carry={IsCarrying=true,Uid='other'};return true end
 assert(not pickup(egg)and state.pickupPending and dispatches==1)
end)
test('timed-out native mutation retains both request and pickup leases',function(pickup)
 call=function()dispatches=dispatches+1;pending.carry={};return false,'request timed out'end
 assert(not pickup(egg)and pending.carry and state.pickupPending and dispatches==1)
 assert(not pickup(egg)and dispatches==1)
end)
test('reset replacement during hold cancels stale UID/version without a mutation',function(pickup)
 onWait=function()live={Uid='u',Version=2,State='Slot',AssetCategory='Chicken'}end
 assert(not pickup(egg)and dispatches==0 and not state.pickupPending)
end)
test('disappearing egg during hold cannot be stolen from a stale record',function(pickup)
 onWait=function()live=nil end;assert(not pickup(egg)and dispatches==0)
end)
test('a higher rarity appearing during hold is reselected before dispatch',function(pickup)
 local better={Uid='rare',AssetCategory='Dragon',BottomCFrame=frame(vec(100,0,0))}
 onWait=function()bestEgg=function()return better end end
 assert(not pickup(egg)and state.eggUrgent and dispatches==0)
end)
test('a bigger same-rarity spawn preempts the uncommitted hold',function(pickup)
 local better={Uid='big',AssetCategory='Chicken',BottomCFrame=frame(vec(100,0,0)),BoundsSize=vec(8,12,8)}
 onWait=function()bestEgg=function()return better end end
 assert(not pickup(egg)and state.eggUrgent and dispatches==0)
end)
test('large egg reach uses its surface instead of bottom-to-root distance',function(pickup)
 egg.BoundsSize=vec(200,6,200);r.Position=vec(103,3,0)
 assert(pickup(egg)and dispatches==1)
end)
test('out-of-reach character never sends a carry request',function(pickup)
 r.Position=vec(30,3,0);assert(not pickup(egg)and dispatches==0)
end)
test('native barrier gate prevents dispatch',function(pickup)
 api.barriers={Separates=function()return true end,IsFencedUid=function()return false end}
 assert(not pickup(egg)and dispatches==0)
end)
test('sealed reset wall waits for native opening',function(pickup)
 api.eggWall={IsSealed=function()return true end};assert(not pickup(egg)and dispatches==0)
end)
test('trapped character cannot initiate a pickup',function(pickup)
 c.GetAttribute=function()return true end;assert(not pickup(egg)and dispatches==0)
end)
test('missing running route defers pickup before dispatch',function(pickup)
 readyPath=false;assert(not pickup(egg)and dispatches==0 and not state.pickupPending)
end)
test('late carry during path planning prevents a new mutation',function(pickup)
 prepareReturnPath=function()carry={IsCarrying=true,Uid='late'};return true end
 assert(not pickup(egg)and dispatches==0)
end)
test('stop or character replacement during hold cancels pickup',function(pickup)
 onWait=function()active=function()return false end end;assert(not pickup(egg)and dispatches==0)
end)
local function step()local a=assert(source:find('local function farmStep()',1,true));local b=assert(source:find('-- A single worker owns movement',a,true));return assert(load(source:sub(a,b-1)..'\nreturn farmStep'))()end
test('pending pickup prevents hatch event and treadmill movement',function()
 state.pickupPending={uid='u',at=now};options={hatch=true,treadmill=true,events=true,steal=true}
 periodic=function()error('must not dispatch another job during pickup')end
 step()();assert(state.job=='waiting for pickup receipt')
end)
test('an in-flight carry request blocks every optional job after a local pickup deadline',function()
 pending.carry={};state.pickupPending={uid='u',at=-50};periodic=function()error('cannot race a pending carry mutation')end
 step()();assert(state.job=='waiting for native carry reply'and state.pickupPending)
end)
test('failed pickup never falls through to walking home for training',function()
 options={steal=true,treadmill=true};newEggOpportunity=function()return false end
 stopTraining=function()return true end;api={eggs={HasFieldSnapshot=function()return true end}}
 periodic=function(key)assert(key=='steal');state.pickupAttempted=true;return false end
 step()();assert(state.pickupAttempted)
end)
test('spawned egg immediately preempts an idle treadmill session and optional jobs',function()
 options={steal=true,treadmill=true,hatch=true,events=true};state.training=true;state.trainUntil=100
 newEggOpportunity=function()return true end;state.eggUrgent=true;cooldown={steal=99}
 periodic=function(key)assert(key=='steal'and cooldown.steal==0);state.pickupAttempted=true;return false end
 step()();assert(state.pickupAttempted)
end)
print(n..' native carry dispatch, hold, receipt and scheduler checks passed')
