-- EXIScript: Island Escape module. Client APIs verified against the supplied export.
local function runIslandEscape()
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local UIS = game:GetService("UserInputService")
    local HTTP = game:GetService("HttpService")
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")
    local engineReady = RS:WaitForChild("Engine", 30)
    if not engineReady or not engineReady:WaitForChild("Service", 15) or not engineReady.Service:WaitForChild("Config", 15) then
        warn("EXIScript: Island Escape services are not loaded")
        return
    end
    local previous = pg:FindFirstChild("EXISIslandEscape")
    if previous then
        previous:Destroy()
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "EXISIslandEscape"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 2147483647
    gui.Parent = pg
    local alive = true
    local connections = {}
    local flags = {quest = true, bagUpgrade = true, combat = true}
    local selected = {}
    local modules = {}
    local failed = {}
    local due = {}
    local taskStatus = {}
    local recentErrors = {}
    local opts = {
        move = "Walk",
        interval = 0,
        schedulerVersion = 3,
        avoidEnemies = true,
        dangerRadius = 20,
        baseRadius = 45,
        health = 50,
        hunger = 40,
        fuel = 3,
        tweenSpeed = 32,
        routeTimeout = 15,
        autoJump = true,
        bagLimit = 0,
        jobTimeout = 90,
        huntRadius = 40,
        enemyReach = 4,
        combatMargin = 0.75,
        combatHeight = 2.5,
        retreatHealth = 35,
        safeCombat = true,
    }
    local work = {
        needs = {},
        amounts = {},
        resourceNeeds = {},
        waiting = {},
        sent = 0,
        active = nil,
        buildRemaining = {},
    }
    function work.remaining(info, id, total)
        local progress = info.assetId and work.buildRemaining[info.assetId]
        return progress and type(progress[id]) == "number" and math.max(0, progress[id]) or total
    end
    local path = "exis_island_" .. player.UserId .. "_" .. game.PlaceId .. ".json"
    local blue = Color3.fromRGB(83, 158, 244)
    local white = Color3.fromRGB(226, 234, 245)
    local function make(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do
            o[k] = v
        end
        o.Parent = parent
        return o
    end
    local function corner(o, radius)
        make("UICorner", {
            CornerRadius = UDim.new(0, radius or 6),
        }, o)
    end
    local function round(o)
        corner(o, 6)
    end
    local screen = make("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, gui)
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local width = math.min(392, viewport.X - 20)
    local height = math.min(272, viewport.Y - 20)
    local panel = make("Frame", {
        Size = UDim2.fromOffset(width, height),
        Position = UDim2.fromOffset((viewport.X - width) / 2, (viewport.Y - height) / 2),
        BackgroundColor3 = Color3.fromRGB(8, 12, 18),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, screen)
    corner(panel, 9)
    make("UIStroke", {
        Color = Color3.fromRGB(48, 76, 111),
        Thickness = 1,
    }, panel)
    local header = make("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.fromRGB(17, 22, 31),
        BorderSizePixel = 0,
        Active = true,
    }, panel)
    local title = make("TextLabel", {
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -75, 1, 0),
        BackgroundTransparency = 1,
        Text = "EXIScript | MRBEAST ISLAND ESCAPE",
        TextColor3 = blue,
        Font = Enum.Font.BuilderSansBold,
        TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)
    make("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(175, 209, 255), Color3.fromRGB(105, 125, 152)),
        Rotation = 12,
    }, header)
    make("Frame", {
        Position = UDim2.fromOffset(7, 11),
        Size = UDim2.fromOffset(2, 12),
        BackgroundColor3 = blue,
        BorderSizePixel = 0,
    }, header)
    local function headerButton(text, x)
        local b = make("TextButton", {
            Size = UDim2.fromOffset(25, 23),
            Position = UDim2.new(1, x, 0, 3),
            BackgroundColor3 = Color3.fromRGB(14, 19, 27),
            Text = text,
            TextColor3 = white,
            TextSize = 20,
            Font = Enum.Font.BuilderSans,
        }, header)
        corner(b, 6)
        return b
    end
    local mini = headerButton("−", -57)
    local close = headerButton("×", -29)
    local body = make("Frame", {
        Position = UDim2.fromOffset(0, 30),
        Size = UDim2.new(1, 0, 1, -30),
        BackgroundTransparency = 1,
    }, panel)
    local sidebar = make("ScrollingFrame", {
        Size = UDim2.new(0, 82, 1, 0),
        CanvasSize = UDim2.fromOffset(0, 228),
        ScrollBarThickness = 2,
        BackgroundColor3 = Color3.fromRGB(15, 19, 27),
        BorderSizePixel = 0,
    }, body)
    local content = make("Frame", {
        Position = UDim2.fromOffset(90, 29),
        Size = UDim2.new(1, -99, 1, -51),
        BackgroundTransparency = 1,
    }, body)
    local pageTitle = make("TextLabel", {
        Position = UDim2.fromOffset(91, 0),
        Size = UDim2.new(1, -101, 0, 26),
        BackgroundTransparency = 1,
        Text = "MAIN",
        TextColor3 = white,
        Font = Enum.Font.BuilderSansBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, body)
    make("Frame", {
        Position = UDim2.fromOffset(82, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Color3.fromRGB(31, 43, 59),
        BorderSizePixel = 0,
    }, body)
    make("Frame", {
        Position = UDim2.fromOffset(91, 25),
        Size = UDim2.new(1, -102, 0, 1),
        BackgroundColor3 = Color3.fromRGB(31, 43, 59),
        BorderSizePixel = 0,
    }, body)
    local function button(parent, text, fn)
        local b = make("TextButton", {
            Size = UDim2.new(1, 0, 0, 25),
            Text = text:upper(),
            TextSize = 10,
            Font = Enum.Font.BuilderSans,
            TextColor3 = white,
            BackgroundColor3 = Color3.fromRGB(23, 45, 71),
            BorderSizePixel = 0,
        }, parent)
        round(b)
        b.Activated:Connect(function()
            local ok, e = pcall(fn)
            if not ok then
                warn("EXIScript: " .. tostring(e))
            end
        end)
        return b
    end
    local status = make("TextLabel", {
        Position = UDim2.new(0, 90, 1, -20),
        Size = UDim2.new(1, -95, 0, 18),
        Text = "READY",
        TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = Enum.Font.BuilderSans,
        TextColor3 = blue,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
    local function say(s)
        status.Text = tostring(s)
    end
    local function note(key, message)
        taskStatus[key] = message
    end
    local function safely(key, fn)
        local ok, result = pcall(fn)
        if not ok then
            local message = tostring(result):gsub("^.-:%d+: ", "")
            note(key, "ERROR: " .. message)
            say(key:upper() .. ": " .. message)
            recentErrors[#recentErrors + 1] = key .. ": " .. message
            if #recentErrors > 12 then
                table.remove(recentErrors, 1)
            end
            return false
        end
        return result
    end
    local englishTranslator = nil
    local labelCache = {}
    task.spawn(function()
        pcall(function()
            englishTranslator = game:GetService("LocalizationService"):GetTranslatorForLocaleAsync("en-us")
        end)
    end)
    local function readable(value)
        if type(value) ~= "string" or value == "" then
            return
        end
        if not value:find("[\128-\255]") and value:find("%a") then
            return value
        end
        if labelCache[value] then
            return labelCache[value]
        end
        if englishTranslator then
            local ok, t = pcall(function()
                return englishTranslator:Translate(game, value)
            end)
            if ok and type(t) == "string" and t:find("%a") and not t:find("[\128-\255]") then
                labelCache[value] = t
                return t
            end
        end
    end
    local function itemLabel(kind, id, info, index)
        local c = modules.Config
        local item = c and c.item and c.item.byId and c.item.byId[id]
        for _, entry in ipairs({
            info,
            item or {},
        }) do
            for _, field in ipairs({
                "displayName",
                "DisplayName",
                "englishName",
                "enName",
                "name",
                "assetId",
                "id",
            }) do
                local t = readable(entry[field])
                if t then
                    return t
                end
            end
        end
        return ({
            ["木板1"] = "Wooden Planks",
            ["原始部落宝箱"] = "Tribal Chest",
            ["森林守护者宝箱"] = "Forest Guardian Chest",
        })[id] or readable(tostring(id)) or (kind:upper() .. " " .. string.format("%03d", index or 0))
    end
    local function save()
        if type(writefile) == "function" then
            local ok, e = pcall(function()
                writefile(path, HTTP:JSONEncode({
                    version = 1,
                    flags = flags,
                    selected = selected,
                    options = opts,
                }))
            end)
            if not ok then
                say(e)
            end
        end
    end
    if type(readfile) == "function" then
        pcall(function()
            local d = HTTP:JSONDecode(readfile(path))
            if d.version == 1 then
                if type(d.flags) == "table" then
                    for k, v in pairs(d.flags) do
                        if type(v) == "boolean" then
                            flags[k] = v
                        end
                    end
                end
                if type(d.selected) == "table" then
                    selected = d.selected
                end
                if type(d.options) == "table" then
                    opts.schedulerVersionLoaded = d.options.schedulerVersion == 3
                    if d.options.move == "Walk" or d.options.move == "Teleport" or d.options.move == "Tween" then
                        opts.move = d.options.move
                    end
                    for _, k in ipairs({
                        "interval",
                        "health",
                        "hunger",
                        "fuel",
                        "bagLimit",
                        "jobTimeout",
                        "huntRadius",
                        "enemyReach",
                        "combatMargin",
                        "combatHeight",
                        "retreatHealth",
                    }) do
                        local n = tonumber(d.options[k])
                        if n and n == n and n >= 0 and n < 10000 then
                            opts[k] = n
                        end
                    end
                end
                if type(d.options) == "table" then
                    if type(d.options.safeCombat) == "boolean" then opts.safeCombat = d.options.safeCombat end
                    if type(d.options.autoJump) == "boolean" then
                        opts.autoJump = d.options.autoJump
                    end
                    for key, range in pairs({
                        tweenSpeed = {
                            8,
                            120,
                        },
                        routeTimeout = {
                            6,
                            30,
                        },
                    }) do
                        local n = tonumber(d.options[key])
                        if n and n == n then
                            opts[key] = math.clamp(n, range[1], range[2])
                        end
                    end
                end
            end
        end)
    end
    if not opts.schedulerVersionLoaded then opts.interval = 0 end
    opts.dangerRadius = math.clamp(tonumber(opts.dangerRadius) or 20, 8, 60)
    opts.baseRadius = math.clamp(tonumber(opts.baseRadius) or 45, 15, 100)
    opts.interval = math.clamp(opts.interval, 0, 5)
    opts.huntRadius = math.clamp(opts.huntRadius, 10, 150)
    opts.enemyReach = math.clamp(opts.enemyReach, 1, 20)
    opts.combatMargin = math.clamp(opts.combatMargin, 0.25, 5)
    opts.combatHeight = math.clamp(opts.combatHeight, 1, 10)
    opts.retreatHealth = math.clamp(opts.retreatHealth, 5, 90)
    local function module(name)
        if modules[name] then
            return modules[name]
        end
        if name == "Config" then
            local lib = RS:FindFirstChild("Module")
            local service = lib and lib:FindFirstChild("Service")
            local cloud = service and service:FindFirstChild("CloudConfig")
            local remote = cloud and cloud:FindFirstChild("getAllConfigFunction")
            if remote then
                local ok, data = pcall(function()
                    return remote:InvokeServer()
                end)
                if ok and type(data) == "table" and data.item then
                    modules.Config = data
                    return data
                end
            end
        end
        if failed[name] and os.clock() - failed[name] < 15 then
            return
        end
        local engine = RS:FindFirstChild("Engine")
        local lib = RS:FindFirstChild("Module")
        local source = (engine and engine:FindFirstChild("Service") and engine.Service:FindFirstChild(name)) or (lib and lib:FindFirstChild("Service") and lib.Service:FindFirstChild(name))
        if not source then
            failed[name] = os.clock()
            return
        end
        local ok, m = pcall(require, source)
        if ok then
            modules[name] = m
            return m
        end
        failed[name] = os.clock()
        say(name .. " unavailable")
    end
    local remoteActions = {
        ItemCollect = {
            collect = "collectRemote",
        },
        MakeFire = {
            addWood = "addWoodRemote",
            addFood = "addFoodRemote",
            collectFood = "collectFoodRemote",
        },
        Furnace = {
            addBoth = "addTaskRemote",
            collectResult = "collectResultRemote",
        },
        WaterMaker = {
            collect = "collectRemote",
        },
        CraftItems = {
            craft = "craftRemote",
        },
        BuildBuilding = {
            build = "buildRemote",
        },
        PlayerInventory = {
            dropItem = "dropItemRemote",
        },
        ChestService = {
            requestOpen = "RequestOpenEvent",
            isOpened = "IsOpenedFunction",
            isLocked = "IsLockedFunction",
        },
        PuzzlePropService = {
            requestSolve = "RequestSolveEvent",
            isSolved = "IsSolvedFunction",
        },
        DailyReward = {
            claim = "claimRemote",
        },
        WeekReward = {
            claim = "claimRemote",
        },
        PlayTimeReward = {
            claim = "claimRemote",
        },
        DailyQuest = {
            claim = "claimRemote",
        },
    }
    local function call(name, action, ...)
        local remoteName = remoteActions[name] and remoteActions[name][action]
        if remoteName then
            local source = RS.Engine.Service:FindFirstChild(name)
            local lib = RS:FindFirstChild("Module")
            source = source or (lib and lib:FindFirstChild("Service") and lib.Service:FindFirstChild(name))
            local remote = source and source:FindFirstChild(remoteName)
            assert(remote, name .. " remote unavailable in this server")
            if remote:IsA("RemoteFunction") then
                return remote:InvokeServer(...)
            end
            work.sent = work.sent + 1
            if name == "Furnace" and action == "addBoth" then
                remote:FireServer("both")
            else
                remote:FireServer(...)
            end
            note(name .. "." .. action, "REQUEST SENT")
            return true
        end
        local m = module(name)
        assert(m and m.client and type(m.client[action]) == "function", name .. "." .. action .. " unavailable")
        return m.client[action](...)
    end
    local function world()
        return workspace:FindFirstChild("Game")
    end
    local function serverMode()
        local lib = RS:FindFirstChild("Module")
        local service = lib and lib:FindFirstChild("Service")
        local source = service and service:FindFirstChild("GetServerType")
        local cache = source and source:FindFirstChild("cache")
        if cache and cache:IsA("StringValue") and cache.Value ~= "" then
            return cache.Value == "ReservedServer" and "match" or "lobby"
        end
        local w = world()
        return w and w:FindFirstChild("Static") and w:FindFirstChild("Day") and "match" or "loading"
    end
    local function built(name)
        local w = world()
        local folder = w and w:FindFirstChild("Buildings")
        return folder and folder:FindFirstChild(name)
    end
    local function root()
        local c = player.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        return h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart"), h
    end
    local function pos(o)
        if o:IsA("BasePart") then
            return o.Position
        elseif o:IsA("Model") then
            return o:GetPivot().Position
        end
    end
    local motion = {
        owner = nil,
        serial = 0,
        tween = nil,
        manual = nil,
        blocked = {},
        pulse = nil,
    }
    function motion.cancel(reason)
        motion.serial = motion.serial + 1
        if motion.tween then
            motion.tween:Cancel()
            motion.tween = nil
        end
        local r, h = root()
        if r and h then
            h:MoveTo(r.Position)
        end
        if motion.owner then
            note(motion.owner, reason or "MOVEMENT CANCELLED")
        end
    end
    function motion.water(hit)
        if not hit then
            return false
        end
        if hit.Material == Enum.Material.Water then
            return true
        end
        local node = hit.Instance
        while node and node ~= workspace do
            local n = node.Name:lower()
            if n == "ocean" or n == "water" or n == "sea" then
                return true
            end
            node = node.Parent
        end
        return false
    end
    function motion.floor(point, target, drop, raise)
        local ignore = {}
        if player.Character then
            ignore[#ignore + 1] = player.Character
        end
        if typeof(target) == "Instance" then
            ignore[#ignore + 1] = target
        end
        local w = world()
        if w then
            for _, name in ipairs({
                "DroppedItems",
                "Entities",
            }) do
                local folder = w:FindFirstChild(name)
                if folder then
                    ignore[#ignore + 1] = folder
                end
            end
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = false
        local up = raise or 4
        for _ = 1, 5 do
            params.FilterDescendantsInstances = ignore
            local hit = workspace:Raycast(point + Vector3.new(0, up, 0), Vector3.new(0, -((drop or 8) + up), 0), params)
            if not hit or motion.water(hit) then
                return
            end
            if hit.Instance == workspace.Terrain or hit.Instance.CanCollide then
                if hit.Normal.Y < 0.65 then
                    return
                end
                return hit.Position
            end
            ignore[#ignore + 1] = hit.Instance
        end
    end
    function motion.clearSegment(a, b, target)
        local delta = b - a
        local steps = math.max(1, math.ceil(delta.Magnitude / 2))
        if steps > 240 then
            return false
        end
        for i = 1, steps do
            if not motion.floor(a + delta * (i / steps), target, 7, 3) then
                return false
            end
        end
        return true
    end
    function motion.goals(target, radius)
        local r, h = root()
        local p = typeof(target) == "Vector3" and target or pos(target)
        if not r or not p then
            return {}
        end
        local result = {}
        local distance = math.max(1, math.min(4, radius * 0.6))
        local height = math.max(2, h.HipHeight + r.Size.Y / 2)
        for i = 0, 7 do
            local angle = i * math.pi / 4
            local probe = p + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            local floor = motion.floor(probe, target, 120, 12)
            if floor then
                local stand = floor + Vector3.new(0, height, 0)
                local horizontal = Vector2.new(stand.X - p.X, stand.Z - p.Z).Magnitude
                if horizontal <= radius and math.abs(stand.Y - p.Y) <= math.max(8, radius) then
                    result[#result + 1] = stand
                end
            end
        end
        table.sort(result, function(a, b)
            return (a - r.Position).Magnitude < (b - r.Position).Magnitude
        end)
        return result
    end
    function motion.valid(key, serial, character)
        return alive and work.keyEnabled(key) and serial == motion.serial and player.Character == character and not not root()
            and work.checkpoint(key)
    end
    function motion.pathTo(start, goal)
        local path = game:GetService("PathfindingService"):CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = opts.autoJump ~= false,
            AgentCanClimb = true,
            WaypointSpacing = 3,
            Costs = {
                Water = math.huge,
            },
        })
        local ok = pcall(function()
            path:ComputeAsync(start, goal)
        end)
        if not ok or path.Status ~= Enum.PathStatus.Success then
            return
        end
        return path
    end
    function motion.walkPath(path, goal, key, serial, character, deadline)
        local waypoints = path:GetWaypoints()
        local index = 2
        local blocked = false
        local connection = path.Blocked:Connect(function(i)
            if i >= index then
                blocked = true
            end
        end)
        local ok, result = pcall(function()
            for i = 2, #waypoints do
                index = i
                local r, h = root()
                if not r or not motion.valid(key, serial, character) then
                    return false
                end
                local wp = waypoints[i]
                local jumping = wp.Action == Enum.PathWaypointAction.Jump
                if not work.safeRoute(r.Position, wp.Position, key) then return false end
                if not motion.floor(wp.Position, nil, 8, 4) then
                    note(key, "UNSAFE LANDING - REPLANNING")
                    return false
                end
                if not jumping and not motion.clearSegment(r.Position, wp.Position, nil) then
                    note(key, "WATER OR DROP AHEAD - REPLANNING")
                    return false
                end
                if jumping then
                    if opts.autoJump == false then
                        return false
                    end
                    h.Jump = true
                    h:ChangeState(Enum.HumanoidStateType.Jumping)
                end
                h:MoveTo(wp.Position)
                local last = r.Position
                local progressed = os.clock()
                local attemptedJump = false
                while alive do
                    task.wait()
                    r, h = root()
                    if not r or not motion.valid(key, serial, character) or blocked or os.clock() > deadline then
                        return false
                    end
                    if not work.safeRoute(r.Position, wp.Position, key) then return false end
                    if motion.pulse and motion.pulse() then
                        note(key, "YIELDING TO SURVIVAL")
                        return false
                    end
                    if (r.Position - wp.Position).Magnitude <= math.max(2.2, h.HipHeight + 0.5) then
                        break
                    end
                    if (r.Position - last).Magnitude > 0.5 then
                        last = r.Position
                        progressed = os.clock()
                    elseif os.clock() - progressed > 1 then
                        if opts.autoJump ~= false and not attemptedJump and motion.floor(wp.Position, nil, 8, 4) then
                            h.Jump = true
                            h:ChangeState(Enum.HumanoidStateType.Jumping)
                            attemptedJump = true
                            progressed = os.clock()
                        else
                            note(key, "STUCK - REPLANNING")
                            return false
                        end
                    end
                    if not jumping and h.FloorMaterial ~= Enum.Material.Air then
                        local delta = wp.Position - r.Position
                        if delta.Magnitude > 0.1 and not motion.floor(r.Position + delta.Unit * math.min(2, delta.Magnitude), nil, 7, 2) then
                            h:MoveTo(r.Position)
                            return false
                        end
                    end
                end
            end
            local r = root()
            return r and (r.Position - goal).Magnitude <= 4
        end)
        connection:Disconnect()
        if not ok then
            error(result)
        end
        return result
    end
    function motion.tweenPath(path, goal, key, serial, character, deadline)
        local r, h = root()
        if not r then
            return false
        end
        local points = path:GetWaypoints()
        for i = 2, #points do
            r, h = root()
            if not r or not motion.valid(key, serial, character) then
                return false
            end
            local floor = motion.floor(points[i].Position, nil, 8, 4)
            if not floor then
                note(key, "UNSAFE TWEEN ROUTE")
                return false
            end
            local destination = floor + Vector3.new(0, math.max(2, h.HipHeight + r.Size.Y / 2), 0)
            if not motion.clearSegment(r.Position, destination, nil) then
                note(key, "TWEEN ROUTE CROSSES WATER OR A DROP")
                return false
            end
            if not work.safeRoute(r.Position, destination, key) then return false end
            local delta = destination - r.Position
            if delta.Magnitude > 0.2 then
                local facing = Vector3.new(goal.X, destination.Y, goal.Z)
                local cf = (facing - destination).Magnitude > 0.1 and CFrame.lookAt(destination, facing) or CFrame.new(destination)
                motion.tween = game:GetService("TweenService"):Create(r, TweenInfo.new(math.max(0.05, delta.Magnitude / opts.tweenSpeed), Enum.EasingStyle.Linear), {
                    CFrame = cf,
                })
                motion.tween:Play()
                while motion.tween and motion.tween.PlaybackState == Enum.PlaybackState.Playing do
                    task.wait()
                    if not motion.valid(key, serial, character) or os.clock() > deadline
                        or not work.safeRoute(r.Position, destination, key) or (motion.pulse and motion.pulse()) then
                        motion.tween:Cancel()
                        motion.tween = nil
                        return false
                    end
                end
                motion.tween = nil
            end
        end
        r = root()
        return r and (r.Position - goal).Magnitude <= 4
    end
    local function travel(target, key, radius)
        local r, h = root()
        if not r then
            note(key, "CHARACTER NOT READY")
            return false
        end
        if motion.owner and motion.owner ~= key then
            note(key, "WAITING FOR MOVEMENT")
            return false
        end
        if typeof(target) == "Instance" and motion.blocked[target] and motion.blocked[target] > os.clock() then
            return false
        end
        local character = player.Character
        local serial = motion.serial
        radius = radius or 6
        local p = typeof(target) == "Vector3" and target or pos(target)
        if not p then
            return false
        end
        if not work.checkpoint(key) then return false end
        if not work.safeDestination(p, key) then
            note(key, "ENEMY AREA • DESTINATION DEFERRED")
            return false
        end
        -- Already in range needs no movement, preserving a manually chosen position.
        if (r.Position - p).Magnitude <= radius and motion.floor(r.Position, nil, 8, 3) then
            return true
        end
        motion.owner = key
        local goals = motion.goals(target, radius)
        for i = #goals, 1, -1 do
            if not work.safeDestination(goals[i], key) then table.remove(goals, i) end
        end
        local deadline = os.clock() + opts.routeTimeout
        local ok, result = pcall(function()
            if #goals == 0 then
                note(key, "NO SAFE DRY APPROACH")
                return false
            end
            for index = 1, math.min(3, #goals) do
                r, h = root()
                if not r or not motion.valid(key, serial, character) or os.clock() > deadline then
                    return false
                end
                local goal = goals[index]
                if not work.safeDestination(goal, key) then return false end
                if opts.move == "Teleport" then
                    local facing = Vector3.new(p.X, goal.Y, p.Z)
                    r.CFrame = (goal - facing).Magnitude > 0.1 and CFrame.lookAt(goal, facing) or CFrame.new(goal)
                    task.wait()
                    return motion.valid(key, serial, character)
                end
                local path = motion.pathTo(r.Position, goal)
                if path then
                    note(key, opts.move:upper() .. " - FOLLOWING SAFE ROUTE")
                    local reached = opts.move == "Tween" and motion.tweenPath(path, goal, key, serial, character, deadline) or (opts.move == "Walk" and motion.walkPath(path, goal, key, serial, character, deadline))
                    if reached then
                        return true
                    end
                end
            end
            note(key, "NO REACHABLE DRY ROUTE - TARGET DEFERRED")
            return false
        end)
        if motion.tween then
            motion.tween:Cancel()
            motion.tween = nil
        end
        r, h = root()
        if r and h then
            h:MoveTo(r.Position)
        end
        motion.owner = nil
        if not ok then
            note(key, "MOVEMENT ERROR: " .. tostring(result))
            result = false
        end
        if not result and serial == motion.serial and alive and flags[key] and typeof(target) == "Instance" then
            motion.blocked[target] = os.clock() + 8
        end
        return result == true and motion.valid(key, serial, character)
    end
    local function tools()
        local t = {}
        for _, p in ipairs({
            player:FindFirstChild("Backpack"),
            player.Character,
        }) do
            if p then
                for _, o in ipairs(p:GetChildren()) do
                    if o:IsA("Tool") then
                        t[#t + 1] = o
                    end
                end
            end
        end
        return t
    end
    local function count(name)
        local n = 0
        for _, o in ipairs(tools()) do
            if o.Name == name then
                n = n + (o:GetAttribute("count") or 1)
            end
        end
        return n
    end
    local function equip(t)
        local _, h = root()
        if h and t.Parent ~= player.Character then
            h:EquipTool(t)
            task.wait()
        end
    end
    local function nearest(list, predicate, score)
        local r = root()
        if not r then
            return
        end
        local best, d = nil, math.huge
        for _, o in ipairs(list) do
            if o.Parent and not (motion.blocked[o] and motion.blocked[o] > os.clock()) and predicate(o) then
                local p = pos(o)
                if p then
                    local n = (p - r.Position).Magnitude / (1 + math.max(0, score and score(o) or 0) * 0.05)
                    if n < d then
                        best, d = o, n
                    end
                end
            end
        end
        return best
    end
    local function config()
        local m = module("Config")
        assert(m, "Game config unavailable")
        return m
    end
    local function allowed(kind, id)
        return type(selected[kind]) == "table" and selected[kind][id] == true
    end
    local function selectedEmpty(kind)
        for _, v in pairs(selected[kind] or {}) do
            if v == true then
                return false
            end
        end
        return true
    end
    local function recipeReady(info)
        local c = config()
        local recipe = c.recipe.byId[info.recipeId]
        if not recipe then
            return false
        end
        for k, n in pairs(recipe) do
            local id = type(k) == "string" and k:match("^require_(.+)$")
            if id and type(n) == "number" and n > 0 then
                local item = c.item.byId[id]
                if not item or count(item.displayName) < n then
                    return false
                end
            end
        end
        return true
    end
    local pages = {}
    local groups = {}
    local toggles = {}
    local tabButtons = {}
    local nav = sidebar
    local function page(name)
        local frame = make("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = blue,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(),
            Visible = false,
        }, content)
        make("UIListLayout", {
            Padding = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, frame)
        pages[name] = frame
        local index = 0
        for _ in pairs(tabButtons) do
            index = index + 1
        end
        local b = make("TextButton", {
            Position = UDim2.fromOffset(4, 4 + index * 24),
            Size = UDim2.new(1, -8, 0, 21),
            Text = "  " .. name:upper(),
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = Color3.fromRGB(15, 19, 27),
            BorderSizePixel = 0,
            TextColor3 = white,
            Font = Enum.Font.BuilderSansMedium,
            TextSize = 10,
        }, nav)
        corner(b, 7)
        make("UIStroke", {
            Color = Color3.fromRGB(35, 56, 79),
            Thickness = 1,
        }, b)
        b.Activated:Connect(function()
            pageTitle.Text = name:upper()
            for n, other in pairs(pages) do
                other.Visible = n == name
                tabButtons[n].TextColor3 = n == name and blue or white
                tabButtons[n].BackgroundColor3 = n == name and Color3.fromRGB(23, 45, 71) or Color3.fromRGB(15, 19, 27)
            end
        end)
        tabButtons[name] = b
        nav.CanvasSize = UDim2.fromOffset(0, 4 + (index + 1) * 24)
        return frame
    end
    local function text(container, text)
        return make("TextLabel", {
            Size = UDim2.new(1, -8, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = text,
            TextWrapped = true,
            TextSize = 10,
            TextColor3 = Color3.fromRGB(156, 175, 198),
            Font = Enum.Font.BuilderSans,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }, container)
    end
    local function group(container, name)
        local frame = make("Frame", {
            Size = UDim2.new(1, -4, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Color3.fromRGB(16, 22, 31),
            BorderSizePixel = 0,
        }, container)
        corner(frame, 6)
        local border = make("UIStroke", {
            Color = Color3.fromRGB(32, 44, 61),
            Thickness = 1,
        }, frame)
        make("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 0),
        }, frame)
        local header = make("TextButton", {
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
        }, frame)
        make("TextLabel", {
            Position = UDim2.fromOffset(9, 0),
            Size = UDim2.new(1, -35, 1, 0),
            BackgroundTransparency = 1,
            Text = name:upper(),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = white,
            TextSize = 10,
            Font = Enum.Font.BuilderSansMedium,
        }, header)
        local arrow = make("TextLabel", {
            Position = UDim2.new(1, -24, 0, 0),
            Size = UDim2.fromOffset(20, 25),
            BackgroundTransparency = 1,
            Text = "›",
            TextColor3 = Color3.fromRGB(126, 149, 179),
            TextSize = 17,
            Font = Enum.Font.BuilderSans,
        }, header)
        local body = make("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Visible = false,
        }, frame)
        make("UIPadding", {
            PaddingLeft = UDim.new(0, 6),
            PaddingRight = UDim.new(0, 6),
            PaddingTop = UDim.new(0, 2),
            PaddingBottom = UDim.new(0, 5),
        }, body)
        make("UIListLayout", {
            Padding = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, body)
        local accent = make("Frame", {
            Position = UDim2.fromOffset(0, 7),
            Size = UDim2.fromOffset(2, 11),
            BackgroundColor3 = blue,
            BackgroundTransparency = 0.7,
            BorderSizePixel = 0,
        }, header)
        local entry = {
            frame = frame,
            body = body,
        }
        function entry.setOpen(open)
            body.Visible = open
            arrow.Text = open and "⌄" or "›"
            arrow.TextColor3 = open and blue or Color3.fromRGB(126, 149, 179)
            border.Color = open and Color3.fromRGB(49, 88, 135) or Color3.fromRGB(32, 44, 61)
            frame.BackgroundColor3 = open and Color3.fromRGB(18, 27, 39) or Color3.fromRGB(16, 22, 31)
            accent.BackgroundTransparency = open and 0 or 0.7
            if not open then
                for _, other in ipairs(groups) do
                    if other.frame:IsDescendantOf(body) then
                        other.setOpen(false)
                    end
                end
            end
        end
        groups[#groups + 1] = entry
        header.Activated:Connect(function()
            local open = not body.Visible
            if open then
                for _, other in ipairs(groups) do
                    if other ~= entry and other.frame.Parent == frame.Parent then
                        other.setOpen(false)
                    end
                end
            end
            entry.setOpen(open)
        end)
        return body
    end
    local function switch(p, label, get, set)
        local b = button(p, "", function()
            set(not get())
            save()
        end)
        b.BackgroundColor3 = Color3.fromRGB(21, 30, 43)
        make("TextLabel", {
            Position = UDim2.fromOffset(7, 0),
            Size = UDim2.new(1, -53, 1, 0),
            Text = label:upper(),
            TextSize = 10,
            TextWrapped = true,
            Font = Enum.Font.BuilderSans,
            TextColor3 = white,
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, b)
        local track = make("Frame", {
            Position = UDim2.new(1, -33, 0.5, -6),
            Size = UDim2.fromOffset(25, 12),
            BorderSizePixel = 0,
        }, b)
        round(track)
        local knob = make("Frame", {
            Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = white,
            BorderSizePixel = 0,
        }, track)
        round(knob)
        local function render()
            track.BackgroundColor3 = get() and blue or Color3.fromRGB(47, 59, 75)
            knob.Position = UDim2.fromOffset(get() and 15 or 2, 2)
        end
        b.Activated:Connect(render)
        render()
        return render
    end
    local function toggle(p, key, label, description)
        toggles[key] = switch(p, label, function()
            return flags[key] == true
        end, function(value)
            flags[key] = value
            note(key, value and "ENABLED" or "OFF")
            toggles[key]()
        end)
        if description then
            text(p, description)
        end
    end
    local function number(p, key, label, min, max)
        text(p, label)
        local b = make("TextBox", {
            Size = UDim2.new(1, 0, 0, 26),
            Text = tostring(opts[key]),
            ClearTextOnFocus = false,
            TextSize = 11,
            Font = Enum.Font.BuilderSans,
            TextColor3 = white,
            BackgroundColor3 = Color3.fromRGB(21, 32, 47),
        }, p)
        round(b)
        b.FocusLost:Connect(function()
            local n = tonumber(b.Text)
            if n and n == n and n < math.huge then
                opts[key] = math.clamp(n, min, max)
                save()
            end
            b.Text = tostring(opts[key])
        end)
    end
    local main = page("Main")
    local resources = page("Gather")
    local camp = page("Camp")
    local craft = page("Craft")
    local questPage = page("Quests")
    local explore = page("Explore")
    local settings = page("Settings")
    local survival = group(main, "SURVIVAL")
    toggle(survival, "eat", "Auto eat", "Uses selected food when health or hunger is low. No selection uses food listed in the game config.")
    number(survival, "health", "HEALTH BELOW (%)", 1, 100)
    number(survival, "hunger", "HUNGER BELOW (%)", 1, 100)
    local combat = group(main, "DEFENCE")
    toggle(combat, "combat", "Auto defend base / nearby enemies", "Base threats interrupt ordinary work. Attacks from checked swarm edges, repositions, and retreats on danger.")
    switch(combat, "AVOID ENEMIES WHILE WORKING", function() return opts.avoidEnemies end, function(v) opts.avoidEnemies = v end)
    number(combat, "dangerRadius", "ENEMY AVOIDANCE RADIUS", 8, 60)
    number(combat, "baseRadius", "BASE DEFENCE RADIUS", 15, 100)
    toggle(combat, "hunt", "Auto hunt / kill enemies", "Hunts within the selected radius after urgent survival and progression work.")
    switch(combat, "PREFER LOWER-RISK ATTACK POSITIONS", function() return opts.safeCombat end, function(v) opts.safeCombat = v end)
    number(combat, "huntRadius", "HUNT RADIUS", 10, 150)
    number(combat, "enemyReach", "ENEMY REACH ESTIMATE (STUDS)", 1, 20)
    number(combat, "retreatHealth", "RETREAT BELOW HEALTH (%)", 5, 90)
    text(combat, "Uses visible proximity and approach as threat estimates. Prefers the outside of a swarm with clear sight. Hidden AI / attack reach can still cause damage.")
    local upgrades = group(main, "UPGRADE PROGRESSION")
    toggle(upgrades, "progression", "Auto upgrade / gather missing materials", "One target at a time: active campfire blueprint, basic tools, next campfire level, tools and available buildings. Submits partial materials when the bag fills.")
    text(upgrades, "Automatically gathers required resources and collects required drops. Selected craft recipes are included. Unavailable goals retry later.")
    work.upgradeLabel = text(upgrades, "UPGRADE: WAITING")
    toggle(upgrades, "bagUpgrade", "Prioritize larger bags", "Collects and equips better bags even when full. Progression crafts available station bag recipes and prioritizes bag rewards.")
    local fishing = group(main, "FISHING")
    toggle(fishing, "fish", "Auto cast and reel", "Equip a rod and face water. Casts and reels automatically; complete the fish minigame normally. Movement pauses only during an active cast.")
    local gather = group(resources, "RESOURCE FARMING")
    toggle(gather, "gather", "Auto gather selected resources", "Cuts one resource fully, then collects all its loaded drops before another tree. Full bags retain a recovery job. No selection = all resource types.")
    local drops = group(resources, "DROPPED ITEMS")
    toggle(drops, "drops", "Auto collect drops", "All unprotected drops when no items are selected below. Respects owner protection.")
    local fire = group(camp, "CAMPFIRE")
    toggle(fire, "fuel", "Auto add wood", "Adds wood only below the fuel target.")
    number(fire, "fuel", "FUEL TARGET (WOOD)", 1, 100)
    toggle(fire, "cook", "Auto cook food", "Uses selected cookable food. No selection uses all cookable food from the game config.")
    toggle(fire, "cooked", "Auto collect cooked food")
    button(fire, "ADD ONE WOOD / REFRESH FUEL STATE", function()
        assert(built("Campfire"), "Build the campfire first")
        call("MakeFire", "addWood")
    end)
    local furnace = group(camp, "FURNACE")
    toggle(furnace, "smelt", "Auto feed furnace", "Consumes smelting ingredients.")
    toggle(furnace, "smeltCollect", "Auto collect results")
    local water = group(camp, "WATER MAKER")
    toggle(water, "water", "Auto collect coconuts")
    local crafting = group(craft, "TOOLS AND ARMOUR")
    toggle(crafting, "craft", "Auto craft selected items", "Crafts one missing selected item when materials are available.")
    local building = group(craft, "CONSTRUCTION")
    toggle(building, "build", "Auto contribute selected buildings", "Spends recipe materials on selected unfinished buildings.")
    toggle(building, "buildCurrent", "Auto build active blueprints", "Uses owned materials on available unfinished buildings, including the first campfire. No selection required.")
    local questBody = group(questPage, "MRBEAST QUESTS")
    toggle(questBody, "quest", "Auto MrBeast requests", "Important progression work below immediate defence and survival. Included in progression. Stores needed items near MrBeast if a request exceeds bag capacity.")
    local questInfo = text(questBody, "QUEST: WAITING")
    local rewards = group(questPage, "REWARDS")
    toggle(rewards, "daily", "Auto daily reward")
    toggle(rewards, "weekly", "Auto weekly reward")
    toggle(rewards, "playtime", "Auto playtime rewards")
    toggle(rewards, "dailyQuest", "Claim completed daily quests")
    local chestUI = group(explore, "CHESTS AND PUZZLES")
    toggle(chestUI, "chests", "Auto open unlocked chests")
    toggle(chestUI, "puzzles", "Auto interact with puzzle props")
    local escape = group(explore, "ESCAPE BOAT")
    toggle(escape, "escape", "Auto use available escape boat", "Uses the boat interaction when its prompt is enabled. Ends your run.")
    local destination = group(explore, "BUILDING TRAVEL")
    local session = group(settings, "SESSION")
    toggle(session, "antiAfk", "Anti idle")
    toggle(session, "autoExecute", "Auto execute after teleport", "Reloads EXIScript when entering the match if your executor supports teleport queues.")
    button(session, "SAVE CONFIG", save)
    button(session, "RECHECK BAG / COLLECTION", function()
        work.blockedBag = nil
        work.rejectedPickups = 0
        due.drops = 0
        due.gather = 0
        say("BAG COLLECTION RETRY ENABLED")
    end)
    local function stopAll()
        motion.manual = nil
        motion.cancel("ALL TASKS STOPPED")
        for k in pairs(flags) do
            flags[k] = false
        end
        for _, render in pairs(toggles) do
            render()
        end
        local r, h = root()
        if r and h then
            h:MoveTo(r.Position)
        end
        save()
        say("ALL TASKS STOPPED")
    end
    button(session, "STOP ALL", stopAll)
    local moveButton
    moveButton = button(session, "MOVE: " .. opts.move, function()
        motion.cancel("MOVEMENT MODE CHANGED")
        opts.move = opts.move == "Walk" and "Teleport" or (opts.move == "Teleport" and "Tween" or "Walk")
        moveButton.Text = "MOVE: " .. opts.move:upper()
        save()
    end)
    number(session, "tweenSpeed", "TWEEN SPEED (STUDS / SECOND)", 8, 120)
    number(session, "routeTimeout", "ROUTE TIMEOUT (SECONDS)", 6, 30)
    number(session, "bagLimit", "BAG CAPACITY OVERRIDE (0 = DETECT)", 0, 10000)
    number(session, "jobTimeout", "TASK SAFETY TIMEOUT (SECONDS)", 15, 600)
    switch(session, "AUTO JUMP WHEN BLOCKED", function()
        return opts.autoJump
    end, function(v)
        opts.autoJump = v
        motion.cancel("JUMP OPTION CHANGED")
    end)
    text(session, "Walk uses dry paths, jump waypoints and stuck recovery. Tween follows checked paths. Teleport uses a dry landing; blocked routes are skipped.")
    local jobGroup = group(settings, "TASK PRIORITIES")
    text(jobGroup, "LEVEL 0: EVADE • 1: BASE DEFENCE • 2–6: SURVIVAL / FIRE / ESCAPE • 7–14: REWARDS / BAGS / REQUESTS / UPGRADES • 15–30: SUPPLIES / GATHER / HUNT / EXPLORE / FISH")
    text(jobGroup, "Lower number = higher priority. Higher jobs interrupt at frame checkpoints. Equal / lower jobs wait. Unfinished work stays enabled and resumes when safe.")
    local queueLabel = text(jobGroup, "JOB: IDLE")
    for _, category in ipairs({
        {
            "SURVIVAL",
            {
                "eat",
                "combat",
                "hunt",
            },
        },
        {
            "GATHER",
            {
                "gather",
                "drops",
            },
        },
        {
            "CAMP",
            {
                "fuel",
                "cook",
                "cooked",
                "smelt",
                "smeltCollect",
                "water",
            },
        },
        {
            "PROGRESSION",
            {
                "progression",
                "bagUpgrade",
            },
        },
        {
            "CRAFT",
            {
                "craft",
                "build",
                "buildCurrent",
            },
        },
        {
            "QUESTS",
            {
                "quest",
                "daily",
                "weekly",
                "playtime",
                "dailyQuest",
            },
        },
        {
            "EXPLORE",
            {
                "escape",
                "chests",
                "puzzles",
                "travel",
            },
        },
        {
            "FISHING",
            {
                "fish",
            },
        },
    }) do
        local categoryName, keys = category[1], category[2]
        button(jobGroup, "STOP " .. categoryName, function()
            for _, key in ipairs(keys) do
                flags[key] = false
                if toggles[key] then
                    toggles[key]()
                end
                if motion.owner == key then
                    motion.cancel("CATEGORY STOPPED")
                end
            end
            save()
        end)
    end
    number(session, "interval", "ACTION DELAY (SECONDS; 0 = NEXT FRAME)", 0, 5)
    local diag = group(settings, "DIAGNOSTICS")
    button(diag, "CHECK GAME SERVICES", function()
        local ready = {}
        for _, n in ipairs({
            "Config",
            "ItemCollect",
            "MakeFire",
            "Furnace",
            "CraftItems",
            "BuildBuilding",
            "MrbeastQuest",
            "ChestService",
        }) do
            ready[#ready + 1] = n .. ": " .. (module(n) and "OK" or "UNAVAILABLE")
        end
        say(table.concat(ready, " | "))
    end)
    local diagnosticText = text(diag, "NO ERRORS RECORDED")
    local function refreshDiagnostics()
        local lines = {}
        for key in pairs(toggles) do
            lines[#lines + 1] = key:upper() .. ": " .. (flags[key] and (taskStatus[key] or "WAITING") or "OFF")
        end
        table.sort(lines)
        diagnosticText.Text = "QUEUE: " .. tostring(taskStatus.queue or "IDLE") .. "\nMOVEMENT: " .. tostring(motion.owner or "IDLE") .. "\n" .. table.concat(lines, "\n") .. "\n\nRECENT ERRORS\n" .. (#recentErrors > 0 and table.concat(recentErrors, "\n") or "NONE")
    end
    button(diag, "COPY DIAGNOSTICS", function()
        refreshDiagnostics()
        assert(type(setclipboard) == "function", "Clipboard unavailable")
        setclipboard(diagnosticText.Text)
        say("DIAGNOSTICS COPIED")
    end)
    local modeLabel = text(main, "SERVER: CHECKING")
    local clockLabel = text(main, "DAY / PHASE: WAITING")
    connections[#connections + 1] = player.OnTeleport:Connect(function(state)
        if not flags.autoExecute or state ~= Enum.TeleportState.Started then
            return
        end
        local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
        if type(queue) ~= "function" then
            say("TELEPORT QUEUE NOT SUPPORTED")
            return
        end
        save()
        queue('loadstring(game:HttpGet("https://raw.githubusercontent.com/iaxen/EXIScript/main/EXIScript.lua"))()')
    end)
    local grip = make("TextButton", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(1, 1),
        Size = UDim2.fromOffset(25, 22),
        BackgroundTransparency = 1,
        Text = "◢",
        TextColor3 = blue,
        TextSize = 17,
        Active = true,
    }, panel)
    local icon = make("TextButton", {
        Name = "OpenEXISIslandEscape",
        Size = UDim2.fromOffset(32, 32),
        Position = UDim2.fromOffset(12, 90),
        BackgroundColor3 = Color3.fromRGB(8, 15, 25),
        Text = "EXIS",
        TextColor3 = Color3.fromRGB(240, 247, 255),
        Font = Enum.Font.BuilderSansBold,
        TextSize = 10,
        Visible = false,
        BorderSizePixel = 0,
    }, screen)
    corner(icon, 4)
    make("UIStroke", {
        Color = blue,
        Thickness = 1.5,
    }, icon)
    close.Activated:Connect(function()
        stopAll()
        gui:Destroy()
    end)
    local iconDragged = false
    mini.Activated:Connect(function()
        panel.Visible = false
        icon.Visible = true
    end)
    icon.Activated:Connect(function()
        if iconDragged then
            return
        end
        panel.Visible = true
        icon.Visible = false
    end)
    local operation, activeInput, startPoint, startPos, startSize
    local function begin(input, mode)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        operation = mode
        activeInput = input
        startPoint = input.Position
        startPos = mode == "icon" and icon.Position or panel.Position
        if mode == "icon" then
            iconDragged = false
        end
        startSize = panel.AbsoluteSize
    end
    header.InputBegan:Connect(function(input)
        begin(input, "drag")
    end)
    grip.InputBegan:Connect(function(input)
        begin(input, "resize")
    end)
    icon.InputBegan:Connect(function(input)
        begin(input, "icon")
    end)
    connections[#connections + 1] = UIS.InputChanged:Connect(function(input)
        if not operation then
            return
        end
        local mouse = activeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
        if not mouse and input ~= activeInput then
            return
        end
        local delta = input.Position - startPoint
        local cam = workspace.CurrentCamera
        local view = screen.AbsoluteSize
        if operation == "icon" then
            if delta.Magnitude > 6 then
                iconDragged = true
            end
            icon.Position = UDim2.fromOffset(math.clamp(startPos.X.Offset + delta.X, 0, math.max(0, view.X - icon.AbsoluteSize.X)), math.clamp(startPos.Y.Offset + delta.Y, 0, math.max(0, view.Y - icon.AbsoluteSize.Y)))
        elseif operation == "drag" then
            panel.Position = UDim2.fromOffset(math.clamp(startPos.X.Offset + delta.X, 0, math.max(0, view.X - panel.AbsoluteSize.X)), math.clamp(startPos.Y.Offset + delta.Y, 0, math.max(0, view.Y - panel.AbsoluteSize.Y)))
        else
            local maxW = math.max(1, view.X - panel.AbsolutePosition.X - 8)
            local maxH = math.max(1, view.Y - panel.AbsolutePosition.Y - 8)
            panel.Size = UDim2.fromOffset(math.clamp(startSize.X + delta.X, math.min(310, maxW), maxW), math.clamp(startSize.Y + delta.Y, math.min(210, maxH), maxH))
        end
    end)
    connections[#connections + 1] = UIS.InputEnded:Connect(function(input)
        if input == activeInput then
            operation = nil
            activeInput = nil
        end
    end)
    local function fitScreen()
        local view = screen.AbsoluteSize
        if view.X <= 0 or view.Y <= 0 then
            return
        end
        local size = panel.AbsoluteSize
        local w = math.min(size.X, math.max(1, view.X - 16))
        local h = math.min(size.Y, math.max(1, view.Y - 16))
        panel.Size = UDim2.fromOffset(w, h)
        panel.Position = UDim2.fromOffset(math.clamp(panel.Position.X.Offset, 0, math.max(0, view.X - w)), math.clamp(panel.Position.Y.Offset, 0, math.max(0, view.Y - h)))
        icon.Position = UDim2.fromOffset(math.clamp(icon.Position.X.Offset, 0, math.max(0, view.X - icon.AbsoluteSize.X)), math.clamp(icon.Position.Y.Offset, 0, math.max(0, view.Y - icon.AbsoluteSize.Y)))
    end
    connections[#connections + 1] = screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitScreen)
    task.defer(fitScreen)
    connections[#connections + 1] = player.Idled:Connect(function()
        if flags.antiAfk then
            pcall(function()
                local v = game:GetService("VirtualUser")
                v:CaptureController()
                v:ClickButton2(Vector2.new())
            end)
        end
    end)
    gui.Destroying:Connect(function()
        alive = false
        motion.cancel("UI CLOSED")
        for _, c in ipairs(connections) do
            c:Disconnect()
        end
        local r, h = root()
        if r and h then
            h:MoveTo(r.Position)
        end
    end)
    pages.Main.Visible = true
    tabButtons.Main.TextColor3 = blue
    tabButtons.Main.BackgroundColor3 = Color3.fromRGB(23, 45, 71)
    task.spawn(function()
        local ok, e = pcall(function()
            local c = config()
            local function choices(parent, kind, rows, predicate)
                local g = group(parent, "SELECT " .. kind)
                selected[kind] = selected[kind] or {}
                local ids = {}
                for id, info in pairs(rows or {}) do
                    if type(info) == "table" and (not predicate or predicate(info)) then
                        ids[#ids + 1] = id
                    end
                end
                table.sort(ids, function(a, b)
                    return tostring(a) < tostring(b)
                end)
                local renders = {}
                button(g, "SELECT ALL", function()
                    for _, id in ipairs(ids) do
                        selected[kind][id] = true
                    end
                    for _, r in ipairs(renders) do
                        r()
                    end
                    save()
                end)
                button(g, "CLEAR SELECTION", function()
                    selected[kind] = {}
                    for _, r in ipairs(renders) do
                        r()
                    end
                    save()
                end)
                for index, id in ipairs(ids) do
                    local item = rows[id]
                    local key = id
                    renders[#renders + 1] = switch(g, itemLabel(kind, id, item, index), function()
                        return selected[kind][key] == true
                    end, function(v)
                        selected[kind][key] = v
                    end)
                end
            end
            choices(resources, "resources", c.worldResource.byId)
            choices(resources, "drops", c.item.byId)
            choices(main, "food", c.food.byId)
            choices(camp, "cook", c.food.byId, function(i)
                return i.canCook == true
            end)
            choices(craft, "craft", c.item.byId, function(i)
                return i.recipeId and (i.type == "tool" or i.type == "armour")
            end)
            choices(craft, "build", c.build.byId)
            for _, info in ipairs(c.build.list or {}) do
                local name = info.assetId
                if type(name) == "string" then
                    button(destination, "GO TO " .. itemLabel("building", info.id or name, info), function()
                        local w = world()
                        local b = w and w:FindFirstChild("Buildings")
                        local target = b and (b:FindFirstChild(name) or b:FindFirstChild(name .. "_Construct"))
                        if target then
                            motion.manual = {
                                target = target,
                            }
                            flags.travel = true
                            say("TRAVEL QUEUED")
                        else
                            say("BUILDING NOT LOADED")
                        end
                    end)
                end
            end
        end)
        if not ok then
            say(e)
        end
    end)
    -- Reward data is read from the game's real replicated state.
    local rewardData = {}
    local campData = {}
    local furnaceData = {}
    for _, binding in ipairs({
        {
            "DailyReward",
            "onSync",
            "daily",
        },
        {
            "WeekReward",
            "onSync",
            "week",
        },
        {
            "PlayTimeReward",
            "sync",
            "play",
        },
        {
            "DailyQuest",
            "sync",
            "quest",
        },
    }) do
        task.spawn(function()
            safely("sync " .. binding[1], function()
                call(binding[1], binding[2], function(v)
                    rewardData[binding[3]] = v
                end)
            end)
        end)
    end
    task.spawn(function()
        local function syncRemote(name, fn)
            local m = RS:FindFirstChild("Engine")
            m = m and m:FindFirstChild("Service")
            m = m and m:FindFirstChild(name)
            local e = m and m:FindFirstChild("syncRemote")
            if e then
                connections[#connections + 1] = e.OnClientEvent:Connect(fn)
            end
        end
        syncRemote("MakeFire", function(v)
            if type(v) == "table" then
                campData = v
            end
        end)
        syncRemote("Furnace", function(v)
            if type(v) == "table" then
                furnaceData = v
            end
        end)
    end)
    task.spawn(function()
        local source = RS.Engine.Service:FindFirstChild("BuildBuilding")
        local event = source and source:WaitForChild("progressChangedRemote", 10)
        if alive and event then
            connections[#connections + 1] = event.OnClientEvent:Connect(function(assetId, remaining)
                if type(assetId) == "string" and type(remaining) == "table" then
                    work.buildRemaining[assetId] = remaining
                    local c = modules.Config
                    local info = c and c.build.byId[assetId]
                    if info then work.buildRemaining[info.assetId] = remaining end
                    work.refreshAt = 0
                end
            end)
        end
    end)
    -- Inventory acknowledgement stays inside the scheduler's active task.
    function work.inventory()
        local result = {}
        for _, tool in ipairs(tools()) do
            result[tool.Name] = (result[tool.Name] or 0) + (tonumber(tool:GetAttribute("count")) or 1)
        end
        return result
    end
    function work.signature()
        local rows = {}
        for name, amount in pairs(work.inventory()) do
            rows[#rows + 1] = name .. "=" .. tostring(amount)
        end
        table.sort(rows)
        return table.concat(rows, "|")
    end
    function work.running(key, character, serial)
        return alive and work.keyEnabled(key) and player.Character == character
            and motion.serial == serial and not not root() and work.checkpoint(key)
    end
    function work.await(key, predicate, seconds)
        local character, serial = player.Character, motion.serial
        local deadline = os.clock() + (seconds or 3)
        repeat
            if predicate() then return true end
            if not work.running(key, character, serial) then return false end
            task.wait()
        until os.clock() >= deadline
        return false
    end
    function work.request(key, name, action, ...)
        local before = work.signature()
        call(name, action, ...)
        local confirmed = work.await(key, function()
            return work.signature() ~= before
        end, 3)
        note(key, confirmed and "INVENTORY CHANGE CONFIRMED" or "NO INVENTORY CHANGE; RETRY LATER")
        return confirmed
    end
    function work.bagState()
        local c, used = config(), nil
        local inventory = module("PlayerInventory")
        local api = inventory and inventory.client
        if api and type(api.getBagItemCount) == "function" then
            local ok, value = pcall(api.getBagItemCount, player)
            if ok and type(value) == "number" then used = value end
        end
        if not used then
            used = 0
            for _, tool in ipairs(tools()) do
                local info = c.item.byDisplayName[tool.Name]
                if info and info.isBagItem then used = used + (tonumber(tool:GetAttribute("count")) or 1) end
            end
        end
        local bag = c.bag and c.bag.byId and c.bag.byId[player:GetAttribute("bagId")]
        local cap = opts.bagLimit > 0 and opts.bagLimit or
            ((bag and bag.cap or c.misc.defaultBagSlots) + (tonumber(player:GetAttribute("bagSlotsBonus")) or 0))
        note("inventory", "BAG: " .. used .. " / " .. cap)
        return used, cap
    end
    function work.canCollect()
        local signature = work.signature()
        if work.blockedBag and work.blockedBag == signature then
            return false
        end
        work.blockedBag = nil
        local used, cap = work.bagState()
        if used and cap and used >= cap then
            note("inventory", "BAG FULL: PROCESS OR SUBMIT ITEMS FIRST")
            return false
        end
        return true
    end
    function work.foodAllowed(kind, id)
        local food = config().food.byId[id]
        return food and (selectedEmpty(kind) or allowed(kind, id))
            and (kind ~= "cook" or food.canCook == true)
    end
    function work.cookReady()
        if not built("Campfire") then
            return false
        end
        for id, item in pairs(config().item.byId) do
            if work.foodAllowed("cook", id) and count(item.displayName) > 0 then
                return true
            end
        end
        return false
    end
    function work.cook()
        local rows = config().item.byId
        local ids = {}
        for id, item in pairs(rows) do
            if work.foodAllowed("cook", id) and count(item.displayName) > 0 then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids, function(a, b)
            return tostring(a) < tostring(b)
        end)
        for _, id in ipairs(ids) do
            if count(rows[id].displayName) > 0 then
                if not travel(built("Campfire"), "cook") then
                    return false
                end
                return work.request("cook", "MakeFire", "addFood", id)
            end
        end
        return false
    end
    function work.fuelItem()
        local c = config()
        local info = c.build.byId.campfire
        local fuel = info and info.config and info.config["燃料"]
        return fuel and c.item.byName[fuel]
    end
    function work.fuel()
        local fire = built("Campfire")
        local item = work.fuelItem()
        if not fire or not item or count(item.displayName) <= 0 then
            note("fuel", "NEED CAMPFIRE WOOD")
            return false
        end
        if not travel(fire, "fuel") then
            return false
        end
        local before = campData.campfireWoodCount
        if before == nil then
            work.fuelProbe = true
        end
        local bagBefore = count(item.displayName)
        call("MakeFire", "addWood")
        local confirmed = work.await("fuel", function()
            return count(item.displayName) < bagBefore
                or (type(campData.campfireWoodCount) == "number"
                    and (before == nil or campData.campfireWoodCount > before))
        end, 3)
        note("fuel", confirmed and "WOOD ADDED" or "FUEL NOT CONFIRMED")
        return confirmed
    end
    local function eat()
        local r, h = root()
        if not r then
            return
        end
        local hunger = h:GetAttribute("hunger")
        local max = h:GetAttribute("maxHunger") or 100
        if h.Health / h.MaxHealth * 100 > opts.health and (not hunger or hunger / max * 100 > opts.hunger) then
            return
        end
        local c = config()
        for _, t in ipairs(tools()) do
            local info = c.item.byDisplayName[t.Name]
            if info and work.foodAllowed("food", info.id) then
                equip(t)
                local before = work.signature()
                local health, hungerBefore = h.Health, h:GetAttribute("hunger")
                t:Activate()
                local confirmed = work.await("eat", function()
                    return work.signature() ~= before or h.Health > health
                        or (hungerBefore and (h:GetAttribute("hunger") or 0) > hungerBefore)
                end, 3)
                note("eat", confirmed and "FOOD USED" or "FOOD USE NOT CONFIRMED")
                return confirmed
            end
        end
        note("eat", "SELECT FOOD YOU OWN")
    end
    function work.dropAllowed(model)
        if not model.Parent or model:GetAttribute("collecting") then return false end
        local owner = model:GetAttribute("ownerName")
        if owner and owner ~= player.Name then
            local lock = tonumber(model:GetAttribute("lockedFor_" .. owner)) or 0
            local untilTime = tonumber(model:GetAttribute("protectEndTick")) or 0
            if math.max(lock, untilTime) > workspace:GetServerTimeNow() then return false end
        end
        return true
    end
    function work.collectModel(model, key, bag)
        if not work.dropAllowed(model) then return false end
        if not bag and not work.canCollect() then return false end
        local radius = math.max(0.5, (tonumber(config().misc.collectRadius) or 3) * 1.5)
        if not travel(model, key, radius) then return false end
        local before, bagId = count(model.Name), player:GetAttribute("bagId")
        call("ItemCollect", "collect", model)
        local confirmed = work.await(key, function()
            return bag and player:GetAttribute("bagId") ~= bagId or count(model.Name) > before
        end, 2)
        if confirmed then work.blockedBag = nil work.rejectedPickups = 0 end
        return confirmed
    end
    function work.treeDropContext(resource)
        local scene = world()
        local folder = scene and scene:FindFirstChild("DroppedItems")
        local c, wanted, before = config(), {}, {}
        local info = c.worldResource.byId[resource:GetAttribute("resourceId")]
        for _, entry in pairs(info and c.itemDrop.byId[info.dropId] or {}) do
            local item = type(entry) == "table" and c.item.byName[entry.itemCN]
            if item then wanted[item.id] = true end
        end
        if folder then for _, model in ipairs(folder:GetChildren()) do before[model] = true end end
        return {center = pos(resource), before = before, wanted = wanted, key = nil, seen = false}
    end
    function work.drainTreeDrops(context, key)
        local scene = world()
        local folder = scene and scene:FindFirstChild("DroppedItems")
        if not folder or not context.center then return true end
        local c, quietSince, started = config(), os.clock(), os.clock()
        local deadline = started + math.clamp(opts.jobTimeout, 15, 600)
        local character, serial = player.Character, motion.serial
        while work.running(key, character, serial) and os.clock() < deadline do
            local target = nearest(folder:GetChildren(), function(model)
                local info, point = c.item.byDisplayName[model.Name], pos(model)
                return info and point and context.wanted[info.id] and not context.before[model]
                    and work.dropAllowed(model) and (point - context.center).Magnitude <= 12
            end)
            if target then
                context.seen = true
                if not work.canCollect() then
                    note(key, "BAG FULL • TREE DROPS SAVED FOR RECOVERY")
                    return false
                end
                if not work.collectModel(target, key) then
                    note(key, "TREE DROP UNCONFIRMED • RETRY BEFORE NEXT TREE")
                    return false
                end
                quietSince = os.clock()
            else
                local settle = context.seen and 0.12 or 0.5
                if os.clock() - quietSince >= settle then return true end
                task.wait()
            end
        end
        return false
    end
    function work.recoverTreeDrops()
        local context = work.treeDrops
        if not context then return false end
        if work.drainTreeDrops(context, context.key) then
            work.treeDrops = nil
            return true
        end
        return false
    end
    function work.bagRank(id)
        local c = config()
        local current = c.bag and c.bag.byId[player:GetAttribute("bagId")]
        local info = c.bag and c.bag.byId[id]
        if info and tonumber(info.cap) and info.cap > (current and current.cap or c.misc.defaultBagSlots or 0) then
            return info.cap
        end
    end
    function work.bagCandidate()
        local c = config()
        for _, tool in ipairs(tools()) do
            local item = c.item.byDisplayName[tool.Name]
            if item and work.bagRank(item.id) then return tool, true end
        end
        local folder = world() and world():FindFirstChild("DroppedItems")
        if not folder then return end
        return nearest(folder:GetChildren(), function(model)
            local item = c.item.byDisplayName[model.Name]
            return item and work.bagRank(item.id) and work.dropAllowed(model) and work.safeResource(model)
        end, function(model)
            return work.bagRank(c.item.byDisplayName[model.Name].id) or 0
        end)
    end
    function work.bagUpgradeTick()
        local target, held = work.bagCandidate()
        if not target then return false end
        local key = "bagUpgrade"
        if held then
            local name = target.Name
            local folder = world() and world():FindFirstChild("DroppedItems")
            if not folder then return false end
            local before = {}
            for _, model in ipairs(folder:GetChildren()) do before[model] = true end
            call("PlayerInventory", "dropItem", target)
            local dropped
            if not work.await(key, function()
                for _, model in ipairs(folder:GetChildren()) do
                    if not before[model] and model.Name == name and model:GetAttribute("ownerName") == player.Name then
                        dropped = model return true
                    end
                end
            end, 3) then return false end
            target = dropped
        end
        local confirmed = work.collectModel(target, key, true)
        note(key, confirmed and "BAG CAPACITY UPGRADED" or "BAG UPGRADE NOT CONFIRMED")
        work.refreshAt = 0
        return confirmed
    end
    function work.meleeWeapon()
        local c, best, stats = config(), nil, nil
        for _, tool in ipairs(tools()) do
            local info = c.tool.byDisplayName[tool.Name]
            if info and (tonumber(info.atkDmg) or 0) > 0 and info.toolType ~= "gun"
                and info.toolType ~= "ranged" and info.toolType ~= "infGun"
                and (not stats or info.atkDmg > stats.atkDmg) then
                best, stats = tool, info
            end
        end
        return best, stats
    end
    function work.hostiles(force)
        if not force and os.clock() < (work.threatCacheAt or 0) then return work.threatCache or {} end
        local scene, rows = world(), {}
        local folder = scene and scene:FindFirstChild("Entities")
        local c = config()
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            local human = model:FindFirstChildOfClass("Humanoid")
            local point = pos(model)
            if human and human.Health > 0 and point and c.mob and c.mob.byId[model.Name]
                and not Players:GetPlayerFromCharacter(model) then
                local part = model:FindFirstChild("HumanoidRootPart")
                rows[#rows + 1] = {model = model, human = human, point = point,
                    velocity = part and part.AssemblyLinearVelocity or Vector3.new(0, 0, 0),
                    attackable = human.Health < 10000}
            end
        end
        work.threatCache, work.threatCacheAt = rows, os.clock() + 0.04
        return rows
    end
    function work.danger(point, radius, ignore)
        if not point then return math.huge, nil, 0 end
        local risk, closest, count, distance = 0, nil, 0, math.huge
        for _, row in ipairs(work.hostiles()) do
            if row.model ~= ignore and row.model.Parent and row.human.Health > 0 then
                local delta = point - row.point
                local d = delta.Magnitude
                if d < radius and math.abs(delta.Y) < 18 then
                    risk = risk + (radius - d + 1) ^ 2
                    count = count + 1
                    if d < distance then closest, distance = row.model, d end
                end
            end
        end
        return risk, closest, count
    end
    function work.automationOn()
        for _, enabled in pairs(flags) do if enabled == true then return true end end
        return false
    end
    function work.personalThreat()
        if not opts.avoidEnemies then return end
        local r, human = root()
        if not r then return end
        local _, target = work.danger(r.Position, opts.dangerRadius)
        local damaged = work.observedHealth and human.Health < work.observedHealth
        work.observedHealth = human.Health
        if damaged then work.damageUntil = os.clock() + 1 end
        if not target then return end
        local fighting = work.active == "combat" or work.active == "hunt"
        if not fighting then return target end
        local _, stats = work.meleeWeapon()
        if human.Health / human.MaxHealth * 100 <= opts.retreatHealth
            or os.clock() < (work.damageUntil or 0) then return target end
        if stats and work.combatClear(r.Position) then return end
        return target
    end
    function work.baseThreat()
        local fire = built("Campfire")
        local center = fire and pos(fire)
        if not center then return end
        local scene = world()
        local buildings = scene and scene:FindFirstChild("Buildings")
        local best, bestScore
        for _, row in ipairs(work.hostiles()) do
            if row.attackable and row.model.Parent and row.human.Health > 0 then
                local distance = (row.point - center).Magnitude
                local nearBuilding = false
                for _, building in ipairs(buildings and buildings:GetChildren() or {}) do
                    local point = pos(building)
                    if point and (row.point - point).Magnitude < 14 then nearBuilding = true break end
                end
                local toward = center - row.point
                local closing = toward.Magnitude > 0 and row.velocity:Dot(toward.Unit) > 1
                -- Proximity / approach is a conservative warning, not a claim about hidden AI state.
                if nearBuilding or distance < 16 or (distance < opts.baseRadius and closing) then
                    local score = (nearBuilding and 1000 or 0) + (closing and 100 or 0) - distance
                    if not bestScore or score > bestScore then best, bestScore = row.model, score end
                end
            end
        end
        return best
    end
    function work.safeDestination(point, key)
        if not opts.avoidEnemies then return true end
        local owner = work.active or key
        local risk = work.danger(point, opts.dangerRadius)
        if owner == "evade" or work.escapeMove then
            local r = root()
            return r and risk <= work.danger(r.Position, opts.dangerRadius)
        end
        if owner == "combat" or owner == "hunt" then return work.combatClear(point) end
        return risk == 0
    end
    function work.combatClear(point)
        for _, row in ipairs(work.hostiles()) do
            if row.model.Parent and row.human.Health > 0 then
                local delta = point - row.point
                local elevatedTarget = row.model == work.attackTarget and delta.Y >= opts.combatHeight
                if not elevatedTarget and delta.Magnitude < work.enemyReach(row.model) + opts.combatMargin then return false end
            end
        end
        return true
    end
    function work.safeRoute(a, b, key)
        if opts.move == "Teleport" then return work.safeDestination(b, key) end
        local delta = b - a
        for i = 1, math.max(1, math.ceil(delta.Magnitude / 3)) do
            local point = a + delta * (i / math.max(1, math.ceil(delta.Magnitude / 3)))
            if not work.safeDestination(point, key) then return false end
        end
        return true
    end
    function work.safeResource(model)
        return not opts.avoidEnemies or work.danger(pos(model), opts.dangerRadius + 5) == 0
    end
    function work.evade(key)
        key = key or "evade"
        local r, human = root()
        if not r then return false end
        local currentRisk, nearestEnemy = work.danger(r.Position, opts.dangerRadius)
        if currentRisk == 0 then return true end
        local best, bestScore
        local lift = math.max(2, human.HipHeight + r.Size.Y / 2)
        local function consider(probe)
            local ground = motion.floor(probe, nil, 10, 5)
            if not ground then return end
            local candidate = ground + Vector3.new(0, lift, 0)
            if not motion.clearSegment(r.Position, candidate, nil) then return end
            local risk = work.danger(candidate, opts.dangerRadius)
            if risk >= currentRisk then return end
            local score = -risk * 100 - (candidate - r.Position).Magnitude
            if not bestScore or score > bestScore then best, bestScore = candidate, score end
        end
        for _, distance in ipairs({12, 24, 36}) do
            for i = 0, 15 do
                local angle = i * math.pi / 8
                consider(r.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
            end
        end
        if not best then
            note(key, "NO CHECKED DRY ESCAPE ROUTE; STOPPING UNSAFE WORK")
            return false
        end
        note(key, "EVADING ENEMY PROXIMITY / APPROACH")
        local moved = travel(best, key, 1)
        work.threatCacheAt = 0
        work.safeUntil = os.clock() + 0.35
        return moved
    end
    function work.enemy(radius)
        local r = root()
        if not r then return end
        local best, distance
        for _, row in ipairs(work.hostiles()) do
            local d = (row.point - r.Position).Magnitude
            if row.attackable and row.model.Parent and row.human.Health > 0 and d <= radius
                and not (failed[row.model] and failed[row.model] > os.clock())
                and (not distance or d < distance) then best, distance = row.model, d end
        end
        return best
    end
    function work.lineOfSight(from, target)
        local part = target:FindFirstChild("HumanoidRootPart")
        local point = part and part.Position or pos(target)
        if not point then return false end
        local scene, include = world(), {}
        for _, name in ipairs({"Tiles", "自由建筑"}) do
            local folder = scene and scene:FindFirstChild(name)
            if folder then include[#include + 1] = folder end
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = include
        return workspace:Raycast(from, point - from, params) == nil
    end
    function work.enemyReach(target)
        local configured = tonumber(target:GetAttribute("AttackRange"))
        return configured and configured > 0 and configured or opts.enemyReach
    end
    function work.stanceScore(point, target, stats)
        local p = pos(target)
        if not p then return end
        local distance = (point - p).Magnitude
        if distance > (stats.range or 6) - 0.1 or not work.lineOfSight(point, target) then return end
        local elevated = point.Y - p.Y >= opts.combatHeight
        local outside = distance >= work.enemyReach(target) + opts.combatMargin
        if opts.safeCombat and not elevated and not outside then return end
        local sum, neighbours = Vector3.new(0, 0, 0), 0
        local clearance = 30
        for _, row in ipairs(work.hostiles()) do
            if row.model ~= target and row.model.Parent and row.human.Health > 0 then
                local d = (point - row.point).Magnitude
                if d < work.enemyReach(row.model) + opts.combatMargin then return end
                clearance = math.min(clearance, d)
                if (row.point - p).Magnitude < 25 then sum = sum + row.point neighbours = neighbours + 1 end
            end
        end
        local flank = 0
        if neighbours > 0 then
            local outward = p - sum / neighbours
            local approach = point - p
            if outward.Magnitude > 0.1 and approach.Magnitude > 0.1 then flank = outward.Unit:Dot(approach.Unit) * 20 end
        end
        local r = root()
        return (elevated and 10 or 0) + clearance * 2 + flank + distance
            - (r and (point - r.Position).Magnitude or 0) * 0.12
    end
    function work.combatPosition(target, stats)
        local r, human = root()
        local point = pos(target)
        if not r or not point then return end
        local best, score = r.Position, work.stanceScore(r.Position, target, stats)
        if not score then best = nil end
        local radius = math.max(1, (stats.range or 6) - 0.25)
        local lift = math.max(2, human.HipHeight + r.Size.Y / 2)
        for index = 0, 15 do
            local angle = index * math.pi / 8
            local probe = point + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            local ground = motion.floor(probe, target, 12, radius + 4)
            if ground then
                local candidate = ground + Vector3.new(0, lift, 0)
                local rank = work.stanceScore(candidate, target, stats)
                if rank and (opts.move == "Teleport" or motion.clearSegment(r.Position, candidate, target))
                    and (not score or rank > score) then best, score = candidate, rank end
            end
        end
        return best, score
    end
    function work.attackPlan(key, stats)
        local r = root()
        if not r then return end
        local fire = built("Campfire")
        local center = fire and pos(fire)
        local candidates = {}
        for _, row in ipairs(work.hostiles()) do
            local d = (row.point - r.Position).Magnitude
            local baseDistance = center and (row.point - center).Magnitude or math.huge
            if row.attackable and row.model.Parent and row.human.Health > 0
                and not (failed[row.model] and failed[row.model] > os.clock())
                and ((key == "combat" and (baseDistance <= opts.baseRadius or d <= opts.dangerRadius))
                    or (key == "hunt" and d <= opts.huntRadius)) then
                candidates[#candidates + 1] = {row = row, distance = d, baseDistance = baseDistance}
            end
        end
        table.sort(candidates, function(a, b)
            if key == "combat" and a.baseDistance ~= b.baseDistance then return a.baseDistance < b.baseDistance end
            return a.distance < b.distance
        end)
        local target, position, bestScore
        for i = 1, math.min(8, #candidates) do
            local candidate = candidates[i]
            local point, stance = work.combatPosition(candidate.row.model, stats)
            if point then
                local score = stance - candidate.row.human.Health * 0.05
                if key == "combat" then score = score + math.max(0, opts.baseRadius - candidate.baseDistance) * 2 end
                if candidate.row.model == work.attackTarget then score = score + 6 end
                if not bestScore or score > bestScore then target, position, bestScore = candidate.row.model, point, score end
            end
        end
        return target, position
    end
    function work.retreat(key)
        work.escapeMove = true
        local ok, result = pcall(work.evade, key)
        work.escapeMove = nil
        if not ok then error(result) end
        return result
    end
    local function defend(key)
        key = key or "combat"
        local r, human = root()
        local tool, stats = work.meleeWeapon()
        if not r or not tool then note(key, "MELEE WEAPON REQUIRED") return false end
        local character, serial = player.Character, motion.serial
        local deadline, misses = os.clock() + math.clamp(opts.jobTimeout, 15, 600), 0
        local defeated = false
        while work.running(key, character, serial) and os.clock() < deadline do
            r, human = root()
            if human.Health / human.MaxHealth * 100 <= opts.retreatHealth
                or os.clock() < (work.damageUntil or 0) then work.retreat(key) return false end
            local target, position = work.attackPlan(key, stats)
            if not target then
                note(key, "NO CHECKED ATTACK POSITION; KEEPING OUT OF SWARM")
                if work.personalThreat() then work.retreat(key) end
                return defeated
            end
            work.attackTarget, work.attackStats = target, stats
            if (r.Position - position).Magnitude > 0.75 and not travel(position, key, 0.5) then return defeated end
            r = root()
            if not r or not work.stanceScore(r.Position, target, stats) then return defeated end
            local enemyHuman = target:FindFirstChildOfClass("Humanoid")
            local before = enemyHuman.Health
            local point = pos(target)
            if (point - r.Position).Magnitude > 0.1 then r.CFrame = CFrame.lookAt(r.Position, Vector3.new(point.X, r.Position.Y, point.Z)) end
            local targets = {target}
            for _, row in ipairs(work.hostiles()) do
                if #targets >= (stats.capAOE or 1) then break end
                local delta = row.point - r.Position
                if row.model ~= target and row.attackable and delta.Magnitude > 0.1
                    and r.CFrame.LookVector:Dot(delta.Unit) >= 0 and work.stanceScore(r.Position, row.model, stats) then
                    targets[#targets + 1] = row.model
                end
            end
            if not work.strike(tool, stats, targets, {}, key) then return defeated end
            local damaged = work.await(key, function() return not target.Parent or enemyHuman.Health < before end,
                math.max(0.15, math.min(0.5, tonumber(stats.useCd) or 0.7)))
            if work.preempted then return defeated end
            misses = damaged and 0 or misses + 1
            if not target.Parent or enemyHuman.Health <= 0 then defeated = true work.threatCacheAt = 0 end
            if misses >= 3 then
                failed[target] = os.clock() + 1
                note(key, "HITS UNCONFIRMED; REPOSITION / RETREAT")
                work.retreat(key)
                return defeated
            end
        end
        return defeated
    end
    function work.pickupCandidate(neededOnly)
        local w = world()
        local folder = w and w:FindFirstChild("DroppedItems")
        if not folder then
            return
        end
        local c = config()
        return nearest(folder:GetChildren(), function(x)
            local owner = x:GetAttribute("ownerName")
            local protected = x:GetAttribute("protectEndTick") or 0
            if owner and owner ~= player.Name and protected > workspace:GetServerTimeNow() then
                return false
            end
            local info = c.item.byDisplayName[x.Name]
            return not (neededOnly and work.objective and work.objective.kind == "quest"
                and x:GetAttribute("ownerName") == player.Name and info and work.questRequirement
                and info.id == work.questRequirement.itemId) and not x:GetAttribute("collecting") and info and (not neededOnly or work.needs[info.id]) and (neededOnly or selectedEmpty("drops") or allowed("drops", info.id)) and work.safeResource(x) and not (failed[x] and failed[x] > os.clock())
        end, function(x)
            local info = c.item.byDisplayName[x.Name]
            return info and work.needs[info.id] or 0
        end)
    end
    local function pickups(key, neededOnly)
        key = key or "drops"
        if not work.canCollect() then
            note(key, "BAG BLOCKED: WAITING FOR ITEMS TO BE USED / SUBMITTED")
            return false
        end
        local o = work.pickupCandidate(neededOnly)
        if not o then
            note(key, "NO ELIGIBLE DROPS")
        end
        if o and travel(o, key) then
            local before = work.signature()
            local amount = count(o.Name)
            call("ItemCollect", "collect", o)
            local confirmed = work.await(key, function()
                return count(o.Name) > amount
            end, 3)
            if work.preempted then return confirmed end
            failed[o] = os.clock() + (confirmed and 0.1 or 1)
            if not confirmed and o.Parent and not o:GetAttribute("collecting")
                and work.signature() == before then
                work.rejectedPickups = (work.rejectedPickups or 0) + 1
                if work.rejectedPickups >= 3 then
                    work.blockedBag = before
                    note("inventory", "COLLECTION REJECTED: WAITING FOR INVENTORY CHANGE")
                end
            elseif confirmed then
                work.rejectedPickups = 0
            end
            note(key, confirmed and "ITEM ADDED TO INVENTORY" or "COLLECTION NOT CONFIRMED")
            return confirmed
        end
    end
    local function gatherResource(key, neededOnly)
        key = key or "gather"
        if not work.canCollect() then
            note(key, "BAG BLOCKED: USE / SUBMIT ITEMS FIRST")
            return false
        end
        local w = world()
        local static = w and w:FindFirstChild("Static")
        if not static then
            note(key, "MATCH RESOURCES NOT LOADED")
            return
        end
        if work.treeDrops then work.treeDrops.key = key return work.recoverTreeDrops() end
        local c = config()
        local best = nearest(static:GetChildren(), function(o)
            return o:IsA("Model") and o:GetAttribute("resourceId") and c.worldResource.byId[o:GetAttribute("resourceId")] and (type(o:GetAttribute("hp")) ~= "number" or o:GetAttribute("hp") > 0) and (next(work.needs) == nil or (work.resourceNeeds[o:GetAttribute("resourceId")] or 0) > 0) and (neededOnly or selectedEmpty("resources") or allowed("resources", o:GetAttribute("resourceId"))) and work.safeResource(o) and not (failed[o] and failed[o] > os.clock())
        end, function(o)
            local priority = work.resourceNeeds[o:GetAttribute("resourceId")] or 0
            return priority + ((work.resourcePlans and work.resourcePlans[o]) and 1000 or 0)
        end)
        if not best then
            note(key, "NO LOADED MATCHING RESOURCES")
            return
        end
        local rc = c.worldResource.byId[best:GetAttribute("resourceId")]
        local tool, tc
        for _, t in ipairs(tools()) do
            local info = c.tool.byDisplayName[t.Name]
            if info and (rc.requireToolType == "any" or info.toolType == rc.requireToolType) and (not tc or (info.useDmg or 0) > (tc.useDmg or 0)) then
                tool, tc = t, info
            end
        end
        if not tool then
            note(key, "MATCHING TOOL REQUIRED")
            say("GATHER: MATCHING TOOL REQUIRED")
            failed[best] = os.clock() + 5
            return
        end
        work.resourcePlans = work.resourcePlans or {}
        local dropContext = work.resourcePlans[best] or work.treeDropContext(best)
        work.resourcePlans[best] = dropContext
        dropContext.key = key
        local character, serial = player.Character, motion.serial
        local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        local noDamage = 0
        while work.running(key, character, serial) and os.clock() < deadline do
            local hp = best:GetAttribute("hp")
            if not best.Parent or (type(hp) == "number" and hp <= 0) then
                work.resourcePlans[best] = nil
                work.treeDrops = dropContext
                work.recoverTreeDrops()
                note(key, work.treeDrops and "RESOURCE CUT • DROPS PENDING" or "RESOURCE CUT • ALL LOADED DROPS COLLECTED")
                return true
            end
            if not tool.Parent then
                note(key, "TOOL NO LONGER AVAILABLE")
                return false
            end
            if not travel(best, key, math.max(1, (tc.range or 6) - 0.5)) then
                return false
            end
            equip(tool)
            local r = root()
            if not r then
                return false
            end
            local p = best:GetPivot().Position
            r.CFrame = CFrame.lookAt(r.Position, Vector3.new(p.X, r.Position.Y, p.Z))
            if not work.strike(tool, tc, {}, {best}, key) then return false end
            local damaged = work.await(key, function()
                local current = best:GetAttribute("hp")
                return not best.Parent or (type(current) == "number"
                    and type(hp) == "number" and current < hp)
            end, math.max(0.15, math.min(0.5, tonumber(tc.useCd) or 0.7)))
            if work.preempted then return damaged end
            noDamage = damaged and 0 or noDamage + 1
            note(key, damaged and "CHOPPING SAME RESOURCE" or "WAITING FOR RESOURCE DAMAGE")
            if noDamage >= 3 then
                failed[best] = os.clock() + 1
                note(key, "NO DAMAGE AFTER 3 SWINGS; RETRY LATER")
                return false
            end
        end
        if work.preempted then return false end
        failed[best] = os.clock() + 1
        note(key, "STOPPED OR SAFETY TIMEOUT; NOT MARKED COMPLETE")
        return false
    end
    local function exploreTick(key, kind, service, check, request)
        local w = world()
        if not w then
            return
        end
        local c = config()
        local rows = kind == "chest" and c.chest.byId or c.mapProp.byCnId
        local search = kind == "chest" and w:FindFirstChild("Chest") or w
        local obj = nearest(search and search:GetDescendants() or {}, function(o)
            return o:IsA("Model") and rows[o.Name] and not (failed[o] and failed[o] > os.clock())
        end)
        if not obj then
            return
        end
        failed[obj] = os.clock() + 20
        if call(service, check, obj) then
            return
        end
        if kind == "chest" and call(service, "isLocked", obj) then
            return
        end
        if travel(obj, key) then
            call(service, request, obj)
            local confirmed = work.await(key, function()
                return not obj.Parent or call(service, check, obj) == true
            end, 4)
            note(key, confirmed and "INTERACTION CONFIRMED" or "INTERACTION NOT CONFIRMED")
            return confirmed
        end
    end
    local function escapeTick()
        local w = world()
        if not w then
            return
        end
        for _, o in ipairs(w:GetDescendants()) do
            if o:IsA("LocalScript") and o.Name == "BoatEscapeClient" then
                local boat = o.Parent
                local part = boat:FindFirstChild("promptPart")
                local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
                if prompt and prompt.Enabled and travel(part, "escape") then
                    assert(type(fireproximityprompt) == "function", "Executor prompt support required for the boat")
                    fireproximityprompt(prompt, prompt.HoldDuration)
                    due.escape = os.clock() + 10
                    return true
                end
            end
        end
    end
    function work.readQuest(force)
        local scene = world()
        local npc = scene and scene:FindFirstChild("Mrbeast", true)
        if not npc then work.questRequirement = nil work.questCache = nil return end
        local q = module("MrbeastQuest")
        if not q then return end
        local index = player:GetAttribute("MrbeastQuestIndex")
        local alt = player:GetAttribute("MrbeastQuestAlt")
        local revision = player:GetAttribute("MrbeastQuestRevision")
        local cache = work.questCache
        if type(index) == "number" and type(alt) == "number" and type(revision) == "number" then
            cache = {index = index, alt = alt, revision = revision, at = os.clock()}
            work.questCache = cache
        elseif not work.questFetchPending and (force or not cache or os.clock() - cache.at >= 2) then
            work.questFetchPending = true
            local character = player.Character
            task.spawn(function()
                local ok, newIndex, newAlt, newRevision = pcall(q.client.fetchQuest)
                work.questFetchPending = nil
                if alive and ok and player.Character == character and scene == world() then
                    work.questCache = {index = newIndex, alt = newAlt, revision = newRevision, at = os.clock()}
                    work.refreshAt = 0
                end
            end)
        end
        local req = cache and cache.index and q.getQuestRequirement(cache.index, cache.alt)
        work.questRequirement = req
        if cache then return req, cache.index, cache.alt, cache.revision, q end
    end
    function work.questDrops(req)
        local result = {}
        local item = req and config().item.byId[req.itemId]
        local folder = world() and world():FindFirstChild("DroppedItems")
        if item and folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model.Name == item.displayName and model:GetAttribute("ownerName") == player.Name
                    and not model:GetAttribute("collecting") then result[#result + 1] = model end
            end
        end
        return result
    end
    function work.questTotal(req)
        local item = req and config().item.byId[req.itemId]
        return item and count(item.displayName) + #work.questDrops(req) or 0
    end
    local function questTick(key)
        key = key or "quest"
        local req, index, alt, revision, q = work.readQuest(true)
        if not req then note(key, "NO ACTIVE MRBEAST REQUEST") return false end
        local info = config().item.byId[req.itemId]
        if not info then return false end
        questInfo.Text = "MRBEAST NEEDS: " .. req.count .. " " .. itemLabel("item", req.itemId, info)
        local mr = world():FindFirstChild("Mrbeast", true)
        local area = mr and mr:FindFirstChild("SuckArea")
        if not area then return false end
        local used, cap = work.bagState()
        if work.questTotal(req) < req.count and not (used >= cap and count(info.displayName) > 0) then return false end
        if not travel(area, key, 1.8) then return false end
        local deposited = false
        local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        while work.running(key, player.Character, motion.serial) and os.clock() < deadline do
            local best, held = nil, 0
            for _, tool in ipairs(tools()) do
                local n = tonumber(tool:GetAttribute("count")) or 1
                if tool.Name == info.displayName and n > held then best, held = tool, n end
            end
            local owned = work.questDrops(req)
            if #owned + held >= req.count then
                if best then equip(best) end
                q.client.submitQuest(owned, revision)
                work.sent = work.sent + 1
                local confirmed = work.await(key, function()
                    if player:GetAttribute("MrbeastQuestRevision") ~= nil
                        and player:GetAttribute("MrbeastQuestRevision") ~= revision then return true end
                    local _, newIndex, newAlt, newRevision = work.readQuest(false)
                    return newIndex ~= index or newAlt ~= alt or newRevision ~= revision
                end, 3)
                work.questCache = nil
                work.refreshAt = 0
                note(key, confirmed and "MRBEAST REQUEST COMPLETE" or "MRBEAST SUBMISSION UNCONFIRMED")
                return confirmed
            end
            if not best then return deposited end
            -- Native drop sends one unit. Owned quest drops are retained for the eventual full submission.
            local before, dropsBefore = count(info.displayName), #owned
            call("PlayerInventory", "dropItem", best)
            if not work.await(key, function()
                return count(info.displayName) < before and #work.questDrops(req) > dropsBefore
            end, 3) then return deposited end
            deposited = true
        end
        return deposited
    end
    function work.waterDrop()
        local scene = world()
        local folder = scene and scene:FindFirstChild("DroppedItems")
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            if model:GetAttribute("WaterMakerCoconut") and work.dropAllowed(model) and work.safeResource(model) then return model end
        end
    end
    function work.net(name)
        work.netEvents = work.netEvents or {}
        if not work.netEvents[name] then
            work.netEvents[name] = require(RS.Packages.Net):RemoteEvent(name)
        end
        return work.netEvents[name]
    end
    function work.bindFastServices()
        if work.fastBound or serverMode() ~= "match" then return end
        work.fastBound = true
        task.spawn(function()
            safely("station sync", function()
                connections[#connections + 1] = work.net("CraftingStationStateChanged").OnClientEvent:Connect(function(stock)
                    if type(stock) == "table" then work.stationStock = stock work.stationSynced = true work.refreshAt = 0 end
                end)
                work.net("CraftingStationRequestState"):FireServer()
            end)
        end)
        local service = RS.Engine.Service:FindFirstChild("MrbeastChoice")
        local event = service and service:FindFirstChild("onChoiceRemote")
        if event then
            connections[#connections + 1] = event.OnClientEvent:Connect(function(choices)
                work.choices = type(choices) == "table" and choices or nil
                work.choiceVersion = (work.choiceVersion or 0) + 1
            end)
        end
        local close = service and service:FindFirstChild("closeChoiceRemote")
        if close then
            connections[#connections + 1] = close.OnClientEvent:Connect(function() work.choices = nil end)
        end
    end
    function work.station()
        if work.stationModel and work.stationModel.Parent then return work.stationModel, work.stationZone end
        if os.clock() < (work.stationSearchAt or 0) then return end
        work.stationSearchAt = os.clock() + 1
        local scene = world()
        for _, model in ipairs(scene and scene:GetDescendants() or {}) do
            if model:IsA("Model") and model.Name == "制作台" then
                local zone = model:FindFirstChild("吸入范围")
                if zone and zone:IsA("BasePart") then
                    work.stationModel, work.stationZone = model, zone
                    return model, zone
                end
            end
        end
    end
    function work.bagGoal()
        work.bagNeedsFire = nil
        if not flags.bagUpgrade or not work.stationSynced or not work.station() then return end
        local c, best = config(), nil
        local fire = built("Campfire")
        local level = tonumber(campData.campfireLevel) or (fire and tonumber(fire:GetAttribute("CampfireMeshLevel"))) or 1
        for _, entry in ipairs(c.craftingContent and c.craftingContent.list or {}) do
            local item = c.item.byName[entry.itemName]
            local cap = item and work.bagRank(item.id)
            if cap and item.recipeId and count(item.displayName) == 0 then
                if (tonumber(entry.campfireLvl) or 1) > level then
                    work.bagNeedsFire = true
                elseif not best or cap < best.cap then
                    local recipe = work.recipeAmounts(item)
                    if next(recipe) then
                        local amounts = {}
                        for id, n in pairs(recipe) do amounts[id] = math.max(0, n - ((work.stationStock or {})[id] or 0)) end
                        local used, capacity = work.bagState()
                        best = {key = "bag:" .. item.id, id = item.id, kind = "bag", info = item,
                            rank = (used >= capacity or not next(work.missing(amounts))) and 0.05 or 0.2,
                            cap = cap, recipe = recipe, amounts = amounts,
                            name = "BAG UPGRADE: " .. itemLabel("bag", item.id, item)}
                    end
                end
            end
        end
        return best
    end
    function work.insideStation(zone)
        local r = root()
        if not r then return false end
        local p = zone.CFrame:PointToObjectSpace(r.Position)
        return math.abs(p.X) < zone.Size.X / 2 and math.abs(p.Z) < zone.Size.Z / 2
            and math.abs(p.Y) < zone.Size.Y / 2
    end
    function work.stationTick(goal)
        local _, zone = work.station()
        local key = "progression"
        if not zone or not travel(zone, key, 0.5) then return false end
        if not work.insideStation(zone) then
            local _, h = root()
            h:MoveTo(zone.Position)
            if not work.await(key, function() return work.insideStation(zone) end, 2) then
                note(key, "MOVE INSIDE THE CRAFTING STATION'S DEPOSIT AREA")
                return false
            end
        end
        local deposited = false
        local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        for id, needed in pairs(goal.recipe) do
            local item = config().item.byId[id]
            while item and ((work.stationStock or {})[id] or 0) < needed and count(item.displayName) > 0
                and work.running(key, player.Character, motion.serial) and os.clock() < deadline do
                if not work.insideStation(zone) then return deposited end
                local tool
                for _, candidate in ipairs(tools()) do if candidate.Name == item.displayName then tool = candidate break end end
                if not tool then break end
                local before = (work.stationStock or {})[id] or 0
                call("PlayerInventory", "dropItem", tool)
                if not work.await(key, function() return ((work.stationStock or {})[id] or 0) > before end, 3) then
                    note(key, "DEPOSIT SENT; WAITING FOR SHARED STATION STOCK")
                    return deposited
                end
                deposited = true
            end
        end
        for id, amount in pairs(goal.recipe) do
            if ((work.stationStock or {})[id] or 0) < amount then return deposited end
        end
        local before, bagId = count(goal.info.displayName), player:GetAttribute("bagId")
        work.net("CraftingStationCraft"):FireServer(goal.id)
        work.sent = work.sent + 1
        return work.await(key, function()
            return player:GetAttribute("bagId") ~= bagId or count(goal.info.displayName) > before
        end, 3)
    end
    function work.choiceScore(choice)
        local c, id = config(), choice.itemId
        local item = c.item.byId[id]
        if not item then return -1000 end
        local _, human = root()
        local food = c.food and c.food.byId[id]
        local amount = tonumber(choice.count) or 1
        local used, capacity = work.bagState()
        local underAttack = work.baseThreat() ~= nil or work.personalThreat() ~= nil
        if food and human then
            local hunger, maxHunger = human:GetAttribute("hunger"), human:GetAttribute("maxHunger") or 100
            if human.Health / human.MaxHealth * 100 <= opts.retreatHealth and (tonumber(food.healthRegen) or 0) > 0 then
                return 1000000 + math.min(human.MaxHealth - human.Health, food.healthRegen * amount)
            end
            if hunger and hunger / maxHunger * 100 < 15 and (tonumber(food.hungerRegen) or 0) > 0 then return 900000 + food.hungerRegen end
        end
        local tool = c.tool.byId[id]
        if tool then
            local ownedTier, ownedDamage = 0, 0
            for _, owned in ipairs(tools()) do
                local info = c.tool.byDisplayName[owned.Name]
                if info and info.toolType == tool.toolType then ownedTier = math.max(ownedTier, tonumber(info.lvl) or 0) end
                if info then ownedDamage = math.max(ownedDamage, tonumber(info.atkDmg) or 0) end
            end
            local upgrade = (tonumber(tool.lvl) or 0) > ownedTier
            if underAttack and (tonumber(tool.atkDmg) or 0) > ownedDamage then return 800000 + tool.atkDmg end
            if upgrade then return 300000 + (tonumber(tool.lvl) or 0) * 100 + (tonumber(tool.atkDmg) or 0) end
            return -100
        end
        local cap = work.bagRank(id)
        if cap then return (used >= capacity and 750000 or 700000) + cap end
        if c.bag and c.bag.byId[id] then return -100 end
        if work.objective and work.objective.amounts then
            local missing = math.max(0, (work.objective.amounts[id] or 0) - count(item.displayName))
            if missing > 0 then return 500000 + math.min(missing, amount) end
        end
        local req = work.questRequirement
        if req and req.itemId == id and work.questTotal(req) < req.count then return 400000 + amount end
        if food then return 200000 + amount end
        if work.needs[id] then return 100000 + work.needs[id] + amount end
        return amount
    end
    function work.rewardChoiceTick()
        local choices = work.choices
        if not choices or work.choiceSentVersion == work.choiceVersion then return false end
        local best, score = nil, -math.huge
        for index, choice in ipairs(choices) do
            local rank = work.choiceScore(choice)
            if rank > score then best, score = index, rank end
        end
        if not best then return false end
        local version = work.choiceVersion
        local source = RS.Engine.Service:FindFirstChild("MrbeastChoice")
        local event = source and source:FindFirstChild("playerSelectRemote")
        if not event then return false end
        work.choiceSentVersion = version
        work.choiceSentAt = os.clock()
        local before, bagId = work.signature(), player:GetAttribute("bagId")
        event:FireServer(best)
        work.sent = work.sent + 1
        local key = flags.progression and "progression" or "quest"
        local confirmed = work.await(key, function()
            return work.choiceVersion ~= version or work.choices == nil or work.signature() ~= before
                or player:GetAttribute("bagId") ~= bagId
        end, 2)
        if confirmed and work.choiceVersion == version then work.choices = nil end
        work.blockedBag = nil
        return confirmed
    end
    local fish = {
        state = "idle",
        at = 0,
        tool = nil,
        mini = nil,
    }
    local events = RS:FindFirstChild("Events")
    if events then
        local bite = events:FindFirstChild("fishBiteRemote")
        if bite then
            connections[#connections + 1] = bite.OnClientEvent:Connect(function(yes)
                if flags.fish and yes and fish.tool then
                    events.fishReelRemote:FireServer(fish.tool)
                    fish.state = "reeling"
                    fish.at = os.clock()
                end
            end)
        end
        local mini = events:FindFirstChild("fishMinigameRemote")
        if mini then
            connections[#connections + 1] = mini.OnClientEvent:Connect(function(action, token, id, settings)
                if not flags.fish or action ~= "start" or not fish.tool then
                    return
                end
                fish.state = "minigame"
                fish.at = os.clock()
                local source = RS.Engine.Tool.Client:FindFirstChild("FishingMinigame")
                if source then
                    local ok, e = pcall(function()
                        fish.mini = require(source).new(token, settings)
                        fish.mini:start(function(success)
                            if alive and flags.fish then
                                mini:FireServer("result", success, id)
                                fish.state = success and "reeling" or "waiting"
                                fish.at = os.clock()
                            end
                            fish.mini = nil
                        end)
                    end)
                    if not ok then
                        say(e)
                    end
                end
            end)
        end
        local reel = events:FindFirstChild("fishReelRemote")
        if reel then
            connections[#connections + 1] = reel.OnClientEvent:Connect(function()
                if flags.fish then
                    fish.state = "reeling"
                    fish.at = os.clock()
                end
            end)
        end
        local cancel = events:FindFirstChild("fishCancelRemote")
        if cancel then
            connections[#connections + 1] = cancel.OnClientEvent:Connect(function()
                fish.state = "idle"
                fish.at = os.clock()
            end)
        end
    end
    connections[#connections + 1] = gui.Destroying:Connect(function()
        if fish.mini then
            pcall(function()
                fish.mini:cancel()
            end)
        end
        if fish.state ~= "idle" and events and events:FindFirstChild("fishCancelRemote") then
            pcall(function()
                events.fishCancelRemote:FireServer()
            end)
        end
    end)
    local function fishTick()
        local r = root()
        if not r or not events then
            return
        end
        if fish.state ~= "idle" and (not root() or not fish.tool or not fish.tool.Parent) then
            if fish.mini then
                fish.mini:cancel()
                fish.mini = nil
            end
            events.fishCancelRemote:FireServer()
            fish.state = "idle"
            return false
        end
        if fish.state == "minigame" then
            if os.clock() - fish.at > math.clamp(opts.jobTimeout, 15, 600) then
                if fish.mini then
                    fish.mini:cancel()
                    fish.mini = nil
                end
                events.fishCancelRemote:FireServer()
                fish.state = "idle"
                note("fish", "MINIGAME SAFETY TIMEOUT")
                return false
            end
            say("COMPLETE FISH MINIGAME")
            return true
        end
        if fish.state == "reeling" and os.clock() - fish.at > 4 then
            fish.state = "idle"
            -- Release the cast lock before the scheduler chooses another job.
            return false
        end
        if fish.state ~= "idle" then
            if os.clock() - fish.at > 45 then
                events.fishCancelRemote:FireServer()
                fish.state = "idle"
            end
            return fish.state ~= "idle"
        end
        if not work.canCollect() then
            note("fish", "BAG BLOCKED: PROCESS ITEMS FIRST")
            return false
        end
        local c = config()
        local rod
        for _, t in ipairs(tools()) do
            local info = c.tool.byDisplayName[t.Name]
            if info and info.toolType == "鱼竿" then
                rod = t
                break
            end
        end
        if not rod then
            note("fish", "FISHING ROD REQUIRED")
            return false
        end
        equip(rod)
        fish.tool = rod
        local direction = r.CFrame.LookVector * Vector3.new(1, 0, 1)
        local p = r.Position + direction.Unit * 18
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = {
            workspace.Terrain,
            world().Tiles,
        }
        params.IgnoreWater = false
        local hit = workspace:Raycast(p + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
        if not hit or hit.Material ~= Enum.Material.Water then
            note("fish", "FACE WATER TO CAST")
            return false
        end
        events.fishVisualRemote:FireServer("castBegin", rod.Name)
        events.fishCastRemote:FireServer(rod, hit.Position + Vector3.new(0, 0.05, 0))
        fish.state = "waiting"
        fish.at = os.clock()
        say("FISHING: WAITING FOR BITE")
        return true
    end
    local function limited(key, seconds, fn)
        if not flags[key] or (due[key] and os.clock() < due[key]) then
            return
        end
        due[key] = os.clock() + seconds
        return safely(key, fn)
    end
    function work.buildRank(info)
        local name = tostring(info.assetId):lower()
        if name == "campfire" then
            return 0
        end
        if name:find("craft") or name:find("workbench") then
            return 1
        end
        return 2
    end
    function work.contribute(key, onlySelected, targetId)
        local folder = world() and world():FindFirstChild("Buildings")
        if not folder then
            return false
        end
        local c = config()
        local candidates = {}
        for id, info in pairs(c.build.byId) do
            if (not targetId or id == targetId) and (not onlySelected or allowed("build", id))
                and folder:FindFirstChild(info.assetId .. "_Construct") then
                candidates[#candidates + 1] = { id = id, info = info }
            end
        end
        table.sort(candidates, function(a, b)
            local ar, br = work.buildRank(a.info), work.buildRank(b.info)
            return ar < br or (ar == br and tostring(a.id) < tostring(b.id))
        end)
        for _, entry in ipairs(candidates) do
            local info = entry.info
            local blueprint = folder:FindFirstChild(info.assetId .. "_Construct")
            local function hasMaterial()
                for field, amount in pairs(c.recipe.byId[info.recipeId] or {}) do
                    local id = type(field) == "string" and field:match("^require_(.+)$")
                    local item = id and c.item.byId[id]
                    if item and type(amount) == "number" and amount > 0
                        and work.remaining(info, id, amount) > 0 and count(item.displayName) > 0 then
                        return true
                    end
                end
                return false
            end
            if hasMaterial() then
                local character, serial = player.Character, motion.serial
                local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
                local submitted = false
                while blueprint.Parent and hasMaterial()
                    and work.running(key, character, serial) and os.clock() < deadline do
                    if not travel(blueprint, key) then
                        return false
                    end
                    local before = work.signature()
                    local progress = work.buildRemaining[info.assetId]
                    call("BuildBuilding", "build", entry.id)
                    local confirmed = work.await(key, function()
                        return not blueprint.Parent or built(info.assetId) ~= nil
                            or work.signature() ~= before
                            or work.buildRemaining[info.assetId] ~= progress
                    end, 4)
                    if not confirmed then
                        note(key, "SUBMISSION NOT CONFIRMED; RETRY LATER")
                        return false
                    end
                    submitted = true
                    work.refreshAt = 0
                end
                note(key, not blueprint.Parent and "CONSTRUCTION FINISHED"
                    or "AVAILABLE MATERIALS SUBMITTED; NEED MORE MATERIALS")
                return submitted
            end
        end
        note(key, "NO BLUEPRINT WITH USABLE MATERIALS")
        return false
    end
    local function craftTick()
        local c = config()
        if selectedEmpty("craft") then
            note("craft", "SELECT ITEMS FIRST")
            return
        end
        for id in pairs(selected.craft or {}) do
            local i = c.item.byId[id]
            if allowed("craft", id) and i and count(i.displayName) == 0 and recipeReady(i) then
                return work.request("craft", "CraftItems", "craft", id)
            end
        end
        note("craft", "OWNED ALREADY OR NEED MATERIALS")
    end
    local function buildTick()
        return work.contribute("build", true)
    end
    local function buildCurrentTick()
        return work.contribute("buildCurrent", false)
    end
    local function foodReady()
        local r, h = root()
        if not r then
            return false
        end
        local hunger = h:GetAttribute("hunger")
        local max = h:GetAttribute("maxHunger") or 100
        if h.Health / h.MaxHealth * 100 > opts.health and (not hunger or hunger / max * 100 > opts.hunger) then
            return false
        end
        local c = config()
        for _, t in ipairs(tools()) do
            local item = c.item.byDisplayName[t.Name]
            if item and work.foodAllowed("food", item.id) then
                return true
            end
        end
        return false
    end
    local function enemyReady()
        return work.meleeWeapon() ~= nil and (work.baseThreat() ~= nil or work.enemy(opts.dangerRadius) ~= nil)
    end
    function work.needItem(id, amount, priority)
        local c = config()
        local item = c.item.byId[id]
        if item and count(item.displayName) < amount then
            work.needs[id] = math.max(work.needs[id] or 0, priority)
            work.amounts[id] = math.max(work.amounts[id] or 0, amount - count(item.displayName))
        end
    end
    function work.needRecipe(info, priority)
        local c = config()
        local recipe = c.recipe.byId[info.recipeId]
        for key, n in pairs(recipe or {}) do
            local id = type(key) == "string" and key:match("^require_(.+)$")
            if id and type(n) == "number" and n > 0 then
                work.needItem(id, work.remaining(info, id, n), priority)
            end
        end
    end
    function work.recipeAmounts(info, building)
        local amounts = {}
        local c = config()
        for field, amount in pairs(c.recipe.byId[info.recipeId] or {}) do
            local id = type(field) == "string" and field:match("^require_(.+)$")
            if id and type(amount) == "number" and amount > 0 and c.item.byId[id] then
                amounts[id] = building and work.remaining(info, id, amount) or amount
            end
        end
        return amounts
    end
    function work.missing(amounts)
        local missing = {}
        for id, amount in pairs(amounts) do
            local item = config().item.byId[id]
            local need = math.max(0, amount - (item and count(item.displayName) or 0))
            if need > 0 then missing[id] = need end
        end
        return missing
    end
    function work.campfireGoal()
        local fire = built("Campfire")
        local w = world()
        local rain = w and w:FindFirstChild("IsRaining")
        if not fire or (rain and rain.Value) then return end
        local c = config()
        local level = tonumber(campData.campfireLevel) or tonumber(fire:GetAttribute("CampfireMeshLevel")) or 1
        local row, higher
        for _, info in ipairs(c.campfire and c.campfire.list or {}) do
            if info.lvl == level then row = info end
            if type(info.lvl) == "number" and info.lvl > level then higher = true end
        end
        local item = work.fuelItem()
        if not row or not higher or not item or not tonumber(row.woodBurnSec) or row.woodBurnSec <= 0 then return end
        local cap = tonumber(campData.campfireLevelCapMins)
        if not cap and type(row.capMinsPlayerCount) == "table" and #row.capMinsPlayerCount > 0 then
            local players = w and w:FindFirstChild("PlayerCount")
            cap = row.capMinsPlayerCount[math.clamp(players and players.Value or 1, 1, #row.capMinsPlayerCount)]
        end
        if not cap or cap <= 0 then return end
        local remaining = campData.isOnFire and math.max(0, (campData.fuelEndTime or 0) - workspace:GetServerTimeNow()) or 0
        local amount = math.max(1, math.ceil((cap * 60 - remaining) / row.woodBurnSec))
        return {key = "campfire:" .. level, kind = "fuel", level = level, rank = 2 + (level - 1) * 2,
            name = "CAMPFIRE LEVEL " .. (level + 1), amounts = {[item.id] = amount}}
    end
    function work.upgradeCandidates()
        local c, result = config(), {}
        local folder = world() and world():FindFirstChild("Buildings")
        if folder then
            for id, info in pairs(c.build.byId) do
                if folder:FindFirstChild(info.assetId .. "_Construct") then
                    local rank = work.buildRank(info)
                    result[#result + 1] = {key = "build:" .. id, id = id, kind = "build", info = info,
                        rank = rank == 0 and 0 or (rank == 1 and 2.2 or 4.5),
                        name = itemLabel("building", id, info), amounts = work.recipeAmounts(info, true)}
                end
            end
        end
        local req = work.questRequirement
        if req then
            result[#result + 1] = {key = "quest:" .. tostring(req.itemId), kind = "quest", rank = 0.4,
                name = "MRBEAST REQUEST", amounts = {[req.itemId] = math.max(0, req.count - #work.questDrops(req))}}
        end
        local bag = work.bagGoal()
        if bag then bag.rank = math.min(bag.rank, 0.08) result[#result + 1] = bag end
        local fire = work.campfireGoal()
        if fire then
            if campData.isOnFire == false then fire.rank = 0.02
            elseif work.bagNeedsFire then fire.rank = 0.25 end
            result[#result + 1] = fire
        end
        local best, nextTools = {}, {}
        for _, tool in ipairs(tools()) do
            local info = c.tool.byDisplayName[tool.Name]
            if info then best[info.toolType] = math.max(best[info.toolType] or 0, tonumber(info.lvl) or 0) end
        end
        for id, info in pairs(c.tool.byId or {}) do
            local item, level = c.item.byId[id], tonumber(info.lvl)
            local relevant = (tonumber(info.useDmg) or 0) > 0 or (tonumber(info.atkDmg) or 0) > 0
            local excluded = info.toolType == "gun" or info.toolType == "ranged" or info.toolType == "infGun"
            if item and item.recipeId and level and info.toolType and relevant and not excluded
                and level > (best[info.toolType] or 0) and count(item.displayName) == 0 then
                local previous = nextTools[info.toolType]
                if not previous or level < previous.level or (level == previous.level and tostring(id) < tostring(previous.id)) then
                    nextTools[info.toolType] = {id = id, info = item, level = level, base = best[info.toolType] or 0}
                end
            end
        end
        for _, candidate in pairs(nextTools) do
            result[#result + 1] = {key = "craft:" .. candidate.id, id = candidate.id, kind = "craft", info = candidate.info,
                rank = (candidate.base == 0 and not work.meleeWeapon()) and 0.03 or (candidate.base == 0 and 1 or 3 + candidate.base),
                name = itemLabel("tool", candidate.id, candidate.info), amounts = work.recipeAmounts(candidate.info)}
        end
        for id, checked in pairs(selected.craft or {}) do
            local item = checked and c.item.byId[id]
            if item and item.recipeId and count(item.displayName) == 0 then
                result[#result + 1] = {key = "selected:" .. id, id = id, kind = "craft", info = item,
                    rank = 2.5, name = itemLabel("craft", id, item), amounts = work.recipeAmounts(item)}
            end
        end
        table.sort(result, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.key < b.key) end)
        return result
    end
    function work.chooseUpgrade()
        work.upgradeBlocked = work.upgradeBlocked or {}
        local candidates = work.upgradeCandidates()
        -- Essential requests / capacity can take the next turn; active actions remain atomic.
        for _, goal in ipairs(candidates) do
            local blocked = work.upgradeBlocked[goal.key]
            if goal.rank < 0.5 and (not blocked or blocked <= os.clock()) then
                work.upgradeBlocked[goal.key] = nil
                work.objective = goal
                return goal
            end
        end
        -- Keep other chosen objectives stable while their materials are being collected.
        for _, goal in ipairs(candidates) do
            if work.objective and goal.key == work.objective.key and not work.upgradeBlocked[goal.key] then
                work.objective = goal
                return goal
            end
        end
        for _, goal in ipairs(candidates) do
            local untilTime = work.upgradeBlocked[goal.key]
            if not untilTime or untilTime <= os.clock() then
                work.upgradeBlocked[goal.key] = nil
                work.objective = goal
                return goal
            end
        end
        work.objective = nil
    end
    function work.planProgression()
        local goal = work.chooseUpgrade()
        work.processing = nil
        if not goal then
            note("progression", "NO AVAILABLE UPGRADE / BLUEPRINT")
            if work.upgradeLabel then work.upgradeLabel.Text = "NO AVAILABLE UPGRADE / BLUEPRINT" end
            return
        end
        local missing = work.missing(goal.amounts)
        local c = config()
        local resultId = c.misc and c.misc.furnaceResultId
        for id, amount in pairs(missing) do
            if id == resultId and built("Furnace") then
                work.processing = true
                local a, b = c.misc.furnaceMatter1Id, c.misc.furnaceMatter2Id
                local ready = furnaceData.readyCount or 0
                local batches = math.max(0, amount - ready)
                work.needItem(a, math.max(0, batches - (furnaceData.matter1Count or 0)), 100)
                work.needItem(b, math.max(0, batches - (furnaceData.matter2Count or 0)), 100)
            else
                work.needItem(id, goal.amounts[id], 100)
            end
        end
        local lines = {}
        for id, rank in pairs(work.needs) do
            local item = c.item.byId[id]
            if item then lines[#lines + 1] = itemLabel("material", id, item) .. " x" .. tostring(work.amounts[id] or 1) end
        end
        table.sort(lines)
        note("progression", goal.name .. (#lines > 0 and (" • NEED " .. table.concat(lines, ", ")) or " • READY"))
        if work.upgradeLabel then work.upgradeLabel.Text = taskStatus.progression end
    end
    function work.progressionTick()
        work.refreshAt = 0
        work.refreshNeeds()
        local goal = work.objective
        if not goal then return false end
        if work.previousGoal ~= goal.key then work.previousGoal = goal.key work.upgradeStalls = 0 end
        local before, acted = work.signature(), false
        local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        local missing = work.missing(goal.amounts)
        local used, cap = work.bagState()
        local full = used and cap and used >= cap
        if goal.kind == "quest" then
            if not next(missing) or (full and count(config().item.byId[work.questRequirement.itemId].displayName) > 0) then
                acted = questTick("progression")
            end
        elseif goal.kind == "bag" then
            if not next(missing) or full then acted = work.stationTick(goal) end
        elseif goal.kind == "fuel" then
            local item = work.fuelItem()
            if item and count(item.displayName) > 0 and (not next(missing) or full) then
                if travel(built("Campfire"), "progression") then
                    local amount = math.min(count(item.displayName), goal.amounts[item.id])
                    for _ = 1, amount do
                        if not work.running("progression", player.Character, motion.serial)
                            or os.clock() >= deadline
                            or (tonumber(campData.campfireLevel) or 0) > goal.level then break end
                        if not work.request("progression", "MakeFire", "addWood") then break end
                        acted = true
                    end
                end
            end
        elseif goal.kind == "build" then
            local has = false
            for id in pairs(goal.amounts) do if count(config().item.byId[id].displayName) > 0 then has = true end end
            if not next(missing) or (full and has) then
                acted = work.contribute("progression", false, goal.id)
            end
        elseif not next(missing) then
            acted = work.request("progression", "CraftItems", "craft", goal.id)
        end
        if work.preempted then return acted end
        if not acted and work.processing then
            if (furnaceData.readyCount or 0) > 0 and work.canCollect() then
                acted = travel(built("Furnace"), "progression") and work.request("progression", "Furnace", "collectResult")
            else
                local c = config()
                local a, b = c.item.byId[c.misc.furnaceMatter1Id], c.item.byId[c.misc.furnaceMatter2Id]
                if a and b and (count(a.displayName) > 0 or count(b.displayName) > 0) then
                    acted = travel(built("Furnace"), "progression") and work.request("progression", "Furnace", "addBoth")
                end
            end
        end
        if not acted and next(work.needs) and work.canCollect() then
            acted = pickups("progression", true)
            if not acted then acted = gatherResource("progression", true) end
        end
        if work.preempted then return acted end
        work.refreshAt = 0
        work.refreshNeeds()
        if acted or work.signature() ~= before then work.upgradeStalls = 0
        else
            work.upgradeStalls = (work.upgradeStalls or 0) + 1
            if work.upgradeStalls >= 3 and not work.processing then
                work.upgradeBlocked[goal.key] = os.clock() + ((goal.kind == "quest" or goal.kind == "bag") and 2 or 5)
                work.objective = nil
                work.upgradeStalls = 0
                note("progression", "UPGRADE BLOCKED: " .. goal.name .. " • RETRYING SHORTLY")
            end
        end
        return acted
    end
    function work.refreshNeeds()
        if work.refreshAt and os.clock() < work.refreshAt then
            return
        end
        work.refreshAt = os.clock() + 0.15
        work.needs = {}
        work.amounts = {}
        work.resourceNeeds = {}
        local c = config()
        if flags.quest or flags.progression then work.readQuest(false) end
        if flags.progression then
            work.planProgression()
        else
            if flags.fuel and built("Campfire") and (campData.campfireWoodCount or 0) < opts.fuel then
                local info = c.build.byId.campfire
                local fuel = info and info.config and info.config["燃料"]
                local item = fuel and c.item.byName[fuel]
                if item then
                    work.needItem(item.id, math.max(1, opts.fuel - (campData.campfireWoodCount or 0)), 100)
                end
            end
            local w = world()
            local folder = w and w:FindFirstChild("Buildings")
            if folder and (flags.build or flags.buildCurrent) then
                for id, info in pairs(c.build.byId) do
                    if folder:FindFirstChild(info.assetId .. "_Construct") and (flags.buildCurrent or allowed("build", id)) then
                        work.needRecipe(info, info.assetId == "Campfire" and 95 or 55)
                    end
                end
            end
            if flags.craft then
                for id, v in pairs(selected.craft or {}) do
                    local item = c.item.byId[id]
                    if v and item and count(item.displayName) == 0 then
                        work.needRecipe(item, 60)
                    end
                end
            end
        end
        local w = world()
        if flags.quest and not flags.progression and work.questRequirement then
            local req = work.questRequirement
            work.needItem(req.itemId, math.max(0, req.count - #work.questDrops(req)), 100)
        end
        for id, info in pairs(c.worldResource.byId) do
            local drops = c.itemDrop and c.itemDrop.byId and c.itemDrop.byId[info.dropId]
            for _, entry in pairs(drops or {}) do
                if type(entry) == "table" then
                    local item = c.item.byName[entry.itemCN]
                    if item then
                        work.resourceNeeds[id] = math.max(work.resourceNeeds[id] or 0, work.needs[item.id] or 0)
                    end
                end
            end
        end
    end
    work.waitReasons = {
        progression = "WAITING FOR AN AVAILABLE UPGRADE",
        hunt = "NO ELIGIBLE ENEMY / MELEE WEAPON",
        eat = "HEALTH / HUNGER OK OR NO ELIGIBLE FOOD",
        combat = "NO NEARBY ENEMY OR NO MELEE WEAPON",
        travel = "NO MANUAL TRAVEL REQUEST",
        escape = "BOAT PROMPT NOT AVAILABLE",
        fuel = "CAMPFIRE MISSING, FUEL READY OR STATE UNKNOWN",
        quest = "NO READY QUEST ITEMS",
        build = "SELECT BUILDING / NEED MATERIALS",
        buildCurrent = "NO ACTIVE BLUEPRINT OR NEED MATERIALS",
        craft = "SELECT ITEMS TO CRAFT",
        cook = "CAMPFIRE MISSING OR NO COOKABLE FOOD OWNED",
        cooked = "NO READY FOOD / CAMPFIRE MISSING",
        smelt = "FURNACE MISSING OR NEED INGREDIENTS",
        smeltCollect = "NO READY OUTPUT / FURNACE MISSING",
        water = "NO READY COCONUTS OR BAG FULL",
    }
    function work.jobEnabled(job)
        return job.enabled and job.enabled() or (not job.enabled and flags[job.key] == true)
    end
    function work.keyEnabled(key)
        if flags[key] == true then return true end
        local job = work.jobsByKey and work.jobsByKey[key]
        return job and work.jobEnabled(job) or false
    end
    function work.rank(job)
        local key = job.key
        if key == "evade" then return 0 end
        if key == "combat" then return work.baseThreat() and 1 or 5 end
        if key == "eat" then
            local _, human = root()
            return human and human.Health / human.MaxHealth * 100 <= opts.retreatHealth and 2 or 6
        end
        if key == "fuel" then
            return campData.isOnFire == false and 3 or 16
        end
        if key == "escape" then return 4 end
        if key == "mrbeastReward" then return 7 end
        if key == "bagUpgrade" then return 8 end
        if key == "progression" then
            local goal = work.objective
            if goal and goal.kind == "bag" then return 9 end
            if goal and goal.kind == "fuel" and campData.isOnFire == false then return 3 end
            if goal and goal.kind == "build" and work.buildRank(goal.info) == 0 then return 3 end
            if goal and goal.kind == "quest" then return 12 end
            return 14
        end
        local ranks = {quest = 12, recoverDrops = 13, travel = 15, cooked = 17, cook = 18,
            buildCurrent = 19, build = 20, craft = 21, smeltCollect = 22, smelt = 23,
            water = 24, drops = 25, gather = 26, hunt = 27, puzzles = 28, chests = 29, fish = 30}
        return ranks[key] or 40
    end
    function work.pick(jobs, now, ceiling)
        local best, bestScore
        for _, job in ipairs(jobs) do
            if work.jobEnabled(job) and now >= (due[job.key] or 0) then
                local ok, ready, rank = pcall(function()
                    local rank = work.rank(job)
                    if ceiling and rank >= ceiling then return false, rank end
                    return not job.ready or job.ready(), rank
                end)
                if not ok then
                    note(job.key, "READINESS ERROR: " .. tostring(ready))
                    due[job.key] = now + 0.5
                elseif ready and (not bestScore or rank < bestScore) then
                    best, bestScore = job, rank
                end
            end
        end
        return best, bestScore
    end
    function work.checkpoint(key)
        if not work.active or not work.currentJob or not work.jobs then return true end
        if work.preempted then return false end
        if os.clock() < (work.nextPriorityCheck or 0) then return true end
        work.nextPriorityCheck = os.clock() + 0.03
        local job, rank = work.pick(work.jobs, os.clock(), work.rank(work.currentJob))
        if job then
            work.preempted = {from = work.active, to = job.key, rank = rank}
            work.suspended = work.suspended or {}
            work.suspended[work.active] = true
            note("queue", "INTERRUPT: " .. work.active:upper() .. " → " .. job.key:upper())
            motion.cancel("HIGHER PRIORITY: " .. job.key:upper())
            return false
        end
        return true
    end
    function work.pause(key, seconds)
        local untilTime = os.clock() + math.max(0, seconds or 0)
        local character, serial = player.Character, motion.serial
        repeat
            if not work.running(key, character, serial) then return false end
            if os.clock() >= untilTime then return true end
            task.wait()
        until not alive
        return false
    end
    function work.strike(tool, stats, targets, resources, key)
        equip(tool)
        if not work.pause(key, math.max(0, (work.nextStrikeAt or 0) - os.clock())) then return false end
        if not work.checkpoint(key) then return false end
        local r = root()
        if not r or tool.Parent ~= player.Character then return false end
        for _, model in ipairs(targets) do
            if not model.Parent or not work.stanceScore(r.Position, model, stats) then return false end
        end
        for _, model in ipairs(resources) do
            if not model.Parent or not work.safeResource(model)
                or (r.Position - pos(model)).Magnitude > (stats.range or 6) then return false end
        end
        work.nextStrikeAt = os.clock() + math.max(0, tonumber(stats.useCd) or 0.7)
        RS.Events.meleeHitRemote:FireServer(targets, resources)
        work.sent = work.sent + 1
        return true
    end
    local function blueprintReady(onlySelected)
        local folder = world() and world():FindFirstChild("Buildings")
        if not folder then
            return false
        end
        local c = config()
        for id, info in pairs(c.build.byId) do
            if (not onlySelected or allowed("build", id)) and folder:FindFirstChild(info.assetId .. "_Construct") then
                for key, n in pairs(c.recipe.byId[info.recipeId] or {}) do
                    local itemId = type(key) == "string" and key:match("^require_(.+)$")
                    local item = itemId and c.item.byId[itemId]
                    if item and type(n) == "number" and work.remaining(info, itemId, n) > 0 and count(item.displayName) > 0 then
                        return true
                    end
                end
            end
        end
        return false
    end
    local function escapeReady()
        local w = world()
        if not w then
            return false
        end
        for _, o in ipairs(w:GetDescendants()) do
            if o:IsA("LocalScript") and o.Name == "BoatEscapeClient" then
                local part = o.Parent:FindFirstChild("promptPart")
                local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
                if prompt and prompt.Enabled then
                    return true
                end
            end
        end
        return false
    end
    local jobsList = {
        {
            key = "evade", priority = 0, cooldown = 0,
            enabled = function() return opts.avoidEnemies and work.automationOn() end,
            ready = function() return work.personalThreat() ~= nil end,
            run = work.evade,
        },
        {
            key = "mrbeastReward", priority = 1.9, cooldown = 0.02,
            enabled = function() return flags.quest or flags.progression end,
            ready = function()
                if work.choices and work.choiceSentVersion == work.choiceVersion and os.clock() - (work.choiceSentAt or 0) >= 2.5 then
                    work.choiceSentVersion = nil
                end
                return work.choices and work.choiceSentVersion ~= work.choiceVersion
            end,
            run = work.rewardChoiceTick,
        },
        {
            key = "bagUpgrade", priority = 2.15, cooldown = 0.02,
            ready = function() return work.bagCandidate() ~= nil end,
            run = work.bagUpgradeTick,
        },
        {
            key = "recoverDrops", priority = 2.4, cooldown = 0.02,
            enabled = function() return work.treeDrops and flags[work.treeDrops.key] end,
            ready = function() return work.canCollect() and work.treeDrops and flags[work.treeDrops.key] end,
            run = work.recoverTreeDrops,
        },
        {
            key = "eat",
            priority = 0,
            urgent = true,
            cooldown = 2,
            ready = foodReady,
            run = eat,
        },
        {
            key = "combat",
            priority = 1,
            urgent = true,
            cooldown = 0.5,
            ready = enemyReady,
            run = defend,
        },
        {
            key = "travel",
            priority = 2,
            cooldown = 0.2,
            ready = function()
                return motion.manual ~= nil
            end,
            run = function()
                local request = motion.manual
                motion.manual = nil
                if request then
                    travel(request.target, "travel")
                end
                flags.travel = false
                return true
            end,
        },
        {
            key = "progression",
            priority = 2.5,
            cooldown = 0.2,
            ready = function() return work.objective ~= nil end,
            run = work.progressionTick,
        },
        {
            key = "hunt",
            priority = 8,
            cooldown = 1,
            ready = function() return work.meleeWeapon() ~= nil and work.enemy(opts.huntRadius) ~= nil end,
            run = function() return defend("hunt") end,
        },
        {
            key = "escape",
            priority = 2.1,
            cooldown = 4,
            ready = escapeReady,
            run = escapeTick,
        },
        {
            key = "fuel",
            priority = function()
                local w = world()
                local phase = w and w:FindFirstChild("Phase")
                return (campData.isOnFire == false or (phase and tostring(phase.Value):lower():find("night"))) and 2.3 or 3.5
            end,
            cooldown = 4,
            ready = function()
                local item = work.fuelItem()
                return built("Campfire") and item and count(item.displayName) > 0
                    and ((campData.campfireWoodCount == nil and not work.fuelProbe)
                        or (type(campData.campfireWoodCount) == "number" and campData.campfireWoodCount < opts.fuel))
            end,
            run = work.fuel,
        },
        {
            key = "buildCurrent",
            priority = function()
                return built("Campfire") and 6 or 3.2
            end,
            cooldown = 4,
            ready = function()
                return not (flags.progression and work.objective) and blueprintReady(false)
            end,
            run = buildCurrentTick,
        },
        {
            key = "quest",
            priority = 2.05,
            cooldown = 0.02,
            ready = function()
                local req = work.questRequirement
                if not req then return false end
                local used, cap = work.bagState()
                return work.questTotal(req) >= req.count or (used >= cap and count(config().item.byId[req.itemId].displayName) > 0)
            end,
            run = questTick,
        },
        {
            key = "drops",
            priority = function()
                return next(work.needs) and 7 or 12
            end,
            cooldown = 0.4,
            ready = function() return not (flags.progression and work.objective) and work.canCollect() and work.pickupCandidate(false) ~= nil end,
            run = pickups,
        },
        {
            key = "cooked",
            priority = 4.5,
            cooldown = 3,
            ready = function()
                return work.canCollect() and built("Campfire") and (campData.readyCount or 0) > 0
            end,
            run = function()
                return travel(built("Campfire"), "cooked") and work.request("cooked", "MakeFire", "collectFood")
            end,
        },
        {
            key = "craft",
            priority = 5,
            cooldown = 3,
            ready = function()
                if flags.progression and work.objective then return false end
                for id, selectedItem in pairs(selected.craft or {}) do
                    local item = selectedItem and config().item.byId[id]
                    if item and count(item.displayName) == 0 and recipeReady(item) then return true end
                end
                return false
            end,
            run = craftTick,
        },
        {
            key = "build",
            priority = function()
                return built("Campfire") and 6 or 3.3
            end,
            cooldown = 4,
            ready = function()
                return not (flags.progression and work.objective) and not selectedEmpty("build") and blueprintReady(true)
            end,
            run = buildTick,
        },
        {
            key = "cook",
            priority = 4,
            cooldown = 4,
            ready = work.cookReady,
            run = work.cook,
        },
        {
            key = "smeltCollect",
            priority = 8.5,
            cooldown = 3,
            ready = function()
                return work.canCollect() and built("Furnace") and (furnaceData.readyCount or 0) > 0
            end,
            run = function()
                return travel(built("Furnace"), "smeltCollect") and work.request("smeltCollect", "Furnace", "collectResult")
            end,
        },
        {
            key = "water",
            priority = 9,
            cooldown = 10,
            ready = function()
                return work.canCollect() and work.waterDrop() ~= nil
            end,
            run = function()
                local drop = work.waterDrop()
                return drop and work.collectModel(drop, "water") or false
            end,
        },
        {
            key = "smelt",
            priority = 6.2,
            cooldown = 5,
            ready = function()
                local c = config()
                local a, b = c.item.byId[c.misc.furnaceMatter1Id], c.item.byId[c.misc.furnaceMatter2Id]
                return built("Furnace") ~= nil and ((a and count(a.displayName) > 0) or (b and count(b.displayName) > 0))
            end,
            run = function()
                return travel(built("Furnace"), "smelt") and work.request("smelt", "Furnace", "addBoth")
            end,
        },
        {
            key = "puzzles",
            priority = 10,
            cooldown = 3,
            run = function()
                return exploreTick("puzzles", "puzzle", "PuzzlePropService", "isSolved", "requestSolve")
            end,
        },
        {
            key = "chests",
            priority = 11,
            cooldown = 3,
            run = function()
                return exploreTick("chests", "chest", "ChestService", "isOpened", "requestOpen")
            end,
        },
        {
            key = "gather",
            priority = function()
                return next(work.needs) and 7.5 or 13
            end,
            cooldown = 0.3,
            ready = function() return not (flags.progression and work.objective) and work.canCollect() end,
            run = gatherResource,
        },
        {
            key = "fish",
            priority = 14,
            cooldown = 2,
            run = fishTick,
        },
    }
    work.jobs, work.jobsByKey = jobsList, {}
    for _, job in ipairs(jobsList) do work.jobsByKey[job.key] = job end
    function work.settleCuts()
        work.dropQueue = work.dropQueue or {}
        for model, context in pairs(work.resourcePlans or {}) do
            local hp = model:GetAttribute("hp")
            if not model.Parent or (type(hp) == "number" and hp <= 0) then
                work.dropQueue[#work.dropQueue + 1] = context
                work.resourcePlans[model] = nil
            end
        end
        if not work.treeDrops and #work.dropQueue > 0 then work.treeDrops = table.remove(work.dropQueue, 1) end
    end
    local function cancelFishing()
        if fish.mini then
            fish.mini:cancel()
            fish.mini = nil
        end
        if fish.state ~= "idle" and events and events:FindFirstChild("fishCancelRemote") then
            events.fishCancelRemote:FireServer()
        end
        fish.state = "idle"
        fish.tool = nil
        if work.active == "fish" then work.active, work.currentJob = nil, nil end
        due.fish = os.clock() + 3
    end
    local function claimRewards()
        limited("daily", 10, function()
            if rewardData.daily == "canClaim" then
                call("DailyReward", "claim")
            else
                note("daily", "NOT CLAIMABLE")
            end
        end)
        limited("weekly", 10, function()
            for i, v in pairs((rewardData.week or {}).days or {}) do
                if v == "Claim" then
                    call("WeekReward", "claim", i)
                    return
                end
            end
            note("weekly", "NOT CLAIMABLE")
        end)
        limited("playtime", 10, function()
            for id, v in pairs((rewardData.play or {}).rewards or {}) do
                if v.canClaim and not v.claimed then
                    call("PlayTimeReward", "claim", id)
                    return
                end
            end
            note("playtime", "NOT CLAIMABLE")
        end)
        limited("dailyQuest", 10, function()
            for _, v in pairs((rewardData.quest or {}).list or {}) do
                if v.completed and not v.claimed then
                    call("DailyQuest", "claim", v.id)
                    return
                end
            end
            note("dailyQuest", "NO COMPLETED REWARDS")
        end)
    end
    task.spawn(function()
        while alive do
            local ok, e = pcall(function()
                safely("clock", function()
                    local w = world()
                    if w then
                        local d = w:FindFirstChild("Day")
                        local phase = w:FindFirstChild("Phase")
                        clockLabel.Text = "DAY " .. tostring(d and d.Value or "—") .. " | " .. tostring(phase and phase.Value or "—")
                    end
                end)
                local mode = serverMode()
                modeLabel.Text = mode == "match" and "SERVER: MATCH" or (mode == "lobby" and "SERVER: LOBBY - ENTER A MATCH" or "SERVER: LOADING")
                claimRewards()
                if mode ~= "match" then
                    for _, job in ipairs(jobsList) do
                        if flags[job.key] then
                            note(job.key, "ENTER A MATCH FIRST")
                        end
                    end
                    if fish.state ~= "idle" then
                        cancelFishing()
                    end
                    return
                end
                work.bindFastServices()
                safely("material planning", work.refreshNeeds)
                work.settleCuts()
                work.preempted = nil
                work.nextPriorityCheck = 0
                local now = os.clock()
                local job = safely("queue readiness", function()
                    return work.pick(jobsList, now)
                end)
                if fish.state ~= "idle" and flags.fish and job and work.rank(job) < work.rank(work.jobsByKey.fish) then
                    cancelFishing()
                    due.fish = os.clock()
                    note("fish", "INTERRUPTED FOR HIGHER PRIORITY; WILL RECAST")
                end
                if fish.state ~= "idle" and flags.fish then
                    work.currentJob = work.jobsByKey.fish
                    work.active = "fish"
                    queueLabel.Text = "JOB: FISH"
                    safely("fish", fishTick)
                    if fish.state == "idle" then
                        work.active, work.currentJob = nil, nil
                        due.fish = os.clock()
                    end
                    return
                elseif fish.state ~= "idle" then
                    cancelFishing()
                end
                if not job then
                    queueLabel.Text = "JOB: WAITING"
                    note("queue", "WAITING FOR READY JOBS")
                    return
                end
                work.active = job.key
                work.currentJob = job
                if work.suspended then work.suspended[job.key] = nil end
                queueLabel.Text = "LEVEL " .. work.rank(job) .. " | " .. job.key:upper()
                note("queue", "ACTIVE: " .. job.key:upper())
                local before = work.sent
                local result = safely(job.key, job.run)
                local acted = result == true
                local requested = work.sent > before
                work.failures = work.failures or {}
                work.failures[job.key] = (acted or work.preempted) and 0 or (work.failures[job.key] or 0) + 1
                local backoff = math.min(2, 0.15 * 2 ^ math.min(4, work.failures[job.key]))
                due[job.key] = os.clock() + (work.preempted and 0 or (acted and 0 or backoff))
                if work.preempted then
                    local nextKey = work.preempted.to
                    due[nextKey] = os.clock()
                    note(job.key, "PAUSED FOR " .. nextKey:upper() .. "; REMAINS ENABLED")
                end
                if requested and not acted and not work.preempted then
                    note("queue", job.key:upper() .. " REQUEST NOT CONFIRMED")
                end
                work.waiting[job.key] = nil
                work.active, work.currentJob = nil, nil
                queueLabel.Text = "LAST JOB: " .. job.key:upper()
                if not acted and not work.preempted then
                    note("queue", job.key:upper() .. " STOPPED / WAITING / UNCONFIRMED; NEXT READY JOB")
                end
            end)
            if not ok then
                note("queue", "ERROR: " .. tostring(e))
                say(e)
                work.active, work.currentJob = nil, nil
                motion.cancel("JOB ERROR")
            end
            if os.clock() >= (work.nextDiagnosticAt or 0) then
                refreshDiagnostics()
                work.nextDiagnosticAt = os.clock() + 0.2
            end
            local wakeAt = os.clock() + math.max(0, opts.interval)
            repeat
                task.wait()
                local ready = work.pick(jobsList, os.clock(), 9)
                if ready then break end
            until not alive or os.clock() >= wakeAt
        end
    end)
    say("ISLAND ESCAPE LOADED • CONFIG SAVED PER GAME")
end
runIslandEscape()


