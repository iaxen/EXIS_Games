-- EXIScript | Zombie Rush Survival | initial test release
-- Lobby: 82457571485380. Both gameplay maps: 87413622775071.
-- Each EXIS game keeps its own module and configuration.
-- Executor-workspace storage. Old root files remain readable during migration.
local storage = {root = "EXIGames/ZombieRushSurvival"}
function storage.path(name)
    name = tostring(name):gsub("\\", "/")
    if name:sub(1, #storage.root + 1) == storage.root .. "/" then return name end
    return storage.root .. "/" .. name
end
function storage.ensure()
    for _, directory in ipairs({"EXIGames", storage.root}) do
        local exists = false
        if type(isfolder) == "function" then
            local ok, found = pcall(isfolder, directory)
            exists = ok and found == true
        end
        if not exists then
            assert(type(makefolder) == "function", "Cannot create save folder: executor makefolder is unavailable")
            local ok, err = pcall(makefolder, directory)
            if not ok then
                local found = false
                if type(isfolder) == "function" then
                    local checked, present = pcall(isfolder, directory)
                    found = checked and present == true
                end
                assert(found, "Cannot create save folder " .. directory .. ": " .. tostring(err))
            end
        end
    end
end
function storage.write(name, contents)
    assert(type(writefile) == "function", "Executor writefile is unavailable")
    storage.ensure()
    return writefile(storage.path(name), contents)
end
function storage.read(name)
    assert(type(readfile) == "function", "Executor readfile is unavailable")
    local target = storage.path(name)
    local ok, contents = pcall(readfile, target)
    if ok then return contents end
    local legacy = tostring(name):gsub("\\", "/")
    if legacy:sub(1, #storage.root + 1) == storage.root .. "/" then
        legacy = legacy:sub(#storage.root + 2)
    end
    local oldOK, oldContents = pcall(readfile, legacy)
    if not oldOK then error(contents, 0) end
    -- Loading still succeeds if saving is unsupported; never delete the old save.
    pcall(storage.write, target, oldContents)
    return oldContents
end
function storage.exists(name)
    local ok = pcall(storage.read, name)
    return ok
end

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

function Core.mapViewHeight(bounds, width, height, fov, top)
    local aspect = math.max(0.1, width / math.max(1, height))
    local tangent = math.tan(math.rad(fov) / 2)
    local halfX = math.max(4, bounds.maxX - bounds.minX) / 2
    local halfZ = math.max(4, bounds.maxZ - bounds.minZ) / 2
    local usable = math.max(0.2, (height - (top or 0)) / math.max(1, height))
    return math.max(halfZ / (tangent * usable), halfX / (tangent * aspect)) * 1.15
end

function Core.fairChoice(state, keys, random)
    local ready = {}
    for _, key in ipairs(keys) do ready[key] = true end
    state.remaining, state.served = state.remaining or {}, state.served or {}
    local remaining, included = {}, {}
    for _, key in ipairs(state.remaining) do
        if ready[key] then remaining[#remaining + 1], included[key] = key, true end
    end
    for _, key in ipairs(keys) do
        if not included[key] and not state.served[key] then remaining[#remaining + 1] = key end
    end
    if #remaining == 0 then
        remaining, state.served = {}, {}
        for _, key in ipairs(keys) do remaining[#remaining + 1] = key end
    end
    state.remaining = remaining
    if #remaining == 0 then return nil end
    return remaining[(random or math.random)(1, #remaining)]
end

function Core.finishChoice(state, key)
    state.served = state.served or {}
    state.served[key] = true
    for i = #(state.remaining or {}), 1, -1 do if state.remaining[i] == key then table.remove(state.remaining, i) end end
end

function Core.airRisk(point, rows, clearance)
    local risk, count = 0, 0
    for _, row in ipairs(rows) do
        local radius = math.max(clearance, (row.range or 3) + 3)
        local d = math.sqrt((point.x - row.x) ^ 2 + (point.z - row.z) ^ 2)
        if d < radius then risk, count = risk + (radius - d + 1) ^ 2, count + 1 end
    end
    return risk, count
end

function Core.airRoute(a, b, rows, clearance)
    local dx, dz = b.x - a.x, b.z - a.z
    local length = dx * dx + dz * dz
    for _, row in ipairs(rows) do
        local t = length > 0 and math.max(0, math.min(1, ((row.x - a.x) * dx + (row.z - a.z) * dz) / length)) or 0
        local radius = math.max(clearance, (row.range or 3) + 3)
        if (a.x + t * dx - row.x) ^ 2 + (a.z + t * dz - row.z) ^ 2 < radius ^ 2 then return false end
    end
    return true
end

function Core.escapeRoute(a, b, rows, clearance)
    local initial = Core.airRisk(a, rows, clearance)
    if initial == 0 then return Core.airRoute(a, b, rows, clearance) end
    if Core.airRisk(b, rows, clearance) >= initial then return false end
    for _, t in ipairs({0.2, 0.4, 0.6, 0.8}) do
        local risk = Core.airRisk({x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t}, rows, clearance)
        if risk > initial + 0.01 then return false end
    end
    return true
end

function Core.mapPixelDirection(x, y, width, height, fov)
    if width <= 0 or height <= 0 then return nil end
    if x < 0 or y < 0 or x > width or y > height then return nil end
    local tangent = math.tan(math.rad(fov) / 2)
    return (x / width * 2 - 1) * tangent * width / height, (1 - y / height * 2) * tangent, -1
end

function Core.hull(points)
    local p = {}
    for _, point in ipairs(points) do p[#p + 1] = {x = point.x, y = point.y, z = point.z} end
    table.sort(p, function(a, b) return a.x == b.x and a.z < b.z or a.x < b.x end)
    local unique = {}
    for _, point in ipairs(p) do
        local prev = unique[#unique]
        if not prev or prev.x ~= point.x or prev.z ~= point.z then unique[#unique + 1] = point end
    end
    if #unique < 3 then return {} end
    local lower, upper = {}, {}
    for _, point in ipairs(unique) do
        while #lower >= 2 and Core.cross(lower[#lower - 1], lower[#lower], point) <= 0 do table.remove(lower) end
        lower[#lower + 1] = point
    end
    for i = #unique, 1, -1 do
        local point = unique[i]
        while #upper >= 2 and Core.cross(upper[#upper - 1], upper[#upper], point) <= 0 do table.remove(upper) end
        upper[#upper + 1] = point
    end
    table.remove(lower) table.remove(upper)
    for _, point in ipairs(upper) do lower[#lower + 1] = point end
    return lower
end

function Core.clipPolygon(subject, boundary)
    local output = subject
    for i, a in ipairs(boundary) do
        local b, input = boundary[i % #boundary + 1], output
        output = {}
        for j, endPoint in ipairs(input) do
            local start = input[(j - 2) % #input + 1]
            local from, to = Core.cross(a, b, start), Core.cross(a, b, endPoint)
            local fromInside, toInside = from >= -0.0001, to >= -0.0001
            if fromInside ~= toInside then
                local t = from / (from - to)
                output[#output + 1] = {x = start.x + (endPoint.x - start.x) * t,
                    y = start.y + (endPoint.y - start.y) * t, z = start.z + (endPoint.z - start.z) * t}
            end
            if toInside then output[#output + 1] = endPoint end
        end
        if #output == 0 then break end
    end
    return output
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
        headAim = true, bossFirst = true, clearance = 14, moveMode = "Smooth", placeSpawnArea = false, fireInput = "Mobile", flyHeight = 14, orbitRadius = 16, flySpeed = 32}
    local file = storage.path("EXIS_ZombieRushSurvival_" .. player.UserId .. ".json")
    if type(readfile) == "function" then
        local ok, data = pcall(function() if storage.exists(file) then return Http:JSONDecode(storage.read(file)) end end)
        if ok and type(data) == "table" and data.version == 1 then
            for key, value in pairs(data) do if type(value) == type(cfg[key]) then cfg[key] = value end end
        end
    end
    for key, limits in pairs({maxDefenses = {1, 48}, reserveCash = {0, 1e12}, flyHeight = {5, 50},
        orbitRadius = {6, 90}, flySpeed = {8, 100}, clearance = {8, 60}}) do
        local value = cfg[key]
        cfg[key] = Core.finite(value) and math.clamp(value, limits[1], limits[2]) or limits[1]
    end
    function app.save()
        if type(writefile) == "function" then
            local ok, err = pcall(function() storage.write(file, Http:JSONEncode(cfg)) end)
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
        return app.alive and cfg.enabled and app.root() ~= nil
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
    function app.upgradeCandidate(name)
        local upgrades = app.module(modules, "PlayerUpgradeDefinitions")
        if not upgrades then return nil end
        local types = {health = "Health", gun = upgrades.WeaponTierUpgradeTypeName, melee = upgrades.MeleeUpgradeTypeName}
        local kind = types[name]
        if not cfg[name] or not kind or not upgrades.Types[kind] then return nil end
        local level = upgrades.GetPlayerLevel(player, kind)
        if upgrades.IsAtMaxLevel(kind, level) then return nil end
        local round = RS:FindFirstChild("RoundInfo")
        local currency, price = upgrades.GetPrice(kind, level, {Player = player, CurrentLevel = level,
            Difficulty = app.value(round and round:FindFirstChild("Difficulty"), "Regular")})
        if app.afford(currency, price) and os.clock() >= (app.next["upgrade:" .. name] or 0) then return kind end
    end
    function app.upgradeTick(preferred)
        local ready = {}
        for _, name in ipairs(preferred and {preferred} or {"health", "gun", "melee"}) do
            if app.upgradeCandidate(name) then ready[#ready + 1] = name end
        end
        app.upgradeMix = app.upgradeMix or {}
        local name = preferred and ready[1] or Core.fairChoice(app.upgradeMix, ready)
        if not name then return false end
        local kind = app.upgradeCandidate(name)
        if not kind then return false end
        app.invoke("upgrade:" .. name, app.find(RS, "Events", "Actions", "PurchaseUpgrade"), kind)
        Core.finishChoice(app.upgradeMix, name)
        return true
    end
    function app.turretEstablished()
        local folder = workspace:FindFirstChild("Deployables")
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            local name = model:GetAttribute("TypeName")
            local info = name and defs.Types[name]
            if model:GetAttribute("OwnerUserId") == player.UserId and model:GetAttribute("Destroyed") ~= true
                and (model:GetAttribute("Health") or 1) > 0 and info and Core.role(name, info) == "turret" then return true end
        end
        for _, pending in pairs(app.pendingPlacements or {}) do
            if os.clock() < pending.expires and pending.slot.role == "turret" then return true end
        end
        return false
    end
    function app.matchTick()
        local _, human = app.root()
        if not human then return end
        -- Survival remains urgent; ordinary spending uses a randomized fair cycle.
        if human.Health / human.MaxHealth < 0.5 and app.upgradeCandidate("health") then app.upgradeTick("health") return end
        local boss = cfg.fight and cfg.bossFirst and app.target and app.target.boss
        if cfg.autoPlace and not boss and not app.turretEstablished() then
            local first = app.placementTask and app.placementTask.slot.role == "turret" and app.placementTask
                or app.getPlacement("turret", true)
            if first then
                if not first.affordable then app.note("economy", "SAVING FOR FIRST TURRET") app.buildGoal = nil return end
                app.placementTask = first
                local result = app.placeTick()
                if result ~= nil then app.placementTask = nil end
                return
            end
        end
        if app.placementTask and not boss then
            local result = app.placeTick()
            if result == nil then return end -- Keep a moving placement until it completes.
            if app.matchMix and app.placementKey then Core.finishChoice(app.matchMix, app.placementKey) end
            app.placementTask, app.placementKey = nil, nil
        end
        local keys, choices = {}, {}
        for _, name in ipairs({"health", "gun", "melee"}) do
            if app.upgradeCandidate(name) then keys[#keys + 1] = "upgrade:" .. name end
        end
        if cfg.autoPlace and not boss then
            local seen = {}
            for _, slot in ipairs(app.layout()) do
                if not seen[slot.name] then
                    seen[slot.name] = true
                    local candidate = app.getPlacement(slot.name)
                    if candidate then
                        local key = "place:" .. slot.name
                        keys[#keys + 1], choices[key] = key, candidate
                    end
                end
            end
        end
        app.matchMix = app.matchMix or {}
        local key = Core.fairChoice(app.matchMix, keys)
        if not key then app.buildGoal = nil return end
        if choices[key] then
            app.placementTask, app.placementKey = choices[key], key
            local result = app.placeTick()
            if result == nil then return end
            app.placementTask, app.placementKey = nil, nil
        else app.upgradeTick(key:sub(9)) end
        Core.finishChoice(app.matchMix, key)
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
        local geometry = workspace:FindFirstChild("MapGeometry")
        if geometry then result[#result + 1] = geometry end
        local map = workspace:FindFirstChild("Map")
        for _, name in ipairs({"Map", "Background"}) do
            local folder = map and map:FindFirstChild(name)
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
    function app.stopMapView()
        local state = app.mapView
        if not state then return end
        app.mapView = nil
        UIS.MouseBehavior, UIS.MouseIconEnabled = state.mouseBehavior, state.mouseIcon
        if state.world then state.world:Destroy() end
        if state.camera then state.camera:Destroy() end
        if app.viewport then app.viewport.CurrentCamera = nil end
    end
    function app.mapLayer(layer)
        local state = app.mapView
        if not state then return false end
        local floors = {}
        for _, part in ipairs(state.parts) do
            if part.Parent then
                local top = part.CFrame:PointToWorldSpace(Vector3.new(0, part.Size.Y / 2, 0))
                local onLayer = math.abs(top.Y - layer) <= 3.1 and part.CFrame.UpVector.Y >= 0.65
                part.LocalTransparencyModifier = state.cutaway and not onLayer and 1 or (state.original[part] or 0)
                if onLayer then floors[#floors + 1] = part end
            end
        end
        if #floors == 0 then return false end
        state.layer, state.floors = layer, floors
        return true
    end
    function app.cloneMapPart(source)
        local changed = {}
        local all = {source}
        for _, child in ipairs(source:GetDescendants()) do all[#all + 1] = child end
        for _, node in ipairs(all) do if not node.Archivable then changed[#changed + 1] = node node.Archivable = true end end
        local ok, clone = pcall(source.Clone, source)
        for _, node in ipairs(changed) do if node.Parent then node.Archivable = false end end
        if not ok or not clone then return nil end
        for _, node in ipairs(clone:GetDescendants()) do
            if node:IsA("BaseScript") or node:IsA("ModuleScript") or node:IsA("BasePart")
                or node:IsA("JointInstance") or node:IsA("Constraint") then node:Destroy() end
        end
        clone.Anchored, clone.CanCollide, clone.CanTouch, clone.CanQuery = true, false, false, true
        clone.CFrame = source.CFrame
        clone.LocalTransparencyModifier = source.LocalTransparencyModifier
        return clone
    end
    function app.startMapView(layer)
        app.stopMapView()
        if not app.viewport then return false end
        local world = Instance.new("WorldModel")
        world.Name, world.Parent = "EXIS_MAP_REPLICA", app.viewport
        local camera = Instance.new("Camera")
        camera.FieldOfView, camera.Parent = 50, app.viewport
        app.viewport.CurrentCamera = camera
        local state = {world = world, camera = camera, parts = {}, sources = {}, original = {}, floors = {}, map = app.mapId,
            layer = layer, zoom = 1, panX = 0, panZ = 0, cutaway = false, loading = true,
            mouseBehavior = UIS.MouseBehavior, mouseIcon = UIS.MouseIconEnabled, count = 0, total = 0, failed = 0}
        app.mapView = state
        local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
        local originals, seen = {}, {}
        for _, folder in ipairs(app.mapFilters()) do
            for _, source in ipairs(folder:GetDescendants()) do
                if source:IsA("BasePart") and not seen[source] then
                    seen[source] = true originals[#originals + 1] = source
                    if source.Transparency < 1 then
                        local p = source.Position
                        minX, maxX = math.min(minX, p.X - source.Size.X / 2), math.max(maxX, p.X + source.Size.X / 2)
                        minZ, maxZ = math.min(minZ, p.Z - source.Size.Z / 2), math.max(maxZ, p.Z + source.Size.Z / 2)
                    end
                end
            end
        end
        local nav = app.navigation()
        if #nav.hull >= 3 then
            minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
            for _, p in ipairs(nav.hull) do minX, maxX, minZ, maxZ = math.min(minX, p.x), math.max(maxX, p.x), math.min(minZ, p.z), math.max(maxZ, p.z) end
        end
        if minX == math.huge then app.stopMapView() app.note("area", "MAP GEOMETRY NOT LOADED") return false end
        state.bounds = {minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ}
        state.center, state.total = Vector3.new((minX + maxX) / 2, layer, (minZ + maxZ) / 2), #originals
        -- Bounded clone batches keep the live fight loop running during replica loading.
        task.spawn(function()
            for index, source in ipairs(originals) do
                if not app.alive or app.mapView ~= state then return end
                if source.Parent then
                    local clone = app.cloneMapPart(source)
                    if clone then
                        clone.Parent = world
                        state.parts[#state.parts + 1], state.sources[clone] = clone, source
                        state.original[clone] = source.LocalTransparencyModifier
                    else state.failed = state.failed + 1 end
                end
                state.count = index
                if index % 24 == 0 then task.wait() end
            end
            if app.mapView ~= state then return end
            state.loading = false
            if state.failed > 0 then app.note("replica", "COPY FAILED FOR " .. state.failed .. " MAP PARTS") end
            if not app.mapLayer(state.layer) then app.editorMessage = "CHOOSE A FLOOR LAYER" end
        end)
        return true
    end
    function app.projectMapPoint(point)
        local state, viewport = app.mapView, app.viewport
        if not state or not viewport or not state.camera then return nil end
        local p = state.camera.CFrame:PointToObjectSpace(point)
        if p.Z >= -0.01 then return nil end
        local size, tangent = viewport.AbsoluteSize, math.tan(math.rad(state.camera.FieldOfView) / 2)
        if size.X <= 0 or size.Y <= 0 then return nil end
        return Vector2.new(size.X / 2 + p.X / -p.Z * size.Y / (2 * tangent),
            size.Y / 2 - p.Y / -p.Z * size.Y / (2 * tangent))
    end
    function app.renderMapView()
        local state, viewport = app.mapView, app.viewport
        if not state or not app.editing or not viewport then return end
        local size = viewport.AbsoluteSize
        state.height = math.clamp(Core.mapViewHeight(state.bounds, size.X, size.Y, 50) * state.zoom, 8, 20000)
        local center = state.center + Vector3.new(state.panX, 0, state.panZ)
        state.camera.CFrame = CFrame.lookAt(center + Vector3.new(0, state.height, 0), center, Vector3.new(0, 0, -1))
        UIS.MouseBehavior, UIS.MouseIconEnabled = Enum.MouseBehavior.Default, true
        if app.refreshMapDots then app.refreshMapDots(state.camera) end
    end
    function app.mapViewRay(screen)
        local state, viewport = app.mapView, app.viewport
        if not state or state.loading or #state.floors == 0 or not viewport then return nil end
        local p, size = viewport.AbsolutePosition, viewport.AbsoluteSize
        local x, y, z = Core.mapPixelDirection(screen.X - p.X, screen.Y - p.Y, size.X, size.Y, state.camera.FieldOfView)
        if not x then return nil end
        local direction = state.camera.CFrame:VectorToWorldSpace(Vector3.new(x, y, z)).Unit
        local params = RaycastParams.new()
        params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Include, state.floors
        return state.world:Raycast(state.camera.CFrame.Position, direction * (state.height * 3 + 200), params)
    end
    function app.navigation()
        local cached = app.navCache
        if cached and cached.map == app.mapId and os.clock() < cached.untilTime then return cached end
        local spawns = app.find(workspace, "Map", "ZombieTestMap", "ZombieSpawns")
        local rows, points = {}, {}
        for _, part in ipairs(spawns and spawns:GetChildren() or {}) do
            if part:IsA("BasePart") then
                local p = part.Position
                rows[#rows + 1] = {point = p, source = part}
                points[#points + 1] = {x = p.X, y = p.Y, z = p.Z}
            end
        end
        local spawn = app.find(workspace, "Map", "ZombieTestMap", "PlayerSpawn")
        if spawn and spawn:IsA("BasePart") then
            points[#points + 1] = {x = spawn.Position.X, y = spawn.Position.Y, z = spawn.Position.Z}
        end
        local filters = app.mapFilters()
        local map = workspace:FindFirstChild("Map")
        if map then
            local preload, generated = map:FindFirstChild("PreloadPaths"), map:FindFirstChild("Zombie_GeneratedPaths")
            if preload then filters[#filters + 1] = preload end
            if generated then filters[#filters + 1] = generated end
        end
        local borders = app.find(workspace, "WeaponBlacklist", "Zombie_BorderWalls")
        if borders then filters[#filters + 1] = borders end
        cached = {map = app.mapId, spawns = rows, hull = Core.hull(points), filters = filters, untilTime = os.clock() + 5}
        app.navCache = cached
        return cached
    end
    function app.inPlayableMap(point)
        local nav = app.navigation()
        return #nav.hull >= 3 and Core.inside({x = point.X, z = point.Z}, nav.hull)
    end
    function app.travelHit(origin, direction)
        if direction.Magnitude < 0.01 then return nil end
        local root = app.root()
        if not root then return true end
        local params = RaycastParams.new()
        params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Include, app.navigation().filters
        params.RespectCanCollide, params.CollisionGroup = true, root.CollisionGroup
        -- Sweep a character-sized volume, not just a ray through its center.
        return workspace:Blockcast(CFrame.new(origin), Vector3.new(3, 4, 3), direction, params)
    end
    function app.placementRegion()
        if not cfg.placeSpawnArea then return app.region() end
        local nav, root = app.navigation(), app.root()
        if #nav.hull < 3 or not root or #nav.spawns == 0 then return {points = {}} end
        if not app.spawnAnchor or app.spawnAnchorMap ~= app.mapId then
            local best, distance
            for _, row in ipairs(nav.spawns) do
                local d = (row.point - root.Position).Magnitude
                if app.airRisk(row.point) > 0 then d = d + 10000 end
                if not distance or d < distance then best, distance = row.point, d end
            end
            local alternatives = {}
            for _, row in ipairs(nav.spawns) do alternatives[#alternatives + 1] = row.point end
            table.sort(alternatives, function(a, b) return (a - root.Position).Magnitude < (b - root.Position).Magnitude end)
            best = alternatives[((app.spawnAnchorTurn or 0) % #alternatives) + 1] or best
            local hit = app.raycast(best + Vector3.new(0, 5, 0), Vector3.new(0, -100, 0), app.mapFilters())
            if hit and hit.Normal.Y >= 0.65 then best = hit.Position end
            app.spawnAnchor, app.spawnAnchorMap = best, app.mapId
        end
        local p, radius = app.spawnAnchor, 25
        local square = {{x = p.X - radius, y = p.Y, z = p.Z - radius}, {x = p.X + radius, y = p.Y, z = p.Z - radius},
            {x = p.X + radius, y = p.Y, z = p.Z + radius}, {x = p.X - radius, y = p.Y, z = p.Z + radius}}
        local clipped = Core.clipPolygon(square, nav.hull)
        if #clipped > 24 then
            local simpler = {}
            for i = 1, 24 do simpler[i] = clipped[math.floor((i - 1) * #clipped / 24) + 1] end
            clipped = simpler
        end
        return {points = clipped, anywhere = true}
    end
    function app.routeHop(goal)
        local root = app.root()
        if not root or not app.inPlayableMap(goal) then return nil end
        if app.airRoute(root.Position, goal) and not app.travelHit(root.Position, goal - root.Position) then return goal end
        local cached = app.routeCache
        if cached and os.clock() < cached.untilTime and (cached.goal - goal).Magnitude < 1
            and (cached.from - root.Position).Magnitude < 3 then
            if not cached.hop then return nil end
            if app.airRoute(root.Position, cached.hop) and not app.travelHit(root.Position, cached.hop - root.Position) then return cached.hop end
        end
        local cache = {goal = goal, from = root.Position, untilTime = os.clock() + 0.18}
        app.routeCache = cache
        local candidates = {}
        for _, row in ipairs(app.navigation().spawns) do
            local p = row.point
            local cost = (p - root.Position).Magnitude + (p - goal).Magnitude
            candidates[#candidates + 1] = {point = p, cost = cost}
        end
        table.sort(candidates, function(a, b) return a.cost < b.cost end)
        for i = 1, math.min(24, #candidates) do
            local point = candidates[i].point
            if app.airRisk(point) == 0 then
                local hop = app.flightPoint(point)
                if hop and (hop - root.Position).Magnitude > 3 and app.airRoute(root.Position, hop)
                    and app.airRoute(hop, goal) and not app.travelHit(root.Position, hop - root.Position)
                    and not app.travelHit(hop, goal - hop) then cache.hop = hop return hop end
            end
        end
        return nil
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
        local region = app.placementRegion()
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
        local region = app.placementRegion()
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
        local plan, reason, reserve = Core.plan(app.placementRegion().points or {}, specs, cfg.maxDefenses, app.defenseBoxes())
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
        local poly, floorY = app.placementRegion().points or {}, 0
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
    function app.getPlacement(preferred, allowUnfunded)
        if os.clock() < (app.next.place or 0) then return nil end
        if app.mode ~= "MATCH" or not cfg.autoPlace or app.editing or app.mapId == "Unknown" or not app.className then return nil end
        local client = app.module(app.find(player, "PlayerScripts", "Client"), "DeployableSystem")
        if not client then return nil end
        local folder, ownedCount = workspace:FindFirstChild("Deployables"), 0
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            if model:GetAttribute("OwnerUserId") == player.UserId and model:GetAttribute("Destroyed") ~= true then ownedCount = ownedCount + 1 end
        end
        if ownedCount >= cfg.maxDefenses then return nil end
        local choices = {}
        for index, slot in ipairs(app.layout()) do
            local key = app.planKey .. ":" .. index
            if (not preferred or slot.name == preferred or slot.role == preferred)
                and os.clock() >= (app.rejected[key] or 0) and not app.occupied(slot) then
                local currency, price = client.GetCurrentPrice(slot.name)
                local affordable = app.afford(currency, price)
                if affordable or allowUnfunded then
                    local hit = app.ground(slot.x, slot.z, slot.y)
                    if hit and app.inPlayableMap(hit.Position) and app.airRisk(hit.Position) == 0 then
                        choices[#choices + 1] = {key = key, slot = slot, point = hit.Position, class = app.className,
                            map = app.mapId, revision = app.revision, affordable = affordable}
                    elseif not hit then app.rejected[key] = os.clock() + 8 end
                end
            end
        end
        if #choices == 0 then
            if cfg.placeSpawnArea and not app.placementTask and os.clock() >= (app.next.spawnArea or 0) then
                app.next.spawnArea = os.clock() + 5
                app.spawnAnchorTurn = (app.spawnAnchorTurn or 0) + 1
                app.spawnAnchor, app.planKey = nil, nil
            end
            return nil
        end
        return choices[math.random(1, #choices)]
    end
    function app.placeTick()
        if app.target and app.target.boss and cfg.bossFirst and cfg.fight then app.buildGoal = nil return end
        if app.editing then app.buildGoal = nil return false end
        local candidate = app.placementTask or app.getPlacement()
        if not candidate then app.buildGoal = nil return false end
        if candidate.class ~= app.className or candidate.map ~= app.mapId or candidate.revision ~= app.revision then
            app.placementTask, app.buildGoal = nil, nil return false
        end
        local root, human = app.root()
        if not root then return false end
        if app.airRisk(root.Position) > 0 or app.airRisk(candidate.point) > 0 then app.buildGoal = nil return false end
        local lift = human.HipHeight + root.Size.Y / 2
        local outward = Vector3.new(root.Position.X - candidate.point.X, 0, root.Position.Z - candidate.point.Z)
        if outward.Magnitude < 0.1 then outward = Vector3.new(1, 0, 0) end
        local side = candidate.point + outward.Unit * math.min(8, math.max(candidate.slot.w, candidate.slot.d) / 2 + 3)
        local sideHit = app.ground(side.X, side.Z, candidate.point.Y)
        local stand = (sideHit and sideHit.Position or candidate.point) + Vector3.new(0, lift, 0)
        if app.airRisk(stand) > 0 or not app.inPlayableMap(stand) then
            local safe
            for i = 0, 7 do
                local angle = i * math.pi / 4
                local probe = candidate.point + Vector3.new(math.cos(angle) * 7, 0, math.sin(angle) * 7)
                local floor = app.ground(probe.X, probe.Z, candidate.point.Y)
                if floor and app.airRisk(floor.Position) == 0 and app.inPlayableMap(floor.Position) then safe = floor.Position + Vector3.new(0, lift, 0) break end
            end
            if not safe then return false end
            stand = safe
        end
        local delta = stand - root.Position
        if delta.Magnitude > 10 or math.abs(root.Position.Y - stand.Y) > 2 then
            app.buildGoal = stand
            app.note("defense", "MOVING INTO PLACEMENT RANGE")
            return nil
        end
        app.buildGoal = nil
        -- Re-check after movement; selection, class, occupancy and cash can change.
        if candidate.class ~= app.className or candidate.map ~= app.mapId or candidate.revision ~= app.revision
            or not cfg.autoPlace or not app.active() or app.occupied(candidate.slot) then return false end
        local spec = candidate.slot.spec
        local region = app.placementRegion()
        if not Core.fits(candidate.slot, candidate.slot.w + 0.1, candidate.slot.d + 0.1, region.points or {}) then return false end
        local client = app.module(app.find(player, "PlayerScripts", "Client"), "DeployableSystem")
        if not client then return false end
        local currency, price = client.GetCurrentPrice(candidate.slot.name)
        if not app.afford(currency, price) then return false end
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
        return result and result.ok == true or false
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
        local best, score
        for _, row in ipairs(app.enemyRows()) do
            if row.model.Parent then
                local rank = Core.targetScore((row.point - root.Position).Magnitude, row.boss, cfg.bossFirst,
                    app.target and app.target.model == row.model)
                if not score or rank > score then best, score = {model = row.model, point = row.point, boss = row.boss}, rank end
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
    function app.ensureFlight(root, human)
        if app.flight and app.flight.root == root then return end
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
    function app.move(goal, dt)
        local root, human = app.root()
        if not root or not goal then
            if app.flight then app.flight.velocity.VectorVelocity = Vector3.new(0, 0, 0) end
            return
        end
        local hop = app.routeHop(goal)
        if not hop then
            app.routeBlockedSince = app.routeBlockedSince or os.clock()
            if app.placementTask and os.clock() - app.routeBlockedSince >= 1 then
                app.rejected[app.placementTask.key] = os.clock() + 8
                if app.matchMix and app.placementKey then Core.finishChoice(app.matchMix, app.placementKey) end
                app.placementTask, app.placementKey, app.buildGoal = nil, nil, nil
            end
            if app.flight then app.flight.velocity.VectorVelocity = Vector3.new(0, 0, 0) end
            app.airGoal = nil
            return
        end
        app.routeBlockedSince = nil
        goal = hop
        if cfg.moveMode == "Teleport" and cfg.fly then
            app.ensureFlight(root, human)
            app.flight.velocity.VectorVelocity = Vector3.new(0, 0, 0)
            if os.clock() >= (app.next.teleport or 0) then
                app.next.teleport = os.clock() + 0.15
                root.CFrame = CFrame.new(goal) * root.CFrame.Rotation
                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end
            return
        end
        if not cfg.fly then app.stopFlight() human:MoveTo(goal) return end
        app.ensureFlight(root, human)
        local delta = goal - root.Position
        local direction = delta.Magnitude > 0.2 and delta.Unit * math.min(cfg.flySpeed, delta.Magnitude * 4) or Vector3.new(0, 0, 0)
        if direction.Magnitude > 0 then
            local probe = direction.Unit * math.min(5, delta.Magnitude)
            local hit = app.travelHit(root.Position, probe)
            if hit then
                local slide = direction - hit.Normal * math.min(0, direction:Dot(hit.Normal))
                direction = slide.Magnitude > 0.5 and slide.Unit * math.min(cfg.flySpeed, slide.Magnitude) or Vector3.new(0, 0, 0)
            end
        end
        local rate = math.min(1, dt * 12)
        local velocity = app.flight.velocity.VectorVelocity:Lerp(direction, rate)
        local probe = root.Position + velocity * math.max(dt, 0.12)
        if not app.airRoute(root.Position, probe) or app.travelHit(root.Position, probe - root.Position) then
            velocity = Vector3.new(0, 0, 0)
            app.airGoal = nil
        end
        app.flight.velocity.VectorVelocity = velocity
    end
    function app.enemyRows()
        if app.enemyCache and os.clock() < app.enemyCache.untilTime then return app.enemyCache.rows end
        local folder, rows = workspace:FindFirstChild("Zombie_ClientVisuals"), {}
        local types = app.module(shared:FindFirstChild("Zombies"), "ZombieTypes")
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            if model:IsA("Model") and model:GetAttribute("ZombieId") ~= nil then
                local point = app.head(model)
                local human = model:FindFirstChildOfClass("Humanoid")
                if point and (not human or human.Health > 0) then
                    local info = types and types.GetById(model:GetAttribute("ZombieTypeId"))
                    rows[#rows + 1] = {model = model, point = point, x = point.X, z = point.Z,
                        range = info and tonumber(info.attackRange) or 3, boss = app.isBoss(model)}
                end
            end
        end
        app.enemyCache = {rows = rows, untilTime = os.clock() + 0.08}
        return rows
    end
    function app.airRisk(point)
        return Core.airRisk({x = point.X, z = point.Z}, app.enemyRows(), cfg.clearance)
    end
    function app.airRoute(a, b)
        local from, to = {x = a.X, z = a.Z}, {x = b.X, z = b.Z}
        return Core.escapeRoute(from, to, app.enemyRows(), cfg.clearance)
    end
    function app.flightPoint(point)
        if not app.inPlayableMap(point) then return nil end
        local hit = app.raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -256, 0), app.mapFilters())
        if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.6 then return nil end
        local root, human = app.root()
        if not root then return nil end
        local lift = human.HipHeight + root.Size.Y / 2
        local base = hit.Position + Vector3.new(0, lift, 0)
        local ceiling = app.raycast(base, Vector3.new(0, cfg.flyHeight + 3, 0), app.mapFilters())
        local y = hit.Position.Y + cfg.flyHeight
        if ceiling then y = math.min(y, ceiling.Position.Y - lift - 0.5) end
        if y < base.Y then return nil end
        return Vector3.new(point.X, y, point.Z)
    end
    function app.safeAirGoal(target)
        local root = app.root()
        if not root then return nil end
        local anchor = target and app.head(target.model) or root.Position
        if not anchor then return nil end
        local unsafe = app.airRisk(root.Position) > 0
        local angle = os.clock() * 0.3 * (app.orbitDirection or 1)
        local best, bestScore
        local radius = math.max(cfg.orbitRadius, cfg.clearance + 4)
        for _, row in ipairs(app.enemyRows()) do if target and row.model == target.model then radius = math.max(radius, (row.range or 3) + 7) end end
        local candidates = {}
        for _, distance in ipairs({radius, radius + 18, radius + 38}) do
            for i = 0, 11 do
                local a = angle + i * math.pi / 6
                local point = anchor + Vector3.new(math.cos(a) * distance, 0, math.sin(a) * distance)
                if app.inPlayableMap(point) and app.airRisk(point) == 0 then
                    local cost = (point - root.Position).Magnitude
                    if os.clock() < (app.damageEvadeUntil or 0) and cost < 12 then cost = cost + 100 end
                    candidates[#candidates + 1] = {point = point, cost = cost + distance * 0.2}
                end
            end
        end
        table.sort(candidates, function(a, b) return a.cost < b.cost end)
        for i = 1, math.min(8, #candidates) do
            local goal = app.flightPoint(candidates[i].point)
            if goal and app.routeHop(goal) then
                if not target or not app.raycast(goal, anchor - goal, app.mapFilters()) then return goal end
                if not best then best = goal end
            end
        end
        if best then return best end
        if unsafe then
            -- Short lower-exposure steps let a surrounded player leave the swarm
            -- without treating altitude as protection or crossing another crowd.
            local risk = app.airRisk(root.Position)
            for i = 0, 15 do
                local a = i * math.pi / 8
                local goal = root.Position + Vector3.new(math.cos(a) * 10, 0, math.sin(a) * 10)
                local nextRisk = app.airRisk(goal)
                if nextRisk < risk and app.airRoute(root.Position, goal)
                    and not app.raycast(root.Position, goal - root.Position, app.mapFilters()) then
                    local supported = app.flightPoint(goal)
                    if supported and (not bestScore or -nextRisk > bestScore) then best, bestScore = goal, -nextRisk end
                end
            end
        end
        if not best then app.note("flight", "NO CLEAR FLIGHT ROUTE; RECHECKING") end
        return best
    end
    function app.orbitGoal(target)
        local cached = app.airGoal
        local root = app.root()
        if cached and root and os.clock() < cached.untilTime and app.airRisk(cached.point) == 0
            and app.airRoute(root.Position, cached.point) then return cached.point end
        local goal = app.safeAirGoal(target)
        app.airGoal = goal and {point = goal, untilTime = os.clock() + 0.25} or nil
        return goal
    end
    function app.combatTick(dt)
        if app.mode ~= "MATCH" or not app.active() then
            app.releaseFire() app.stopFlight() app.buildGoal = nil return
        end
        if not cfg.fight and not cfg.autoPlace then app.releaseFire() app.stopFlight() app.buildGoal = nil return end
        local target = cfg.fight and app.target or nil
        if target and not target.model.Parent then target = nil end
        local build = cfg.autoPlace and not app.editing and app.buildGoal
        local root, human = app.root()
        if human and app.observedHealth and human.Health < app.observedHealth then
            app.airGoal, app.damageEvadeUntil = nil, os.clock() + 1.2
            app.orbitDirection = -(app.orbitDirection or 1)
        end
        app.observedHealth = human and human.Health
        local danger = root and (app.airRisk(root.Position) > 0 or os.clock() < (app.damageEvadeUntil or 0))
        if danger and cfg.fly and (cfg.fight or cfg.autoPlace) then
            build = nil
            app.move(app.orbitGoal(target), dt)
            app.note("flight", "RELOCATING TO CLEAR MAP SPACE")
        end
        if target and target.boss and cfg.bossFirst then build = nil end
        if build then app.releaseFire() app.move(build, dt) return end
        if not target then
            app.releaseFire()
            if not danger then app.stopFlight() end
            return
        end
        local tool, info = app.weapon()
        if cfg.fly and not danger then app.move(app.orbitGoal(target), dt) elseif not cfg.fly then app.stopFlight() end
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
        if not app.editing and app.buildGoal and not (app.target.boss and cfg.bossFirst) then return end
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
    ui.draggable(icon, icon, function()
        if app.editing and app.closeMapEditor then app.closeMapEditor(false)
        else frame.Visible = not frame.Visible end
    end)
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
    ui.number(flight, "FLY SPEED", "flySpeed", 8, 100)
    ui.number(flight, "ZOMBIE CLEARANCE", "clearance", 8, 60)
    ui.button(flight, "SMOOTH FLIGHT", function() cfg.moveMode = "Smooth" app.changed() end)
    ui.button(flight, "CHECKED TELEPORT", function() cfg.moveMode = "Teleport" app.changed() end)
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
    ui.textLabel(upgrades, "Turret first, then mixed placements and upgrades. Low HP prioritizes health.", 30)
    local upgradeState = ui.textLabel(upgradesPage, "", 50)
    function ui.buildDefenses()
        for _, child in ipairs(defensePage:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        local group = ui.group(defensePage, "AUTO DEFENSE")
        ui.toggle(group, "AUTO PLACE CURRENT CLASS", cfg, "autoPlace")
        ui.toggle(group, "USE ZOMBIE-SPAWN MAP AREA", cfg, "placeSpawnArea")
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
    local area = ui.group(areaPage, "TOP VIEW MAP SELECTION")
    ui.textLabel(area, "Open the map, tap your corners, then CONNECT. First edge = front.", 32)
    local areaLabel = ui.textLabel(area, "NO AREA SELECTED", 28)
    local editor = ui.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
        Size = UDim2.fromOffset(370, 137), BackgroundColor3 = Color3.fromRGB(12, 23, 38), Visible = false,
        ZIndex = 10}, gui)
    ui.round(editor)
    ui.stroke(editor, ui.blue)
    local editorText = ui.textLabel(editor, "TOP VIEW · TAP CORNERS", 27)
    editorText.TextSize = 10
    local mapHolder = ui.new("Frame", {Position = UDim2.fromOffset(8, 150), Size = UDim2.new(1, -16, 1, -158),
        BackgroundColor3 = Color3.fromRGB(9, 17, 29), Visible = false, ClipsDescendants = true, ZIndex = 4}, gui)
    ui.round(mapHolder) ui.stroke(mapHolder, ui.blue)
    app.viewport = ui.new("ViewportFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Ambient = Color3.fromRGB(180, 180, 180), LightColor = Color3.fromRGB(255, 250, 240),
        LightDirection = Vector3.new(-1, -2, -1), Active = true, ZIndex = 4}, mapHolder)
    local dotOverlay = ui.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Active = false, Visible = false, ZIndex = 5}, mapHolder)
    local dots, lines = {}, {}
    function app.refreshMapDots(camera)
        local points = app.draft or {}
        for i = 1, 24 do
            local dot, line = dots[i], lines[i]
            if not dot then
                dot = ui.new("TextLabel", {Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0.5, 0.5),
                    Text = tostring(i), TextSize = 10, Font = Enum.Font.GothamBold, BackgroundColor3 = ui.blue,
                    TextColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, ZIndex = 7, Active = false}, dotOverlay)
                ui.round(dot, 10)
                line = ui.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
                    BackgroundColor3 = ui.blue, ZIndex = 6, Active = false}, dotOverlay)
                dots[i], lines[i] = dot, line
            end
            local point = points[i]
            dot.Visible, line.Visible = false, false
            if point then
                local a = app.projectMapPoint(Vector3.new(point.x, point.y, point.z))
                dot.Position, dot.Visible = UDim2.fromOffset(a and a.X or 0, a and a.Y or 0), a ~= nil
                dot.BackgroundColor3 = i == 1 and Color3.fromRGB(255, 190, 75) or ui.blue
                local nextPoint = points[i + 1]
                local b = nextPoint and app.projectMapPoint(Vector3.new(nextPoint.x, nextPoint.y, nextPoint.z))
                if a and b then
                    local delta = Vector2.new(b.X - a.X, b.Y - a.Y)
                    line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
                    line.Size = UDim2.fromOffset(delta.Magnitude, 2)
                    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                    line.BackgroundColor3 = i == 1 and Color3.fromRGB(255, 190, 75) or ui.blue
                    line.Visible = true
                end
            end
        end
    end
    function app.closeMapEditor(saved)
        app.stopMapView()
        app.editing, app.pickPart, app.draftSurface, app.clearSurface = false, false, nil, nil
        editor.Visible, dotOverlay.Visible, mapHolder.Visible, frame.Visible = false, false, false, true
        app.drawRegion(saved and app.draft or app.region().points or {}, true)
    end
    function app.commitArea()
        local ok, reason = Core.validPolygon(app.draft or {})
        if not ok then app.editorMessage = reason app.note("area", reason) return false end
        local previous = app.region()
        local surface = app.draftSurface or previous.surface
        if app.clearSurface then surface = nil end
        cfg.regions[app.mapId] = {points = app.draft, surface = surface}
        app.closeMapEditor(true)
        app.changed()
        return true
    end
    function app.openMapEditor(mode)
        if app.mode ~= "MATCH" or app.mapId == "Unknown" then app.note("area", "JOIN A LOADED MAP FIRST") return end
        local root, human = app.root()
        if not root then app.note("area", "WAIT UNTIL YOUR CHARACTER IS ALIVE") return end
        local saved = app.region().points or {}
        local layer = root.Position.Y - human.HipHeight - root.Size.Y / 2
        if #saved > 0 then layer = saved[1].y end
        if not app.startMapView(layer) then return end
        app.buildGoal = nil
        app.editing, app.pickPart, app.draftSurface, app.editorMessage = true, mode == "part", nil, nil
        app.draft, app.clearSurface = {}, mode == "new"
        if mode == "saved" then for _, point in ipairs(saved) do app.draft[#app.draft + 1] = {x = point.x, y = point.y, z = point.z} end end
        frame.Visible, editor.Visible, dotOverlay.Visible, mapHolder.Visible = false, true, true, true
        app.clearMarkers()
        app.renderMapView()
    end
    local function editorButton(text, x, width, y, callback)
        local button = ui.button(editor, text, callback)
        button.Size, button.Position = UDim2.new(width, -5, 0, 27), UDim2.new(x, 3, 0, y)
        button.TextSize, button.ZIndex = 10, 11
        return button
    end
    editorButton("UNDO", 0, 0.25, 30, function()
        if app.draft then table.remove(app.draft) end
        app.editorMessage = nil
    end)
    editorButton("CLEAR", 0.25, 0.25, 30, function() app.draft, app.editorMessage = {}, nil end)
    editorButton("CONNECT", 0.5, 0.25, 30, app.commitArea)
    editorButton("CANCEL", 0.75, 0.25, 30, function() app.closeMapEditor(false) end)
    local controls = {
        {"−", function(s) s.zoom = math.min(2.5, s.zoom * 1.25) end},
        {"+", function(s) s.zoom = math.max(0.03, s.zoom / 1.25) end},
        {"←", function(s) s.panX = s.panX - s.height * 0.12 end},
        {"→", function(s) s.panX = s.panX + s.height * 0.12 end},
        {"↑", function(s) s.panZ = s.panZ - s.height * 0.12 end},
        {"↓", function(s) s.panZ = s.panZ + s.height * 0.12 end},
        {"FIT", function(s) s.zoom, s.panX, s.panZ = 1, 0, 0 end},
    }
    for index, control in ipairs(controls) do
        editorButton(control[1], (index - 1) / 7, 1 / 7, 63, function()
            if app.mapView then control[2](app.mapView) end
        end)
    end
    editorButton("FLOOR −", 0, 0.25, 97, function()
        if app.mapView then
            local old = app.mapView.layer
            if not app.mapLayer(old - 6) then app.mapLayer(old) app.editorMessage = "NO LOWER FLOOR" end
        end
    end)
    editorButton("FLOOR +", 0.75, 0.25, 97, function()
        if app.mapView then
            local old = app.mapView.layer
            if not app.mapLayer(old + 6) then app.mapLayer(old) app.editorMessage = "NO HIGHER FLOOR" end
        end
    end)
    editorButton("FULL / CUTAWAY", 0.25, 0.5, 97, function()
        if app.mapView and not app.mapView.loading then
            app.mapView.cutaway = not app.mapView.cutaway
            app.mapLayer(app.mapView.layer)
        end
    end)
    ui.button(area, "OPEN TOP VIEW · NEW AREA", function() app.openMapEditor("new") end)
    ui.button(area, "OPEN TOP VIEW · EDIT SAVED AREA", function() app.openMapEditor("saved") end)
    ui.button(area, "OPEN TOP VIEW · PICK MAP PART", function() app.openMapEditor("part") end)
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
        if not app.editing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not app.mapView or app.mapView.loading then return end
        local screen = Vector2.new(input.Position.X, input.Position.Y)
        local at, size = app.viewport.AbsolutePosition, app.viewport.AbsoluteSize
        if screen.X < at.X or screen.Y < at.Y or screen.X > at.X + size.X or screen.Y > at.Y + size.Y then return end
        if #pg:GetGuiObjectsAtPosition(screen.X, screen.Y) > 0 then
            -- Only our editor blocks selection; the game's transparent full-screen HUD does not.
            for _, object in ipairs(pg:GetGuiObjectsAtPosition(screen.X, screen.Y)) do
                if object:IsDescendantOf(editor) or object == icon or (frame.Visible and object:IsDescendantOf(frame)) then return end
            end
        end
        if not app.pickPart and #app.draft >= 3 then
            local first = app.draft[1]
            local pixel = app.projectMapPoint(Vector3.new(first.x, first.y, first.z))
            if pixel and (pixel + app.viewport.AbsolutePosition - screen).Magnitude <= 14 then
                app.commitArea()
                return
            end
        end
        local hit = app.mapViewRay(screen)
        if not hit or not hit.Instance:IsA("BasePart") or hit.Normal.Y < 0.65 then app.note("area", "TAP A FLOOR SURFACE") return end
        app.editorMessage = nil
        if app.pickPart then
            local part = app.mapView.sources[hit.Instance]
            if not part or not part.Parent then return end
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
        if app.mapView then app.refreshMapDots(app.mapView.camera) end
    end)
    app.connect(UIS.InputEnded, function(input)
        if app.editing and app.held and input ~= app.held.token
            and input.UserInputType == Enum.UserInputType.MouseButton1 then app.releaseFire() end
    end)
    function app.stop()
        if not app.alive then return end
        app.alive = false
        app.save()
        app.releaseFire() app.stopFlight() app.stopMapView() app.clearMarkers()
        RunService:UnbindFromRenderStep("EXIS_ZOMBIE_AIM")
        RunService:UnbindFromRenderStep("EXIS_ZOMBIE_MAP")
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
    app.connect(player.CharacterRemoving, function()
        if app.editing then app.closeMapEditor(false) end
        app.releaseFire() app.stopFlight() app.buildGoal = nil
    end)
    RunService:BindToRenderStep("EXIS_ZOMBIE_MAP", Enum.RenderPriority.Camera.Value + 20, function()
        local ok, err = pcall(app.renderMapView)
        if not ok then
            app.note("area", err)
            if app.editing then app.closeMapEditor(false) end
        end
    end)
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
                    if app.mapView and app.mapView.map ~= app.mapId then app.closeMapEditor(false) end
                    app.planKey, app.target, app.buildGoal, app.surface, app.defenseCache = nil, nil, nil, nil, nil
                    app.rejected, app.pendingPlacements = {}, {}
                    app.enemyCache, app.airGoal, app.navCache, app.spawnAnchor = nil, nil, nil, nil
                    app.matchMix, app.placementTask = nil, nil
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
                        app.matchTick()
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
            editor.Size = UDim2.fromOffset(math.min(370, workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X - 20 or 370), 137)
            local view = app.mapView
            editorText.Text = view and view.loading and ("COPYING MAP " .. view.count .. "/" .. view.total .. " · " .. (cfg.fight and "FIGHT ON" or "FIGHT OFF"))
                or app.editorMessage or ("MAP REPLICA · DOTS " .. #(app.draft or {}) .. " · " .. (cfg.fight and "FIGHT ACTIVE" or "FIGHT OFF"))
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
