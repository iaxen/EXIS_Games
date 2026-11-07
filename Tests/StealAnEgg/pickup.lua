local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
local a=assert(source:find('local function findPickupPrompt(',1,true));local b=assert(source:find('local function returnEgg()',a,true))
local chunk=source:sub(a,b-1)..'\nreturn pickupEgg'
local V={};V.__index=function(t,k)if k=='Magnitude'then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(x,y)return vec(x.X+y.X,x.Y+y.Y,x.Z+y.Z)end
V.__sub=function(x,y)return vec(x.X-y.X,x.Y-y.Y,x.Z-y.Z)end
local now,carry,beginCount,endCount,fireCount,duration,prompt,callback,r,h
local function setup()
 now=0;carry={IsCarrying=false};beginCount=0;endCount=0;fireCount=0;duration=nil;callback=nil
 os.clock=function()return now end;state={};player={};options={};active=function()return true end;note=function()end;prepareReturnPath=function()return true end
 Vector3={new=vec};CFrame={new=function(v)return{Position=v}end}
 r={Position=vec(0,0,0)};h={UnequipTools=function()end,MoveTo=function(_,goal)assert(goal==r.Position);state.movementStopped=true end};character=function()return r,h end
 local model={Name='u'};local attachment={Parent=model,WorldPosition=vec(3,0,0),IsA=function(_,name)return name=='Attachment'end}
 prompt={Name='CarryAreaEgg',Enabled=true,Parent=attachment,HoldDuration=1.2,MaxActivationDistance=8,IsA=function(_,name)return name=='ProximityPrompt'end,
  Triggered={Connect=function(_,fn)callback=fn;return{Disconnect=function()callback=nil end}end},
  InputHoldBegin=function()beginCount=beginCount+1 end,InputHoldEnd=function()endCount=endCount+1 end}
 workspace={GetDescendants=function()return{prompt}end};model.Parent=workspace
 carrying=function()return carry end
 pause=function(n)duration=n;now=now+n;return true end
 await=function(predicate,seconds)local limit=now+seconds repeat if predicate()then return true end;now=now+.05 until now>=limit;return false end
 fireproximityprompt=function(p,hold)assert(p==prompt and hold==prompt.HoldDuration);fireCount=fireCount+1;callback(player);carry={IsCarrying=true,Uid='u'}end
 firesignal=nil
end
local n=0
local function test(name,fn)setup();fn(assert(load(chunk))());n=n+1;print('PASS '..name)end
test('native prompt holds and obtains exact egg carry receipt',function(pickup)
 assert(pickup{Uid='u'}and duration==1.2 and beginCount==1 and endCount>=1 and fireCount==1 and not state.pickupPending and state.movementStopped)
end)
test('a naturally triggered hold cannot double-dispatch pickup',function(pickup)
 prompt.InputHoldBegin=function()beginCount=beginCount+1;callback(player);carry={IsCarrying=true,Uid='u'}end
 assert(pickup{Uid='u'}and fireCount==0)
end)
test('another egg prompt is never substituted',function(pickup)
 prompt.Parent.Parent.Name='neighbour';assert(not pickup{Uid='u'}and beginCount==0 and fireCount==0)
end)
test('an unconfirmed prompt retains pending state instead of running home',function(pickup)
 fireproximityprompt=function()fireCount=fireCount+1;callback(player)end
 assert(not pickup{Uid='u'}and state.pickupPending.uid=='u'and state.collectionHoldUntil>now)
end)
test('a receipt for a different egg does not complete pickup',function(pickup)
 fireproximityprompt=function()callback(player);carry={IsCarrying=true,Uid='different'}end
 assert(not pickup{Uid='u'}and state.pickupPending)
end)
test('hold interruption releases input and disconnects its receipt',function(pickup)
 pause=function()return false end
 assert(not pickup{Uid='u'}and endCount>=1 and callback==nil and fireCount==0)
end)
test('live prompt timing overrides the guessed pickup default',function(pickup)
 prompt.HoldDuration=3.5;assert(pickup{Uid='u'}and duration==3.5)
end)
test('an unavailable return path defers pickup without dispatching a prompt',function(pickup)
 prepareReturnPath=function()return false end
 assert(not pickup{Uid='u'}and beginCount==0 and fireCount==0 and not state.pickupPending)
end)
test('optional guardian data loads before the pickup hold',function(pickup)
 options.autoRunSpeed=true
 optionalAPI=function(key,path)assert(key=='guards'and path=='Data.Guards'and beginCount==0 and not carry.IsCarrying);return{}end
 assert(pickup{Uid='u'})
end)
test('a character change during preplanning cancels the pickup',function(pickup)
 prepareReturnPath=function()character=function()return{}end;return true end
 assert(not pickup{Uid='u'}and beginCount==0 and fireCount==0)
end)
test('a late carry receipt during prompt discovery prevents pickup repositioning',function(pickup)
 await=function(predicate)assert(predicate());carry={IsCarrying=true,Uid='late'};return true end
 assert(not pickup{Uid='u'}and beginCount==0 and fireCount==0 and r.CFrame==nil)
end)
test('pending pickup prevents hatch event and treadmill movement',function()
 state.pickupPending={uid='u',at=now};options={hatch=true,treadmill=true,events=true,steal=true}
 periodic=function()error('must not dispatch another job during pickup')end
 local a=assert(source:find('local function farmStep()',1,true));local b=assert(source:find('-- A single worker owns movement',a,true))
 local step=assert(load(source:sub(a,b-1)..'\nreturn farmStep'))()
 step();assert(state.job=='waiting for pickup receipt')
end)
test('failed native pickup cannot fall through to walking to the treadmill',function()
 options={steal=true,treadmill=true};state={}
 stopTraining=function()return true end;api={eggs={HasFieldSnapshot=function()return true end}}
 periodic=function(key)assert(key=='steal');state.pickupAttempted=true;return false end
 local a=assert(source:find('local function farmStep()',1,true));local b=assert(source:find('-- A single worker owns movement',a,true))
 local step=assert(load(source:sub(a,b-1)..'\nreturn farmStep'))()
 step();assert(state.pickupAttempted)
end)
print(n..' native egg prompt and carry acknowledgement checks passed')
