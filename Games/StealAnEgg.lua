-- EXIS | Steal an Egg. Native client APIs from the supplied November 2026 export.
-- Core is separately executable for deterministic tests; Roblox runtime starts below.
local Core={}
function Core.allowed(record,options,assets)
    local info=assets[record.AssetCategory]
    if not info or options.excluded[record.AreaId] or options.excludedPets[record.AssetCategory]
        or options.eggTypes and options.eggTypes[record.AssetCategory]==false then return false end
    local rarity=info.Rarity and info.Rarity._id
    if options.rarities[rarity]==false then return false end
    return record.State=="Slot" or record.State=="Dropped"
end
-- Compare native rarity first, then actual spawned size, scale, distance and UID.
function Core.size(record)
    local size=record.BoundsSize
    if size and size.X>0 and size.Y>0 and size.Z>0 then return size.X*size.Y*size.Z end
    return math.max(0,tonumber(record.AssetScale)or 1)^3
end
function Core.better(a,b,assets,position)
    if not b then return true end
    local function rank(r)local info=assets[r.AssetCategory];return tonumber(info and info.Rarity and info.Rarity.Rank)or 0 end
    local ar,br=rank(a),rank(b)
    if ar~=br then return ar>br end
    local az,bz=Core.size(a),Core.size(b)
    if az~=bz then return az>bz end
    local as,bs=tonumber(a.AssetScale)or 1,tonumber(b.AssetScale)or 1
    if as~=bs then return as>bs end
    if position and a.BottomCFrame and b.BottomCFrame then
        local ad,bd=(a.BottomCFrame.Position-position).Magnitude,(b.BottomCFrame.Position-position).Magnitude
        if ad~=bd then return ad<bd end
    end
    return a.Uid<b.Uid
end
function Core.choose(records,options,assets,position,blocked,now)
    local best
    for _,r in pairs(records)do
        if Core.allowed(r,options,assets)and r.BottomCFrame and not(blocked[r.Uid]and blocked[r.Uid]>now)
            and Core.better(r,best,assets,position)then best=r end
    end
    return best
end
function Core.surfaceDistance(record,position)
    if not record.BoundsCFrame or not record.BoundsSize then return(position-record.BottomCFrame.Position).Magnitude end
    local localPoint=record.BoundsCFrame:PointToObjectSpace(position)
    local size=record.BoundsSize
    local x=math.max(0,math.abs(localPoint.X)-size.X/2)
    local y=math.max(0,math.abs(localPoint.Y)-size.Y/2)
    local z=math.max(0,math.abs(localPoint.Z)-size.Z/2)
    return math.sqrt(x*x+y*y+z*z)
end
function Core.firstSlot(record)
    if record.Uid:sub(1,13)=="FirstAreaEgg_" then return record.AreaId..":"..record.NestId end
end
function Core.claimReceipt(uid,category,before,after)
    if after[uid] and not before[uid] then return true end
    if not category then return false end
    for id,record in pairs(after)do
        if not before[id] and record.AssetCategory==category then return true end
    end
    return false
end
function Core.flatDistance(a,b)
    local x,z=a.X-b.X,a.Z-b.Z
    return math.sqrt(x*x+z*z)
end
function Core.reached(a,b,radius)
    return Core.flatDistance(a,b)<=radius and math.abs(a.Y-b.Y)<=8
end
function Core.guardSpeed(base,flatRadius,distance,policy)
    if not base or base<=0 then return 0 end
    local strength=tonumber(policy.DISTANCE_MULTIPLIER_STRENGTH)or .5
    local cap=tonumber(policy.MAX_DISTANCE_MULTIPLIER)or 4
    return math.min(base*(1+math.max(0,distance/math.max(.001,flatRadius or 1)-1)*strength),base*cap)
end
function Core.runningSpeed(options,baseline,guards)
    local cap=options.runSpeedCap or 300
    if options.autoRunSpeed then
        local needed=baseline
        for _,guard in ipairs(guards)do
            needed=math.max(needed,(guard.speed or 0)+(options.runMargin or 12))
        end
        return math.min(cap,needed),needed>cap
    end
    if options.fixedRunSpeed then return math.min(cap,options.runSpeed or 64),(options.runSpeed or 64)>cap end
end
function Core.count(t)local n=0 for _ in pairs(t or {})do n=n+1 end return n end
function Core.fuseGroup(inventory,equipped,assets,kernel,inputCount)
    local groups={}
    for uid,item in pairs(inventory) do
        local info=assets[item.Category]
        if info and not equipped[uid] and item.CreatorTemporary~=true
            and kernel.MayEnterFuse(uid,item,nil,false,false) then
            groups[item.Category]=groups[item.Category] or {}
            table.insert(groups[item.Category],uid)
        end
    end
    local categories={}for category in pairs(groups)do categories[#categories+1]=category end table.sort(categories)
    for _,category in ipairs(categories)do
        local group=groups[category];table.sort(group)
        if #group>=inputCount then local result={}for i=1,inputCount do result[i]=group[i]end return result end
    end
end
if ...=="EXIS_TEST" then return Core end

local startup={}
local function run()
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local Pathfinding=game:GetService("PathfindingService")
local HTTP=game:GetService("HttpService")
local player=Players.LocalPlayer
local bootParent=player:WaitForChild("PlayerGui")
local previous=bootParent:FindFirstChild("EXISEggStartup")
if previous then previous:Destroy()end
startup.gui=Instance.new("ScreenGui");startup.gui.Name="EXISEggStartup";startup.gui.ResetOnSpawn=false;startup.gui.DisplayOrder=2147483647;startup.gui.Parent=bootParent
startup.label=Instance.new("TextLabel");startup.label.Size=UDim2.fromOffset(340,110);startup.label.Position=UDim2.new(.5,-170,.5,-55)
startup.label.BackgroundColor3=Color3.fromRGB(8,12,18);startup.label.TextColor3=Color3.fromRGB(80,160,255)
startup.label.TextWrapped=true;startup.label.TextSize=14;startup.label.Text="EXIS | STEAL AN EGG\nStarting native adapters…";startup.label.Parent=startup.gui
local dismiss=Instance.new("TextButton");dismiss.Size=UDim2.fromOffset(24,24);dismiss.Position=UDim2.new(.5,145,.5,-55);dismiss.Text="×";dismiss.Parent=startup.gui
dismiss.Activated:Connect(function()startup.gui:Destroy()end)
local alive=true
local connections={}
local options={master=false,hidePens=false,hideOtherPets=false,hideSelfPets=false,lowDetail=false,disableEffects=false,disableVideos=false,antiAfk=false,autoExecute=false,autoReconnect=false,steal=false,hatch=false,equip=false,treadmill=false,events=false,
    upgrades=false,rewards=false,fusion=false,LightVsDarkness=true,SammyEvent=true,excluded={},excludedPets={},eggTypes={},rarities={},trainingSeconds=20,fixedRunSpeed=false,autoRunSpeed=false,runSpeed=64,runMargin=12,runSpeedCap=300,skipUnsafeEggs=false,priorityVersion=2}
local api={}
local pending={}
local cooldown={}
local blocked={}
local state={job="idle",claimed=0,hatches=0,trained=0,training=false,trace={},hatchPending={},plantBlocked={}}
local function resolve(path)
    local obj=RS
    for name in path:gmatch('[^.]+')do obj=obj:FindFirstChild(name)if not obj then return end end
    return obj
end
local function bounded(key,fn)
    -- Keep timed-out mutations in flight until their actual reply; never duplicate them.
    local old=pending[key]
    if old then return false,"request still pending" end
    local request={done=false};pending[key]=request
    task.spawn(function()request.result=table.pack(pcall(fn));request.done=true end)
    local untilTime=os.clock()+6.5
    repeat
        if request.done then
            pending[key]=nil
            if not request.result[1] then return false,tostring(request.result[2]) end
            return table.unpack(request.result,2,request.result.n)
        end
        task.wait()
    until not alive or os.clock()>=untilTime
    task.spawn(function()while alive and not request.done do task.wait(.2)end if request.done then pending[key]=nil end end)
    return false,"request timed out; awaiting reconciliation"
end
local function loadAPI(key,path)
    if startup.label and startup.label.Parent then startup.label.Text="EXIS | STEAL AN EGG\nLoading "..path end
    local deadline=os.clock()+15
    local module=resolve(path)
    while not module and os.clock()<deadline do task.wait(.1);module=resolve(path)end
    assert(module,"Missing native module: "..path)
    local value,message=bounded("load:"..key,function()return require(module)end)
    assert(type(value)=="table",message or "Native module failed: "..path)
    api[key]=value
end
loadAPI("eggs","Client.EggState")
loadAPI("plots","Client.PlotState")
loadAPI("remotes","Shared.Remotes")
loadAPI("assets","Data.Assets")
loadAPI("areas","Data.Areas")
loadAPI("rarity","Data.Rarity")
loadAPI("save","Shared.Save")
loadAPI("bases","Client.BaseUpgrade")
loadAPI("treadmills","Data.Treadmills")
loadAPI("kernel","Shared.Util.FuseKernel")
loadAPI("balance","Shared.Flags.GameplayBalance")
local function rpc(namespace,action,...)
    local args=table.pack(...)
    return bounded(namespace.."."..action,function()
        local remote=assert(api.remotes[namespace] and api.remotes[namespace][action],"Native action absent")
        return remote:InvokeServer(table.unpack(args,1,args.n))
    end)
end
local function call(key,fn,...)local args=table.pack(...)return bounded(key,function()return fn(table.unpack(args,1,args.n))end)end
local function character()
    local c=player.Character
    local r=c and c:FindFirstChild("HumanoidRootPart")
    local h=c and c:FindFirstChildOfClass("Humanoid")
    if r and h and h.Health>0 then return r,h,c end
end
local function profile()return api.save.Peek(player)end
local function plot()return api.plots.ResolvePlot(player.UserId)end
local function carrying()return api.eggs.ReadCarryState()end
local function active()return alive and options.master and character()~=nil end
local report=function(message)warn("EXIS Egg: "..message)end
local function note(message)
    state.trace[#state.trace+1]=os.date("%H:%M:%S").." "..message
    if #state.trace>30 then table.remove(state.trace,1)end
    report(message)
end
local function pause(seconds)
    local deadline=os.clock()+seconds
    repeat if not active()then return false end task.wait(.05)until os.clock()>=deadline
    return true
end
local function await(fn,seconds)
    local deadline=os.clock()+seconds
    repeat if fn()then return true end if not active()then return false end task.wait(.05)until os.clock()>=deadline
    return false
end
local motion={speedOwner=nil}
local function optionalAPI(key,path)
 if api[key]then return api[key]end
 local module=resolve(path)
 if module then local value=call("load:"..key,require,module)if type(value)=="table"then api[key]=value end end
 return api[key]
end
optionalAPI("cycle","Shared.Util.AreaEggCycle")
optionalAPI("clock","Shared.Util.ServerClock")
optionalAPI("eggWall","Client.AreaEggResetWall")
optionalAPI("geometry","Shared.Util.GuardAreaGeometry")
optionalAPI("barriers","Shared.Util.SafeZoneBarriers")
local function bestEgg()
 local r=character()
 if not r then return end
 return Core.choose(api.eggs.ReadFieldEggs().Records,options,api.assets.Directory,r.Position,blocked,os.clock())
end
local function newEggOpportunity()
 if not options.steal or pending.carry or state.pickupPending then return false end
 if Core.count(api.eggs.ReadOwnerEggs(player.UserId))>=115 then return false end
 return bestEgg()~=nil
end
local function guardianRows()
 local r=character();if not r then return{}end
 local world=workspace:FindFirstChild("World")
 local areas=world and world:FindFirstChild("Areas")
 local folder=areas and areas:FindFirstChild("GuardAreas")
 if not folder then return{}end
 local guards=api.guards
 -- Never require/yield while escaping; preload optional data before pickup.
 local policy=api.balance.GuardChase or {}
 local carry=carrying();local rows={}
 for _,area in ipairs(folder:GetChildren())do
  for _,guard in ipairs(area:GetChildren())do
   if guard:IsA("Model")and guard.Name=="Guard"then
    local phase=guard:GetAttribute("GuardState")
    local target=tostring(guard:GetAttribute("TargetPlayer")or "")
    local wake=tostring(guard:GetAttribute("WakeTargetPlayer")or "")
    local own=tostring(player.UserId)
    if (phase=="Chasing"and target==own)or ((phase=="Waking"or phase=="Sleeping")and (wake==own or carry.IsCarrying and carry.AreaId==area.Name))then
     local root=guard:FindFirstChild("HumanoidRootPart")
     local human=guard:FindFirstChildOfClass("Humanoid")
     if root and human then
      local areaInfo=api.areas.Directory[area.Name]
      local config=guards and guards.Directory and guards.Directory[areaInfo and areaInfo.GuardId or area.Name]
      local distance=Core.flatDistance(r.Position,root.Position)
      local predicted=config and Core.guardSpeed(config.WalkSpeed,config.FlatRadius,distance,policy)or 0
      rows[#rows+1]={model=guard,distance=distance,speed=math.max(human.WalkSpeed,predicted),
       hit=config and config.HitDistance or policy.DEFAULT_HIT_DISTANCE or 10,area=area.Name}
     end
    end
   end
  end
 end
 return rows
end
local function restoreRunSpeed()
 local own=motion.speedOwner;motion.speedOwner=nil
 state.runRequested=nil;state.runCapped=false;state.guardSpeed=0
 if own and own.human.Parent and own.human.WalkSpeed==own.applied then own.human.WalkSpeed=own.original end
end
local function applyRunSpeed(r,h)
 if not options.master or not (options.fixedRunSpeed or options.autoRunSpeed)then restoreRunSpeed();return end
 if r.Anchored or h.PlatformStand or h.Sit then restoreRunSpeed();return end
 local phase=h.GetState and h:GetState()
 if phase==Enum.HumanoidStateType.Physics or phase==Enum.HumanoidStateType.Ragdoll or phase==Enum.HumanoidStateType.Dead then restoreRunSpeed();return end
 local own=motion.speedOwner
 if not own or own.human~=h then
  restoreRunSpeed();own={human=h,original=h.WalkSpeed};motion.speedOwner=own
 elseif h.WalkSpeed~=own.applied then
  -- Preserve a newer native slowdown/buff when this temporary override ends.
  own.original=h.WalkSpeed
 end
 local guards=guardianRows()
 local wanted,capped=Core.runningSpeed(options,own.original,guards)
 if wanted then h.WalkSpeed=wanted;own.applied=wanted end
 state.runRequested=wanted;state.guardSpeed=0;state.runCapped=capped
 for _,guard in ipairs(guards)do state.guardSpeed=math.max(state.guardSpeed,guard.speed)end
end
local function prepareReturnPath()
 local r,_,c=character();local base=plot()
 if not r or not base then return false end
 local goal=base.PetArea.Position+Vector3.new(0,3,0)
 local cached=state.returnPath
 if cached and cached.character==c and os.clock()-cached.at<10
  and Core.flatDistance(r.Position,cached.from)<2 and Core.flatDistance(goal,cached.goal)<5 then return true end
 local path=Pathfinding:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=8})
 local ok=pcall(function()path:ComputeAsync(r.Position,goal)end)
 if not ok or path.Status~=Enum.PathStatus.Success then return false end
 state.returnPath={points=path:GetWaypoints(),from=r.Position,goal=goal,character=c,at=os.clock()}
 return true
end
local function walk(goal,carryUid)
    local r,h,c=character();if not r then return false end
    local last=r.Position;local progress=os.clock();local deadline=os.clock()+90
    local function interrupted()
        if not active()or player.Character~=c then return true end
        local held=carrying()
        return carryUid and (not held.IsCarrying or held.Uid~=carryUid)
            or not carryUid and (held.IsCarrying or state.job~="steal"and newEggOpportunity())
    end
    local function finish(result)
        if h.Parent then h:MoveTo(r.Position)end
        restoreRunSpeed();return result
    end
    local ok,result=pcall(function()
      while os.clock()<deadline do
        if interrupted()then return false end
        if Core.reached(r.Position,goal,4)then return true end
        applyRunSpeed(r,h)
        local points
        local prepared=state.returnPath
        if carryUid and prepared and prepared.character==c and os.clock()-prepared.at<15
            and Core.flatDistance(r.Position,prepared.from)<8 and Core.flatDistance(goal,prepared.goal)<5 then
            points=prepared.points;state.returnPath=nil
        else
            local path=Pathfinding:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=8})
            local computed=pcall(function()path:ComputeAsync(r.Position,goal)end)
            if interrupted()then return false end
            if not computed or path.Status~=Enum.PathStatus.Success then note("No walking route; retaining carried egg for retry")return false end
            points=path:GetWaypoints()
        end
        for _,point in ipairs(points)do
            if interrupted()then return false end
            -- Path waypoints are ground positions; root height must not add a
            -- three-second wait at every already-reached waypoint.
            if not Core.reached(r.Position,point.Position,3)then
                applyRunSpeed(r,h)
                if point.Action==Enum.PathWaypointAction.Jump then h.Jump=true end
                h:MoveTo(point.Position)
                local step=os.clock()+math.max(.6,math.min(3,Core.flatDistance(r.Position,point.Position)/math.max(1,h.WalkSpeed)+1))
                local nextSpeed=0
                repeat
                    if interrupted()then return false end
                    if os.clock()>=nextSpeed then applyRunSpeed(r,h);nextSpeed=os.clock()+.1 end
                    local moved=Core.flatDistance(r.Position,last)
                    if moved>1.5 then
                        local dt=os.clock()-progress
                        if dt>.01 then state.runMeasured=moved/dt end
                        last=r.Position;progress=os.clock()
                    end
                    if os.clock()-progress>7 then note("Walking stalled; retaining egg and recalculating route")return false end
                    task.wait(.03)
                until Core.reached(r.Position,point.Position,3)or os.clock()>step
                if not Core.reached(r.Position,point.Position,3)then break end
            end
        end
      end
      return false
    end)
    finish(false)
    if not ok then error(result)end
    return result
end
connections[#connections+1]=api.remotes.Treadmill.AssignedBeltShifted.OnClientEvent:Connect(function(id)
    state.belt=id
    if id==nil then state.training=false end
end)
connections[#connections+1]=player.CharacterRemoving:Connect(function()
    state.training=false
    restoreRunSpeed()
    state.hatchPending={}
    state.hatchInFlight=nil;state.returnPath=nil
end)
local function stopTraining()
    if not state.training then return true end
    local ok=rpc("Treadmill","AskDoff")
    if ok==true then state.training=false return true end
    note("Treadmill exit unconfirmed; movement waits")return false
end
-- Native SmartProximityPrompt parents CarryAreaEgg to Workspace.SmartPromptPart,
-- not to the egg model. Use the controller's exact carry adapter, once per hold.
local function pickupReady(egg,r,c)
 if not active()or character()~=r or carrying().IsCarrying then return false,"character/carry changed"end
 local live=api.eggs.ReadFieldEgg(egg.Uid)
 if not live or live.Version~=egg.Version or not Core.allowed(live,options,api.assets.Directory)then return false,"egg reset or taken"end
 if c and c:GetAttribute("IsTrapped")==true then return false,"character trapped"end
 if api.eggWall and api.eggWall.IsSealed()then return false,"reset wall sealed"end
 if Core.surfaceDistance(live,r.Position)>7.5 then return false,"out of egg surface reach"end
 local world=workspace:FindFirstChild("World")
 local areas=world and world:FindFirstChild("Areas")
 local line=areas and areas:FindFirstChild("SeparationLine")
 if line and api.geometry and not api.geometry.IsPastLine(line,r.Position)then return false,"outside field"end
 if api.barriers and api.barriers.Separates(r.Position,live.BoundsCFrame.Position,api.barriers.IsFencedUid(live.Uid))then
  return false,"native barrier separates egg"end
 local best=bestEgg()
 if best and best.Uid~=live.Uid and Core.better(best,live,api.assets.Directory,r.Position)then
  state.eggUrgent=true;return false,"better spawned egg available"end
 return true
end
local function pickupEgg(egg)
 if pending.carry or state.pickupPending then return false end
 local r,h,c=character()
 if not r then return false end
 local ready,why=pickupReady(egg,r,c)
 if not ready then note("Pickup deferred: "..why)return false end
 h:MoveTo(r.Position);h:UnequipTools()
 if options.fixedRunSpeed or options.autoRunSpeed then optionalAPI("guards","Data.Guards")end
 if not prepareReturnPath()then note("No verified running route home; pickup deferred")return false end
 ready,why=pickupReady(egg,r,c)
 if not ready then note("Pickup deferred: "..why)return false end
 local duration=workspace:GetAttribute("FastEggPickupTime")and .25 or 1.2
 state.job="holding egg pickup"
 local untilTime=os.clock()+duration
 repeat
  ready,why=pickupReady(egg,r,c)
  if not ready then note("Pickup hold cancelled: "..why)return false end
  task.wait(.03)
 until os.clock()>=untilTime
 -- One native dispatch; no Triggered/fireproximityprompt path can duplicate it.
 ready,why=pickupReady(egg,r,c)
 if not ready then note("Pickup hold cancelled: "..why)return false end
 state.pickupPending={uid=egg.Uid,at=os.clock()}
 state.collectionHoldUntil=os.clock()+20
 state.pickupDispatches=(state.pickupDispatches or 0)+1
 local accepted,message=call("carry",api.eggs.CarryFieldEgg,egg.Uid,Core.firstSlot(egg))
 state.lastPickupVerdict=accepted==true and "accepted; waiting for carry"or tostring(message or "denied")
 if accepted~=true and not pending.carry then
  state.pickupPending=nil;state.collectionHoldUntil=nil
  note("Native carry denied for "..egg.Uid..": "..tostring(message or "no reason returned"))
  return false
 end
 if await(function()local held=carrying();return held.IsCarrying and held.Uid==egg.Uid end,5)then
  state.pickupPending=nil;state.collectionHoldUntil=nil
  state.lastPickupVerdict="confirmed "..egg.Uid;note("Pickup confirmed: "..egg.Uid)return true
 end
 note("Native carry unconfirmed; staying at egg while reconciling")
 return false
end
local function returnEgg()
    local carry=carrying();if not carry.IsCarrying then return false end
    if not stopTraining()then return false end
    local base=plot();if not base then note("Waiting for own base to stream")return false end
    state.job="return egg"
    -- Start running immediately after carry confirmation. Waiting for Chasing
    -- would throw away the native GuardChase.WAKING_DURATION head start.
    local before=api.eggs.ReadOwnerEggs(player.UserId)
    local arrived=walk(base.PetArea.Position+Vector3.new(0,3,0),carry.Uid)
    if not arrived and carrying().IsCarrying then
        note("Return route needs retry; still holding egg, no other task allowed")return false
    end
    if await(function()return not carrying().IsCarrying end,3)then
        if await(function()
            return Core.claimReceipt(carry.Uid,carry.AssetCategory,before,api.eggs.ReadOwnerEggs(player.UserId))
        end,4)then
            state.claimed=state.claimed+1;state.pickupPending=nil;note("Egg redeemed at own base")return true
        end
        note("Carry ended without matching ownership receipt; egg may have been lost")
    end
    return false
end
local function escapePreflight(egg,h)
 if not options.skipUnsafeEggs then return true end
 local world=workspace:FindFirstChild("World")
 local areas=world and world:FindFirstChild("Areas")
 local guards=areas and areas:FindFirstChild("GuardAreas")
 local area=guards and guards:FindFirstChild(egg.AreaId)
 local requirement=area and area:GetAttribute("GuardEscapeSpeeds")
 if not requirement or type(requirement.Y)~="number"then return true end
 local available
 if options.autoRunSpeed then available=options.runSpeedCap
 elseif options.fixedRunSpeed then available=math.min(options.runSpeed,options.runSpeedCap)
 else available=h.WalkSpeed*(api.balance.GuardRequirements and api.balance.GuardRequirements.CARRY_SPEED_RATIO or .9)end
 if available<requirement.Y then
  note("Deferred "..egg.AreaId.." egg: native escape estimate "..math.ceil(requirement.Y).." exceeds requested running limit "..math.floor(available))
  return false
 end
 return true
end
local function approachEgg(egg)
 local r,h,c=character();if not r then return false end
 local frame=egg.BoundsCFrame or egg.BottomCFrame
 local size=egg.BoundsSize or Vector3.new(0,0,0)
 local points={}
 for _,offset in ipairs({Vector3.new(size.X/2+3,0,0),Vector3.new(-size.X/2-3,0,0),
  Vector3.new(0,0,size.Z/2+3),Vector3.new(0,0,-size.Z/2-3)})do
  local point=frame:PointToWorldSpace(offset)
  points[#points+1]=Vector3.new(point.X,egg.BottomCFrame.Position.Y+3,point.Z)
 end
 local base=plot();local toward=base and base.PetArea.Position or r.Position
 table.sort(points,function(a,b)return Core.flatDistance(a,toward)<Core.flatDistance(b,toward)end)
 for _,point in ipairs(points)do
  if not active()or character()~=r or carrying().IsCarrying or pending.carry then return false end
  r.CFrame=CFrame.new(point);h:MoveTo(r.Position)
  if not pause(.12)then return false end
  local ready=pickupReady(egg,r,c)
  if not ready and state.eggUrgent then return false end
  if ready and prepareReturnPath()then return true end
 end
 note("No reachable pickup surface with a running route home for "..egg.Uid)
 return false
end
local function stealEgg()
    if pending.carry then note("Previous carry request awaiting reconciliation")return false end
    local r,h=character();if not r or carrying().IsCarrying then return false end
    local owned=api.eggs.ReadOwnerEggs(player.UserId)
    if Core.count(owned)>=115 then note("Egg inventory full; hatch before stealing")return false end
    state.pickupAttempted=false
    local egg=bestEgg()
    if not egg then state.eggUrgent=nil;return false end
    state.pickupAttempted=true;state.eggUrgent=nil;state.targetEgg=egg.Uid
    if api.eggWall and api.eggWall.IsSealed()then state.job="waiting for reset wall";return false end
    if not stopTraining()then return false end
    if not active()or character()~=r or carrying().IsCarrying then return false end
    if not escapePreflight(egg,h)then blocked[egg.Uid]=os.clock()+10;return false end
    if workspace.StreamingEnabled then pcall(function()player:RequestStreamAroundAsync(egg.BottomCFrame.Position,2)end)end
    if not active()or character()~=r or carrying().IsCarrying then return false end
    -- Re-read every yield boundary. Never carry a vanished egg or an obsolete lower target.
    local live=api.eggs.ReadFieldEgg(egg.Uid)
    local best=bestEgg()
    if not live or live.Version~=egg.Version or not Core.allowed(live,options,api.assets.Directory)then return false end
    if best and best.Uid~=live.Uid and Core.better(best,live,api.assets.Directory,r.Position)then state.eggUrgent=true;cooldown.steal=0;return false end
    if not escapePreflight(live,h)then blocked[egg.Uid]=os.clock()+10;return false end
    if not approachEgg(live)then blocked[egg.Uid]=os.clock()+1;return false end
    if not pickupEgg(live)then
     if not state.eggUrgent then blocked[egg.Uid]=os.clock()+2 end
     return false
    end
    return returnEgg()
end
local function plantOrHatch()
    if pending.plant then return false end
    local _,human=character();if human then human:UnequipTools()end
    local base=plot();if not base then return false end
    local rows={}
    for uid,egg in pairs(api.eggs.ReadOwnerEggs(player.UserId))do
        rows[#rows+1]={uid=uid,egg=egg,ready=egg.Placement and api.eggs.IsReadyToHatch(uid) or false}
    end
    table.sort(rows,function(a,b)if a.ready~=b.ready then return a.ready end return a.uid<b.uid end)
    for _,row in ipairs(rows)do
        local uid,egg=row.uid,row.egg
        if not egg.Placement and os.clock()>=(state.plantBlocked[uid]or 0)then
            if not stopTraining()or not walk(base.PetArea.Position+Vector3.new(0,3,0))then return false end
            -- Grid positions are inside the player's actual PetArea, converted to CenterPoint space.
            local area=base.PetArea
            local occupied=api.eggs.ReadOwnerEggs(player.UserId)
            local attempts=0
            for x=-area.Size.X/2+3,area.Size.X/2-3,6 do
                for z=-area.Size.Z/2+3,area.Size.Z/2-3,6 do
                    local cf=area.CFrame*CFrame.new(x,area.Size.Y/2,z)
                    local localCF=base.CenterPoint.CFrame:ToObjectSpace(cf)
                    local clear=true
                    for _,other in pairs(occupied)do
                        if other.Placement and (other.Placement.LocalCFrame.Position-localCF.Position).Magnitude<5 then clear=false break end
                    end
                    if clear then
                        attempts=attempts+1
                        local ok=call("plant",api.eggs.PlantEgg,uid,localCF)
                        if ok==true then return await(function()local e=api.eggs.ReadOwnedEgg(player.UserId,uid)return e and e.Placement~=nil end,3)end
                        if attempts>=3 or pending.plant or not active()then state.plantBlocked[uid]=os.clock()+5;return false end
                    end
                end
            end
            state.plantBlocked[uid]=os.clock()+5
            note("No confirmed placement space; keep egg in inventory")return false
        elseif api.eggs.IsReadyToHatch(uid) and os.clock()>=(state.hatchPending[uid]or 0)then
            if not stopTraining()then return false end
            local point=(base.CenterPoint.CFrame*egg.Placement.LocalCFrame).Position
            if not walk(point+Vector3.new(0,3,0))then return false end
            -- Let the native placed-egg controller own Begin/animation/Finish.
            local nearestPrompt,distance
            for _,p in ipairs(workspace:GetDescendants())do
                if p:IsA("ProximityPrompt") and p:GetAttribute("PlacedEggPrompt")==true and p.Enabled then
                    local owner=p.Parent
                    local at=owner and (owner:IsA("Attachment")and owner.WorldPosition or owner:IsA("BasePart")and owner.Position)
                    local d=at and (at-point).Magnitude
                    if d and d<5 and (not distance or d<distance)then nearestPrompt,distance=p,d end
                end
            end
            if nearestPrompt and type(fireproximityprompt)=="function"then
                state.hatchPending[uid]=os.clock()+20
                state.hatchInFlight={uid=uid,untilTime=os.clock()+20}
                fireproximityprompt(nearestPrompt,nearestPrompt.HoldDuration)
                if await(function()return api.eggs.ReadOwnedEgg(player.UserId,uid)==nil end,15)then
                    state.hatchInFlight=nil;state.hatches=state.hatches+1;note("Native hatch completed")return true
                end
                note("Hatch pending; no duplicate Begin/Finish call")return false
            end
            note("Native hatch prompt unavailable; waiting for renderer/input support")
        end
    end
    return false
end
local function equipBest()
    local ok,message=rpc("Haul","WearBest")
    note(ok==true and "Native best pets equipped" or "Equip best: "..tostring(message))
    return ok==true
end
local function train()
    if state.training then return true end
    local base=plot();local bottom=base and base.PlotFolder:FindFirstChild("TreadmillBottom",true)
    if not bottom or not stopTraining()then return false end
    if not walk(bottom.Position+Vector3.new(0,3,0))then return false end
    local ok,message=rpc("Treadmill","AskWearStill")
    if ok==true then state.training=true;state.trainUntil=os.clock()+options.trainingSeconds;state.job="training";note("Training on own treadmill")return true end
    note("Treadmill rejected: "..tostring(message))return false
end
local function upgrades()
    local data=profile();if not data then return false end
    if api.bases.IsNextTierAffordable(data)then
        local before=data.BaseUpgradeLevel
        call("base upgrade",api.bases.PurchaseNextTier)
        return await(function()local p=profile()return p and p.BaseUpgradeLevel>before end,3)
    end
    local nextTier=api.treadmills.GetByUpgradeLevel(data.TreadmillUpgradeLevel+1)
    if nextTier and not nextTier.ProductId and data.Money>=nextTier.Price then
        return rpc("Treadmill","AskTierRaise",nextTier._id)==true
    end
    return false
end
local function fuse()
    local data=profile();if not data then return false end
    if data.FusionLocked or data.FusionEggReward~=false then note("Fusion already in progress; native reveal owns completion")return false end
    local count=api.balance.Fusion.INPUT_COUNT
    local slots=data.FusionSlots or {}
    if #slots>0 and not state.fusePlan then note("Existing fusion inputs retained; finish through native fuse menu")return false end
    local equipped={}for k,v in pairs(data.EquippedAssets or {})do equipped[type(k)=="number"and v or k]=true end
    local group=state.fusePlan or Core.fuseGroup(data.Inventory or {},equipped,api.assets.Directory,api.kernel,count)
    if not group then return false end
    local inputs={}for _,uid in ipairs(group)do if not data.Inventory[uid]then state.fusePlan=nil;return false end;inputs[#inputs+1]=data.Inventory[uid] end
    if data.Money<api.kernel.PriceFor(inputs)then return false end
    if not active()then return false end
    state.fusePlan=group
    local loaded={}for _,uid in ipairs(slots)do loaded[uid]=true end
    for _,uid in ipairs(group)do
      if not active()then return false end
      if not loaded[uid]then
        local ok,message=rpc("Fusery","LoadPet",uid,false)
        if ok~=true then note("Fusion load rejected: "..tostring(message))return false end
      end
    end
    local ok,message=rpc("Fusery","BeginFuse")
    if ok==true then state.fusePlan=nil end
    note(ok==true and "Fusion started; native reveal completes reward"or "Fusion: "..tostring(message))return ok==true
end
local eventSpecs={
    {name="LightVsDarkness",fetch="FetchRings",decode="DecodeRings",data="Data.LightVsDarkness",shift=1,receipt="RingCollected"},
    {name="SammyEvent",fetch="FetchPickups",decode="DecodePickups",data="Data.SammyEvent",shift=0,receipt="PickupCollected"},
}
local eventReceipts={}
for _,spec in ipairs(eventSpecs)do
    local remote=api.remotes[spec.name] and api.remotes[spec.name][spec.receipt]
    if remote then connections[#connections+1]=remote.OnClientEvent:Connect(function(...)
        eventReceipts[spec.name]=(eventReceipts[spec.name]or 0)+1
    end)end
end
local function eventCollect()
    for _,spec in ipairs(eventSpecs)do
        if options[spec.name]~=false then
            local wave,a,b,c=rpc(spec.name,spec.fetch)
            local zones,removed=spec.shift==1 and b or a,spec.shift==1 and c or b
            if type(wave)=="number" and type(zones)=="table" then
                if not api[spec.name]then loadAPI(spec.name,spec.data)end
                local r=character();local best,distance
                for zone,encoded in pairs(zones)do
                    local ok,records=pcall(api[spec.name][spec.decode],encoded)
                    if ok then
                        local gone={}for _,id in ipairs(type(removed)=="table"and removed[zone]or{})do gone[id]=true end
                        for id,row in ipairs(records)do
                            local key=spec.name..":"..wave..":"..zone..":"..id
                            if not gone[id] and not (blocked[key]and blocked[key]>os.clock())then
                                local point=Vector3.new(row.X,row.Y,row.Z)
                                local d=(r.Position-point).Magnitude
                                if not distance or d<distance then best={point=point,key=key};distance=d end
                            end
                        end
                    end
                end
                if best then
                    local receipt=eventReceipts[spec.name]or 0
                    if not stopTraining()then return false end
                    walk(best.point+Vector3.new(0,2,0))
                    blocked[best.key]=os.clock()+15
                    -- Native proximity collector sends wave/zone/id; observe its receipt.
                    local ok=await(function()return(eventReceipts[spec.name]or 0)>receipt end,2)
                    note(ok and spec.name.." pickup confirmed"or spec.name.." pickup not confirmed")return ok
                end
            end
        end
    end
    return false
end

local parent=player:WaitForChild("PlayerGui")
local blue = Color3.fromRGB(80, 160, 255)
local white = Color3.fromRGB(232, 238, 248)
local function make(class, props, parentObject)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        if k=="Text" and class=="TextButton" and type(v)=="string" then v=v:upper() end
        obj[k] = v
    end
    obj.Parent = parentObject
    return obj
end
local function corner(obj, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, obj)
end
local old=parent:FindFirstChild("EXIPanel")
if old then old:Destroy()end
local gui = make("ScreenGui", {Name="EXIPanel", ResetOnSpawn=false,
    DisplayOrder=2147483647, ZIndexBehavior=Enum.ZIndexBehavior.Sibling}, parent)
local screen=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1},gui)
local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(800,600)
local width = math.min(392, viewport.X - 20)
local height = math.min(272, viewport.Y - 20)
local panel = make("Frame", {Size=UDim2.fromOffset(width,height),
    Position=UDim2.fromOffset((viewport.X-width)/2,(viewport.Y-height)/2),
    BackgroundColor3=Color3.fromRGB(8,12,18),BackgroundTransparency=0, BorderSizePixel=0,
    ClipsDescendants=true}, screen)
corner(panel,9)
make("UIStroke", {Color=Color3.fromRGB(48,76,111),Thickness=1}, panel)
local header = make("Frame", {Size=UDim2.new(1,0,0,30),
    BackgroundColor3=Color3.fromRGB(17,22,31),BorderSizePixel=0,Active=true}, panel)
local title = make("TextLabel", {Position=UDim2.fromOffset(18,0),
    Size=UDim2.new(1,-120,1,0),BackgroundTransparency=1,
    Text="EXIScript | STEAL AN EGG",TextColor3=blue,Font=Enum.Font.BuilderSansBold,
    TextSize=11,TextXAlignment=Enum.TextXAlignment.Left}, header)
make("UIGradient",{
    Color=ColorSequence.new(Color3.fromRGB(175,209,255),Color3.fromRGB(105,125,152)),
    Rotation=12},header)
make("Frame",{Position=UDim2.fromOffset(7,11),Size=UDim2.fromOffset(2,12),
    BackgroundColor3=blue,BorderSizePixel=0},header)
local function headerButton(text,x)
    local b=make("TextButton", {Size=UDim2.fromOffset(25,23),
        Position=UDim2.new(1,x,0,3),BackgroundColor3=Color3.fromRGB(14,19,27),
        Text=text,TextColor3=white,TextSize=20,Font=Enum.Font.BuilderSans},header)
    corner(b,6)
    return b
end
local mini=headerButton("−",-57)
local close=headerButton("×",-29)
local body=make("Frame", {Position=UDim2.fromOffset(0,30),
    Size=UDim2.new(1,0,1,-30),BackgroundTransparency=1},panel)
local sidebar=make("ScrollingFrame", {Size=UDim2.new(0,82,1,0),
    CanvasSize=UDim2.fromOffset(0,228),ScrollBarThickness=2,
    BackgroundColor3=Color3.fromRGB(15,19,27),BorderSizePixel=0},body)
local content=make("Frame", {Position=UDim2.fromOffset(90,29),
    Size=UDim2.new(1,-99,1,-51),BackgroundTransparency=1},body)
local pageTitle=make("TextLabel",{Position=UDim2.fromOffset(91,0),Size=UDim2.new(1,-101,0,26),
    BackgroundTransparency=1,Text="MAIN",TextColor3=white,Font=Enum.Font.BuilderSansBold,
    TextSize=12,TextXAlignment=Enum.TextXAlignment.Left},body)
make("Frame",{Position=UDim2.fromOffset(82,0),Size=UDim2.new(0,1,1,0),
    BackgroundColor3=Color3.fromRGB(31,43,59),BorderSizePixel=0},body)
make("Frame",{Position=UDim2.fromOffset(91,25),Size=UDim2.new(1,-102,0,1),
    BackgroundColor3=Color3.fromRGB(31,43,59),BorderSizePixel=0},body)
local selectPage
local pages={}
local tabs={}
local sessionOptions={}
local configChanged=function() end
local renderToggle={}

local ui={}
function ui.page(name)
    local frame=make("ScrollingFrame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=blue,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),Visible=false},content)
    make("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},frame)
    pages[name]=frame
    return frame
end
function ui.text(container,text)
    return make("TextLabel",{Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,Text=text,TextWrapped=true,TextSize=10,
        TextColor3=Color3.fromRGB(156,175,198),Font=Enum.Font.BuilderSans,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},container)
end
ui.groups={}
function ui.group(container,name)
    local frame=make("Frame",{Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundColor3=Color3.fromRGB(16,22,31),BorderSizePixel=0},container)
    corner(frame,6)
    local border=make("UIStroke",{Color=Color3.fromRGB(32,44,61),Thickness=1},frame)
    make("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,0)},frame)
    local header=make("TextButton",{LayoutOrder=0,Size=UDim2.new(1,0,0,25),
        BackgroundTransparency=1,Text="",AutoButtonColor=false},frame)
    make("TextLabel",{Position=UDim2.fromOffset(9,0),Size=UDim2.new(1,-35,1,0),
        BackgroundTransparency=1,Text=name:upper(),TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,TextColor3=white,TextSize=10,
        Font=Enum.Font.BuilderSansMedium},header)
    local arrow=make("TextLabel",{Position=UDim2.new(1,-24,0,0),Size=UDim2.fromOffset(20,25),
        BackgroundTransparency=1,Text="›",TextColor3=Color3.fromRGB(126,149,179),TextSize=17,
        Font=Enum.Font.BuilderSans},header)
    local body=make("Frame",{LayoutOrder=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,Visible=false},frame)
    make("UIPadding",{PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6),
        PaddingTop=UDim.new(0,2),PaddingBottom=UDim.new(0,5)},body)
    make("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},body)
    local accent=make("Frame",{Position=UDim2.fromOffset(0,7),Size=UDim2.fromOffset(2,11),
        BackgroundColor3=blue,BackgroundTransparency=0.7,BorderSizePixel=0},header)
    local entry={frame=frame,body=body}
    function entry.setOpen(open)
        body.Visible=open
        arrow.Text=open and "⌄" or "›"
        arrow.TextColor3=open and blue or Color3.fromRGB(126,149,179)
        border.Color=open and Color3.fromRGB(49,88,135) or Color3.fromRGB(32,44,61)
        frame.BackgroundColor3=open and Color3.fromRGB(18,27,39) or Color3.fromRGB(16,22,31)
        accent.BackgroundTransparency=open and 0 or 0.7
        if not open then
            for _,other in ipairs(ui.groups) do
                if other.frame:IsDescendantOf(body) then other.setOpen(false) end
            end
        end
    end
    ui.groups[#ui.groups+1]=entry
    header.Activated:Connect(function()
        local open=not body.Visible
        if open then
            for _,other in ipairs(ui.groups) do
                if other~=entry and other.frame.Parent==frame.Parent then other.setOpen(false) end
            end
        end
        entry.setOpen(open)
    end)
    return body
end

local status=ui.text(body,"")
status.Size=UDim2.new(1,-115,0,18);status.AutomaticSize=Enum.AutomaticSize.None
status.Position=UDim2.new(0,91,1,-21);status.TextTruncate=Enum.TextTruncate.AtEnd
report=function(message)if alive then status.Text=message end end
local savePath="EXIGames/StealAnEgg/settings_"..player.UserId..".json"
local function save()
 if type(writefile)~="function"or type(makefolder)~="function"then return end
 pcall(function()
  for _,dir in ipairs({"EXIGames","EXIGames/StealAnEgg"})do if type(isfolder)~="function"or not isfolder(dir)then pcall(makefolder,dir)end end
  writefile(savePath,HTTP:JSONEncode(options))
 end)
end
if type(readfile)=="function"then pcall(function()
 local loaded=HTTP:JSONDecode(readfile(savePath))
 for k,v in pairs(loaded)do
  if (k=="runSpeed"or k=="runMargin"or k=="runSpeedCap")and type(v)=="number"and v==v then
   options[k]=math.clamp(v,k=="runMargin"and 1 or 16,k=="runMargin"and 100 or 1000)
  elseif type(v)=="boolean"and type(options[k])=="boolean"then options[k]=v
  elseif (k=="excluded"or k=="excludedPets"or k=="eggTypes"or k=="rarities")and type(v)=="table"then
   for id,on in pairs(v)do if type(id)=="string"and type(on)=="boolean"then options[k][id]=on end end
  end
 end
 if loaded.priorityVersion~=2 then options.skipUnsafeEggs=false end
 if options.autoRunSpeed then options.fixedRunSpeed=false end
 options.master=false -- Starting a new session always exposes settings before moving.
end)end
local renders={}
local function toggle(container,key,text,map)
 local target=map or options
 local row=make("TextButton",{Size=UDim2.new(1,-5,0,25),Text="",BorderSizePixel=0,
  BackgroundColor3=Color3.fromRGB(21,30,43)},container)
 corner(row,5)
 make("TextLabel",{Position=UDim2.fromOffset(7,0),Size=UDim2.new(1,-53,1,0),
  BackgroundTransparency=1,Text=text:upper(),TextColor3=white,TextSize=10,TextWrapped=true,
  Font=Enum.Font.BuilderSans,TextXAlignment=Enum.TextXAlignment.Left},row)
 local track=make("Frame",{Name="SwitchTrack",Position=UDim2.new(1,-32,.5,-6),Size=UDim2.fromOffset(25,12),
  BackgroundColor3=Color3.fromRGB(47,59,75),BorderSizePixel=0},row)
 corner(track,8)
 local knob=make("Frame",{Name="SwitchKnob",Position=UDim2.fromOffset(2,2),Size=UDim2.fromOffset(8,8),
  BackgroundColor3=white,BorderSizePixel=0},track)
 corner(knob,8)
 local function render()
  track.BackgroundColor3=target[key]and blue or Color3.fromRGB(47,59,75)
  knob.Position=UDim2.fromOffset(target[key]and 15 or 2,2)
 end
 render();renders[row]=render
 row.Destroying:Connect(function()renders[row]=nil end)
 row.Activated:Connect(function()
  target[key]=not target[key]
  if target==options and target[key]and key=="fixedRunSpeed"then options.autoRunSpeed=false end
  if target==options and target[key]and key=="autoRunSpeed"then options.fixedRunSpeed=false end
  if key=="master"and not options.master then restoreRunSpeed()end
  if key=="fixedRunSpeed"or key=="autoRunSpeed"then for _,refresh in pairs(renders)do refresh()end end
  if map==options.eggTypes then for _,refresh in pairs(renders)do refresh()end else render()end
  save()
 end)
 return row
end
local function button(container,text,fn)
 local b=make("TextButton",{Size=UDim2.new(1,-5,0,25),Text=text,TextSize=10,Font=Enum.Font.BuilderSans,
  TextColor3=blue,BackgroundColor3=Color3.fromRGB(20,29,41),BorderSizePixel=0},container)
 corner(b,5);b.Activated:Connect(fn);return b
end
local names={"Main","Eggs","Biomes","Rarities","Pets","Base","Training","Events","Fusion","Performance","Tools","Settings"}
for _,name in ipairs(names)do ui.page(name)end
local main=ui.group(pages.Main,"Automation")
toggle(main,"master","Master switch")
button(main,"Enable core automation",function()
 for _,k in ipairs({"steal","hatch","equip","treadmill","events","rewards"})do options[k]=true end
 for _,render in pairs(renders)do render()end;save();note("Core enabled; turn on Master to begin")
end)
button(main,"Stop all",function()
 options.master=false
 for _,render in pairs(renders)do render()end
 local r,h=character();if r then h:MoveTo(r.Position)end
 task.spawn(stopTraining);save()
end)
ui.text(main,"Finish carrying before hatch, equipment, events or training. Return uses walking; no carried teleport.")
local eggs=ui.group(pages.Eggs,"Collection and hatching")
toggle(eggs,"steal","Teleport to egg; run home")
toggle(eggs,"hatch","Auto plant and native hatch")
ui.text(eggs,"Highest rarity, then biggest spawned egg, then nearest. Native reset/spawn signals re-rank immediately; exclusions still apply.")
local eggRecords
local eggRecordsModule=resolve("Shared.Util.EggRecords")
if eggRecordsModule then
 local value=call("load egg names",require,eggRecordsModule)
 if type(value)=="table"then eggRecords=value end
end
local function eggLabel(category,record)
 local info=api.assets.Directory[category]
 if eggRecords then
  local sample=record or {AssetCategory=category,AssetScale=1,AssetEyeColor="Black",AssetColorSeed=0,AssetColorIndex=1,Mutations={}}
  local ok,name=pcall(eggRecords.DisplayName,sample)
  if ok and type(name)=="string"then return name end
 end
 return info and info.Egg and info.Egg.DisplayName or category.." Egg"
end
local eggTypes=ui.group(pages.Eggs,"Egg catalogue • included types")
local eggSearch=make("TextBox",{Size=UDim2.new(1,-5,0,24),Text="",PlaceholderText="Search egg, pet or rarity",TextSize=11,
 BackgroundColor3=Color3.fromRGB(20,29,41),TextColor3=white,ClearTextOnFocus=false},eggTypes)
local eggPage=1
local eggCount=ui.text(eggTypes,"")
local eggChoices=make("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1},eggTypes)
make("UIListLayout",{Padding=UDim.new(0,3)},eggChoices)
local eggEntries={}
for category,info in pairs(api.assets.Directory)do
 if info.Egg then eggEntries[#eggEntries+1]={id=category,name=eggLabel(category),rank=tonumber(info.Rarity and info.Rarity.Rank)or 0,
  rarity=info.Rarity and (info.Rarity.DisplayName or info.Rarity._id)or "Unknown"}end
end
table.sort(eggEntries,function(a,b)if a.rank~=b.rank then return a.rank>b.rank end if a.name~=b.name then return a.name<b.name end return a.id<b.id end)
local eggMatches={}
local function showEggTypes()
 for _,child in ipairs(eggChoices:GetChildren())do if child:IsA("TextButton")then child:Destroy()end end
 eggMatches={}
 local query=eggSearch.Text:lower()
 for _,entry in ipairs(eggEntries)do
  if (entry.name.." "..entry.id.." "..entry.rarity):lower():find(query,1,true)then eggMatches[#eggMatches+1]=entry end
 end
 local maxPage=math.max(1,math.ceil(#eggMatches/40));eggPage=math.clamp(eggPage,1,maxPage)
 eggCount.Text=#eggMatches.." eggs • page "..eggPage.." / "..maxPage
 for index=(eggPage-1)*40+1,math.min(eggPage*40,#eggMatches)do
  local entry=eggMatches[index]
  if options.eggTypes[entry.id]==nil then options.eggTypes[entry.id]=true end
  toggle(eggChoices,entry.id,entry.name.." | "..entry.rarity.." | "..entry.id,options.eggTypes)
 end
end
button(eggTypes,"Previous egg page",function()eggPage=math.max(1,eggPage-1);showEggTypes()end)
button(eggTypes,"Next egg page",function()eggPage=eggPage+1;showEggTypes()end)
button(eggTypes,"Include all eggs",function()for _,entry in ipairs(eggEntries)do options.eggTypes[entry.id]=true end;showEggTypes();save()end)
button(eggTypes,"Exclude all eggs",function()for _,entry in ipairs(eggEntries)do options.eggTypes[entry.id]=false end;showEggTypes();save()end)
eggSearch:GetPropertyChangedSignal("Text"):Connect(function()eggPage=1;showEggTypes()end)
showEggTypes()
ui.text(eggTypes,"Each switch includes that egg's pet category. Names come from the native egg naming helper when available; pet category distinguishes shared egg names. Biome, rarity and pet exclusions still apply.")
local liveEggs=ui.group(pages.Eggs,"Live eggs in the map")
local liveList=ui.text(liveEggs,"")
local livePage=1
local function refreshLiveEggs()
 local rows=api.eggs.ReadFieldEggs().Records
 local r=character()
 table.sort(rows,function(a,b)return Core.better(a,b,api.assets.Directory,r and r.Position)end)
 local maxPage=math.max(1,math.ceil(#rows/20));livePage=math.clamp(livePage,1,maxPage)
 local lines={#rows.." live eggs • page "..livePage.." / "..maxPage}
 for i=(livePage-1)*20+1,math.min(livePage*20,#rows)do
  local record=rows[i];local info=api.assets.Directory[record.AssetCategory]
  lines[#lines+1]=eggLabel(record.AssetCategory,record).." | "..tostring(info and info.Rarity and info.Rarity._id or "Unknown")
   .." | "..record.AreaId.." | "..record.State.." | "..record.AssetCategory..string.format(" | size %.2fx",tonumber(record.AssetScale)or 1)
 end
 liveList.Text=table.concat(lines,"\n")
end
button(liveEggs,"Refresh live eggs",refreshLiveEggs)
button(liveEggs,"Previous live page",function()livePage=math.max(1,livePage-1);refreshLiveEggs()end)
button(liveEggs,"Next live page",function()livePage=livePage+1;refreshLiveEggs()end)
local biome=ui.group(pages.Biomes,"Excluded biomes")
local sorted={}for id in pairs(api.areas.Directory)do sorted[#sorted+1]=id end table.sort(sorted)
for _,id in ipairs(sorted)do toggle(biome,id,"Exclude "..id,options.excluded)end
local tiers=ui.group(pages.Rarities,"Include rarity tiers")
local rarityIds={}for id,tier in pairs(api.rarity.Rarities)do if id==tier._id then rarityIds[#rarityIds+1]=id end end
table.sort(rarityIds,function(a,b)return api.rarity.Rarities[a].Rank>api.rarity.Rarities[b].Rank end)
for _,id in ipairs(rarityIds)do if options.rarities[id]==nil then options.rarities[id]=true end toggle(tiers,id,id,options.rarities)end
local pets=ui.group(pages.Pets,"Pet categories to exclude")
local search=make("TextBox",{Size=UDim2.new(1,-5,0,24),Text="",PlaceholderText="Search pet / egg category",TextSize=11,
 BackgroundColor3=Color3.fromRGB(20,29,41),TextColor3=white,ClearTextOnFocus=false},pets)
local petChoices=make("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1},pets)
make("UIListLayout",{Padding=UDim.new(0,3)},petChoices)
local function showPets()
 for _,c in ipairs(petChoices:GetChildren())do if c:IsA("TextButton")then c:Destroy()end end
 local ids={}for id in pairs(api.assets.Directory)do if id:lower():find(search.Text:lower(),1,true)then ids[#ids+1]=id end end table.sort(ids)
 for i=1,math.min(60,#ids)do toggle(petChoices,ids[i],"Exclude "..ids[i],options.excludedPets)end
end
search:GetPropertyChangedSignal("Text"):Connect(showPets);showPets()
local base=ui.group(pages.Base,"Income and upgrades")
toggle(base,"equip","Auto equip best native earning pets")
toggle(base,"upgrades","Buy affordable cash base / treadmill upgrades")
toggle(base,"rewards","Claim discovered index rewards")
ui.text(base,"Cash upgrades spend in-game money. Paid products, selling and rebirth are never invoked automatically.")
local training=ui.group(pages.Training,"Speed")
toggle(training,"treadmill","Train on own treadmill when idle")
ui.text(training,"Uses own TreadmillBottom and AskWearStill. Leaves the belt before egg, hatch or event movement. Egg spawns interrupt idle training; confirmed carries finish first.")
local running=ui.group(pages.Training,"Running and guardian speed")
toggle(running,"fixedRunSpeed","Use fixed running speed")
toggle(running,"autoRunSpeed","Auto speed from my chasing guardians")
toggle(running,"skipUnsafeEggs","Defer eggs above native escape-speed estimate")
local function runNumber(key,label,minimum,maximum)
 ui.text(running,label)
 local box=make("TextBox",{Size=UDim2.new(1,-5,0,24),Text=tostring(options[key]),ClearTextOnFocus=false,
  TextSize=11,TextColor3=white,BackgroundColor3=Color3.fromRGB(20,29,41)},running)
 box.FocusLost:Connect(function()
  local value=tonumber(box.Text)
  if value and value==value and value>-math.huge and value<math.huge then options[key]=math.clamp(value,minimum,maximum)end
  box.Text=tostring(options[key]);save()
 end)
 renders[box]=function()box.Text=tostring(options[key])end
 box.Destroying:Connect(function()renders[box]=nil end)
end
runNumber("runSpeed","Fixed speed (studs/sec)",16,1000)
runNumber("runMargin","Auto speed advantage (studs/sec)",1,100)
runNumber("runSpeedCap","Maximum requested run speed",16,1000)
ui.text(running,"Modes are exclusive. Auto follows guardians targeting you, including their distance-based acceleration. Return is always Humanoid running, never teleporting. These are temporary local speed requests; server corrections or native slowdowns may prevent outrunning. Diagnostics show requested, measured and guardian speeds.")
local events=ui.group(pages.Events,"Live activities")
toggle(events,"events","Collect active event pickups")
for _,spec in ipairs(eventSpecs)do toggle(events,spec.name,spec.name)end
ui.text(events,"Supports Light vs Darkness rings, Sammy pickups and field event eggs. Native collectors confirm receipts. Other event-specific bosses, races and dimensions are listed in the audit; full automatic completion is not implemented.")
local fusion=ui.group(pages.Fusion,"Matching pet fusion")
toggle(fusion,"fusion","Fuse unequipped non-favorite duplicates")
ui.text(fusion,"Consumes native INPUT_COUNT matching pets and cash. Uses native eligibility and PriceFor; never takes equipped or favorite pets. Existing partial inputs remain available in the native menu.")
local settings=ui.group(pages.Settings,"Session")
button(settings,"Print diagnostics",function()print(table.concat(state.trace,"\n"));note("Diagnostics printed to console")end)
button(settings,"Queue walk to own base",function()state.wantHome=true;note("Walk home queued behind current action")end)
ui.text(settings,"Settings save in EXIGames/StealAnEgg. Master starts off. No promotional-code loop is included.")
-- Visual ownership: save each property once, restore on toggle-off or close.
local perf={saved=setmetatable({},{__mode="k"}),prefs={},lastSignature=nil,revision=0}
local function restoreVisuals()
 for obj,properties in pairs(perf.saved)do
  if obj.Parent then for property,value in pairs(properties)do pcall(function()obj[property]=value end)end end
  perf.saved[obj]=nil
 end
end
local function writeVisual(obj,property,value)
 local ok,old=pcall(function()return obj[property]end)
 if not ok or old==value then return end
 perf.saved[obj]=perf.saved[obj]or{}
 if perf.saved[obj][property]==nil then perf.saved[obj][property]=old end
 pcall(function()obj[property]=value end)
end
local function hideVisual(obj)
 if obj:IsA("BasePart")then writeVisual(obj,"LocalTransparencyModifier",1)
 elseif obj:IsA("Decal")or obj:IsA("Texture")then writeVisual(obj,"Transparency",1)
 elseif obj:IsA("BillboardGui")or obj:IsA("SurfaceGui")then writeVisual(obj,"Enabled",false)end
end
local function otherPlotRoots()
 local roots={}
 if not options.hidePens then return roots end
 for slot,owner in pairs(api.plots.ReadOwners())do
  if owner~=player.UserId then
   local folder=api.plots.ResolveFolder()
   local other=folder and folder:FindFirstChild(tostring(slot))
   local detail=other and other:FindFirstChild("ToUpdate")
   if detail then roots[#roots+1]=detail end
  end
 end
 return roots
end
local function applyVisual(obj,roots)
 if options.lowDetail then
  if obj:IsA("BasePart")then writeVisual(obj,"Material",Enum.Material.SmoothPlastic);writeVisual(obj,"Reflectance",0);writeVisual(obj,"CastShadow",false)
  elseif obj:IsA("Decal")or obj:IsA("Texture")then writeVisual(obj,"Transparency",1)end
 end
 if options.disableEffects and (obj:IsA("ParticleEmitter")or obj:IsA("Trail")or obj:IsA("Beam")or obj:IsA("Smoke")or obj:IsA("Fire")or obj:IsA("Sparkles")or obj:IsA("PostEffect"))then writeVisual(obj,"Enabled",false)end
 for _,root in ipairs(roots)do if obj:IsDescendantOf(root)then hideVisual(obj)break end end
end
local preferences
local prefModule=resolve("Shared.Preferences")
if prefModule then local value=call("load preferences",require,prefModule)if type(value)=="table"then preferences=value end end
local function syncPreference(key,on)
 if not preferences then return end
 if on then
  if perf.prefs[key]==nil then perf.prefs[key]=preferences.IsOn(key)end
  if not preferences.IsOn(key)then call("preference:"..key,preferences.Set,key,true)end
 elseif perf.prefs[key]~=nil then
  local old=perf.prefs[key]
  if preferences.IsOn(key)==old or call("preference:"..key,preferences.Set,key,old)==true then perf.prefs[key]=nil end
 end
end
local function restorePreferences()
 if preferences then for key,value in pairs(perf.prefs)do pcall(preferences.Set,key,value)end end
 perf.prefs={}
end
local function performanceSignature()
 local values={"pens="..tostring(options.hidePens),"detail="..tostring(options.lowDetail),"effects="..tostring(options.disableEffects)}
 if options.hidePens then for slot,owner in pairs(api.plots.ReadOwners())do values[#values+1]=tostring(slot)..":"..tostring(owner)end end
 table.sort(values);return table.concat(values,"|")
end
local function refreshPerformance()
 perf.revision=perf.revision+1;local revision=perf.revision
 restoreVisuals()
 local roots=otherPlotRoots()
 if options.lowDetail then writeVisual(game:GetService("Lighting"),"GlobalShadows",false)end
 if not (options.hidePens or options.lowDetail or options.disableEffects)then return end
 local objects=workspace:GetDescendants()
 for _,obj in ipairs(game:GetService("Lighting"):GetDescendants())do objects[#objects+1]=obj end
 for i,obj in ipairs(objects)do
  if not alive or revision~=perf.revision then return end
  if obj.Parent then applyVisual(obj,roots)end
  if i%150==0 then task.wait()end
 end
end
connections[#connections+1]=workspace.DescendantAdded:Connect(function(obj)
 if options.hidePens or options.lowDetail or options.disableEffects then task.defer(function()if alive and obj.Parent then applyVisual(obj,otherPlotRoots())end end)end
end)
connections[#connections+1]=game:GetService("Lighting").DescendantAdded:Connect(function(obj)
 if options.disableEffects then task.defer(function()if alive and obj.Parent then applyVisual(obj,{})end end)end
end)
local performance=ui.group(pages.Performance,"Reversible performance booster")
toggle(performance,"hidePens","Hide other players' pen visuals")
toggle(performance,"hideOtherPets","Hide other pets (native)")
toggle(performance,"hideSelfPets","Hide own pets (native)")
toggle(performance,"lowDetail","Plain materials / no textures or shadows")
toggle(performance,"disableEffects","Disable particles trails and post effects")
toggle(performance,"disableVideos","Disable treadmill videos (native)")
button(performance,"Apply performance preset",function()
 for _,key in ipairs({"hidePens","hideOtherPets","hideSelfPets","lowDetail","disableEffects","disableVideos"})do options[key]=true end
 for _,render in pairs(renders)do render()end;save()
end)
button(performance,"Restore visuals",function()
 for _,key in ipairs({"hidePens","hideOtherPets","hideSelfPets","lowDetail","disableEffects","disableVideos"})do options[key]=false end
 for _,render in pairs(renders)do render()end;save()
end)
ui.text(performance,"Local visual changes only. No parts are destroyed and collisions/prompts stay intact. Native pet settings suppress pet rendering work; materials/effects savings vary by device. Close restores changes owned by EXIS.")
local tools=ui.group(pages.Tools,"EXIS diagnostics")
local diagnostics=ui.text(tools,"Loading session diagnostics…")
local fps=0;local samples,elapsed=0,0
connections[#connections+1]=game:GetService("RunService").RenderStepped:Connect(function(dt)
 samples=samples+1;elapsed=elapsed+dt
 if elapsed>=1 then fps=math.floor(samples/elapsed+.5);samples,elapsed=0,0 end
end)
local function diagnosticsText()
 local r,h=character();local carry=carrying();local data=profile()
 local p={}for key in pairs(pending)do p[#p+1]=key end table.sort(p)
 local modules={}for key in pairs(api)do modules[#modules+1]=key end table.sort(modules)
 return table.concat({"EXIS Steal an Egg | build 4","Place "..game.PlaceId.." | Job "..game.JobId,
  "FPS "..fps.." | Master "..tostring(options.master).." | Task "..state.job,
  "Health "..tostring(h and math.floor(h.Health)).." | Save "..tostring(data~=nil).." | Base "..tostring(plot()~=nil),
  "Carrying "..tostring(carry.IsCarrying).." | Owned eggs "..Core.count(api.eggs.ReadOwnerEggs(player.UserId)),
  "Delivered "..state.claimed.." | Hatched "..state.hatches.." | Training "..tostring(state.training),
  "Run requested "..tostring(state.runRequested or "native").." | measured "..tostring(state.runMeasured and math.floor(state.runMeasured)or "—").." | guardian "..tostring(state.guardSpeed or 0).." | capped "..tostring(state.runCapped==true),
  "Pickup "..tostring(state.pickupPending and state.pickupPending.uid or "none").." | target "..tostring(state.targetEgg or "none"),
  "Carry dispatches "..tostring(state.pickupDispatches or 0).." | verdict "..tostring(state.lastPickupVerdict or "none"),
  "Field revision "..tostring(state.fieldRevision or 0).." | reset period "..tostring(state.resetPeriod or "unknown").." | next reset "..tostring(state.nextResetAt or "unknown"),
  "Pending "..(#p>0 and table.concat(p,", ")or"none"),"Modules "..table.concat(modules,", "),
  "Hatch input "..tostring(type(fireproximityprompt)=="function").." | Files "..tostring(type(writefile)=="function"),
  "Native preferences "..tostring(preferences~=nil),"Recent log:",table.concat(state.trace,"\n")},"\n")
end
button(tools,"Copy diagnostics",function()
 local text=diagnosticsText();print(text)
 if type(setclipboard)=="function"then setclipboard(text);note("Diagnostics copied")else note("Clipboard unavailable; diagnostics printed")end
end)
button(tools,"Save diagnostics file",function()
 local ok,err=pcall(function()assert(type(writefile)=="function","writefile unavailable");save();writefile("EXIGames/StealAnEgg/diagnostics_"..player.UserId..".txt",diagnosticsText())end)
 note(ok and "Diagnostics file saved"or tostring(err))
end)
button(tools,"Clear diagnostic log",function()state.trace={};note("Log cleared")end)
button(tools,"Refresh native snapshots",function()state.refreshSnapshots=true;note("Snapshot refresh queued; pending mutations retained")end)
local session=ui.group(pages.Tools,"Session and configuration")
button(session,"Save settings now",function()save();note("Settings save requested")end)
button(session,"Reload saved settings (paused)",function()
 local ok,err=pcall(function()
  assert(type(readfile)=="function","readfile unavailable")
  local data=HTTP:JSONDecode(readfile(savePath));options.master=false;restoreRunSpeed()
  for k,v in pairs(data)do
   if (k=="runSpeed"or k=="runMargin"or k=="runSpeedCap")and type(v)=="number"and v==v then
    options[k]=math.clamp(v,k=="runMargin"and 1 or 16,k=="runMargin"and 100 or 1000)
   elseif k~="master"and type(v)=="boolean"and type(options[k])=="boolean"then options[k]=v
   elseif (k=="excluded"or k=="excludedPets"or k=="eggTypes"or k=="rarities")and type(v)=="table"then
    for id in pairs(options[k])do options[k][id]=nil end
    for id,on in pairs(v)do if type(id)=="string"and type(on)=="boolean"then options[k][id]=on end end
   end
  end
  if data.priorityVersion~=2 then options.skipUnsafeEggs=false end
  if options.autoRunSpeed then options.fixedRunSpeed=false end
  for _,render in pairs(renders)do render()end
 end)
 note(ok and "Settings reloaded; Master paused"or tostring(err))
end)
toggle(session,"antiAfk","Anti-idle input")
toggle(session,"autoExecute","Queue EXIS on teleport")
toggle(session,"autoReconnect","Reconnect on connection loss (277/279)")
local function queueLoader()
 local queue=queue_on_teleport or (syn and syn.queue_on_teleport)
 if type(queue)~="function"then return false,"queue_on_teleport unavailable"end
 local code=("if game.PlaceId==107778070777162 and type(readfile)=='function' then local ok,c=pcall(function()return game:GetService('HttpService'):JSONDecode(readfile(%q))end);if ok and c.autoExecute then loadstring(game:HttpGet('https://raw.githubusercontent.com/iaxen/EXIScript/main/EXIScript.lua'))()end end"):format(savePath)
 return pcall(queue,code)
end
button(session,"Rejoin current server",function()
 save();if options.autoExecute then queueLoader()end
 game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId,game.JobId,player)
end)
button(session,"Join another available server",function()
 save();if options.autoExecute then queueLoader()end
 game:GetService("TeleportService"):Teleport(game.PlaceId,player)
end)
ui.text(session,"Teleport queue requires executor support. Auto reconnect handles connection loss only; it does not retry kicks or moderation messages. New sessions start paused.")
connections[#connections+1]=player.OnTeleport:Connect(function()if options.autoExecute then queueLoader()end end)
connections[#connections+1]=player.Idled:Connect(function()
 if options.antiAfk then pcall(function()local vu=game:GetService("VirtualUser");vu:CaptureController();vu:ClickButton2(Vector2.new())end)end
end)
local reconnectAt,reconnectAttempts
connections[#connections+1]=game:GetService("GuiService").ErrorMessageChanged:Connect(function(message)
 local text=tostring(message):lower()
 local code=tonumber(text:match("error%s*code%s*:%s*(%d+)")or text:match("%((%d%d%d)%)"))
 local lost=code and (code==277 or code==279)or (not code and text:find("lost connection",1,true)~=nil)
 if options.autoReconnect and lost then reconnectAt=os.clock()+3;reconnectAttempts=0;note("Connection lost; reconnect queued")end
end)
local visualThread
local queuedOption=false
-- Performance/session work is independent of the farm master, but never owns movement.
task.spawn(function()
 while alive do
  local ok,err=pcall(function()
   syncPreference("HideOtherPets",options.hideOtherPets)
   syncPreference("HideSelfPets",options.hideSelfPets)
   syncPreference("DisableVideos",options.disableVideos)
   local signature=performanceSignature()
   if signature~=perf.lastSignature then
    perf.lastSignature=signature
    visualThread=task.spawn(refreshPerformance)
   end
   if options.autoExecute and not queuedOption then local done,message=queueLoader();queuedOption=done;if not done then note(tostring(message))end
   elseif not options.autoExecute then queuedOption=false end
   if reconnectAt and options.autoReconnect and os.clock()>=reconnectAt then
    reconnectAttempts=(reconnectAttempts or 0)+1;reconnectAt=os.clock()+math.min(30,3*2^reconnectAttempts)
    if options.autoExecute then queueLoader()end
    game:GetService("TeleportService"):Teleport(game.PlaceId,player)
   elseif not options.autoReconnect then reconnectAt=nil end
   diagnostics.Text=diagnosticsText()
   if ui.selected=="Eggs"then refreshLiveEggs()end
  end)
  if not ok then note("Tools: "..tostring(err))end
  task.wait(2)
 end
end)
gui.Destroying:Connect(function()
 perf.revision=perf.revision+1
 restoreVisuals()
 task.spawn(restorePreferences)
end)

selectPage=function(name)
 ui.selected=name;pageTitle.Text=name:upper()
 for key,frame in pairs(pages)do frame.Visible=key==name end
 for key,b in pairs(tabs)do b.BackgroundColor3=key==name and Color3.fromRGB(23,45,71)or Color3.fromRGB(15,19,27);b.TextColor3=key==name and blue or white end
end
sidebar.CanvasSize=UDim2.fromOffset(0,#names*24+8)
for i,name in ipairs(names)do
 local b=make("TextButton",{Position=UDim2.fromOffset(4,4+(i-1)*24),Size=UDim2.new(1,-8,0,21),Text="  "..name,
  TextXAlignment=Enum.TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(15,19,27),BorderSizePixel=0,TextColor3=white,
  Font=Enum.Font.BuilderSansMedium,TextSize=10},sidebar)
 corner(b,7);make("UIStroke",{Color=Color3.fromRGB(35,56,79),Thickness=1},b);tabs[name]=b
 b.Activated:Connect(function()selectPage(name)end)
end
local icon=make("TextButton",{Name="OpenEXIScript",Size=UDim2.fromOffset(32,32),Position=UDim2.fromOffset(12,90),
 BackgroundColor3=Color3.fromRGB(8,15,25),Text="EXIS",TextColor3=white,Font=Enum.Font.BuilderSansBold,TextSize=10,Visible=false},screen)
corner(icon,4);make("UIStroke",{Color=blue,Thickness=1.5},icon)
mini.Activated:Connect(function()panel.Visible=false;icon.Visible=true end)
icon.Activated:Connect(function()panel.Visible=true;icon.Visible=false end)
local dragging,start,startPosition
header.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=input;start=input.Position;startPosition=panel.Position end end)
connections[#connections+1]=UIS.InputChanged:Connect(function(input)
 if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input==dragging)then
  local delta=input.Position-start;local view=screen.AbsoluteSize
  panel.Position=UDim2.fromOffset(math.clamp(startPosition.X.Offset+delta.X,0,math.max(0,view.X-panel.AbsoluteSize.X)),math.clamp(startPosition.Y.Offset+delta.Y,0,math.max(0,view.Y-panel.AbsoluteSize.Y)))
 end
end)
connections[#connections+1]=UIS.InputEnded:Connect(function(input)if input==dragging then dragging=nil end end)
close.Activated:Connect(function()gui:Destroy()end)
gui.Destroying:Connect(function()
 alive=false;options.master=false
 restoreRunSpeed()
 for _,connection in ipairs(connections)do connection:Disconnect()end
 local r,h=character();if r then h:MoveTo(r.Position)end
 task.spawn(stopTraining)
end)
selectPage("Main")
local function periodic(key,seconds,fn)
 if os.clock()<(cooldown[key]or 0)then return false end
 cooldown[key]=os.clock()+seconds
 state.job=key
 local ok,result=pcall(fn)
 if not ok then note(key..": "..tostring(result))return false end
 return result==true
end
local function wakeEggs(reset)
 state.fieldRevision=(state.fieldRevision or 0)+1
 state.eggUrgent=true;cooldown.steal=0
 if reset then
  for uid in pairs(blocked)do if not uid:find(":",1,true)then blocked[uid]=nil end end
 end
end
local function observeField(snapshot)
 local versions=state.fieldVersions or {};local nextVersions={}
 for _,egg in pairs(snapshot.Records or {})do
  nextVersions[egg.Uid]=egg.Version
  if versions[egg.Uid]~=egg.Version then blocked[egg.Uid]=nil end
 end
 state.fieldVersions=nextVersions;state.resetSync=nil
 wakeEggs(false)
end
local function watchEggSignals()
 local function listen(name,fn)
  local signal=api.eggs[name]
  if signal and signal.Connect then connections[#connections+1]=signal:Connect(fn)end
 end
 observeField(api.eggs.ReadFieldEggs())
 listen("FieldRefreshed",observeField)
 listen("FieldShifted",function(egg)
  local versions=state.fieldVersions or {};state.fieldVersions=versions
  if versions[egg.Uid]~=egg.Version then blocked[egg.Uid]=nil end
  versions[egg.Uid]=egg.Version;wakeEggs(false)
 end)
 listen("FieldGone",function(uid)
  if state.fieldVersions then state.fieldVersions[uid]=nil end
  blocked[uid]=nil;wakeEggs(false)
 end)
 listen("ResetCountdown",function(payload)
  if type(payload.DayStartsAt)=="number"and payload.DayStartsAt>(state.lastCountdownAt or -math.huge)then
   state.lastCountdownAt=payload.DayStartsAt;state.countdownAt=payload.DayStartsAt
  end
 end)
 listen("RarityRevealed",function(payload)
  if not state.revealPeriod or payload.PeriodIndex>state.revealPeriod then
   state.revealPeriod=payload.PeriodIndex;state.resetSync=true;wakeEggs(true)
  end
 end)
end
local function pollEggReset()
 local cycle=api.cycle
 if not cycle or not cycle.IsRunning()then state.nextResetAt=nil;return end
 local now=api.clock and api.clock.Now()or workspace:GetServerTimeNow()
 local period=cycle.PeriodIndexAt(now)
 local crossed=state.resetPeriod~=nil and period~=state.resetPeriod
 local countdown=state.countdownAt
 if countdown and now>=countdown then state.countdownAt=nil;crossed=true end
 state.resetPeriod=period;state.nextResetAt=cycle.NextResetTime(now)
 if crossed then state.resetSync=true;wakeEggs(true)end
end
watchEggSignals()
-- These listeners only invalidate state. The existing single worker owns all movement.
task.spawn(function()
 while alive do
  local ok,message=pcall(pollEggReset)
  if not ok then state.resetClockError=tostring(message)end
  task.wait(.05)
 end
end)
local function farmStep()
    if carrying().IsCarrying then state.pickupPending=nil;state.collectionHoldUntil=nil;returnEgg();return end
    if pending.carry then state.job="waiting for native carry reply";return end
    if state.hatchInFlight then
     local hatch=state.hatchInFlight
     if api.eggs.ReadOwnedEgg(player.UserId,hatch.uid)==nil then
      state.hatchInFlight=nil;state.hatches=state.hatches+1;note("Late native hatch receipt confirmed")
     elseif os.clock()<hatch.untilTime then state.job="waiting for native hatch";return
     else state.hatchInFlight=nil;note("Hatch receipt timed out; keeping retry backoff")end
    end
    if state.pickupPending then
     local attempt=state.pickupPending
     if os.clock()-attempt.at<12 then state.job="waiting for pickup receipt";return end
     blocked[attempt.uid]=os.clock()+8;state.pickupPending=nil
     note("Pickup expired without carry receipt; retrying collection, not training")
     return
    end
    if state.collectionHoldUntil and os.clock()<state.collectionHoldUntil then
     state.job="retrying egg pickup"
     if options.steal then periodic("steal",.25,stealEgg)end
     return
    end
    if state.resetSync and options.steal then
     state.resetSync=nil
     call("field sync",api.eggs.SyncFieldEggs)
     if carrying().IsCarrying or pending.carry then return end
    end
    if state.refreshSnapshots then
     state.refreshSnapshots=nil
     call("field sync",api.eggs.SyncFieldEggs)
     call("owned sync",api.eggs.SyncOwnedEggs)
     note("Native snapshots refreshed")
     return
    end
    if state.wantHome then state.wantHome=nil;local b=plot()if b and stopTraining()then walk(b.PetArea.Position+Vector3.new(0,3,0))end;return end
    if options.steal and newEggOpportunity()then
     if state.eggUrgent then cooldown.steal=0 end
     state.pickupAttempted=false
     if periodic("steal",.25,stealEgg)or state.pickupAttempted then return end
    end
    if state.training and os.clock()<state.trainUntil and options.treadmill then return end
    if state.training and not stopTraining()then return end
    if not api.eggs.HasFieldSnapshot()then periodic("sync",10,function()call("field sync",api.eggs.SyncFieldEggs)return true end)end
    if options.hatch and periodic("hatch",2,plantOrHatch)then return end
    if carrying().IsCarrying then return end
    if options.equip then periodic("equip",15,equipBest)end
    if carrying().IsCarrying then return end
    if options.upgrades then periodic("upgrades",8,upgrades)end
    if carrying().IsCarrying then return end
    if options.rewards then periodic("index",30,function()return rpc("Codex","AskRedeemAll")==true end)end
    if carrying().IsCarrying then return end
    if options.fusion then periodic("fusion",15,fuse)end
    if carrying().IsCarrying then return end
    if options.events and periodic("events",12,eventCollect)then return end
    if carrying().IsCarrying then return end
    if options.steal then
     state.pickupAttempted=false
     if periodic("steal",.25,stealEgg)or state.pickupAttempted then return end
    end
    if carrying().IsCarrying then return end
    if options.treadmill then periodic("training",3,train)end
end
-- A single worker owns movement and requests. Carrying always finishes first.
task.spawn(function()
 while alive do
  if not active()then
   if state.training then periodic("stop training",3,stopTraining)end
  else
   local ok,err=pcall(farmStep)
   if not ok then note("Worker error: "..tostring(err))end
  end
  task.wait(.05)
 end
end)
if startup.gui then startup.gui:Destroy()end
note("Ready • configure selections, then enable Master")
end
local ok,err=pcall(run)
if not ok then
    warn("EXIS Steal an Egg startup: "..tostring(err))
    if startup.label and startup.label.Parent then startup.label.Text="EXIS STARTUP FAILED\n"..tostring(err).."\nCopy this error for diagnostics." end
    return false, tostring(err)
end
return true
