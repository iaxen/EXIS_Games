-- EXI: exported client APIs and live NPC options; Roblox runtime testing required.
-- AFK updates: confirmed buff cooldowns, persistent desired toggles, quests/orders/mayor, selective dig and crop arrangement.
-- Shop choices follow GameHUD: NpcChoose(keeperId, offeredOptionId).
local SEED_PREFIX = "seeds#"
local PURCHASE_DELAY = 0.25
local BED_DELAY = 0.1 -- Seconds; adjustable live from the Main tab.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local parent = player:WaitForChild("PlayerGui")
local old = parent:FindFirstChild("EXIPanel") or parent:FindFirstChild("FarmPanel")
if old then old:Destroy() end
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
    Text="EXIScript | FUZZOPIA",TextColor3=blue,Font=Enum.Font.BuilderSansBold,
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
local states={}
local sessionOptions={}
local configChanged=function() end
local alive=true
local jobs={}
local renderToggle={}
local Remotes=game:GetService("ReplicatedStorage"):WaitForChild("CozyVillageRemotes",10)
assert(Remotes,"CozyVillageRemotes was not found in this experience")
local status=make("TextLabel",{Position=UDim2.new(0,91,1,-22),
    Size=UDim2.new(1,-119,0,19),BackgroundTransparency=1,
    Text="Idle • all automation is OFF",TextColor3=Color3.fromRGB(156,175,198),TextSize=10,
    Font=Enum.Font.BuilderSans,TextTruncate=Enum.TextTruncate.AtEnd,
    TextXAlignment=Enum.TextXAlignment.Left},body)
local function report(message)
    if alive then status.Text=message end
end
local function invoke(name,...)
    local remote=Remotes:FindFirstChild(name)
    assert(remote and remote:IsA("RemoteFunction"),name.." RemoteFunction missing")
    return remote:InvokeServer(...)
end
local function fire(name,...)
    local Event=Remotes:FindFirstChild(name)
    assert(Event and Event:IsA("RemoteEvent"),name.." RemoteEvent missing")
    Event:FireServer(...)
end
local function seedChoice(choice)
    return invoke("NpcChoose","SeedKeeper",choice)
end
local function enabled(key)
    return alive and states[key]
end
local shopping=false
local fairyBusy=false
local fairyCleanup=function() end
local activityCleanup=function() end
local chopBusy=false
local stopWalking=function() end
local findFairy
local movement={owner=nil,waiting={},rank={houseLayout=0.25,buyer=0,seeds=0,normalSeeds=0,harvest=1,plant=1.25,dust=1.5,sellBoom=0.75,fairy=-1,candyFairy=2.5,tend=4,gardenUpgrade=4,houseUpgrade=4,water=1.6,orders=0.5,mayor=2,quest=3,dig=1.1,rearrange=1.2,pickups=5,wood=6,fishing=7}}
movement.ready=function() return true end
function movement.active(key)
    if key=="buyer" then return alive and (states.seeds or states.normalSeeds or states.gears) end
    return alive and states[key]
end
function movement.release(key)
    movement.waiting[key]=nil
    if movement.owner==key then
        movement.owner=nil
        shopping=false
        chopBusy=false
        fairyBusy=false
    end
end
function movement.acquire(key)
    movement.waiting[key]=movement.waiting[key] or os.clock()
    while movement.active(key) do
        local first=nil
        local score=math.huge
        for candidate,since in pairs(movement.waiting) do
            if movement.active(candidate) and movement.ready(candidate) then
                local rank=movement.rank[candidate] or 8
                if rank<score or (rank==score and (not first or since<movement.waiting[first])) then
                    first,score=candidate,rank
                end
            elseif not movement.active(candidate) then movement.waiting[candidate]=nil end
        end
        if not movement.owner and first==key then
            movement.waiting[key]=nil
            movement.owner=key
            shopping=key~="wood" and key~="harvest"
            chopBusy=key=="wood" or key=="harvest"
            fairyBusy=key=="fairy" or (key~="buyer" and key~="wood" and key~="harvest")
            return true
        end
        task.wait(0.05)
    end
    movement.waiting[key]=nil
    return false
end
local function stop(key)
    local owned=movement.owner==key
    states[key]=false
    if key=="houseLayout" and sessionOptions.houseCleanup then sessionOptions.houseCleanup() end
    if key=="autoExecute" and alive and sessionOptions.sync then sessionOptions.sync() end
    if key=="autoReconnect" and sessionOptions.reconnect then sessionOptions.reconnect.pending=false end
    if key=="fairy" and owned then fairyCleanup() end
    if owned and (key=="pickups" or key=="fishing" or key=="sellBoom" or key=="houseUpgrade" or key=="gardenUpgrade" or key=="candyFairy") then activityCleanup(key) end
    if key=="wood" and owned then stopWalking() end
    local job=jobs[key]
    jobs[key]=nil
    if job and coroutine.status(job)~="dead" then task.cancel(job) end
    movement.release(key)
    if renderToggle[key] then renderToggle[key]() end
end
local itemIds={"LuckyCharm","RainbowDew"}
local itemLabels={}
local cooldown=600
local function deadline(item)
    return parent:GetAttribute("EXINext_"..item) or parent:GetAttribute("HardineroNext_"..item) or 0
end
local ownedBeds
local buffs={busy={},retry={},pending={}}
function buffs.reconcile(item)
    local pending=buffs.pending[item]
    if not pending then return end
    local now=workspace:GetServerTimeNow()
    local inventory=player:FindFirstChild("Inventory")
    local stock=inventory and inventory:FindFirstChild(item)
    if stock and (stock:IsA("IntValue") or stock:IsA("NumberValue")) and stock.Value<pending.before then
        parent:SetAttribute("EXINext_"..item,math.max(deadline(item),pending.at+cooldown))
        buffs.pending[item]=nil buffs.busy[item]=nil
        configChanged()
    elseif now-pending.at>=2.5 then
        buffs.pending[item]=nil buffs.busy[item]=nil
        buffs.retry[item]=now+2
    end
end
function buffs.harvestReady()
    if not states.harvest or movement.owner~="harvest" then return false end
    local beds=ownedBeds and ownedBeds()
    local target=buffs.target
    return beds~=nil and target~=nil and target.Parent==beds
        and target:FindFirstChild("RipeSparkle")~=nil
        and buffs.atFarm~=nil and buffs.atFarm()
end
function buffs.available(item)
    local now=workspace:GetServerTimeNow()
    if not enabled(item) or not buffs.harvestReady() or buffs.busy[item] or now<deadline(item) or now<(buffs.retry[item] or 0) then return false end
    local inventory=player:FindFirstChild("Inventory")
    local stock=inventory and inventory:FindFirstChild(item)
    return stock~=nil and (stock:IsA("IntValue") or stock:IsA("NumberValue")) and stock.Value>0
end
function buffs.use(item)
    buffs.reconcile(item)
    if not enabled(item) or not buffs.harvestReady() then return end
    local now=workspace:GetServerTimeNow()
    if buffs.busy[item] or now<deadline(item) or now<(buffs.retry[item] or 0) then return end
    local inventory=player:FindFirstChild("Inventory")
    local stock=inventory and inventory:FindFirstChild(item)
    if not stock or not (stock:IsA("IntValue") or stock:IsA("NumberValue")) or stock.Value<=0 then return end
    buffs.busy[item]=true
    local before=stock.Value
    buffs.pending[item]={before=before,at=now}
    local ok,err=pcall(function()
        fire("UseItem",item)
        local start=os.clock()
        repeat task.wait(0.05)
        until not enabled(item) or stock.Value<before or os.clock()-start>=2
        if stock.Value<before then
            parent:SetAttribute("EXINext_"..item,workspace:GetServerTimeNow()+cooldown)
            configChanged()
            report(item.." consumption confirmed; 10 minute timer started")
        else
            buffs.retry[item]=workspace:GetServerTimeNow()+10
            report(item.." use unconfirmed; retry in 10 seconds")
        end
    end)
    buffs.busy[item]=nil
    buffs.pending[item]=nil
    if not ok then buffs.retry[item]=now+10 report(item..": "..tostring(err)) end
end
function buffs.beforeTap(bed)
    if buffs.checked or not bed or not bed:FindFirstChild("RipeSparkle") then return end
    buffs.target=bed
    for _,item in ipairs(itemIds) do buffs.use(item) end
    buffs.checked=true
    buffs.target=nil
end
local function startItem(item)
    if not states[item] then stop(item) return end
    if jobs[item] then return end
    jobs[item]=task.defer(function()
        -- Actual item use belongs to the harvest turn, before its first tap.
        while enabled(item) do task.wait(1) end
        jobs[item]=nil
    end)
end
local tendLabel=nil
local animalCare={needed=0}
local function animalsNeedingCare()
    local village=workspace:FindFirstChild("CozyVillage")
    local animals=village and village:FindFirstChild("RanchAnimals")
    local needs={}
    if animals then
        for _,animal in ipairs(animals:GetChildren()) do
            if animal:GetAttribute("OwnerUserId")==player.UserId then
                local root=animal:FindFirstChild("Root")
                local prompt=root and root:FindFirstChild("CarePrompt")
                if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled
                    and not prompt.ActionText:lower():find("busy",1,true) then
                    needs[#needs+1]=animal.Name.."|"..prompt.ActionText.."|"..prompt.ObjectText
                end
            end
        end
    end
    table.sort(needs)
    animalCare.needed=#needs
    return #needs,table.concat(needs,";")
end
local function startTend()
    if not states.tend then stop("tend") return end
    if jobs.tend then return end
    jobs.tend=task.defer(function()
        local lastSignature=nil
        local lastRequest=0
        while enabled("tend") do
            local count,signature=animalsNeedingCare()
            if count>0 and (signature~=lastSignature or os.clock()-lastRequest>=5) then
                if not movement.acquire("tend") then break end
                count,signature=animalsNeedingCare()
                if count>0 then
                    local ok,sent,currentCount,currentSignature=pcall(animalCare.perform,"tend")
                    if not ok then
                        movement.release("tend")
                        report("Tend error: "..tostring(sent))
                        break
                    end
                    lastRequest=os.clock()
                    lastSignature=signature
                    if sent then
                        lastSignature=currentSignature
                        report("Tending requested for "..currentCount.." animals at your farm")
                    else report("Tending waiting for your farm or animals needing care") end
                end
                movement.release("tend")
            elseif count==0 then lastSignature=nil end
            task.wait(0.5)
        end
        movement.release("tend")
        jobs.tend=nil
    end)
end
local returnMode="Bed_6_5"
local ripeReturnPending=false
local function bedReturnPosition()
    local beds=ownedBeds and ownedBeds()
    local bed=beds and beds:FindFirstChild("Bed_6_5")
    if not bed then return end
    if bed:IsA("BasePart") then return bed.CFrame*CFrame.new(0,bed.Size.Y/2+3,0) end
    if bed:IsA("Model") then return bed:GetPivot()*CFrame.new(0,3,0) end
end
local savedCenter=nil
local pendingReturn=nil
local function currentPosition()
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    return root and root.CFrame
end
-- Count the whole owned bed grid, including narrow paths between beds.
local function atOwnBeds(position)
    local beds=ownedBeds and ownedBeds()
    if not beds then return false end
    for _,bed in ipairs(beds:GetChildren()) do
        if bed.Name:match("^Bed_%d+_%d+$") and (bed:IsA("BasePart") or bed:IsA("Model")) then
            local cf,size
            if bed:IsA("BasePart") then cf,size=bed.CFrame,bed.Size
            else cf,size=bed:GetBoundingBox() end
            local offset=cf:PointToObjectSpace(position)
            if math.abs(offset.X)<=size.X/2+3 and math.abs(offset.Z)<=size.Z/2+3
                and math.abs(offset.Y)<=size.Y/2+12 then return true end
        end
    end
    return false
end
function animalCare.goHome(key)
    if not enabled(key) or movement.owner~=key then return false end
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    if not atOwnBeds(root.Position) then
        local target=bedReturnPosition()
        if not target then return false end
        root.CFrame=target
        task.wait(0.2)
    end
    return enabled(key) and movement.owner==key and root.Parent~=nil and atOwnBeds(root.Position)
end
function animalCare.perform(key)
    if not animalCare.goHome(key) then return false end
    local count,signature=animalsNeedingCare()
    if count==0 or not enabled(key) or movement.owner~=key then return false end
    fire("FarmAction","tend")
    return true,count,signature
end
buffs.atFarm=function()
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    return root~=nil and atOwnBeds(root.Position)
end
local function tryRipeReturn()
    if movement.owner~="harvest" or not (alive and states.harvest and states.ripeReturn and ripeReturnPending) then return false end
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    if atOwnBeds(root.Position) then
        ripeReturnPending=false
        return true
    end
    local target=bedReturnPosition()
    if not target then return false end
    root.CFrame=target
    ripeReturnPending=false
    report("Ripe crops detected • returned to Bed_6_5")
    return true
end
local function returnToPosition()
    local target=pendingReturn
    pendingReturn=nil
    if not states.returnAfterBuy then return end
    if returnMode=="Bed_6_5" then target=bedReturnPosition() or target end
    if tryRipeReturn() then return end
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if target and root and not atOwnBeds(root.Position)
        and (root.Position-target.Position).Magnitude>2 then root.CFrame=target end
end
local function stopAll()
    if sessionOptions.stopEmote then sessionOptions.stopEmote() end
    if jobs.seedCheck then task.cancel(jobs.seedCheck) jobs.seedCheck=nil end
    for _,key in ipairs({"houseLayout","quest","orders","mayor","dig","rearrange","seeds","normalSeeds","gears","harvest","plant","dust","LuckyCharm","RainbowDew","wood","tend","water","ripeReturn","returnAfterBuy","fairy","candyFairy","antiAfk","leaveOnJoin","autoExecute","autoReconnect","pickups","fishing","sellBoom","houseUpgrade","gardenUpgrade"}) do stop(key) end
    local buyer=jobs.buyer
    jobs.buyer=nil
    if buyer and coroutine.status(buyer)~="dead" then task.cancel(buyer) end
    movement.release("buyer")
    shopping=false
    returnToPosition()
    report("ALL AUTOMATION STOPPED")
    if alive then configChanged() end
end
local normalIds={}
local seedIds={"CrystalRose","Corn","Starfruit","FrostLily","CloudCotton","AuroraFern",
    "EmberBulb","CandyReed","StardustBush","PearlPod","Honeybell",
    "PeachTree","Lavender","Beanstalk","Sunbloom","WindbellTree",
    "PuddingGourd","PrismGourd","DreamPlumTree","PhoenixBloom","CometSquash",
    "OpalOrchid","StarlightTree","FuzzberryTree","RainbowFruitTree",
    "MoonMelon","Lotus","AvocadoTree","Moonflower","Watermelon"}
local gearIds={"WateringBucket","GrowthTonic","LuckyCharm","RainbowDew"}
local function hasSelection(ids,prefix)
    for _,id in ipairs(ids) do if states[prefix..id] then return true end end
    return false
end
-- Harvest has its own worker; one buyer visits both shops sequentially.
local gearDiagnostics={log={},reply=nil,statusLabel=nil,replyLabel=nil}
local shopStatus=nil
local function shopReport(message)
    report(message)
    if shopStatus then shopStatus.Text=message end
    gearDiagnostics.log[#gearDiagnostics.log+1]=message
    if #gearDiagnostics.log>15 then table.remove(gearDiagnostics.log,1) end
    if gearDiagnostics.statusLabel then gearDiagnostics.statusLabel.Text=table.concat(gearDiagnostics.log,"\n") end
end
local function checkedInvoke(name,...)
    local result=invoke(name,...)
    assert(result~=false,name.." was rejected by server")
    return result
end
local HttpService=game:GetService("HttpService")
local shopReplyLabel=nil
local seedDiagnostics={active=nil,labels={},replies={},logs={seeds={},normalSeeds={}}}

local function showShopReply(keeper,reply)
    local ok,encoded=pcall(function() return HttpService:JSONEncode(reply) end)
    local message=keeper.." reply: "..(ok and encoded or tostring(reply))
    if keeper:find("GearKeeper",1,true) then
        gearDiagnostics.reply=message
        if gearDiagnostics.replyLabel then gearDiagnostics.replyLabel.Text=message end
    elseif shopReplyLabel then shopReplyLabel.Text=message:sub(1,1800) end
    if keeper:find("SeedKeeper",1,true) and seedDiagnostics.active then
        local key=seedDiagnostics.active
        seedDiagnostics.replies[key]=message
        if seedDiagnostics.labels[key] then seedDiagnostics.labels[key].Text=message end
    end
    print("EXI "..message)
end
local function keeperPrompt(keeper)
    for _,prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled and prompt:GetAttribute("NpcId")==keeper then
            return prompt
        end
    end
end
local function approachKeeper(key,keeper,targetPrompt)
    if not enabled(key) then return false end
    local prompt=targetPrompt or keeperPrompt(keeper)
    assert(prompt,"No active interaction prompt for "..keeper)
    local part=prompt:FindFirstAncestorWhichIsA("BasePart")
    local model=prompt:FindFirstAncestorWhichIsA("Model")
    local position=part and part.Position or (model and model:GetPivot().Position)
    assert(position,"NPC interaction position unavailable")
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    local humanoid=c and c:FindFirstChildOfClass("Humanoid")
    assert(root and humanoid,"Character unavailable")
    local direction=Vector3.new(root.Position.X-position.X,0,root.Position.Z-position.Z)
    direction=direction.Magnitude>0.1 and direction.Unit or Vector3.new(0,0,1)
    local destination=position+direction*2.5
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={c,model or part}
    local ground=workspace:Raycast(destination+Vector3.new(0,12,0),Vector3.new(0,-60,0),params)
    if ground then destination=Vector3.new(destination.X,ground.Position.Y+humanoid.HipHeight+root.Size.Y/2,destination.Z) end
    shopReport("Teleporting beside "..keeper)
    root.CFrame=CFrame.lookAt(destination,Vector3.new(position.X,destination.Y,position.Z))
    task.wait(0.35)
    if not enabled(key) then return false end
    assert((root.Position-position).Magnitude<=prompt.MaxActivationDistance,"NPC teleport was rejected or is outside interaction range")
    -- Invoke the menu directly after reaching the exact selected prompt.
    return enabled(key)
end
local function yieldShopForFarm(key,keeper)
    return enabled(key)
end
local function extractStock(reply)
    -- Only accept an explicit stock map; never infer quantities from prices or inventory.
    if type(reply)~="table" then return end
    local stock=reply.stock or reply.Stock
    if type(stock)=="table" then return stock end
    local parsed={}
    local found=false
    for _,option in ipairs(reply.Options or {}) do
        if type(option.Id)=="string" and type(option.Text)=="string" then
            local remaining=option.Text:match("%((%d+) left%)")
            if remaining then
                parsed[option.Id]=tonumber(remaining)
                found=true
            end
        end
    end
    if found then return parsed end
end
local function stockCount(stock,id)
    if not stock then return end
    local entry=stock[id] or stock["stock_"..id] or stock[SEED_PREFIX..id]
        or stock["seeds#"..id] or stock["seeds_"..id] or stock["seed_"..id] or stock["seed#"..id]
    local value=entry
    if type(entry)=="table" then value=entry.remaining or entry.stock or entry.Stock end
    if type(value)=="number" and value==value and value>=0 and value<math.huge then
        return math.floor(value)
    end
end
local stockConfig=nil
local function getStockConfig()
    if stockConfig then return stockConfig end
    local shared=game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
    local module=shared and shared:FindFirstChild("StockConfig")
    assert(module and module:IsA("ModuleScript"),"Shared.StockConfig module unavailable")
    local config=require(module)
    assert(type(config)=="table" and type(config.Lineup)=="function"
        and type(config.Window)=="function","StockConfig has an unexpected format")
    stockConfig=config
    return config
end
local function stockWindow()
    local config=getStockConfig()
    return config.Window(math.floor(workspace:GetServerTimeNow()))
end
local function requestKey(kind,id)
    return "EXIStockV4_"..kind.."_"..id
end
local function requestsThisWindow(kind,id,window)
    local key=requestKey(kind,id)
    if parent:GetAttribute(key.."_Window")~=window then return 0 end
    return parent:GetAttribute(key.."_Count") or 0
end
local function recordRequest(kind,id,window)
    local key=requestKey(kind,id)
    local count=requestsThisWindow(kind,id,window)
    parent:SetAttribute(key.."_Window",window)
    parent:SetAttribute(key.."_Count",count+1)
end
local function calculatedStock(kind,ids,window)
    local lineup=getStockConfig().Lineup(kind,window)
    local remaining={}
    for _,id in ipairs(ids) do
        remaining[id]=math.max(0,(lineup[id] or 0)-requestsThisWindow(kind,id,window))
    end
    return remaining
end
local seedStatus={}
local function seedReport(key,message)
    report(message)
    local log=seedDiagnostics.logs[key]
    log[#log+1]=os.date("%H:%M:%S").."  "..message
    if #log>12 then table.remove(log,1) end
    if seedStatus[key] then seedStatus[key].Text=table.concat(log,"\n") end
    print("EXI seeds: "..message)
end
local function seedInventoryCount(id)
    local inventory=player:FindFirstChild("Inventory")
    local config=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    local crop=config.Crops[id]
    local item=inventory and crop and inventory:FindFirstChild(crop.SeedItemId)
    if not item then return 0 end
    if item:IsA("IntValue") or item:IsA("NumberValue") then return item.Value end
    return nil
end
local function purchaseSeeds(key)
    seedDiagnostics.active=key
    seedReport(key,"Starting "..(key=="seeds" and "Special" or "Normal").." Seeds visit")
    local ids=key=="seeds" and seedIds or normalIds
    local selection=key=="seeds" and "seed:" or "normal:"
    if not enabled(key) or not hasSelection(ids,selection) then return end
    if not approachKeeper(key,"SeedKeeper") then return end
    seedReport(key,"NpcOpen request: SeedKeeper")
    local menu=checkedInvoke("NpcOpen","SeedKeeper")
    assert(type(menu)=="table","SeedKeeper returned no dialogue")
    showShopReply("SeedKeeper",menu)
    local page=nil
    for _,option in ipairs(menu.Options or {}) do
        local text=tostring(option.Text or ""):lower()
        if key=="seeds" and (option.Id=="page_special" or text:find("special seeds",1,true)) then page=option.Id break end
        if key=="normalSeeds" and (option.Id=="page_normal" or text:find("normal seeds",1,true)) then page=option.Id break end
    end
    if key=="seeds" and not page then
        seedReport(key,"No Special Seeds choice returned. Open Settings > Shop diagnostics.")
        return
    end
    if page then
        seedReport(key,"Selecting page: "..tostring(page))
        menu=checkedInvoke("NpcChoose","SeedKeeper",page)
    end
    assert(type(menu)=="table" and type(menu.Options)=="table","Seed page returned no Options")
    local config=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    local matched={}
    local purchases=0
    local outcomes={}
    for sweep=1,10 do
        local beforeSweep=purchases
        local visited={}
        local seenThisSweep={}
        if sweep>1 then
            if not yieldShopForFarm(key,"SeedKeeper") then return end
            menu=checkedInvoke("NpcOpen","SeedKeeper")
            if page then menu=checkedInvoke("NpcChoose","SeedKeeper",page) end
            seedReport(key,"Rechecking remaining selected stock, pass "..sweep)
        end
    for pageNumber=1,40 do
        if not enabled(key) then return end
        showShopReply("SeedKeeper",menu)
        local signature={}
        for _,option in ipairs(menu.Options or {}) do signature[#signature+1]=tostring(option.Id) end
        local fingerprint=table.concat(signature,"|")
        seedReport(key,"Offered IDs: "..fingerprint)
        if visited[fingerprint] then break end
        visited[fingerprint]=true
        seedReport(key,"Reading seed page "..pageNumber.." ("..#(menu.Options or {}).." choices)")
        for _,id in ipairs(ids) do
            if not enabled(key) then return end
            if states[selection..id] and not seenThisSweep[id] then
                if not yieldShopForFarm(key,"SeedKeeper") then return end
                local crop=config.Crops[id]
                local chosen=nil
                local candidates={
                    ["seeds#"..id]=true,["seeds"..id]=true,["seeds_"..id]=true,
                    ["seed_"..id]=true,["seed#"..id]=true
                }
                for _,option in ipairs(menu.Options or {}) do
                    if candidates[option.Id] then chosen=option break end
                end
                if chosen then
                    matched[id]=true
                    seenThisSweep[id]=true
                    local label=tostring(chosen.Text or ""):lower()
                    local live=tonumber(chosen.Remaining or chosen.Stock)
                        or tonumber(label:match("(%d+)%s+left"))
                    local max=(getStockConfig().Seeds[id] or {}).Max or 1
                    local amount=live or max
                    if label:find("sold out",1,true) or label:find("out of stock",1,true) then amount=0 end
                    if amount==0 then outcomes[id]="sold out / zero stock" end
                    if crop and (crop.UnlockLevel or 1)>(tonumber(player:GetAttribute("FarmLevel")) or 1) then
                        seedReport(key,id.." requires Farm Lv "..crop.UnlockLevel)
                        amount=0
                        outcomes[id]="locked at Farm Lv "..crop.UnlockLevel
                    end
                    for attempt=1,math.min(amount,50) do
                        if not yieldShopForFarm(key,"SeedKeeper") then return end
                        if not enabled(key) or not states[selection..id] then return end
                        local before=seedInventoryCount(id)
                        seedReport(key,"Buying "..id.." via "..tostring(chosen.Id))
                        local result=invoke("NpcChoose","SeedKeeper",chosen.Id)
                        if result==false or result==nil then
                            outcomes[id]="server declined request"
                            seedReport(key,"Server declined "..id.."; result="..tostring(result))
                            showShopReply("SeedKeeper purchase",result)
                            break
                        end
                        local replyText=type(result)=="table" and tostring(result.Text or "") or tostring(result)
                        local started=os.clock()
                        repeat task.wait(0.05)
                        until not enabled(key) or seedInventoryCount(id)~=before or os.clock()-started>=3
                        local after=seedInventoryCount(id)
                        if before~=nil and after~=nil and after>before then
                            purchases=purchases+1
                            seedReport(key,"Confirmed "..id..": +"..(after-before).." seeds")
                            outcomes[id]="purchased; awaiting stock recheck"
                        else
                            outcomes[id]="not confirmed: "..replyText:sub(1,100)
                            seedReport(key,"No seed increase for "..id..". Reply: "..replyText:sub(1,180))
                            showShopReply("SeedKeeper purchase",result)
                            break
                        end
                        task.wait(PURCHASE_DELAY)
                    end
                end
            end
        end
        local nextPage=nil
        for _,option in ipairs(menu.Options or {}) do
            if type(option.Id)=="string" and tostring(option.Text or ""):lower():find("next page",1,true) then
                nextPage=option.Id
                break
            end
        end
        if not nextPage then break end
        seedReport(key,"Selecting next page: "..nextPage)
        menu=checkedInvoke("NpcChoose","SeedKeeper",nextPage)
        assert(type(menu)=="table","Next seed page returned no menu")
    end
        if purchases==beforeSweep then break end
        if sweep==10 then seedReport(key,"Stock recheck limit reached; inspect remaining quantities") end
    end
    local missing={}
    for _,id in ipairs(ids) do
        if states[selection..id] then
            if not matched[id] then missing[#missing+1]=id
            else seedReport(key,id..": "..(outcomes[id] or "checked")) end
        end
    end
    if #missing>0 then seedReport(key,"Not offered on scanned pages: "..table.concat(missing,", ")) end
    seedReport(key,"Seed visit finished: "..purchases.." purchases confirmed")
end
local restockLabel=nil
local function purchaseVisit(key)
    if key=="seeds" or key=="normalSeeds" then return purchaseSeeds(key) end
    if not enabled("gears") or not hasSelection(gearIds,"gear:") then return end
    if not approachKeeper("gears","GearKeeper") then return end
    local window=stockWindow()
    local total=0
    local outcomes={}
    local function itemCount(id)
        local inventory=player:FindFirstChild("Inventory")
        local item=inventory and inventory:FindFirstChild(id)
        return item and (item:IsA("IntValue") or item:IsA("NumberValue")) and item.Value or 0
    end
    for sweep=1,3 do
        if not enabled("gears") or stockWindow()~=window then break end
        local beforeSweep=total
        local menu=checkedInvoke("NpcOpen","GearKeeper")
        assert(type(menu)=="table","GearKeeper returned no shop menu")
        showShopReply("GearKeeper",menu)
        shopReport("Gear stock pass "..sweep)
        for _,id in ipairs(gearIds) do
            if not enabled("gears") or stockWindow()~=window then return end
            if states["gear:"..id] then
                local option=nil
                for _,candidate in ipairs(menu.Options or {}) do
                    if candidate.Id=="stock_"..id then option=candidate break end
                end
                if not option then
                    outcomes[id]="not offered"
                else
                    local text=tostring(option.Text or ""):lower()
                    local amount=tonumber(option.Remaining or option.Stock)
                        or tonumber(text:match("(%d+)%s+left"))
                    local stock=extractStock(menu)
                    amount=amount or stockCount(stock,id)
                    if text:find("sold out",1,true) or text:find("out of stock",1,true) then amount=0 end
                    amount=amount or (getStockConfig().Gear[id] or {}).Max or 1
                    if amount==0 then outcomes[id]="sold out / zero stock" end
                    for attempt=1,math.min(amount,50) do
                        if not enabled("gears") or not states["gear:"..id] then break end
                        if not yieldShopForFarm("gears","GearKeeper") then return end
                        local before=itemCount(id)
                        shopReport("Buying "..id.." "..attempt.."/"..amount)
                        local result=invoke("NpcChoose","GearKeeper",option.Id)
                        local started=os.clock()
                        repeat task.wait(0.05)
                        until not enabled("gears") or itemCount(id)>before or os.clock()-started>=3
                        local after=itemCount(id)
                        if after>before then
                            total=total+1
                            outcomes[id]="purchased; awaiting final stock check"
                            shopReport("Confirmed "..id..": +"..(after-before))
                        else
                            local text=type(result)=="table" and tostring(result.Text or "") or tostring(result)
                            outcomes[id]="not confirmed: "..text:sub(1,100)
                            shopReport(id..": "..outcomes[id])
                            showShopReply("GearKeeper purchase",result)
                            break
                        end
                        task.wait(PURCHASE_DELAY)
                    end
                end
            end
        end
        if total==beforeSweep then break end
    end
    for _,id in ipairs(gearIds) do
        if states["gear:"..id] then shopReport(id..": "..(outcomes[id] or "not checked")) end
    end
    shopReport("Gear visit finished: "..total.." purchases confirmed")
end
local function startBuyer()
    if jobs.buyer then return end
    jobs.buyer=task.defer(function()
        -- The game announces restocks when StockConfig.Window changes.
        -- Capture the current window so enabling a toggle never starts a shop trip immediately.
        local observedWindow=stockWindow()
        local retryAt=nil
        shopReport("Auto Buy enabled • waiting for the next restock")
        while alive and (states.seeds or states.normalSeeds or states.gears) do
            local window=stockWindow()
            if window==observedWindow and (not retryAt or os.clock()<retryAt) then
                task.wait(0.5)
            else
                observedWindow=window
                retryAt=nil
                if not movement.acquire("buyer") then break end
                local previous=currentPosition()
                if previous then
                    pendingReturn=(returnMode=="Bed center" and savedCenter) or previous
                    for _,key in ipairs({"normalSeeds","seeds","gears"}) do
                        if enabled(key) then
                            local ids=key=="seeds" and seedIds or (key=="normalSeeds" and normalIds or gearIds)
                            local prefix=key=="seeds" and "seed:" or (key=="normalSeeds" and "normal:" or "gear:")
                            if not hasSelection(ids,prefix) then
                                shopReport("No "..key.." selected; waiting")
                            else
                                local ok,err=pcall(purchaseVisit,key)
                                if not ok then
                                    retryAt=os.clock()+15
                                    shopReport("Shop error; retrying in 15 seconds: "..tostring(err))
                                    if key~="gears" then seedReport(key,"ERROR: "..tostring(err)) end
                                end
                            end
                        end
                    end
                    returnToPosition()
                else retryAt=os.clock()+15 shopReport("Character unavailable; retrying in 15 seconds") end
                movement.release("buyer")
            end
        end
        movement.release("buyer")
        jobs.buyer=nil
    end)
end
ownedBeds=function()
    local village=workspace:FindFirstChild("CozyVillage")
    local gardens=village and village:FindFirstChild("PlayerGardens")
    if gardens then
        for _,garden in ipairs(gardens:GetChildren()) do
            if garden:GetAttribute("OwnerUserId")==player.UserId then return garden:FindFirstChild("Beds") end
        end
    end
end
local function inventoryAmount(id)
    local inventory=player:FindFirstChild("Inventory")
    local item=inventory and inventory:FindFirstChild(id)
    if item and (item:IsA("IntValue") or item:IsA("NumberValue")) then return item.Value end
    return 0
end
local planting={order="normal",label=nil,orderButton=nil}
function planting.seed()
    local config=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    local candidates={}
    for index,id in ipairs(config.CropOrder) do
        local crop=config.Crops[id]
        if states["plant:"..id] and not (states.dig and states["dig:"..id]) and crop and inventoryAmount(crop.SeedItemId)>0 then
            candidates[#candidates+1]={id=id,index=index,cost=crop.PackCost or 0}
        end
    end
    if planting.order=="expensive" then
        table.sort(candidates,function(a,b)
            if a.cost~=b.cost then return a.cost>b.cost end
            return a.index<b.index
        end)
    end
    return candidates[1] and candidates[1].id
end
function planting.emptyBed()
    local beds=ownedBeds()
    if not beds then return end
    if states.rearrange then
        local empty=0
        for _,bed in ipairs(beds:GetChildren()) do if not bed:FindFirstChild("CropVisual") then empty=empty+1 end end
        if empty<=1 then return end
    end
    for row=1,11 do
        for column=1,10 do
            local bed=beds:FindFirstChild(("Bed_%d_%d"):format(row,column))
            if bed and not bed:FindFirstChild("CropVisual") then return bed end
        end
    end
end
local function startPlant()
    if not states.plant then stop("plant") return end
    if jobs.plant then return end
    jobs.plant=task.defer(function()
        local tried=setmetatable({},{__mode="k"})
        local ok,err=pcall(function()
            while enabled("plant") do
                if not movement.acquire("plant") then break end
                local id=planting.seed()
                local bed=planting.emptyBed()
                if id and bed and os.clock()-(tried[bed] or -math.huge)>=5 then
                    local c=player.Character
                    local root=c and c:FindFirstChild("HumanoidRootPart")
                    if root and not atOwnBeds(root.Position) then
                        local target=bedReturnPosition()
                        if target then root.CFrame=target task.wait(0.2) end
                    end
                    fire("SelectSeed",id)
                    local started=os.clock()
                    repeat task.wait(0.05)
                    until not enabled("plant") or player:GetAttribute("SelectedSeed")==id or os.clock()-started>=2
                    if enabled("plant") and player:GetAttribute("SelectedSeed")==id and bed.Parent and not bed:FindFirstChild("CropVisual") then
                        tried[bed]=os.clock()
                        fire("FarmTap",bed.Name,nil)
                        local before=os.clock()
                        repeat task.wait(0.05)
                        until not enabled("plant") or not bed.Parent or bed:FindFirstChild("CropVisual") or os.clock()-before>=2
                        local message=bed:FindFirstChild("CropVisual") and ("Planted "..id.." in "..bed.Name) or ("Plant request unconfirmed for "..bed.Name)
                        report(message)
                        if planting.label then planting.label.Text=message end
                    end
                end
                movement.release("plant")
                task.wait(BED_DELAY)
            end
        end)
        movement.release("plant")
        if not ok then

            report("Plant error: "..tostring(err))
        end
        jobs.plant=nil
    end)
end
local function farmReadiness()
    local beds=ownedBeds()
    local ripe,growing=0,0
    if beds then
        for _,bed in ipairs(beds:GetChildren()) do
            if bed:FindFirstChild("RipeSparkle") then ripe=ripe+1 end
            if bed:FindFirstChild("CropVisual") then growing=growing+1 end
        end
    end
    return ripe,growing,inventoryAmount("FairyDust")
end
function movement.higherPending(key)
    -- An action is non-preemptive. Priority is evaluated only at acquisition.
    return false
end
local ripeMarkers=setmetatable({},{__mode="k"})
local ripeAttempts=setmetatable({},{__mode="k"})
local function startWater()
    if not states.water then stop("water") return end
    if jobs.water then return end
    jobs.water=task.defer(function()
        local sent=setmetatable({},{__mode="k"})
        local ok,err=pcall(function()
            while enabled("water") do
                if not movement.acquire("water") then break end
                local beds=ownedBeds()
                local c=player.Character
                local root=c and c:FindFirstChild("HumanoidRootPart")
                if beds and root then
                    if not atOwnBeds(root.Position) then
                        local target=bedReturnPosition()
                        if target then root.CFrame=target task.wait(0.2) end
                    end
                    for _,bed in ipairs(beds:GetChildren()) do
                        if not enabled("water") then break end
                        local marker=bed:FindFirstChild("NeedsWater")
                        if marker and sent[bed]~=marker and not bed:FindFirstChild("RipeSparkle") then
                            fire("FarmTap",bed.Name,nil)
                            sent[bed]=marker
                            task.wait(BED_DELAY)
                        elseif not marker then sent[bed]=nil end
                    end
                end
                movement.release("water")
                task.wait(1)
            end
        end)
        movement.release("water")
        if not ok then report("Water error: "..tostring(err)) end
        jobs.water=nil
    end)
end
local harvestProgress=nil
local dustStatus=nil
local bedCount=0
local dustRequests=0
local dustAwaitingRipening=false
local dustRequestTime=0
local dustCycle={stockBefore=0,retryDelay=1.5,reserve=20,spending=false}
function dustCycle.canSpend(count)
    local previous=dustCycle.spending
    if count<=0 then dustCycle.spending=false
    elseif states.dust and not dustCycle.spending and count>=dustCycle.reserve then dustCycle.spending=true end
    if previous~=dustCycle.spending then configChanged() end
    return states.dust and dustCycle.spending and count>0
end
function dustCycle.status()
    if not dustCycle.label then return end
    local count=inventoryAmount("FairyDust")
    local active=dustCycle.canSpend(count)
    dustCycle.label.Text=not states.dust and "FAIRY DUST: OFF" or
        (active and ("USING BATCH • STOCK: "..count) or ("REFILLING: "..count.." / "..dustCycle.reserve))
end
function dustCycle.ready(ripe,growing,count)
    if ripe>0 then dustAwaitingRipening=false end
    local stocked=dustCycle.canSpend(count)
    if not states.harvest or ripe~=0 or growing<=0 or not stocked then return false end
    if not dustAwaitingRipening then return true end
    -- Consumption without a ripe update is still pending: do not spend again.
    if count<dustCycle.stockBefore then return false end
    return workspace:GetServerTimeNow()-dustRequestTime>=dustCycle.retryDelay
end
function dustCycle.observe(object)
    if object.Name~="RipeSparkle" then return end
    local beds=ownedBeds()
    if beds and object:IsDescendantOf(beds) then dustAwaitingRipening=false end
end
local function requestDust()
    local before=inventoryAmount("FairyDust")
    local ok,err=pcall(fire,"UseItem","FairyDust")
    if ok then
        dustCycle.stockBefore=before
        dustRequests=dustRequests+1
        dustAwaitingRipening=true
        dustRequestTime=workspace:GetServerTimeNow()
        if dustStatus then dustStatus.Text="Fairy Dust requests: "..dustRequests.." • last request sent" end
    else
        if dustStatus then dustStatus.Text="Fairy Dust error: "..tostring(err) end
        warn("EXI Fairy Dust: "..tostring(err))
    end
    return ok,err
end
movement.ready=function(key)
    local ripe,growing,dust=farmReadiness()
    if ripe>0 then dustAwaitingRipening=false end
    if key=="LuckyCharm" or key=="RainbowDew" then return false end
    if key=="harvest" then return ripe>0 end
    if key=="water" then
        local beds=ownedBeds()
        if beds then for _,bed in ipairs(beds:GetChildren()) do
            if bed:FindFirstChild("NeedsWater") and not bed:FindFirstChild("RipeSparkle") then return true end
        end end
        return false
    end
    if key=="plant" then return planting.emptyBed()~=nil and planting.seed()~=nil end
    if key=="dust" then
        return dustCycle.ready(ripe,growing,dust)
    end
    if key=="wood" or key=="pickups" then
        if states.harvest then return ripe==0 and not dustCycle.canSpend(dust) end
    end
    return true
end
local function startDust()
    if not states.dust then stop("dust") return end
    if jobs.dust then return end
    jobs.dust=task.defer(function()
        while enabled("dust") do
            if not movement.acquire("dust") then break end
            local ripe,growing,count=farmReadiness()
            if dustCycle.ready(ripe,growing,count) then
                ripe,growing,count=farmReadiness()
                local used,err=true,nil
                if enabled("dust") and dustCycle.ready(ripe,growing,count) then used,err=requestDust() end
                if not used then

                    report("Fairy Dust error: "..tostring(err))
                end
            end
            movement.release("dust")
            task.wait(0.03)
        end
        movement.release("dust")
        jobs.dust=nil
    end)
end
local function runAutomation(key)
    if key~="harvest" then
        if states[key] then
            local ids=key=="seeds" and seedIds or (key=="normalSeeds" and normalIds or gearIds)
            local prefix=key=="seeds" and "seed:" or (key=="normalSeeds" and "normal:" or "gear:")
            if not hasSelection(ids,prefix) then
                report("Waiting for selected items in "..key)
            end
            startBuyer()
        end
        -- Let an active buyer finish returning when a shop toggle is disabled.
        return
    end
    if not states.harvest then stop("harvest") return end
    if jobs.harvest then return end
    jobs.harvest=task.defer(function()
        local ok,err=pcall(function()
            while enabled("harvest") do
                if not movement.acquire("harvest") then return end
                tryRipeReturn()
                local c=player.Character
                local root=c and c:FindFirstChild("HumanoidRootPart")
                if root and not atOwnBeds(root.Position) then
                    local target=bedReturnPosition()
                    if target then root.CFrame=target task.wait(0.2) end
                end
                buffs.checked=false
                buffs.target=nil
                bedCount=0
                for row=1,11 do
                    if movement.higherPending("harvest") then break end
                    for col=1,10 do
                        if movement.higherPending("harvest") then break end
                        if not enabled("harvest") then movement.release("harvest") return end
                        local bedId=("Bed_%d_%d"):format(row,col)
                        local requested=false
                        if states.ripeOnly then
                            local beds=ownedBeds()
                            local bed=beds and beds:FindFirstChild(bedId)
                            local marker=bed and bed:FindFirstChild("RipeSparkle")
                            if marker and (ripeMarkers[bed]~=marker or os.clock()-(ripeAttempts[bed] or 0)>=1) then
                                buffs.beforeTap(bed)
                                if not enabled("harvest") then movement.release("harvest") return end
                                fire("FarmTap",bedId,nil)
                                requested=true
                                ripeMarkers[bed]=marker
                                ripeAttempts[bed]=os.clock()
                            elseif bed and not marker then ripeMarkers[bed]=nil end
                        else
                            local beds=ownedBeds()
                            local bed=beds and beds:FindFirstChild(bedId)
                            buffs.beforeTap(bed)
                            if not enabled("harvest") then movement.release("harvest") return end
                            fire("FarmTap",bedId,nil) requested=true
                        end
                        bedCount=bedCount+1
                        if harvestProgress then harvestProgress.Text="Harvest round: "..bedCount.." / 110 beds checked" end
                        if requested then task.wait(BED_DELAY) end
                    end
                end

                movement.release("harvest")
                task.wait(0.1)
            end
        end)
        movement.release("harvest")
        if not ok then

            report("Harvest error: "..tostring(err))
        end
        jobs.harvest=nil
    end)
end
local treeNames={Tree_Apple=true,Tree_Blossom=true,Tree_Pine=true,Tree_Round=true}
local chopMode="Teleport"
local chopHits=1
local Pathfinding=game:GetService("PathfindingService")
local function characterParts()
    local c=player.Character
    return c and c:FindFirstChild("HumanoidRootPart"),c and c:FindFirstChildOfClass("Humanoid")
end
stopWalking=function()
    local root,humanoid=characterParts()
    if root and humanoid then humanoid:MoveTo(root.Position) end
end
local function treesFolder()
    local island=workspace:FindFirstChild("FuzzIsland")
    local nature=island and island:FindFirstChild("Nature")
    return nature and nature:FindFirstChild("Trees")
end
local function treePosition(tree)
    if tree:IsA("Model") then return tree:GetPivot().Position end
    if tree:IsA("BasePart") then return tree.Position end
end
local function besideTree(tree,root)
    local center=treePosition(tree)
    if not center then return end
    local direction=Vector3.new(root.Position.X-center.X,0,root.Position.Z-center.Z)
    direction=direction.Magnitude>0.1 and direction.Unit or Vector3.new(1,0,0)
    -- Aim near the trunk rather than five studs away from the tree pivot.
    local sample=center+direction*1.8
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={tree,player.Character}
    local ground=workspace:Raycast(sample+Vector3.new(0,40,0),Vector3.new(0,-160,0),params)
    if not ground then return end
    return ground.Position+Vector3.new(0,3,0),center
end
local function moveToTree(target,center)
    local root,humanoid=characterParts()
    if not root or not humanoid or humanoid.Health<=0 then return false end
    if chopMode=="Teleport" then
        root.CFrame=CFrame.lookAt(target,Vector3.new(center.X,target.Y,center.Z))
        task.wait(0.15)
        root=select(1,characterParts())
        return root and (Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(target.X,0,target.Z)).Magnitude<2
    end
    local path=Pathfinding:CreatePath({AgentCanJump=true,WaypointSpacing=3})
    path:ComputeAsync(root.Position,target)
    if path.Status~=Enum.PathStatus.Success then return false end
    local started=os.clock()
    for _,waypoint in ipairs(path:GetWaypoints()) do
        if not enabled("wood") or shopping or movement.higherPending("wood") then stopWalking() return false end
        if waypoint.Action==Enum.PathWaypointAction.Jump then humanoid.Jump=true end
        humanoid:MoveTo(waypoint.Position)
        local stepStart=os.clock()
        repeat
            task.wait(0.05)
            if not enabled("wood") or shopping or movement.higherPending("wood") or humanoid.Health<=0 then stopWalking() return false end
            if os.clock()-stepStart>4 or os.clock()-started>25 then stopWalking() return false end
        until (Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(waypoint.Position.X,0,waypoint.Position.Z)).Magnitude<2
    end
    -- Finish the approach precisely; path waypoints alone can stop short.
    humanoid:MoveTo(target-Vector3.new(0,3,0))
    local finalStart=os.clock()
    repeat
        if not enabled("wood") or shopping or movement.higherPending("wood") then stopWalking() return false end
        local distance=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(target.X,0,target.Z)).Magnitude
        if distance<=1.2 then
            root.CFrame=CFrame.lookAt(root.Position,Vector3.new(center.X,root.Position.Y,center.Z))
            return true
        end
        task.wait(0.05)
    until os.clock()-finalStart>2
    return false
end
local function startChop()
    if not states.wood then stop("wood") return end
    if jobs.wood then return end
    jobs.wood=task.defer(function()
        local attempted=setmetatable({},{__mode="k"})
        local ok,err=pcall(function()
            while enabled("wood") do
                if shopping then task.wait(0.2)
                else
                    local folder=treesFolder()
                    assert(folder,"Workspace.FuzzIsland.Nature.Trees was not found")
                    local root=select(1,characterParts())
                    local nearest,best=nil,math.huge
                    if root then
                        for _,tree in ipairs(folder:GetChildren()) do
                            if treeNames[tree.Name] and tree:GetAttribute("Choppable")==true
                                and not tree:GetAttribute("Felled") and states["tree:"..tree.Name]
                                and os.clock()-(attempted[tree] or -math.huge)>=30 then
                                local position=treePosition(tree)
                                local distance=position and (position-root.Position).Magnitude or math.huge
                                if distance<best then nearest,best=tree,distance end
                            end
                        end
                    end
                    if not nearest then task.wait(1)
                    else
                        if not movement.acquire("wood") then return end
                        root=select(1,characterParts())
                        if not root or nearest.Parent~=folder then movement.release("wood") return end
                        attempted[nearest]=os.clock()
                        local target,center=besideTree(nearest,root)
                        local arrived=target and moveToTree(target,center)
                        if arrived and not shopping then
                            for hit=1,chopHits do
                                if not enabled("wood") or shopping or movement.higherPending("wood") or nearest.Parent~=folder or nearest:GetAttribute("Felled") then break end
                                fire("Chop",nearest)
                                report("Chop requested: "..nearest.Name.." ("..hit..")")
                                task.wait(0.12)
                            end
                        end
                        movement.release("wood")
                        task.wait(0.05)
                    end
                end
            end
        end)
        movement.release("wood")
        stopWalking()
        if not ok then

            report("Chop error: "..tostring(err))
        end
        jobs.wood=nil
    end)
end
local fairyLabel=nil
local fairyOrigin=nil
local function fairyReport(message)
    report(message)
    if fairyLabel then fairyLabel.Text=message end
end
fairyCleanup=function()
    if movement.owner~="fairy" then return end
    stopWalking()
    local handled=tryRipeReturn()
    local target=fairyOrigin
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    if not handled and root and target and not atOwnBeds(root.Position) then root.CFrame=target end
    fairyOrigin=nil
    movement.release("fairy")
end
local fairyTargets={cachedAt=-math.huge,acorn={},candy={}}
function fairyTargets.position(object)
    if object:IsA("Attachment") then return object.WorldPosition end
    if object:IsA("BasePart") then return object.Position end
    if object:IsA("Model") then return object:GetPivot().Position end
end
function fairyTargets.scan()
    if os.clock()-fairyTargets.cachedAt<0.5 then return fairyTargets.acorn,fairyTargets.candy end
    local prompts,houses={},{}
    for _,object in ipairs(workspace:GetDescendants()) do
        if object:IsA("ProximityPrompt") and object.Enabled then
            local id=object:GetAttribute("NpcId")
            local model=object:FindFirstAncestorWhichIsA("Model")
            local clue=(tostring(id or "").." "..object.ObjectText.." "..(model and model.Name or "")):lower()
            if type(id)=="string" and (clue:find("fairy",1,true) or clue:find("twinkle",1,true)) then
                local holder=object.Parent
                local pos=holder and fairyTargets.position(holder)
                if not pos and model then pos=fairyTargets.position(model) end
                if pos then prompts[#prompts+1]={prompt=object,id=id,position=pos} end
            end
        elseif object:IsA("Model") or object:IsA("BasePart") then
            local name=object.Name:lower():gsub("[%s_]","")
            if name=="fairyhouse" or name=="mushroomhouse" then
                local pos=fairyTargets.position(object)
                if pos then houses[#houses+1]=pos end
            end
        end
    end
    local linked={}
    for _,house in ipairs(houses) do
        local nearest,distance=nil,24
        for _,entry in ipairs(prompts) do
            local d=(entry.position-house).Magnitude
            if d<distance then nearest,distance=entry.prompt,d end
        end
        if nearest then linked[nearest]=true end
    end
    local acorn,candy={},{}
    for _,entry in ipairs(prompts) do
        if linked[entry.prompt] then acorn[#acorn+1]=entry else candy[#candy+1]=entry.prompt end
    end
    fairyTargets.acorn,fairyTargets.candy,fairyTargets.cachedAt=acorn,candy,os.clock()
    return acorn,candy
end
findFairy=function()
    local targets=fairyTargets.scan()
    for _,entry in ipairs(targets) do
        if entry.prompt.Parent and entry.prompt.Enabled then return entry.prompt,entry.id end
    end
end
local function acorns()
    local inventory=player:FindFirstChild("Inventory")
    if not inventory then return nil end
    local value=inventory:FindFirstChild("GoldenAcorn")
    if not value then return 0 end
    if value:IsA("IntValue") or value:IsA("NumberValue") then return math.max(0,value.Value) end
    return nil
end
local fairyOffers = { prices = {}, candyCost = 0 }
function fairyOffers.cost(option)
    if type(option) ~= "table" then return nil end
    local value = option.CandyCost
        or (type(option.Cost) == "table" and option.Cost.Candy)
        or (type(option.Costs) == "table" and option.Costs.Candy)
    if not value and option.Currency == "Candy" then value = option.Price or option.Cost end
    if type(value) == "number" and value >= 1 and value % 1 == 0 then return value end
    local text = tostring(option.Text or ""):lower():gsub(",", "")
    local amount = text:match("(%d+)%s+candy") or text:match("candy%s*[x:]%s*(%d+)")
    amount = tonumber(amount)
    if amount and amount >= 1 then return amount end
    if text:find("a candy", 1, true) or text:find("one candy", 1, true) then return 1 end
end
function fairyOffers.option(menu)
    for _, option in ipairs(type(menu) == "table" and menu.Options or {}) do
        local text = tostring(option.Text or ""):lower()
        if type(option.Id) == "string" and text:find("candy", 1, true)
            and text:find("fairy dust", 1, true) then
            return option.Id, fairyOffers.cost(option)
        end
    end
end
function fairyOffers.required(id)
    return fairyOffers.prices[id] or (fairyOffers.candyCost > 0 and fairyOffers.candyCost or nil)
end
function fairyOffers.affordable(id)
    local cost = fairyOffers.required(id)
    return cost ~= nil and inventoryAmount("Candy") >= cost, cost
end
function fairyOffers.learnNearby(prompt, id)
    if fairyOffers.prices[id] then return end
    local cf = currentPosition()
    local holder = prompt and prompt.Parent
    local position = holder and fairyTargets.position(holder)
    if not cf or not position or (cf.Position - position).Magnitude > (prompt.MaxActivationDistance or 10) then return end
    local ok, menu = pcall(invoke, "NpcOpen", id)
    if ok then
        local _, cost = fairyOffers.option(menu)
        if cost then fairyOffers.prices[id] = cost configChanged() end
    end
end
local function startFairy()
    if not states.fairy then stop("fairy") return end
    if jobs.fairy then return end
    jobs.fairy=task.defer(function()
        while enabled("fairy") do
            local prompt,id=findFairy()
            local count=acorns()
            if count==nil then fairyReport("WAITING FOR INVENTORY")
            elseif count<1 then fairyReport("WAITING FOR GOLDEN ACORNS")
            elseif not prompt then fairyReport("WAITING FOR THE FAIRY")
            else
                if not movement.acquire("fairy") then break end
                local queuedCount=acorns()
                if not queuedCount or queuedCount<1 then
                    movement.release("fairy")
                    fairyReport("WAITING FOR GOLDEN ACORNS")
                else
                fairyOrigin=currentPosition()
                local trades=0
                local approachedId=nil
                local emptySince=nil
                local retryAt=0
                -- Keep the same turn across trades, unavailable menus and transient failures.
                while enabled("fairy") do
                    local remaining=acorns()
                    if remaining==nil then
                        emptySince=nil
                        fairyReport("INVENTORY UNAVAILABLE • OTHER TASKS WAIT")
                    elseif remaining==0 then
                        emptySince=emptySince or os.clock()
                        if os.clock()-emptySince>=0.5 then
                            fairyReport("GOLDEN ACORNS: 0 • TRADING COMPLETE")
                            break
                        end
                    else
                        emptySince=nil
                        if os.clock()>=retryAt then
                            prompt,id=findFairy()
                            if not prompt then
                                approachedId=nil
                                retryAt=os.clock()+2
                                fairyReport("GOLDEN ACORNS: "..remaining.." • WAITING FOR MUSHROOM FAIRY • OTHER TASKS WAIT")
                            else
                                local ok,err=pcall(function()
                                    local available=acorns()
                                    if not available or available<1 then return end
                                    if approachedId~=id then
                                        if not approachKeeper("fairy",id,prompt) then return end
                                        approachedId=id
                                    end
                                    if not enabled("fairy") then return end
                                    local menu=checkedInvoke("NpcOpen",id)
                                    if not enabled("fairy") then return end
                                    local choice=nil
                                    for _,option in ipairs(type(menu)=="table" and menu.Options or {}) do
                                        local text=tostring(option.Text or ""):lower()
                                        if type(option.Id)=="string" and text:find("3 fairy dust",1,true)
                                            and text:find("golden acorn",1,true) then choice=option.Id break end
                                    end
                                    if not choice then
                                        showShopReply(id,menu)
                                        error("Golden Acorn offer unavailable")
                                    end
                                    local before=acorns()
                                    if not before or before<=0 or not enabled("fairy") then return end
                                    checkedInvoke("NpcChoose",id,choice)
                                    local started=os.clock()
                                    local after=acorns()
                                    while enabled("fairy") and (after==nil or after>=before) and os.clock()-started<3 do
                                        task.wait(0.1)
                                        after=acorns()
                                    end
                                    if not enabled("fairy") then return end
                                    if after==nil or after>=before then error("Inventory decrease not confirmed") end
                                    trades=trades+1
                                    fairyReport("TRADES: "..trades.." • GOLDEN ACORNS: "..after)
                                end)
                                if not ok then
                                    approachedId=nil
                                    retryAt=os.clock()+2
                                    fairyReport("TRADE RETRY • "..tostring(err).." • OTHER TASKS WAIT")
                                end
                            end
                        end
                    end
                    task.wait(0.25)
                end
                fairyCleanup()
                end
            end
            task.wait(3)
        end
        fairyCleanup()
        jobs.fairy=nil
    end)
end
-- Prompt actions share the movement queue with shops, trees and the fairy.
local activityOwner=nil
local activityStatus={}
local catchSequence=0
local auxiliaryConnections={}
auxiliaryConnections[#auxiliaryConnections+1]=workspace.DescendantAdded:Connect(dustCycle.observe)
local catchEvent=game:GetService("ReplicatedStorage").Shared:FindFirstChild("FishingCatchEvent")
if catchEvent and catchEvent:IsA("RemoteEvent") then
    auxiliaryConnections[#auxiliaryConnections+1]=catchEvent.OnClientEvent:Connect(function(kind)
        if kind=="catch" then catchSequence=catchSequence+1 end
    end)
end
local function activityReport(key,message)
    report(message)
    if activityStatus[key] then activityStatus[key].Text=message end
end
activityCleanup=function(key)
    if activityOwner~=key then return end
    stopWalking()
    activityOwner=nil
    movement.release(key)
end
local function teleportPrompt(key,prompt)
    if not enabled(key) or not prompt.Parent or not prompt.Enabled then return false end
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    local humanoid=c and c:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then return false end
    local part=prompt:FindFirstAncestorWhichIsA("BasePart")
    local model=prompt:FindFirstAncestorWhichIsA("Model")
    local holder=prompt.Parent
    local pos=holder:IsA("Attachment") and holder.WorldPosition or (part and part.Position or (model and model:GetPivot().Position))
    if not pos then return false end
    local offset=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
    offset=offset.Magnitude>0.1 and offset.Unit or Vector3.new(1,0,0)
    local target=pos+offset*math.min(2.5,prompt.MaxActivationDistance*0.5)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={c,model or part}
    local ground=workspace:Raycast(target+Vector3.new(0,15,0),Vector3.new(0,-80,0),params)
    if ground then target=Vector3.new(target.X,ground.Position.Y+humanoid.HipHeight+root.Size.Y/2,target.Z) end
    if key=="pickups" then target=pos+Vector3.new(0,math.min(1,prompt.MaxActivationDistance*0.25),0) end
    if key~="fishing" or (root.Position-pos).Magnitude>prompt.MaxActivationDistance*0.8 then
        root.CFrame=CFrame.new(target)
        task.wait(0.2)
    end
    if not enabled(key) or not prompt.Parent then return false end
    if (root.Position-pos).Magnitude>prompt.MaxActivationDistance then return false end
    if type(fireproximityprompt)=="function" then
        fireproximityprompt(prompt)
    else
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration+0.05)
        prompt:InputHoldEnd()
    end
    return true
end
local pickupNames={
    ["wildflowers"]=true,["candy"]=true,["acorn"]=true,["bird feather"]=true,
    ["forest mushroom"]=true,["golden acorn"]=true,["four leaf clover"]=true,
    ["four-leaf clover"]=true,["clover"]=true}
do
    local ok,config=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.ItemConfig) end)
    if ok then
        for _,item in pairs(config.Forage or {}) do
            if type(item)=="table" and type(item.DisplayName)=="string" then
                pickupNames[item.DisplayName:lower()]=true
            end
        end
    end
end
local function closestPrompt(predicate)
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    local closest,distance=nil,math.huge
    if not root then return end
    local island=workspace:FindFirstChild("FuzzIsland") or workspace
    for _,prompt in ipairs(island:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled and predicate(prompt) then
            local part=prompt:FindFirstAncestorWhichIsA("BasePart")
            if part then
                local d=(root.Position-part.Position).Magnitude
                if d<distance then closest,distance=prompt,d end
            end
        end
    end
    return closest
end
local function visibleForestDrop(attempted)
    local folder=workspace:FindFirstChild("ForestFinds",true)
    if not folder then return end
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local closest,best=nil,math.huge
    for _,drop in ipairs(folder:GetChildren()) do
        if (drop:IsA("Model") or drop:IsA("BasePart")) and drop.Name:match("^Find_")
            and os.clock()-(attempted[drop] or -math.huge)>=5 then
            local part=drop:IsA("BasePart") and drop or drop:FindFirstChildWhichIsA("BasePart",true)
            if part and part.Transparency<1 then
                local distance=(part.Position-root.Position).Magnitude
                if distance<best then closest,best=drop,distance end
            end
        end
    end
    return closest
end
local function collectForestDrop(key,drop)
    local c=player.Character
    local root=c and c:FindFirstChild("HumanoidRootPart")
    if not root or not drop.Parent then return false end
    local part=drop:IsA("BasePart") and drop or drop:FindFirstChildWhichIsA("BasePart",true)
    if not part then return false end
    -- Drops are discovered as Find_* objects, independent of whether a prompt is visible.
    root.CFrame=CFrame.new(part.Position+Vector3.new(0,0.8,0))
    task.wait(0.15)
    if not enabled(key) then return false end
    local prompt=drop:FindFirstChildWhichIsA("ProximityPrompt",true)
    if prompt and prompt.Enabled then
        if type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
        else prompt:InputHoldBegin() task.wait(prompt.HoldDuration+0.05) prompt:InputHoldEnd() end
    else
        local click=drop:FindFirstChildWhichIsA("ClickDetector",true)
        if click and type(fireclickdetector)=="function" then fireclickdetector(click) end
        if type(firetouchinterest)=="function" then
            firetouchinterest(root,part,0)
            task.wait(0.05)
            firetouchinterest(root,part,1)
        end
    end
    -- Ordinary physical contact also works for touch-driven drops.
    task.wait(0.2)
    return drop.Parent==nil or part.Parent==nil
end
local function ownedGarden()
    local beds=ownedBeds()
    return beds and beds.Parent
end
local function offeredChoice(menu,predicate)
    for _,option in ipairs(type(menu)=="table" and menu.Options or {}) do
        if type(option.Id)=="string" and predicate(tostring(option.Text or ""):lower(),option.Id:lower()) then return option.Id end
    end
end
local saleLimit={value=0,text="",lastRefresh=0,gameCap=1000000000}
function saleLimit.parse(text)
    assert(type(text)=="string" and #text<=64,"Enter an amount such as 1B, 500M or 1000000000.")
    local normalized=text:lower():gsub("[,%s_]","")
    if normalized=="" then return 0,"" end
    local amount,suffix=normalized:match("^(%d*%.?%d+)([kmbt]?)$")
    assert(amount,"Invalid sell limit. Use 1B, 500M, 1.5B or a full number.")
    local multipliers={k=1e3,m=1e6,b=1e9,t=1e12,[""]=1}
    local value=tonumber(amount)*multipliers[suffix]
    assert(value==value and value>=0 and value<=9007199254740991,"Sell limit is too large.")
    value=math.ceil(value)
    return value,value==0 and "" or normalized:upper()
end
function saleLimit.set(text)
    local value,display=saleLimit.parse(text)
    saleLimit.value,saleLimit.text=value,display
    if saleLimit.input then saleLimit.input.Text=display end
    saleLimit.lastRefresh=0
    configChanged()
end
function saleLimit.balance()
    local stats=player:FindFirstChild("leaderstats")
    local coins=stats and stats:FindFirstChild("Coins")
    if not coins or not (coins:IsA("IntValue") or coins:IsA("NumberValue")) then return nil end
    local value=coins.Value
    if type(value)=="number" and value==value and math.abs(value)<math.huge then return value end
end
function saleLimit.target()
    return saleLimit.value>0 and math.min(saleLimit.value,saleLimit.gameCap) or saleLimit.gameCap
end
function saleLimit.blocked()
    local balance=saleLimit.balance()
    return balance==nil or balance>=saleLimit.target()
end
function saleLimit.reason()
    local balance=saleLimit.balance()
    if balance==nil then return "AUTO SELL PAUSED • BALANCE UNAVAILABLE" end
    return "AUTO SELL PAUSED • EFFECTIVE BALANCE LIMIT REACHED"
end
function saleLimit.refresh()
    if not saleLimit.label or os.clock()-saleLimit.lastRefresh<0.5 then return end
    saleLimit.lastRefresh=os.clock()
    local balance=saleLimit.balance()
    local text=balance and (("%.0f"):format(balance):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")) or "UNAVAILABLE"
    saleLimit.label.Text="EFFECTIVE LIMIT: "..("%.0f"):format(saleLimit.target()).." • BALANCE: "..text.."\n"..
        (saleLimit.blocked() and "AUTO SELL PAUSED" or "BELOW LIMIT")
end
local saleDiagnostics={label=nil,reply=nil}
local function saleSnapshot()
    local items=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    local cropCount=0
    local seen={}
    for _,crop in pairs(items.Crops) do
        for field,id in pairs(crop) do
            if type(field)=="string" and field:find("HarvestItemId",1,true) and type(id)=="string" and not seen[id] then
                seen[id]=true
                cropCount=cropCount+inventoryAmount(id)
            end
        end
    end
    local stats=player:FindFirstChild("leaderstats")
    local coins=stats and stats:FindFirstChild("Coins")
    return cropCount,coins and coins.Value or 0
end
local safeSales={cap=1000000000,logs={},menus={},maxTransactions=12}
function safeSales.capture(menu,label)
    local ok,text=pcall(function()return HttpService:JSONEncode(menu)end)
    if not ok then
        local lines={tostring(type(menu)=="table" and menu.Text or menu)}
        for _,option in ipairs(type(menu)=="table" and menu.Options or {}) do lines[#lines+1]=tostring(option.Id).." • "..tostring(option.Text) end
        text=table.concat(lines,"\n")
    end
    safeSales.menus[#safeSales.menus+1]=label.."\n"..text:sub(1,10000)
    if #safeSales.menus>8 then table.remove(safeSales.menus,1) end
end
function safeSales.log(message)
    safeSales.logs[#safeSales.logs+1]=message
    if #safeSales.logs>40 then table.remove(safeSales.logs,1) end
    saleDiagnostics.reply=table.concat(safeSales.logs,"\n")
    if saleDiagnostics.label then saleDiagnostics.label.Text=saleDiagnostics.reply end
end
function safeSales.allowed(key)
    if not enabled(key) or saleLimit.blocked() then return false end
    if states.sellOnlyBoom~=false then
        local untilTime=tonumber(workspace:GetAttribute("IslandEventEndsAt")) or 0
        return workspace:GetAttribute("IslandEvent")=="MarketBoom" and untilTime>workspace:GetServerTimeNow()
    end
    return true
end
function safeSales.bonusKey()
    return tostring(player:GetAttribute("FuzzSell")).."|"..tostring(player:GetAttribute("Pass_DoubleCoins")).."|"..
        tostring(workspace:GetAttribute("IslandEvent")).."|"..tostring(workspace:GetAttribute("IslandEventEndsAt")).."|"..
        tostring(workspace:GetAttribute("Festival"))
end
function safeSales.items()
    local config=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    local prices=config.SellPrices()
    local result={}
    for cropId,crop in pairs(config.Crops) do
        if states.autoDetectSellCrops or not states.sellSpecificOnly or states["sellcrop:"..cropId] then
            for field,itemId in pairs(crop) do
                if type(field)=="string" and field:find("HarvestItemId",1,true) and type(itemId)=="string" then
                    local amount=inventoryAmount(itemId)
                    local price=tonumber(prices[itemId])
                    local item=config.Items[itemId]
                    if amount>0 and price and price>0 then result[itemId]={id=itemId,crop=cropId,stock=amount,base=price,name=item and item.DisplayName or itemId} end
                end
            end
        end
    end
    return result
end
function safeSales.rankedInventory()
    local ranked={}
    for _,item in pairs(safeSales.items()) do ranked[#ranked+1]=item end
    table.sort(ranked,function(a,b)
        if a.base~=b.base then return a.base>b.base end
        return a.id<b.id
    end)
    return ranked
end
function safeSales.refreshDetected()
    if not safeSales.detectedLabel or os.clock()-(safeSales.lastDetection or -math.huge)<1 then return end
    safeSales.lastDetection=os.clock()
    if not states.autoDetectSellCrops then safeSales.detectedLabel.Text="AUTO DETECT: OFF • USING MANUAL SELECTIONS" return end
    local ranked=safeSales.rankedInventory()
    local item=ranked[1]
    if not item then safeSales.detectedLabel.Text="AUTO DETECT: NO SELLABLE CROPS IN BAG" return end
    local price=("%.0f"):format(item.base):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
    safeSales.detectedLabel.Text="MOST EXPENSIVE IN BAG: "..item.name:upper().." x"..item.stock.."\nCATALOG PRICE PER FRUIT: "..price.." COINS"
end
function safeSales.contains(text,word)
    text,word=text:lower(),word:lower()
    local start=1
    while true do
        local a,b=text:find(word,start,true)
        if not a then return false end
        local before=a>1 and text:sub(a-1,a-1) or ""
        local after=text:sub(b+1,b+1)
        if not before:match("[%w_]") and not after:match("[%w_]") then return true end
        start=b+1
    end
end
function safeSales.matchItem(option,items)
    local explicit=option.ItemId or option.ItemID or option.HarvestItemId
    if type(explicit)=="string" then return items[explicit] end
    local candidates={}
    for _,item in pairs(items) do
        if safeSales.contains(tostring(option.Id or ""),item.id) or safeSales.contains(tostring(option.Text or ""),item.name) then candidates[#candidates+1]=item end
    end
    table.sort(candidates,function(a,b)return #a.name>#b.name end)
    if not candidates[1] then return end
    -- A mutation's full name wins over a base name contained inside it.
    if candidates[2] and #candidates[1].name==#candidates[2].name then return end
    return candidates[1]
end
function safeSales.quote(option,item)
    if type(option.Id)~="string" or option.Disabled==true or option.Enabled==false or option.Available==false then return nil,"unavailable offer" end
    local amount=option.UncappedTotalCoins or option.TotalCoins or option.TotalPayout
    local quantity=option.Quantity or option.Count
    local text=tostring(option.Text or ""):gsub("<[^>]+>",""):gsub("💰",""):lower()
    if type(amount)~="number" or type(quantity)~="number" then
        -- Never treat an ambiguous per-item price or a rounded 1.2B label as a full quote.
        if text:find("each",1,true) or text:find("per item",1,true) or not text:match("^%s*sell%s+") then return nil,"no explicit total quote" end
        local prefix,literal=text:match("^%s*(sell .-)%s+for%s+([%d,]+)%s+coins[%p%s]*$")
        if not literal then return nil,"exact integer total not shown" end
        amount=tonumber((literal:gsub(",","")))
        quantity=tonumber(prefix:match("^sell%s+(%d+)%s") or prefix:match("[xX]%s*(%d+)") or prefix:match("×%s*(%d+)"))
        if not quantity and prefix:match("^sell all ") then quantity=item.stock end
    end
    if type(amount)~="number" or amount~=amount or amount<=0 or amount>9007199254740991 or amount%1~=0 then return nil,"invalid total" end
    if type(quantity)~="number" or quantity~=quantity or quantity<1 or quantity%1~=0 or quantity>item.stock then return nil,"quantity not confirmed" end
    -- Reject apparent cap-clipped quotes instead of trusting a displayed capped amount.
    local unit=math.floor(item.base*(1+math.max(0,tonumber(player:GetAttribute("FuzzSell")) or 0)))
    if workspace:GetAttribute("IslandEvent")=="MarketBoom" then unit=math.floor(unit*1.5) end
    if player:GetAttribute("Pass_DoubleCoins")==true then unit=unit*2 end
    if amount<unit*quantity then return nil,"quote is below known uncapped value" end
    return {id=option.Id,item=item.id,crop=item.crop,quantity=quantity,total=amount,unit=amount/quantity,stock=item.stock,bonus=safeSales.bonusKey()}
end
function safeSales.root(key)
    if not safeSales.allowed(key) then return end
    local menu=checkedInvoke("NpcOpen","Grocer")
    safeSales.capture(menu,"GROCER ROOT")
    if not safeSales.allowed(key) then return end
    local page=offeredChoice(menu,function(text)
        return text:find("sell one kind",1,true) or text:find("prices",1,true)
    end)
    if not page then safeSales.log("ONE-KIND MENU NOT OFFERED: "..tostring(type(menu)=="table" and menu.Text or menu)) return end
    local result=checkedInvoke("NpcChoose","Grocer",page)
    return result,{page}
end
function safeSales.offers(key)
    local items=safeSales.items()
    local menu,path=safeSales.root(key)
    if not menu then return {} end
    local candidates,seen={},{}
    for _=1,40 do
        if not safeSales.allowed(key) then break end
        local signature={tostring(type(menu)=="table" and menu.Text or "")}
        local options=type(menu)=="table" and menu.Options or {}
        safeSales.capture(menu,"ONE-KIND PRICE PAGE")
        for _,option in ipairs(options) do signature[#signature+1]=tostring(option.Id) end
        signature=table.concat(signature,"|")
        if seen[signature] then break end
        seen[signature]=true
        for _,option in ipairs(options) do
            local item=safeSales.matchItem(option,items)
            if item then
                local quote,why=safeSales.quote(option,item)
                if quote then
                    quote.path={}
                    for i,id in ipairs(path) do quote.path[i]=id end
                    candidates[#candidates+1]=quote
                else safeSales.log("SKIP "..item.id..": "..tostring(why).." • "..tostring(option.Id).." • "..tostring(option.Text)) end
            end
        end
        local nextId=offeredChoice(menu,function(text)return text:find("next page",1,true) or text:match("^next%s")end)
        if not nextId then break end
        menu=checkedInvoke("NpcChoose","Grocer",nextId)
        path[#path+1]=nextId
    end
    table.sort(candidates,function(a,b)
        if a.unit~=b.unit then return a.unit>b.unit end
        if a.total~=b.total then return a.total>b.total end
        return a.item<b.item
    end)
    return candidates
end
function safeSales.fits(quote)
    local balance=saleLimit.balance()
    if balance==nil or not quote then return false end
    -- Keep one coin of room: cap-clipped quotes equal to the remaining room are not accepted.
    return quote.total<saleLimit.target()-balance
end
function safeSales.fresh(key,candidate)
    local menu=checkedInvoke("NpcOpen","Grocer")
    for _,id in ipairs(candidate.path) do
        if not safeSales.allowed(key) then return end
        local offered=false
        for _,option in ipairs(type(menu)=="table" and menu.Options or {}) do if option.Id==id then offered=true break end end
        if not offered then return end
        menu=checkedInvoke("NpcChoose","Grocer",id)
    end
    for _,option in ipairs(type(menu)=="table" and menu.Options or {}) do
        if option.Id==candidate.id then
            local items=safeSales.items()
            local item=items[candidate.item]
            if not item then return end
            local quote=safeSales.quote(option,item)
            if quote and quote.item==candidate.item then return quote end
        end
    end
end
function safeSales.run(key)
    if safeSales.halted then activityReport(key,"SAFE SELL PAUSED • CHECK DIAGNOSTICS AND RESUME") return false end
    if not safeSales.allowed(key) then activityReport(key,saleLimit.blocked() and saleLimit.reason() or "WAITING FOR MARKET BOOM") return false end
    if not approachKeeper(key,"Grocer") then return false end
    local confirmedAny=false
    for _=1,safeSales.maxTransactions do
        if not safeSales.allowed(key) then break end
        local candidates=safeSales.offers(key)
        local chosen=nil
        for _,quote in ipairs(candidates) do if safeSales.fits(quote) then chosen=quote break end end
        if not chosen then
            local reason=#candidates==0 and "NO EXACT SELECTED-CROP SALE QUOTE • SEE DIAGNOSTICS" or "NO CROP STACK FITS THE REMAINING BALANCE SPACE • FRUIT KEPT"
            safeSales.log(reason) activityReport(key,reason)
            return confirmedAny
        end
        local quote=safeSales.fresh(key,chosen)
        if not quote or not safeSales.fits(quote) or not safeSales.allowed(key) then
            safeSales.log("QUOTE OR BALANCE CHANGED • SALE SKIPPED") return confirmedAny
        end
        local beforeStock=inventoryAmount(quote.item)
        local beforeBalance=saleLimit.balance()
        if beforeStock~=quote.stock or quote.bonus~=safeSales.bonusKey() then
            safeSales.log("STOCK OR BONUS CHANGED • SALE SKIPPED") return confirmedAny
        end
        if not safeSales.fits(quote) or not safeSales.allowed(key) then return confirmedAny end
        safeSales.log(("REQUEST %s x%d • QUOTED %d • BALANCE %.0f"):format(quote.item,quote.quantity,quote.total,beforeBalance))
        local sent,result=pcall(checkedInvoke,"NpcChoose","Grocer",quote.id)
        if not sent then
            safeSales.halted=true configChanged()
            safeSales.log("SALE OUTCOME UNKNOWN • AUTOMATIC RETRIES PAUSED • "..tostring(result))
            activityReport(key,"SAFE SELL PAUSED • CHECK DIAGNOSTICS")
            return confirmedAny
        end
        showShopReply("Grocer specific sale",result)
        local began=os.clock()
        local afterStock,afterBalance=inventoryAmount(quote.item),saleLimit.balance()
        while enabled(key) and (afterStock>=beforeStock or afterBalance==nil or afterBalance<=beforeBalance) and os.clock()-began<4 do
            task.wait(0.05)
            afterStock,afterBalance=inventoryAmount(quote.item),saleLimit.balance()
        end
        if not enabled(key) then return confirmedAny end
        if afterBalance==nil or beforeStock-afterStock~=quote.quantity or afterBalance-beforeBalance~=quote.total then
            safeSales.log("SALE RESULT DOES NOT MATCH QUOTE • FURTHER SALES PAUSED")
            safeSales.halted=true configChanged() activityReport(key,"SAFE SELL PAUSED • CHECK SALE DIAGNOSTICS") return confirmedAny
        end
        confirmedAny=true
        safeSales.log(("CONFIRMED %s x%d • +%d • BALANCE %.0f"):format(quote.item,quote.quantity,quote.total,afterBalance))
        activityReport(key,"SPECIFIC CROP SALE CONFIRMED • "..quote.item)
        task.wait(0.1)
    end
    return confirmedAny
end

local function npcAction(key,npc,predicate)
    if npc=="Grocer" then return safeSales.run(key) end
    if not approachKeeper(key,npc) then return false end
    local menu=checkedInvoke("NpcOpen",npc)
    showShopReply(npc,menu)
    local choice=offeredChoice(menu,predicate)
    if not choice then activityReport(key,"Required offer not in "..npc.." menu; see NPC reply") return false end
    local result=invoke("NpcChoose",npc,choice)
    if result==false then activityReport(key,"Server declined "..key) return false end
    activityReport(key,"Requested "..key.." from "..npc)
    return true
end
local function hasSellablePlants()
    if saleLimit.blocked() or safeSales.halted then return false end
    return next(safeSales.items())~=nil
end
local function startActivity(key)
    if not states[key] then stop(key) return end
    if jobs[key] then return end
    jobs[key]=task.defer(function()
        local attempted=setmetatable({},{__mode="k"})
        local lastMarket=nil
        local nextAttempt=0
        while enabled(key) do
            local now=workspace:GetServerTimeNow()
            local boom=workspace:GetAttribute("IslandEvent")=="MarketBoom"
            local boomEnd=tonumber(workspace:GetAttribute("IslandEventEndsAt")) or 0
            local ready=now>=nextAttempt
            if key=="sellBoom" then
                if safeSales.halted then
                    ready=false
                    activityReport(key,"SAFE SELL PAUSED • CHECK DIAGNOSTICS AND RESUME")
                elseif saleLimit.blocked() then
                    ready=false
                    activityReport(key,saleLimit.reason())
                elseif states.sellOnlyBoom~=false then ready=ready and boom and boomEnd>now and hasSellablePlants()
                else ready=ready and hasSellablePlants() end
            end
            if ready then
                if not movement.acquire(key) then break end
                activityOwner=key
                local ok,err=pcall(function()
                    if key=="pickups" then
                        local drop=visibleForestDrop(attempted)
                        if drop then
                            attempted[drop]=os.clock()
                            local name=drop.Name
                            if collectForestDrop(key,drop) then
                                activityReport(key,"Collected "..name)
                            else activityReport(key,"Contact/interaction requested: "..name.."; will recheck") end
                        else activityReport(key,"Watching ForestFinds for visible drops") end
                        nextAttempt=workspace:GetServerTimeNow()+0.15
                    elseif key=="fishing" then
                        local prompt=closestPrompt(function(p)
                            return p.Name=="FishingPrompt" and (p.ObjectText:lower():find("lake",1,true)
                                or p:FindFirstAncestor("FishingSpot_Lake"))
                        end)
                        if prompt then
                            local sequence=catchSequence
                            if teleportPrompt(key,prompt) then
                                activityReport(key,"Cast requested at "..prompt.ObjectText)
                                local started=workspace:GetServerTimeNow()
                                repeat task.wait(0.05)
                                until not enabled(key) or catchSequence>sequence or movement.higherPending(key) or workspace:GetServerTimeNow()-started>=15
                                activityReport(key,catchSequence>sequence and "Fish catch confirmed" or "Waiting for next available cast")
                            end
                        else activityReport(key,"No available Cast Line prompt") end
                        nextAttempt=workspace:GetServerTimeNow()+0.05
                    elseif key=="sellBoom" then
                        safeSales.run(key)
                        nextAttempt=now+15
                    elseif key=="houseUpgrade" then
                        npcAction(key,"Carpenter",function(text)
                            return (text:find("upgrade",1,true) or text:find("expand",1,true))
                                and (text:find("house",1,true) or text:find("cottage",1,true) or text:find("home",1,true))
                        end)
                        nextAttempt=now+15
                    elseif key=="gardenUpgrade" then
                        local garden=ownedGarden()
                        local prompt=garden and garden:FindFirstChild("UpgradeFarm",true)
                        if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                            teleportPrompt(key,prompt)
                            activityReport(key,"Garden upgrade requested")
                        else activityReport(key,"Owned garden upgrade unavailable or already complete") end
                        nextAttempt=now+15
                    end
                end)
                activityCleanup(key)
                if not ok then
                    activityReport(key,"Retrying: "..tostring(err))
                end
            elseif key=="sellBoom" and states.sellOnlyBoom~=false and not boom and not saleLimit.blocked() then
                activityReport(key,"Waiting for the Market Boom event")
            end
            task.wait(key=="fishing" and 0.05 or 0.5)
        end
        activityCleanup(key)
        jobs[key]=nil
    end)
end
local candyFairyLabel=nil
local function candyFairyReport(message)
    report(message)
    if candyFairyLabel then candyFairyLabel.Text=message end
end
local function fairyPrompts()
    local _,candy=fairyTargets.scan()
    return candy
end
local function startCandyFairy()
    if not states.candyFairy then stop("candyFairy") return end
    if jobs.candyFairy then return end
    jobs.candyFairy=task.defer(function()
        local nextCheck=setmetatable({},{__mode="k"})
        while enabled("candyFairy") do
            if inventoryAmount("Candy")>0 then
                for _,prompt in ipairs(fairyPrompts()) do
                    if not enabled("candyFairy") then break end
                    if inventoryAmount("Candy")<=0 then break end
                    if os.clock()>=(nextCheck[prompt] or 0) then
                        local id=prompt:GetAttribute("NpcId")
                        fairyOffers.learnNearby(prompt,id)
                        local affordable,cost=fairyOffers.affordable(id)
                        if not cost then
                            candyFairyReport("CANDY PRICE UNKNOWN • VISIT A FAIRY ONCE OR ENTER ITS COST")
                            nextCheck[prompt]=os.clock()+3
                        elseif not affordable then
                            candyFairyReport("WAITING FOR CANDY: "..inventoryAmount("Candy").." / "..cost)
                        else
                            if not movement.acquire("candyFairy") then return end
                            activityOwner="candyFairy"
                            local ok,err=pcall(function()
                                -- Inventory can change while this worker waits for its turn.
                                if not enabled("candyFairy") or not fairyOffers.affordable(id) then return end
                                if not approachKeeper("candyFairy",id,prompt) then return end
                                if not enabled("candyFairy") or not fairyOffers.affordable(id) then return end
                                local menu=checkedInvoke("NpcOpen",id)
                                if not enabled("candyFairy") then return end
                                showShopReply(id,menu)
                                local choice,actualCost=fairyOffers.option(menu)
                                if actualCost then fairyOffers.prices[id]=actualCost configChanged() end
                                if not choice then
                                    candyFairyReport("NO CANDY → FAIRY DUST OFFER AT "..id)
                                    nextCheck[prompt]=os.clock()+15
                                    return
                                end
                                local canOffer,required=fairyOffers.affordable(id)
                                if not canOffer then
                                    candyFairyReport("WAITING FOR CANDY: "..inventoryAmount("Candy").." / "..tostring(required))
                                    return
                                end
                                local beforeCandy=inventoryAmount("Candy")
                                local beforeDust=inventoryAmount("FairyDust")
                                if not enabled("candyFairy") then return end
                                invoke("NpcChoose",id,choice)
                                local started=os.clock()
                                repeat task.wait(0.1)
                                until not enabled("candyFairy") or (inventoryAmount("Candy")<beforeCandy and inventoryAmount("FairyDust")>beforeDust) or os.clock()-started>=4
                                if inventoryAmount("Candy")<beforeCandy and inventoryAmount("FairyDust")>beforeDust then
                                    fairyOffers.prices[id]=actualCost or required
                                    configChanged()
                                    candyFairyReport("CANDY TRADE CONFIRMED • LEFT: "..inventoryAmount("Candy"))
                                    nextCheck[prompt]=os.clock()+0.25
                                else
                                    candyFairyReport("CANDY TRADE NOT CONFIRMED • SEE NPC REPLY")
                                    nextCheck[prompt]=os.clock()+15
                                end
                            end)
                            activityCleanup("candyFairy")
                            if not ok then candyFairyReport("CANDY TRADE ERROR: "..tostring(err)) nextCheck[prompt]=os.clock()+15 end
                        end
                    end
                end
            else candyFairyReport("WAITING FOR CANDY") end
            task.wait(0.5)
        end
        activityCleanup("candyFairy")
        jobs.candyFairy=nil
    end)
end
auxiliaryConnections[#auxiliaryConnections+1]=player.Idled:Connect(function()
    if not states.antiAfk then return end
    local ok,err=pcall(function()
        local virtualUser=game:GetService("VirtualUser")
        virtualUser:CaptureController()
        local camera=workspace.CurrentCamera
        local cf=camera and camera.CFrame or CFrame.new()
        virtualUser:Button2Down(Vector2.new(0,0),cf)
        task.wait(0.05)
        virtualUser:Button2Up(Vector2.new(0,0),cf)
    end)
    report(ok and "Anti-idle input sent" or "Anti-idle unavailable: "..tostring(err))
end)
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
local extras={labels={},progress=nil,attempted={}}
function extras.say(key,message)
    if extras.labels[key] then extras.labels[key].Text=message end
    report(message)
end
function extras.cropId(bed)
    local visual=bed:FindFirstChild("CropVisual")
    if not visual then return end
    local config=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    for _,obj in ipairs({bed,visual}) do
        for _,attr in ipairs({"CropId","Crop","CropType"}) do
            local value=obj:GetAttribute(attr)
            if config.Crops[value] then return value end
        end
    end
    local prompt=bed:FindFirstChild("DigPrompt",true)
    for id,crop in pairs(config.Crops) do
        if visual.Name==id or (prompt and prompt.ObjectText==crop.DisplayName) then return id end
    end
end
function extras.beds()
    local folder=ownedBeds()
    local beds={}
    if folder then
        for row=1,11 do for col=1,10 do
            local bed=folder:FindFirstChild(("Bed_%d_%d"):format(row,col))
            if bed then beds[#beds+1]=bed end
        end end
    end
    return beds
end
function extras.home()
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    if not atOwnBeds(root.Position) then
        local target=bedReturnPosition()
        if not target then return false end
        root.CFrame=target task.wait(0.2)
    end
    return true
end
function extras.move(source,dest)
    if not source:FindFirstChild("CropVisual") or dest:FindFirstChild("CropVisual") then return false end
    fire("MoveCrop",source.Name,dest.Name)
    local started=os.clock()
    repeat task.wait(0.05)
    until not alive or (not source:FindFirstChild("CropVisual") and dest:FindFirstChild("CropVisual")) or os.clock()-started>2
    return not source:FindFirstChild("CropVisual") and dest:FindFirstChild("CropVisual")~=nil
end
function extras.sortStep()
    local beds=extras.beds()
    local items=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    local selected={}
    local empty
    for _,bed in ipairs(beds) do
        local id=extras.cropId(bed)
        if not bed:FindFirstChild("CropVisual") then empty=bed end
        if id and states["sort:"..id] then
            selected[#selected+1]={bed=bed,id=id,cost=tonumber(items.Crops[id].PackCost) or 0}
        end
    end
    table.sort(selected,function(a,b) if a.cost==b.cost then return a.id<b.id end return a.cost>b.cost end)
    for index,entry in ipairs(selected) do
        local target=beds[index]
        if entry.bed~=target and extras.cropId(target)~=entry.id then
            if not empty then extras.say("rearrange","Sorting needs one empty bed; no plants were removed") return end
            if not extras.home() then return end
            if target:FindFirstChild("CropVisual") and not extras.move(target,empty) then
                extras.say("rearrange","Temporary move unconfirmed; retrying") return
            end
            if not enabled("rearrange") or movement.higherPending("rearrange") then return end
            local ok=extras.move(entry.bed,target)
            extras.say("rearrange",ok and ("Moved "..entry.id.." to "..target.Name) or "Move unconfirmed; retrying")
            return
        end
    end
    extras.say("rearrange","Selected crops sorted by seed-pack price; unselected crops kept")
end
function extras.digStep()
    for _,bed in ipairs(extras.beds()) do
        local id=extras.cropId(bed)
        if id and states["dig:"..id] then
            local prompt=bed:FindFirstChild("DigPrompt",true)
            if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                teleportPrompt("dig",prompt)
                extras.say("dig","Dig Up requested: "..id.." • "..bed.Name)
                return
            end
        end
    end
    extras.say("dig","Waiting for selected planted crops with an enabled Dig Up prompt")
end
function extras.menuStep(key,npc)
    if not approachKeeper(key,npc) then return end
    local menu=checkedInvoke("NpcOpen",npc)
    local seen={}
    for depth=1,12 do
        if not enabled(key) or movement.higherPending(key) then return end
        showShopReply(npc,menu)
        local choice
        for _,option in ipairs(type(menu)=="table" and menu.Options or {}) do
            local text=tostring(option.Text or ""):lower()
            local id=option.Id
            local unavailable=option.Disabled==true or option.Enabled==false or option.Available==false or text:find("not enough",1,true)
                or text:find("completed",1,true) or text:find("tomorrow",1,true) or text:find("locked",1,true)
            local action=text:find("submit",1,true) or text:find("deliver",1,true) or text:find("claim",1,true)
                or text:find("hand in",1,true) or text:find("turn in",1,true) or text:find("fill order",1,true) or text:find("fulfill",1,true)
                or text:find("complete order",1,true) or text:match("^give ")
                or text:find("complete request",1,true) or text:find("accept request",1,true)
            local offerId=type(id)=="string" and id:lower() or ""
            local submission=(key=="orders" and (offerId:match("^order[_#%d]") or offerId:match("^submit[_#]")))
                or (key=="mayor" and (offerId:match("^request[_#%d]") or offerId:match("^complete[_#]")))
            local have,need=text:match("(%d+)%s*/%s*(%d+)")
            if have and tonumber(have)<tonumber(need) then unavailable=true end
            if text:find("how",1,true) or text:find("help",1,true) then unavailable=true end
            local page=text=="orders" or text=="requests" or text:find("special orders",1,true) or text:find("daily requests",1,true)
                or text:find("today's requests",1,true) or text:find("quests",1,true)
            if type(id)=="string" and not seen[id] and not unavailable and (action or page or submission) then choice=id break end
        end
        if not choice then extras.say(key,"No available submission or claim in "..npc.." menu; see NPC replies") return end
        seen[choice]=true
        local result=checkedInvoke("NpcChoose",npc,choice)
        showShopReply(npc,result)
        if type(result)=="table" and type(result.Options)=="table" and #result.Options>0 then menu=result end
        task.wait(0.2)
    end
end
function extras.questStep()
    fire("RequestProgress")
    local quests=extras.progress and extras.progress.Quests
    if not quests then extras.say("quest","Waiting for server quest progress") return end
    local pending={}
    for _,q in ipairs(quests.List or {}) do
        if not q.Done then
            pending[#pending+1]=q.Text or q.Id or "Quest"
            local id=tostring(q.Id or "")
            local text=tostring(q.Text or ""):lower()
            if text:find("harvest",1,true) or text:find("water",1,true) then
                for _,bed in ipairs(extras.beds()) do
                    if (text:find("harvest",1,true) and bed:FindFirstChild("RipeSparkle"))
                        or (text:find("water",1,true) and bed:FindFirstChild("NeedsWater")) then
                        if extras.home() then fire("FarmTap",bed.Name,nil) end return
                    end
                end
            elseif text:find("plant",1,true) then
                local seed=planting.seed()
                local bed=planting.emptyBed()
                if seed and bed and extras.home() then
                    fire("SelectSeed",seed) task.wait(0.2)
                    if player:GetAttribute("SelectedSeed")==seed then fire("FarmTap",bed.Name,nil) end
                    return
                end
            elseif text:find("animal",1,true) then
                if animalsNeedingCare()>0 then animalCare.perform("quest") return end
            elseif text:find("fish",1,true) then
                local prompt=closestPrompt(function(p) return p.Name=="FishingPrompt" and
                    (p.ObjectText:lower():find("lake",1,true) or p:FindFirstAncestor("FishingSpot_Lake")) end)
                if prompt then
                    local sequence=catchSequence
                    if teleportPrompt("quest",prompt) then
                        local start=os.clock()
                        repeat task.wait(0.05) until not enabled("quest") or movement.higherPending("quest")
                            or catchSequence>sequence or os.clock()-start>=15
                    end
                    return
                end
            elseif text:find("wood",1,true) then
                local island=workspace:FindFirstChild("FuzzIsland")
                local nature=island and island:FindFirstChild("Nature")
                local trees=nature and nature:FindFirstChild("Trees")
                local character=player.Character
                local root=character and character:FindFirstChild("HumanoidRootPart")
                if trees and root then
                    for _,tree in ipairs(trees:GetChildren()) do
                        if treeNames[tree.Name] and tree:GetAttribute("Choppable")==true and not tree:GetAttribute("Felled") then
                            local pos=tree:IsA("Model") and tree:GetPivot().Position or tree.Position
                            root.CFrame=CFrame.new(pos+Vector3.new(1.5,1,0),pos)
                            task.wait(0.15) fire("Chop",tree) return
                        end
                    end
                end
            elseif text:find("market",1,true) and hasSellablePlants() then
                if states.sellOnlyBoom==false or workspace:GetAttribute("IslandEvent")=="MarketBoom" then
                    safeSales.run("quest")
                    return
                end
            end
        end
    end
    extras.say("quest",#pending==0 and "All daily quests complete; rewards are automatic" or
        ("Pending: "..table.concat(pending,"; ")..". Waiting on available resources. Gifts and likes stay manual."))
end
function extras.start(key)
    if not enabled(key) then stop(key) return end
    if jobs[key] then return end
    jobs[key]=task.defer(function()
        while enabled(key) do
            if not movement.acquire(key) then break end
            local ok,err=pcall(function()
                if key=="dig" then extras.digStep()
                elseif key=="rearrange" then extras.sortStep()
                elseif key=="quest" then extras.questStep()
                elseif key=="orders" then extras.menuStep(key,"FlowerSeller")
                elseif key=="mayor" then extras.menuStep(key,"Mayor") end
            end)
            movement.release(key)
            if not ok then extras.say(key,"Retrying: "..tostring(err)) end
            task.wait((key=="orders" or key=="mayor") and 30 or (key=="quest" and 5 or 1))
        end
        movement.release(key) jobs[key]=nil
    end)
end
local progressEvent=Remotes:FindFirstChild("ProgressUpdate")
if progressEvent and progressEvent:IsA("RemoteEvent") then
    auxiliaryConnections[#auxiliaryConnections+1]=progressEvent.OnClientEvent:Connect(function(data)
        if type(data)=="table" then extras.progress=data end
    end)
end
ui.categoryKeys={
    Main={"harvest","plant","dig","rearrange","dust","water","quest","tend","gardenUpgrade","houseUpgrade","LuckyCharm","RainbowDew","ripeReturn","returnAfterBuy"},
    Home={"houseLayout"},
    Plaza={"seeds","normalSeeds","gears","orders","sellBoom","mayor"},
    Forest={"fairy","candyFairy","pickups","wood"},
    Lake={"fishing"},Settings={"antiAfk","leaveOnJoin","autoExecute","autoReconnect"}
}
function ui.stopCategory(name)
    for _,key in ipairs(ui.categoryKeys[name] or {}) do stop(key) end
    if name=="Plaza" then
        if jobs.seedCheck then task.cancel(jobs.seedCheck) jobs.seedCheck=nil movement.release("seeds") end
        if jobs.buyer then task.cancel(jobs.buyer) jobs.buyer=nil end
        movement.release("buyer")
        pendingReturn=nil
    end
    report(name:upper().." TASKS STOPPED")
    configChanged()
end
ui.bag={labels={},lastRefresh=0}
function ui.bag.values()
    local items=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
    local prices=items.SellPrices()
    local seen={}
    local base=0
    local count=0
    for _,crop in pairs(items.Crops) do
        for field,id in pairs(crop) do
            if type(field)=="string" and field:find("HarvestItemId",1,true) and type(id)=="string" and not seen[id] then
                seen[id]=true
                local quantity=inventoryAmount(id)
                local price=tonumber(prices[id])
                if quantity>0 and price then base=base+quantity*price count=count+quantity end
            end
        end
    end
    local fuzz=math.max(0,tonumber(player:GetAttribute("FuzzSell")) or 0)
    return base,base*(1+fuzz),base*(1+fuzz)*1.5,count,fuzz
end
function ui.bag.money(value)
    local whole=tostring(math.floor(value+0.5))
    local grouped=whole:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
    return grouped.." COINS"
end
function ui.bag.refresh()
    if not ui.bag.labels.base or os.clock()-ui.bag.lastRefresh<1 then return end
    ui.bag.lastRefresh=os.clock()
    local ok,base,fuzz,boom,count,bonus=pcall(ui.bag.values)
    if not ok then
        ui.bag.labels.base.Text="NO BONUS: UNAVAILABLE"
        ui.bag.labels.fuzz.Text="FUZZ BONUS: UNAVAILABLE"
        ui.bag.labels.boom.Text="FUZZ + MARKET BOOM: UNAVAILABLE"
        return
    end
    ui.bag.labels.count.Text="BAG CROPS: "..count
    ui.bag.labels.base.Text="NO BONUS: "..ui.bag.money(base)
    ui.bag.labels.fuzz.Text=("FUZZ BONUS (+%.1f%%): %s"):format(bonus*100,ui.bag.money(fuzz))
    ui.bag.labels.boom.Text="FUZZ + MARKET BOOM: "..ui.bag.money(boom)
end
function ui.dispatch(key)
    if key=="autoReconnect" then
        if not states.autoReconnect then sessionOptions.reconnect.pending=false end
        sessionOptions.reconnectSay(states.autoReconnect and "AUTO RECONNECT: WATCHING FOR CONNECTION ERRORS" or "AUTO RECONNECT: OFF")
        return
    end
    if key=="autoExecute" then sessionOptions.sync() return end
    if key=="quest" or key=="orders" or key=="mayor" or key=="dig" or key=="rearrange" then extras.start(key) return end
    if key=="seeds" or key=="normalSeeds" or key=="gears" or key=="harvest" then runAutomation(key)
    elseif key=="LuckyCharm" or key=="RainbowDew" then startItem(key)
    elseif key=="wood" then startChop()
    elseif key=="tend" then startTend()
    elseif key=="water" then startWater()
    elseif key=="plant" then startPlant()
    elseif key=="fairy" then startFairy()
    elseif key=="candyFairy" then startCandyFairy()
    elseif key=="pickups" or key=="fishing" or key=="sellBoom" or key=="houseUpgrade" or key=="gardenUpgrade" then startActivity(key)
    elseif key=="dust" then
        if states.dust and not states.harvest then states.harvest=true renderToggle.harvest() runAutomation("harvest") end
        startDust()
    end
end
function ui.toggle(container,label,key,default)
    states[key]=default==true
    local row=make("TextButton",{Size=UDim2.new(1,0,0,25),Text="",BorderSizePixel=0,
        BackgroundColor3=Color3.fromRGB(21,30,43)},container)
    corner(row,5)
    make("TextLabel",{Position=UDim2.fromOffset(7,0),Size=UDim2.new(1,-53,1,0),
        BackgroundTransparency=1,Text=label:upper(),TextColor3=white,TextSize=10,TextWrapped=true,
        Font=Enum.Font.BuilderSans,TextXAlignment=Enum.TextXAlignment.Left},row)
    local track=make("Frame",{Position=UDim2.new(1,-32,0.5,-6),Size=UDim2.fromOffset(25,12),
        BackgroundColor3=Color3.fromRGB(47,59,75),BorderSizePixel=0},row)
    corner(track,8)
    local knob=make("Frame",{Position=UDim2.fromOffset(2,2),Size=UDim2.fromOffset(8,8),
        BackgroundColor3=white,BorderSizePixel=0},track)
    corner(knob,8)
    renderToggle[key]=function()
        track.BackgroundColor3=states[key] and blue or Color3.fromRGB(47,59,75)
        knob.Position=UDim2.fromOffset(states[key] and 15 or 2,2)
    end
    renderToggle[key]()
    row.Activated:Connect(function()
        states[key]=not states[key]
        renderToggle[key]()
        ui.dispatch(key)
        configChanged(key=="autoSave")
    end)
end
function ui.button(container,label,callback)
    local button=make("TextButton",{Size=UDim2.new(1,0,0,25),Text=label,TextSize=10,
        TextColor3=white,Font=Enum.Font.BuilderSans,BackgroundColor3=Color3.fromRGB(23,45,71),BorderSizePixel=0},container)
    corner(button,5)
    button.Activated:Connect(function()
        local ok,err=pcall(callback)
        if not ok then
            if ui.layout and (container==ui.houseImport or container==ui.houseExport or container==ui.houseFormat) then ui.layout.say(tostring(err))
            else report(tostring(err)) end
        end
    end)
    return button
end
function ui.number(container,value,minimum,maximum,onChange)
    local input=make("TextBox",{Size=UDim2.new(1,0,0,25),Text=tostring(value),ClearTextOnFocus=false,
        TextSize=10,TextColor3=white,Font=Enum.Font.Code,BackgroundColor3=Color3.fromRGB(13,20,30),BorderSizePixel=0},container)
    corner(input,5)
    input.FocusLost:Connect(function()
        local n=tonumber(input.Text)
        if n and n==n and math.abs(n)<math.huge then
            value=math.clamp(math.floor(n+0.5),minimum,maximum)
            onChange(value)
            configChanged()
        end
        input.Text=tostring(value)
    end)
    return input
end
local config={path="exi_"..player.UserId.."_"..game.PlaceId..".json",loading=false,pending=nil,numbers={}}
function config.status(message)
    report(message)
    if config.label then config.label.Text=message end
end
function config.snapshot()
    local toggles={}
    for key,value in pairs(states) do if key~="houseLayout" and type(value)=="boolean" then toggles[key]=value end end
    local timers={}
    for _,item in ipairs(itemIds) do timers[item]=deadline(item) end
    return {version=1,userId=player.UserId,placeId=game.PlaceId,toggles=toggles,
        options={candyOfferCost=fairyOffers.candyCost,candyOfferCosts=fairyOffers.prices,safeSellHalted=safeSales.halted==true,sellLimitText=saleLimit.text,dustSpending=dustCycle.spending,dustMinimum=dustCycle.reserve,plantOrder=planting.order,bedDelay=BED_DELAY,chopHits=chopHits,chopMode=chopMode,returnMode=returnMode,
            savedCenter=savedCenter and {savedCenter:GetComponents()} or nil},timers=timers}
end
function config.save()
    if type(writefile)~="function" then config.status("Saving unavailable: executor writefile is missing") return false end
    local ok,err=pcall(function() writefile(config.path,HttpService:JSONEncode(config.snapshot())) end)
    config.status(ok and "Config saved" or "Save failed: "..tostring(err))
    return ok
end
function config.validNumber(value,minimum,maximum)
    return type(value)=="number" and value==value and value>=minimum and value<=maximum
end
function config.apply(data)
    assert(type(data)=="table" and data.version==1,"Unsupported config format")
    assert(data.userId==player.UserId and data.placeId==game.PlaceId,"Config belongs to a different player or place")
    assert(type(data.toggles)=="table","Config toggle list is missing")
    config.loading=true
    stopAll()
    -- Restore every selection before starting any automation worker.
    for key,value in pairs(data.toggles) do
        if renderToggle[key] and type(value)=="boolean" then states[key]=value end
    end
    local options=type(data.options)=="table" and data.options or {}
    safeSales.halted=options.safeSellHalted==true
    fairyOffers.candyCost=config.validNumber(options.candyOfferCost,0,1000000000) and math.floor(options.candyOfferCost) or 0
    fairyOffers.prices={}
    for id,cost in pairs(type(options.candyOfferCosts)=="table" and options.candyOfferCosts or {}) do
        if type(id)=="string" and #id<=100 and config.validNumber(cost,1,1000000000) and cost%1==0 then fairyOffers.prices[id]=cost end
    end
    if config.validNumber(options.dustMinimum,1,9007199254740991) then dustCycle.reserve=math.floor(options.dustMinimum) end
    dustCycle.spending=options.dustSpending==true
    local limitOK=pcall(saleLimit.set,type(options.sellLimitText)=="string" and options.sellLimitText or "")
    if not limitOK then saleLimit.set("") end
    if options.plantOrder=="normal" or options.plantOrder=="expensive" then planting.order=options.plantOrder end
    if planting.orderButton then planting.orderButton.Text="PLANT ORDER: "..(planting.order=="expensive" and "EXPENSIVE FIRST" or "NORMAL") end
    if config.validNumber(options.bedDelay,0.05,5) then BED_DELAY=options.bedDelay end
    if config.validNumber(options.chopHits,1,6) then chopHits=math.floor(options.chopHits) end
    if options.chopMode=="Walk" or options.chopMode=="Teleport" then chopMode=options.chopMode end
    if options.returnMode=="Previous" or options.returnMode=="Bed center" or options.returnMode=="Bed_6_5" then returnMode=options.returnMode end
    if type(options.savedCenter)=="table" and #options.savedCenter==12 then
        local valid=true
        for _,value in ipairs(options.savedCenter) do if not config.validNumber(value,-10000000,10000000) then valid=false break end end
        if valid then savedCenter=CFrame.new(table.unpack(options.savedCenter)) end
    end
    local timers=type(data.timers)=="table" and data.timers or {}
    local now=workspace:GetServerTimeNow()
    for _,item in ipairs(itemIds) do
        if config.validNumber(timers[item],0,now+cooldown+1) then parent:SetAttribute("EXINext_"..item,timers[item]) end
    end
    for _,render in pairs(renderToggle) do render() end
    if config.numbers.delay then config.numbers.delay.Text=tostring(math.floor(BED_DELAY*1000)) end
    if config.numbers.hits then config.numbers.hits.Text=tostring(chopHits) end
    if config.numbers.dustMinimum then config.numbers.dustMinimum.Text=tostring(dustCycle.reserve) end
    if config.numbers.candyOfferCost then config.numbers.candyOfferCost.Text=tostring(fairyOffers.candyCost) end
    for _,key in ipairs({"quest","orders","mayor","dig","rearrange","harvest","plant","water","dust","seeds","normalSeeds","gears","tend","LuckyCharm","RainbowDew","fairy","candyFairy","sellBoom","houseUpgrade","gardenUpgrade","pickups","wood","fishing"}) do
        if states[key] then ui.dispatch(key) end
    end
    if sessionOptions.sync then sessionOptions.sync() end
    ui.dispatch("autoReconnect")
    config.loading=false
end
function config.load()
    if type(readfile)~="function" then config.status("Loading unavailable: executor readfile is missing") return false end
    local source=config.path
    local legacy="hardinero_"..player.UserId.."_"..game.PlaceId..".json"
    if type(isfile)=="function" and not isfile(source) then
        if isfile(legacy) then source=legacy
        else config.status("No saved config yet; changes will auto-save") return false end
    end
    local ok,err=pcall(function() config.apply(HttpService:JSONDecode(readfile(source))) end)
    if ok and source~=config.path then config.save() end
    config.loading=false
    config.status(ok and "Saved config restored" or "Load failed: "..tostring(err))
    return ok
end
configChanged=function(force)
    if config.loading or (not force and states.autoSave==false) then return end
    if config.pending then task.cancel(config.pending) end
    config.pending=task.delay(0.4,function()
        config.pending=nil
        if alive then config.save() end
    end)
end
sessionOptions.path="exi_autorun_"..player.UserId.."_"..game.PlaceId..".json"
sessionOptions.raw="https://raw.githubusercontent.com/iaxen/EXIScript/main/EXIScript.lua"
function sessionOptions.say(message)
    if sessionOptions.label then sessionOptions.label.Text=message end
    report(message)
end
function sessionOptions.loader()
    return ("-- EXI AUTORUN\nif game.PlaceId~=%d then return end\npcall(function()\nlocal H=game:GetService('HttpService')\nif type(readfile)~='function' then return end\nlocal ok,p=pcall(function()return H:JSONDecode(readfile(%q))end)\nif not ok or not p.enabled then return end\nlocal env=type(getgenv)=='function' and getgenv() or _G\nif env.EXI_AUTORUN_LOADED then return end\nenv.EXI_AUTORUN_LOADED=true\nlocal f=loadstring(game:HttpGet(%q));if f then f() end\nend)\n"):format(game.PlaceId,sessionOptions.path,sessionOptions.raw)
end
function sessionOptions.queue()
    if sessionOptions.queued or not states.autoExecute then return sessionOptions.queued end
    local queue=queue_on_teleport or queueonteleport or (type(syn)=="table" and syn.queue_on_teleport)
    if type(queue)~="function" then return false end
    local ok=pcall(queue,sessionOptions.loader())
    if ok then sessionOptions.queued=true end
    return ok
end
function sessionOptions.sync()
    local ok,err=pcall(function()
        assert(type(writefile)=="function" and type(readfile)=="function","Executor file access unavailable")
        writefile(sessionOptions.path,HttpService:JSONEncode({enabled=states.autoExecute==true}))
        if not states.autoExecute then
            sessionOptions.say("AUTO EXECUTE: OFF")
            return
        end
        local folder=nil
        if type(isfolder)=="function" then
            for _,path in ipairs({"autoexec","autoexecute"}) do if isfolder(path) then folder=path break end end
        end
        if folder then
            writefile(folder.."/EXI_FUZZOPIA_"..game.PlaceId..".lua",sessionOptions.loader())
        end
        local queued=sessionOptions.queue()
        sessionOptions.say(folder and (queued and "AUTO EXECUTE READY • EXECUTOR AUTOEXEC + TELEPORT" or "AUTO EXECUTE READY • EXECUTOR AUTOEXEC FOLDER") or
            (queued and "TELEPORT AUTO EXECUTE READY • REJOINS NEED EXECUTOR AUTOEXEC SUPPORT" or "AUTO EXECUTE UNSUPPORTED BY THIS EXECUTOR"))
    end)
    if not ok then sessionOptions.say("AUTO EXECUTE UNAVAILABLE: "..tostring(err)) end
end
auxiliaryConnections[#auxiliaryConnections+1]=Players.PlayerAdded:Connect(function(other)
    if not alive or not states.leaveOnJoin or other==player then return end
    sessionOptions.intentionalLeave=true
    if sessionOptions.reconnect then sessionOptions.reconnect.pending=false end
    if states.autoSave then config.save() end
    player:Kick("EXI: left because another player joined.")
end)
auxiliaryConnections[#auxiliaryConnections+1]=player.OnTeleport:Connect(function()
    if alive and states.autoExecute then sessionOptions.queue() end
end)
sessionOptions.reconnect={pending=false,attempts=0,nextAt=0}
function sessionOptions.reconnectSay(message)
    if sessionOptions.reconnectLabel then sessionOptions.reconnectLabel.Text=message end
end
function sessionOptions.connectionError(message)
    message=tostring(message or ""):lower()
    if message:find("exi:",1,true) then return false end
    local code=tonumber(message:match("error%s*code%s*:%s*(%d+)") or message:match("%((%d%d%d)%)"))
    if code then return code==277 or code==279 end
    return message:find("lost connection",1,true)~=nil or message:find("connection was lost",1,true)~=nil
        or message:find("check your internet connection",1,true)~=nil or message:find("connection timed out",1,true)~=nil
        or message:find("failed to connect",1,true)~=nil
end
function sessionOptions.captureError(message)
    if not alive or not states.autoReconnect or sessionOptions.intentionalLeave or not sessionOptions.connectionError(message) then return end
    local state=sessionOptions.reconnect
    if state.pending then return end
    state.pending=true
    state.attempts=0
    state.nextAt=os.clock()+3
    if states.autoSave then pcall(config.save) end
    if states.autoExecute then sessionOptions.queue() end
    sessionOptions.reconnectSay("CONNECTION LOST • RECONNECTING IN 3 SECONDS")
end
function sessionOptions.errorPrompt()
    local ok,message=pcall(function()
        local core=game:GetService("CoreGui")
        local root=core:FindFirstChild("RobloxPromptGui")
        local prompt=root and root:FindFirstChild("ErrorPrompt",true)
        if not prompt or not prompt:IsA("GuiObject") or not prompt.Visible then return end
        local texts={}
        for _,object in ipairs(prompt:GetDescendants()) do
            if object:IsA("TextLabel") and object.Visible and object.Text~="" then texts[#texts+1]=object.Text end
        end
        return table.concat(texts," ")
    end)
    if ok then return message end
end
function sessionOptions.retryReconnect()
    local state=sessionOptions.reconnect
    if not state.pending or not alive or not states.autoReconnect or sessionOptions.intentionalLeave or os.clock()<state.nextAt then return end
    state.attempts=state.attempts+1
    local delay=math.min(30,3*2^math.min(state.attempts,4))
    state.nextAt=os.clock()+delay
    if states.autoExecute then sessionOptions.queue() end
    local same=state.attempts<=2 and type(game.JobId)=="string" and game.JobId~=""
    sessionOptions.reconnectSay("RECONNECT ATTEMPT "..state.attempts..(same and " • SAME SERVER" or " • AVAILABLE SERVER"))
    local ok,err=pcall(function()
        local service=game:GetService("TeleportService")
        if same then service:TeleportToPlaceInstance(game.PlaceId,game.JobId,player)
        else service:Teleport(game.PlaceId,player) end
    end)
    if not ok then sessionOptions.reconnectSay("RECONNECT RETRY IN "..delay.."S • "..tostring(err)) end
end
pcall(function()
    local service=game:GetService("GuiService")
    auxiliaryConnections[#auxiliaryConnections+1]=service.ErrorMessageChanged:Connect(sessionOptions.captureError)
end)
pcall(function()
    auxiliaryConnections[#auxiliaryConnections+1]=game:GetService("TeleportService").TeleportInitFailed:Connect(function(who,_,message)
        if who~=player or not sessionOptions.reconnect.pending then return end
        sessionOptions.reconnectSay("TELEPORT FAILED • RETRYING • "..tostring(message))
    end)
end)
jobs.reconnectMonitor=task.defer(function()
    while alive do
        if states.autoReconnect and not sessionOptions.intentionalLeave then
            local message=sessionOptions.errorPrompt()
            if message then sessionOptions.captureError(message) end
            sessionOptions.retryReconnect()
        end
        task.wait(0.5)
    end
end)
ui.events={lastRefresh=0,counts={},seen={},keys={},probLabels={},total=0,
    ids={"GoldenHour","FishingFrenzy","BlessingRain","MarketBoom","LuckyEggs","BountifulForest","StarShower"}}
ui.events.path="exi_event_history_"..game.PlaceId..".json"
function ui.events.saveHistory()
    if type(writefile)=="function" then
        pcall(writefile,ui.events.path,HttpService:JSONEncode({version=1,counts=ui.events.counts,keys=ui.events.keys}))
    end
end
function ui.events.loadHistory()
    if type(readfile)~="function" then return end
    local ok,data=pcall(function()return HttpService:JSONDecode(readfile(ui.events.path))end)
    if not ok or type(data)~="table" or data.version~=1 then return end
    for _,id in ipairs(ui.events.ids) do
        local count=type(data.counts)=="table" and data.counts[id]
        if type(count)=="number" and count>=0 and count<1e9 and count==count then
            ui.events.counts[id]=math.floor(count)
            ui.events.total=ui.events.total+math.floor(count)
        end
    end
    for _,key in ipairs(type(data.keys)=="table" and data.keys or {}) do
        if type(key)=="string" and #key<200 and #ui.events.keys<256 then
            ui.events.keys[#ui.events.keys+1]=key ui.events.seen[key]=true
        end
    end
end
function ui.events.observe(event,ends,now)
    if type(event)~="string" or ends<=now then ui.events.pendingKey=nil return end
    local known=false
    for _,id in ipairs(ui.events.ids) do if event==id then known=true break end end
    if not known then return end
    local key=tostring(game.JobId).."|"..event.."|"..tostring(ends)
    if ui.events.seen[key] then return end
    if ui.events.pendingKey~=key then ui.events.pendingKey=key ui.events.pendingAt=os.clock() return end
    if os.clock()-ui.events.pendingAt<0.75 then return end
    ui.events.seen[key]=true
    ui.events.keys[#ui.events.keys+1]=key
    if #ui.events.keys>256 then ui.events.seen[table.remove(ui.events.keys,1)]=nil end
    ui.events.counts[event]=(ui.events.counts[event] or 0)+1
    ui.events.total=ui.events.total+1
    ui.events.saveHistory()
end
function ui.events.probability(id)
    if ui.events.total==0 then return nil,0,0 end
    local count=ui.events.counts[id] or 0
    return count/ui.events.total*100,count,ui.events.total
end
ui.events.loadHistory()
function ui.events.refresh()
    if not ui.events.current or os.clock()-ui.events.lastRefresh<0.25 then return end
    ui.events.lastRefresh=os.clock()
    local now=workspace:GetServerTimeNow()
    local event=workspace:GetAttribute("IslandEvent")
    local ends=tonumber(workspace:GetAttribute("IslandEventEndsAt")) or 0
    local nextAt=tonumber(workspace:GetAttribute("IslandEventNextAt"))
    local active=type(event)=="string" and event~="" and ends>now
    ui.events.observe(event,ends,now)
    local function clock(seconds)
        seconds=math.max(0,math.ceil(seconds))
        return ("%02d:%02d"):format(math.floor(seconds/60),seconds%60)
    end
    ui.events.current.Text="CURRENT: "..(active and event:gsub("(%l)(%u)","%1 %2"):upper() or "NONE")
    ui.events.ends.Text="ENDS IN: "..(active and clock(ends-now) or "—")
    ui.events.next.Text="NEXT EVENT IN: "..(nextAt and clock(nextAt-now) or "NOT AVAILABLE")
    ui.events.kind.Text="NEXT EVENT TYPE: UNKNOWN"
    if ui.events.sampleLabel then ui.events.sampleLabel.Text="RECORDED EVENTS: "..ui.events.total end
    for id,label in pairs(ui.events.probLabels) do
        local probability,count,total=ui.events.probability(id)
        local title=id:gsub("(%l)(%u)","%1 %2"):upper()
        label.Text=probability and ("%s: %.1f%% (%d/%d)"):format(title,probability,count,total) or (title..": NO DATA")
    end
end
-- House layout import uses the same owned-interior and HouseAction API as HomeDecorUI.
ui.layout={version=1,maxItems=500}
function ui.layout.say(message)
    message = tostring(message):gsub("^.-:%d+:%s*", "")
    report(message)
    if ui.layout.label then ui.layout.label.Text=message end
end
function ui.layout.interior()
    local village=workspace:FindFirstChild("CozyVillage")
    local interiors=village and village:FindFirstChild("HouseInteriors")
    if interiors then
        for _,model in ipairs(interiors:GetChildren()) do
            if model:IsA("Model") and model:GetAttribute("OwnerUserId")==player.UserId then return model end
        end
    end
end
function ui.layout.catalog()
    return require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
end
function ui.layout.finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function ui.layout.floors(interior)
    local shell = interior:FindFirstChild("Shell")
    assert(shell, "Interior shell not loaded. Enter your own house first.")

    local parts = {}
    for _, part in ipairs(shell:GetChildren()) do
        if part:IsA("BasePart") and part:GetAttribute("InteriorFloor") and part.CFrame.UpVector.Y > 0.98 then
            parts[#parts + 1] = part
        end
    end

    table.sort(parts, function(a, b)
        if math.abs(a.Position.Y - b.Position.Y) > 0.25 then
            return a.Position.Y < b.Position.Y
        end
        local areaA = a.Size.X * a.Size.Z
        local areaB = b.Size.X * b.Size.Z
        if areaA ~= areaB then
            return areaA > areaB
        end
        return a.Name < b.Name
    end)

    local floors = {}
    for _, part in ipairs(parts) do
        local floor = floors[#floors]
        if not floor or math.abs(part.Position.Y - floor.base.Position.Y) > 0.5 then
            floor = { base = part, parts = {} }
            floors[#floors + 1] = floor
        end
        floor.parts[#floor.parts + 1] = part
    end
    assert(#floors > 0, "Interior floors not loaded. Enter your own house first.")

    for index, floor in ipairs(floors) do
        local base = floor.base
        local minX, minZ = math.huge, math.huge
        local maxX, maxZ = -math.huge, -math.huge
        for _, part in ipairs(floor.parts) do
            for _, sign in ipairs({ {-1, -1}, {1, -1}, {1, 1}, {-1, 1} }) do
                local corner = Vector3.new(sign[1] * part.Size.X / 2, 0, sign[2] * part.Size.Z / 2)
                local point = base.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(corner))
                minX, maxX = math.min(minX, point.X), math.max(maxX, point.X)
                minZ, maxZ = math.min(minZ, point.Z), math.max(maxZ, point.Z)
            end
        end
        floor.Name = "Floor " .. index
        floor.CFrame = base.CFrame * CFrame.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
        floor.Position = floor.CFrame.Position
        floor.Size = Vector3.new(maxX - minX, base.Size.Y, maxZ - minZ)
    end
    return floors
end

function ui.layout.polygonArea(points)
    local area = 0
    for index, a in ipairs(points) do
        local b = points[index % #points + 1]
        area = area + a.x * b.z - b.x * a.z
    end
    return math.abs(area) / 2
end

function ui.layout.clipHalfPlane(points, a, b, keepInside)
    local result = {}
    if #points == 0 then
        return result
    end
    local function distance(point)
        return (b.x - a.x) * (point.z - a.z) - (b.z - a.z) * (point.x - a.x)
    end
    local previous = points[#points]
    local before = distance(previous)
    local previousInside = keepInside and before >= 0 or not keepInside and before <= 0
    for _, current in ipairs(points) do
        local after = distance(current)
        local currentInside = keepInside and after >= 0 or not keepInside and after <= 0
        if currentInside ~= previousInside then
            local t = before / (before - after)
            result[#result + 1] = {
                x = previous.x + (current.x - previous.x) * t,
                z = previous.z + (current.z - previous.z) * t,
            }
        end
        if currentInside then
            result[#result + 1] = current
        end
        previous, before, previousInside = current, after, currentInside
    end
    return result
end

function ui.layout.subtractSupport(polygon, support)
    local outside = {}
    local remaining = polygon
    for index, a in ipairs(support) do
        local b = support[index % #support + 1]
        local piece = ui.layout.clipHalfPlane(remaining, a, b, false)
        if ui.layout.polygonArea(piece) > 0.000001 then
            outside[#outside + 1] = piece
        end
        remaining = ui.layout.clipHalfPlane(remaining, a, b, true)
        if #remaining == 0 then
            break
        end
    end
    return outside
end

function ui.layout.supported(floor, entry, size, angle)
    local footprint = {}
    local cosine, sine = math.cos(angle), math.sin(angle)
    for _, sign in ipairs({ {-1, -1}, {1, -1}, {1, 1}, {-1, 1} }) do
        local x, z = sign[1] * size.X / 2, sign[2] * size.Z / 2
        footprint[#footprint + 1] = {
            x = entry.x + cosine * x + sine * z,
            z = entry.z - sine * x + cosine * z,
        }
    end

    local uncovered = { footprint }
    for _, part in ipairs(floor.parts) do
        local support = {}
        for _, sign in ipairs({ {-1, -1}, {1, -1}, {1, 1}, {-1, 1} }) do
            local corner = Vector3.new(sign[1] * (part.Size.X / 2 + 0.05), 0, sign[2] * (part.Size.Z / 2 + 0.05))
            local point = floor.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(corner))
            support[#support + 1] = { x = point.X, z = point.Z }
        end
        local remaining = {}
        for _, polygon in ipairs(uncovered) do
            for _, piece in ipairs(ui.layout.subtractSupport(polygon, support)) do
                remaining[#remaining + 1] = piece
            end
        end
        uncovered = remaining
        if #uncovered == 0 then
            return true
        end
    end
    local area = 0
    for _, polygon in ipairs(uncovered) do
        area = area + ui.layout.polygonArea(polygon)
    end
    return area <= 0.001
end

function ui.layout.placed(interior)
    local folder=interior:FindFirstChild("Furniture")
    local result={}
    if folder then
        for _,model in ipairs(folder:GetChildren()) do
            local index=model:GetAttribute("Index")
            if model:IsA("Model") and ui.layout.finite(index) then result[#result+1]={model=model,index=index,id=model.Name} end
        end
    end
    table.sort(result,function(a,b)return a.index<b.index end)
    return result
end
function ui.layout.bag(id)
    for _,name in ipairs({"Inventory","leaderstats"}) do
        local folder=player:FindFirstChild(name)
        local value=folder and folder:FindFirstChild("F_"..id)
        if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then return math.max(0,value.Value) end
    end
    return 0
end
function ui.layout.atTarget(model,row,floors)
    local position=model:GetPivot().Position
    if (Vector2.new(position.X,position.Z)-Vector2.new(row.position.X,row.position.Z)).Magnitude>0.9 then return false end
    local cf,size=model:GetBoundingBox()
    local bottom=cf.Position.Y-size.Y/2
    local closest,best=nil,math.huge
    for index,floor in ipairs(floors) do
        local surface = floor.Position.Y + floor.Size.Y / 2
        local distance = math.min(math.abs(bottom - surface), math.abs(position.Y - surface))
        if distance<best then closest,best=index,distance end
    end
    if closest~=row.floor then return false end
    local yaw=tonumber(model:GetAttribute("Yaw"))
    if yaw==nil then local _,angle=model:GetPivot():ToOrientation() yaw=math.deg(angle) end
    return math.abs((yaw-row.yaw+180)%360-180)<2
end
function ui.layout.decode(text)
    assert(type(text)=="string" and #text>0 and #text<=524288,"Paste a JSON layout under 512 KB.")
    local data=HttpService:JSONDecode(text)
    assert(type(data)=="table" and data.version==1,"Layout version must be 1.")
    assert(data.coordinateSpace=="floor-local","Layout coordinateSpace must be floor-local.")
    assert(type(data.items)=="table" and #data.items>0 and #data.items<=ui.layout.maxItems,"Layout must contain 1–500 items.")
    local total=0
    for key in pairs(data.items) do
        total=total+1
        assert(type(key)=="number" and key%1==0 and key>=1 and key<=#data.items,"Layout items must be a consecutive array.")
    end
    assert(total==#data.items,"Layout item array has gaps.")
    return data
end
function ui.layout.plan(data)
    local interior=ui.layout.interior()
    assert(interior,"Enter your own house first so its interior can load.")
    local floors=ui.layout.floors(interior)
    local items=ui.layout.catalog()
    local placed=ui.layout.placed(interior)
    local rows,used,bag,missing={},{},{},{}
    local level=tonumber(player:GetAttribute("HouseLevel")) or 1
    local wallCount,furnitureCount,newWalls,newFurniture=0,0,0,0
    for _,entry in ipairs(placed) do
        if items.WallPieces[entry.id] then wallCount=wallCount+1
        elseif not items.FloorPieces[entry.id] and entry.id~="RoomSign" then furnitureCount=furnitureCount+1 end
    end
    for index,entry in ipairs(data.items) do
        assert(type(entry)=="table","Invalid item "..index)
        local info=type(entry.id)=="string" and items.Furniture[entry.id]
        assert(info and info.Size,"Unknown furniture ID at item "..index..": "..tostring(entry.id))
        local floorIndex=entry.floor or 1
        assert(ui.layout.finite(floorIndex) and floorIndex%1==0 and floors[floorIndex],"Floor unavailable for item "..index)
        assert(ui.layout.finite(entry.x) and ui.layout.finite(entry.z),"Item "..index.." needs finite x and z coordinates.")
        local yaw=entry.yaw or 0
        assert(ui.layout.finite(yaw) and math.abs(yaw/45-math.floor(yaw/45+0.5))<0.00001,"Item "..index.." rotation must use 45-degree steps.")
        yaw=yaw%360
        local floor=floors[floorIndex]
        local _,floorYaw=floor.CFrame:ToOrientation()
        local angle=math.rad(yaw)-floorYaw
        assert(ui.layout.supported(floor, entry, info.Size, angle),
            ("Item %d (%s) on floor %d: footprint crosses an edge or stair opening. Floor %.1f x %.1f studs, %d section(s).")
                :format(index, entry.id, floorIndex, floor.Size.X, floor.Size.Z, #floor.parts))
        rows[#rows+1]={id=entry.id,floor=floorIndex,x=entry.x,z=entry.z,yaw=yaw,size=info.Size,
            position=floor.CFrame:PointToWorldSpace(Vector3.new(entry.x,floor.Size.Y/2,entry.z))}
    end
    -- Preserve exact existing matches before allocating furniture to moves.
    for _,row in ipairs(rows) do
        for _,entry in ipairs(placed) do
            if not used[entry.index] and entry.id==row.id and ui.layout.atTarget(entry.model,row,floors) then
                row.sourceIndex=entry.index row.action="keep" used[entry.index]=true break
            end
        end
    end
    local keeps,moves,places=0,0,0
    for _,row in ipairs(rows) do
        if not row.action then
            for _,entry in ipairs(placed) do
                if not used[entry.index] and entry.id==row.id then
                    row.sourceIndex=entry.index row.action="move" used[entry.index]=true break
                end
            end
        end
        if not row.action then
            row.action="place"
            local info=items.Furniture[row.id]
            if bag[row.id]==nil then bag[row.id]=ui.layout.bag(row.id) end
            if bag[row.id]>0 then bag[row.id]=bag[row.id]-1 else missing[row.id]=(missing[row.id] or 0)+1 end
            if info.HouseLevel and level < info.HouseLevel then
                row.blockReason = "HOUSE LEVEL " .. tostring(info.HouseLevel) .. " REQUIRED"
            end
            if items.WallPieces[row.id] then newWalls=newWalls+1
            elseif not items.FloorPieces[row.id] and row.id~="RoomSign" then newFurniture=newFurniture+1 end
        end
        if row.action=="keep" then keeps=keeps+1 elseif row.action=="move" then moves=moves+1 else places=places+1 end
    end
    -- Capacity is checked per placement so an incomplete layout can still make progress.
    local warnings = {}
    if wallCount + newWalls > items.WallLimit(level) then
        warnings[#warnings + 1] = "Some new walls may exceed the house limit."
    end
    if furnitureCount + newFurniture > items.FurnitureLimit(level) then
        warnings[#warnings + 1] = "Some new furniture may exceed the house limit."
    end
    local absent={}
    for id,count in pairs(missing) do absent[#absent+1]=id.." x"..count end
    table.sort(absent)
    return {interior=interior,floors=floors,rows=rows,missing=absent,warnings=warnings,keeps=keeps,moves=moves,places=places}
end
function ui.layout.clearPreview()
    if ui.layout.preview then ui.layout.preview:Destroy() ui.layout.preview=nil end
end
function ui.layout.inspect(preview)
    assert(not states.houseLayout,"Stop the current build before changing the layout.")
    local plan=ui.layout.plan(ui.layout.decode(ui.layout.input.Text))
    ui.layout.clearPreview()
    if preview then
        local folder=Instance.new("Folder") folder.Name="EXIHousePreview" folder.Parent=workspace ui.layout.preview=folder
        for _,row in ipairs(plan.rows) do
            local part=Instance.new("Part")
            part.Name=row.id part.Size=row.size part.Anchored=true
            part.CanCollide=false part.CanTouch=false part.CanQuery=false
            part.Transparency=0.65 part.Color=blue part.Material=Enum.Material.ForceField
            part.CFrame=CFrame.new(row.position+Vector3.new(0,row.size.Y/2,0))*CFrame.Angles(0,math.rad(row.yaw),0)
            part.Parent=folder
        end
    end
    ui.layout.say(("KEEP %d • MOVE %d • PLACE %d"):format(plan.keeps,plan.moves,plan.places)..
        (#plan.missing>0 and ("\nMISSING: "..table.concat(plan.missing,", ")) or "\nALL REQUIRED ITEMS AVAILABLE")..
        (#plan.warnings>0 and ("\n"..table.concat(plan.warnings," ")) or ""))
    return plan
end
function ui.layout.export()
    assert(not states.houseLayout,"Stop building before exporting.")
    local interior=ui.layout.interior()
    assert(interior,"Enter your own house first.")
    local floors=ui.layout.floors(interior)
    local items=ui.layout.catalog()
    local data={version=1,coordinateSpace="floor-local",name="My house",items={},context={houseLevel=player:GetAttribute("HouseLevel"),floors={},bag={},catalog={}}}
    for i,floor in ipairs(floors) do data.context.floors[i]={floor=i,surface=floor.Name,width=floor.Size.X,depth=floor.Size.Z,sections=#floor.parts} end
    for id,info in pairs(items.Furniture) do
        if info.Size then data.context.catalog[id]={name=info.DisplayName,size={info.Size.X,info.Size.Y,info.Size.Z}} end
        local count=ui.layout.bag(id) if count>0 then data.context.bag[id]=count end
    end
    for _,entry in ipairs(ui.layout.placed(interior)) do
        if items.Furniture[entry.id] then
            local cf,size=entry.model:GetBoundingBox()
            local bottom=cf.Position.Y-size.Y/2
            local best,index=math.huge,1
            for i,floor in ipairs(floors) do
                local distance=math.abs(bottom-(floor.Position.Y+floor.Size.Y/2))
                if distance<best then best,index=distance,i end
            end
            local point=floors[index].CFrame:PointToObjectSpace(entry.model:GetPivot().Position)
            local yaw=tonumber(entry.model:GetAttribute("Yaw"))
            if not yaw then local _,angle=entry.model:GetPivot():ToOrientation() yaw=math.deg(angle) end
            data.items[#data.items+1]={id=entry.id,floor=index,x=math.floor(point.X*100)/100,z=math.floor(point.Z*100)/100,yaw=math.floor(yaw/45+0.5)*45%360}
        end
    end
    local text=HttpService:JSONEncode(data)
    ui.layout.input.Text=text
    if type(setclipboard)=="function" then setclipboard(text) end
    if type(writefile)=="function" then pcall(writefile,"exi_house_export.json",text) end
    ui.layout.say("HOUSE EXPORTED • COPY THE JSON OR SEND exi_house_export.json WITH YOUR DESIGN")
end
-- Read-only export of another player's already replicated interior.
function ui.layout.interiorFor(ownerId)
    local village = workspace:FindFirstChild("CozyVillage")
    local interiors = village and village:FindFirstChild("HouseInteriors")
    if interiors then
        for _, model in ipairs(interiors:GetChildren()) do
            if model:IsA("Model") and tonumber(model:GetAttribute("OwnerUserId")) == ownerId then
                return model
            end
        end
    end
end

function ui.layout.refreshVisited()
    local selected = ui.layout.visitedOwnerId
    if not selected then
        local current = tonumber(player:GetAttribute("InHouse"))
        if current and current ~= player.UserId then
            selected = current
            ui.layout.visitedOwnerId = current
        end
    end
    local owner = selected and Players:GetPlayerByUserId(selected)
    if ui.layout.visitedLabel then
        ui.layout.visitedLabel.Text = selected
            and ("SELECTED: " .. (owner and owner.Name or tostring(selected)))
            or "SELECT A PLAYER OR ENTER THEIR HOUSE"
    end
    local list = ui.layout.visitedChoices
    if not list then
        return
    end
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiButton") then
            child:Destroy()
        end
    end
    local others = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            others[#others + 1] = other
        end
    end
    table.sort(others, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)
    for _, other in ipairs(others) do
        local ownerId = other.UserId
        local loaded = ui.layout.interiorFor(ownerId) ~= nil
        local label = (selected == ownerId and "✓ " or "") .. other.Name
            .. (loaded and " • LOADED" or " • VISIT FIRST")
        ui.button(list, label, function()
            ui.layout.visitedOwnerId = ownerId
            ui.layout.refreshVisited()
        end)
    end
end

function ui.layout.exportVisited()
    assert(not states.houseLayout, "Stop building before exporting.")
    local ownerId = ui.layout.visitedOwnerId or tonumber(player:GetAttribute("InHouse"))
    assert(ownerId and ownerId ~= player.UserId, "Select another player or enter their house first.")
    local interior = ui.layout.interiorFor(ownerId)
    assert(interior, "That house is not loaded. Visit it, wait for furniture to load, then refresh.")
    local furniture = interior:FindFirstChild("Furniture")
    assert(furniture, "House furniture has not loaded yet. Wait inside the house, then try again.")
    local floors = ui.layout.floors(interior)
    local catalog = ui.layout.catalog()
    local owner = Players:GetPlayerByUserId(ownerId)
    local name = owner and owner.Name or tostring(ownerId)
    local data = {
        version = 1,
        coordinateSpace = "floor-local",
        name = name .. " house",
        items = {},
        context = { ownerUserId = ownerId, ownerName = name, snapshot = "loaded-furniture", floors = {} },
    }
    for index, floor in ipairs(floors) do
        data.context.floors[index] = {
            floor = index, surface = floor.Name, width = floor.Size.X,
            depth = floor.Size.Z, sections = #floor.parts,
        }
    end
    local skipped = 0
    for _, entry in ipairs(ui.layout.placed(interior)) do
        if catalog.Furniture[entry.id] then
            local cf, size = entry.model:GetBoundingBox()
            local bottom = cf.Position.Y - size.Y / 2
            local best, index = math.huge, 1
            for floorIndex, floor in ipairs(floors) do
                local distance = math.abs(bottom - (floor.Position.Y + floor.Size.Y / 2))
                if distance < best then
                    best, index = distance, floorIndex
                end
            end
            local point = floors[index].CFrame:PointToObjectSpace(entry.model:GetPivot().Position)
            local yaw = tonumber(entry.model:GetAttribute("Yaw"))
            if not yaw then
                local _, angle = entry.model:GetPivot():ToOrientation()
                yaw = math.deg(angle)
            end
            data.items[#data.items + 1] = {
                id = entry.id, floor = index, x = math.floor(point.X * 100) / 100,
                z = math.floor(point.Z * 100) / 100, yaw = math.floor(yaw / 45 + 0.5) * 45 % 360,
            }
        else
            skipped = skipped + 1
        end
    end
    assert(#data.items > 0, "No supported furniture is loaded. Wait for the house to load before exporting.")
    assert(#data.items <= ui.layout.maxItems, "This house exceeds the layout import item limit.")
    assert(ui.layout.interiorFor(ownerId) == interior, "House unloaded during export. Visit it and try again.")
    local text = HttpService:JSONEncode(data)
    assert(#text < 200000, "Export is too large for the layout text box.")
    ui.layout.input.Text = text
    local filename = "exi_house_" .. tostring(ownerId) .. "_layout.json"
    local saved = type(writefile) == "function" and pcall(writefile, filename, text)
    if type(setclipboard) == "function" then
        pcall(setclipboard, text)
    end
    if saved and ui.layout.path then
        ui.layout.path.Text = filename
    end
    ui.layout.say(("EXPORTED %d LOADED ITEMS FROM %s"):format(#data.items, name)
        .. (saved and (" • " .. filename) or " • JSON LOADED")
        .. (skipped > 0 and (" • UNKNOWN ITEMS SKIPPED: " .. skipped) or ""))
    if ui.layout.visitedLabel then
        ui.layout.visitedLabel.Text = "EXPORTED: " .. name .. " • " .. #data.items .. " LOADED ITEMS"
    end
end

function ui.layout.cancel()
    stop("houseLayout")
    ui.layout.clearPreview()
    ui.layout.clearSay("HOUSE JOB STOPPED • COMPLETED CHANGES REMAIN")
end
sessionOptions.houseCleanup=function()
    ui.layout.clearPreview()
    if ui.layout.feedbackConnection then
        ui.layout.feedbackConnection:Disconnect()
        ui.layout.feedbackConnection=nil
    end
end
function ui.layout.roomFor(id, interior)
    local items = ui.layout.catalog()
    local level = tonumber(player:GetAttribute("HouseLevel")) or 1
    local info = items.Furniture[id]
    if info.HouseLevel and level < info.HouseLevel then
        return false, "HOUSE LEVEL " .. tostring(info.HouseLevel) .. " REQUIRED"
    end
    local walls, furniture = 0, 0
    for _, entry in ipairs(ui.layout.placed(interior)) do
        if items.WallPieces[entry.id] then
            walls = walls + 1
        elseif not items.FloorPieces[entry.id] and entry.id ~= "RoomSign" then
            furniture = furniture + 1
        end
    end
    if items.WallPieces[id] and walls >= items.WallLimit(level) then
        return false, "PARTITION-WALL LIMIT"
    end
    if not items.WallPieces[id] and not items.FloorPieces[id] and id ~= "RoomSign"
        and furniture >= items.FurnitureLimit(level) then
        return false, "FURNITURE LIMIT"
    end
    return true
end

function ui.layout.balance(name)
    for _, folderName in ipairs({"leaderstats", "Inventory"}) do
        local folder = player:FindFirstChild(folderName)
        local value = folder and folder:FindFirstChild(name)
        if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
            return value.Value
        end
    end
end

function ui.layout.purchaseReady(row, plan)
    local room, reason = ui.layout.roomFor(row.id, plan.interior)
    if not room then return false, reason end
    local info = ui.layout.catalog().Furniture[row.id]
    if info.Robux then return false, "ROBUX PURCHASE REQUIRED" end
    if info.Event and workspace:GetAttribute("Festival") ~= info.Event then
        return false, "EVENT UNAVAILABLE: " .. tostring(info.Event)
    end
    for _, name in ipairs({"Coins", "Wood", "Candy"}) do
        local price = tonumber(info[name]) or 0
        if price > 0 then
            local balance = ui.layout.balance(name)
            if balance == nil then return false, name:upper() .. " NOT LOADED" end
            if balance < price then
                return false, ("NEED %s %s; HAVE %s"):format(price, name:upper(), balance)
            end
        end
    end
    return true
end

function ui.layout.live(plan)
    if not enabled("houseLayout") then return false end
    assert(player:GetAttribute("InHouse") == player.UserId, "You left your own house.")
    assert(ui.layout.interior() == plan.interior, "Your house interior changed.")
    return true
end

function ui.layout.reason(fallback, serial)
    if (ui.layout.feedbackSerial or 0) > (serial or 0) and ui.layout.feedbackText then
        return fallback .. ": " .. ui.layout.feedbackText
    end
    return fallback
end

function ui.layout.send(plan, ...)
    while os.clock() - (plan.lastSent or -math.huge) < (plan.retryPace or 0) do
        if not ui.layout.live(plan) then return false end
        task.wait()
    end
    if not ui.layout.live(plan) then return false end
    plan.lastSent = os.clock()
    fire("HouseAction", ...)
    return true
end

function ui.layout.receipt(row, plan, request)
    plan.claimed = plan.claimed or {}
    for _, entry in ipairs(ui.layout.placed(plan.interior)) do
        local expected = request.action == "move" and entry.index == row.sourceIndex
            or request.action == "place" and not request.before[entry.index]
        if expected and entry.id == row.id and (not plan.claimed[entry.index] or plan.claimed[entry.index] == row)
            and ui.layout.atTarget(entry.model, row, plan.floors) then
            row.confirmedIndex = entry.index
            plan.claimed[entry.index] = row
            row.request = nil
            return true
        end
    end
    return false
end

function ui.layout.placeRow(row, plan)
    if not ui.layout.live(plan) then return false, "STOPPED" end
    plan.claimed = plan.claimed or {}
    for _, entry in ipairs(ui.layout.placed(plan.interior)) do
        if entry.index == row.confirmedIndex and entry.id == row.id
            and ui.layout.atTarget(entry.model, row, plan.floors) then
            plan.claimed[entry.index] = row
            return true
        end
    end
    local request = row.request
    if request and ui.layout.receipt(row, plan, request) then return true end
    if row.action == "keep" then
        for _, entry in ipairs(ui.layout.placed(plan.interior)) do
            if entry.index == row.sourceIndex and entry.id == row.id
                and ui.layout.atTarget(entry.model, row, plan.floors) then
                row.confirmedIndex = entry.index
                plan.claimed[entry.index] = row
                return true
            end
        end
        return false, "EXISTING FURNITURE CHANGED"
    end
    if request and request.action == "place" and ui.layout.bag(row.id) < request.bagBefore then
        -- Inventory was charged: keep reconciling this request instead of placing/buying another copy.
        return false, ui.layout.reason("INVENTORY USED; PLACEMENT STILL PENDING", request.serial)
    end
    if request and request.attempts >= 3 then
        return false, ui.layout.reason("PLACEMENT RETRY LIMIT", request.serial)
    end
    local before, existing = {}, nil
    for _, entry in ipairs(ui.layout.placed(plan.interior)) do
        before[entry.index] = true
        if entry.index == row.sourceIndex and entry.id == row.id then existing = entry.model end
    end
    if row.action == "move" and not existing then return false, "SOURCE FURNITURE UNAVAILABLE" end
    local bagBefore = ui.layout.bag(row.id)
    if row.action == "place" then
        if bagBefore <= 0 then return false, "MISSING" end
        if plan.pendingBuys then plan.pendingBuys[row.id] = nil end
        local room, reason = ui.layout.roomFor(row.id, plan.interior)
        if not room then return false, reason end
    end
    request = {
        action = row.action, before = request and request.before or before,
        bagBefore = request and request.bagBefore or bagBefore,
        attempts = (request and request.attempts or 0) + 1,
        serial = ui.layout.feedbackSerial or 0,
    }
    row.request = request
    if row.action == "move" then
        if not ui.layout.send(plan, "move", row.sourceIndex, row.position, row.yaw) then return false, "STOPPED" end
    else
        if not ui.layout.send(plan, "place", row.id, row.position, row.yaw) then return false, "STOPPED" end
    end
    local started = os.clock()
    repeat
        if not ui.layout.live(plan) then return false, "STOPPED" end
        if ui.layout.receipt(row, plan, request) then return true end
        task.wait()
    until os.clock() - started >= 4
    plan.retryPace = math.min(0.5, (plan.retryPace or 0) + 0.1)
    return false, ui.layout.reason("PLACEMENT NOT CONFIRMED", request.serial)
end

function ui.layout.buyOne(row, plan)
    if not ui.layout.live(plan) then return false, "STOPPED" end
    plan.pendingBuys = plan.pendingBuys or {}
    if ui.layout.bag(row.id) > 0 then
        plan.pendingBuys[row.id] = nil
        return true
    end
    local request = plan.pendingBuys[row.id]
    if request and request.lastPass == (plan.pass or 0) then
        return false, ui.layout.reason("BUY STILL PENDING", request.serial)
    end
    if not request then
        local ready, reason = ui.layout.purchaseReady(row, plan)
        if not ready then return false, reason end
        request = { before = ui.layout.bag(row.id), serial = ui.layout.feedbackSerial or 0 }
        plan.pendingBuys[row.id] = request
        ui.layout.say("BUYING: " .. row.id)
        if not ui.layout.send(plan, "buy", row.id) then return false, "STOPPED" end
    end
    -- Reconcile an unanswered buy; never send a duplicate paid request on a timeout.
    request.lastPass = plan.pass or 0
    local started = os.clock()
    repeat
        if not ui.layout.live(plan) then return false, "STOPPED" end
        if ui.layout.bag(row.id) > request.before then
            plan.pendingBuys[row.id] = nil
            return true
        end
        task.wait()
    until os.clock() - started >= 4
    plan.retryPace = math.min(0.5, (plan.retryPace or 0) + 0.1)
    return false, ui.layout.reason("BUY NOT CONFIRMED", request.serial)
end

function ui.layout.finishRow(row, plan, buyMissing)
    plan.reserved = plan.reserved or {}
    if plan.reserved[row.id] and plan.reserved[row.id] ~= row then
        return false, "WAITING FOR EARLIER COPY"
    end
    local confirmed, reason = ui.layout.placeRow(row, plan)
    if confirmed then
        if plan.reserved[row.id] == row then plan.reserved[row.id] = nil end
        return true
    end
    if reason ~= "MISSING" or not buyMissing or row.request then return false, reason end
    local bought, buyReason = ui.layout.buyOne(row, plan)
    if not bought then return false, buyReason end
    plan.reserved[row.id] = row
    confirmed, reason = ui.layout.placeRow(row, plan)
    if confirmed then plan.reserved[row.id] = nil end
    return confirmed, reason
end

function ui.layout.clearSay(message)
    ui.layout.say(message)
    if ui.layout.clearLabel then ui.layout.clearLabel.Text = message end
end

function ui.layout.pickupOne(entry, plan)
    local beforeCount = #ui.layout.placed(plan.interior)
    local serial = ui.layout.feedbackSerial or 0
    for attempt = 1, 3 do
        if not ui.layout.live(plan) then return false, "STOPPED" end
        local current = ui.layout.placed(plan.interior)
        if #current < beforeCount then return true end
        local target
        for _, candidate in ipairs(current) do
            if candidate.model == entry.model and candidate.index == entry.index then
                target = candidate
                break
            end
        end
        if not target then return false, "FURNITURE CHANGED; REFRESH AND TRY AGAIN" end
        -- The native HomeDecorUI pickup action returns the item; no sell/delete action is sent.
        if not ui.layout.send(plan, "pickup", target.index) then return false, "STOPPED" end
        local started = os.clock()
        repeat
            if not ui.layout.live(plan) then return false, "STOPPED" end
            if #ui.layout.placed(plan.interior) < beforeCount then return true end
            task.wait()
        until os.clock() - started >= 4
        plan.retryPace = math.min(0.5, (plan.retryPace or 0) + 0.1)
    end
    return false, ui.layout.reason("PICKUP NOT CONFIRMED", serial)
end

function ui.layout.clearHouse()
    assert(not states.houseLayout, "Stop the current house job before clearing.")
    assert(player:GetAttribute("InHouse") == player.UserId, "Enter your own house before clearing.")
    local interior = ui.layout.interior()
    assert(interior and interior:FindFirstChild("Furniture"), "Your house furniture has not loaded.")
    states.houseLayout = true
    jobs.houseLayout = task.defer(function()
        local feedbackConnection
        local ok, err = pcall(function()
            ui.layout.clearSay("HOUSE CLEAR QUEUED")
            if not movement.acquire("houseLayout") then return end
            ui.layout.clearPreview()
            local plan = { interior = interior }
            if not ui.layout.live(plan) then return end
            ui.layout.feedbackText = nil
            ui.layout.feedbackSerial = 0
            local feedback = Remotes:FindFirstChild("GardenFeedback")
            if feedback and feedback:IsA("RemoteEvent") then
                feedbackConnection = feedback.OnClientEvent:Connect(function(message)
                    if type(message) == "string" then
                        ui.layout.feedbackSerial = ui.layout.feedbackSerial + 1
                        ui.layout.feedbackText = message
                    end
                end)
                ui.layout.feedbackConnection = feedbackConnection
            end
            local picked = 0
            while ui.layout.live(plan) do
                local placed = ui.layout.placed(interior)
                if #placed == 0 then
                    ui.layout.buildLog = "HOUSE CLEARED • " .. picked .. " PICKED UP"
                    ui.layout.clearSay(ui.layout.buildLog .. " • LOAD YOUR NEXT LAYOUT")
                    return
                end
                -- Highest live index first; refresh after every pickup so index shifts stay safe.
                local entry = placed[#placed]
                ui.layout.clearSay(("CLEARING: %s • %d PICKED UP • %d REMAINING")
                    :format(entry.id, picked, #placed))
                local confirmed, reason = ui.layout.pickupOne(entry, plan)
                if not confirmed then
                    ui.layout.buildLog = ("CLEAR PAUSED • %d PICKED UP • %d REMAINING\n%s: %s")
                        :format(picked, #ui.layout.placed(interior), entry.id, tostring(reason))
                    ui.layout.clearSay(ui.layout.buildLog)
                    return
                end
                picked = picked + 1
            end
        end)
        if feedbackConnection then feedbackConnection:Disconnect() end
        ui.layout.feedbackConnection = nil
        states.houseLayout = false
        movement.release("houseLayout")
        jobs.houseLayout = nil
        if not ok then
            ui.layout.buildLog = "CLEAR STOPPED: " .. tostring(err)
            ui.layout.clearSay(ui.layout.buildLog)
        end
    end)
end

function ui.layout.apply(buyMissing)
    if states.houseLayout then return end
    buyMissing = buyMissing == true
    local data = ui.layout.decode(ui.layout.input.Text)
    ui.layout.plan(data)
    assert(player:GetAttribute("InHouse") == player.UserId, "Enter your own house before Apply.")
    states.houseLayout = true
    jobs.houseLayout = task.defer(function()
        local feedbackConnection
        local ok, err = pcall(function()
            ui.layout.say("HOUSE BUILD QUEUED")
            if not movement.acquire("houseLayout") then return end
            ui.layout.clearPreview()
            ui.layout.feedbackText = nil
            ui.layout.feedbackSerial = 0
            local feedback = Remotes:FindFirstChild("GardenFeedback")
            if feedback and feedback:IsA("RemoteEvent") then
                feedbackConnection = feedback.OnClientEvent:Connect(function(message)
                    if type(message) == "string" then
                        ui.layout.feedbackSerial = ui.layout.feedbackSerial + 1
                        ui.layout.feedbackText = message
                    end
                end)
                ui.layout.feedbackConnection = feedbackConnection
            end
            local plan = ui.layout.plan(data)
            local complete, pending = 0, {}
            for index, row in ipairs(plan.rows) do
                if not ui.layout.live(plan) then return end
                local confirmed, reason = ui.layout.placeRow(row, plan)
                if confirmed then complete = complete + 1
                else row.pendingReason = reason pending[#pending + 1] = row end
                ui.layout.say(("OWNED FIRST: %d / %d • PENDING %d"):format(complete, #plan.rows, #pending))
                if index % 20 == 0 then task.wait() end
            end
            for pass = 1, 3 do
                if #pending == 0 then break end
                plan.pass = pass
                local nextPending = {}
                for index, row in ipairs(pending) do
                    if not ui.layout.live(plan) then return end
                    local confirmed, reason = ui.layout.finishRow(row, plan, buyMissing)
                    if confirmed then complete = complete + 1 row.pendingReason = nil
                    else row.pendingReason = reason nextPending[#nextPending + 1] = row end
                    ui.layout.say(("BUILD / RECOVERY %d: %d / %d • PENDING %d")
                        :format(pass, complete, #plan.rows, #nextPending))
                    if index % 20 == 0 then task.wait() end
                end
                pending = nextPending
            end
            ui.layout.pending = {}
            local log = {("BUILT / KEPT %d OF %d; REMAINING %d"):format(complete, #plan.rows, #pending)}
            for _, row in ipairs(pending) do
                local line = row.id .. " • " .. tostring(row.pendingReason)
                ui.layout.pending[#ui.layout.pending + 1] = line
                log[#log + 1] = line
            end
            if ui.layout.feedbackText then log[#log + 1] = "LATEST GAME MESSAGE: " .. ui.layout.feedbackText end
            ui.layout.buildLog = table.concat(log, "\n")
            local preview = {}
            for index = 1, math.min(3, #pending) do preview[#preview + 1] = ui.layout.pending[index] end
            ui.layout.say(log[1] .. (#pending > 0 and ("\n" .. table.concat(preview, "\n") .. "\nCOPY BUILD LOG for all details.") or " • COMPLETE"))
        end)
        if feedbackConnection then feedbackConnection:Disconnect() end
        ui.layout.feedbackConnection = nil
        states.houseLayout = false
        movement.release("houseLayout")
        jobs.houseLayout = nil
        if not ok then
            ui.layout.buildLog = "BUILD STOPPED: " .. tostring(err)
            ui.layout.say(ui.layout.buildLog)
        end
    end)
end


-- Main contains the actual farming grind, with no duplicate navigation rows.
ui.main=ui.page("Main")
ui.farming=ui.group(ui.main,"FARMING")
ui.progression=ui.group(ui.main,"PROGRESSION")
ui.autoItems=ui.group(ui.farming,"AUTO USE ITEMS")
ui.harvest=ui.group(ui.farming,"Harvest")
ui.toggle(ui.harvest,"Auto Harvest","harvest")
ui.toggle(ui.harvest,"Ripe crops only","ripeOnly",true)
ui.text(ui.harvest,"Harvests your planted crops in one bed pass per turn.")
ui.text(ui.harvest,"Tap interval: 50–5000 ms.")
config.numbers.delay=ui.number(ui.harvest,BED_DELAY*1000,50,5000,function(n) BED_DELAY=n/1000 end)
harvestProgress=ui.text(ui.harvest,"Harvest: OFF")
ui.plant=ui.group(ui.farming,"Planting")
ui.toggle(ui.plant,"Auto Plant Selected Seeds","plant")
ui.text(ui.plant,"Plants selected seeds in empty beds. Choose normal order or highest seed-pack price first.")
planting.orderButton=ui.button(ui.plant,"Plant order: Normal",function()
    planting.order=planting.order=="normal" and "expensive" or "normal"
    planting.orderButton.Text="PLANT ORDER: "..(planting.order=="expensive" and "EXPENSIVE FIRST" or "NORMAL")
    configChanged()
end)
planting.label=ui.text(ui.plant,"Waiting for empty beds and selected seeds")
ui.plantList=ui.group(ui.plant,"Seeds to plant")
ui.plantConfig=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
for _,id in ipairs(ui.plantConfig.CropOrder) do
    local crop=ui.plantConfig.Crops[id]
    local label=crop.DisplayName or id
    if crop.PackCost then label=label.." • "..crop.PackCost.." "..(crop.PackCurrency or "coins") end
    ui.toggle(ui.plantList,label,"plant:"..id)
end
ui.dig=ui.group(ui.farming,"Dig Up Selected Plants")
ui.toggle(ui.dig,"Auto Dig Up","dig")
ui.text(ui.dig,"Removes selected crop types from your garden. Selected types are excluded from Auto Plant while digging is enabled.")
extras.labels.dig=ui.text(ui.dig,"Dig Up: OFF")
ui.sort=ui.group(ui.farming,"Replant / Arrange Expensive First")
ui.toggle(ui.sort,"Auto Arrange Selected Plants","rearrange")
ui.text(ui.sort,"Sorts selected plants by seed price. Keeps displaced plants; needs one empty bed.")
extras.labels.rearrange=ui.text(ui.sort,"Arrange: OFF")
ui.digList=ui.group(ui.dig,"Crop types to dig up")
ui.sortList=ui.group(ui.sort,"Crop types to place first")
for _,id in ipairs(ui.plantConfig.CropOrder) do
    local crop=ui.plantConfig.Crops[id]
    ui.toggle(ui.digList,crop.DisplayName or id,"dig:"..id)
    ui.toggle(ui.sortList,crop.DisplayName or id,"sort:"..id)
end
ui.quests=ui.group(ui.farming,"Daily Quests")
ui.toggle(ui.quests,"Auto Quest","quest")
ui.text(ui.quests,"Works available daily quest goals using selected seeds and resources. Sales follow the market setting. Gifts and farm likes remain manual.")
extras.labels.quest=ui.text(ui.quests,"Quests: OFF")
ui.dust=ui.group(ui.autoItems,"Fairy Dust")
ui.toggle(ui.dust,"Use when zero crops are ripe","dust")
ui.text(ui.dust,"Refills to your minimum, then uses dust when no fruit is ripe. Repeats after stock empties. Enables harvesting.")
ui.text(ui.dust,"MINIMUM FAIRY DUST TO START A BATCH")
config.numbers.dustMinimum=ui.number(ui.dust,dustCycle.reserve,1,9007199254740991,function(n)
    dustCycle.reserve=n
    dustCycle.canSpend(inventoryAmount("FairyDust"))
    dustCycle.status()
end)
dustCycle.label=ui.text(ui.dust,"REFILLING: 0 / "..dustCycle.reserve)
dustStatus=ui.text(ui.dust,"Fairy Dust requests: 0")
ui.water=ui.group(ui.farming,"Watering")
ui.toggle(ui.water,"Auto Water","water")
ui.text(ui.water,"Waters garden beds that need water.")
ui.returns=ui.group(ui.farming,"Optional returns")
ui.toggle(ui.returns,"Return after shopping","returnAfterBuy")
ui.toggle(ui.returns,"Return when ripe and away","ripeReturn")
ui.text(ui.returns,"Returns after shopping when enabled. Ripe-crop return runs during the harvest turn only.")
ui.housePage=ui.page("Home")
ui.houseImport=ui.group(ui.housePage,"AUTO HOUSE LAYOUT")
ui.text(ui.houseImport,"Places owned furniture first, then buys and places missing pieces one at a time. Unavailable items are skipped; unused furniture stays.")
ui.layout.input=make("TextBox",{Size=UDim2.new(1,0,0,116),MultiLine=true,ClearTextOnFocus=false,
    Text="",PlaceholderText="PASTE HOUSE LAYOUT JSON",TextSize=10,Font=Enum.Font.Code,
    TextColor3=white,PlaceholderColor3=Color3.fromRGB(125,146,173),TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    BackgroundColor3=Color3.fromRGB(10,16,24),BorderSizePixel=0},ui.houseImport)
corner(ui.layout.input,5)
ui.layout.path=make("TextBox",{Size=UDim2.new(1,0,0,25),ClearTextOnFocus=false,
    Text="exi_house_layout.json",TextSize=10,Font=Enum.Font.Code,TextColor3=white,
    BackgroundColor3=Color3.fromRGB(13,20,30),BorderSizePixel=0},ui.houseImport)
ui.button(ui.houseImport,"LOAD JSON FILE",function()
    assert(not states.houseLayout,"Stop building before loading a layout.")
    assert(type(readfile)=="function","Executor readfile is unavailable; paste JSON instead.")
    local text=readfile(ui.layout.path.Text)
    ui.layout.decode(text)
    ui.layout.input.Text=text
    ui.layout.say("LAYOUT LOADED • VALIDATE BEFORE APPLYING")
end)
ui.button(ui.houseImport,"PASTE FROM CLIPBOARD",function()
    assert(not states.houseLayout,"Stop building before pasting a layout.")
    assert(type(getclipboard)=="function","Clipboard reading unavailable; paste manually.")
    ui.layout.input.Text=getclipboard()
end)
ui.button(ui.houseImport,"VALIDATE LAYOUT",function()ui.layout.inspect(false)end)
ui.button(ui.houseImport,"PREVIEW FOOTPRINTS",function()ui.layout.inspect(true)end)
ui.button(ui.houseImport,"HIDE PREVIEW",ui.layout.clearPreview)
ui.button(ui.houseImport,"BUILD + BUY MISSING",function()ui.layout.apply(true)end)
ui.button(ui.houseImport,"PLACE OWNED ONLY",function()ui.layout.apply(false)end)
ui.button(ui.houseImport,"STOP HOUSE BUILD",ui.layout.cancel)
ui.button(ui.houseImport,"COPY BUILD LOG",function()
    assert(type(setclipboard)=="function","Clipboard is unavailable.")
    setclipboard(ui.layout.buildLog or "No completed build log yet.")
    ui.layout.say("BUILD LOG COPIED")
end)
ui.layout.label=ui.text(ui.houseImport,"NO LAYOUT LOADED")
ui.houseClear=ui.group(ui.housePage,"CLEAR HOUSE")
ui.text(ui.houseClear,"Picks up all placed furniture, walls and floor decorations into inventory. Keeps your loaded layout and house upgrades.")
ui.button(ui.houseClear,"PICK UP ALL FURNITURE",ui.layout.clearHouse)
ui.button(ui.houseClear,"STOP CLEARING",ui.layout.cancel)
ui.layout.clearLabel=ui.text(ui.houseClear,"ENTER YOUR OWN HOUSE TO CLEAR")
ui.houseExport=ui.group(ui.housePage,"EXPORT HOUSE DATA")
ui.text(ui.houseExport,"Exports floors, furniture, inventory and catalog IDs to exi_house_export.json.")
ui.button(ui.houseExport,"EXPORT MY HOUSE",ui.layout.export)
ui.houseVisited=ui.group(ui.housePage,"EXPORT VISITED HOUSE")
ui.text(ui.houseVisited,"Visit the house and wait for furniture to load. Exports visible furniture layout only; inventory is excluded.")
ui.layout.visitedLabel=ui.text(ui.houseVisited,"SELECT A PLAYER OR ENTER THEIR HOUSE")
ui.button(ui.houseVisited,"USE CURRENT VISITED HOUSE",function()
    local ownerId=tonumber(player:GetAttribute("InHouse"))
    assert(ownerId and ownerId~=player.UserId,"Enter another player's house first.")
    ui.layout.visitedOwnerId=ownerId
    ui.layout.refreshVisited()
end)
ui.button(ui.houseVisited,"REFRESH PLAYERS / LOADED HOUSES",ui.layout.refreshVisited)
ui.layout.visitedSelect=ui.group(ui.houseVisited,"SELECT PLAYER")
ui.layout.visitedChoices=make("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1},ui.layout.visitedSelect)
make("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},ui.layout.visitedChoices)
ui.button(ui.houseVisited,"EXPORT SELECTED HOUSE",ui.layout.exportVisited)
ui.layout.refreshVisited()
ui.houseFormat=ui.group(ui.housePage,"LAYOUT FORMAT")
ui.text(ui.houseFormat,"Floor-local X/Z in studs; floor 1 is lowest. Rotation: 45° steps. Preview footprints are approximate.")
ui.button(ui.houseFormat,"LOAD SMALL EXAMPLE",function()
    assert(not states.houseLayout,"Stop building before changing the layout.")
    ui.layout.input.Text=HttpService:JSONEncode({version=1,coordinateSpace="floor-local",name="Example only",
        items={{id="Rug",floor=1,x=0,z=0,yaw=0},{id="Chair",floor=1,x=-5,z=0,yaw=90}}})
end)
ui.plazaPage=ui.page("Plaza")
ui.orders=ui.group(ui.plazaPage,"Lila — Special Orders")
ui.toggle(ui.orders,"Auto Submit Available Orders","orders")
ui.text(ui.orders,"Checks Lila every 30 seconds and submits available orders using items in your bag.")
extras.labels.orders=ui.text(ui.orders,"Orders: OFF")
ui.mayor=ui.group(ui.plazaPage,"Mayor — Daily Requests")
ui.toggle(ui.mayor,"Auto Mayor","mayor")
ui.text(ui.mayor,"Checks Mayor Pip for available daily requests, submissions and rewards.")
extras.labels.mayor=ui.text(ui.mayor,"Mayor: OFF")
ui.seedPage=ui.group(ui.plazaPage,"Seed shop")
ui.seedDiagnostics=ui.group(ui.seedPage,"Shop diagnostics")
ui.text(ui.seedDiagnostics,"Shows normal and special seed purchase results.")
for _,entry in ipairs({{key="normalSeeds",name="Normal Seeds"},{key="seeds",name="Special Seeds"}}) do
    local body=ui.group(ui.seedDiagnostics,entry.name.." diagnostics")
    seedStatus[entry.key]=ui.text(body,"No seed visit recorded yet")
    ui.text(body,"Latest server reply")
    seedDiagnostics.labels[entry.key]=ui.text(body,"No reply yet")
    ui.button(body,"Copy diagnostics",function()
        local output=entry.name.."\n"..table.concat(seedDiagnostics.logs[entry.key],"\n")
            .."\n\n"..(seedDiagnostics.replies[entry.key] or "No reply yet")
        if type(setclipboard)=="function" then setclipboard(output) report("Seed diagnostics copied")
        else report("Clipboard function unavailable; diagnostics remain visible here") end
    end)
    ui.button(body,"Clear log",function()
        seedDiagnostics.logs[entry.key]={}
        seedDiagnostics.replies[entry.key]=nil
        seedStatus[entry.key].Text="Log cleared"
        seedDiagnostics.labels[entry.key].Text="No reply yet"
    end)
end
ui.seedRoot=ui.seedPage
ui.normal=ui.group(ui.seedRoot,"Normal Seeds")
ui.toggle(ui.normal,"Auto Buy Normal Seeds","normalSeeds")
ui.text(ui.normal,"Buys selected normal seeds after restock.")
ui.special=ui.group(ui.seedRoot,"Special Seeds")
ui.toggle(ui.special,"Auto Buy Special Seeds","seeds")
ui.button(ui.special,"Buy selected Special Seeds now",function()
    if not states.seeds then report("Enable Auto Buy Special Seeds and select items first") return end
    if jobs.seedCheck then return end
    jobs.seedCheck=task.defer(function()
        if movement.acquire("seeds") then
            local ok,err=pcall(purchaseSeeds,"seeds")
            movement.release("seeds")
            if not ok then seedReport("seeds",tostring(err)) end
        end
        jobs.seedCheck=nil
    end)
end)
ui.text(ui.special,"Opens the special-seed page and buys selected available stock.")
ui.config=getStockConfig()
ui.items=require(game:GetService("ReplicatedStorage").Shared.ItemConfig)
ui.specialSet={}
for _,id in ipairs(seedIds) do ui.specialSet[id]=true end
for id in pairs(ui.config.Seeds or {}) do
    if not ui.specialSet[id] then table.insert(normalIds,id) end
end
function ui.seedSort(a,b)
    local x,y=(ui.items.Crops[a] or {}).PackCost or math.huge,(ui.items.Crops[b] or {}).PackCost or math.huge
    if x~=y then return x<y end
    return a<b
end
table.sort(normalIds,ui.seedSort)
ui.specialSorted={}
for _,id in ipairs(seedIds) do table.insert(ui.specialSorted,id) end
table.sort(ui.specialSorted,ui.seedSort)
function ui.seedList(container,ids,prefix)
    for _,id in ipairs(ids) do
        local crop=ui.items.Crops[id] or {}
        local label=crop.DisplayName or id
        if crop.PackCost then label=label.." • "..crop.PackCost.." "..(crop.PackCurrency or "coins") end
        ui.toggle(container,label,prefix..id)
    end
end
ui.seedList(ui.normal,normalIds,"normal:")
ui.seedList(ui.special,ui.specialSorted,"seed:")
ui.gearPage=ui.group(ui.plazaPage,"Gear shop")
ui.gear=ui.gearPage
ui.toggle(ui.gear,"Auto Buy Selected Gears","gears")
ui.text(ui.gear,"Buys available quantities of selected gear after restock.")
for _,id in ipairs(gearIds) do
    local info=ui.config.Gear[id] or {}
    ui.toggle(ui.gear,id.." • "..tostring(info.Coins or "?").." coins","gear:"..id,true)
end
shopStatus=ui.text(ui.gear,"Shop status: idle")
ui.gearDiagnostics=ui.group(ui.gearPage,"GearKeeper diagnostics")
restockLabel=ui.text(ui.gearDiagnostics,"Waiting for restock")
gearDiagnostics.statusLabel=ui.text(ui.gearDiagnostics,"No gear visit recorded yet")
gearDiagnostics.replyLabel=ui.text(ui.gearDiagnostics,"No GearKeeper reply yet")
ui.button(ui.gearDiagnostics,"Copy gear diagnostics",function()
    local output=table.concat(gearDiagnostics.log,"\n").."\n\n"..(gearDiagnostics.reply or "No reply yet")
    if type(setclipboard)=="function" then setclipboard(output) report("Gear diagnostics copied")
    else report("Clipboard function unavailable") end
end)
ui.button(ui.gearDiagnostics,"Clear gear log",function()
    gearDiagnostics.log={}
    gearDiagnostics.reply=nil
    gearDiagnostics.statusLabel.Text="Log cleared"
    gearDiagnostics.replyLabel.Text="No reply yet"
end)
ui.marketPage=ui.group(ui.plazaPage,"Harvest market")
ui.market=ui.marketPage
ui.toggle(ui.market,"AUTO SELL CROPS SAFELY","sellBoom")
ui.toggle(ui.market,"AUTO DETECT MOST EXPENSIVE BAG CROPS","autoDetectSellCrops")
safeSales.detectedLabel=ui.text(ui.market,"AUTO DETECT: OFF • USING MANUAL SELECTIONS")
ui.text(ui.market,"Auto Detect overrides selections. Sells the most expensive fitting offer, then checks again. Stops at your limit or no safe fit.")
ui.toggle(ui.market,"MANUAL SELECTION FILTER (AUTO DETECT OFF)","sellSpecificOnly",true)
ui.toggle(ui.market,"Wait for Market Boom only","sellOnlyBoom",true)
ui.text(ui.market,"Sells quoted crops by highest unit price. Includes selected plant variants; filter off includes all crops.")
ui.text(ui.market,"STOP SELLING AT BALANCE")
saleLimit.input=make("TextBox",{Size=UDim2.new(1,0,0,25),Text="",PlaceholderText="GAME CAP 1B • CUSTOM: 500M",
    ClearTextOnFocus=false,TextSize=10,TextColor3=white,Font=Enum.Font.Code,
    BackgroundColor3=Color3.fromRGB(13,20,30),BorderSizePixel=0},ui.market)
corner(saleLimit.input,5)
saleLimit.input.FocusLost:Connect(function()
    local ok,err=pcall(saleLimit.set,saleLimit.input.Text)
    if not ok then saleLimit.input.Text=saleLimit.text report(tostring(err)) end
end)
saleLimit.label=ui.text(ui.market,"BALANCE LIMIT: OFF")
ui.text(ui.market,"Use K/M/B/T or a number. Blank/0 = 1B cap. Leaves 1 coin of room; skips oversized stacks. Requires exact game quotes.")
ui.bagTitle=ui.text(ui.market,"BAG CROP VALUE")
ui.bagTitle.TextColor3=white
ui.bagTitle.Font=Enum.Font.BuilderSansBold
ui.bag.labels.count=ui.text(ui.market,"BAG CROPS: 0")
ui.bag.labels.base=ui.text(ui.market,"NO BONUS: 0 COINS")
ui.bag.labels.fuzz=ui.text(ui.market,"FUZZ BONUS: 0 COINS")
ui.bag.labels.boom=ui.text(ui.market,"FUZZ + MARKET BOOM: 0 COINS")
ui.text(ui.market,"Bonus values are estimates using FuzzSell and a 50% Market Boom increase. Excludes other bonuses; server rounding may differ.")
activityStatus.sellBoom=ui.text(ui.market,"Auto Sell: OFF")
ui.sellCropList=ui.group(ui.market,"MANUAL PLANT SELECTIONS — EXPENSIVE FIRST")
ui.sellCropRows={}
for id,crop in pairs(ui.items.Crops) do
    ui.sellCropRows[#ui.sellCropRows+1]={id=id,name=crop.DisplayName or id,price=tonumber(crop.SellPrice) or 0}
end
table.sort(ui.sellCropRows,function(a,b) if a.price~=b.price then return a.price>b.price end return a.id<b.id end)
for _,crop in ipairs(ui.sellCropRows) do ui.toggle(ui.sellCropList,crop.name,"sellcrop:"..crop.id,true) end
ui.saleDiag=ui.group(ui.market,"Sale diagnostics")
saleDiagnostics.label=ui.text(ui.saleDiag,"No sale attempted yet")
ui.button(ui.saleDiag,"COPY SAFE SALE DIAGNOSTICS",function()
    if type(setclipboard)=="function" then
        setclipboard((saleDiagnostics.reply or "No sale yet").."\n\nLIVE MENU DATA\n"..table.concat(safeSales.menus,"\n\n"))
        report("Safe sale diagnostics copied")
    end
end)
ui.button(ui.saleDiag,"RESUME AFTER REVIEW",function() safeSales.halted=false configChanged() safeSales.log("SAFE SALE CHECKS RESUMED") end)
ui.text(ui.saleDiag,"Missing exact quantity or total pauses sales. Copy diagnostics to check the menu format.")
ui.forestPage=ui.page("Forest")
ui.fairies=ui.group(ui.forestPage,"FAIRY TRADES")
ui.forest=ui.group(ui.forestPage,"Forest drops")
ui.toggle(ui.forest,"Auto Pick Up","pickups")
ui.text(ui.forest,"Collects visible forest drops by moving to each item.")
activityStatus.pickups=ui.text(ui.forest,"Pickups: OFF")
ui.fishPage=ui.page("Lake")
ui.fish=ui.group(ui.fishPage,"Lake fishing")
ui.toggle(ui.fish,"Auto Fish at the lake","fishing")
ui.text(ui.fish,"Casts at the lake and waits for a catch or cast timeout before releasing its turn.")
activityStatus.fishing=ui.text(ui.fish,"Lake fishing: OFF")
ui.treePage=ui.forestPage
ui.tree=ui.group(ui.treePage,"Chopping")
ui.toggle(ui.tree,"Auto Chop","wood")
ui.text(ui.tree,"Chops one tree per turn. Yields to ripe fruit and ready Fairy Dust batches.")
ui.button(ui.tree,"Change movement mode",function() chopMode=chopMode=="Teleport" and "Walk" or "Teleport" report("Tree movement: "..chopMode) configChanged() end)
ui.text(ui.tree,"Hits per tree (1–6).")
config.numbers.hits=ui.number(ui.tree,chopHits,1,6,function(n) chopHits=n end)
ui.treeTypes=ui.group(ui.tree,"Tree selections")
for _,name in ipairs({"Tree_Apple","Tree_Blossom","Tree_Pine","Tree_Round"}) do ui.toggle(ui.treeTypes,name,"tree:"..name,true) end
ui.house=ui.group(ui.progression,"Carpenter — house upgrades")
ui.toggle(ui.house,"Auto Upgrade House","houseUpgrade")
ui.text(ui.house,"Buys available cottage upgrades from Carpenter using your coins.")
activityStatus.houseUpgrade=ui.text(ui.house,"House upgrades: OFF")
ui.garden=ui.group(ui.progression,"Garden upgrades")
ui.toggle(ui.garden,"Auto Upgrade Garden","gardenUpgrade")
ui.text(ui.garden,"Buys available garden upgrades using your coins.")
activityStatus.gardenUpgrade=ui.text(ui.garden,"Garden upgrades: OFF")
ui.timerPage=ui.farming
ui.animals=ui.group(ui.timerPage,"Animals")
ui.toggle(ui.animals,"Auto Tend Animals","tend")
ui.text(ui.animals,"Returns to your farm before tending animals that need care. Waits if your farm or character is unavailable.")
tendLabel=ui.text(ui.animals,"Animal tending: OFF")
ui.candyFairy=ui.group(ui.fairies,"Candy — Fairies Without a Mushroom House")
ui.toggle(ui.candyFairy,"Auto Trade Candy With Regular Fairies","candyFairy")
ui.text(ui.candyFairy,"Travels only when Candy covers one offer. Learns the price while nearby and saves it.")
ui.text(ui.candyFairy,"CANDY PER OFFER (0 = LEARN NEARBY)")
config.numbers.candyOfferCost=ui.number(ui.candyFairy,fairyOffers.candyCost,0,1000000000,function(n)
    fairyOffers.candyCost=math.floor(n)
end)
candyFairyLabel=ui.text(ui.candyFairy,"Candy trades: OFF")
ui.fairy=ui.group(ui.fairies,"Golden Acorns — Mushroom-house Fairy")
ui.toggle(ui.fairy,"Trade all Golden Acorns","fairy")
ui.text(ui.fairy,"Trades all Golden Acorns with the mushroom fairy. Holds the turn until empty. Toggle off to cancel.")
fairyLabel=ui.text(ui.fairy,"Fairy trading: OFF")
for _,item in ipairs(itemIds) do
    local body=ui.group(ui.autoItems,item)
    ui["buff"..item]=body
    ui.toggle(body,"Auto "..item,item)
    ui.text(body,"Uses at the first ripe-fruit harvest. Separate 10-minute cooldown; no idle use.")
    itemLabels[item]=ui.text(body,"Ready / OFF")
end
ui.socialPage=ui.page("Social")
ui.photo=ui.group(ui.socialPage,"PHOTO MODE")
ui.text(ui.photo,"Opens the photo camera and poses. Stops automation.")
ui.button(ui.photo,"OPEN PHOTO MODE — PAUSE TASKS",function()
    local event=parent:FindFirstChild("OpenPhotoMode")
    assert(event and event:IsA("BindableEvent"),"Photo Mode has not loaded in this server.")
    stopAll()
    event:Fire()
end)
ui.emotes=ui.group(ui.socialPage,"EMOTES AND POSES")
ui.social={armed={}}
function ui.social.owned(id,info)
    if not info.Coins and not info.Robux then return true end
    local owned=tostring(player:GetAttribute("OwnedEmotes") or "")
    for token in owned:gmatch("[^,]+") do if token:match("^%s*(.-)%s*$")==id then return true end end
    return false
end
sessionOptions.stopEmote=function()
    if sessionOptions.exiEmote then
        pcall(fire,"EmoteAction","stop",nil)
        sessionOptions.exiEmote=false
    end
end
ui.button(ui.emotes,"STOP EMOTE",function()fire("EmoteAction","stop",nil) sessionOptions.exiEmote=false end)
ui.text(ui.emotes,"Play owned/free emotes. Double-click within 3 seconds to buy with coins.")
ui.social.module=game:GetService("ReplicatedStorage").Shared:FindFirstChild("EmoteConfig")
if ui.social.module then
    local ok,data=pcall(require,ui.social.module)
    if ok and type(data)=="table" then
        for _,id in ipairs(data.Order or {}) do
            local emoteId=id
            local info=data.Emotes[id]
            if info then
                local group=ui.group(ui.emotes,info.Name or id)
                ui.text(group,info.Coins and ("COIN PRICE: "..info.Coins) or (info.Robux and "ROBLOX SHOP PURCHASE REQUIRED" or "FREE"))
                ui.button(group,"PLAY",function()
                    assert(ui.social.owned(emoteId,info),"This emote is not owned yet.")
                    stopAll()
                    fire("EmoteAction","play",emoteId)
                    sessionOptions.exiEmote=true
                end)
                if info.Coins and not info.Robux then
                    ui.button(group,"BUY WITH COINS — DOUBLE CLICK",function()
                        if ui.social.owned(emoteId,info) then report("EMOTE ALREADY OWNED") return end
                        local now=os.clock()
                        if now<(ui.social.armed[emoteId] or 0) then
                            ui.social.armed[emoteId]=nil
                            fire("EmoteAction","buy",emoteId)
                            report("EMOTE PURCHASE REQUESTED: "..emoteId)
                        else ui.social.armed[emoteId]=now+3 report("CLICK AGAIN WITHIN 3 SECONDS TO BUY FOR "..info.Coins.." COINS") end
                    end)
                end
            end
        end
    else ui.text(ui.emotes,"Emote catalog unavailable in this server.") end
else ui.text(ui.emotes,"EmoteConfig is not loaded in this server.") end
ui.joinEmote=ui.group(ui.socialPage,"JOIN A PLAYER'S EMOTE")
ui.social.joinBox=make("TextBox",{Size=UDim2.new(1,0,0,25),Text="",PlaceholderText="EXACT ROBLOX USERNAME",ClearTextOnFocus=false,
    TextColor3=white,TextSize=10,Font=Enum.Font.Code,BackgroundColor3=Color3.fromRGB(13,20,30),BorderSizePixel=0},ui.joinEmote)
ui.button(ui.joinEmote,"JOIN EMOTE",function()
    local name=ui.social.joinBox.Text:match("^%s*(.-)%s*$"):lower()
    local target=nil
    for _,other in ipairs(Players:GetPlayers()) do if other~=player and other.Name:lower()==name then target=other break end end
    assert(target and type(target:GetAttribute("EmoteId"))=="string" and target:GetAttribute("EmoteId")~="","Choose an exact username of someone currently emoting in this server.")
    stopAll()
    fire("EmoteAction","join",target.UserId)
    sessionOptions.exiEmote=true
end)
ui.travelPage=ui.page("Travel")
ui.travel=ui.group(ui.travelPage,"Travel destinations")
for _,destination in ipairs({"Seeds","Gear","Forest","Cove"}) do
    ui.button(ui.travel,"Travel to "..destination,function() stopAll() fire("Travel",destination) end)
end
ui.leaderboardPage=ui.page("Leaderboard")
ui.boards={entries={},lastRefresh=0}
function ui.boards.clean(text,rich)
    text=tostring(text or "")
    if rich then text=text:gsub("<[^>]+>",""):gsub("&lt;","<"):gsub("&gt;",">"):gsub("&amp;","&") end
    return text
end
function ui.boards.list(text)
    local lines={}
    for line in text:gmatch("[^\r\n]+") do
        local trimmed=line:match("^%s*(.-)%s*$")
        if trimmed~="" then lines[#lines+1]="- "..trimmed end
    end
    return #lines>0 and table.concat(lines,"\n") or "- NO ENTRIES"
end
function ui.boards.read(place,id)
    -- GameConfig.Place is the layout marker; rendered boards use Leaderboard_<Id>.
    id=id or (type(place)=="string" and place:match("^Board(.+)$"))
    local folder=workspace:FindFirstChild("Leaderboards")
    local board=id and folder and folder:FindFirstChild("Leaderboard_"..id)
    if not board and id then board=workspace:FindFirstChild("Leaderboard_"..id,true) end
    if not board and type(place)=="string" then board=workspace:FindFirstChild(place,true) end
    if not board then return "BOARD NOT LOADED • MOVE CLOSER TO THE ISLAND LEADERBOARDS AND REFRESH" end
    local fragments={}
    local named={}
    for _,obj in ipairs(board:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Text~="" then
            local visible=true
            local ancestor=obj
            while ancestor and ancestor~=board do
                if ancestor:IsA("GuiObject") and not ancestor.Visible then visible=false break end
                if (ancestor:IsA("SurfaceGui") or ancestor:IsA("BillboardGui")) and not ancestor.Enabled then visible=false break end
                ancestor=ancestor.Parent
            end
            if visible then
                local text=ui.boards.clean(obj.Text,obj.RichText)
                if obj.Name then named[obj.Name]=text end
                fragments[#fragments+1]={text=text,x=obj.AbsolutePosition.X,y=obj.AbsolutePosition.Y}
            end
        end
    end
    if named.List_Week or named.List_All then
        local sections={}
        if named.List_Week then sections[#sections+1]="THIS WEEK\n"..ui.boards.list(named.List_Week) end
        if named.List_All then
            local heading=named.Header_All or "ALL TIME"
            sections[#sections+1]=heading:upper().."\n"..ui.boards.list(named.List_All)
        end
        if named.Footer then sections[#sections+1]=named.Footer end
        return table.concat(sections,"\n\n")
    end
    table.sort(fragments,function(a,b) if a.y~=b.y then return a.y<b.y end return a.x<b.x end)
    local lines={}
    local lastY=nil
    for _,part in ipairs(fragments) do
        if lastY and math.abs(part.y-lastY)<=2 then lines[#lines]=lines[#lines].."  "..part.text
        else lines[#lines+1]=part.text lastY=part.y end
    end
    return #lines>0 and table.concat(lines,"\n") or "BOARD TEXT NOT AVAILABLE"
end
function ui.boards.refresh(force)
    if not force and (ui.selected~="Leaderboard" or os.clock()-ui.boards.lastRefresh<3) then return end
    ui.boards.lastRefresh=os.clock()
    for _,entry in ipairs(ui.boards.entries) do
        local ok,value=pcall(ui.boards.read,entry.place,entry.id)
        entry.label.Text=ok and value or "BOARD DATA UNAVAILABLE"
    end
end
ui.text(ui.leaderboardPage,"Displays the island's replicated leaderboard boards. Updates every three seconds while this page is open.")
ui.boardConfig=require(game:GetService("ReplicatedStorage").Shared.GameConfig)
for index,board in ipairs(ui.boardConfig.Leaderboards or {}) do
    local body=ui.group(ui.leaderboardPage,board.Title or board.Id)
    body.Parent.LayoutOrder=index
    ui.boards.entries[#ui.boards.entries+1]={place=board.Place,id=board.Id,label=ui.text(body,"OPEN THIS PAGE TO REFRESH")}
end
ui.button(ui.leaderboardPage,"REFRESH BOARDS",function() ui.boards.refresh(true) end).LayoutOrder=100
ui.settingsPage=ui.page("Settings")
ui.config=ui.group(ui.settingsPage,"Saved config")
ui.toggle(ui.config,"Auto Save settings","autoSave",true)
ui.text(ui.config,"Saves selections, toggles and timers on this device. Reload the script after rejoining to resume.")
config.label=ui.text(ui.config,"Config ready")
ui.button(ui.config,"Save config now",config.save)
ui.button(ui.config,"Load saved config",config.load)
ui.queue=ui.group(ui.settingsPage,"Task priorities")
ui.text(ui.queue,"Next-turn order: Golden Acorn trades, shops, orders, market, harvest, digging, arrangement, planting, Fairy Dust, water, Mayor, Candy trades, quests, animals and upgrades, drops, chopping, fishing.")
ui.text(ui.queue,"Finishes the current action, then runs the highest-priority waiting task.")
ui.diag=ui.group(ui.settingsPage,"Other NPC replies")
shopReplyLabel=ui.text(ui.diag,"Shop reply not captured yet")
ui.text(ui.diag,"Shows the latest NPC menu and action result.")
ui.position=ui.group(ui.settingsPage,"Return destination")
ui.button(ui.position,"Cycle return destination",function()
    if returnMode=="Bed_6_5" then returnMode="Previous"
    elseif returnMode=="Previous" and savedCenter then returnMode="Bed center"
    else returnMode="Bed_6_5" end
    report("Return destination: "..returnMode)
    configChanged()
end)
ui.button(ui.position,"Save current position",function() savedCenter=currentPosition() report("Return position saved") configChanged() end)
ui.text(ui.position,"Chooses the destination for enabled return functions.")
ui.antiAfk=ui.group(ui.settingsPage,"Anti AFK")
ui.toggle(ui.antiAfk,"Prevent Roblox idle disconnect","antiAfk")
ui.text(ui.antiAfk,"Sends idle input while Roblox is running. Does not keep a suspended phone app active.")
ui.session=ui.group(ui.settingsPage,"SESSION")
ui.toggle(ui.session,"AUTO LEAVE WHEN A PLAYER JOINS","leaveOnJoin")
ui.text(ui.session,"Disconnects when another player joins after this toggle is enabled. Players already in the server do not trigger it.")
ui.toggle(ui.session,"AUTO RECONNECT","autoReconnect")
ui.text(ui.session,"Reconnects after connection loss. Enable Auto Execute to resume. Requires executor support.")
sessionOptions.reconnectLabel=ui.text(ui.session,"AUTO RECONNECT: OFF")
ui.toggle(ui.session,"AUTO EXECUTE","autoExecute")
ui.text(ui.session,"Reloads through supported autoexec or teleport queues. Keep your GitHub script updated.")
sessionOptions.label=ui.text(ui.session,"AUTO EXECUTE: OFF")
ui.eventGroup=ui.group(ui.settingsPage,"ISLAND EVENTS")
ui.events.current=ui.text(ui.eventGroup,"CURRENT: —")
ui.events.ends=ui.text(ui.eventGroup,"ENDS IN: —")
ui.events.next=ui.text(ui.eventGroup,"NEXT EVENT IN: —")
ui.events.kind=ui.text(ui.eventGroup,"NEXT EVENT TYPE: UNKNOWN")
ui.text(ui.eventGroup,"The next start time comes from the server. Official event probabilities are not included in the client files.")
ui.eventOdds=ui.group(ui.eventGroup,"OBSERVED EVENT PROBABILITIES")
ui.events.sampleLabel=ui.text(ui.eventOdds,"RECORDED EVENTS: 0")
for _,id in ipairs(ui.events.ids) do ui.events.probLabels[id]=ui.text(ui.eventOdds,id:upper()..": NO DATA") end
ui.text(ui.eventOdds,"Local observed event frequencies. Saved between sessions; not official odds or predictions.")
ui.safety=ui.group(ui.settingsPage,"Controls")
ui.text(ui.safety,"Stops active and queued tasks for the chosen area. Selections remain saved.")
ui.button(ui.safety,"STOP ALL",stopAll)
for _,name in ipairs({"Main","Plaza","Forest","Lake","Home","Settings"}) do
    local category=name
    ui.button(ui.safety,"STOP "..name,function() ui.stopCategory(category) end)
end
function ui.order(group,order)
    if group and group.Parent then group.Parent.LayoutOrder=order end
end
ui.order(ui.farming,1)
ui.order(ui.progression,2)
for order,key in ipairs({"harvest","plant","water","animals","quests","autoItems","dig","sort","returns"}) do
    ui.order(ui[key],order)
end
for order,key in ipairs({"dust","buffLuckyCharm","buffRainbowDew"}) do ui.order(ui[key],order) end
ui.order(ui.garden,1)
ui.order(ui.house,2)
for order,key in ipairs({"seedPage","gearPage","orders","marketPage","mayor"}) do ui.order(ui[key],order) end
for order,key in ipairs({"fairies","forest","tree"}) do ui.order(ui[key],order) end
ui.order(ui.fairy,1)
ui.order(ui.candyFairy,2)
for order,key in ipairs({"safety","session","eventGroup","config","queue","position","antiAfk","diag"}) do ui.order(ui[key],order) end
ui.order(ui.special,1)
ui.order(ui.normal,2)
ui.order(ui.seedDiagnostics,3)
ui.order(ui.gearDiagnostics,20)
ui.order(ui.sellCropList,19)
ui.order(ui.saleDiag,20)
ui.selected=nil
selectPage=function(name)
    if ui.selected==name then content.Visible=not content.Visible return end
    ui.selected=name
    content.Visible=true
    pageTitle.Text=name:upper()
    if name=="Leaderboard" then ui.boards.refresh(true) end
    for key,frame in pairs(pages) do frame.Visible=key==name end
    for key,button in pairs(tabs) do
        button.BackgroundColor3=key==name and Color3.fromRGB(23,45,71) or Color3.fromRGB(15,19,27)
        button.TextColor3=key==name and blue or white
    end
end
for index,name in ipairs({"Main","Plaza","Forest","Lake","Social","Travel","Home","Leaderboard","Settings"}) do
    local button=make("TextButton",{Position=UDim2.fromOffset(4,4+(index-1)*24),
        Size=UDim2.new(1,-8,0,21),Text="  "..name,TextXAlignment=Enum.TextXAlignment.Left,
        BackgroundColor3=Color3.fromRGB(15,19,27),BorderSizePixel=0,TextColor3=white,
        Font=Enum.Font.BuilderSansMedium,TextSize=10},sidebar)
    corner(button,7)
    make("UIStroke",{Color=Color3.fromRGB(35,56,79),Thickness=1},button)
    tabs[name]=button
    button.Activated:Connect(function() selectPage(name) end)
end
local grip=make("TextButton", {AnchorPoint=Vector2.new(1,1),Position=UDim2.fromScale(1,1),
    Size=UDim2.fromOffset(25,22),BackgroundTransparency=1,Text="◢",TextColor3=blue,
    TextSize=17,Active=true},panel)
local icon=make("TextButton",{Name="OpenEXIScript",Size=UDim2.fromOffset(32,32),
    Position=UDim2.fromOffset(12,90),BackgroundColor3=Color3.fromRGB(8,15,25),
    Text="EXIS",TextColor3=Color3.fromRGB(240,247,255),Font=Enum.Font.BuilderSansBold,TextSize=10,
    Visible=false,BorderSizePixel=0},screen)
corner(icon,4)
make("UIStroke",{Color=blue,Thickness=1.5},icon)
local iconDragged=false
mini.Activated:Connect(function()
    panel.Visible=false
    icon.Visible=true
end)
icon.Activated:Connect(function()
    if iconDragged then return end
    panel.Visible=true
    icon.Visible=false
end)
local operation,activeInput,startPoint,startPos,startSize
local connections={}
local function begin(input,mode)
    if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
    operation=mode
    activeInput=input
    startPoint=input.Position
    startPos=mode=="icon" and icon.Position or panel.Position
    if mode=="icon" then iconDragged=false end
    startSize=panel.AbsoluteSize
end
header.InputBegan:Connect(function(input) begin(input,"drag") end)
grip.InputBegan:Connect(function(input) begin(input,"resize") end)
icon.InputBegan:Connect(function(input) begin(input,"icon") end)
connections[1]=UIS.InputChanged:Connect(function(input)
    if not operation then return end
    local mouse=activeInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement
    if not mouse and input~=activeInput then return end
    local delta=input.Position-startPoint
    local cam=workspace.CurrentCamera
    local view=screen.AbsoluteSize
    if operation=="icon" then
        if delta.Magnitude>6 then iconDragged=true end
        icon.Position=UDim2.fromOffset(
            math.clamp(startPos.X.Offset+delta.X,0,math.max(0,view.X-icon.AbsoluteSize.X)),
            math.clamp(startPos.Y.Offset+delta.Y,0,math.max(0,view.Y-icon.AbsoluteSize.Y)))
    elseif operation=="drag" then
        panel.Position=UDim2.fromOffset(
            math.clamp(startPos.X.Offset+delta.X,0,math.max(0,view.X-panel.AbsoluteSize.X)),
            math.clamp(startPos.Y.Offset+delta.Y,0,math.max(0,view.Y-panel.AbsoluteSize.Y)))
    else
        local maxW=math.max(1,view.X-panel.AbsolutePosition.X-8)
        local maxH=math.max(1,view.Y-panel.AbsolutePosition.Y-8)
        panel.Size=UDim2.fromOffset(math.clamp(startSize.X+delta.X,math.min(310,maxW),maxW),
            math.clamp(startSize.Y+delta.Y,math.min(210,maxH),maxH))
    end
end)
connections[2]=UIS.InputEnded:Connect(function(input)
    if input==activeInput then operation=nil activeInput=nil end
end)
local function fitScreen()
    local view=screen.AbsoluteSize
    if view.X<=0 or view.Y<=0 then return end
    local size=panel.AbsoluteSize
    local w=math.min(size.X,math.max(1,view.X-16))
    local h=math.min(size.Y,math.max(1,view.Y-16))
    panel.Size=UDim2.fromOffset(w,h)
    panel.Position=UDim2.fromOffset(
        math.clamp(panel.Position.X.Offset,0,math.max(0,view.X-w)),
        math.clamp(panel.Position.Y.Offset,0,math.max(0,view.Y-h)))
    icon.Position=UDim2.fromOffset(
        math.clamp(icon.Position.X.Offset,0,math.max(0,view.X-icon.AbsoluteSize.X)),
        math.clamp(icon.Position.Y.Offset,0,math.max(0,view.Y-icon.AbsoluteSize.Y)))
end
connections[3]=screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitScreen)
task.defer(fitScreen)
local ripeSeen=setmetatable({},{__mode="k"})
local lastRipeTeleport=0
jobs.timerDisplay=task.defer(function()
    while alive do
        local now=workspace:GetServerTimeNow()
        if states.harvest and states.ripeReturn then
            local beds=ownedBeds()
            if beds then
                for _,bed in ipairs(beds:GetChildren()) do
                    local marker=bed:FindFirstChild("RipeSparkle")
                    if marker and ripeSeen[bed]~=marker then
                        ripeSeen[bed]=marker
                        ripeReturnPending=true
                    elseif not marker then ripeSeen[bed]=nil end
                end
            end

        else ripeReturnPending=false end
        ui.bag.refresh()
        saleLimit.refresh()
        safeSales.refreshDetected()
        ui.boards.refresh()
        ui.events.refresh()
        dustCycle.status()
        if restockLabel then
            local ok,seconds=pcall(function()
                local config=getStockConfig()
                return config.SecondsLeft(math.floor(now))
            end)
            restockLabel.Text=ok and ("Shop restock: %02d:%02d"):format(math.floor(seconds/60),seconds%60)
                or "StockConfig unavailable; see shop error"
        end
        if tendLabel then
            tendLabel.Text="Animals needing care: "..animalCare.needed..(states.tend and " / ON" or " / OFF")
        end
        for _,item in ipairs(itemIds) do
            buffs.reconcile(item)
            local remaining=math.max(0,math.ceil(deadline(item)-now))
            local clock=remaining>0 and ("%02d:%02d"):format(math.floor(remaining/60),remaining%60) or "Ready"
            local mode=not states[item] and "OFF" or (remaining>0 and "COOLDOWN" or
                (buffs.harvestReady() and "HARVESTING RIPE FRUIT" or "WAITING FOR A RIPE-FRUIT TAP"))
            itemLabels[item].Text=item.." • "..clock.." / "..mode
        end
        task.wait(0.25)
    end
end)
jobs.watchdog=task.defer(function()
    while alive do
        task.wait(5)
        for _,key in ipairs({"harvest","plant","water","dust","seeds","normalSeeds","gears","tend","LuckyCharm","RainbowDew","fairy","candyFairy","sellBoom","houseUpgrade","gardenUpgrade","pickups","wood","fishing","quest","orders","mayor","dig","rearrange"}) do
            local worker=(key=="seeds" or key=="normalSeeds" or key=="gears") and "buyer" or key
            if states[key] and (not jobs[worker] or coroutine.status(jobs[worker])=="dead") then
                movement.release(worker)
                jobs[worker]=nil
                local ok,err=pcall(ui.dispatch,key)
                if not ok then report(key.." retry: "..tostring(err)) end
            end
        end
    end
end)
close.Activated:Connect(function() gui:Destroy() end)
gui.Destroying:Connect(function()
    if config.pending then task.cancel(config.pending) config.pending=nil end
    if states.autoSave then config.save() end
    alive=false
    ui.layout.clearPreview()
    stopAll()
    if jobs.reconnectMonitor then task.cancel(jobs.reconnectMonitor) end
    if jobs.watchdog then task.cancel(jobs.watchdog) end
    if jobs.timerDisplay then task.cancel(jobs.timerDisplay) end
    for _,connection in ipairs(auxiliaryConnections) do connection:Disconnect() end
    for _,connection in ipairs(connections) do connection:Disconnect() end
end)
selectPage("Main")
config.load()

