-- EXIScript | Zombie Rush Survival | initial test release
-- Lobby: 82457571485380. Both gameplay maps: 87413622775071.
-- Each EXIS game keeps its own module and configuration.
local Core = {}

function Core.finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function Core.cross(a, b, c)
    return (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
end

function Core.onSegment(p, a, b)
    return math.abs(Core.cross(a, b, p)) < 0.0001
        and p.x >= math.min(a.x, b.x) - 0.0001 and p.x <= math.max(a.x, b.x) + 0.0001
        and p.z >= math.min(a.z, b.z) - 0.0001 and p.z <= math.max(a.z, b.z) + 0.0001
end

function Core.intersects(a, b, c, d)
    local ab1, ab2 = Core.cross(a, b, c), Core.cross(a, b, d)
    local cd1, cd2 = Core.cross(c, d, a), Core.cross(c, d, b)
    return (ab1 * ab2 < 0 and cd1 * cd2 < 0)
        or Core.onSegment(c, a, b) or Core.onSegment(d, a, b)
        or Core.onSegment(a, c, d) or Core.onSegment(b, c, d)
end

function Core.validPolygon(poly)
    if type(poly) ~= "table" or #poly < 3 or #poly > 24 then return false, "USE 3–24 DOTS" end
    local area = 0
    for i, p in ipairs(poly) do
        if type(p) ~= "table" or not Core.finite(p.x) or not Core.finite(p.y) or not Core.finite(p.z) then
            return false, "INVALID DOT"
        end
        local q = poly[i % #poly + 1]
        if type(q) ~= "table" or not Core.finite(q.x) or not Core.finite(q.z) then return false, "INVALID DOT" end
        if (p.x - q.x) ^ 2 + (p.z - q.z) ^ 2 < 1 then return false, "DOTS TOO CLOSE" end
        area = area + p.x * q.z - q.x * p.z
    end
    if math.abs(area) < 32 then return false, "AREA TOO SMALL" end
    for i = 1, #poly do
        for j = i + 1, #poly do
            if j ~= i + 1 and not (i == 1 and j == #poly) then
                if Core.intersects(poly[i], poly[i % #poly + 1], poly[j], poly[j % #poly + 1]) then
                    return false, "EDGES CANNOT CROSS"
                end
            end
        end
    end
    return true
end

function Core.inside(p, poly)
    local inside = false
    for i, a in ipairs(poly) do
        local b = poly[i % #poly + 1]
        if Core.onSegment(p, a, b) then return true end
        if (a.z > p.z) ~= (b.z > p.z) and p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x then
            inside = not inside
        end
    end
    return inside
end

function Core.edgeDistance(p, a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    local n = dx * dx + dz * dz
    local t = n > 0 and math.max(0, math.min(1, ((p.x - a.x) * dx + (p.z - a.z) * dz) / n)) or 0
    return math.sqrt((p.x - a.x - t * dx) ^ 2 + (p.z - a.z - t * dz) ^ 2)
end

function Core.rectangle(p, width, depth)
    local a, b = width / 2, depth / 2
    return {{x = p.x - a, z = p.z - b}, {x = p.x + a, z = p.z - b},
        {x = p.x + a, z = p.z + b}, {x = p.x - a, z = p.z + b}}
end

function Core.fits(p, width, depth, poly)
    local corners = Core.rectangle(p, width, depth)
    for _, corner in ipairs(corners) do if not Core.inside(corner, poly) then return false end end
    -- Checking corners alone is insufficient for a concave boundary.
    for i, a in ipairs(poly) do
        local b = poly[i % #poly + 1]
        for j, c in ipairs(corners) do
            if Core.intersects(a, b, c, corners[j % 4 + 1]) then return false end
        end
    end
    return true
end

function Core.overlap(a, b, gap)
    return math.abs(a.x - b.x) < (a.w + b.w) / 2 + (gap or 0.3)
        and math.abs(a.z - b.z) < (a.d + b.d) / 2 + (gap or 0.3)
end

function Core.role(name, info)
    if name == "HealingStation" or info.Heal then return "support" end
    if info.Classification and info.Classification.Barricade then return "wall" end
    if info.PlayerBuff or name == "ReconTower" then return "support" end
    if info.Placement and info.Placement.Ability then return "ability" end
    if name:find("Barrel") or name:find("Mine") or name:find("Bomb") or name:find("Trap") then return "trap" end
    return "turret"
end

function Core.plan(poly, specs, limit, existing)
    existing = existing or {}
    if not Core.validPolygon(poly) then return {}, "SELECT A VALID AREA" end
    local minX, maxX, minZ, maxZ, y, center = math.huge, -math.huge, math.huge, -math.huge, 0, {x = 0, z = 0}
    for _, p in ipairs(poly) do
        minX, maxX, minZ, maxZ = math.min(minX, p.x), math.max(maxX, p.x), math.min(minZ, p.z), math.max(maxZ, p.z)
        center.x, center.z, y = center.x + p.x / #poly, center.z + p.z / #poly, y + p.y / #poly
    end
    if maxX - minX > 600 or maxZ - minZ > 600 then return {}, "SELECT A SMALLER AREA" end
    local candidates, step = {}, math.max(2, math.max(maxX - minX, maxZ - minZ) / 24)
    for x = minX, maxX, step do
        for z = minZ, maxZ, step do
            local p = {x = x, y = y, z = z}
            if Core.inside(p, poly) then candidates[#candidates + 1] = p end
        end
    end
    local result, used, reserve = {}, {}, nil
    local supportSize = 4
    for _, spec in ipairs(specs) do
        if spec.role == "support" then supportSize = math.max(supportSize, spec.w + 0.5, spec.d + 0.5) end
    end
    local coverageRange = 24
    for _, spec in ipairs(specs) do if spec.name == "HealingStation" then coverageRange = spec.range or 24 end end
    local score
    for _, p in ipairs(candidates) do
        local blocked = false
        for _, box in ipairs(existing) do
            if Core.overlap({x = p.x, z = p.z, w = supportSize + 0.6, d = supportSize + 0.6}, box) then blocked = true break end
        end
        if not blocked and Core.fits(p, supportSize + 0.6, supportSize + 0.6, poly) then
            local coverage = 0
            for _, box in ipairs(existing) do
                if (p.x - box.x) ^ 2 + (p.z - box.z) ^ 2 <= coverageRange ^ 2 then coverage = coverage + 1000 end
            end
            for _, q in ipairs(candidates) do
                if (p.x - q.x) ^ 2 + (p.z - q.z) ^ 2 <= coverageRange ^ 2 then coverage = coverage + 1 end
            end
            local rank = coverage * 100 - ((p.x - center.x) ^ 2 + (p.z - center.z) ^ 2)
            if not score or rank > score then reserve, score = {x = p.x, z = p.z, w = supportSize, d = supportSize}, rank end
        end
    end
    if not reserve then return {}, "AREA NEEDS ROOM FOR A SUPPORT GAP" end
    -- Keep the support gap even when another class must supply the healer.
    used[1] = reserve
    for _, box in ipairs(existing) do used[#used + 1] = box end
    local function place(spec, p, ignoreReserve)
        local grid = spec.grid or 1
        local w, d = spec.w, spec.d
        local x = (math.floor(p.x / grid - w * 0.5 + 0.5) + w * 0.5) * grid
        local z = (math.floor(p.z / grid - d * 0.5 + 0.5) + d * 0.5) * grid
        local box = {x = x, z = z, w = w * grid, d = d * grid}
        if not Core.fits(box, box.w + 0.1, box.d + 0.1, poly) then return false end
        for i, other in ipairs(used) do
            if not (ignoreReserve and i == 1) and Core.overlap(box, other) then return false end
        end
        box.name, box.role, box.y, box.facing = spec.name, spec.role, y, spec.facing
        result[#result + 1], used[#used + 1] = box, box
        return true
    end
    -- Front-facing barriers first; the first two dots define the front edge.
    table.sort(candidates, function(a, b)
        return Core.edgeDistance(a, poly[1], poly[2]) < Core.edgeDistance(b, poly[1], poly[2])
    end)
    for _, spec in ipairs(specs) do
        if spec.role == "wall" then
            local n = 0
            for _, p in ipairs(candidates) do
                if #result >= limit then break end
                local distance = Core.edgeDistance(p, poly[1], poly[2])
                if distance <= math.max(spec.w, spec.d) + 3 and place(spec, p) then
                    n = n + 1
                    if n >= math.max(1, math.floor(limit * 0.35)) then break end
                end
            end
        end
    end
    for _, spec in ipairs(specs) do
        if spec.role == "support" and #result < limit then
            if not place(spec, reserve, true) then
                for _, p in ipairs(candidates) do if place(spec, p) then break end end
            end
        end
    end
    table.sort(candidates, function(a, b)
        local da = (a.x - reserve.x) ^ 2 + (a.z - reserve.z) ^ 2
        local db = (b.x - reserve.x) ^ 2 + (b.z - reserve.z) ^ 2
        return da < db
    end)
    local turretTypes, trapTypes = 0, 0
    for _, spec in ipairs(specs) do
        if spec.role == "turret" then turretTypes = turretTypes + 1 end
        if spec.role == "trap" then trapTypes = trapTypes + 1 end
    end
    local trapQuota = math.max(1, math.floor(limit * 0.15))
    local turretQuota = math.max(1, math.floor((limit - #result - trapTypes * trapQuota) / math.max(1, turretTypes)))
    for _, spec in ipairs(specs) do
        if spec.role == "turret" or spec.role == "trap" then
            local quota = spec.role == "trap" and trapQuota or turretQuota
            local n = 0
            for _, p in ipairs(candidates) do
                if #result >= limit or n >= quota then break end
                if Core.edgeDistance(p, poly[1], poly[2]) > math.max(spec.w, spec.d) + 3 and place(spec, p) then n = n + 1 end
            end
        end
    end
    return result, "LAYOUT READY", reserve
end

function Core.targetScore(distance, boss, bossFirst, previous)
    return (boss and bossFirst and 1000000 or 0) - distance + (previous and 3 or 0)
end

-- Runtime adapters. The planning functions above have no Roblox dependencies.
local function run()
    if not game:IsLoaded() then game.Loaded:Wait() end
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local Http = game:GetService("HttpService")
    local GuiService = game:GetService("GuiService")
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")
    local env = type(getgenv) == "function" and getgenv() or _G
    if env.EXISZombieRush and env.EXISZombieRush.stop then env.EXISZombieRush.stop() end
    local app = {alive = true, connections = {}, cache = {}, rejected = {}, notes = {}, mapId = "", mode = "",
        next = {}, selectedPage = "MAIN", manual = {}, revision = 0}
    env.EXISZombieRush = app
    local cfg = {version = 1, enabled = true, autoSkip = false, buyClasses = {}, upgradeClasses = {},
        buyWeapons = {}, upgradeWeapons = {}, loadout = {}, autoLoadout = false,
        health = false, gun = false, melee = false, autoPlace = false, defenseTypes = {},
        regions = {}, maxDefenses = 18, reserveCash = 0, fight = false, fly = true,
        headAim = true, bossFirst = true, fireInput = "Mobile", flyHeight = 14, orbitRadius = 16, flySpeed = 32}
    local file = "EXIS_ZombieRushSurvival_" .. player.UserId .. ".json"
    if type(readfile) == "function" and type(isfile) == "function" then
        local ok, data = pcall(function() if isfile(file) then return Http:JSONDecode(readfile(file)) end end)
        if ok and type(data) == "table" and data.version == 1 then
            for key, value in pairs(data) do if type(value) == type(cfg[key]) then cfg[key] = value end end
        end
    end
    for key, limits in pairs({maxDefenses = {1, 48}, reserveCash = {0, 1e12}, flyHeight = {5, 50},
        orbitRadius = {6, 60}, flySpeed = {8, 70}}) do
        local value = cfg[key]
        cfg[key] = Core.finite(value) and math.clamp(value, limits[1], limits[2]) or limits[1]
    end
    function app.save()
        if type(writefile) == "function" then
            local ok, err = pcall(function() writefile(file, Http:JSONEncode(cfg)) end)
            if not ok then app.notes.config = "CONFIG SAVE FAILED: " .. tostring(err) end
        end
    end
    function app.changed()
        app.revision = app.revision + 1
        app.planKey = nil
        if app.saveQueued then return end
        app.saveQueued = true
        task.delay(0.3, function() app.saveQueued = false if app.alive then app.save() end end)
    end
    function app.connect(signal, callback)
        local connection = signal:Connect(callback)
        app.connections[#app.connections + 1] = connection
        return connection
    end
    function app.find(parent, ...)
        for _, name in ipairs({...}) do parent = parent and parent:FindFirstChild(name) end
        return parent
    end
    function app.value(node, fallback)
        if node and node:IsA("ValueBase") then return node.Value end
        return fallback
    end
    function app.data(...)
        return app.find(RS, "ClientData", player.Name, ...)
    end
    function app.balance(currency)
        return tonumber(app.value(app.data("Stats", currency), nil))
    end
    function app.afford(currency, price)
        local balance = currency and app.balance(currency)
        return Core.finite(price) and price >= 0 and balance ~= nil
            and balance - price >= (currency == "Cash" and cfg.reserveCash or 0)
    end
    function app.module(parent, name)
        local object = parent and parent:FindFirstChild(name)
        if not object or not object:IsA("ModuleScript") then return nil end
        if app.cache[object] then return app.cache[object] end
        local ok, result = pcall(require, object)
        if ok then app.cache[object] = result return result end
        app.notes.modules = name .. ": " .. tostring(result)
    end
    local shared = RS:WaitForChild("Shared", 15)
    if not shared then error("Zombie Rush Shared folder did not load") end
    local modules = shared:WaitForChild("Modules", 15)
    local classes = app.module(shared:FindFirstChild("ClassSystem"), "ClassDefinitions")
    local defs = app.module(shared:FindFirstChild("DeployableSystem"), "DeployableDefinitions")
    local deployUpgrades = app.module(shared:FindFirstChild("DeployableSystem"), "DeployableUpgradeDefinitions")
    local utils = app.module(shared:FindFirstChild("DeployableSystem"), "DeployableUtils")
    local placement = app.module(shared:FindFirstChild("DeployableSystem"), "DeployablePlacement")
    local progression = app.module(modules, "ZombuxProgressionDefinitions")
    local maps = app.module(modules, "MapData")
    if not classes or not defs or not deployUpgrades or not progression then error("Required class/defense definitions are unavailable") end
    function app.detect()
        app.mode = game.PlaceId == 82457571485380 and "LOBBY" or "MATCH"
        local id = workspace:GetAttribute("MapId")
        app.mapId = app.mode == "LOBBY" and "Lobby" or (type(id) == "string" and id or "Unknown")
        local row = maps and maps.AvailableData[app.mapId]
        app.mapName = row and row.DisplayName or app.mapId
        local equipped = app.value(app.data("Classes", "Equipped"), nil)
        app.className = type(equipped) == "string" and equipped or nil
        if classes.TestClassAttribute and classes.GetTestClass then
            local testClass = player:GetAttribute(classes.TestClassAttribute)
            if classes.GetTestClass(testClass) then app.className = testClass end
        end
    end
    function app.root()
        local character = player.Character
        local human = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not human or not root or human.Health <= 0 or character:GetAttribute("Downed") == true
            or player:GetAttribute("Downed") == true or player:GetAttribute("PostDeathDead") == true then return nil end
        return root, human
    end
    function app.active()
        return app.alive and cfg.enabled and not app.editing and app.root() ~= nil
    end
    function app.note(key, value)
        app.notes[key] = tostring(value)
        app.lastNote = key:upper() .. " · " .. tostring(value)
    end
    function app.invoke(key, remote, ...)
        if not app.alive or (not cfg.enabled and key ~= "skip") or not remote or not remote:IsA("RemoteFunction") then return nil end
        if os.clock() < (app.next[key] or 0) then return nil end
        app.next[key] = os.clock() + 1
        local ok, result = pcall(remote.InvokeServer, remote, ...)
        if not app.alive then return nil end
        if not ok then
            app.next[key] = os.clock() + 5
            app.note(key, result)
            return nil
        end
        if type(result) == "table" and result.ok == false then
            app.next[key] = os.clock() + (result.reason == "funds" and 3 or 5)
            app.note(key, result.reason or "REJECTED")
        else app.note(key, "REQUEST CONFIRMED") end
        return result
    end
    function app.ownedClass(name)
        return app.value(app.data("Classes", "Owned", name), name == classes.DefaultClass) == true
    end
    function app.classTick()
        local remote = app.find(RS, "ClassSystem_Remotes", "Request")
        for _, name in ipairs(classes.Order) do
            if cfg.buyClasses[name] and not app.ownedClass(name) and classes.IsPurchasable(name) then
                local currency, price = classes.GetPrice(classes.Get(name))
                if app.afford(currency, price) and os.clock() >= (app.next["class:" .. name] or 0) then
                    local previous = app.className
                    local result = app.invoke("class:" .. name, remote, "PurchaseAndEquip", name)
                    -- The native purchase also equips. Restore the previous class unless selected explicitly.
                    if result and result.ok and previous and previous ~= name and app.alive and cfg.enabled then
                        app.invoke("class:restore", remote, "Equip", previous)
                    end
                    return true
                end
            end
        end
        for _, name in ipairs(classes.Order) do
            if cfg.upgradeClasses[name] and app.ownedClass(name) then
                for _, deployable in ipairs(classes.GetDeployableSlots(name)) do
                    local level = tonumber(app.value(app.data("Classes", "DeployableLevels", deployable), 1)) or 1
                    if not deployUpgrades.IsAtMaxLevel(deployable, level) then
                        local currency, price = deployUpgrades.GetPrice(deployable, level)
                        local key = "classUpgrade:" .. deployable
                        if app.afford(currency, price) and os.clock() >= (app.next[key] or 0) then
                            app.invoke(key, remote, "UpgradeDeployable", name, deployable)
                            return true
                        end
                    end
                end
            end
        end
        return false
    end
    function app.weaponTick()
        local remote = app.find(RS, "WeaponProgression_Remotes", "Request")
        if not remote then return false end
        local names = {}
        for name in pairs(progression.WeaponPrices or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local owned = app.data("Weapons", name)
            local key = "weapon:" .. name
            if os.clock() >= (app.next[key] or 0) then
                if cfg.buyWeapons[name] and not owned then
                    local currency, price = progression.GetWeaponPrice(name)
                    if app.afford(currency, price) then app.invoke(key, remote, "Purchase", name) return true end
                elseif cfg.upgradeWeapons[name] and owned then
                    local level = tonumber(app.value(owned:FindFirstChild("Level"), 1)) or 1
                    if level < progression.MaxWeaponLevel then
                        local currency, price = progression.GetWeaponUpgradePrice(name, level)
                        if app.afford(currency, price) then app.invoke(key, remote, "Upgrade", name) return true end
                    end
                end
            end
        end
        if cfg.autoLoadout then
            for tier, name in pairs(cfg.loadout) do
                local index = tonumber(tier)
                local current = app.value(app.data("CurrentLoadout", "TierSlots", "Tier" .. tostring(index)), nil)
                local key = "slot:" .. tostring(tier)
                if index and index >= 1 and index <= #progression.WeaponTiers and app.data("Weapons", name) and current ~= name and os.clock() >= (app.next[key] or 0) then
                    app.invoke(key, remote, "EquipWeaponInSlot", name, index)
                    return true
                end
            end
        end
        return false
    end
    function app.upgradeTick()
        local upgrades = app.module(modules, "PlayerUpgradeDefinitions")
        if not upgrades then return false end
        local _, human = app.root()
        local order = {"gun", "health", "melee"}
        if human and human.Health / human.MaxHealth < 0.5 then order = {"health", "gun", "melee"} end
        local types = {health = "Health", gun = upgrades.WeaponTierUpgradeTypeName, melee = upgrades.MeleeUpgradeTypeName}
        for _, name in ipairs(order) do
            local kind = types[name]
            if cfg[name] and kind and upgrades.Types[kind] then
                local level = upgrades.GetPlayerLevel(player, kind)
                if not upgrades.IsAtMaxLevel(kind, level) then
                    local round = RS:FindFirstChild("RoundInfo")
                    local currency, price = upgrades.GetPrice(kind, level, {Player = player, CurrentLevel = level,
                        Difficulty = app.value(round and round:FindFirstChild("Difficulty"), "Regular")})
                    local key = "upgrade:" .. name
                    if app.afford(currency, price) and os.clock() >= (app.next[key] or 0) then
                        app.invoke(key, app.find(RS, "Events", "Actions", "PurchaseUpgrade"), kind)
                        return true
                    end
                end
            end
        end
        return false
    end
    function app.skipTick()
        if app.mode ~= "MATCH" or not app.alive or not app.root() or app.editing then return end
        local desired = cfg.autoSkip and cfg.enabled
        if not desired and app.skipKnown == nil then return end
        local gameplay = pg:FindFirstChild("Gameplay")
        if gameplay and app.skipKnown == nil then
            -- The native UI's label mirrors the current vote setting.
            for _, node in ipairs(gameplay:GetDescendants()) do
                if node.Name == "SkipLabel" and node:IsA("TextLabel") then
                    if node.Text:find("Auto Skip: ON", 1, true) then app.skipKnown = true
                    elseif node.Text:find("Auto Skip: OFF", 1, true) then app.skipKnown = false end
                end
            end
        end
        if app.skipKnown == desired then return end
        local wave = app.value(app.find(RS, "RoundInfo", "Wave"), 0)
        if type(wave) ~= "number" or wave <= 0 then return end
        local result = app.invoke("skip", app.find(RS, "Events", "Communication", "AutoSkipToggle"))
        if type(result) == "table" and type(result.enabled) == "boolean" then app.skipKnown = result.enabled app.next.skip = os.clock() + 2 end
    end
    function app.region()
        local region = cfg.regions[app.mapId]
        return type(region) == "table" and region or {points = {}}
    end
    function app.mapFilters()
        local result = {}
        for _, name in ipairs({"MapGeometry", "Map"}) do
            local folder = workspace:FindFirstChild(name)
            if folder then result[#result + 1] = folder end
        end
        return result
    end
    function app.raycast(origin, direction, include)
        local params = RaycastParams.new()
        params.FilterType = include and Enum.RaycastFilterType.Include or Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = include or {player.Character, app.markers}
        params.IgnoreWater = false
        return workspace:Raycast(origin, direction, params)
    end
    function app.resolveSurface()
        local saved = app.region().surface
        if not saved then return nil end
        if app.surface and app.surface.Parent and app.surfaceMap == app.mapId
            and (app.surface.Position - Vector3.new(saved.x, saved.y, saved.z)).Magnitude < 0.5 then return app.surface end
        for _, folder in ipairs(app.mapFilters()) do
            for _, part in ipairs(folder:GetDescendants()) do
                if part:IsA("BasePart") and part.Name == saved.name
                    and (part.Position - Vector3.new(saved.x, saved.y, saved.z)).Magnitude < 0.5 then
                    app.surface, app.surfaceMap = part, app.mapId
                    return part
                end
            end
        end
        return nil
    end
    function app.ground(x, z, y)
        local region = app.region()
        local surface = app.resolveSurface()
        if region.surface and not surface then return nil end
        local filters = surface and {surface} or app.mapFilters()
        if #filters == 0 then return nil end
        local hit = app.raycast(Vector3.new(x, y + 8, z), Vector3.new(0, -30, 0), filters)
        if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.65 then return nil end
        if math.abs(hit.Position.Y - y) > 5 then return nil end
        return hit
    end
    function app.clearMarkers()
        if app.markers then app.markers:Destroy() app.markers = nil end
    end
    function app.drawRegion(points, closed)
        app.clearMarkers()
        local folder = Instance.new("Folder")
        folder.Name, folder.Parent = "EXIS_ZOMBIE_AREA", workspace
        app.markers = folder
        local function part(name, size, frame)
            local node = Instance.new("Part")
            node.Name, node.Size, node.CFrame = name, size, frame
            node.Anchored, node.CanCollide, node.CanTouch, node.CanQuery = true, false, false, false
            node.Material, node.Color = Enum.Material.Neon, Color3.fromRGB(65, 162, 255)
            node.Parent = folder
            return node
        end
        for i, p in ipairs(points) do
            local at = Vector3.new(p.x, p.y + 0.3, p.z)
            local dot = part("DOT_" .. i, Vector3.new(0.6, 0.6, 0.6), CFrame.new(at))
            dot.Shape = Enum.PartType.Ball
            local q = points[i + 1] or (closed and points[1])
            if q then
                local to = Vector3.new(q.x, q.y + 0.3, q.z)
                if (to - at).Magnitude > 0.01 then
                    local line = part("EDGE_" .. i, Vector3.new(0.1, 0.1, (to - at).Magnitude), CFrame.lookAt((to + at) / 2, to))
                    if i == 1 then line.Color = Color3.fromRGB(255, 195, 80) end
                end
            end
        end
    end
    function app.specs()
        local result = {}
        if not app.className then return result end
        local region = app.region()
        local poly = region.points or {}
        local outward = #poly >= 2 and Vector3.new(poly[2].z - poly[1].z, 0, poly[1].x - poly[2].x) or Vector3.new(0, 0, -1)
        local center = Vector3.new(0, 0, 0)
        for _, p in ipairs(poly) do center = center + Vector3.new(p.x, p.y, p.z) / #poly end
        if #poly >= 2 and outward:Dot(Vector3.new(poly[1].x, poly[1].y, poly[1].z) - center) < 0 then outward = -outward end
        for _, name in ipairs(classes.GetDeployableSlots(app.className)) do
            local info = defs.Types[name]
            if info and cfg.defenseTypes[name] ~= false and not (info.Placement and info.Placement.Ability) then
                local templates = RS:FindFirstChild("Deployables")
                local template = templates and templates:FindFirstChild(defs.GetTemplateName(name, info))
                local primary = template and utils.GetRootPrimaryPart(template)
                if primary then
                    local w, d = utils.GetFootprint(primary)
                    local facing = placement.FacesCharacter(info) and placement.GetFacingFromLookVector(outward) or 0
                    w, d = placement.GetFacingFootprint(w, d, facing)
                    local level = tonumber(app.value(app.data("Classes", "DeployableLevels", name), 1)) or 1
                    local effective = deployUpgrades.ApplyLevelToTypeInfo(name, info, level)
                    result[#result + 1] = {name = name, role = Core.role(name, info), w = w, d = d,
                        grid = defs.GetNumber(info, "Placement", "GridSize", 1), facing = facing,
                        info = info, primary = primary, range = placement.GetFunctionalRange(effective)}
                else app.note("layout", "MISSING DEFENSE TEMPLATE: " .. name) end
            end
        end
        return result
    end
    function app.layout()
        local key = app.mapId .. ":" .. tostring(app.className) .. ":" .. app.revision
        if key == app.planKey then return app.plan or {} end
        local specs = app.specs()
        local plan, reason, reserve = Core.plan(app.region().points or {}, specs, cfg.maxDefenses, app.defenseBoxes())
        local byName = {}
        for _, spec in ipairs(specs) do byName[spec.name] = spec end
        for _, slot in ipairs(plan) do slot.spec = byName[slot.name] end
        app.plan, app.planKey, app.reserve = plan, key, reserve
        app.note("layout", reason .. " · " .. #plan .. " SLOTS")
        return plan
    end
    function app.defenseBoxes()
        if app.defenseCache and os.clock() < app.defenseCache.untilTime then return app.defenseCache.boxes end
        local folder, boxes = workspace:FindFirstChild("Deployables"), {}
        local poly, floorY = app.region().points or {}, 0
        for _, p in ipairs(poly) do floorY = floorY + p.y / #poly end
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            if model:IsA("Model") and model:GetAttribute("Destroyed") ~= true then
                local primary = model.PrimaryPart
                local grid = model:GetAttribute("GridSize") or 1
                local x, z = model:GetAttribute("GridStartX"), model:GetAttribute("GridStartZ")
                local w, d = model:GetAttribute("FootprintX"), model:GetAttribute("FootprintZ")
                if primary and math.abs(primary.Position.Y - floorY) < 12 then
                    local box
                    if type(x) == "number" and type(z) == "number" and type(w) == "number" and type(d) == "number" then
                        box = {x = (x + w * 0.5) * grid, z = (z + d * 0.5) * grid, w = w * grid, d = d * grid}
                    else
                        box = {x = primary.Position.X, z = primary.Position.Z, w = primary.Size.X, d = primary.Size.Z}
                    end
                    boxes[#boxes + 1] = box
                end
            end
        end
        app.defenseCache = {boxes = boxes, untilTime = os.clock() + 0.1}
        return boxes
    end
    function app.occupied(slot)
        for _, box in ipairs(app.defenseBoxes()) do if Core.overlap(slot, box, 0.1) then return true end end
        for _, pending in pairs(app.pendingPlacements or {}) do
            if os.clock() < pending.expires and Core.overlap(slot, pending.slot) then return true end
        end
        return false
    end
    function app.getPlacement()
        if app.mode ~= "MATCH" or not cfg.autoPlace or app.mapId == "Unknown" or not app.className then return nil end
        local client = app.module(app.find(player, "PlayerScripts", "Client"), "DeployableSystem")
        if not client then return nil end
        local folder, ownedCount = workspace:FindFirstChild("Deployables"), 0
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:GetAttribute("OwnerUserId") == player.UserId and model:GetAttribute("Destroyed") ~= true then ownedCount = ownedCount + 1 end
            end
        end
        if ownedCount >= cfg.maxDefenses then return nil end
        for index, slot in ipairs(app.layout()) do
            local key = app.planKey .. ":" .. index
            if os.clock() >= (app.rejected[key] or 0) and not app.occupied(slot) then
                local currency, price = client.GetCurrentPrice(slot.name)
                if app.afford(currency, price) then
                    local hit = app.ground(slot.x, slot.z, slot.y)
                    if hit then
                        return {key = key, slot = slot, point = hit.Position, class = app.className,
                            map = app.mapId, revision = app.revision}
                    end
                    app.rejected[key] = os.clock() + 10
                end
            end
        end
        return nil
    end
    function app.placeTick()
        if app.target and app.target.boss and cfg.bossFirst and cfg.fight then app.buildGoal = nil return end
        local candidate = app.getPlacement()
        if not candidate then app.buildGoal = nil return end
        local root, human = app.root()
        if not root then return end
        local lift = human.HipHeight + root.Size.Y / 2
        local outward = Vector3.new(root.Position.X - candidate.point.X, 0, root.Position.Z - candidate.point.Z)
        if outward.Magnitude < 0.1 then outward = Vector3.new(1, 0, 0) end
        local side = candidate.point + outward.Unit * math.min(8, math.max(candidate.slot.w, candidate.slot.d) / 2 + 3)
        local sideHit = app.ground(side.X, side.Z, candidate.point.Y)
        local stand = (sideHit and sideHit.Position or candidate.point) + Vector3.new(0, lift, 0)
        local delta = stand - root.Position
        if delta.Magnitude > 10 or math.abs(root.Position.Y - stand.Y) > 2 then
            app.buildGoal = stand
            app.note("defense", "MOVING INTO PLACEMENT RANGE")
            return
        end
        app.buildGoal = nil
        -- Re-check after movement; selection, class, occupancy and cash can change.
        if candidate.class ~= app.className or candidate.map ~= app.mapId or candidate.revision ~= app.revision
            or not cfg.autoPlace or not app.active() or app.occupied(candidate.slot) then return end
        local spec = candidate.slot.spec
        local region = app.region()
        if not Core.fits(candidate.slot, candidate.slot.w + 0.1, candidate.slot.d + 0.1, region.points or {}) then return end
        local result = app.invoke("place", app.find(RS, "DeployableSystem_Remotes", "Place"),
            candidate.slot.name, candidate.point, {Facing = spec.facing})
        if type(result) == "table" and result.ok == true then
            app.pendingPlacements = app.pendingPlacements or {}
            app.pendingPlacements[candidate.key] = {slot = candidate.slot, expires = os.clock() + 5}
            app.note("defense", "PLACED " .. candidate.slot.name:upper())
        elseif result then
            app.rejected[candidate.key] = os.clock() + 8
            app.note("defense", "REJECTED: " .. tostring(result.reason or "UNKNOWN"))
        end
    end
    function app.weapon()
        local guns = app.module(modules, "GunData")
        if not guns then return nil end
        local selected, rank, equipped
        for _, container in ipairs({player.Character, player:FindFirstChild("Backpack")}) do
            if container then
                for _, tool in ipairs(container:GetChildren()) do
                    local info = tool:IsA("Tool") and guns[tool.Name]
                    if type(info) == "table" and info.Type ~= "Melee" then
                        local tier = tonumber(tool:GetAttribute("LoadoutSlotTier")) or 0
                        local score = tier * 1e6 + (tonumber(info.Damage) or 0) * math.max(1, tonumber(info.FireRate) or 60)
                        if tool.Parent == player.Character then equipped = tool end
                        if not rank or score > rank then selected, rank = tool, score end
                    end
                end
            end
        end
        if selected and selected ~= equipped then
            app.releaseFire()
            local toolbar = app.module(pg:FindFirstChild("Toolbar"), "ToolbarService")
            if toolbar then toolbar.RequestEquip(selected.Name)
            else local _, human = app.root() if human then human:EquipTool(selected) end end
            return nil
        end
        return selected, selected and guns[selected.Name]
    end
    function app.head(model)
        local head = model:FindFirstChild("Head", true)
        if head and head:IsA("BasePart") then return head.Position end
        local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart", true)
        if not root then return nil end
        local types = app.module(shared:FindFirstChild("Zombies"), "ZombieTypes")
        local row = types and types.GetById(model:GetAttribute("ZombieTypeId"))
        local hitbox = row and row.hitbox
        return root.Position + Vector3.new(0, hitbox and hitbox.headHeightOffset or 2.45, 0)
    end
    function app.isBoss(model)
        local types = app.module(shared:FindFirstChild("Zombies"), "ZombieTypes")
        local row = types and types.GetById(model:GetAttribute("ZombieTypeId"))
        for _, tag in ipairs(row and row.tags or {}) do if tag == "Boss" then return true end end
        return false
    end
    function app.chooseTarget()
        local root = app.root()
        if not root then return nil end
        local folder = workspace:FindFirstChild("Zombie_ClientVisuals")
        if not folder then return nil end
        local best, score
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model:GetAttribute("ZombieId") ~= nil then
                local point = app.head(model)
                local health = model:FindFirstChildOfClass("Humanoid")
                if point and (not health or health.Health > 0) then
                    local boss = app.isBoss(model)
                    local rank = Core.targetScore((point - root.Position).Magnitude, boss, cfg.bossFirst,
                        app.target and app.target.model == model)
                    if not score or rank > score then best, score = {model = model, point = point, boss = boss}, rank end
                end
            end
        end
        return best
    end
    function app.fireButton()
        local controls = app.find(pg, "Gameplay", "MobileGunControls")
        return controls and controls:FindFirstChild("Fire")
    end
    function app.releaseFire()
        local held = app.held
        if not held then return end
        app.held = nil
        if held.signal and type(firesignal) == "function" then
            pcall(firesignal, UIS.InputEnded, held.token, false)
            app.fireReadyAt = os.clock() + 0.14
        end
        if held.tool and held.tool.Parent then pcall(held.tool.Deactivate, held.tool) end
    end
    function app.holdFire(tool, info)
        if os.clock() < (app.fireReadyAt or 0) then return end
        if app.held and app.held.tool == tool then
            if info.Automatic ~= false or os.clock() - app.held.at < math.max(0.12, 60 / math.max(1, tonumber(info.FireRate) or 300)) then return end
            app.releaseFire()
            app.fireReadyAt = os.clock() + 0.14
            return
        end
        app.releaseFire()
        local button = app.fireButton()
        local token = {UserInputType = Enum.UserInputType.MouseButton1, UserInputState = Enum.UserInputState.Begin,
            KeyCode = Enum.KeyCode.Unknown, Position = Vector3.new(0, 0, 0)}
        if type(firesignal) == "function" and (button or cfg.fireInput == "Native") then
            local signal = cfg.fireInput == "Native" and UIS.InputBegan or button.InputBegan
            local ok = pcall(firesignal, signal, token, false)
            if ok then app.held = {tool = tool, token = token, signal = true, at = os.clock()} return end
        end
        app.note("combat", "FIRE INPUT UNSUPPORTED; AIM ACTIVE, HOLD FIRE MANUALLY")
    end
    function app.reload(tool)
        local info = tool:FindFirstChild("ServerInfo") or tool:FindFirstChild("Info")
        local clip = app.value(info and info:FindFirstChild("Clip"), nil)
        if type(clip) ~= "number" or clip > 0 then return false end
        app.releaseFire()
        if os.clock() < (app.next.reload or 0) then return true end
        app.next.reload = os.clock() + 2
        local button = app.find(pg, "Gameplay", "MobileGunControls", "Reload")
        if type(firesignal) == "function" and button then
            local token = {UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown}
            task.delay(0.15, function()
                if not app.alive or not cfg.enabled or not cfg.fight then return end
                pcall(firesignal, button.InputBegan, token)
                task.defer(function() pcall(firesignal, UIS.InputEnded, token, false) end)
            end)
        else app.note("combat", "RELOAD INPUT UNSUPPORTED") end
        return true
    end
    function app.stopFlight()
        if app.flight then
            local state = app.flight
            app.flight = nil
            state.velocity:Destroy()
            state.attachment:Destroy()
            if state.human.Parent then state.human.AutoRotate = state.autoRotate end
        end
    end
    function app.move(goal, dt)
        local root, human = app.root()
        if not root or not goal then app.stopFlight() return end
        if not cfg.fly then app.stopFlight() human:MoveTo(goal) return end
        if not app.flight or app.flight.root ~= root then
            app.stopFlight()
            local attachment = Instance.new("Attachment")
            attachment.Name, attachment.Parent = "EXIS_FLIGHT", root
            local velocity = Instance.new("LinearVelocity")
            velocity.Name, velocity.Attachment0 = "EXIS_FLIGHT_VELOCITY", attachment
            velocity.RelativeTo, velocity.MaxForce = Enum.ActuatorRelativeTo.World, math.huge
            velocity.VectorVelocity, velocity.Parent = Vector3.new(0, 0, 0), root
            app.flight = {root = root, human = human, attachment = attachment, velocity = velocity, autoRotate = human.AutoRotate}
            human.AutoRotate = false
        end
        local delta = goal - root.Position
        local direction = delta.Magnitude > 0.2 and delta.Unit * math.min(cfg.flySpeed, delta.Magnitude * 4) or Vector3.new(0, 0, 0)
        if direction.Magnitude > 0 then
            local probe = direction.Unit * math.min(5, delta.Magnitude)
            local hit = app.raycast(root.Position, probe, app.mapFilters())
            if hit then
                local slide = direction - hit.Normal * math.min(0, direction:Dot(hit.Normal))
                direction = slide.Magnitude > 0.5 and slide.Unit * math.min(cfg.flySpeed, slide.Magnitude) or Vector3.new(0, 0, 0)
            end
        end
        local rate = math.min(1, dt * 12)
        app.flight.velocity.VectorVelocity = app.flight.velocity.VectorVelocity:Lerp(direction, rate)
    end
    function app.orbitGoal(target)
        local root = app.root()
        if not root then return nil end
        local point = app.head(target.model)
        if not point then return nil end
        local angle = os.clock() * 0.65
        for i = 0, 7 do
            local a = angle + i * math.pi / 4
            local goal = point + Vector3.new(math.cos(a) * cfg.orbitRadius, cfg.flyHeight, math.sin(a) * cfg.orbitRadius)
            if not app.raycast(root.Position, goal - root.Position, app.mapFilters()) then return goal end
        end
        return root.Position
    end
    function app.combatTick(dt)
        if app.mode ~= "MATCH" or not app.active() then
            app.releaseFire() app.stopFlight() app.buildGoal = nil return
        end
        local target = cfg.fight and app.target or nil
        if target and not target.model.Parent then target = nil end
        local build = cfg.autoPlace and app.buildGoal
        if target and target.boss and cfg.bossFirst then build = nil end
        if build then app.releaseFire() app.move(build, dt) return end
        if not target then app.releaseFire() app.stopFlight() return end
        local tool, info = app.weapon()
        if cfg.fly then app.move(app.orbitGoal(target), dt) else app.stopFlight() end
        if not tool or app.reload(tool) then return end
        local point = app.head(target.model)
        local camera = workspace.CurrentCamera
        if not point or not camera then app.releaseFire() return end
        local origin = camera.CFrame.Position
        if app.raycast(origin, point - origin, app.mapFilters()) then app.releaseFire() return end
        app.holdFire(tool, info)
    end
    function app.aimTick()
        if not cfg.fight or not cfg.headAim or not app.active() or not app.target then return end
        if app.buildGoal and not (app.target.boss and cfg.bossFirst) then return end
        local camera, target = workspace.CurrentCamera, app.target.model
        if not camera or not target.Parent then return end
        local point = app.head(target)
        if not point then return end
        local crosshair = app.module(shared:FindFirstChild("ClientGunDependencies"), "CrosshairService")
        local origin = camera.CFrame.Position
        if (point - origin).Magnitude < 0.1 then return end
        camera.CFrame = CFrame.lookAt(origin, point)
        local ray = crosshair and crosshair.GetAimCameraRay(camera)
        if ray then
            local desired, actual = (point - ray.Origin).Unit, ray.Direction.Unit
            local axis = actual:Cross(desired)
            if axis.Magnitude > 0.0001 then
                local rotation = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(actual:Dot(desired), -1, 1)))
                camera.CFrame = CFrame.new(origin) * rotation * camera.CFrame.Rotation
            end
        end
    end
    -- Compact EXIS interface: sidebar categories and expanding child sections.
    local ui = {}
    ui.blue, ui.text, ui.muted = Color3.fromRGB(58, 148, 245), Color3.fromRGB(224, 232, 244), Color3.fromRGB(147, 162, 184)
    function ui.new(class, properties, parent)
        local node = Instance.new(class)
        for key, value in pairs(properties) do node[key] = value end
        node.Parent = parent
        return node
    end
    function ui.round(node, radius)
        ui.new("UICorner", {CornerRadius = UDim.new(0, radius or 7)}, node)
    end
    function ui.stroke(node, color)
        ui.new("UIStroke", {Color = color or Color3.fromRGB(39, 56, 78), Thickness = 1}, node)
    end
    function ui.stack(parent, padding)
        ui.new("UIListLayout", {Padding = UDim.new(0, padding or 4), SortOrder = Enum.SortOrder.LayoutOrder}, parent)
    end
    function ui.textLabel(parent, text, height)
        return ui.new("TextLabel", {Size = UDim2.new(1, 0, 0, height or 25), BackgroundTransparency = 1,
            Text = text, TextColor3 = ui.muted, Font = Enum.Font.Gotham, TextSize = 11,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left}, parent)
    end
    function ui.button(parent, text, callback)
        local button = ui.new("TextButton", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.fromRGB(23, 42, 65),
            Text = text, TextColor3 = ui.text, Font = Enum.Font.GothamMedium, TextSize = 11, AutoButtonColor = true}, parent)
        ui.round(button, 6)
        app.connect(button.Activated, callback)
        return button
    end
    function ui.toggle(parent, text, object, key)
        local row = ui.new("Frame", {Size = UDim2.new(1, 0, 0, 29), BackgroundTransparency = 1}, parent)
        local label = ui.textLabel(row, text, 29)
        label.Size, label.TextColor3 = UDim2.new(1, -50, 1, 0), ui.text
        local button = ui.new("TextButton", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0),
            Size = UDim2.fromOffset(36, 19), Text = "", AutoButtonColor = false}, row)
        ui.round(button, 5)
        local thumb = ui.new("Frame", {Size = UDim2.fromOffset(13, 13), BorderSizePixel = 0,
            BackgroundColor3 = ui.text}, button)
        ui.round(thumb, 3)
        local function refresh()
            local enabled = object[key] == true
            button.BackgroundColor3 = enabled and ui.blue or Color3.fromRGB(44, 52, 67)
            thumb.Position = UDim2.fromOffset(enabled and 20 or 3, 3)
        end
        app.connect(button.Activated, function()
            object[key] = not object[key]
            if object == cfg and (key == "fight" or key == "enabled" or key == "headAim") then app.releaseFire() end
            app.changed()
            refresh()
        end)
        refresh()
        return row
    end
    function ui.number(parent, text, key, low, high)
        local row = ui.new("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1}, parent)
        local label = ui.textLabel(row, text, 30)
        label.Size, label.TextColor3 = UDim2.new(1, -75, 1, 0), ui.text
        local input = ui.new("TextBox", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 3),
            Size = UDim2.fromOffset(67, 24), Text = tostring(cfg[key]), ClearTextOnFocus = false,
            BackgroundColor3 = Color3.fromRGB(17, 28, 44), TextColor3 = ui.text, Font = Enum.Font.Gotham, TextSize = 11}, row)
        ui.round(input, 5)
        app.connect(input.FocusLost, function()
            local value = tonumber(input.Text)
            if Core.finite(value) then cfg[key] = math.clamp(value, low, high) app.changed() end
            input.Text = tostring(cfg[key])
        end)
    end
    local gui = ui.new("ScreenGui", {Name = "EXIS_ZOMBIE_RUSH", ResetOnSpawn = false,
        IgnoreGuiInset = false, DisplayOrder = 100000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, pg)
    local frame = ui.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(520, 354), BackgroundColor3 = Color3.fromRGB(10, 16, 25), BorderSizePixel = 0,
        Active = true}, gui)
    ui.round(frame, 9)
    ui.stroke(frame)
    local scale = ui.new("UIScale", {Scale = 1}, frame)
    function app.resize()
        local camera = workspace.CurrentCamera
        if camera then
            scale.Scale = 1
            frame.Size = UDim2.fromOffset(math.min(app.windowWidth or 520, camera.ViewportSize.X - 24),
                math.min(app.windowHeight or 354, camera.ViewportSize.Y - 55))
        end
    end
    app.resize()
    local titlebar = ui.new("Frame", {Size = UDim2.new(1, 0, 0, 35), BackgroundColor3 = Color3.fromRGB(15, 25, 40),
        BorderSizePixel = 0, Active = true}, frame)
    ui.round(titlebar, 9)
    ui.new("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(20, 42, 68), Color3.fromRGB(11, 18, 30)), Rotation = 0}, titlebar)
    local title = ui.textLabel(titlebar, "  EXIScript | ZOMBIE RUSH SURVIVAL", 35)
    title.Size, title.TextColor3, title.Font = UDim2.new(1, -75, 1, 0), ui.blue, Enum.Font.GothamBold
    local minimize = ui.button(titlebar, "−", function() frame.Visible = false end)
    minimize.Size, minimize.Position = UDim2.fromOffset(27, 25), UDim2.new(1, -63, 0, 5)
    local close = ui.button(titlebar, "×", function() app.stop() end)
    close.Size, close.Position = UDim2.fromOffset(27, 25), UDim2.new(1, -32, 0, 5)
    local icon = ui.new("TextButton", {Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0, 16, 0.5, 0),
        BackgroundColor3 = Color3.fromRGB(12, 25, 42), Text = "EXIS", TextColor3 = ui.blue,
        TextSize = 11, Font = Enum.Font.GothamBold, AutoButtonColor = true}, gui)
    ui.round(icon, 6)
    ui.stroke(icon, ui.blue)
    function ui.draggable(handle, target, activate)
        local pointer, initial, origin, moved
        app.connect(handle.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                pointer, initial, origin, moved = input, input.Position, target.Position, false
            end
        end)
        app.connect(UIS.InputChanged, function(input)
            if not pointer then return end
            if input == pointer or (pointer.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
                local delta = input.Position - initial
                if delta.Magnitude > 5 then moved = true end
                if moved then
                    target.Position = UDim2.new(origin.X.Scale, origin.X.Offset + delta.X, origin.Y.Scale, origin.Y.Offset + delta.Y)
                end
            end
        end)
        app.connect(UIS.InputEnded, function(input)
            if pointer and (input == pointer or input.UserInputType == Enum.UserInputType.MouseButton1) then
                pointer = nil
                if activate and not moved then activate() end
            end
        end)
    end
    ui.draggable(titlebar, frame)
    ui.draggable(icon, icon, function() frame.Visible = not frame.Visible end)
    local grip = ui.new("TextButton", {Size = UDim2.fromOffset(17, 17), Position = UDim2.new(1, -18, 1, -18),
        Text = "◢", TextColor3 = ui.blue, BackgroundTransparency = 1, TextSize = 16, ZIndex = 4}, frame)
    local resizePointer, resizeStart, resizeSize
    app.connect(grip.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizePointer, resizeStart, resizeSize = input, input.Position, frame.AbsoluteSize
        end
    end)
    app.connect(UIS.InputChanged, function(input)
        if resizePointer and (input == resizePointer or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - resizeStart
            app.windowWidth, app.windowHeight = math.clamp(resizeSize.X + delta.X, 340, 800), math.clamp(resizeSize.Y + delta.Y, 260, 650)
            app.resize()
        end
    end)
    app.connect(UIS.InputEnded, function(input)
        if input == resizePointer or input.UserInputType == Enum.UserInputType.MouseButton1 then resizePointer = nil end
    end)
    local navigation = ui.new("ScrollingFrame", {Position = UDim2.fromOffset(8, 44), Size = UDim2.new(0, 94, 1, -69),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 1, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y}, frame)
    ui.stack(navigation, 5)
    local body = ui.new("Frame", {Position = UDim2.fromOffset(112, 44), Size = UDim2.new(1, -122, 1, -69),
        BackgroundTransparency = 1}, frame)
    local footer = ui.textLabel(frame, "READY", 19)
    footer.Position, footer.Size = UDim2.new(0, 10, 1, -21), UDim2.new(1, -20, 0, 19)
    footer.TextTruncate, footer.TextWrapped, footer.TextSize = Enum.TextTruncate.AtEnd, false, 10
    ui.pages, ui.nav, ui.openGroups = {}, {}, {}
    function ui.page(name)
        local page = ui.new("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = ui.blue,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false}, body)
        ui.new("UIPadding", {PaddingRight = UDim.new(0, 4), PaddingLeft = UDim.new(0, 1), PaddingBottom = UDim.new(0, 8)}, page)
        ui.stack(page, 6)
        ui.pages[name] = page
        local button = ui.button(navigation, name, function() ui.show(name) end)
        button.TextSize = 10
        ui.nav[name] = button
        return page
    end
    function ui.show(name)
        app.selectedPage = name
        for key, page in pairs(ui.pages) do
            page.Visible = key == name
            ui.nav[key].BackgroundColor3 = key == name and Color3.fromRGB(26, 65, 107) or Color3.fromRGB(14, 25, 39)
        end
    end
    function ui.group(parent, name)
        local box = ui.new("Frame", {Size = UDim2.new(1, -1, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Color3.fromRGB(15, 23, 35), BorderSizePixel = 0}, parent)
        ui.round(box, 7)
        ui.stroke(box)
        ui.stack(box, 0)
        local header = ui.button(box, "  " .. name .. "    ›", function() end)
        header.TextXAlignment, header.BackgroundTransparency, header.Size = Enum.TextXAlignment.Left, 1, UDim2.new(1, 0, 0, 31)
        local children = ui.new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, Visible = false}, box)
        ui.new("UIPadding", {PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), PaddingBottom = UDim.new(0, 6)}, children)
        ui.stack(children, 2)
        local function set(open)
            children.Visible = open
            header.Text = "  " .. name .. (open and "    ⌄" or "    ›")
        end
        app.connect(header.Activated, function()
            local open = not children.Visible
            local previous = ui.openGroups[parent]
            if previous and previous ~= set then previous(false) end
            ui.openGroups[parent] = open and set or nil
            set(open)
        end)
        return children
    end
    local main = ui.page("MAIN")
    local classPage = ui.page("CLASSES")
    local weaponPage = ui.page("WEAPONS")
    local upgradesPage = ui.page("UPGRADES")
    local defensePage = ui.page("DEFENSE")
    local areaPage = ui.page("AREA")
    local settings = ui.page("SETTINGS")
    local contextLabel = ui.textLabel(main, "DETECTING CLASS / MAP", 42)
    contextLabel.TextColor3, contextLabel.Font = ui.text, Enum.Font.GothamMedium
    local fight = ui.group(main, "FIGHT MODE")
    ui.toggle(fight, "AUTO FIGHT", cfg, "fight")
    ui.toggle(fight, "HEAD AIM", cfg, "headAim")
    ui.toggle(fight, "BOSS FIRST", cfg, "bossFirst")
    ui.textLabel(fight, "Uses your equipped gun's normal fire, ammo and reload rules.", 30)
    local flight = ui.group(main, "FLY AROUND TARGETS")
    ui.toggle(flight, "FLY ORBIT", cfg, "fly")
    ui.number(flight, "HEIGHT", "flyHeight", 5, 50)
    ui.number(flight, "ORBIT RADIUS", "orbitRadius", 6, 60)
    ui.number(flight, "FLY SPEED", "flySpeed", 8, 70)
    local wave = ui.group(main, "WAVES")
    ui.toggle(wave, "AUTO SKIP", cfg, "autoSkip")
    local liveLabel = ui.textLabel(main, "", 62)
    liveLabel.TextYAlignment = Enum.TextYAlignment.Top
    function ui.buildClasses()
        for _, child in ipairs(classPage:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        ui.textLabel(classPage, app.mode == "LOBBY" and "LOBBY · PURCHASE / UPGRADE" or "CURRENT CLASS · LOBBY PURCHASES ONLY", 28)
        local order = app.mode == "MATCH" and {app.className or classes.DefaultClass} or classes.Order
        for _, name in ipairs(order) do
            local row = classes.Get(name)
            if row then
                local group = ui.group(classPage, name:upper())
                local currency, price = classes.GetPrice(row)
                ui.textLabel(group, (app.ownedClass(name) and "OWNED · " or "PRICE ") .. tostring(price) .. " " .. tostring(currency), 23)
                if app.mode == "LOBBY" then
                    ui.toggle(group, "AUTO BUY", cfg.buyClasses, name)
                    ui.toggle(group, "AUTO UPGRADE DEFENSES", cfg.upgradeClasses, name)
                    ui.button(group, "EQUIP CLASS", function() app.manual = {kind = "class", name = name} end)
                end
                for _, deployable in ipairs(classes.GetDeployableSlots(name)) do
                    local level = app.value(app.data("Classes", "DeployableLevels", deployable), 1)
                    local node = ui.textLabel(group, deployable:upper() .. " · LV " .. tostring(level) .. "/" .. deployUpgrades.GetMaxLevel(deployable), 22)
                    node.TextColor3 = ui.text
                end
            end
        end
    end
    function ui.buildWeapons()
        ui.textLabel(weaponPage, "LOBBY PURCHASES · WEAPON LEVELS AND TIER LOADOUTS", 30)
        local loadout = ui.group(weaponPage, "APPLY SELECTED LOADOUT")
        ui.toggle(loadout, "AUTO EQUIP TIER CHOICES", cfg, "autoLoadout")
        for tier, row in ipairs(progression.WeaponTiers) do
            local group = ui.group(weaponPage, "TIER " .. tier)
            for _, name in ipairs(row.Weapons) do
                local weapon = ui.group(group, name:upper())
                ui.toggle(weapon, "AUTO BUY", cfg.buyWeapons, name)
                ui.toggle(weapon, "AUTO UPGRADE LEVEL", cfg.upgradeWeapons, name)
                local button
                button = ui.button(weapon, (cfg.loadout[tostring(tier)] == name and "SELECTED FOR TIER " or "USE IN TIER ") .. tier, function()
                    cfg.loadout[tostring(tier)] = name
                    app.changed()
                    button.Text = "SELECTED FOR TIER " .. tier
                end)
                local owned = app.data("Weapons", name)
                local level = owned and app.value(owned:FindFirstChild("Level"), 1)
                ui.textLabel(weapon, (level and "LV " .. tostring(level) or "NOT OWNED") .. " · MAX " .. tostring(progression.MaxWeaponLevel), 22)
            end
        end
    end
    local upgrades = ui.group(upgradesPage, "MATCH UPGRADES")
    ui.toggle(upgrades, "AUTO HEALTH", cfg, "health")
    ui.toggle(upgrades, "AUTO GUN TIER", cfg, "gun")
    ui.toggle(upgrades, "AUTO MELEE", cfg, "melee")
    ui.textLabel(upgrades, "Health comes first below 50% HP; otherwise gun, health, melee.", 30)
    local upgradeState = ui.textLabel(upgradesPage, "", 50)
    function ui.buildDefenses()
        for _, child in ipairs(defensePage:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        local group = ui.group(defensePage, "AUTO DEFENSE")
        ui.toggle(group, "AUTO PLACE CURRENT CLASS", cfg, "autoPlace")
        ui.number(group, "MAX OWNED DEFENSES", "maxDefenses", 1, 48)
        ui.textLabel(group, "Barricades at front · turrets inside · support gap reserved.", 30)
        local selection = ui.group(defensePage, "CLASS DEFENSE SELECTION")
        for _, name in ipairs(classes.GetDeployableSlots(app.className or classes.DefaultClass)) do
            local info = defs.Types[name]
            if info and Core.role(name, info) ~= "ability" then
                if cfg.defenseTypes[name] == nil then cfg.defenseTypes[name] = true end
                ui.toggle(selection, name:upper(), cfg.defenseTypes, name)
            end
        end
        ui.textLabel(selection, "Healing Station repairs defenses. Buff Barricade buffs players.", 32)
    end
    local area = ui.group(areaPage, "MAP PART / DOT SELECTION")
    ui.textLabel(area, "First two dots define the front. Tap map points, then CONNECT.", 32)
    local areaLabel = ui.textLabel(area, "NO AREA SELECTED", 28)
    local editor = ui.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
        Size = UDim2.fromOffset(310, 76), BackgroundColor3 = Color3.fromRGB(12, 23, 38), Visible = false}, gui)
    ui.round(editor)
    ui.stroke(editor, ui.blue)
    local editorText = ui.textLabel(editor, "TAP MAP POINTS", 29)
    local undo = ui.button(editor, "UNDO", function()
        if app.draft then table.remove(app.draft) app.drawRegion(app.draft, false) end
    end)
    undo.Size, undo.Position = UDim2.fromOffset(74, 30), UDim2.fromOffset(6, 38)
    local connect = ui.button(editor, "CONNECT", function()
        local ok, reason = Core.validPolygon(app.draft or {})
        if not ok then app.note("area", reason) return end
        local previous = app.region()
        cfg.regions[app.mapId] = {points = app.draft, surface = app.draftSurface or previous.surface}
        app.draftSurface = nil
        app.editing, editor.Visible, frame.Visible = false, false, true
        app.drawRegion(app.draft, true)
        app.changed()
    end)
    connect.Size, connect.Position = UDim2.fromOffset(109, 30), UDim2.fromOffset(85, 38)
    local cancel = ui.button(editor, "CANCEL", function()
        app.editing, app.pickPart, app.draftSurface, editor.Visible, frame.Visible = false, false, nil, false, true
        app.drawRegion(app.region().points or {}, true)
    end)
    cancel.Size, cancel.Position = UDim2.fromOffset(104, 30), UDim2.fromOffset(200, 38)
    ui.button(area, "PICK MAP PART", function()
        if app.mode ~= "MATCH" then app.note("area", "JOIN A MAP FIRST") return end
        app.editing, app.pickPart, app.draft, app.draftSurface = true, true, {}, nil
        frame.Visible, editor.Visible = false, true
        app.releaseFire() app.stopFlight()
    end)
    ui.button(area, "DRAW NEW DOT BOUNDARY", function()
        if app.mode ~= "MATCH" or app.mapId == "Unknown" then app.note("area", "WAIT FOR THE MAP") return end
        app.editing, app.pickPart, app.draft, app.draftSurface = true, false, {}, nil
        frame.Visible, editor.Visible = false, true
        app.clearMarkers() app.releaseFire() app.stopFlight()
    end)
    ui.button(area, "ADD CURRENT POSITION DOT", function()
        local root, human = app.root()
        if not root then return end
        local p = root.Position - Vector3.new(0, human.HipHeight + root.Size.Y / 2, 0)
        app.editing, app.draft, editor.Visible = true, app.draft or {}, true
        app.draft[#app.draft + 1] = {x = p.X, y = p.Y, z = p.Z}
        app.drawRegion(app.draft, false)
    end)
    ui.button(area, "SHOW SAVED BOUNDARY", function() app.drawRegion(app.region().points or {}, true) end)
    ui.button(area, "HIDE BOUNDARY", app.clearMarkers)
    ui.button(area, "REMOVE MAP PART LOCK", function()
        local region = app.region()
        region.surface = nil
        cfg.regions[app.mapId] = region
        app.surface = nil
        app.changed()
    end)
    local system = ui.group(settings, "AUTOMATION / CONFIG")
    ui.toggle(system, "MASTER ENABLED", cfg, "enabled")
    ui.number(system, "KEEP CASH RESERVE", "reserveCash", 0, 1e12)
    ui.button(system, "SAVE CONFIG NOW", function() app.save() app.note("config", "SAVED") end)
    ui.button(system, "STOP MOVEMENT / FIRING", function()
        cfg.fight, cfg.autoPlace = false, false
        app.releaseFire() app.stopFlight() app.buildGoal = nil app.changed()
    end)
    local diagnostics = ui.group(settings, "DIAGNOSTICS")
    local diagnosticLabel = ui.textLabel(diagnostics, "", 150)
    diagnosticLabel.TextYAlignment = Enum.TextYAlignment.Top
    diagnosticLabel.AutomaticSize = Enum.AutomaticSize.Y
    ui.button(diagnostics, "COPY DIAGNOSTICS", function()
        if type(setclipboard) == "function" then setclipboard(diagnosticLabel.Text) app.note("diagnostics", "COPIED") end
    end)
    local inputOptions = ui.group(settings, "FIRE INPUT MODE")
    ui.button(inputOptions, "USE MOBILE FIRE BUTTON", function()
        app.releaseFire() cfg.fireInput = "Mobile" app.changed() app.note("combat", "MOBILE FIRE INPUT")
    end)
    ui.button(inputOptions, "USE NATIVE MOUSE INPUT", function()
        app.releaseFire() cfg.fireInput = "Native" app.changed() app.note("combat", "NATIVE FIRE INPUT")
    end)
    ui.textLabel(inputOptions, "Switch input mode if aiming works but firing does not.", 30)
    local resize = ui.group(settings, "WINDOW")
    ui.button(resize, "CENTER / FIT SCREEN", function() frame.Position = UDim2.fromScale(0.5, 0.5) app.resize() end)
    app.connect(UIS.InputBegan, function(input, processed)
        if not app.editing or processed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local screen = Vector2.new(input.Position.X, input.Position.Y)
        if #pg:GetGuiObjectsAtPosition(screen.X, screen.Y) > 0 then
            -- Only our editor blocks selection; the game's transparent full-screen HUD does not.
            for _, object in ipairs(pg:GetGuiObjectsAtPosition(screen.X, screen.Y)) do
                if object:IsDescendantOf(gui) then return end
            end
        end
        local inset = GuiService:GetGuiInset()
        local ray = camera:ViewportPointToRay(screen.X - inset.X, screen.Y - inset.Y)
        local hit = app.raycast(ray.Origin, ray.Direction * 1000, app.mapFilters())
        if not hit or not hit.Instance:IsA("BasePart") or hit.Normal.Y < 0.65 then app.note("area", "TAP A FLOOR SURFACE") return end
        if app.pickPart then
            local part = hit.Instance
            local points = {}
            for _, corner in ipairs({{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) do
                local p = part.CFrame:PointToWorldSpace(Vector3.new(corner[1] * part.Size.X / 2, part.Size.Y / 2, corner[2] * part.Size.Z / 2))
                points[#points + 1] = {x = p.X, y = p.Y, z = p.Z}
            end
            app.draft, app.pickPart = points, false
            app.surface, app.surfaceMap = part, app.mapId
            app.draftSurface = {name = part.Name, x = part.Position.X, y = part.Position.Y, z = part.Position.Z}
        else
            if #app.draft >= 24 then app.note("area", "MAXIMUM 24 DOTS") return end
            local p = hit.Position
            app.draft[#app.draft + 1] = {x = p.X, y = p.Y, z = p.Z}
        end
        app.drawRegion(app.draft, false)
    end)
    function app.stop()
        if not app.alive then return end
        app.alive = false
        app.save()
        app.releaseFire() app.stopFlight() app.clearMarkers()
        RunService:UnbindFromRenderStep("EXIS_ZOMBIE_AIM")
        for _, connection in ipairs(app.connections) do connection:Disconnect() end
        app.connections = {}
        gui:Destroy()
        if env.EXISZombieRush == app then env.EXISZombieRush = nil end
    end
    app.detect()
    ui.buildClasses()
    ui.buildWeapons()
    ui.buildDefenses()
    ui.show("MAIN")
    app.connect(gui.Destroying, app.stop)
    app.connect(player.CharacterRemoving, function() app.releaseFire() app.stopFlight() app.buildGoal = nil end)
    local tickTime = 0
    app.connect(RunService.Heartbeat, function(dt)
        tickTime = tickTime + dt
        if tickTime >= 0.1 then
            tickTime = 0
            local ok, err = pcall(function()
                if cfg.fight and app.active() and app.mode == "MATCH" and app.mapId ~= "Unknown" then app.target = app.chooseTarget()
                else app.target = nil end
            end)
            if not ok then app.note("target", err) end
        end
        local ok, err = pcall(app.combatTick, dt)
        if not ok then app.releaseFire() app.stopFlight() app.note("combat", err) end
    end)
    RunService:BindToRenderStep("EXIS_ZOMBIE_AIM", Enum.RenderPriority.Camera.Value + 5, function()
        local ok, err = pcall(app.aimTick)
        if not ok then app.note("aim", err) end
    end)
    task.spawn(function()
        while app.alive do
            local ok, err = pcall(function()
                local before = app.mapId .. tostring(app.className) .. app.mode
                app.detect()
                if before ~= app.mapId .. tostring(app.className) .. app.mode then
                    app.planKey, app.target, app.buildGoal, app.surface, app.defenseCache = nil, nil, nil, nil, nil
                    app.rejected, app.pendingPlacements = {}, {}
                    ui.buildClasses() ui.buildDefenses()
                end
                if cfg.enabled and not app.editing then
                    if app.manual.kind == "class" and app.mode == "LOBBY" then
                        local name = app.manual.name
                        app.manual = {}
                        if app.ownedClass(name) then app.invoke("equipClass", app.find(RS, "ClassSystem_Remotes", "Request"), "Equip", name)
                        else app.note("class", "CLASS NOT OWNED; SELECT AUTO BUY") end
                    elseif app.mode == "LOBBY" then
                        if not app.classTick() then app.weaponTick() end
                    elseif app.active() and app.mapId ~= "Unknown" then
                        if not app.upgradeTick() then app.placeTick() end
                    end
                end
            end)
            if not ok then app.note("worker", err) end
            task.wait(0.2)
        end
    end)
    task.spawn(function()
        while app.alive do
            local ok, err = pcall(app.skipTick)
            if not ok then app.note("skip", err) end
            task.wait(2)
        end
    end)
    task.spawn(function()
        while app.alive do
            app.resize()
            local round = RS:FindFirstChild("RoundInfo")
            local root, human = app.root()
            contextLabel.Text = app.mode .. " · " .. (app.mapName or "UNKNOWN") .. "\nCLASS: " .. (app.className or "WAITING FOR DATA"):upper()
            liveLabel.Text = "WAVE " .. tostring(app.value(round and round:FindFirstChild("Wave"), "—"))
                .. "  ·  HP " .. (human and math.floor(human.Health) .. "/" .. math.floor(human.MaxHealth) or "DOWN / LOADING")
                .. "\nTARGET: " .. (app.target and ((app.target.boss and "BOSS · " or "") .. tostring(app.target.model:GetAttribute("ZombieVisualName") or app.target.model.Name)) or "NONE")
                .. "\nCASH " .. tostring(app.balance("Cash") or "—") .. "  ·  ZOMBUX " .. tostring(app.balance("Zombux") or "—")
            areaLabel.Text = (app.mapName or "UNKNOWN") .. " · " .. #(app.region().points or {}) .. " DOTS"
            editorText.Text = app.pickPart and "TAP THE MAP PART TO USE" or "DOTS " .. #(app.draft or {}) .. " · FIRST EDGE = FRONT"
            footer.Text = app.lastNote or "INITIAL TEST RELEASE · SELECT FEATURES TO START"
            local upgrades = app.mode == "MATCH" and app.module(modules, "PlayerUpgradeDefinitions")
            if upgrades then
                upgradeState.Text = "HEALTH " .. upgrades.GetPlayerLevel(player, "Health")
                    .. " · GUN " .. upgrades.GetPlayerLevel(player, upgrades.WeaponTierUpgradeTypeName)
                    .. " · MELEE " .. upgrades.GetPlayerLevel(player, upgrades.MeleeUpgradeTypeName)
            else upgradeState.Text = "MATCH UPGRADES ARE AVAILABLE INSIDE A MAP" end
            local lines = {"PLACE " .. game.PlaceId, "MAP " .. app.mapId, "CLASS " .. tostring(app.className),
                "FIRE SIGNAL " .. tostring(type(firesignal) == "function"), "CONFIG WRITE " .. tostring(type(writefile) == "function")}
            local keys = {}
            for key in pairs(app.notes) do keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do lines[#lines + 1] = key:upper() .. ": " .. app.notes[key] end
            diagnosticLabel.Text = table.concat(lines, "\n")
            task.wait(0.5)
        end
    end)
end

local ok, err = pcall(run)
if not ok then warn("EXIScript / ZombieRushSurvival: " .. tostring(err)) end
