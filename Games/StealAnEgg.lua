-- EXIS | Steal an Egg. Native client APIs from the supplied November 2026 export.
-- Core is separately executable for deterministic tests; Roblox runtime starts below.
local Core={}
function Core.allowed(record,options,assets)
    local info=assets[record.AssetCategory]
    if not info or options.excluded[record.AreaId] or options.excludedPets[record.AssetCategory] then return false end
    local rarity=info.Rarity and info.Rarity._id
    if options.rarities[rarity]==false then return false end
    return record.State=="Slot" or record.State=="Dropped" or record.State=="GuardCarried"
end
function Core.choose(records,options,assets,position,blocked,now)
    local best,rank,distance
    for _,r in pairs(records) do
        if Core.allowed(r,options,assets) and r.BottomCFrame and not (blocked[r.Uid] and blocked[r.Uid]>now) then
            local tier=assets[r.AssetCategory].Rarity
            local score=tonumber(tier and tier.Rank) or 0
            local d=(r.BottomCFrame.Position-position).Magnitude
            if not best or score>rank or score==rank and d<distance then best,rank,distance=r,score,d end
        end
    end
    return best
end
function Core.firstSlot(record)
    if record.Uid:sub(1,13)=="FirstAreaEgg_" then return record.AreaId..":"..record.NestId end
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

local function run()
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local Pathfinding=game:GetService("PathfindingService")
local HTTP=game:GetService("HttpService")
local player=Players.LocalPlayer
local alive=true
local connections={}
local options={master=false,steal=false,hatch=false,equip=false,treadmill=false,events=false,
    upgrades=false,rewards=false,fusion=false,LightVsDarkness=true,SammyEvent=true,excluded={},excludedPets={},rarities={},trainingSeconds=20}
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
    local module=resolve(path)
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
local function walk(goal,carryUid)
    local r,h,c=character();if not r then return false end
    local last=r.Position;local progress=os.clock();local deadline=os.clock()+90
    while active() and player.Character==c and os.clock()<deadline do
        if carryUid and (not carrying().IsCarrying or carrying().Uid~=carryUid)then return false end
        if (r.Position-goal).Magnitude<5 then return true end
        local path=Pathfinding:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=5})
        local ok=pcall(function()path:ComputeAsync(r.Position,goal)end)
        if not ok or path.Status~=Enum.PathStatus.Success then note("No walking route; retrying without teleporting carried egg")return false end
        for _,point in ipairs(path:GetWaypoints())do
            if not active() or player.Character~=c then h:MoveTo(r.Position)return false end
            if carryUid and (not carrying().IsCarrying or carrying().Uid~=carryUid)then return false end
            if point.Action==Enum.PathWaypointAction.Jump then h.Jump=true end
            h:MoveTo(point.Position)
            local step=os.clock()+3
            repeat
                if not active()then h:MoveTo(r.Position)return false end
                if carryUid and not carrying().IsCarrying then return false end
                if (r.Position-last).Magnitude>1.5 then last=r.Position;progress=os.clock()end
                if os.clock()-progress>7 then h:MoveTo(r.Position)note("Walking stalled; route will be recalculated")return false end
                task.wait(.05)
            until (r.Position-point.Position).Magnitude<3 or os.clock()>step
            if (r.Position-point.Position).Magnitude>=3 then break end
        end
    end
    return false
end
connections[#connections+1]=api.remotes.Treadmill.AssignedBeltShifted.OnClientEvent:Connect(function(id)
    state.belt=id
    if id==nil then state.training=false end
end)
connections[#connections+1]=player.CharacterRemoving:Connect(function()
    state.training=false
    state.hatchPending={}
end)
local function stopTraining()
    if not state.training then return true end
    local ok=rpc("Treadmill","AskDoff")
    if ok==true then state.training=false return true end
    note("Treadmill exit unconfirmed; movement waits")return false
end
local function returnEgg()
    local carry=carrying();if not carry.IsCarrying then return false end
    if not stopTraining()then return false end
    local base=plot();if not base then note("Waiting for own base to stream")return false end
    state.job="return egg"
    if carry.RunBackWakeDelayRequired and not carry.GuardDisabled then
        local world=workspace:FindFirstChild("World")
        local guards=world and world:FindFirstChild("Areas")
        guards=guards and guards:FindFirstChild("GuardAreas")
        local area=guards and guards:FindFirstChild(carry.AreaId or "")
        local guard=area and area:FindFirstChild("Guard")
        if not guard or not await(function()return not carrying().IsCarrying or guard:GetAttribute("GuardState")=="Chasing"end,8)then
            note("Waiting for native guardian wake state")return false
        end
    end
    local before=api.eggs.ReadOwnerEggs(player.UserId)
    walk(base.PetArea.Position+Vector3.new(0,3,0),carry.Uid)
    if await(function()return not carrying().IsCarrying end,3)then
        local owned=api.eggs.ReadOwnerEggs(player.UserId)
        if owned[carry.Uid] or Core.count(owned)>Core.count(before)then
            state.claimed=state.claimed+1;note("Egg redeemed at own base")return true
        end
        note("Carry ended without ownership receipt; egg may have been lost")
    end
    return false
end
local function stealEgg()
    if pending.carry then note("Previous carry request awaiting reconciliation")return false end
    local r,h=character();if not r then return false end
    local owned=api.eggs.ReadOwnerEggs(player.UserId)
    if Core.count(owned)>=115 then note("Egg inventory full; hatch before stealing")return false end
    local records=api.eggs.ReadFieldEggs().Records
    local egg=Core.choose(records,options,api.assets.Directory,r.Position,blocked,os.clock())
    if not egg then return false end
    if not stopTraining()then return false end
    -- Only approach is teleported. Carried return movement never changes CFrame.
    if workspace.StreamingEnabled then pcall(function()player:RequestStreamAroundAsync(egg.BottomCFrame.Position,2)end)end
    r.CFrame=egg.BottomCFrame+Vector3.new(3,3,0)
    if not pause(.2)then return false end
    local live=api.eggs.ReadFieldEgg(egg.Uid)
    if not live or not Core.allowed(live,options,api.assets.Directory)then return false end
    if (r.Position-live.BottomCFrame.Position).Magnitude>8 then return false end
    h:UnequipTools()
    -- Same minimum as CarryAreaEgg; use the native method exactly once afterward.
    if not pause(workspace:GetAttribute("FastEggPickupTime") and .25 or 1.2)then return false end
    local ok,message=call("carry",api.eggs.CarryFieldEgg,egg.Uid,Core.firstSlot(egg))
    if ok~=true then blocked[egg.Uid]=os.clock()+8;note("Steal rejected: "..tostring(message))return false end
    if not await(function()local c=carrying()return c.IsCarrying and c.Uid==egg.Uid end,3)then
        blocked[egg.Uid]=os.clock()+8;note("Carry receipt missing; reconciling before retry")return false
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
                fireproximityprompt(nearestPrompt,nearestPrompt.HoldDuration)
                if await(function()return api.eggs.ReadOwnedEgg(player.UserId,uid)==nil end,15)then
                    state.hatches=state.hatches+1;note("Native hatch completed")return true
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
  if type(v)=="boolean"and type(options[k])=="boolean"then options[k]=v
  elseif (k=="excluded"or k=="excludedPets"or k=="rarities")and type(v)=="table"then
   for id,on in pairs(v)do if type(id)=="string"and type(on)=="boolean"then options[k][id]=on end end
  end
 end
 options.master=false -- Starting a new session always exposes settings before moving.
end)end
local renders={}
local function toggle(container,key,text,map)
 local target=map or options
 local button=make("TextButton",{Size=UDim2.new(1,-5,0,24),Text="",TextSize=10,Font=Enum.Font.BuilderSans,
  TextColor3=white,BackgroundColor3=Color3.fromRGB(20,29,41),BorderSizePixel=0,TextXAlignment=Enum.TextXAlignment.Left},container)
 corner(button,5)
 local function render()button.Text="  "..(target[key]and"●  "or"○  ")..text:upper();button.TextColor3=target[key]and blue or white end
 render();renders[button]=render
 button.Destroying:Connect(function()renders[button]=nil end)
 button.Activated:Connect(function()target[key]=not target[key];render();save()end)
 return button
end
local function button(container,text,fn)
 local b=make("TextButton",{Size=UDim2.new(1,-5,0,25),Text=text,TextSize=10,Font=Enum.Font.BuilderSans,
  TextColor3=blue,BackgroundColor3=Color3.fromRGB(20,29,41),BorderSizePixel=0},container)
 corner(b,5);b.Activated:Connect(fn);return b
end
local names={"Main","Eggs","Biomes","Rarities","Pets","Base","Training","Events","Fusion","Settings"}
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
ui.text(eggs,"Highest native rarity rank first, nearest for ties. Exclusions also apply to event eggs in the field snapshot.")
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
ui.text(training,"Uses own TreadmillBottom and AskWearStill. Leaves the belt before egg, hatch or event movement. Training sessions last 20 seconds.")
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
 for _,connection in ipairs(connections)do connection:Disconnect()end
 local r,h=character();if r then h:MoveTo(r.Position)end
 task.spawn(stopTraining)
end)
selectPage("Main")
local function periodic(key,seconds,fn)
 if os.clock()<(cooldown[key]or 0)then return false end
 cooldown[key]=os.clock()+seconds
 local ok,result=pcall(fn)
 if not ok then note(key..": "..tostring(result))return false end
 return result==true
end
-- A single worker owns movement and requests. Carrying always finishes first.
task.spawn(function()
 while alive do
  if not active()then
   if state.training then periodic("stop training",3,stopTraining)end
  else
   local ok,err=pcall(function()
    if carrying().IsCarrying then returnEgg();return end
    if state.wantHome then state.wantHome=nil;local b=plot()if b and stopTraining()then walk(b.PetArea.Position+Vector3.new(0,3,0))end;return end
    if state.training and os.clock()<state.trainUntil and options.treadmill then return end
    if state.training and not stopTraining()then return end
    if not api.eggs.HasFieldSnapshot()then periodic("sync",10,function()call("field sync",api.eggs.SyncFieldEggs)return true end)end
    if options.hatch and periodic("hatch",2,plantOrHatch)then return end
    if options.equip then periodic("equip",15,equipBest)end
    if options.upgrades then periodic("upgrades",8,upgrades)end
    if options.rewards then periodic("index",30,function()return rpc("Codex","AskRedeemAll")==true end)end
    if options.fusion then periodic("fusion",15,fuse)end
    if options.events and periodic("events",12,eventCollect)then return end
    if options.steal and periodic("steal",1,stealEgg)then return end
    if options.treadmill then periodic("training",3,train)end
   end)
   if not ok then note("Worker error: "..tostring(err))end
  end
  task.wait(.15)
 end
end)
note("Ready • configure selections, then enable Master")
end
local ok,err=pcall(run)
if not ok then warn("EXIS Steal an Egg startup: "..tostring(err))end
