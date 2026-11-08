-- Session diagnostics: bounded live view, complete persisted chunks, no network logging.
local Diagnostics = {}
function Diagnostics.traceback(err)
    return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
end
function Diagnostics.level(message)
    local value = tostring(message):upper()
    for _, token in ipairs({"ERROR:", "FAILED", "REJECTED", "TIMED OUT", "UNAVAILABLE", "UNSUPPORTED"}) do
        if value:find(token, 1, true) then return "ERROR" end
    end
    for _, token in ipairs({"WAIT", "BLOCKED", "UNCONFIRMED", "NOT CONFIRMED", "NO SAFE", "NO REACHABLE", "DEFERRED", "BAG FULL", "AREA FULL", "STORAGE FULL", "MISSING"}) do
        if value:find(token, 1, true) then return "WAIT" end
    end
    return "INFO"
end
function Diagnostics.describe(value)
    if type(value) ~= "table" then return tostring(value) end
    local fields = {}
    for _, key in ipairs({"ok", "reason", "message", "enabled", "success"}) do
        if value[key] ~= nil then fields[#fields+1] = key .. "=" .. tostring(value[key]) end
    end
    return #fields > 0 and table.concat(fields, ", ") or "table response"
end
function Diagnostics.new(name, storage)
    local log = {name=name, storage=storage, started=os.clock(), recent={}, chunk={}, parts={}, latest={}, failures={},
        total=0, suppressed=0, discarded=0, serial=1, revision=0, savedRevision=-1, storageError=nil}
    log.session = os.date("!%Y%m%d_%H%M%S") .. "_" .. tostring(math.floor(os.clock()*1000))
    log.prefix = "diagnostic_" .. log.session
    function log:currentFile()
        return self.prefix .. "_" .. string.format("%06d", self.serial) .. ".log"
    end
    function log:flush()
        if self.savedRevision == self.revision then return true end
        if self.retryAt and os.clock() < self.retryAt then return false end
        local ok, err = pcall(self.storage.write, self:currentFile(), table.concat(self.chunk, "\n") .. "\n")
        if not ok then self.storageError=tostring(err) self.retryAt=os.clock()+3 return false end
        self.storageError=nil self.retryAt=nil self.savedRevision=self.revision
        return true
    end
    function log:record(key, message, level, force)
        key, message = tostring(key), tostring(message)
        level = level or Diagnostics.level(message)
        self.total = self.total + 1
        if level == "ERROR" then
            local failure=self.failures[key] or {count=0}
            failure.count, failure.reason, failure.at = failure.count+1, message, os.clock()-self.started
            self.failures[key]=failure
        end
        local previous = self.latest[key]
        if previous and previous.message == message and previous.level == level then
            previous.count = previous.count + 1
            if not force then self.suppressed=self.suppressed+1 return end
        else self.latest[key]={message=message, level=level, count=1} end
        if #self.chunk >= 200 and self:flush() then
            self.parts[#self.parts+1]=self:currentFile()
            self.serial=self.serial+1 self.chunk={} self.savedRevision=-1
        end
        -- File-less executors retain a bounded buffer and explicitly report any loss.
        if #self.chunk >= 2000 then table.remove(self.chunk,1) self.discarded=self.discarded+1 end
        local line=string.format("[%s +%.2fs] [%s] [%s] %s",os.date("!%Y-%m-%dT%H:%M:%SZ"),os.clock()-self.started,level,key,message)
        self.chunk[#self.chunk+1]=line self.recent[#self.recent+1]=line self.revision=self.revision+1
        if #self.recent>80 then table.remove(self.recent,1) end
    end
    function log:summary(short)
        local lines={"SESSION "..self.session,"EVENTS "..self.total.." | UNCHANGED REPEATS "..self.suppressed}
        local keys={};for key in pairs(self.failures)do keys[#keys+1]=key end;table.sort(keys)
        lines[#lines+1]="FAILED ACTIONS / LAST REASON"
        if #keys==0 then lines[#lines+1]="NONE RECORDED" end
        for _,key in ipairs(keys)do local row=self.failures[key]
            local reason=short and #row.reason>700 and row.reason:sub(1,700).." [full reason in export]" or row.reason
            lines[#lines+1]=string.format("%s (%d) +%.2fs: %s",key,row.count,row.at,reason)
        end
        lines[#lines+1]="CURRENT WAITING / BLOCKED ACTIONS"
        local waiting={};for key,row in pairs(self.latest)do if row.level=="WAIT"then waiting[#waiting+1]=key..": "..row.message end end
        table.sort(waiting);lines[#lines+1]=#waiting>0 and table.concat(waiting,"\n")or"NONE"
        lines[#lines+1]="LOG FILE: "..self.storage.path(self:currentFile())
        if self.storageError then lines[#lines+1]="LOG SAVE FAILED: "..self.storageError end
        if self.discarded>0 then lines[#lines+1]="INCOMPLETE LOG: "..self.discarded.." oldest entries lost while file saving was unavailable" end
        return table.concat(lines,"\n")
    end
    function log:tail()
        local lines={}
        for _,line in ipairs(self.recent)do lines[#lines+1]=#line>700 and line:sub(1,700).." [full entry in export]" or line end
        return table.concat(lines,"\n")
    end
    function log:report(snapshot)
        local lines={"EXIS "..self.name.." DIAGNOSTICS",tostring(snapshot or ""),self:summary(),"\nFULL SESSION LOG (UTC; unchanged statuses counted above)"}
        for _,file in ipairs(self.parts)do
            local ok,data=pcall(self.storage.read,file)
            lines[#lines+1]=ok and data or("[LOG READ FAILED: "..self.storage.path(file)..": "..tostring(data).."]")
        end
        lines[#lines+1]=table.concat(self.chunk,"\n")
        return table.concat(lines,"\n")
    end
    function log:saveReport(snapshot)
        local file=self.prefix.."_report.txt"
        local ok,err=pcall(self.storage.write,file,self:report(snapshot))
        if not ok then self.storageError=tostring(err) return nil,tostring(err) end
        return self.storage.path(file)
    end
    log:record("session","STARTED "..name,"INFO",true)
    return log
end
local diagnostic
-- End session diagnostics.

-- EXIScript: Island Escape module. Client APIs verified against the supplied export.
local function runIslandEscape()
    -- Executor-workspace storage. Old root files remain readable during migration.
    local storage = {root = "EXIGames/MrbeastIslandEscape"}
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

    diagnostic = Diagnostics.new("MrbeastIslandEscape", storage)
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local UIS = game:GetService("UserInputService")
    local HTTP = game:GetService("HttpService")
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")
    local engineReady = RS:WaitForChild("Engine", 30)
    if not engineReady or not engineReady:WaitForChild("Service", 15) or not engineReady.Service:WaitForChild("Config", 15) then
        diagnostic:record("startup", "ERROR: Island Escape services are not loaded", "ERROR") diagnostic:flush()
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
    local flags = {autoFarm = true, quest = true, bagUpgrade = true, combat = true, runShadow = true,
        liveStatus = true, choiceRewards = true, unloadBag = true, autoAttack = true,
        killFoodOnSight = true, stormStock = true, useStorage = true, scavengeAll = true,
        followFootprints = true, structureCraft = true, autoSprint = true, tidyTools = true}
    local selected = {}
    local modules = {}
    local failed = {}
    local due = {}
    local taskStatus = {}
    local recentErrors = {}
    local opts = {
        move = "Walk",
        interval = 0,
        schedulerVersion = 4,
        suiteVersion = 1,
        smoothVersion = 1,
        taskMaterialsVersion = 1,
        automationVersion = 1, survivalVersion = 3, chestHoldPadding = 1.5, foodReserve = 8, stormReserve = 20, carryFood = 0, campCacheVersion = 1,
        evadeMove = "Teleport",
        espLabelsOnly = true,
        onlyNeeded = true, exploreOutsideBorder = false,
        fastHarvest = true,
        settleTime = 0.12,
        guardRadius = 14,
        shadowRadius = 60,
        hoverHeight = 8, lowHoverVersion = 1,
        roundWait = 20,
        espDistance = 600,
        espLimit = 120,
        emergencyEscape = true,
        codes = "",
        avoidEnemies = true,
        dangerRadius = 20, threatScanRadius = 180,
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
    local path = storage.path("exis_island_" .. player.UserId .. "_" .. game.PlaceId .. ".json")
    local blue = Color3.fromRGB(80, 160, 255)
    local white = Color3.fromRGB(232, 238, 248)
    local function make(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do
            if k == "Text" and class == "TextButton" and type(v) == "string" then v = v:upper() end
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
        TextSize = 11,
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
                diagnostic:record("button " .. text, e, "ERROR")
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
        if diagnostic then diagnostic:record(key, message) end
    end
    local function safely(key, fn)
        local ok, result = xpcall(fn, Diagnostics.traceback)
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
                local payload = HTTP:JSONEncode({
                    version = 1,
                    flags = flags,
                    selected = selected,
                    options = opts,
                })
                storage.write(path, payload)
                storage.write("exis_island_session_" .. player.UserId .. ".json", payload)
            end)
            if not ok then
                note("config", "CONFIG SAVE FAILED: " .. tostring(e))
                say(e)
            end
        end
    end
    if type(readfile) == "function" then
        pcall(function()
            local configPath = path
            pcall(function()
                local sharedPath = storage.path("exis_island_session_" .. player.UserId .. ".json")
                local shared = HTTP:JSONDecode(storage.read(sharedPath))
                if shared.flags and shared.flags.autoRound then configPath = sharedPath end
            end)
            local d = HTTP:JSONDecode(storage.read(configPath))
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
                    opts.automationLoaded = d.options.automationVersion == 1
                    opts.survivalLoaded = d.options.survivalVersion == 3
                    opts.lowHoverLoaded = d.options.lowHoverVersion == 1
                    for key, range in pairs({chestHoldPadding={0,4},foodReserve={2,50},stormReserve={6,100},carryFood={0,1}}) do
                        local n = tonumber(d.options[key])
                        if n and n == n then opts[key] = math.clamp(n, range[1], range[2]) end
                    end
                    opts.schedulerVersionLoaded = d.options.schedulerVersion == 4
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
                    opts.suiteVersionLoaded = d.options.suiteVersion == 1
                    opts.smoothVersionLoaded = d.options.smoothVersion == 1
                    opts.taskMaterialsVersionLoaded = d.options.taskMaterialsVersion == 1
                    if d.options.evadeMove == "Walk" or d.options.evadeMove == "Tween" or d.options.evadeMove == "Teleport" then opts.evadeMove = d.options.evadeMove end
                    if type(d.options.espLabelsOnly) == "boolean" then opts.espLabelsOnly = d.options.espLabelsOnly end
                    for _, name in ipairs({"onlyNeeded", "fastHarvest", "emergencyEscape", "avoidEnemies", "exploreOutsideBorder"}) do
                        if type(d.options[name]) == "boolean" then opts[name] = d.options[name] end
                    end
                    if type(d.options.codes) == "string" then opts.codes = d.options.codes:sub(1, 4096) end
                    for name, limits in pairs({settleTime = {0, 2}, guardRadius = {6, 80}, shadowRadius = {20, 150},
                        hoverHeight = {4, 12}, roundWait = {5, 120}, espDistance = {30, 5000}, espLimit = {20, 500},
                        threatScanRadius={40,500}, dangerRadius = {8, 60}, baseRadius = {15, 100}}) do
                        local n = tonumber(d.options[name])
                        if n and n == n then opts[name] = math.clamp(n, limits[1], limits[2]) end
                    end
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
    if not opts.survivalLoaded then
        for _, key in ipairs({"quest","choiceRewards","combat","cook","cooked","fuel","buildCamp","progression",
            "artifacts","chests","puzzles","smelt","smeltCollect","buildBoat","antiAfk","autoAttack","killFoodOnSight","stormStock","useStorage","structureCraft",
            "scavengeAll","followFootprints","autoSprint","tidyTools"}) do flags[key] = true end
        -- Long-run survival remains the goal; preparation does not activate escape.
        flags.escape, flags.nightHover, opts.emergencyEscape = false, true, false
        flags.holdNight, flags.redeemCodes, flags.emergencyHover = true, true, true
    end
    if not opts.automationLoaded then
        for _,key in ipairs({"craft","progression","toolLadder","chopTrees","mineStone","mineIron","combat","autoAttack",
            "killFoodOnSight","killShadow","chests","buildCamp","structureCraft","smelt","smeltCollect","unloadBag",
            "useStorage","bulkCollect","nightExplore","greatWall"})do flags[key]=true end
    end
    opts.carryFood = 0
    opts.interval = 0
    if not opts.lowHoverLoaded then
        opts.hoverHeight = 8
        flags.emergencyHover = false
        flags.quest, flags.choiceRewards = true, true
    end
    if not opts.taskMaterialsVersionLoaded then opts.onlyNeeded = true end
    if not opts.schedulerVersionLoaded then opts.interval = 0 end
    if not opts.suiteVersionLoaded then flags.escape = false end
    if not opts.smoothVersionLoaded then
        opts.interval = 0
        opts.settleTime = 0
        opts.fastHarvest = true
        opts.espLimit = math.min(opts.espLimit, 48)
    end
    opts.threatScanRadius=math.clamp(tonumber(opts.threatScanRadius)or 180,40,500)
    opts.dangerRadius = math.clamp(tonumber(opts.dangerRadius) or 20, 8, 60)
    opts.baseRadius = math.clamp(tonumber(opts.baseRadius) or 45, 15, 100)
    opts.interval = math.clamp(opts.interval, 0, 5)
    opts.huntRadius = math.clamp(opts.huntRadius, 10, 150)
    opts.enemyReach = math.clamp(opts.enemyReach, 1, 20)
    opts.combatMargin = math.clamp(opts.combatMargin, 0.25, 5)
    opts.combatHeight = math.clamp(opts.combatHeight, 1, 10)
    opts.retreatHealth = math.clamp(opts.retreatHealth, 5, 90)
    function work.boundedRead(read, label)
        local done, result = false, nil
        if diagnostic then diagnostic:record(label,"REQUEST STARTED","INFO",true) end
        local thread=task.spawn(function() result=table.pack(pcall(read)) done=true end)
        local deadline=os.clock()+6.5
        repeat
            if done then
                if not result[1] then
                    if diagnostic then diagnostic:record(label,result[2],"ERROR",true) end
                    error(result[2])
                end
                if diagnostic then
                    local rejected=type(result[2])=="table" and (result[2].ok==false or result[2].success==false)
                    diagnostic:record(label,"RESPONSE: "..Diagnostics.describe(result[2]),rejected and "ERROR" or "INFO",true)
                end
                return table.unpack(result,2,result.n)
            end
            task.wait()
        until not alive or os.clock()>=deadline
        task.cancel(thread)
        if diagnostic then diagnostic:record(label,"READ TIMED OUT; queue can continue","ERROR",true) end
        error(tostring(label).." read timed out; queue can continue")
    end
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
                    return work.boundedRead(function() return remote:InvokeServer() end,"configuration")
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
            note("module "..name,"UNAVAILABLE IN THIS SERVER")
            return
        end
        local ok, m = pcall(require, source)
        if ok then
            modules[name] = m
            return m
        end
        failed[name] = os.clock()
        note("module "..name,"ERROR: "..tostring(m))
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
            addMatter = "addTaskRemote",
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
        Storage = {storeItem = "storeItemRemote", takeItem = "takeItemRemote", getSnapshot = "getSnapshotFunc"},
        FreeBuild = {requestPlace = "placeRemote"},
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
                local args=table.pack(...)
                return work.boundedRead(function() return remote:InvokeServer(table.unpack(args,1,args.n)) end,name.."."..action)
            end
            work.sent = work.sent + 1
            if name == "Furnace" and action == "addBoth" then
                remote:FireServer("both")
            else
                remote:FireServer(...)
            end
            note(name .. "." .. action, "REQUEST SENT (AWAITING GAME CONFIRMATION)")
            if diagnostic then diagnostic:record(name.."."..action,"REQUEST SENT","INFO",true) end
            return true
        end
        local m = module(name)
        assert(m and m.client and type(m.client[action]) == "function", name .. "." .. action .. " unavailable")
        if name=="ChestService" and (action=="isLocked" or action=="isOpened") then
            local args=table.pack(...)
            return work.boundedRead(function() return m.client[action](table.unpack(args,1,args.n)) end,name.."."..action)
        end
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
        local distance = math.max(0, math.min(4, radius * 0.6))
        local height = math.max(2, h.HipHeight + r.Size.Y / 2)
        for i = -1, 7 do
            local angle = i * math.pi / 4
            local offset=i<0 and 0 or distance
            local probe = p + Vector3.new(math.cos(angle) * offset, 0, math.sin(angle) * offset)
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
    local function travel(target, key, radius, overrideMode)
        local mode = overrideMode or opts.move
        if flags.autoSprint and work.setSprint then work.setSprint(mode ~= "Teleport") end
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
        motion.owner, motion.mode = key, mode
        local goals = motion.goals(target, radius)
        local dryCount=#goals
        for i = #goals, 1, -1 do
            if not work.safeDestination(goals[i], key) then table.remove(goals, i) end
        end
        local deadline = os.clock() + opts.routeTimeout
        local ok, result = pcall(function()
            if #goals == 0 then
                note(key,"NO SAFE DRY APPROACH • DRY "..dryCount.." / SAFE "..#goals.." • RADIUS "..tostring(radius))
                return false
            end
            for index = 1, math.min(3, #goals) do
                r, h = root()
                if not r or not motion.valid(key, serial, character) or os.clock() > deadline then
                    return false
                end
                local goal = goals[index]
                if not work.safeDestination(goal, key) then return false end
                if mode == "Teleport" then
                    local facing = Vector3.new(p.X, goal.Y, p.Z)
                    r.CFrame = (goal - facing).Magnitude > 0.1 and CFrame.lookAt(goal, facing) or CFrame.new(goal)
                    task.wait()
                    return motion.valid(key, serial, character)
                end
                local path = motion.pathTo(r.Position, goal)
                if path then
                    note(key, mode:upper() .. " - FOLLOWING SAFE ROUTE")
                    local reached = mode == "Tween" and motion.tweenPath(path, goal, key, serial, character, deadline) or (mode == "Walk" and motion.walkPath(path, goal, key, serial, character, deadline))
                    if reached then
                        local arrived=root()
                        local gap=arrived and Vector3.new(arrived.Position.X-goal.X,0,arrived.Position.Z-goal.Z).Magnitude
                        if gap and gap<=math.max(.25,radius)then return true end
                        -- MoveToFinished permits a wider tolerance than a native
                        -- station or a melee stance. Finish the last step here.
                        h:MoveTo(goal)
                        if work.await(key,function()
                            local current=root()
                            return current and Vector3.new(current.Position.X-goal.X,0,current.Position.Z-goal.Z).Magnitude<=math.max(.25,radius)
                        end,1.5)then return true end
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
        motion.owner, motion.mode = nil, nil
        if not ok then
            note(key, "MOVEMENT ERROR: " .. tostring(result))
            result = false
        end
        if not result and serial == motion.serial and alive and flags[key] and typeof(target) == "Instance" then
            motion.blocked[target] = os.clock() + 8
        end
        return result == true and motion.valid(key, serial, character)
    end
    function work.invalidateInventory()
        work.toolCache, work.countCache, work.signatureCache, work.bagCache, work.resourceToolCache = nil, nil, nil, nil, nil
    end
    local function tools()
        local stamp = math.floor(os.clock() * 120)
        if work.toolCache and work.toolStamp == stamp then return work.toolCache end
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
        work.toolCache, work.toolStamp = t, stamp
        return t
    end
    function work.toolCounts()
        local stamp = math.floor(os.clock() * 120)
        if work.countCache and work.countStamp == stamp then return work.countCache end
        local result = {}
        for _, tool in ipairs(tools()) do
            result[tool.Name] = (result[tool.Name] or 0) + (tonumber(tool:GetAttribute("count")) or 1)
        end
        work.countCache, work.countStamp = result, stamp
        work.signatureCache = nil
        return result
    end
    local function count(name)
        return work.toolCounts()[name] or 0
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
                if p and work.insideBorder(p) then
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
            if work.selectedPage == name then content.Visible = not content.Visible return end
            work.selectedPage, content.Visible = name, true
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
    function work.slider(parent, key, label, lo, hi, step)
        local row = make("Frame", {Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1}, parent)
        make("TextLabel", {Size = UDim2.new(1, -60, 0, 20), BackgroundTransparency = 1, Text = label,
            TextSize = 10, Font = Enum.Font.BuilderSans, TextColor3 = white, TextXAlignment = Enum.TextXAlignment.Left}, row)
        local value = make("TextBox", {Position = UDim2.new(1, -55, 0, 0), Size = UDim2.fromOffset(55, 21),
            BackgroundColor3 = Color3.fromRGB(21, 32, 47), TextColor3 = white, TextSize = 10, Font = Enum.Font.BuilderSans,
            ClearTextOnFocus = false}, row)
        corner(value, 4)
        local track = make("TextButton", {Position = UDim2.fromOffset(1, 29), Size = UDim2.new(1, -2, 0, 9),
            Text = "", BackgroundColor3 = Color3.fromRGB(38, 52, 72), AutoButtonColor = false}, row)
        corner(track, 5)
        local fill = make("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = blue, BorderSizePixel = 0}, track)
        corner(fill, 5)
        local knob = make("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.fromOffset(13, 13), BackgroundColor3 = white, BorderSizePixel = 0}, track)
        corner(knob, 7)
        local dragging
        local function set(n, persist)
            if type(n) ~= "number" or n ~= n then return end
            opts[key] = math.clamp(math.floor(n / step + 0.5) * step, lo, hi)
            local alpha = (opts[key] - lo) / (hi - lo)
            fill.Size = UDim2.fromScale(alpha, 1) knob.Position = UDim2.fromScale(alpha, 0.5)
            value.Text = string.format(step < 1 and "%.2f" or "%.0f", opts[key])
            if persist then save() end
        end
        local function point(input)
            local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
            set(lo + alpha * (hi - lo), false)
        end
        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = input point(input) end
        end)
        connections[#connections + 1] = UIS.InputChanged:Connect(function(input)
            if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseMovement) then point(input) end
        end)
        connections[#connections + 1] = UIS.InputEnded:Connect(function(input)
            if input == dragging then dragging = nil save() end
        end)
        value.FocusLost:Connect(function() set(tonumber(value.Text) or opts[key], true) end)
        set(opts[key], false)
    end
    function work.makeSuiteUI(p)
        local master = group(p.main, "AUTO FARM")
        toggles.autoFarm = switch(master, "AUTO FARM • MASTER SWITCH", function() return flags.autoFarm end, function(v)
            flags.autoFarm = v
            motion.cancel(v and "AUTO FARM STARTED" or "AUTO FARM PAUSED")
            if work.releaseHover then work.releaseHover(true) end
        end)
        text(master, "Controls grind loops, survival, combat and round automation. Your individual selections remain saved.")
        button(master, "APPLY LONG-RUN PRESET", function()
            for _, key in ipairs({"autoFarm", "eat", "fuel", "cook", "cooked", "huntFood", "buildCamp", "toolLadder",
                "smelt", "smeltCollect", "tidyBag", "choiceRewards", "quest", "bagUpgrade", "combat", "runShadow",
                "drops", "chopTrees", "mineStone", "mineIron", "liveStatus", "unloadBag", "autoAttack", "killFoodOnSight",
                "stormStock", "useStorage", "structureCraft", "scavengeAll", "followFootprints", "artifacts", "chests", "puzzles", "autoSprint"}) do flags[key] = true end
            flags.escape = false flags.buildBoat = true
            flags.nightHover,flags.holdNight,flags.emergencyHover,flags.redeemCodes=true,true,false,true
            for _, render in pairs(toggles) do render() end
            save()
        end)
        toggle(group(p.combat,"ATTACK INPUT"), "autoAttack", "Auto click attack button", "Uses native Attack input and respects weapon cooldown / hit timing.")
        local mining = group(p.gather, "RESOURCE LOOPS")
        toggle(mining, "chopTrees", "Chop trees")
        toggle(mining, "mineStone", "Mine stone")
        toggle(mining, "mineIron", "Mine iron")
        switch(mining, "ONLY MATERIALS STILL NEEDED", function() return opts.onlyNeeded end, function(v) opts.onlyNeeded = v end)
        text(mining, "Needed-only follows enabled quests, recipes and fuel goals. Turn it off to stockpile freely.")
        switch(mining, "FAST HARVEST", function() return opts.fastHarvest end, function(v) opts.fastHarvest = v end)
        work.slider(mining, "settleTime", "DROP SETTLE TIME (0 = BACKGROUND WATCH)", 0, 2, 0.05)
        local near = group(p.combat, "AURA / NEARBY DEFENCE")
        toggle(near, "aura", "Kill aura • nearby NPCs", "Uses an equipped melee weapon, checked positions and its native cooldown / target cap.")
        work.evadeButton = button(near, "EVADE MODE: " .. opts.evadeMove:upper(), function()
            opts.evadeMove = opts.evadeMove == "Teleport" and "Tween" or (opts.evadeMove == "Tween" and "Walk" or "Teleport")
            work.evadeButton.Text = "EVADE MODE: " .. opts.evadeMove:upper()
            say("EVADE MODE: " .. opts.evadeMove:upper()) save()
        end)
        text(near, "Evade first switches to a safe useful target. Teleport is the default escape mode; normal movement is unchanged.")
        work.slider(near, "guardRadius", "GUARD RADIUS (STUDS)", 6, 80, 1)
        local shadows=group(p.survival,"SHADOW AVOIDANCE")
        toggle(shadows, "killShadow", "Fight Shadow with a torch", "Uses native TorchHits receipts. Retreats without a torch or at unsafe health.")
        toggle(shadows, "runShadow", "Run from the Shadow when unable to fight")
        number(shadows, "shadowRadius", "SHADOW AVOIDANCE RADIUS", 20, 150)
        local food = group(p.food, "COOKED STOCKPILE")
        local hunting=group(p.combat,"PASSIVE FOOD MOBS")
        toggle(hunting, "killFoodOnSight", "Kill passive food mobs on sight", "Chickens, crabs and other passive food animals. Survival comes first.")
        toggle(food, "stormStock", "Stock cooked food before storms")
        number(food, "foodReserve", "NORMAL COOKED RESERVE", 2, 50)
        number(food, "stormReserve", "DAY 5 / 6 STORM RESERVE", 6, 100)
        text(food,"Cooked meals stay on the ground by camp. Pick up one only when health or hunger needs it.")
        toggle(hunting, "huntFood", "Hunt food when empty", "Hunts chickens, crabs and configured food animals when food is empty. Collects their drops.")
        local inventory=group(p.inventory,"CAMP STOCKPILE / RECLAIM")
        toggle(inventory,"tidyTools","Drop duplicate tools; keep one best of each kind", "Keeps one torch. Quest supplies and active recipe quantities stay reserved.")
        toggle(inventory,"bulkCollect","Fill the bag before sorting at base", "Collect a batch before storing or dropping. Urgent survival and completed quest deliveries can run sooner.")
        toggle(inventory, "tidyBag", "Tidy bag by submitting materials", "Submits usable materials to quests, buildings, crafting, cooking and smelting.")
        toggle(inventory, "unloadBag", "Drop unused supplies and spare tools at camp", "Keeps one best working tool per type and only current craft ingredients. Reclaims supplies only for the current task.")
        work.slider(food, "hunger", "EAT BELOW HUNGER (%)", 1, 100, 1)
        local projects = group(p.craft, "PROGRESSION GOALS")
        toggle(projects, "toolLadder", "Craft tool ladder")
        local campProjects=group(p.camp,"CAMP PROGRESSION")
        toggle(campProjects, "buildCamp", "Build camp")
        toggle(campProjects,"greatWall","Great Wall of EXI • three beach layers", "Uses the live wall recipe, dry beach edges and an entrance. Prioritizes survival, gear and utility buildings.")
        toggle(group(p.explore,"BOAT PREPARATION"), "buildBoat", "Build the boat", "Uses live recipe / contribution requirements. Building does not trigger escape.")
        toggle(group(p.quests, "CHOICE REWARDS"), "choiceRewards", "Take MrBeast choice rewards", "Selects useful rewards automatically, including an already-open menu.")
        toggle(group(p.explore, "ARTIFACTS"), "artifacts", "Fetch the four artifacts", "Compass, Map, Plastic Bucket and Radio. Locked or unsafe locations are skipped.")
        local night = group(p.survival, "NIGHT SURVIVAL")
        toggle(night,"nightExplore","Explore at night after loaded hostiles are cleared", "Keeps checking for newly spawned enemies; unloaded enemies cannot be verified.")
        toggle(night, "holdNight", "Pause routine work at night", "Optional. Turn off to keep working at safe targets inside the border. Defence and urgent survival always take priority.")
        toggle(night, "nightHover", "Low hover above camp at night", "Checks threats and health every 0.15s, moves laterally on danger, and stops hover for this night if unexplained damage continues. No climbing.")
        number(night, "hoverHeight", "LOW HOVER HEIGHT (STUDS)", 4, 12)
        local escape = group(p.explore, "LONG RUN / ESCAPE")
        text(escape, "LONG DAYS FIRST • AUTO ESCAPE IS OFF BY DEFAULT")
        switch(escape, "EMERGENCY CONDITIONS ONLY", function() return opts.emergencyEscape end, function(v) opts.emergencyEscape = v end)
        text(escape, "Requires critical health, no carried food, a detected threat and a ready boat. Leave auto escape off to stay indefinitely.")
        local session = p.rounds
        local rounds = group(session, "ROUND CONTROLS")
        toggle(rounds, "autoRound", "Start a new round automatically", "Votes replay after a confirmed team wipe. In a lobby, joins a room and requests a solo start. Other players / server minimums can still delay it.")
        toggle(rounds, "leaveLost", "Leave a lost round", "Requires every loaded teammate to be dead and the death screen to be open. Does not abandon living teammates.")
        button(rounds, "STOP ROUND AUTOMATION", function()
            for _, key in ipairs({"autoRound", "leaveLost"}) do flags[key] = false if toggles[key] then toggles[key]() end end
            save()
        end)
        number(rounds, "roundWait", "LOST ROUND WAIT (SECONDS)", 5, 120)
        local codes = group(p.rewards, "REDEEM CODES")
        toggle(codes, "redeemCodes", "Auto redeem available codes")
        text(codes, "Uses codes in the current config and your list below. No invented codes; requests follow the server rate limit.")
        local box = make("TextBox", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.fromRGB(21, 32, 47),
            Text = opts.codes, PlaceholderText = "CODES, SEPARATED, BY COMMAS", ClearTextOnFocus = false,
            TextColor3 = white, PlaceholderColor3 = Color3.fromRGB(120, 135, 155), TextSize = 10, Font = Enum.Font.BuilderSans}, codes)
        corner(box, 5)
        box.FocusLost:Connect(function() opts.codes = box.Text:sub(1, 4096) save() end)
        local esp = p.esp
        for _, category in ipairs({
            {"RESOURCES", {"espTrees", "Trees"}, {"espStone", "Stone nodes"}, {"espIron", "Iron nodes"}, {"espOtherResources", "Other resource nodes"}},
            {"DROPS", {"espDrops", "Material drops"}, {"espFood", "Food drops"}, {"espBags", "Bag / equipment drops"}},
            {"CHARACTERS", {"espEnemies", "Enemies"}, {"espShadow", "Shadow"}, {"espPlayers", "Other players"}},
            {"CAMP", {"espCamp", "Camp buildings"}, {"espBlueprints", "Unfinished blueprints"}},
            {"EXPLORATION", {"espArtifacts", "Artifacts"}, {"espChests", "Loot boxes"}, {"espPuzzles", "Puzzle props"}},
        }) do
            local section = group(esp, category[1])
            for i = 2, #category do toggle(section, category[i][1], category[i][2]) end
        end
        local display = group(esp, "DISPLAY LIMITS")
        switch(display, "LIGHTWEIGHT ESP • LABELS ONLY", function() return opts.espLabelsOnly end, function(v) opts.espLabelsOnly = v end)
        number(display, "espDistance", "MAX DISTANCE (STUDS)", 30, 5000)
        number(display, "espLimit", "MAX VISIBLE MARKERS", 20, 500)
        button(display, "CLEAR ALL ESP", function()
            for key in pairs(flags) do if key:sub(1, 3) == "esp" then flags[key] = false if toggles[key] then toggles[key]() end end end
            if work.clearESP then work.clearESP() end
            save()
        end)
        local status = p.status
        local live = group(status, "LIVE RUN")
        toggle(live,"liveStatus","Live status outside panel")
        work.statusLabel = text(live, "WAITING FOR RUN DATA")
        local shield = group(status, "COSMETIC SHIELD")
        toggle(shield, "cosmeticShield", "No damage • cosmetic display", "Shows a shield label only. Health, incoming damage and server hit validation are unchanged.")
        work.shieldLabel = text(shield, "COSMETIC SHIELD: OFF")
    end
    local main=page("Main")
    local survivalPage=page("Survival")
    local combatPage=page("Combat")
    local foodPage=page("Food")
    local inventoryPage=page("Inventory")
    local resources=page("Gather")
    local camp=page("Camp")
    local craft=page("Craft")
    local questPage=page("Quests")
    local rewardsPage=page("Rewards")
    local explore=page("Explore")
    local fishingPage=page("Fishing")
    local roundsPage=page("Rounds")
    local espPage=page("ESP")
    local statusPage=page("Status")
    local settings=page("Settings")
    work.diagnosticsPage=page("Diagnostics")
    local survival = group(foodPage, "MEALS / THRESHOLDS")
    toggle(survival, "eat", "Auto eat", "Uses selected food when health or hunger is low. No selection uses food listed in the game config.")
    number(survival, "health", "HEALTH BELOW (%)", 1, 100)
    local combat = group(combatPage, "DEFENCE")
    toggle(combat, "combat", "Auto defend base / nearby enemies", "Base threats interrupt ordinary work. Attacks from checked swarm edges, repositions, and retreats on danger.")
    switch(combat, "AVOID ENEMIES WHILE WORKING", function() return opts.avoidEnemies end, function(v) opts.avoidEnemies = v end)
    number(combat,"threatScanRadius","HOSTILE DETECTION RADIUS",40,500)
    number(combat, "dangerRadius", "ENEMY AVOIDANCE BUFFER", 8, 60)
    number(combat, "baseRadius", "BASE DEFENCE RADIUS", 15, 100)
    toggle(combat, "hunt", "Auto hunt / kill enemies", "Hunts within the selected radius after urgent survival and progression work.")
    switch(combat, "PREFER LOWER-RISK ATTACK POSITIONS", function() return opts.safeCombat end, function(v) opts.safeCombat = v end)
    number(combat, "huntRadius", "HUNT RADIUS", 10, 150)
    number(combat, "enemyReach", "ENEMY REACH ESTIMATE (STUDS)", 1, 20)
    number(combat, "retreatHealth", "RETREAT BELOW HEALTH (%)", 5, 90)
    text(combat, "Uses visible proximity and approach as threat estimates. Prefers the outside of a swarm with clear sight. Hidden AI / attack reach can still cause damage.")
    local upgrades = group(craft, "UPGRADE PROGRESSION")
    toggle(upgrades, "progression", "Auto upgrade / gather missing materials", "Upgrades bags, campfire, tools, armour and available buildings. Collects current shortages and deposits each pickup. Blocked goals give way.")
    text(upgrades, "Automatically gathers required resources and collects required drops. Selected craft recipes are included. Unavailable goals retry later.")
    work.upgradeLabel = text(upgrades, "UPGRADE: WAITING")
    toggle(group(inventoryPage,"BAG UPGRADES"), "bagUpgrade", "Prioritize larger bags", "Collects and equips better bags even when full. Progression crafts available station bag recipes and prioritizes bag rewards.")
    local fishing = group(fishingPage, "FISHING")
    toggle(fishing, "fish", "Auto cast and reel", "Equip a rod and face water. Casts and reels automatically; complete the fish minigame normally. Movement pauses only during an active cast.")
    local gather = group(resources, "RESOURCE FARMING")
    toggle(gather, "gather", "Auto gather selected resources", "Cuts one resource fully, then collects all its loaded drops before another tree. Full bags retain a recovery job. No selection = all resource types.")
    local drops = group(resources, "DROPPED ITEMS")
    toggle(drops, "drops", "Auto collect drops", "All unprotected drops when no items are selected below. Respects owner protection.")
    local fire = group(camp, "CAMPFIRE")
    toggle(fire, "fuel", "Auto add wood", "Adds wood only below the fuel target.")
    number(fire, "fuel", "FUEL TARGET (WOOD)", 1, 100)
    local cooking=group(foodPage,"CAMPFIRE COOKING")
    toggle(cooking, "cook", "Auto cook food", "Uses selected cookable food. No selection uses all cookable food from the game config.")
    toggle(cooking, "cooked", "Collect one cooked meal only when needed")
    button(fire, "ADD ONE WOOD / REFRESH FUEL STATE", function()
        assert(built("Campfire"), "Build the campfire first")
        call("MakeFire", "addWood")
    end)
    local furnace = group(craft, "FURNACE PROCESSING")
    toggle(furnace, "smelt", "Auto feed furnace", "Consumes smelting ingredients.")
    toggle(furnace, "smeltCollect", "Auto collect results")
    local water = group(foodPage, "WATER MAKER")
    toggle(water, "water", "Auto collect coconuts")
    local crafting = group(craft, "TOOLS AND ARMOUR")
    toggle(crafting, "craft", "Auto craft selected items", "Crafts one missing selected item when materials are available.")
    local building = group(camp, "CONSTRUCTION")
    toggle(building, "build", "Auto contribute selected buildings", "Spends recipe materials on selected unfinished buildings.")
    toggle(building, "buildCurrent", "Auto build active blueprints", "Uses owned materials on available unfinished buildings, including the first campfire. No selection required.")
    local questBody = group(questPage, "MRBEAST QUESTS")
    toggle(questBody, "quest", "Auto MrBeast requests", "Follows the active requested item and quantity. Hunts matching animals when needed; deposits quest supplies near MrBeast.")
    local questInfo = text(questBody, "QUEST: WAITING")
    work.questLabel=questInfo
    button(questBody,"COPY LIVE QUESTS AND REWARD POOLS",function()
        local details=work.questCatalog and work.questCatalog()or "Quest configuration is still loading"
        if type(setclipboard)=="function"then setclipboard(details)else print(details)end
        say("LIVE QUEST CONFIGURATION "..(type(setclipboard)=="function"and "COPIED"or "PRINTED"))
    end)
    local rewards = group(rewardsPage, "CLAIM REWARDS")
    toggle(rewards, "daily", "Auto daily reward")
    toggle(rewards, "weekly", "Auto weekly reward")
    toggle(rewards, "playtime", "Auto playtime rewards")
    toggle(rewards, "dailyQuest", "Claim completed daily quests")
    local chestUI = group(explore, "CHESTS AND PUZZLES")
    toggle(chestUI, "chests", "Auto open unlocked chests", "Collects chest drops. Unloads at camp when full, then returns for the rest.")
    toggle(chestUI, "puzzles", "Auto interact with puzzle props")
    local escape = group(explore, "ESCAPE BOAT")
    toggle(escape, "escape", "Emergency auto escape", "Off by default. Only uses a ready boat when your enabled emergency conditions are met. Ends your run.")
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
        if work.releaseHover then work.releaseHover(true) end
        if work.clearESP then work.clearESP() end
        say("ALL TASKS STOPPED")
    end
    button(session, "STOP ALL", stopAll)
    local movementOptions=group(settings,"MOVEMENT / ROUTING")
    local moveButton
    moveButton = button(movementOptions, "MOVE: " .. opts.move, function()
        motion.cancel("MOVEMENT MODE CHANGED")
        opts.move = opts.move == "Walk" and "Teleport" or (opts.move == "Teleport" and "Tween" or "Walk")
        moveButton.Text = "MOVE: " .. opts.move:upper()
        save()
    end)
    number(movementOptions, "tweenSpeed", "TWEEN SPEED (STUDS / SECOND)", 8, 120)
    number(movementOptions, "routeTimeout", "ROUTE TIMEOUT (SECONDS)", 6, 30)
    number(group(inventoryPage,"BAG CAPACITY"), "bagLimit", "BAG CAPACITY OVERRIDE (0 = DETECT)", 0, 10000)
    number(group(settings,"TASK TIMEOUT"), "jobTimeout", "TASK SAFETY TIMEOUT (SECONDS)", 15, 600)
    switch(movementOptions, "AUTO JUMP WHEN BLOCKED", function()
        return opts.autoJump
    end, function(v)
        opts.autoJump = v
        motion.cancel("JUMP OPTION CHANGED")
    end)
    text(movementOptions, "Walk uses dry paths, jump waypoints and stuck recovery. Tween follows checked paths. Teleport uses a dry landing; blocked routes are skipped.")
    local jobGroup = group(settings, "TASK PRIORITIES")
    text(jobGroup,"Survival and fire → MrBeast rewards / requests → on-sight food → camp stockpile → upgrades, gathering and exploration.")
    text(jobGroup,"Urgent survival can interrupt. Other work queues behind the current action. Daytime tasks yield after seven seconds without progress; valid interaction holds keep their required time.")
    local queueLabel = text(jobGroup, "JOB: IDLE")
    for _, category in ipairs({
        {"SURVIVAL",{"runShadow","holdNight","nightHover","emergencyHover"}},
        {"COMBAT",{"combat","hunt","aura","autoAttack","killFoodOnSight","huntFood"}},
        {"FOOD",{"eat","stormStock","cook","cooked","water"}},
        {"INVENTORY",{"bagUpgrade","tidyBag","unloadBag","useStorage"}},
        {"GATHER",{"gather","chopTrees","mineStone","mineIron","scavengeAll","drops"}},
        {"CAMP",{"fuel","build","buildCurrent","buildCamp","structureCraft"}},
        {"CRAFT",{"craft","progression","toolLadder","smelt","smeltCollect"}},
        {"QUESTS",{"quest","choiceRewards","daily","weekly","playtime","dailyQuest"}},
        {"EXPLORE",{"escape","artifacts","followFootprints","chests","puzzles","travel","buildBoat"}},
        {"FISHING",{"fish"}},
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
    text(session,"NO ROUTINE ACTION DELAY • valid holds, native cooldowns and receipts keep their required time.")
    work.makeSuiteUI({main=main,gather=resources,camp=camp,craft=craft,quests=questPage,explore=explore,settings=settings,
        combat=combatPage,food=foodPage,inventory=inventoryPage,survival=survivalPage,
        rewards=rewardsPage,rounds=roundsPage,esp=espPage,status=statusPage})
    toggle(group(inventoryPage, "LEGACY STORAGE"), "useStorage", "Reclaim existing storage supplies", "New stockpiles go on the ground at camp; food in old storage is moved out safely.")
    toggle(group(camp, "BASE STRUCTURES"), "structureCraft", "Craft and place available base structures")
    toggle(group(resources, "STOCKPILE"), "scavengeAll", "Collect all material types, including crystals")
    local explorationSafety=group(explore,"EXPLORATION BORDER")
    switch(explorationSafety,"ALLOW EXPLORATION OUTSIDE UNLOCKED BORDER",function()return opts.exploreOutsideBorder end,function(v)opts.exploreOutsideBorder=v end)
    text(explorationSafety,"Applies only to chests, puzzles, artifacts and selected travel. It does not remove server walls or change combat/camp safety.")
    toggle(group(explore, "TRAILS AND CLUES"), "followFootprints", "Follow chest footprints and objective hints")
    toggle(movementOptions, "autoSprint", "Use native sprint while travelling")
    number(chestUI, "chestHoldPadding", "CHEST EXTRA HOLD (SECONDS)", 0, 4)
    work.hintLabel = text(group(explore,"LIVE OBJECTIVE HINTS"), "READING LOADED ARTIFACT AND CHEST CLUES")
    work.liveLabel = make("TextLabel", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10),
        Size = UDim2.fromOffset(math.min(285, viewport.X - 20), 82), BackgroundColor3 = Color3.fromRGB(8, 12, 18),
        BackgroundTransparency = 0.2, BorderSizePixel = 0, Text = "EXIS • WAITING", TextSize = 9,
        TextColor3 = white, Font = Enum.Font.BuilderSans, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Active = false}, gui)
    corner(work.liveLabel, 6)
    make("UIPadding", {PaddingRight = UDim.new(0, 20)}, work.liveLabel)
    local hideLive = make("TextButton", {Position = UDim2.new(1, -20, 0, 0), Size = UDim2.fromOffset(20, 20),
        Text = "×", TextColor3 = white, TextSize = 16, BackgroundTransparency = 1, Font = Enum.Font.BuilderSans}, work.liveLabel)
    hideLive.Activated:Connect(function() flags.liveStatus = false work.liveLabel.Visible = false
        if toggles.liveStatus then toggles.liveStatus() end save() end)
    local diag = group(work.diagnosticsPage, "FAILURES AND FULL SESSION LOG")
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
    diagnosticText.LayoutOrder = 100000
    local function refreshDiagnostics()
        local lines = {}
        for key in pairs(toggles) do
            lines[#lines + 1] = key:upper() .. ": " .. (flags[key] and (taskStatus[key] or "WAITING") or "OFF")
        end
        table.sort(lines)
        local _, human = root()
        local scene = world()
        local day = scene and scene:FindFirstChild("Day")
        local phase = scene and scene:FindFirstChild("Phase")
        local used, capacity = 0, 0
        if work.bagState then used, capacity = work.bagState() end
        work.diagnosticSnapshot = "PLACE "..game.PlaceId.." | DAY "..tostring(day and day.Value or "UNKNOWN").." | PHASE "..tostring(phase and phase.Value or "UNKNOWN")
            .."\nHP "..tostring(human and human.Health or "NO CHARACTER").." | BAG "..tostring(used).."/"..tostring(capacity).." | REQUESTS "..work.sent
            .."\nAUTO FARM "..tostring(flags.autoFarm).." | CURRENT JOB "..tostring(work.active or "NONE").."\nQUEUE: " .. tostring(taskStatus.queue or "IDLE") .. "\nMOVEMENT: " .. tostring(motion.owner or "IDLE") .. "\nHOSTILE SCAN: "..tostring(opts.threatScanRadius).." STUDS\nMRBEAST: "..tostring(work.questStatus or "WAITING").."\n"..tostring(questInfo.Text).."\n" .. table.concat(lines, "\n") .. "\n"..(work.automationReport and work.automationReport()or"").."\n\nRECENT ERRORS\n" .. (#recentErrors > 0 and table.concat(recentErrors, "\n") or "NONE")
        diagnosticText.Text = work.diagnosticSnapshot .. "\n\n" .. diagnostic:summary(true) .. "\n\nRECENT LOG\n" .. diagnostic:tail()
    end
    button(diag, "COPY DIAGNOSTICS", function()
        refreshDiagnostics()
        assert(type(setclipboard) == "function", "Clipboard unavailable")
        setclipboard(diagnostic:report(work.diagnosticSnapshot))
        say("DIAGNOSTICS COPIED")
    end)
    button(diag, "SAVE FULL LOG", function()
        refreshDiagnostics()
        local file, err = diagnostic:saveReport(work.diagnosticSnapshot)
        assert(file, err)
        say("LOG SAVED: " .. file)
    end)
    task.spawn(function()
        while alive do
            safely("diagnostic view", function()
                if work.selectedPage == "Diagnostics" then refreshDiagnostics() end
                if os.clock() >= (work.nextLogFlush or 0) then
                    diagnostic:flush() work.nextLogFlush = os.clock() + 3
                end
            end)
            task.wait(0.5)
        end
    end)
    local modeLabel = text(main, "SERVER: CHECKING")
    local clockLabel = text(main, "DAY / PHASE: WAITING")
    connections[#connections + 1] = player.OnTeleport:Connect(function(state)
        if (not flags.autoExecute and not flags.autoRound) or state ~= Enum.TeleportState.Started then
            return
        end
        local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
        if type(queue) ~= "function" then
            say("TELEPORT QUEUE NOT SUPPORTED")
            return
        end
        save()
        if flags.autoRound then
            queue('loadstring(game:HttpGet("https://raw.githubusercontent.com/iaxen/EXIS_Games/main/Games/MrbeastIslandEscape.lua"))()')
        else
            queue('loadstring(game:HttpGet("https://raw.githubusercontent.com/iaxen/EXIScript/main/EXIScript.lua"))()')
        end
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
        diagnostic:record("session","STOPPED: UI CLOSED","INFO",true) diagnostic:flush()
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
    work.selectedPage = "Main"
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
            choices(foodPage, "food", c.food.byId)
            choices(foodPage, "cook", c.food.byId, function(i)
                return i.canCook == true
            end)
            choices(craft, "craft", c.item.byId, function(i)
                return i.recipeId and (i.type == "tool" or i.type == "armour")
            end)
            choices(camp, "build", c.build.byId)
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
            if diagnostic then diagnostic:record("background setup",e,"ERROR") end
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
                local service=module(binding[1])
                local api=service and(service.client or service)
                if api and type(api[binding[2]])=="function"then
                    api[binding[2]](function(v)rewardData[binding[3]]=v end)
                else note("optional rewards",binding[1].." NOT AVAILABLE IN THIS SERVER; SKIPPED")end
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
                work.refreshAt = 0
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
        return work.toolCounts()
    end
    function work.signature()
        local inventory = work.inventory()
        if work.signatureCache then return work.signatureCache end
        local rows = {}
        for name, amount in pairs(inventory) do rows[#rows + 1] = name .. "=" .. tostring(amount) end
        table.sort(rows)
        work.signatureCache = table.concat(rows, "|")
        return work.signatureCache
    end
    function work.running(key, character, serial)
        return alive and work.keyEnabled(key) and player.Character == character
            and motion.serial == serial and not not root() and work.checkpoint(key)
    end
    function work.await(key, predicate, seconds)
        local character, serial = player.Character, motion.serial
        local deadline = os.clock() + (seconds or 3)
        repeat
            if predicate() then work.progressAt = os.clock() return true end
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
    function work.submitUnits(key, name, action, amounts, argument)
        work.submissionPending = work.submissionPending or {}
        local token = name .. ":" .. action .. ":" .. tostring(argument or "")
        local pending = work.submissionPending[token]
        local function acknowledged(batch)
            for id, expected in pairs(batch.expected) do
                local item = config().item.byId[id]
                if not item or count(item.displayName) > expected then return false end
            end
            return true
        end
        if pending then
            if acknowledged(pending) then work.submissionPending[token] = nil
            else
                local signature = work.signature()
                if pending.signature ~= signature then pending.signature = signature pending.at = os.clock() end
                if os.clock() - pending.at < 3 then
                    note(key, "WAITING FOR PREVIOUS MATERIAL RECEIPT") return false
                end
                work.submissionPending[token] = nil
            end
        end
        local total, initial = math.huge, {}
        for id, maximum in pairs(amounts) do
            local item = config().item.byId[id]
            local stock = item and count(item.displayName) or 0
            initial[id] = stock
            local available=work.spendable and work.spendable(id,key)or stock
            total = math.min(total, stock, available, math.max(0, math.floor(maximum)))
        end
        if total == math.huge or total <= 0 then return false end
        local character, serial = player.Character, motion.serial
        local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        local sent, batch = 0, {expected = {}, at = os.clock(), signature = work.signature()}
        for id, stock in pairs(initial) do batch.expected[id] = stock end
        work.submissionPending[token] = batch
        while sent < total and os.clock() < deadline do
            if not work.running(key, character, serial) then break end
            local burst = math.min(8, total - sent)
            for _ = 1, burst do
                call(name, action, argument)
                sent = sent + 1
                for id, stock in pairs(initial) do batch.expected[id] = stock - sent end
            end
            -- Yield for priority checks and replication, rather than sleeping.
            task.wait()
        end
        if sent == 0 then work.submissionPending[token] = nil return false end
        local confirmed = work.await(key, function() return acknowledged(batch) end, 3)
        if confirmed then work.submissionPending[token] = nil work.refreshAt = 0 end
        note(key, confirmed and ("SUBMITTED " .. sent .. " MATERIAL UNITS") or "MATERIAL BATCH SENT; WAITING FOR RECEIPT")
        return confirmed
    end
    function work.smeltBag(key, limits)
        key = key or "smelt"
        local furnace, c = built("Furnace"), config()
        if not furnace or not travel(furnace, key) then return false end
        local acted = false
        for _, row in ipairs({{c.misc.furnaceMatter1Id, "matter1"}, {c.misc.furnaceMatter2Id, "matter2"}}) do
            local item = c.item.byId[row[1]]
            if item and count(item.displayName) > 0 then
                acted = work.submitUnits(key, "Furnace", "addMatter", {[item.id] = math.min(count(item.displayName), limits and (limits[item.id] or 0) or count(item.displayName))}, row[2]) or acted
                if work.preempted then return acted end
            end
        end
        return acted
    end
    function work.bagState()
        local stamp = math.floor(os.clock() * 120)
        local bagId, bonus = player:GetAttribute("bagId"), player:GetAttribute("bagSlotsBonus")
        local cached = work.bagCache
        if cached and cached.stamp == stamp and cached.id == bagId and cached.bonus == bonus and cached.limit == opts.bagLimit then return cached.used, cached.cap end
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
        work.bagCache = {stamp = stamp, id = bagId, bonus = bonus, limit = opts.bagLimit, used = used, cap = cap}
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
        local badMeal=false
        if food and kind=="food"then
            local health=tonumber(food.healthRegen)
            badMeal=health and health<0 or false
            local _,human=root()
            local hunger=human and human.GetAttribute and human:GetAttribute("hunger")
            local maximum=human and human.GetAttribute and(human:GetAttribute("maxHunger")or 100)or 100
            if health==0 and hunger and hunger/math.max(1,maximum)*100>(opts.hunger or 40)then badMeal=true end
        end
        return food and not badMeal and not (kind == "food" and (food.canCook == true
            or work.isCookedFood and not work.isCookedFood(id)))
            and (selectedEmpty(kind) or allowed(kind, id))
            and (kind ~= "cook" or food.canCook == true)
    end
    function work.cookCompatible(id)
        return (not campData.currentFoodId or campData.currentFoodId == id)
            and ((campData.readyCount or 0) == 0 or campData.readyFoodId == id)
    end
    function work.cookReady()
        if not built("Campfire") or (work.stormActive and work.stormActive()) then return false end
        for id, item in pairs(config().item.byId) do
            if work.foodAllowed("cook",id)and work.cookCompatible(id)and(work.spendable and work.spendable(id,"cook")or count(item.displayName))>0 then
                return true
            end
        end
        return false
    end
    function work.cook()
        local rows = config().item.byId
        local ids = {}
        for id, item in pairs(rows) do
            if work.foodAllowed("cook",id)and work.cookCompatible(id)and(work.spendable and work.spendable(id,"cook")or count(item.displayName))>0 then
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
                return work.submitUnits("cook", "MakeFire", "addFood", {[id] = count(rows[id].displayName)}, id)
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
    function work.fireState()
        local fire, scene, c = built("Campfire"), world(), config()
        if not fire then return end
        local rain = scene and scene:FindFirstChild("IsRaining")
        local level = tonumber(fire:GetAttribute("CampfireMeshLevel")) or tonumber(campData.campfireLevel) or 1
        local row
        for _, info in ipairs(c.campfire and c.campfire.list or {}) do if info.lvl == level then row = info break end end
        if not row or not tonumber(row.woodBurnSec) or row.woodBurnSec <= 0 then return end
        local cap = tonumber(campData.campfireLevelCapMins)
        if campData.campfireLevel ~= level or not cap or cap <= 0 then
            local caps, players = row.capMinsPlayerCount, scene and scene:FindFirstChild("PlayerCount")
            cap = type(caps) == "table" and #caps > 0 and tonumber(caps[math.clamp(players and players.Value or 1, 1, #caps)]) or nil
        end
        local on = fire:GetAttribute("onFire")
        if type(on) ~= "boolean" then on = campData.isOnFire end
        local remaining
        if on == false then remaining = 0
        elseif on == true and tonumber(campData.fuelEndTime) and campData.fuelEndTime > 0 then
            remaining = math.max(0, campData.fuelEndTime - workspace:GetServerTimeNow())
        elseif on == true and cap and cap > 0 then
            -- A late-loaded script may have missed the initial sync. Read the game's
            -- existing replicated fuel display without changing its UI or state.
            local bar = fire:FindFirstChild("FireBar")
            local frame = bar and bar:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("progressLabel")
            local percent = label and tonumber(label.Text:match(":%s*(%d+)%s*/%s*100"))
            if percent then remaining = math.clamp(percent, 0, 100) / 100 * cap * 60 end
        end
        return {fire = fire, level = level, burn = row.woodBurnSec,
            cap = cap and cap > 0 and cap * 60 or nil, remaining = remaining,
            on = on, raining = rain and rain.Value == true, wood = campData.campfireWoodCount}
    end
    function work.fireReceipt(before, after)
        return after and (after.level > before.level
            or (after.on == true and before.on == false)
            or (after.remaining and before.remaining and after.remaining > before.remaining + 0.05)
            or (type(after.wood) == "number" and type(before.wood) == "number" and after.wood > before.wood)) or false
    end
    function work.firePendingReady()
        local pending = work.fuelPending
        if not pending then return true end
        if work.fireReceipt(pending.state, work.fireState())
            and count(pending.item.displayName) <= pending.stock - (pending.sent or 1) then
            work.fuelPending = nil return true
        end
        -- An inventory deduction alone does not prove the server added fuel.
        if count(pending.item.displayName) < pending.stock then return false end
        if os.clock() - pending.at >= 3 then work.fuelPending = nil return true end
        return false
    end
    function work.maintenanceGoal()
        local state, item = work.fireState(), work.fuelItem()
        if not state or state.raining or not item or not work.firePendingReady() then return end
        if state.remaining == nil then return end
        local reserve = math.max(1, tonumber(opts.fuel) or 3) * state.burn
        if state.cap then reserve = math.min(reserve, state.cap) end
        if state.on ~= false and state.remaining > reserve * 0.5 then return end
        local room = state.cap and math.max(0, state.cap - state.remaining) or state.burn
        if room < state.burn * 0.5 then return end
        local amount = math.max(1, math.ceil((reserve - state.remaining) / state.burn))
        return {key = "fire:upkeep", kind = "fuel", maintenance = true, level = state.level,
            rank = state.on == false and -0.1 or -0.05, name = "KEEP CAMPFIRE LIT",
            amounts = {[item.id] = amount}}
    end
    function work.addFireWood(key, maximum)
        local item, state = work.fuelItem(), work.fireState()
        if not item or not state or state.raining or count(item.displayName) <= 0
            or not work.firePendingReady() then return false end
        if state.remaining == nil or (state.cap and state.remaining >= state.cap - 0.05) then return false end
        if not work.hover and not travel(state.fire, key) then return false end
        state = work.fireState()
        if not state or state.raining or state.remaining == nil
            or (state.cap and state.remaining >= state.cap - 0.05) then return false end
        local pending = {state = state, item = item, stock = count(item.displayName), at = os.clock()}
        work.fuelPending = pending
        local amount = math.min(count(item.displayName), math.max(1, math.floor(maximum or 1)))
        if state.cap then amount = math.min(amount, math.max(0, math.ceil((state.cap - state.remaining) / state.burn))) end
        if amount <= 0 then work.fuelPending = nil return false end
        local character, serial = player.Character, motion.serial
        for index = 1, amount do
            if not work.running(key, character, serial) then break end
            call("MakeFire", "addWood")
            pending.sent = index
            if index % 8 == 0 then task.wait() end
        end
        local confirmed = work.await(key, function()
            return work.fireReceipt(state, work.fireState())
                and count(item.displayName) <= pending.stock - (pending.sent or 0)
        end, 3)
        if confirmed and count(item.displayName) <= pending.stock - (pending.sent or 0) then
            work.fuelPending = nil work.refreshAt = 0
        end
        note(key, confirmed and "CAMPFIRE FUEL CONFIRMED" or "WAITING FOR CAMPFIRE FUEL CONFIRMATION")
        return confirmed
    end
    function work.fuel()
        local goal = work.maintenanceGoal()
        local item = work.fuelItem()
        if not goal or not item then return false end
        return work.addFireWood("fuel", goal.amounts[item.id])
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
        if work.noFood() and work.takeMeal and not work.takeMeal("eat") then return false end
        local c = config()
        for _, t in ipairs(tools()) do
            local info = c.item.byDisplayName[t.Name]
            if info and work.foodAllowed("food", info.id) then
                equip(t)
                if work.pause and not work.pause("eat",.12)then return false end
                local before = work.signature()
                local health, hungerBefore = h.Health, h:GetAttribute("hunger")
                local previous=work.interaction
                work.interaction={key="eat",untilTime=os.clock()+12}
                t:Activate()
                local confirmed = work.await("eat", function()
                    return work.signature() ~= before or h.Health > health
                        or (hungerBefore and (h:GetAttribute("hunger") or 0) > hungerBefore)
                end,12) -- FoodClient sends eatRemote only after the eat animation completes.
                work.interaction=previous
                note("eat", confirmed and "FOOD USED" or "FOOD USE NOT CONFIRMED")
                return confirmed
            end
        end
        note("eat", "SELECT FOOD YOU OWN")
    end
    function work.markCampDrop(model)
        work.campStash = work.campStash or setmetatable({}, {__mode = "k"})
        if work.campStash[model] then return work.campStash[model] end
        if model:GetAttribute("EXISCampStockpile")==true and model:GetAttribute("ownerName")==player.Name then
            local item=config().item.byDisplayName[model.Name]
            if item then local record={id=item.id,camp=built("Campfire")};work.campStash[model]=record;return record end
        end
        local foodRecord = work.campFoodRecord and work.campFoodRecord(model)
        if foodRecord then work.campStash[model]=foodRecord;return foodRecord end
        local point = pos(model)
        if not point or model:GetAttribute("ownerName") ~= player.Name then return end
        for _, watch in ipairs(work.campDropWatches or {}) do
            if os.clock() <= watch.expires and not watch.before[model]
                and (watch.expected[model.Name] or 0) > 0 and (point - watch.point).Magnitude <= 24 then
                local item = config().item.byDisplayName[model.Name]
                if item then
                    local record = {id = item.id, camp = watch.camp}
                    work.campStash[model] = record
                    if model.SetAttribute then model:SetAttribute("EXISCampStockpile",true)end
                    watch.before[model] = true
                    watch.expected[model.Name] = math.max(0, watch.expected[model.Name] - (tonumber(model:GetAttribute("count")) or 1))
                    return record
                end
            end
        end
    end
    function work.captureCampDrops()
        local watches = work.campDropWatches
        if not watches then return end
        for i = #watches, 1, -1 do if os.clock() > watches[i].expires then table.remove(watches, i) end end
        if #watches > 0 then
            for _, model in ipairs(work.models("drops")) do if model.Parent then work.markCampDrop(model) end end
        end
    end
    function work.stashWanted(model, record)
        local c, goal = config(), work.probingGoal or work.activeGoal or work.objective or work.selectedCraftMaterialGoal()
        if goal and work.taskDemand(record.id, "progression") > 0 then
            if goal.kind == "build" then
                local folder = world() and world():FindFirstChild("Buildings")
                local target = folder and folder:FindFirstChild(goal.info.assetId .. "_Construct")
                return target and work.safeResource(target) or false
            elseif goal.kind == "fuel" then
                local state = work.fireState()
                return state and not state.raining and state.remaining ~= nil
                    and (not state.cap or state.remaining < state.cap) and work.safeResource(state.fire) or false
            elseif goal.kind == "bag" or (goal.kind == "craft" and work.stationGoal(goal)) then
                local _, zone = work.station()
                return zone and work.safeResource(zone) or false
            elseif goal.kind == "quest" then
                local scene = world()
                local npc = scene and scene:FindFirstChild("Mrbeast", true)
                return npc and work.safeResource(npc) or false
            elseif goal.kind == "craft" then return true end
        end
        local food = c.food and c.food.byId[record.id]
        local request=flags.quest and work.questRequirement
        if request and request.itemId==record.id and work.questTotal(request)<request.count then return true end
        if food and flags.stormStock and work.foodCounts then
            local _,_,carried=work.foodCounts()
            if work.isCookedFood(record.id) then return work.mealNeeded() and carried==0 end
            local cooked = work.foodCounts()
            return flags.cook==true and food.canCook and(not work.cookCompatible or work.cookCompatible(record.id))
                and not work.stormActive()and not work.rawFoodOwned()and cooked<work.foodReserveTarget()
        end
        if food and work.noFood() then
            local _, human = root()
            local hunger = human and human:GetAttribute("hunger")
            local maxHunger = human and (human:GetAttribute("maxHunger") or 100) or 100
            return human and (human.Health / human.MaxHealth * 100 <= opts.health
                or (hunger and hunger / maxHunger * 100 <= opts.hunger)) or false
        end
        return false
    end
    function work.questReserved(id)
        local req=flags.quest and work.questRequirement
        return req and req.itemId==id and math.max(0,req.count-#work.questDrops(req))or 0
    end
    function work.spendable(id,key)
        local item=config().item.byId[id]
        local total=item and count(item.displayName)or 0
        -- Critical fire maintenance can use the last fuel; routine processing cannot consume quest stock.
        local urgent=(key=="fuel"or work.activeGoal and work.activeGoal.kind=="fuel"and work.activeGoal.maintenance)and campData.isOnFire==false
        return math.max(0,total-(urgent and 0 or work.questReserved(id)))
    end
    function work.toolKeepCount(tool)
        local c=config();local item=c.item.byDisplayName[tool.Name]
        if not item then return end
        local row=c.tool and((c.tool.byDisplayName or{})[tool.Name]or(c.tool.byId or{})[item.id])
        local light=item.isLightSource or item.id=="torch"or row and tostring(row.toolType):lower():find("torch",1,true)
        if not row and not light and item.type~="tool"then return end
        local function family(it,stats)
            if it.isLightSource or it.id=="torch"or stats and tostring(stats.toolType):lower():find("torch",1,true)then return "light"end
            return stats and stats.useSwapUpgrade~=false and stats.toolType or it.id
        end
        local ownFamily=family(item,row);local best,bestScore
        for _,owned in ipairs(tools())do
            local it=c.item.byDisplayName[owned.Name]
            local stats=it and c.tool and((c.tool.byDisplayName or{})[owned.Name]or(c.tool.byId or{})[it.id])
            if it and family(it,stats)==ownFamily then
                local score=(tonumber(stats and stats.lvl)or 0)*1e6+(tonumber(stats and stats.atkDmg)or tonumber(stats and stats.useDmg)or 0)
                    +(owned.Parent==player.Character and .001 or 0)
                if not bestScore or score>bestScore then best,bestScore=owned,score end
            end
        end
        local keep=best==tool and 1 or 0
        local reserved=work.questReserved(item.id)
        for _,other in ipairs(tools())do
            if other==tool then break end
            if other.Name==tool.Name then reserved=math.max(0,reserved-(tonumber(other:GetAttribute("count"))or 1))end
        end
        return math.max(keep,reserved)
    end
    function work.spareToolCandidate()
        for _,tool in ipairs(tools())do
            local keep=work.toolKeepCount(tool)
            if keep~=nil and (tonumber(tool:GetAttribute("count"))or 1)>keep and work.unloadCount(tool)>0 then return tool end
        end
    end
    function work.tidyTools()
        local camp=work.campDropAnchor()
        if not camp or not work.safeResource(camp)then return false end
        local point=work.campDropPoint(camp)
        if not point or not travel(point,"toolTidy",.5)then return false end
        local r=root();if not r then return false end
        local watch={before={},expected={},point=r.Position,camp=camp,expires=os.clock()+10}
        for _,model in ipairs(work.models("drops"))do watch.before[model]=true end
        work.campDropWatches=work.campDropWatches or{};work.campDropWatches[#work.campDropWatches+1]=watch
        local tool=work.spareToolCandidate();if not tool then return false end
        work.unloadWatch=watch
        local amount=work.batchDrop(tool,work.unloadCount(tool),"toolTidy")
        work.unloadWatch=nil;work.captureCampDrops()
        return amount>0
    end
    function work.unloadCount(tool)
        local c=config();local item=c.item.byDisplayName[tool.Name]
        if not item or not tool.Parent then return 0 end
        local total=math.max(0,tonumber(tool:GetAttribute("count"))or 1)
        local goal=work.probingGoal or work.activeGoal or work.objective or work.selectedCraftMaterialGoal()
        local keep=0
        if goal and goal.kind=="craft"and not work.stationGoal(goal)then
            keep=math.max(0,(work.goalAmounts(goal)[item.id]or 0))
            for _,other in ipairs(tools())do
                if other==tool then break end
                if other.Name==tool.Name then keep=math.max(0,keep-(tonumber(other:GetAttribute("count"))or 1))end
            end
        end
        local reserved=work.questReserved(item.id)
        for _,other in ipairs(tools())do
            if other==tool then break end
            if other.Name==tool.Name then reserved=math.max(0,reserved-(tonumber(other:GetAttribute("count"))or 1))end
        end
        keep=math.max(keep,reserved)
        local free=c.freeBuild and c.freeBuild.byCnId[item.id]
        if free then
            local wall=flags.greatWall and work.wallRecipe and work.wallRecipe()
            local utility=flags.structureCraft and work.structureRole and work.structureRole(item.id,item)~="other"
                and not work.findStructure(nil,item.id)
            if utility or wall and wall.id==item.id then
                local retain=1
                for _,other in ipairs(tools())do if other==tool then break end
                    if other.Name==tool.Name then retain=math.max(0,retain-(tonumber(other:GetAttribute("count"))or 1))end
                end
                keep=math.max(keep,retain)
            end
        end
        local toolKeep=work.toolKeepCount(tool)
        if toolKeep~=nil then return math.max(0,total-math.min(total,math.max(keep,toolKeep)))end
        -- Worn equipment is represented on the character/player rather than a
        -- spare item. Spare bags, armour, torches and loose parts belong at camp.
        if not item.isBagItem and item.type~="tool"and item.type~="armour"and item.type~="bag"
            and item.type~="自由建筑"and not(c.freeBuild and c.freeBuild.byCnId[item.id])
            and not(work.artifactNames and work.artifactNames[tool.Name])then return 0 end
        if c.food and c.food.byId[item.id]and work.foodKeepCount then keep=math.max(keep,work.foodKeepCount(item.id,tool))end
        return math.max(0,total-math.min(total,keep))
    end
    function work.itemGroup(tool)
        local c=config();local item=c.item.byDisplayName[tool.Name]or{}
        if c.food and c.food.byId[item.id]then return "food"end
        if c.tool and c.tool.byId and c.tool.byId[item.id]or item.type=="tool"then return "tools"end
        if item.type=="armour"or item.type=="bag"then return "gear"end
        local name=(tostring(item.id).." "..tool.Name):lower()
        if name:find("iron",1,true)or name:find("铁",1,true)or name:find("stone",1,true)or name:find("石",1,true)then return "mining"end
        if name:find("wood",1,true)or name:find("木",1,true)then return "wood"end
        return "other"
    end
    function work.unloadCandidate()
        for _, tool in ipairs(tools()) do if work.unloadCount(tool) > 0 then return tool end end
    end
    function work.campDropAnchor()
        local fire=built("Campfire")
        if fire then return fire end
        local info=config().build.byId.campfire
        local folder=world()and world():FindFirstChild("Buildings")
        return info and folder and folder:FindFirstChild(info.assetId.."_Construct")or nil
    end
    function work.campIntakeZones()
        local scene = world()
        local cached = work.intakeZones
        if cached and cached.scene == scene and os.clock() < cached.expires then return cached.parts end
        local parts = {}
        for _, part in ipairs(scene and scene:GetDescendants() or {}) do
            if part:IsA("BasePart") and (part.Name == "fireZone" or part.Name == "吸入范围") then parts[#parts + 1] = part end
        end
        work.intakeZones = {scene = scene, parts = parts, expires = os.clock() + 0.5}
        return parts
    end
    function work.campDropClear(point, camp)
        if not point or not work.safeWorkPoint(point) then return false end
        local center = pos(camp)
        local store = flags.useStorage and work.findStructure and work.findStructure("storage")
        if not center or (point - center).Magnitude < (store == camp and 4 or 18) then return false end
        for _, part in ipairs(work.campIntakeZones()) do
            if part.Parent then
                local localPoint = part.CFrame:PointToObjectSpace(point)
                if math.abs(localPoint.X) <= part.Size.X / 2 + 10
                    and math.abs(localPoint.Z) <= part.Size.Z / 2 + 10 then return false end
            end
        end
        return true
    end
    function work.campDropPoint(camp,category)
        local r, human = root()
        local center = pos(camp)
        if not r or not center then return end
        local best, score
        local sector=({wood=0,mining=2,food=4,tools=6,gear=8,other=10})[category]
        local store = flags.useStorage and work.findStructure and work.findStructure("storage")
        local planned=flags.useStorage and not store and work.storagePlannedFrame
        if planned then center=planned.Position end
        for _, radius in ipairs((store == camp or planned) and {8,12,20,32} or {24,32,40,48}) do
            for index = 0, 15 do
                local angle = (sector and(sector+index)%16 or index)*math.pi/8
                local probe = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                local floor = motion.floor(probe, nil, 12, 30)
                local point = floor and floor + Vector3.new(0, human.HipHeight + r.Size.Y / 2, 0)
                if point and work.campDropClear(point, camp) then
                    local distance = (point - r.Position).Magnitude
                    local value=distance+(sector and index*1000 or 0)
                    if not score or value < score then best, score = point, value end
                end
            end
            if best then return best end
        end
    end
    function work.unloadBag()
        local key, camp = "unloadBag", work.campDropAnchor()
        if work.foodCacheCandidate and work.foodCacheCandidate() then return work.cacheFood(key) end
        if flags.structureCraft and flags.useStorage and not work.storagePlannedFrame and work.structureGoal then
            local planned=work.structureGoal()
            if planned and planned.role=="storage" then work.structurePlacement(planned) end
        end
        if not camp or not work.safeResource(camp) then note(key, "WAITING FOR A SAFE CAMPFIRE AREA") return false end
        local used, cap = work.bagState()
        work.unloadRank = used >= cap and 3.08 or 4.05
        -- Native submissions always get first use of the carried materials.
        local acted = work.submitGoal(key, work.activeGoal or work.objective)
        if work.preempted then return acted end
        acted = work.tidyBag(key, true) or acted
        if work.preempted then return acted end
        if flags.structureCraft and work.structureUnloadPrep then acted = work.structureUnloadPrep(key) or acted end
        if work.preempted or not work.unloadCandidate() then return acted end
        if flags.useStorage and work.storeBag then
            while work.unloadCandidate() and work.storeBag(key) do
                acted=true
                if work.preempted then return acted end
            end
            if work.preempted or not work.unloadCandidate() then return acted end
        end
        local first=work.unloadCandidate()
        local category=flags.bulkCollect and first and work.itemGroup(first)
        local point = work.campDropPoint(camp,category)
        if not point or not travel(point, key, 0.5) then
            note(key, "NO SAFE DROP SPOT OUTSIDE CAMP INTAKE") return acted
        end
        local r = root()
        if not r or not work.campDropClear(r.Position, camp) then return acted end
        local watch = {before = {}, expected = {}, point = r.Position, camp = camp, expires = os.clock() + 10}
        for _, model in ipairs(work.models("drops")) do watch.before[model] = true end
        work.campDropWatches = work.campDropWatches or {}
        work.campDropWatches[#work.campDropWatches + 1] = watch
        local character, serial = player.Character, motion.serial
        local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        while work.running(key, character, serial) and os.clock() < deadline do
            local tool = work.unloadCandidate()
            if not tool then break end
            local group=flags.bulkCollect and work.itemGroup(tool)
            if group and group~=category then
                local nextPoint=work.campDropPoint(camp,group)
                if not nextPoint or not travel(nextPoint,key,.5)then return acted end
                local current=root()
                if not current or not work.campDropClear(current.Position,camp)then return acted end
                category=group
                watch={before={},expected={},point=current.Position,camp=camp,expires=os.clock()+10}
                for _,drop in ipairs(work.models("drops"))do watch.before[drop]=true end
                work.campDropWatches[#work.campDropWatches+1]=watch
            end
            work.unloadWatch = watch
            local amount = work.batchDrop(tool, work.unloadCount(tool), key)
            work.unloadWatch = nil
            work.captureCampDrops()
            if amount == 0 then note(key, "WAITING FOR CAMP DROP RECEIPT") return acted end
            acted = true
            work.blockedBag, work.rejectedPickups = nil, 0
            watch.expires = os.clock() + 10
            task.wait()
        end
        work.refreshAt = 0
        note(key, "LEFTOVERS DROPPED AT CAMP; GATHERING CAN RESUME")
        return acted
    end
    function work.dropAllowed(model)
        if not model.Parent or model:GetAttribute("collecting") then return false end
        local stashed = work.markCampDrop(model)
        if stashed and not work.stashWanted(model, stashed) then return false end
        local owner = model:GetAttribute("ownerName")
        if owner and owner ~= player.Name then
            local lock = tonumber(model:GetAttribute("lockedFor_" .. owner)) or 0
            local untilTime = tonumber(model:GetAttribute("protectEndTick")) or 0
            if math.max(lock, untilTime) > workspace:GetServerTimeNow() then return false end
        end
        return true
    end
    function work.interactPrompt(model, key, extraHold)
        local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
        if not prompt then return nil end
        -- Pickup prompts initialize disabled for 0.5s. Do not bypass that setup.
        if not prompt.Enabled then return false end
        local triggered, heldFull = false, false
        local receipt = prompt.Triggered and prompt.Triggered:Connect(function() triggered = true end)
        local duration = math.max(0, tonumber(prompt.HoldDuration) or 0) + math.max(0, tonumber(extraHold) or 0)
        if work.setSprint then work.setSprint(false) end
        local previous = work.interaction
        work.interaction = {key = key, untilTime = os.clock() + duration + 0.75}
        local ok, completed = pcall(function()
            prompt:InputHoldBegin()
            if not work.pause(key, duration) then return false end
            heldFull = true
            -- Triggered can dispatch a frame after HoldDuration. Keep E held
            -- until its receipt instead of releasing on the exact deadline.
            local grace = os.clock() + 0.35
            while not triggered and prompt.Enabled and model.Parent and os.clock() < grace do
                if not work.pause(key, 0.05) then heldFull = false return false end
            end
            return triggered
        end)
        pcall(function() prompt:InputHoldEnd() end)
        if receipt then receipt:Disconnect() end
        work.interaction = previous
        if not ok then error(completed) end
        if not completed then note(key, "E TRIGGER NOT CONFIRMED; CHECKING NATIVE INTERACTION") end
        return completed, heldFull
    end
    function work.collectModel(model, key, bag, chestLoot)
        if not work.dropAllowed(model) or not work.pickupEligible(model) then return false end
        local item = config().item.byDisplayName[model.Name]
        local autoEquip = item and config().misc.useArmourCollectEquip and item.type == "armour"
        local taskPickup = key == "progression" or key == "gather" or key == "drops" or key == "chests"
        if not bag and not chestLoot and taskPickup and item and not work.needsDrop(item.id, key) then return false end
        if not bag and not autoEquip and not work.canCollect() then return false end
        local radius = math.max(0.5, (tonumber(config().misc.collectRadius) or 3) * 1.5)
        local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and prompt.Enabled then radius = math.min(radius, math.max(0.5, prompt.MaxActivationDistance - 1)) end
        local approach = prompt and prompt.Parent or model.PrimaryPart or model
        if approach and approach:IsA("Attachment") then approach = approach.Parent end
        if not travel(approach, key, radius) then return false end
        local before, bagId = count(model.Name), player:GetAttribute("bagId")
        local prompted, heldFull = work.interactPrompt(model, key)
        if prompted == false and not heldFull then return false end
        if prompted ~= true then call("ItemCollect", "collect", model) end
        local confirmed = work.await(key, function()
            return bag and player:GetAttribute("bagId") ~= bagId or count(model.Name) > before
                or autoEquip and not model.Parent
        end, 2)
        if confirmed then
            work.recordPickup(model) work.blockedBag = nil work.rejectedPickups = 0
            if not flags.bulkCollect and not bag and not chestLoot and taskPickup and (work.activeGoal or work.objective) and not work.preempted then
                work.submitGoal(key, work.activeGoal or work.objective)
                work.refreshAt = 0
            end
        end
        return confirmed
    end
    function work.pickupEligible(model)
        local c = config()
        local item = c.item.byDisplayName[model.Name]
        if not item then return false end
        if c.food and c.food.byId[item.id] and work.foodPickupWanted and not work.foodPickupWanted(model,item.id) then return false end
        local bags = c.bag and c.bag.byId or {}
        local bag = bags[item.id]
        if bag then
            local owned = bags[player:GetAttribute("bagId")]
            if owned and (bag.lvl or 0) <= (owned.lvl or 0) then return false end
        end
        local row = c.tool and c.tool.byDisplayName and c.tool.byDisplayName[model.Name]
        if row and row.useSwapUpgrade and row.toolType then
            for _, tool in ipairs(tools()) do
                local owned = c.tool.byDisplayName[tool.Name]
                if owned and owned.useSwapUpgrade and owned.toolType == row.toolType
                    and (owned.lvl or 0) > 0 and (owned.lvl or 0) >= (row.lvl or 0) then return false end
            end
        end
        return true
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
        local center = pos(resource)
        for _, model in ipairs(work.models("drops")) do
            local point = pos(model)
            if center and point and (point - center).Magnitude <= 12 then before[model] = true end
        end
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
                    and (key == "stockpile" or work.needsDrop(info.id, key)) and work.dropAllowed(model) and (point - context.center).Magnitude <= 12
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
                context.collected = context.collected or {} context.collected[target] = true
                quietSince = os.clock()
            else
                if opts.settleTime == 0 then work.watchLateDrops(context) return true end
                local settle = context.seen and (opts.settleTime or 0.12) or math.max(0.5, opts.settleTime or 0.12)
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
    function work.isShadow(model)
        return model and model.Name=="Shadow"
    end
    function work.shadowWeapon()
        local c,best,stats=config()
        for _,tool in ipairs(tools())do
            local item=c.item.byDisplayName[tool.Name]
            local row=c.tool.byDisplayName[tool.Name]
            if item and item.isLightSource and row and not({gun=true,infGun=true,ranged=true})[row.toolType]
                and(not stats or (tonumber(row.range)or 0)>(tonumber(stats.range)or 0))then best,stats=tool,row end
        end
        return best,stats
    end
    function work.mobRemaining(model)
        if work.isShadow(model)then
            local hits=model:FindFirstChild("TorchHits")
            if hits then return math.max(0,(tonumber(model:GetAttribute("TorchHitsMax"))or 3)-(tonumber(hits.Value)or 0))end
        end
        local human=model:FindFirstChildOfClass("Humanoid")
        return human and human.Health or 0
    end
    function work.canHitMob(model,stats)
        if not work.isShadow(model)then return true end
        return flags.killShadow and work.isNight()and stats and select(2,work.shadowWeapon())==stats
    end
    function work.shadowCandidate()
        local tool,stats=work.shadowWeapon()
        if not flags.killShadow or not work.isNight()or not tool then return end
        local r,human=root()
        if not r or human.Health/human.MaxHealth*100<=math.max(60,opts.retreatHealth)then return end
        for _,row in ipairs(work.hostiles())do
            if work.isShadow(row.model)and work.mobRemaining(row.model)>0 and work.insideBorder(row.point)
                and(row.point-r.Position).Magnitude<=opts.huntRadius
                and(not work.combatPosition or work.combatPosition(row.model,stats))then return row.model end
        end
    end
    function work.meleeWeapon(key)
        if key=="shadowHunt"then return work.shadowWeapon()end
        local hunting=key=="hunt"or key=="foodHunt"or work.huntingPassive or work.huntingNeeds~=nil
        local c, best, stats, score = config(), nil, nil, nil
        local r, human = root()
        local crowded = r and select(3, work.danger(r.Position, opts.dangerRadius)) >= 2
        for _, tool in ipairs(tools()) do
            local info = c.tool.byDisplayName[tool.Name]
            local ranged = info and (info.toolType == "gun" or info.toolType == "infGun" or info.toolType == "ranged")
            local ammo=tonumber(tool:GetAttribute("ammo"))
            local item=c.item and c.item.byDisplayName and c.item.byDisplayName[tool.Name]or{}
            local light=item.isLightSource or item.id=="torch"or info and tostring(info.toolType):lower():find("torch",1,true)
            if info and not light and (tonumber(info.atkDmg) or 0) > 0 and (not ranged or info.toolType == "infGun" or ammo == nil or ammo > 0) then
                local value = info.atkDmg / math.max(0.1, tonumber(info.useCd) or 0.7)
                if ranged then
                    value = value + (hunting and -1000 or(crowded or human and human.Health / human.MaxHealth < 0.6)and 1000 or 4)
                elseif info.capAOE and crowded then value = value * math.min(4, info.capAOE) end
                if not ranged and (tonumber(info.useDmg) or 0)>0 then value=value*0.85 end
                if not score or value > score then best, stats, score = tool, info, value end
            end
        end
        return best, stats
    end
    function work.clearSceneIndex()
        local state = work.sceneCache
        if state then for _, connection in ipairs(state.connections) do connection:Disconnect() end end
        work.sceneCache = nil
    end
    function work.sceneIndex()
        local scene = world()
        if not scene then work.clearSceneIndex() return end
        if work.sceneCache and work.sceneCache.scene == scene then return work.sceneCache end
        work.clearSceneIndex()
        local c = config()
        local state = {scene = scene, connections = {}, sets = {}, lists = {}, dirty = {}, folders = {}}
        for _, key in ipairs({"resources", "entities", "drops", "buildings", "chests", "explore", "artifacts", "escape", "stations"}) do
            state.sets[key] = {} state.dirty[key] = true
        end
        for key, name in pairs({resources="Static",entities="Entities",drops="DroppedItems",buildings="Buildings",chests="Chest"}) do
            state.folders[key] = scene:FindFirstChild(name)
        end
        local function add(object)
            if object:IsA("Model") then
                if object.Parent == state.folders.entities then work.threatCacheAt = 0 work.baseThreatAt = 0 end
                for key, folder in pairs(state.folders) do
                    if object.Parent == folder then state.sets[key][object] = true state.dirty[key] = true if key == "drops" then
                        work.lateDropsDirty = true
                        if work.lateDropWatches and next(work.lateDropWatches) and not work.latePollQueued and type(task.defer) == "function" then
                            work.latePollQueued = true
                            task.defer(function() work.latePollQueued = nil if alive then work.pollLateDrops() end end)
                        end
                    end end
                end
                if c.mapProp and c.mapProp.byCnId[object.Name] then state.sets.explore[object] = true state.dirty.explore = true end
                if work.artifactNames and work.artifactNames[object.Name] then state.sets.artifacts[object] = true state.dirty.artifacts = true end
                if object.Name == "制作台" or object.Name == "建筑制作台" then state.sets.stations[object] = true state.dirty.stations = true end
                if c.chest and c.chest.byId[object.Name] then state.sets.chests[object] = true state.dirty.chests = true end
            elseif object:IsA("LocalScript") and object.Name == "BoatEscapeClient" then
                state.sets.escape[object] = true state.dirty.escape = true
            elseif object:IsA("Folder") then
                for key, name in pairs({resources="Static",entities="Entities",drops="DroppedItems",buildings="Buildings",chests="Chest"}) do
                    if object.Parent == scene and object.Name == name then state.folders[key] = object end
                end
            end
        end
        local function remove(object)
            if state.sets.entities[object] then work.threatCacheAt = 0 work.baseThreatAt = 0 end
            for key, set in pairs(state.sets) do
                if set[object] then set[object] = nil state.dirty[key] = true state.lists[key] = nil end
            end
        end
        -- Subscribe before the initial snapshot so streamed additions cannot fall into a scan gap.
        if scene.DescendantAdded and scene.DescendantRemoving then
            state.connections[#state.connections + 1] = scene.DescendantAdded:Connect(add)
            state.connections[#state.connections + 1] = scene.DescendantRemoving:Connect(remove)
        end
        if scene.GetDescendants then for _, object in ipairs(scene:GetDescendants()) do add(object) end end
        work.sceneCache = state
        return state
    end
    function work.models(key)
        local state = work.sceneIndex()
        if not state then return {} end
        -- Small mock / partial environments without descendant signals use their direct folders.
        if #state.connections == 0 then
            local folder = state.folders[key]
            if folder and folder.GetChildren then return folder:GetChildren() end
        end
        if state.dirty[key] then
            local list = {}
            for object in pairs(state.sets[key] or {}) do if object.Parent then list[#list + 1] = object end end
            state.lists[key], state.dirty[key] = list, false
        end
        return state.lists[key] or {}
    end
    function work.captureEvadeIntent()
        local focus = work.resourceFocus
        if focus and focus.model and focus.model.Parent and (work.active == focus.key or work.active == "recoverDrops") then
            work.evadeIntent = {kind = "resource", key = focus.key, model = focus.model,
                resourceKind = focus.kind, neededOnly = focus.neededOnly}
        elseif work.active == "recoverDrops" and work.treeDrops then
            local context = work.treeDrops
            work.evadeIntent = {kind = "resource", key = context.key, model = nil,
                resourceKind = context.resourceKind, neededOnly = context.key == "progression"}
        elseif work.active == "drops" or work.active == "foodPickup" then
            work.evadeIntent = {kind = "drop", key = work.active, model = work.interactionTarget}
        else
            work.evadeIntent = nil
        end
    end
    function work.borderState()
        -- The server expands this ring when the campfire's wall level changes.
        local wall = workspace:FindFirstChild("Wall")
        if wall then
            local center, radius = wall:GetAttribute("Center"), tonumber(wall:GetAttribute("Radius"))
            if typeof(center) == "Vector3" and radius and radius > 0 then return center, radius end
        end
        local scene, c = world(), config()
        local fire = built("Campfire")
        local level = fire and tonumber(fire:GetAttribute("CampfireMeshLevel")) or tonumber(campData.campfireLevel) or 1
        local progress = 1
        for _, row in ipairs(c.campfire and c.campfire.list or {}) do
            if row.lvl == level then progress = tonumber(row.wall_lvl) or 1 break end
        end
        local onlyLevelOne = c.campfire and #c.campfire.list == 1 and c.campfire.list[1].lvl == 1
        local unlocked = onlyLevelOne and fire and (fire:GetAttribute("onFire") == true or campData.isOnFire == true)
        if not wall and (progress >= 5 or unlocked) then return Vector3.new(0, 0, 0), math.huge end
        local tiles = scene and scene:FindFirstChild("Tiles")
        local base = tiles and tiles:FindFirstChild("Basic Block")
        local center = base and pos(base)
        local names = {"开局圈", "神器1条带", "神器2条带", "神器3条带", "外圈条带"}
        local band = c.mapBand and c.mapBand.byCn and c.mapBand.byCn[names[progress]]
        local length = scene and tonumber(scene:GetAttribute("IslandLength"))
        if center and band and length and length > 0 and tonumber(band.rateMax) then
            return center, band.rateMax * length
        end
        -- Unknown / still streaming is not permission to leave the unlocked area.
        return nil
    end
    function work.insideBorder(point, margin, key)
        if not point then return false end
        local context=key or work.readinessKey or work.active or motion.owner
        if opts.exploreOutsideBorder and({chests=true,puzzles=true,artifacts=true,travel=true})[context or""]then return true end
        local center, radius = work.borderState()
        if not center then return false end
        local dx, dz = point.X - center.X, point.Z - center.Z
        return dx * dx + dz * dz <= math.max(0, radius - (margin or 2)) ^ 2
    end
    function work.meleeClearance(target, stats)
        local info=work.mobInfo and work.mobInfo(target)or config().mob and config().mob.byId[target.Name]
        if info and not work.isHostile(target, info) then return 0.5 end
        local reach = work.enemyReach(target) + opts.combatMargin
        -- Short tools cannot provide invulnerability. Use their outer attack edge,
        -- keep other enemies away, and retain the damage / low-health retreat.
        if stats and (stats.range or 6) <= reach + 0.1 then
            return math.max(0.5, (stats.range or 6) - 0.65)
        end
        return reach
    end
    function work.safeWorkPoint(point, margin)
        if not work.insideBorder(point) then return false end
        if opts.avoidEnemies and work.threatEnvelope and work.threatEnvelope(point,1.25)<(margin or 0)then return false end
        for _, row in ipairs(work.hostiles()) do
            if row.model.Parent and row.human.Health > 0 then
                local radius = opts.avoidEnemies and opts.dangerRadius + (margin or 0) or 0
                if flags.runShadow and (not row.attackable or row.model.Name:lower():find("shadow", 1, true)) then
                    radius = math.max(radius, opts.shadowRadius + (margin or 0))
                end
                if radius > 0 and (point - row.point).Magnitude < radius and math.abs(point.Y - row.point.Y) < 18 then return false end
            end
        end
        return true
    end
    function work.resourceEligible(model, key, neededOnly)
        if not model.Parent or not model:IsA("Model") or (motion.blocked[model] and motion.blocked[model] > os.clock()) then return false end
        local id = model:GetAttribute("resourceId")
        local info = id and config().worldResource.byId[id]
        local hp = model:GetAttribute("hp")
        local kind=info and work.resourceKind(info)
        local explicit=not neededOnly and ((kind=="tree"and flags.chopTrees)or(kind=="stone"and flags.mineStone)or(kind=="iron"and flags.mineIron))
        return info and (type(hp) ~= "number" or hp > 0) and work.resourceAllowed(info, key)
            and work.resourceTool(info) ~= nil and (key == "stockpile" or explicit or not (neededOnly or opts.onlyNeeded) or (work.resourceNeeds[id] or 0) > 0)
            and (key == "stockpile" or neededOnly or not flags.gather or selectedEmpty("resources") or allowed("resources", id))
            and work.safeResource(model) and not (failed[model] and failed[model] > os.clock())
    end
    function work.alternativeWork(intent)
        if not intent or not work.keyEnabled(intent.key) or not work.canCollect() then return end
        local r = root()
        if not r then return end
        local best, bestScore
        local candidates = intent.kind == "resource" and work.models("resources") or work.models("drops")
        for _, model in ipairs(candidates) do
            if model ~= intent.model and model.Parent then
                local eligible = intent.kind == "resource" and work.resourceEligible(model, intent.key, intent.neededOnly)
                if intent.kind == "drop" then
                    local item = config().item.byDisplayName[model.Name]
                    eligible = item and work.dropAllowed(model) and work.safeResource(model)
                        and (intent.key ~= "foodPickup" or config().food.byId[item.id] ~= nil)
                        and (intent.key == "foodPickup" or not opts.onlyNeeded or work.needs[item.id])
                        and (intent.key == "foodPickup" or selectedEmpty("drops") or allowed("drops", item.id))
                end
                if eligible then
                    local score = -(pos(model) - r.Position).Magnitude
                    if intent.kind == "resource" then
                        local info = config().worldResource.byId[model:GetAttribute("resourceId")]
                        if work.resourceKind(info) == intent.resourceKind then score = score + 10000 end
                        score = score + (work.resourceNeeds[model:GetAttribute("resourceId")] or 0) * 100
                    end
                    if not bestScore or score > bestScore then best, bestScore = model, score end
                end
            end
        end
        return best
    end
    function work.retargetEvade(key)
        local intent = work.evadeIntent
        local target = work.alternativeWork(intent)
        if not target then return false end
        local before = root()
        if not before then return false end
        local reach = 2.5
        if intent.kind == "resource" then
            local info = config().worldResource.byId[target:GetAttribute("resourceId")]
            local _, stats = work.resourceTool(info)
            reach = math.max(1, (stats and stats.range or 6) - 0.5)
        end
        work.retargeting = true
        local ok, moved = pcall(travel, target, key, reach, opts.evadeMove)
        work.retargeting = nil
        if not ok then error(moved) end
        if moved then
            work.preferredTargets = work.preferredTargets or {}
            work.preferredTargets[intent.key] = target
            work.evadeIntent = nil
            work.refreshAt = 0
            note(key, "SAFE ALTERNATIVE FOUND • RESUMING " .. intent.key:upper())
            return true
        end
        return false
    end
    function work.batchDrop(tool, requested, key)
        work.pendingDrops = work.pendingDrops or setmetatable({}, {__mode = "k"})
        local function acknowledged(batch)
            for _, record in ipairs(batch.records) do
                local item = record.tool
                if item.Parent and (tonumber(item:GetAttribute("count")) or 1) > record.before - record.amount then return false end
            end
            return true
        end
        local function clear(batch)
            for _, record in ipairs(batch.records) do work.pendingDrops[record.tool] = nil end
            work.activeDropBatch = nil work.invalidateInventory()
        end
        if work.activeDropBatch then
            local previous = work.activeDropBatch
            if not work.await(key, function() return acknowledged(previous) end, 3) then return 0 end
            clear(previous)
        end
        local budget = math.min(8, math.max(0, requested))
        if budget <= 0 or not work.checkpoint(key) then return 0 end
        local batch, seen = {records = {}, total = 0}, {}
        local function add(item)
            if seen[item] or not item.Parent or item.Name ~= tool.Name or batch.total >= budget then return end
            seen[item] = true
            local before = tonumber(item:GetAttribute("count")) or 1
            local amount = math.min(budget - batch.total, before)
            if amount > 0 then batch.records[#batch.records + 1] = {tool = item, before = before, amount = amount} batch.total = batch.total + amount end
        end
        add(tool)
        for _, owned in ipairs(tools()) do add(owned) end
        if batch.total == 0 then return 0 end
        work.activeDropBatch = batch
        for _, record in ipairs(batch.records) do
            work.pendingDrops[record.tool] = batch
            if work.unloadWatch then
                local watch = work.unloadWatch
                watch.expected[record.tool.Name] = (watch.expected[record.tool.Name] or 0) + record.amount
                watch.expires = os.clock() + 10
            end
            for _ = 1, record.amount do call("PlayerInventory", "dropItem", record.tool) end
        end
        if not work.await(key, function() return acknowledged(batch) end, 3) then return 0 end
        clear(batch)
        return batch.total
    end
    function work.watchLateDrops(context)
        work.lateDropWatches = work.lateDropWatches or {}
        context.watchUntil = os.clock() + 3
        work.lateDropWatches[context] = true
        work.lateDropsDirty = true
    end
    function work.contextEnabled(key)
        if key=="questAcquire"then return flags.quest end
        if key == "gather" then return flags.gather or flags.chopTrees or flags.mineStone or flags.mineIron end
        if key == "progression" then return work.progressionEnabled() end
        return flags[key]
    end
    function work.rotateRecoveries()
        local queue = work.dropQueue or {}
        local current = work.treeDrops
        if current and work.safeWorkPoint(current.center, 5) then return end
        for i, context in ipairs(queue) do
            if work.contextEnabled(context.key) and work.safeWorkPoint(context.center, 5) then
                table.remove(queue, i)
                if current and current ~= context and not current.queued then current.queued = true queue[#queue + 1] = current end
                work.treeDrops, context.queued = context, nil
                return
            end
        end
    end
    function work.setRecovery(context)
        if work.treeDrops and work.treeDrops ~= context and not work.treeDrops.queued then
            work.dropQueue = work.dropQueue or {}
            work.treeDrops.queued = true work.dropQueue[#work.dropQueue + 1] = work.treeDrops
        end
        work.treeDrops = context
    end
    function work.pollLateDrops()
        local watches = work.lateDropWatches
        if not watches then return end
        local dirty = work.lateDropsDirty
        work.lateDropsDirty = nil
        for context in pairs(watches) do
            if os.clock() > context.watchUntil or not work.contextEnabled(context.key) then
                watches[context] = nil
            elseif dirty then
                for _, model in ipairs(work.models("drops")) do
                    local item = config().item.byDisplayName[model.Name]
                    if model.Parent and item and context.wanted[item.id] and work.needsDrop(item.id, context.key)
                        and not context.before[model]
                        and not (context.collected and context.collected[model]) and pos(model)
                        and (pos(model) - context.center).Magnitude <= 12 and work.dropAllowed(model) then
                        work.dropQueue = work.dropQueue or {}
                        if work.treeDrops ~= context and not context.queued then
                            if not work.treeDrops then work.treeDrops = context
                            else context.queued = true work.dropQueue[#work.dropQueue + 1] = context end
                        end
                        watches[context] = nil
                        break
                    end
                end
            end
        end
    end
    function work.mobInfo(model)
        local mobs=config().mob or{}
        for _,attribute in ipairs({"mobId","MobId","configId","entityId"})do
            local id=model.GetAttribute and model:GetAttribute(attribute)
            if id and mobs.byId and mobs.byId[id]then return mobs.byId[id]end
        end
        if work.mobLookupSource~=mobs then
            work.mobLookupSource,work.mobLookup=mobs,{}
            for key,info in pairs(mobs.byId or{})do
                if type(info)=="table"then
                    work.mobLookup[tostring(key):lower()]=info
                    for _,field in ipairs({"id","name","displayName","assetId","modelName"})do
                        if type(info[field])=="string"then work.mobLookup[info[field]:lower()]=info end
                    end
                end
            end
            for _,index in ipairs({mobs.byName or{},mobs.byDisplayName or{}})do
                for key,info in pairs(index)do if type(info)=="table"then work.mobLookup[tostring(key):lower()]=info end end
            end
        end
        local name=model.Name:lower();local info=work.mobLookup[name]
        if info then return info end
        if name:find("chicken",1,true)or name:find("crab",1,true)then return{passive=true,isHostile=false}end
    end
    function work.isHostile(model, info)
        info = info or {}
        local identity = (tostring(info.mobClass or "") .. " " .. model.Name):lower()
        if identity:find("shadow", 1, true) then return work.isNight() end
        if identity:find("ghost", 1, true) then return true end
        for _, key in ipairs({"Hostile", "Aggressive", "CanAttack"}) do
            local value = model:GetAttribute(key)
            if type(value) == "boolean" then return value end
        end
        if info.passive == true or info.isPassive == true or info.isHostile == false
            or info.canAttack == false or info.aggressive == false then return false end
        -- These native wildlife are food animals, not enemies to evade.
        if identity:find("chicken", 1, true) or identity:find("crab", 1, true) then return false end
        if info.isHostile == true or info.aggressive == true then return true end
        local damage = tonumber(info.atkDmg) or tonumber(info.attackDamage)
        if damage ~= nil and damage <= 0 then return false end
        -- Unknown creatures remain conservative until config/attributes say passive.
        return true
    end
    function work.creatures(force)
        if not force and os.clock() < (work.creatureCacheAt or 0) then return work.creatureCache or {} end
        local rows, c = {}, config()
        for _, model in ipairs(work.models("entities")) do
            local human, point = model:FindFirstChildOfClass("Humanoid"), pos(model)
            local info=(work.mobInfo and work.mobInfo(model)or c.mob and c.mob.byId[model.Name])or{}
            if human and human.Health > 0 and point and not Players:GetPlayerFromCharacter(model)
                and(not work.mobRemaining or work.mobRemaining(model)>0)then
                local part = model:FindFirstChild("HumanoidRootPart")
                rows[#rows + 1] = {model = model, human = human, point = point,
                    velocity = part and part.AssemblyLinearVelocity or Vector3.new(0, 0, 0),
                    hostile = work.isHostile(model, info), attackable = human.Health < 10000 or(work.isShadow and work.isShadow(model)and flags.killShadow and work.shadowWeapon()~=nil)}
            end
        end
        work.creatureCache, work.creatureCacheAt = rows, os.clock() + 0.04
        return rows
    end
    function work.hostiles(force)
        if not force and os.clock() < (work.threatCacheAt or 0) then return work.threatCache or {} end
        local rows = {}
        for _, row in ipairs(work.creatures(force or (work.threatCacheAt or 0) == 0)) do if row.hostile then rows[#rows + 1] = row end end
        work.threatCache, work.threatCacheAt = rows, os.clock() + 0.04
        return rows
    end
    function work.projectedEnemyGap(row,point,lead)
        local delta=Vector3.new(point.X-row.point.X,0,point.Z-row.point.Z)
        local velocity=row.velocity or Vector3.new(0,0,0)
        velocity=Vector3.new(velocity.X,0,velocity.Z)
        local speed2=velocity:Dot(velocity)
        local time=speed2>0 and math.clamp(delta:Dot(velocity)/speed2,0,lead or 1.25)or 0
        return(delta-velocity*time).Magnitude,delta.Magnitude
    end
    function work.threatEnvelope(point,lead)
        local margin,nearest,seen=math.huge,nil,0
        for _,row in ipairs(work.hostiles())do
            if row.model.Parent and row.human.Health>0 and math.abs(point.Y-row.point.Y)<24 then
                local gap,distance=work.projectedEnemyGap(row,point,lead)
                if distance<=(opts.threatScanRadius or 180)then
                    seen=seen+1
                    local radius=math.max(opts.dangerRadius or 20,work.enemyReach(row.model)+(opts.combatMargin or 1)+4)
                    if not row.attackable or row.model.Name:lower():find("shadow",1,true)then radius=math.max(radius,opts.shadowRadius or 60)end
                    if gap-radius<margin then margin,nearest=gap-radius,row.model end
                end
            end
        end
        return margin,nearest,seen
    end
    function work.incomingThreat(point)
        local margin,target=work.threatEnvelope(point,1.25)
        if margin<=2 then return target end
    end
    function work.danger(point, radius, ignore)
        if not point then return math.huge, nil, 0 end
        local risk, closest, count, distance = 0, nil, 0, math.huge
        for _, row in ipairs(work.hostiles()) do
            if row.model ~= ignore and row.model.Parent and row.human.Health > 0 then
                local delta = point - row.point
                local d=work.projectedEnemyGap and work.projectedEnemyGap(row,point,1.25)or delta.Magnitude
                if d < radius and math.abs(delta.Y) < 24 then
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
    function work.combatUrgent()
        local r,human=root()
        if not r or not human or human.Health<=0 then return false end
        for _,row in ipairs(work.hostiles())do
            if row.attackable and row.model.Parent and row.human.Health>0 and not(work.isShadow and work.isShadow(row.model))then
                local gap=(row.point-r.Position).Magnitude
                if gap<=work.enemyReach(row.model)+3 then return true end
            end
        end
        local target=work.baseThreat and work.baseThreat()
        local fire=built("Campfire")
        local point=target and pos(target);local center=fire and pos(fire)
        return point and center and(point-center).Magnitude<=16 or false
    end
    function work.counterWindow(target,key)
        local r,human=root()
        if not r or not human or human.Health/human.MaxHealth*100<=math.max(60,opts.retreatHealth)
            or os.clock()<(work.damageUntil or 0)or os.clock()<(work.evadeRecoverUntil or 0)then return false end
        if work.attackPhase and work.attackPhase(target)=="strike"then return false end
        if select(3,work.danger(r.Position,opts.dangerRadius))>=3 then return false end
        local commit=work.attackCommit
        if commit and commit.target==target and os.clock()<commit.expires then
            return human.Health>=commit.health
        end
        if os.clock()<(work.nextStrikeAt or 0)then return false end
        local _,stats=work.meleeWeapon(key)
        return stats and work.stanceScore(r.Position,target,stats,true)~=nil or false
    end
    function work.personalThreat()
        local shadow = work.shadowThreat()
        if not shadow and flags.killShadow and work.shadowCandidate then shadow=work.shadowCandidate()end
        if shadow then
            local fight=work.shadowCandidate and work.shadowCandidate()==shadow
            local r,human=root()
            local crowded=r and select(3,work.danger(r.Position,opts.dangerRadius))>1
            local striking=work.attackPhase and work.attackPhase(shadow)=="strike"
            if fight and not striking and not crowded and human.Health/human.MaxHealth*100>math.max(60,opts.retreatHealth)
                and os.clock()>=(work.damageUntil or 0)then return end
            return shadow
        end
        if not opts.avoidEnemies then return end
        local r, human = root()
        if not r then return end
        local _, target = work.danger(r.Position, opts.dangerRadius)
        local damaged = work.observedHealth and human.Health < work.observedHealth
        work.observedHealth = human.Health
        if damaged then work.damageUntil = os.clock() + 1 end
        local incoming=work.incomingThreat and work.incomingThreat(r.Position)
        if incoming and not work.hover then
            local phase=work.attackPhase and work.attackPhase(incoming)or "unknown"
            local fighting=work.active=="combat"or work.active=="hunt"or work.active=="autoAttack"
            -- A healthy native-range counter may finish one real hit window.
            -- Keep evasion for distant predicted contact, actual strike phases,
            -- new damage, low health and crowds; unknown animation alone must
            -- not cancel every swing before its native hit window.
            if (fighting or flags.combat or flags.autoAttack)and work.counterWindow
                and work.counterWindow(incoming,work.active)then return end
            if not fighting or(phase~="windup"and phase~="recovery")or os.clock()<(work.evadeRecoverUntil or 0)
                or human.Health/human.MaxHealth*100<=math.max(opts.retreatHealth or 35,60)then return incoming end
        end
        if not target then return end
        if work.attackPhase and work.attackPhase(target)=="strike" then
            local p=pos(target)
            if p and Vector3.new(r.Position.X-p.X,0,r.Position.Z-p.Z).Magnitude <= work.enemyReach(target)+3 then return target end
        end
        if work.hover then return end -- the independent hover guard handles movement; ground evasion cannot move an anchored root.
        local fighting = work.active == "combat" or work.active == "hunt" or work.active == "autoAttack" or work.huntingNeeds ~= nil
        if not fighting then
            if (flags.combat or flags.aura or flags.autoAttack) and human.Health / human.MaxHealth * 100 > opts.retreatHealth
                and os.clock() >= (work.damageUntil or 0) then
                local _, stats = work.meleeWeapon()
                if stats then
                    local candidate = work.attackPlan("combat", stats)
                    if candidate or work.retaliationTarget and work.retaliationTarget(stats) then return end
                end
            end
            return target
        end
        local _, stats = work.meleeWeapon()
        if human.Health / human.MaxHealth * 100 <= opts.retreatHealth
            or (os.clock() < (work.damageUntil or 0) and select(3, work.danger(r.Position, opts.dangerRadius)) >= 3) then return target end
        if stats then
            if work.combatClear(r.Position) then return end
            local candidate = work.attackPlan(work.active == "combat" and "combat" or work.active, stats)
            if candidate or work.retaliationTarget and work.retaliationTarget(stats) then return end
        end
        return target
    end
    function work.baseThreat()
        if os.clock() < (work.baseThreatAt or 0) and os.clock() < (work.threatCacheAt or 0)
            and work.baseThreatRows == work.threatCache and (not work.baseThreatCache
                or (work.baseThreatCache.Parent and work.baseThreatHuman and work.baseThreatHuman.Health > 0)) then return work.baseThreatCache end
        work.baseThreatAt = os.clock() + 0.03
        local fire = built("Campfire")
        local center = fire and pos(fire)
        if not center then return end
        local scene = world()
        local buildings = scene and scene:FindFirstChild("Buildings")
        local buildingPoints = {}
        for _, building in ipairs(work.models("buildings")) do
            local point = pos(building) if point then buildingPoints[#buildingPoints + 1] = point end
        end
        local best, bestScore
        for _, row in ipairs(work.hostiles()) do
            if row.attackable and row.model.Parent and row.human.Health > 0 then
                local distance = (row.point - center).Magnitude
                local nearBuilding = false
                for _, point in ipairs(buildingPoints) do
                    if (row.point - point).Magnitude < 14 then nearBuilding = true break end
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
        work.baseThreatCache = best
        work.baseThreatRows = work.threatCache
        work.baseThreatHuman = best and best:FindFirstChildOfClass("Humanoid") or nil
        return best
    end
    function work.safeDestination(point, key)
        if not work.insideBorder(point,nil,key) then return false end
        local owner = work.active or key
        local risk = work.danger(point, opts.dangerRadius)
        if owner == "evade" or work.escapeMove then
            if work.threatEnvelope and work.threatEnvelope(point,1.25)<0 then return false end
            if work.retargeting then return work.safeWorkPoint(point, 0) end
            local r = root()
            return r and risk <= work.danger(r.Position, opts.dangerRadius)
        end
        if owner == "combat" or owner == "hunt" or owner=="foodHunt"or owner=="shadowHunt"or work.huntingNeeds~=nil then return work.combatClear(point) end
        return work.safeWorkPoint(point, 0)
    end
    function work.combatClear(point)
        if not work.insideBorder(point,nil,"combat") then return false end
        for _, row in ipairs(work.hostiles()) do
            if row.model.Parent and row.human.Health > 0 then
                local delta = point - row.point
                local elevatedTarget = false
                local clearance = row.model == work.attackTarget and work.meleeClearance(row.model, work.attackStats) or work.enemyReach(row.model) + opts.combatMargin
                if not elevatedTarget and Vector3.new(delta.X,0,delta.Z).Magnitude < clearance then return false end
            end
        end
        return true
    end
    function work.safeRoute(a, b, key)
        -- A circle is convex: an inside-to-inside segment cannot cross the ring.
        if not work.insideBorder(b,nil,key)then return false end
        if not work.insideBorder(a,nil,key)and key~="evade"then return false end
        if (motion.mode or opts.move) == "Teleport" then return work.safeDestination(b, key) end
        local delta, owner = b - a, work.active or key
        local length2 = delta:Dot(delta)
        for _, row in ipairs(work.hostiles()) do
            if row.model.Parent and row.human.Health > 0 then
                local t = length2 > 0 and math.clamp((row.point - a):Dot(delta) / length2, 0, 1) or 0
                local closest = a + delta * t
                local distance=(closest-row.point).Magnitude
                if work.projectedEnemyGap then distance=math.min(distance,work.projectedEnemyGap(row,closest,1.25))end
                local radius = opts.avoidEnemies and opts.dangerRadius or 0
                if flags.runShadow and (not row.attackable or row.model.Name:lower():find("shadow", 1, true)) then radius = math.max(radius, opts.shadowRadius) end
                if owner == "evade" or work.escapeMove then
                    local initial = (a - row.point).Magnitude
                    if radius > 0 and ((initial < radius and distance + 0.1 < initial) or (initial >= radius and distance < radius)) then return false end
                elseif owner == "combat" or owner == "hunt" or owner=="foodHunt"or owner=="shadowHunt"or work.huntingNeeds~=nil then
                    local elevated = false
                    local clearance = row.model == work.attackTarget and work.meleeClearance(row.model, work.attackStats) or work.enemyReach(row.model) + opts.combatMargin
                    if not elevated and distance < clearance then
                        local initial=(a-row.point).Magnitude
                        if distance+.1<initial or(b-row.point).Magnitude<=initial then return false end
                    end
                elseif radius > 0 and distance < radius and math.abs(closest.Y - row.point.Y) < 18 then return false end
            end
        end
        return true
    end
    function work.safeResource(model)
        return work.safeWorkPoint(pos(model), 5)
    end
    function work.evade(key)
        key = key or "evade"
        local r, human = root()
        if not r then return false end
        local radius = work.shadowThreat() and opts.shadowRadius or opts.dangerRadius
        local currentRisk, nearestEnemy = work.danger(r.Position, radius)
        local incoming=work.incomingThreat and work.incomingThreat(r.Position)
        if currentRisk==0 and not incoming then work.evadeIntent=nil;return true end
        if work.retargetEvade(key)then work.evadeRecoverUntil=os.clock()+2;return true end
        local best, bestScore
        local lift = math.max(2, human.HipHeight + r.Size.Y / 2)
        local function consider(probe)
            local ground = motion.floor(probe, nil, math.max(10, (opts.hoverHeight or 8) + 12), 5)
            if not ground then return end
            local candidate = ground + Vector3.new(0, lift, 0)
            if not work.insideBorder(candidate)or(opts.evadeMove~="Teleport"and not motion.clearSegment(r.Position,candidate,nil))then return end
            local risk=work.danger(candidate,radius)
            local clearance=work.threatEnvelope and work.threatEnvelope(candidate,1.25)or 0
            if clearance<3 or(currentRisk>0 and risk>=currentRisk)then return end
            local score=-risk*100+math.min(50,clearance)*2-(candidate-r.Position).Magnitude*.15
            if not bestScore or score > bestScore then best, bestScore = candidate, score end
        end
        for _, distance in ipairs({24,40,64,96,144})do
            for i=0,15 do
                local angle=i*math.pi/8
                consider(r.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
            end
        end
        if not best then
            note(key, "NO CHECKED DRY ESCAPE ROUTE; STOPPING UNSAFE WORK")
            return false
        end
        note(key,"PREEMPTIVE EVADE • CHECKED PRESENT AND PREDICTED HOSTILE POSITIONS")
        local moved = travel(best, key, 1, opts.evadeMove)
        work.threatCacheAt = 0
        work.safeUntil=os.clock()+.1
        if moved then work.evadeRecoverUntil=os.clock()+2 end
        return moved
    end
    function work.enemy(radius, hunting)
        local r = root()
        if not r then return end
        local best, distance
        for _, row in ipairs((hunting and work.creatures() or work.hostiles())) do
            local d = (row.point - r.Position).Magnitude
            if row.attackable and (not work.isShadow or not work.isShadow(row.model)) and row.model.Parent and row.human.Health > 0 and work.insideBorder(row.point) and d <= radius
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
        local info=work.mobInfo and work.mobInfo(target)or config().mob and config().mob.byId[target.Name]
        local configured = tonumber(target:GetAttribute("AttackRange")) or info and (tonumber(info.attackRange) or tonumber(info.atkRange))
        return configured and configured > 0 and configured or opts.enemyReach
    end
    function work.hitVerticalGap(point,target)
        local at=pos(target)
        if target.GetBoundingBox then
            local ok,frame,size=pcall(target.GetBoundingBox,target)
            if ok and frame and size then return math.max(0,math.abs(point.Y-frame.Position.Y)-size.Y/2)end
        end
        return math.max(0,math.abs(point.Y-at.Y)-1)
    end
    function work.stanceScore(point, target, stats, retaliation)
        local p = pos(target)
        if work.canHitMob and not work.canHitMob(target,stats)then return end
        if not p or not work.insideBorder(p,nil,"combat")or not work.insideBorder(point,nil,"combat")then return end
        local delta = point - p
        local ranged = stats.toolType == "gun" or stats.toolType == "infGun" or stats.toolType == "ranged"
        local distance = ranged and delta.Magnitude or Vector3.new(delta.X, 0, delta.Z).Magnitude
        if not ranged and work.isPassiveFood and work.isPassiveFood(target)then
            local gap=work.hitVerticalGap and work.hitVerticalGap(point,target)or math.max(0,math.abs(delta.Y)-1)
            if math.sqrt(distance^2+gap^2)>(stats.range or 6)-.25 then return end
            -- Match MeleeClient's real part overlap. A model bounding box can
            -- include empty space above a crab and falsely report it in range.
            if workspace.GetPartBoundsInRadius then
                local params=OverlapParams.new()
                params.FilterType=Enum.RaycastFilterType.Include
                params.FilterDescendantsInstances={target}
                local touching=false
                for _,part in ipairs(workspace:GetPartBoundsInRadius(point,math.max(.1,(stats.range or 6)-.25),params))do
                    if part:FindFirstAncestorOfClass("Model")==target then touching=true break end
                end
                if not touching then return end
            end
        end
        if math.abs(delta.Y) > math.max(6, tonumber(stats.range) or 6) or distance > (stats.range or 6) - 0.1 or not work.lineOfSight(point, target) then return end
        if retaliation then return distance end
        local elevated = false
        local outside = distance >= work.meleeClearance(target, stats)
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
    function work.retaliationTarget(stats)
        local r=root()
        if not r or not stats then return end
        for _,row in ipairs(work.hostiles()) do
            if row.attackable and work.stanceScore(r.Position,row.model,stats,true)
                and work.attackPhase(row.model) ~= "strike" then return row.model end
        end
    end
    function work.combatPosition(target, stats)
        local r, human = root()
        local point = pos(target)
        if not r or not point then return end
        local best, score = r.Position, work.stanceScore(r.Position, target, stats)
        if not score then best = nil end
        local ranged = stats.toolType == "gun" or stats.toolType == "infGun" or stats.toolType == "ranged"
        local passive=not ranged and work.isPassiveFood and work.isPassiveFood(target)
        if score and (ranged or passive) then return best, score end
        local radius = math.max(.6,ranged and math.min((stats.range or 20)-1,20)or(stats.range or 6)-.75)
        if not ranged and work.isPassiveFood and work.isPassiveFood(target)then
            local vertical=work.hitVerticalGap and work.hitVerticalGap(r.Position,target)or math.max(0,math.abs(r.Position.Y-point.Y)-1)
            radius=math.max(.6,math.min(radius,math.sqrt(math.max(0,(stats.range or 6)^2-vertical^2))-.6))
        end
        if not ranged and not passive then
            radius=math.min((stats.range or 6)-.2,math.max(radius,work.meleeClearance(target,stats)+.1))
        end
        local lift = math.max(2, human.HipHeight + r.Size.Y / 2)
        -- Recheck inner rings at the destination's floor height. Small animals
        -- on slopes may be unreachable from the outer ring even on level ground.
        for ring = 1, passive and 4 or 1 do
            local approachRadius=radius*(1-(ring-1)*.25)
            for index = 0, 15 do
                local angle = index * math.pi / 8
                local probe = point + Vector3.new(math.cos(angle) * approachRadius, 0, math.sin(angle) * approachRadius)
                local ground = motion.floor(probe, target, 12, radius + 4)
                if ground then
                    local candidate = ground + Vector3.new(0, lift, 0)
                    local rank = work.stanceScore(candidate, target, stats)
                    if rank and (opts.move == "Teleport" or motion.clearSegment(r.Position, candidate, target))
                        and (not score or rank > score) then best, score = candidate, rank end
                end
            end
        end
        return best, score
    end
    function work.attackPlan(key, stats)
        local hunting = key=="hunt"or key=="foodHunt"or work.huntingNeeds~=nil or work.huntingPassive
        local cached = work.attackPlanCache
        if cached and cached.key == key and cached.stats == stats and (not hunting or work.huntEligible(cached.target)) and cached.target.Parent and cached.human and cached.human.Health > 0
            and os.clock() < cached.expires and (pos(cached.target) - cached.targetPoint).Magnitude < 1
            and work.stanceScore(cached.position, cached.target, stats) then return cached.target, cached.position end
        local r = root()
        if not r then return end
        local fire = built("Campfire")
        local center = fire and pos(fire)
        local candidates = {}
        for _, row in ipairs(hunting and work.creatures() or work.hostiles()) do
            local d = (row.point - r.Position).Magnitude
            local baseDistance = center and (row.point - center).Magnitude or math.huge
            if row.attackable and row.model.Parent and row.human.Health > 0 and work.insideBorder(row.point)
                and (not work.canHitMob or work.canHitMob(row.model,stats))
                and not (failed[row.model] and failed[row.model] > os.clock())
                and ((key == "combat" and ((flags.combat and baseDistance <= opts.baseRadius) or d <= math.max(opts.guardRadius,flags.combat and opts.huntRadius or 0,opts.avoidEnemies and opts.dangerRadius or 0)))
                    or(key=="shadowHunt"and work.isShadow(row.model)and d<=opts.huntRadius)
                    or (hunting and d <= opts.huntRadius and work.huntEligible(row.model))) then
                candidates[#candidates + 1] = {row = row, distance = d, baseDistance = baseDistance}
            end
        end
        table.sort(candidates, function(a, b)
            if key=="combat"then
                local urgentA=a.distance<=work.enemyReach(a.row.model)+3
                local urgentB=b.distance<=work.enemyReach(b.row.model)+3
                if urgentA~=urgentB then return urgentA end
            end
            if key == "combat" and a.baseDistance ~= b.baseDistance then return a.baseDistance < b.baseDistance end
            return a.distance < b.distance
        end)
        local target, position, bestScore
        for i = 1, math.min(8, #candidates) do
            local candidate = candidates[i]
            local point, stance = work.combatPosition(candidate.row.model, stats)
            if point then
                local ranged=stats.toolType=="gun" or stats.toolType=="infGun" or stats.toolType=="ranged"
                local score = ranged and (-candidate.distance*10-candidate.row.human.Health*0.001) or stance-candidate.row.human.Health*0.05
                if key == "combat" and not ranged then score = score + math.max(0, opts.baseRadius - candidate.baseDistance) * 2 end
                if key=="combat"and candidate.distance<=work.enemyReach(candidate.row.model)+3 then score=score+100000 end
                if candidate.row.model == work.attackTarget then score = score + 6 end
                if not bestScore or score > bestScore then target, position, bestScore = candidate.row.model, point, score end
            end
        end
        if target then work.attackPlanCache = {key = key, stats = stats, target = target, position = position,
            targetPoint = pos(target), human = target:FindFirstChildOfClass("Humanoid"), expires = os.clock() + 0.15} else work.attackPlanCache = nil end
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
        local tool, stats = work.meleeWeapon(key)
        if not r or not tool then note(key, "USABLE WEAPON REQUIRED") return false end
        equip(tool)
        local character, serial = player.Character, motion.serial
        local deadline, misses = os.clock() + math.clamp(opts.jobTimeout, 15, 600), 0
        local defeated = false
        while work.running(key, character, serial) and os.clock() < deadline do
            if not work.pause(key,math.max(0,(work.nextStrikeAt or 0)-os.clock())) then return defeated end
            r, human = root()
            if human.Health / human.MaxHealth * 100 <= opts.retreatHealth
                or (os.clock() < (work.damageUntil or 0) and select(3, work.danger(r.Position, opts.dangerRadius)) >= 3) then work.retreat(key) return false end
            local target, position = work.attackPlan(key, stats)
            if not target then
                if key=="shadowHunt"then return defeated end
                -- A crowded safe-stance search must not suppress every native
                -- attack. Counter once from here, then immediately create space.
                for _, row in ipairs(work.hostiles()) do
                    if row.attackable and work.stanceScore(r.Position, row.model, stats, true)
                        and work.attackPhase(row.model) ~= "strike" then
                        local before=row.human.Health
                        work.retaliatingUntil=os.clock()+0.25
                        local fired=work.strike(tool, stats, {row.model}, {}, key, true)
                        work.retaliatingUntil=nil
                        if fired then
                            work.await(key,function() return not row.model.Parent or row.human.Health<before end,0.5)
                            work.recordGuard(row.model)
                        end
                        work.kite(row.model, key)
                        return fired and row.human.Health<=0 or defeated
                    end
                end
                note(key, "NO TARGET IN NATIVE RANGE; REPOSITIONING")
                if work.personalThreat() then work.retreat(key) end
                return defeated
            end
            work.attackTarget, work.attackStats = target, stats
            local huntContext
            if key=="hunt"or key=="foodHunt"or work.huntingNeeds or work.huntingPassive then
                huntContext = {center = pos(target), before = {}, wanted = work.huntWanted(), expires = os.clock() + 30}
                for _, drop in ipairs(work.models("drops")) do huntContext.before[drop] = true end
            end
            if (r.Position - position).Magnitude > 0.75 and not travel(position, key, 0.5) then return defeated end
            r = root()
            if not r or not work.stanceScore(r.Position, target, stats) then return defeated end
            local enemyHuman = target:FindFirstChildOfClass("Humanoid")
            local before = work.mobRemaining and work.mobRemaining(target)or enemyHuman.Health
            local point = pos(target)
            if (point - r.Position).Magnitude > 0.1 then r.CFrame = CFrame.lookAt(r.Position, Vector3.new(point.X, r.Position.Y, point.Z)) end
            if work.attackPhase and work.attackPhase(target) == "strike" then
                work.kite(target, key)
                if not work.pause(key, 0.08) then return defeated end
                return defeated
            end
            local targets = {target}
            for _, row in ipairs(work.hostiles()) do
                if #targets >= (stats.capAOE or 1) then break end
                local delta = row.point - r.Position
                if row.model ~= target and row.attackable and row.model.Parent and row.human.Health > 0 and delta.Magnitude > 0.1
                    and r.CFrame.LookVector:Dot(delta.Unit) >= 0 and work.stanceScore(r.Position, row.model, stats) then
                    targets[#targets + 1] = row.model
                end
            end
            if not work.strike(tool, stats, targets, {}, key) then return defeated end
            local damaged = work.await(key, function() return not target.Parent or (work.mobRemaining and work.mobRemaining(target)or enemyHuman.Health) < before end,
                math.max(0.35, math.min(tonumber(stats.windup) or 0, tonumber(stats.useCd) or 0.7) + 0.45))
            work.attackCommit=nil
            if damaged then work.attackReceipts=(work.attackReceipts or 0)+1 end
            if work.preempted then return defeated end
            if work.kite then work.kite(target,key)end
            misses = damaged and 0 or misses + 1
            for _, attacked in ipairs(targets) do work.recordGuard(attacked) end
            if not target.Parent or (work.mobRemaining and work.mobRemaining(target)or enemyHuman.Health) <= 0 then
                defeated = true work.threatCacheAt = 0
                if key=="shadowHunt"then return true end
                if huntContext then
                    work.huntLoot = work.huntLoot or {}
                    work.huntLoot[#work.huntLoot + 1] = huntContext
                    work.await(key, function() return work.foodDropCandidate() ~= nil end, 1)
                    work.foodHuntAt = os.clock() + 1
                    return true
                end
            end
            if misses >= 3 then
                failed[target] = os.clock() + 1
                note(key, "HITS UNCONFIRMED; REPOSITION / RETREAT")
                work.retreat(key)
                return defeated
            end
        end
        return defeated
    end
    function work.pickupCandidate(neededOnly, key)
        local scene = world()
        local folder = scene and scene:FindFirstChild("DroppedItems")
        if not folder then return end
        local c = config()
        local goal = work.probingGoal or work.activeGoal or work.objective or work.selectedCraftMaterialGoal()
        local function eligible(model)
            if not model.Parent or not work.dropAllowed(model) then return false end
            local info = c.item.byDisplayName[model.Name]
            if not info or not work.pickupEligible(model) then return false end
            if key ~= "stockpile" and goal and goal.kind == "quest" and model:GetAttribute("ownerName") == player.Name
                and work.questRequirement and info.id == work.questRequirement.itemId then return false end
            if key ~= "stockpile" and (neededOnly or opts.onlyNeeded) and work.taskDemand(info.id, "progression") <= 0 then return false end
            return (key == "stockpile" or neededOnly or selectedEmpty("drops") or allowed("drops", info.id)) and work.safeResource(model)
                and not (failed[model] and failed[model] > os.clock())
        end
        local loaded, stash = folder:GetChildren(), {}
        for _, model in ipairs(loaded) do if work.markCampDrop(model) then stash[#stash + 1] = model end end
        return nearest(stash, eligible) or nearest(loaded, eligible, function(model)
            local info = c.item.byDisplayName[model.Name]
            return info and work.needs[info.id] or 0
        end)
    end
    local function pickups(key, neededOnly)
        key = key or "drops"
        if not work.canCollect() then note(key,"BAG FULL: USE / SUBMIT ITEMS FIRST") return false end
        local acted,seen=false,{}
        local deadline=os.clock()+math.clamp(opts.jobTimeout,15,600)
        repeat
            local model=work.pickupCandidate(neededOnly,key)
            if not model or seen[model]then break end
            seen[model]=true
            work.interactionTarget=model
            local confirmed=work.collectModel(model,key)
            if not work.preempted then failed[model]=os.clock()+(confirmed and .1 or 1)end
            acted=confirmed or acted
            if not flags.bulkCollect or work.preempted or not work.canCollect()then break end
        until os.clock()>=deadline
        return acted
    end
    function work.resourceCandidate(key, neededOnly)
        local preferred = work.preferredTargets and work.preferredTargets[key]
        if preferred and work.resourceEligible(preferred, key, neededOnly) then return preferred end
        if work.preferredTargets then work.preferredTargets[key] = nil end
        return nearest(work.models("resources"), function(model) return work.resourceEligible(model, key, neededOnly) end,
            function(model)
                local id=model:GetAttribute("resourceId")
                local value=work.resourceNeeds[id]or 0
                if not neededOnly and(key=="stockpile"or key=="gather")then
                    local nextKind=({tree="stone",stone="iron",iron="tree",other="tree"})[work.lastHarvestKind]
                    if nextKind and work.resourceKind(config().worldResource.byId[id])==nextKind then value=value+1000 end
                end
                return value
            end)
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
        if work.treeDrops and work.safeWorkPoint(work.treeDrops.center, 5) then
            work.treeDrops.key = key return work.recoverTreeDrops()
        end
        local c = config()
        local best = work.resourceCandidate(key, neededOnly)
        if not best then
            note(key, "NO LOADED MATCHING RESOURCES")
            return
        end
        local rc = c.worldResource.byId[best:GetAttribute("resourceId")]
        work.resourceFocus = {model = best, key = key, kind = work.resourceKind(rc), neededOnly = neededOnly}
        local tool, tc = work.resourceTool(rc)
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
        dropContext.resourceKind = work.resourceKind(rc)
        local character, serial = player.Character, motion.serial
        local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        local noDamage = 0
        while work.running(key, character, serial) and os.clock() < deadline do
            if not work.canCollect() then note(key, "BAG FULL: SUBMITTING BEFORE FURTHER HARVEST") return false end
            local hp = best:GetAttribute("hp")
            if not best.Parent or (type(hp) == "number" and hp <= 0) then
                work.lastHarvestKind=work.resourceKind(rc)
                work.recordCut(best, rc)
                work.resourceFocus = nil
                work.resourcePlans[best] = nil
                work.setRecovery(dropContext)
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
            if opts.fastHarvest == false and not work.pause(key, opts.settleTime) then return false end
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
    function work.chestState(model)
        work.chestStates = work.chestStates or setmetatable({}, {__mode = "k"})
        local state = work.chestStates[model]
        if not state then
            state = {before = {}, model = model}
            for _, drop in ipairs(work.models("drops")) do state.before[drop] = true end
            work.chestStates[model] = state
        end
        return state
    end
    function work.chestCandidate()
        local rows = config().chest.byId
        local resume = work.chestResume
        if resume and not resume.Parent then work.chestResume = nil end
        if resume and resume.Parent and not (failed[resume] and failed[resume] > os.clock())
            and work.safeResource(resume) then return resume end
        return nearest(work.models("chests"), function(model)
            local state = work.chestStates and work.chestStates[model]
            return model:IsA("Model") and rows[model.Name] and not (state and state.complete)
                and not (failed[model] and failed[model] > os.clock()) and work.safeResource(model)
        end)
    end
    function work.chestDuration(model)
        local animation = model:FindFirstChild("OpenAnimation")
        local controller = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
        local animator = controller and controller:FindFirstChildOfClass("Animator")
        if animator and animation then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track.Animation and track.Animation.AnimationId == animation.AnimationId and track.Length > 0 then
                    return track.Length * 0.9
                end
            end
        end
        return nil
    end
    function work.openChest()
        local key, model = "chests", work.chestCandidate()
        if not model then return false end
        local state = work.chestState(model)
        if not state.requestedAt then
            if call("ChestService", "isOpened", model) then
                state.acceptedAt, state.requestedAt = os.clock(), os.clock()
                state.recoveredOpen = true
                -- A previous interrupted opener may have left its loot on the ground.
                for _, drop in ipairs(work.models("drops")) do
                    local point, center = pos(drop), pos(model)
                    if point and center and drop:GetAttribute("ownerName") == player.Name
                        and (point - center).Magnitude <= 16 then state.before[drop] = nil end
                end
            end
            if call("ChestService", "isLocked", model) then failed[model] = os.clock() + 1 return false end
        end
        local info = config().chest.byId[model.Name]
        local radius = math.max(1, (tonumber(info.openDistance) or 10) - 1)
        local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and prompt.Enabled then radius = math.min(radius, math.max(0.5, prompt.MaxActivationDistance - 1)) end
        -- The prompt is attached to UpperTorso on humanoid chests, otherwise
        -- PrimaryPart. A model pivot is not necessarily that activation point.
        local approach = prompt and prompt.Parent or model.PrimaryPart or model
        if approach and approach:IsA("Attachment") then approach = approach.Parent end
        if not travel(approach, key, radius) then return false end
        work.chestResume = model
        if not state.requestedAt then
            local prompted, heldFull = work.interactPrompt(model, key, opts.chestHoldPadding)
            if prompted == false and not heldFull then return false end
            if prompted == nil then
                if not work.pause(key, math.max(0, tonumber(info.openSec) or 0) + (opts.chestHoldPadding or 0)) then return false end
            end
            -- Some executors do not dispatch synthetic prompt Triggered. Only
            -- fall back to the verified native call after a complete E hold.
            if prompted ~= true then call("ChestService", "requestOpen", model) end
            state.requestedAt = state.requestedAt or os.clock()
        end
        local character, serial = player.Character, motion.serial
        local maximum = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
        local deadline = math.min(maximum, os.clock() + 15)
        work.interaction = {key = key, untilTime = deadline}
        while model.Parent and work.running(key, character, serial) and os.clock() < deadline do
            local now = os.clock()
            if not state.acceptedAt and now >= (state.nextCheck or 0) then
                state.nextCheck = now + 0.4
                if call("ChestService", "isOpened", model) then state.acceptedAt = now end
            end
            if not state.acceptedAt and now - state.requestedAt > 3 then
                state.requestedAt = nil
                failed[model] = now + 0.5
                work.interaction = nil
                note(key, "CHEST DID NOT ACCEPT OPEN REQUEST; RETRYING")
                return false
            end
            if state.acceptedAt then
                local duration = work.chestDuration(model)
                if duration then
                    state.duration = math.max(state.duration or 0, duration)
                    deadline = math.min(maximum, math.max(deadline, state.acceptedAt + state.duration + 3))
                    work.interaction.untilTime = deadline
                end
                local target, sawNew, pendingLoot = nil, false, false
                for _, drop in ipairs(work.models("drops")) do
                    local point, center = pos(drop), pos(model)
                    if drop.Parent and point and center and not state.before[drop]
                        and drop:GetAttribute("ownerName") == player.Name and (point - center).Magnitude <= 16 then
                        sawNew = true
                        local item = config().item.byDisplayName[drop.Name]
                        if item and work.dropAllowed(drop) and work.pickupEligible(drop) then
                            pendingLoot = true
                            if work.safeResource(drop) and not (failed[drop] and failed[drop] > now) then target = target or drop end
                        end
                    end
                end
                if sawNew then state.sawLoot = true end
                local targetItem = target and config().item.byDisplayName[target.Name]
                local autoEquip = targetItem and config().misc.useArmourCollectEquip and targetItem.type == "armour"
                if target and not work.canCollect() and not autoEquip and not work.bagRank(targetItem.id) then
                    work.chestResume = model
                    work.interaction = nil
                    note(key, "CHEST LOOT SAVED; UNLOADING BAG AT CAMP")
                    return false
                end
                if target then
                    local item = config().item.byDisplayName[target.Name]
                    if work.collectModel(target, key, work.bagRank(item.id) ~= nil, true) then state.lastLootAt = os.clock()
                    elseif work.preempted then work.interaction = nil return false
                    else failed[target] = os.clock() + 1 end
                else
                    local durationDone = now >= state.acceptedAt + (state.duration or 0.5)
                    local quiet = not state.lastLootAt or now - state.lastLootAt >= 0.25
                    local emptyAnimationDone = state.duration and now >= state.acceptedAt + state.duration + 1
                    if durationDone and (state.sawLoot or emptyAnimationDone
                        or (state.recoveredOpen and now - state.acceptedAt >= 1 and not duration))
                        and quiet and not pendingLoot then
                        state.complete = true
                        work.interaction = nil
                        if work.chestResume == model then work.chestResume = nil end
                        note(key, "CHEST OPENED; LOOT COLLECTION FINISHED")
                        return true
                    end
                end
                note(key, "OPENING CHEST / WAITING FOR ITS LOOT")
            end
            task.wait()
        end
        work.interaction = nil
        if not work.preempted then failed[model] = os.clock() + 5 end
        note(key, work.preempted and "CHEST SAVED; RESUMING AFTER URGENT JOB" or "CHEST OPEN PENDING; WILL RESUME")
        return false
    end
    local function exploreTick(key, kind, service, check, request)
        if kind == "chest" then return work.openChest() end
        local w = world()
        if not w then
            return
        end
        local c = config()
        local rows = kind == "chest" and c.chest.byId or c.mapProp.byCnId
        local search = kind == "chest" and w:FindFirstChild("Chest") or w
        local obj = nearest(work.models(kind == "chest" and "chests" or "explore"), function(o)
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
        local prompt=obj:FindFirstChildWhichIsA("ProximityPrompt",true)
        local anchor=prompt and prompt.Parent or obj
        local radius=prompt and math.max(1,prompt.MaxActivationDistance-1) or 6
        if travel(anchor, key,radius) then
            local prompted,held=work.interactPrompt(obj,key)
            if prompted==false and not held then return false end
            if prompted~=true then call(service, request, obj) end
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
        for _, o in ipairs(work.models("escape")) do
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
    function work.questCatalog()
        local c=config();local lines={"MRBEAST • LIVE CONFIGURATION (current server)"}
        for _,row in ipairs(c.mrbeastQuestList and c.mrbeastQuestList.list or{})do
            lines[#lines+1]="Quest "..tostring(row.index).." | one selected alternate: "..tostring(row.require)
                .." | preferred reward: "..tostring(row.fixedReward or "pool").." | tutorial only: "..tostring(row.newbieOnly==true)
        end
        lines[#lines+1]="APPEARANCE / RESET WINDOWS"
        for _,row in ipairs(c.mrbeastQuestTiming and c.mrbeastQuestTiming.list or{})do lines[#lines+1]=tostring(row.apearDesc).." | quest range "..tostring(row.questResetRange)end
        lines[#lines+1]="REWARD POOLS (server selects the offered choices)"
        for _,row in ipairs(c.mrbeastQuestPrior and c.mrbeastQuestPrior.list or{})do
            lines[#lines+1]=tostring(row.poolItems).." | weight "..tostring(row.weight).." | fallback pool "..tostring(row.isEdge)
        end
        return table.concat(lines,"\n")
    end
    function work.questDetails(req,index,alt,revision)
        if not req then return "MRBEAST: NO ACTIVE REQUEST • WATCHING FOR THE NEXT ONE"end
        local c=config();local item=c.item.byId[req.itemId]
        local held=item and count(item.displayName)or 0
        local dropped=#work.questDrops(req)
        local reward="Upgrade choice from the live reward pools"
        for _,row in ipairs(c.mrbeastQuestList and c.mrbeastQuestList.list or{})do
            if row.index==index then
                if row.fixedReward and row.fixedReward~="x"then
                    local fixed=c.item.byName[row.fixedReward]or c.bag and c.bag.byCn and c.bag.byCn[row.fixedReward]
                    reward="Preferred reward: "..tostring(fixed and fixed.displayName or row.fixedReward).." (pool choices if already owned)"
                end
                break
            end
        end
        local offers={}
        for _,choice in ipairs(work.choices or{})do
            local it=c.item.byId[choice.itemId]or c.bag and c.bag.byId[choice.itemId]
            offers[#offers+1]=tostring(it and it.displayName or choice.itemId).." x"..tostring(choice.count or 1)
        end
        if #offers>0 then reward=reward.."\nPENDING REWARD CHOICES: "..table.concat(offers,", ")end
        return "QUEST "..tostring(index).." • OPTION "..tostring(alt or 1).." • REV "..tostring(revision)
            .."\nGIVE "..req.count.." "..tostring(item and item.displayName or req.itemId)
            .." • CARRIED "..held.." + OWNED DROPS "..dropped.." • MISSING "..math.max(0,req.count-held-dropped)
            .."\n"..reward.."\n"..tostring(work.questStatus or "Gather / craft the requested item, deliver it, then claim one offered reward")
    end
    function work.readQuest(force)
        local scene=world()
        if work.questScene~=scene then
            work.questScene=scene;work.questGeneration=(work.questGeneration or 0)+1
            work.questCache,work.questRequirement,work.questFetchPending,work.questSubmission=nil,nil,nil,nil
        end
        local npc=scene and scene:FindFirstChild("Mrbeast",true)
        if not npc then
            local cache=work.questCache
            work.questStatus="MRBEAST NOT STREAMED • KEEPING THE CURRENT REQUEST"
            if cache then return work.questRequirement,cache.index,cache.alt,cache.revision,work.questModule end
            return
        end
        local q=module("MrbeastQuest");if not q then return end
        work.questModule=q
        local function apply(index,alt,revision)
            if type(revision)~="number"or(index~=nil and type(index)~="number")then return end
            local previous=work.questCache
            if previous and type(previous.revision)=="number"and revision<previous.revision then return end
            local changed=not previous or previous.index~=index or previous.alt~=alt or previous.revision~=revision
            work.questCache={index=index,alt=alt,revision=revision,at=os.clock()}
            work.questRequirement=index and q.getQuestRequirement(index,alt)or nil
            if changed then
                work.questGeneration=(work.questGeneration or 0)+1
                work.refreshAt,work.goalProbes,work.attackPlanCache=0,nil,nil
                work.questStatus=work.questRequirement and "REQUEST UPDATED • COMPLETION STILL REQUIRED"or "WAITING FOR NEXT REQUEST"
                due.quest=0
            end
        end
        local service=RS.Engine.Service:FindFirstChild("MrbeastQuest")
        local event=service and service:FindFirstChild("questUpdateRemote")
        if event and(work.questBoundEvent~=event or work.questBoundScene~=scene)then
            if work.questUpdateConnection then work.questUpdateConnection:Disconnect()end
            if work.questSubmitConnection then work.questSubmitConnection:Disconnect()end
            work.questBoundEvent,work.questBoundScene=event,scene
            work.questUpdateConnection=event.OnClientEvent:Connect(function(index,alt,revision)
                if alive and scene==world()then apply(index,alt,revision)end
            end)
            connections[#connections+1]=work.questUpdateConnection
            local submitted=service:FindFirstChild("questSubmittedRemote")
            if submitted then
                work.questSubmitConnection=submitted.OnClientEvent:Connect(function()
                    if not alive or scene~=world()then return end
                    work.questAccepted=(work.questAccepted or 0)+1
                    if work.questSubmission then work.questSubmission.accepted=true end
                    work.questStatus="SUBMISSION ACCEPTED • CLAIMING REWARD"
                    work.refreshAt,work.goalProbes=0,nil;due.mrbeastReward=0
                end)
                connections[#connections+1]=work.questSubmitConnection
            end
        end
        local cache=work.questCache
        local canFetch=true
        if type(root)=="function"then local _,human=root();canFetch=not human or human.Health>0 end
        if canFetch and not work.questFetchPending and(not cache or os.clock()-cache.at>=(force and .5 or 2))then
            local token={character=player.Character,generation=work.questGeneration or 0};work.questFetchPending=token
            task.spawn(function()
                local ok,index,alt,revision=pcall(function()return work.boundedRead(q.client.fetchQuest,"MrBeast quest")end)
                if work.questFetchPending==token then work.questFetchPending=nil end
                if alive and ok and player.Character==token.character and scene==world()
                    and token.generation==(work.questGeneration or 0)then apply(index,alt,revision)
                elseif not ok and scene==world()then work.questStatus="QUEST SYNC FAILED • KEEPING REQUEST AND RETRYING"end
            end)
        end
        cache=work.questCache
        local req=cache and cache.index and q.getQuestRequirement(cache.index,cache.alt)
        work.questRequirement=req
        if work.questLabel then
            work.questLabel.Text=work.questDetails and work.questDetails(req,cache and cache.index,cache and cache.alt,cache and cache.revision)
                or(req and("MRBEAST NEEDS "..req.count.." "..req.itemId)or"MRBEAST: WAITING FOR NEXT REQUEST")
        end
        if cache then return req,cache.index,cache.alt,cache.revision,q end
    end
    function work.questDrops(req)
        local result = {}
        local item = req and config().item.byId[req.itemId]
        local folder = world() and world():FindFirstChild("DroppedItems")
        if item and folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model")and model.Name==item.displayName and model:GetAttribute("ownerName")==player.Name
                    and not model:GetAttribute("collecting") then result[#result + 1] = model end
            end
        end
        return result
    end
    function work.questTotal(req)
        local item = req and config().item.byId[req.itemId]
        return item and count(item.displayName) + #work.questDrops(req) or 0
    end
    local function questTick(key,partial)
        key=key or "quest"
        local req,index,alt,revision,q=work.readQuest(true)
        local lease=work.questSubmission
        if lease then
            if lease.accepted then work.questSubmission=nil;work.questStatus="MRBEAST REQUEST COMPLETE • REWARD QUEUED";return true end
            if os.clock()-lease.at<3 then note(key,"WAITING FOR MRBEAST ACCEPTANCE");return false end
            work.questSubmission=nil;work.questStatus="NO ACCEPTANCE RECEIPT • REFRESHING AND RETRYING"
            if work.questCache then work.questCache.at=-math.huge end
            work.readQuest(true);return false
        end
        if not req or type(revision)~="number"then note(key,"WAITING FOR A CURRENT MRBEAST REQUEST");return false end
        local info=config().item.byId[req.itemId];if not info then return false end
        local mr=world():FindFirstChild("Mrbeast",true);local area=mr and mr:FindFirstChild("SuckArea")
        if not area then return false end
        local used,cap=work.bagState()
        if work.questTotal(req)<req.count and not((partial or used>=cap)and count(info.displayName)>0)then return false end
        if not travel(area,key,1.8)then return false end
        local deposited=false;local deadline=os.clock()+math.clamp(opts.jobTimeout,15,600)
        while work.running(key,player.Character,motion.serial)and os.clock()<deadline do
            local current,liveIndex,liveAlt,liveRevision=work.readQuest(false)
            if not current or liveIndex~=index or liveAlt~=alt or liveRevision~=revision then
                note(key,"REQUEST CHANGED DURING DELIVERY • REPLANNING");work.refreshAt=0;return deposited
            end
            local best,held=nil,0
            for _,tool in ipairs(tools())do
                local amount=tonumber(tool:GetAttribute("count"))or 1
                if tool.Name==info.displayName and amount>held then best,held=tool,amount end
            end
            local owned=work.questDrops(req)
            if #owned+held>=req.count then
                if best then
                    equip(best)
                    if best.Parent~=player.Character then note(key,"MATCHING QUEST STACK NOT EQUIPPED; RETRYING");return deposited end
                end
                local _,freshIndex,freshAlt,freshRevision=work.readQuest(false)
                if freshIndex~=index or freshAlt~=alt or freshRevision~=revision then return deposited end
                lease={index=index,alt=alt,revision=revision,at=os.clock()};work.questSubmission=lease
                work.questStatus="SUBMITTING EXACT REQUEST • WAITING FOR SERVER ACCEPTANCE"
                q.client.submitQuest(owned,revision);work.sent=work.sent+1
                local confirmed=work.await(key,function()return lease.accepted==true end,3)
                if confirmed then
                    if work.questSubmission==lease then work.questSubmission=nil end
                    work.questStatus="MRBEAST REQUEST COMPLETE • REWARD QUEUED"
                else work.questStatus="SUBMISSION UNCONFIRMED • RETRYING THE CURRENT REQUEST"end
                work.refreshAt=0;note(key,work.questStatus);return confirmed
            end
            if not best then return deposited end
            local before=#owned
            local amount=work.batchDrop(best,math.min(count(info.displayName),req.count-#owned),key)
            if amount==0 then return deposited end
            if not work.await(key,function()return #work.questDrops(req)>=before+amount end,3)then return deposited end
            deposited=true;work.questStatus="PARTIAL DELIVERY SAVED • GATHERING THE REMAINDER"
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
        work.equippedArmour=work.equippedArmour or{}
        local armourService=RS.Engine.Service:FindFirstChild("ArmourService")
        local armourChanged=armourService and armourService:FindFirstChild("equipChangedRemote")
        local armourVersion={}
        if armourChanged then connections[#connections+1]=armourChanged.OnClientEvent:Connect(function(kind,id)
            armourVersion[kind]=(armourVersion[kind]or 0)+1;work.equippedArmour[kind]=id
        end)end
        local getArmour=armourService and armourService:FindFirstChild("getEquippedFunction")
        if getArmour then
            local kinds={}
            for _,info in pairs(config().armour and config().armour.byId or{})do if info.typeCN then kinds[info.typeCN]=true end end
            for kind in pairs(kinds)do task.spawn(function()
                local generation=armourVersion[kind]or 0
                local ok,id=pcall(function()return work.boundedRead(function()return getArmour:InvokeServer(kind)end,"equipped armour")end)
                if alive and ok and generation==(armourVersion[kind]or 0)then work.equippedArmour[kind]=id end
            end)end
        end
        local chestService = RS.Engine.Service:FindFirstChild("ChestService")
        local opened = chestService and chestService:FindFirstChild("RemoteEvent")
        if opened then
            connections[#connections + 1] = opened.OnClientEvent:Connect(function(model)
                local state = work.chestState(model)
                state.acceptedAt = state.acceptedAt or os.clock()
                state.requestedAt = state.requestedAt or state.acceptedAt
            end)
        end
        local service = RS.Engine.Service:FindFirstChild("MrbeastChoice")
        local event = service and service:FindFirstChild("onChoiceRemote")
        if event then
            connections[#connections + 1] = event.OnClientEvent:Connect(function(choices)
                work.choices = type(choices) == "table" and choices or nil
                work.choiceFailures,work.choiceRetryAt=0,0
                work.recoveredChoice, work.lastRecoveredChoice = nil, nil
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
        for _, model in ipairs(work.models("stations")) do
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
    function work.stationTick(goal, key)
        local _, zone
        local stockField = goal.stationKind == "building" and "buildingStock" or "stationStock"
        if goal.stationKind == "building" then _, zone = work.structureStation() else _, zone = work.station() end
        key = key or "progression"
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
            local initial = (work[stockField] or {})[id] or 0
            local sent = 0
            while item and math.max((work[stockField] or {})[id] or 0, initial + sent) < needed and count(item.displayName) > 0
                and work.running(key, player.Character, motion.serial) and os.clock() < deadline do
                if not work.insideStation(zone) then return deposited end
                local tool
                for _, candidate in ipairs(tools()) do if candidate.Name == item.displayName then tool = candidate break end end
                if not tool then break end
                local missing = needed - math.max((work[stockField] or {})[id] or 0, initial + sent)
                local available=work.spendable and work.spendable(id,key)or count(item.displayName)
                local amount=work.batchDrop(tool,math.min(missing,available),key)
                if amount == 0 then return deposited end
                sent = sent + amount deposited = true
            end
            if sent > 0 and not work.await(key, function() return ((work[stockField] or {})[id] or 0) >= math.min(needed, initial + sent) end, 3) then
                note(key, "MATERIALS SENT • WAITING FOR STATION RECEIPT") return deposited
            end
        end
        for id, amount in pairs(goal.recipe) do
            if ((work[stockField] or {})[id] or 0) < amount then return deposited end
        end
        local before, bagId = count(goal.info.displayName), player:GetAttribute("bagId")
        work.net(goal.stationKind == "building" and "BuildingStationCraft" or "CraftingStationCraft"):FireServer(goal.id)
        work.sent = work.sent + 1
        return work.await(key, function()
            return player:GetAttribute("bagId") ~= bagId or count(goal.info.displayName) > before
        end, 3)
    end
    function work.choiceScore(choice)
        local c, id = config(), choice.itemId
        local item=c.item.byId[id]or c.bag and c.bag.byId[id]
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
        local armour=c.armour and c.armour.byId[id]
        if armour then
            local ownedId=work.equippedArmour and work.equippedArmour[armour.typeCN]
            local owned=ownedId and c.armour.byId[ownedId]
            if (tonumber(armour.lvl)or 1)>(tonumber(owned and owned.lvl)or 0)then
                return(underAttack and 790000 or 650000)+(tonumber(armour.lvl)or 1)*100
            end
            return -100
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
            if upgrade then return 600000 + (tonumber(tool.lvl) or 0) * 100 + (tonumber(tool.atkDmg) or 0) end
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
    function work.choicePanel()
        local screen = pg:FindFirstChild("MrbeastChoice")
        local background = screen and screen:FindFirstChild("Background")
        local panel = background and background:FindFirstChild("RootPanel")
        local scroll = panel and panel:FindFirstChild("BadgeScroll")
        return background, scroll
    end
    function work.recoverChoices()
        if work.choices or not flags.choiceRewards or os.clock() < (work.nextChoiceProbe or 0) then return end
        work.nextChoiceProbe = os.clock() + 0.25
        local background, scroll = work.choicePanel()
        if not background or not background.Visible or not scroll then return end
        local choices, c, signature = {}, config(), {}
        local index = 0
        for _, cell in ipairs(scroll:GetChildren()) do
            if cell.Name == "itemCell" then
                index = index + 1
                local label = cell:FindFirstChild("text")
                local button = cell:FindFirstChild("ReceiveButton")
                if cell.Visible and label and button and button.Visible then
                    local item = c.item.byDisplayName[label.Text]
                    if not item then
                        for id, bag in pairs(c.bag and c.bag.byId or {}) do
                            if bag.displayName == label.Text then item = {id = id} break end
                        end
                    end
                    if item then
                        choices[#choices + 1] = {itemId = item.id, count = 1, serverIndex = index}
                        signature[#signature + 1] = index .. ":" .. item.id
                    end
                end
            end
        end
        local key = table.concat(signature, "|")
        if #choices > 0 and key ~= work.lastRecoveredChoice then
            work.choices, work.recoveredChoice = choices, key
            work.choiceVersion = (work.choiceVersion or 0) + 1
        end
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
        local chosen=choices[best];local c=config();local item=c.item.byId[chosen.itemId]
        local before=item and count(item.displayName)or 0
        local bagId=player:GetAttribute("bagId")
        local armour=c.armour and c.armour.byId[chosen.itemId]
        local armourBefore=armour and work.equippedArmour and work.equippedArmour[armour.typeCN]
        event:FireServer(choices[best].serverIndex or best)
        work.sent = work.sent + 1
        local key = "mrbeastReward"
        local confirmed = work.await(key, function()
            return work.choiceVersion~=version or work.choices==nil
                or item and count(item.displayName)>before
                or c.bag and c.bag.byId[chosen.itemId]and player:GetAttribute("bagId")~=bagId and player:GetAttribute("bagId")==chosen.itemId
                or armour and work.equippedArmour and work.equippedArmour[armour.typeCN]~=armourBefore and work.equippedArmour[armour.typeCN]==chosen.itemId
        end, 2)
        if confirmed and work.choiceVersion == version then
            work.choices = nil
            work.lastRecoveredChoice = work.recoveredChoice
            local background = work.choicePanel()
            if background then background.Visible = false end
        end
        work.blockedBag=nil
        work.choiceFailures=confirmed and 0 or(work.choiceFailures or 0)+1
        work.choiceRetryAt=confirmed and 0 or os.clock()+math.min(30,2^math.min(5,work.choiceFailures))
        work.questStatus=confirmed and "MRBEAST REWARD CONFIRMED • WATCHING NEXT REQUEST"or "REWARD UNCONFIRMED • WAITING / RETRYING"
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
        if flags.autoFarm == false or not flags[key] or (due[key] and os.clock() < due[key]) then
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
        if name:find("craft") or name:find("workbench") or name == "制作台" then
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
            if (id ~= work.boatId() or flags.buildBoat) and (not targetId or id == targetId) and (not onlySelected or allowed("build", id))
                and folder:FindFirstChild(info.assetId .. "_Construct") then
                candidates[#candidates + 1] = { id = id, info = info }
            end
        end
        table.sort(candidates, function(a, b)
            local ar, br = work.buildRank(a.info), work.buildRank(b.info)
            return ar < br or (ar == br and tostring(a.id) < tostring(b.id))
        end)
        local anySubmitted = false
        for _, entry in ipairs(candidates) do
            if work.preempted then return anySubmitted end
            local info = entry.info
            local blueprint = folder:FindFirstChild(info.assetId .. "_Construct")
            local function hasMaterial()
                local has=false
                for field,amount in pairs(c.recipe.byId[info.recipeId]or{})do
                    local id=type(field)=="string"and field:match("^require_(.+)$")
                    local item=id and c.item.byId[id]
                    if item and type(amount)=="number"and amount>0 then
                        local remaining=work.remaining(info,id,amount)
                        local held=count(item.displayName)
                        if remaining>0 and held>0 then
                            local critical=info.assetId=="Campfire"and not built("Campfire")
                            if not critical and work.spendable and work.spendable(id,key)<math.min(held,remaining)then return false end
                            has=true
                        end
                    end
                end
                return has
            end
            if blueprint and hasMaterial() then
                local character, serial = player.Character, motion.serial
                local deadline = os.clock() + math.clamp(opts.jobTimeout, 15, 600)
                local submitted = false
                while blueprint.Parent and hasMaterial()
                    and work.running(key, character, serial) and os.clock() < deadline do
                    if not travel(blueprint, key) then
                        if work.preempted then return anySubmitted end
                        break
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
                        if work.preempted then return anySubmitted end
                        break
                    end
                    submitted = true
                    work.refreshAt = 0
                end
                anySubmitted = submitted or anySubmitted
                note(key, not blueprint.Parent and "CONSTRUCTION FINISHED"
                    or "AVAILABLE MATERIALS SUBMITTED; NEED MORE MATERIALS")
            end
        end
        if not anySubmitted then note(key, "NO BLUEPRINT WITH USABLE MATERIALS") end
        return anySubmitted
    end
    local function craftTick()
        local goal = work.nextReadyCraft()
        if not goal then note("craft", "NO READY CRAFT RECIPE") return false end
        note("craft", "CRAFTING: " .. tostring(goal.info.displayName or goal.id))
        local completed = work.submitGoal("craft", goal)
        if not completed and not work.preempted then
            work.upgradeBlocked = work.upgradeBlocked or {}
            work.upgradeBlocked[goal.key] = os.clock() + 0.75
        end
        work.refreshAt = 0
        return completed
    end
    local function buildTick()
        return work.contribute("build", true)
    end
    local function buildCurrentTick()
        return work.contribute("buildCurrent", false)
    end
    local function foodReady()
        if not work.mealNeeded() then return false end
        if not work.noFood() then return true end
        return work.canCollect() and work.mealAvailable()
    end
    local function enemyReady()
        if os.clock()<(work.evadeRecoverUntil or 0)then return false end
        local _,stats=work.meleeWeapon("combat")
        if not stats then return false end
        return work.attackPlan("combat",stats)~=nil or work.retaliationTarget(stats)~=nil
    end
    function work.needItem(id, amount, priority)
        local c = config()
        local item = c.item.byId[id]
        work.needTotals = work.needTotals or {}
        if item then work.needTotals[id] = math.max(work.needTotals[id] or 0, amount) end
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
        if (not cap or cap <= 0) and type(row.capMinsPlayerCount) == "table" and #row.capMinsPlayerCount > 0 then
            local players = w and w:FindFirstChild("PlayerCount")
            cap = row.capMinsPlayerCount[math.clamp(players and players.Value or 1, 1, #row.capMinsPlayerCount)]
        end
        if not cap or cap <= 0 then return end
        local state = work.fireState()
        if not state or state.remaining == nil or not work.firePendingReady() then return end
        local remaining = state.remaining
        if remaining >= cap * 60 - 0.05 then return end
        local amount = math.max(1, math.ceil((cap * 60 - remaining) / row.woodBurnSec))
        return {key = "campfire:" .. level, kind = "fuel", level = level, rank = 2 + (level - 1) * 2,
            name = "CAMPFIRE LEVEL " .. (level + 1), amounts = {[item.id] = amount}}
    end
    function work.upgradeCandidates()
        local c, result = config(), {}
        local folder = world() and world():FindFirstChild("Buildings")
        if folder then
            for id, info in pairs(c.build.byId) do
                if folder:FindFirstChild(info.assetId .. "_Construct")
                    and ((id == work.boatId() and flags.buildBoat) or (id ~= work.boatId() and (flags.buildCamp or flags.progression))) then
                    local rank = work.buildRank(info)
                    result[#result + 1] = {key = "build:" .. id, id = id, kind = "build", info = info,
                        rank = rank == 0 and 0 or (rank == 1 and 2.2 or 4.5),
                        name = itemLabel("building", id, info), amounts = work.recipeAmounts(info, true)}
                end
            end
        end
        local req = flags.quest and work.questRequirement
        if req then
            local requested=c.item.byId[req.itemId]
            if requested and requested.recipeId and next(work.recipeAmounts(requested))and not(c.food and c.food.byId[requested.id])and count(requested.displayName)==0
                and work.questTotal(req)<req.count then
                -- Produce a requested craft through its native recipe, deliver
                -- that output, then re-read the remaining quest before repeating.
                result[#result+1]={key="questCraft:"..req.itemId,kind="craft",id=req.itemId,
                    questFor=req.itemId,info=requested,rank=5.9,name="MRBEAST REQUEST: "..requested.displayName,
                    amounts=work.recipeAmounts(requested)}
            end
            result[#result + 1] = {key = "quest:" .. tostring(req.itemId), kind = "quest", itemId = req.itemId, rank = 6,
                name = "MRBEAST REQUEST", amounts = {[req.itemId] = math.max(0, req.count - #work.questDrops(req))}}
        end
        local bag = work.bagGoal()
        if bag then bag.rank = math.min(bag.rank, 0.08) result[#result + 1] = bag end
        local upkeep = flags.fuel and work.maintenanceGoal()
        if upkeep then result[#result + 1] = upkeep end
        local fire = not upkeep and (flags.buildCamp or flags.progression) and work.campfireGoal()
        if fire then
            if campData.isOnFire == false then fire.rank = 0.02
            elseif work.bagNeedsFire then fire.rank = 0.25 end
            result[#result + 1] = fire
        end
        if flags.killShadow and work.shadowWeapon and not work.shadowWeapon()then
            for id,tool in pairs(c.tool.byId or{})do
                local item=c.item.byId[id]
                if item and item.isLightSource and item.recipeId then
                    result[#result+1]={key="torch:"..id,id=id,kind="craft",info=item,rank=1.5,
                        name=itemLabel("tool",id,item),amounts=work.recipeAmounts(item)}
                    break
                end
            end
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
            if (flags.toolLadder or flags.progression) and item and item.recipeId and level and info.toolType and relevant and not excluded
                and level > (best[info.toolType] or 0) and count(item.displayName) == 0 then
                local previous = nextTools[info.toolType]
                if not previous or level < previous.level or (level == previous.level and tostring(id) < tostring(previous.id)) then
                    nextTools[info.toolType] = {id = id, info = item, level = level, base = best[info.toolType] or 0}
                end
            end
        end
        for _, candidate in pairs(nextTools) do
            result[#result + 1] = {key = "craft:" .. candidate.id, id = candidate.id, kind = "craft", info = candidate.info,
                rank = (candidate.base == 0 and not work.meleeWeapon()) and 0.03 or (candidate.base == 0 and 1 or 3 + candidate.base / 100),
                name = itemLabel("tool", candidate.id, candidate.info), amounts = work.recipeAmounts(candidate.info)}
        end
        if flags.progression then
            local bestArmour, nextArmour = {}, {}
            for _, owned in ipairs(tools()) do
                local info = c.armour and c.armour.byDisplayName and c.armour.byDisplayName[owned.Name]
                if info then
                    local kind = info.armourType or info.typeCN or "armour"
                    bestArmour[kind] = math.max(bestArmour[kind] or 0, tonumber(info.lvl) or 0)
                end
            end
            for _,id in pairs(work.equippedArmour or{})do
                local info=c.armour and c.armour.byId[id]
                if info then local kind=info.armourType or info.typeCN or "armour";bestArmour[kind]=math.max(bestArmour[kind]or 0,tonumber(info.lvl)or 0)end
            end
            for id, info in pairs(c.armour and c.armour.byId or {}) do
                local item, level = c.item.byId[id], tonumber(info.lvl)
                local kind = info.armourType or info.typeCN or "armour"
                local previous = nextArmour[kind]
                if item and item.recipeId and level and level > (bestArmour[kind] or 0)
                    and count(item.displayName) == 0 and (not previous or level < previous.level) then
                    nextArmour[kind] = {id = id, item = item, level = level}
                end
            end
            for _, entry in pairs(nextArmour) do
                result[#result + 1] = {key = "armour:" .. entry.id, id = entry.id, kind = "craft", info = entry.item,
                    rank = 3.6, name = itemLabel("armour", entry.id, entry.item), amounts = work.recipeAmounts(entry.item)}
            end
        end
        for id, checked in pairs(selected.craft or {}) do
            local item = checked and c.item.byId[id]
            if item and item.recipeId and (work.stockCount and work.stockCount(id)or count(item.displayName))==0 then
                result[#result + 1] = {key = "selected:" .. id, id = id, kind = "craft", info = item,
                    rank = 2.5, name = itemLabel("craft", id, item), amounts = work.recipeAmounts(item)}
            end
        end
        table.sort(result, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.key < b.key) end)
        return result
    end
    function work.stationGoal(goal)
        if goal.kind == "bag" then return goal end
        if goal.kind ~= "craft" or not work.stationSynced or not work.station() then return end
        local c = config()
        for _, entry in ipairs(c.craftingContent and c.craftingContent.list or {}) do
            local item = c.item.byName[entry.itemName]
            if item and item.id == goal.id then
                local fire = work.fireState()
                if (tonumber(entry.campfireLvl) or 1) > (fire and fire.level or 1) then return end
                return {id = goal.id, info = goal.info, recipe = work.recipeAmounts(goal.info)}
            end
        end
    end
    function work.goalAmounts(goal)
        if not goal then return {} end
        if goal.kind == "build" then
            if built(goal.info.assetId) then return {} end
            return work.recipeAmounts(goal.info, true)
        end
        if goal.kind == "fuel" then
            local fresh = goal.maintenance and work.maintenanceGoal() or work.campfireGoal()
            return fresh and fresh.key == goal.key and fresh.amounts or {}
        end
        local station = work.stationGoal(goal)
        if station then
            if goal.kind == "bag" and not work.bagRank(goal.id) then return {} end
            if goal.kind == "craft" and count(goal.info.displayName) > 0 then return {} end
            local amounts = {}
            for id, n in pairs(station.recipe) do amounts[id] = math.max(0, n - ((work.stationStock or {})[id] or 0)) end
            return amounts
        end
        if goal.kind == "quest" then
            local req = work.questRequirement
            if not req or req.itemId ~= goal.itemId and goal.itemId ~= nil then return {} end
            return {[req.itemId] = math.max(0, req.count - #work.questDrops(req))}
        end
        if goal.kind == "craft" and count(goal.info.displayName) > 0 then return {} end
        return goal.amounts or {}
    end
    function work.supplyAmounts(goal)
        local amounts = work.goalAmounts(goal)
        local c = config()
        local result = c.misc.furnaceResultId
        if result and amounts[result] and built("Furnace") then
            local item = c.item.byId[result]
            local batches = math.max(0, amounts[result] - (item and count(item.displayName) or 0) - (furnaceData.readyCount or 0))
            local expanded = {}
            for id, n in pairs(amounts) do expanded[id] = n end
            for index, id in ipairs({c.misc.furnaceMatter1Id, c.misc.furnaceMatter2Id}) do
                expanded[id] = math.max(expanded[id] or 0, math.max(0, batches - (furnaceData["matter" .. index .. "Count"] or 0)))
            end
            return expanded
        end
        return amounts
    end
    function work.taskDemand(id, key)
        local goal = work.probingGoal or work.activeGoal or work.objective or work.selectedCraftMaterialGoal()
        if goal then
            local item = config().item.byId[id]
            return math.max(0, (work.supplyAmounts(goal)[id] or 0) - (item and count(item.displayName) or 0))
        end
        local item = config().item.byId[id]
        if work.needs[id] and work.needTotals and work.needTotals[id] then
            return math.max(0, work.needTotals[id] - (item and count(item.displayName) or 0))
        end
        return work.needs[id] and math.max(0, work.amounts[id] or 0) or 0
    end
    function work.needsDrop(id, key)
        if key == "stockpile" then return true end
        return (key ~= "progression" and not opts.onlyNeeded) or work.taskDemand(id, key) > 0
    end
    function work.submitGoal(key, goal)
        if not goal then return false end
        if work.craftUnlocked and not work.craftUnlocked(goal)then return false end
        local amounts, c = work.goalAmounts(goal), config()
        local has = false
        for id, n in pairs(amounts) do
            local item = c.item.byId[id]
            if n > 0 and item and count(item.displayName) > 0 then has = true break end
        end
        local station=work.stationGoal(goal)
        if station and (has or not next(work.missing(amounts))) then return work.stationTick(station,key) end
        if has then
            if goal.kind == "fuel" then
                local item = work.fuelItem()
                return item and work.addFireWood(key, math.min(count(item.displayName), amounts[item.id] or 0)) or false
            elseif goal.kind == "build" then return work.contribute(key, false, goal.id)
            elseif goal.kind == "quest" then return questTick(key, true) end
            local station = work.stationGoal(goal)
            if station then return work.stationTick(station, key) end
        end
        if goal.kind == "craft" and next(amounts) and not next(work.missing(amounts)) then
            for id,amount in pairs(amounts)do if work.spendable and work.spendable(id,key)<amount then return false end end
            return work.request(key, "CraftItems", "craft", goal.id)
        end
        local resultId = c.misc.furnaceResultId
        if resultId and amounts[resultId] and built("Furnace") and flags.smelt then
            local supply = work.supplyAmounts(goal)
            for _, id in ipairs({c.misc.furnaceMatter1Id, c.misc.furnaceMatter2Id}) do
                local material = c.item.byId[id]
                if material and (supply[id] or 0) > 0 and count(material.displayName) > 0 then
                    return work.smeltBag(key, supply)
                end
            end
        end
        return false
    end
    function work.stockCount(id)
        local item=config().item.byId[id]
        if not item then return 0 end
        local amount=count(item.displayName)
        for _,drop in ipairs(work.models("drops"))do
            if drop.Parent and drop.Name==item.displayName and work.markCampDrop(drop)then amount=amount+1 end
        end
        return amount+(work.storageCount and work.storageCount(id)or 0)
    end
    function work.selectedCraftMaterialGoal()
        if not flags.craft then return end
        local ids, c = {}, config()
        for id, enabled in pairs(selected.craft or {}) do if enabled then ids[#ids + 1] = id end end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local item = c.item.byId[id]
            if item and item.recipeId and(work.stockCount and work.stockCount(id)or count(item.displayName))==0 then
                local amounts = work.recipeAmounts(item)
                if next(amounts) then
                    return {key = "selected:" .. id, id = id, kind = "craft", info = item, amounts = amounts}
                end
            end
        end
    end
    function work.readyCraft(goal)
        if work.craftUnlocked and not work.craftUnlocked(goal)then return false end
        if not goal or (goal.kind ~= "craft" and goal.kind ~= "bag") or not goal.info then return false end
        if goal.kind == "bag" and not work.bagRank(goal.id) then return false end
        if goal.kind=="craft"and(goal.questFor and count(goal.info.displayName)>0
            or not goal.questFor and(work.stockCount and work.stockCount(goal.id)or count(goal.info.displayName))>0)then return false end
        if goal.kind == "bag" or work.stationGoal(goal) then
            local _, zone = work.station()
            if not work.stationSynced or not zone or not work.safeResource(zone) then return false end
        end
        local amounts=work.goalAmounts(goal)
        if not work.stationGoal(goal)then
            for id,amount in pairs(amounts)do if work.spendable and work.spendable(id,"craft")<amount then return false end end
        end
        return not next(work.missing(amounts))
    end
    function work.nextReadyCraft()
        local candidates = {}
        if flags.quest or flags.progression or flags.toolLadder or flags.bagUpgrade then candidates = work.upgradeCandidates() end
        if flags.craft then
            local c, ids = config(), {}
            for id, enabled in pairs(selected.craft or {}) do if enabled then ids[#ids + 1] = id end end
            table.sort(ids)
            for _, id in ipairs(ids) do
                local item = c.item.byId[id]
                if item and item.recipeId then
                    candidates[#candidates + 1] = {key = "selected:" .. id, id = id, kind = "craft", info = item, amounts = work.recipeAmounts(item)}
                end
            end
        end
        for _, goal in ipairs(candidates) do
            local manual = type(goal.key) == "string" and goal.key:sub(1, 9) == "selected:"
            if (not manual or flags.craft or flags.progression)
                and os.clock() >= (work.upgradeBlocked and work.upgradeBlocked[goal.key] or 0)
                and work.readyCraft(goal) then return goal end
        end
    end
    function work.goalRunnable(goal)
        if work.craftUnlocked and not work.craftUnlocked(goal)then return false end
        local amounts = work.goalAmounts(goal)
        local missing = work.missing(amounts)
        if goal.kind == "craft" and not work.stationGoal(goal) then
            local _, cap = work.bagState()
            local slots = 0
            for id, n in pairs(amounts) do if config().item.byId[id].isBagItem then slots = slots + n end end
            if slots > cap then return false end
        end
        if not next(missing) then return true end
        if flags.useStorage and work.storageCount then
            for id in pairs(missing) do if work.storageCount(id)>0 then return true end end
        end
        for id, amount in pairs(amounts) do
            local item = config().item.byId[id]
            if amount > 0 and item and count(item.displayName) > 0
                and (goal.kind == "quest" or goal.kind == "fuel" or goal.kind == "build" or goal.kind == "bag" or work.stationGoal(goal)) then return true end
        end
        if not work.canCollect() then return false end
        local c = config()
        local needs, amounts, resourceNeeds = work.needs, work.amounts, work.resourceNeeds
        local previousProbe = work.probingGoal
        work.probingGoal = goal
        work.needs, work.amounts, work.resourceNeeds = {}, {}, {}
        local ready = false
        local ok, err = pcall(function()
            for id, amount in pairs(missing) do
                if id == c.misc.furnaceResultId and built("Furnace") then
                    if (furnaceData.readyCount or 0) > 0 then ready = true end
                    for _, ingredient in ipairs({c.misc.furnaceMatter1Id, c.misc.furnaceMatter2Id}) do
                        local item = c.item.byId[ingredient]
                        if item then
                            if count(item.displayName) > 0 then ready = true end
                            work.needs[ingredient], work.amounts[ingredient] = 100, amount
                        end
                    end
                else work.needs[id], work.amounts[id] = 100, amount end
            end
            for id, resource in pairs(c.worldResource.byId) do
                for _, drop in pairs(c.itemDrop and c.itemDrop.byId[resource.dropId] or {}) do
                    local item = type(drop) == "table" and c.item.byName[drop.itemCN]
                    if item and work.needs[item.id] then work.resourceNeeds[id] = 100 end
                end
            end
            if not ready then
                ready = work.pickupCandidate(true) ~= nil or work.resourceCandidate("progression", true) ~= nil
                    or work.huntCandidate(work.needs) ~= nil
            end
        end)
        work.needs, work.amounts, work.resourceNeeds = needs, amounts, resourceNeeds
        work.probingGoal = previousProbe
        if not ok then error(err) end
        return ready
    end
    function work.goalQueueRank(goal)
        if goal.kind == "quest" or goal.questFor then return -170 end
        if goal.kind == "fuel" and not goal.maintenance then return -115 end
        if goal.kind == "fuel" and (goal.maintenance or campData.isOnFire == false) then return -200 end
        if goal.kind == "build" and work.buildRank(goal.info) == 0 then return -190 end
        if goal.kind == "build" then
            local name = tostring(goal.info.assetId):lower()
            if work.buildRank(goal.info) == 1 then return -150 end
            if name:find("furnace", 1, true) or name == "熔炉" then return -120 end
            if goal.id ~= work.boatId() then return -105 end
        end
        if work.gearPriority and work.gearPriority(goal)then return -155+(tonumber(goal.rank)or 0)end
        if goal.kind == "bag" then return -130 + (tonumber(goal.rank) or 0) end
        if goal.kind == "craft" then return -100 + (tonumber(goal.rank) or 0) end
        return tonumber(goal.rank) or 100
    end
    function work.chooseUpgrade()
        work.upgradeBlocked = work.upgradeBlocked or {}
        local candidates = work.upgradeCandidates()
        local signature=work.signature()
        if signature~=work.objectiveSignature then
            work.objectiveSignature,work.objectiveProgressAt=signature,os.clock()
        end
        local pinned=work.objective and os.clock()-(work.objectiveProgressAt or 0)<7 and work.objective.key
        table.sort(candidates, function(a, b)
            local ar, br = work.goalQueueRank(a), work.goalQueueRank(b)
            local ae=a.kind=="fuel" and a.maintenance==true
            local be=b.kind=="fuel" and b.maintenance==true
            if ae~=be then return ae==true end
            local aq=a.kind=="quest" or a.questFor~=nil
            local bq=b.kind=="quest" or b.questFor~=nil
            if aq~=bq then return aq end
            if pinned and ar==br and ((a.key==pinned)~=(b.key==pinned)) then return a.key==pinned end
            return ar < br or (ar == br and a.key < b.key)
        end)
        for _, goal in ipairs(candidates) do
            local blocked = work.upgradeBlocked[goal.key]
            if not blocked or blocked <= os.clock() then
                work.upgradeBlocked[goal.key] = nil
                local signature = work.signature()
                work.goalProbes = work.goalProbes or {}
                local probe = work.goalProbes[goal.key]
                if not probe or probe.signature ~= signature or os.clock() >= probe.untilTime then
                    probe = {signature = signature, untilTime = os.clock() + 0.35, ready = work.goalRunnable(goal)}
                    work.goalProbes[goal.key] = probe
                end
                if probe.ready then
                    if not work.objective or work.objective.key~=goal.key then work.objectiveProgressAt=os.clock() end
                    work.objective = goal return goal
                end
            end
        end
        work.objective = nil
    end
    function work.planProgression()
        local goal = (work.active == "progression" and work.activeGoal) or work.chooseUpgrade()
        work.processing = nil
        if not goal then
            note("progression", "NO AVAILABLE UPGRADE / BLUEPRINT")
            if work.upgradeLabel then work.upgradeLabel.Text = "NO AVAILABLE UPGRADE / BLUEPRINT" end
            return
        end
        local amounts = work.goalAmounts(goal)
        local missing = work.missing(amounts)
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
                work.needItem(id, amounts[id], 100)
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
        local missing = work.missing(work.goalAmounts(goal))
        local used, cap = work.bagState()
        local full = used and cap and used >= cap
        work.activeGoal = goal
        if work.reclaimStorage and work.reclaimStorage(goal,"progression") then return true end
        if not work.batchReady or work.batchReady(goal,"progression")then acted = work.submitGoal("progression", goal)end
        if not acted and full then
            acted = work.tidyBag("progression")
            if not acted then note("progression", "BAG FULL: NO VALID DEPOSIT; ITEMS KEPT") end
            return acted
        end
        if work.preempted then return acted end
        if not acted and work.processing and flags.smelt then
            if (furnaceData.readyCount or 0) > 0 and work.canCollect() then
                acted = travel(built("Furnace"), "progression") and work.request("progression", "Furnace", "collectResult")
            else
                local c = config()
                local a, b = c.item.byId[c.misc.furnaceMatter1Id], c.item.byId[c.misc.furnaceMatter2Id]
                if a and b and (count(a.displayName) > 0 or count(b.displayName) > 0) then
                    acted = work.smeltBag("progression")
                end
            end
        end
        if not acted and next(work.needs) and work.canCollect() then
            acted = pickups("progression", true)
            if not acted then acted = gatherResource("progression", true) end
            if not acted then acted = work.huntForMaterials("progression") end
        end
        if work.preempted then return acted end
        work.refreshAt = 0
        work.refreshNeeds()
        if acted or work.signature() ~= before then work.upgradeStalls = 0
        else
            work.upgradeStalls = (work.upgradeStalls or 0) + 1
            if work.upgradeStalls >= 1 then
                work.upgradeBlocked[goal.key] = os.clock() + 0.75
                work.goalProbes = nil
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
        work.needTotals = {}
        work.resourceNeeds = {}
        local c = config()
        if flags.quest or work.progressionEnabled() then work.readQuest(false) end
        if work.progressionEnabled() then
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
                local goal = work.selectedCraftMaterialGoal()
                if goal then work.needRecipe(goal.info, 60) end
            end
        end
        local w = world()
        if flags.quest and work.questRequirement then
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
        if flags.autoFarm == false or work.finished or work.roundLost() or work.nightPaused(job) then return false end
        return job.enabled and job.enabled() or (not job.enabled and flags[job.key] == true)
    end
    function work.keyEnabled(key)
        if flags.autoFarm == false or work.finished or work.roundLost() then return false end
        if key == "progression" and work.progressionEnabled() then return true end
        if flags[key] == true then return true end
        local job = work.jobsByKey and work.jobsByKey[key]
        return job and work.jobEnabled(job) or false
    end
    function work.rank(job)
        local key = job.key
        if key == "evade" then return 0 end
        if key=="shadowHunt"then return 1.4 end
        if key=="greatWall"then return 6.8 end
        if key=="equipArmour"then return 2.9 end
        if key=="questAcquire"then return 3.012 end
        if key=="combat"then
            if work.combatUrgent then return work.combatUrgent()and 1.5 or 6.5 end
            return(flags.combat and work.baseThreat())and 1 or 1.5
        end
        if key == "escape" and opts.emergencyEscape then return 0.8 end
        if key == "mrbeastReward" then return 3.005 end
        if key=="eat"then return work.criticalMeal and work.criticalMeal()and .4 or 2 end
        if key == "fuel" then return 3 end
        if key == "craft" then return flags.progression and 3.018 or 3.5 end
        if key == "cooked" then return (flags.stormStock or work.noFood()) and 3.1 or 7.4 end
        if key == "foodPickup" then return 3.15 end
        if key == "cook" then
            local used,cap=work.bagState()
            if used>=cap and work.rawFoodOwned() and work.cookReady() then return 3.02 end
            return (flags.stormStock or work.noFood()) and 3.2 or 7.5
        end
        if key=="foodHunt"then return 3.025 end
        if key=="toolTidy"then return 3.03 end
        if key == "hunt" then return (flags.killFoodOnSight or work.foodHuntReady()) and 3.3 or 8.8 end
        if key == "foodSupply" then return work.mealNeeded()and 2.01 or 3.12 end
        if key == "foodCache" then return work.mealNeeded()and work.noFood()and 1.99 or 3.04 end
        if key == "autoAttack" then return 1.6 end
        if key == "structures" then return 3.55 end
        if key == "stockpile" then return 7.8 end
        if key == "quest" then return 3.01 end
        if key == "bagUpgrade" then return 4 end
        if key == "unloadBag" then
            if work.active == key and work.unloadRank then return work.unloadRank end
            local used, cap = work.bagState()
            return used >= cap and 3.08 or 4.05
        end
        if key == "chests" and work.chestResume then return 4.2 end
        if key == "tidyBag" then
            if work.active == "tidyBag" and work.bagSweepRank then return work.bagSweepRank end
            local used, cap = work.bagState()
            return used >= cap and 4 or 5.8
        end
        if key == "progression" then
            local goal = work.objective
            if goal and goal.kind == "fuel" then return (goal.maintenance or campData.isOnFire == false) and 3 or 3.45 end
            if goal and work.gearPriority and work.gearPriority(goal)then return 3.02 end
            if goal and goal.kind == "bag" then return 4.1 end
            if goal and (goal.kind == "quest" or goal.questFor) then return 3.015 end
            if goal and goal.id and goal.id == work.boatId() then return 9 end
            return 5
        end
        local rank = {buildCurrent=5.1,build=5.2,craft=5.3,smeltCollect=5.4,smelt=5.5,
            mrbeastReward=6,quest=6.1,recoverDrops=7,drops=7.1,gather=7.2,water=7.3,
            chests=8,puzzles=8.1,artifacts=8.2,escape=9.1,travel=9.2,nightHold=10,fish=10.5}
        if key=="nightHold"and not work.hover and work.shelterNeeded()then
            local _,human=root()
            return human and human.Health/human.MaxHealth*100<=opts.retreatHealth and .3 or 9.5
        end
        return rank[key] or 11
    end
    function work.pick(jobs, now, ceiling, urgentOnly)
        local best, bestScore
        for _, job in ipairs(jobs) do
            if job.key ~= work.skipJob and now >= (due[job.key] or 0) then
                local ok, ready, rank = pcall(function()
                    local rank = work.rank(job)
                    if work.hover and job.key ~= "nightHold" and job.key ~= "fuel" and job.key ~= "eat" and job.key~="foodCache" then return false,rank end
                    if urgentOnly and not work.interruptsInteraction(job) then return false,rank end
                    if (ceiling and rank >= ceiling) or (bestScore and rank >= bestScore) then return false, rank end
                    if not work.jobEnabled(job)then return false,rank end
                    local previous=work.readinessKey;work.readinessKey=job.key
                    local ok,result=pcall(function()return not job.ready or job.ready()end)
                    work.readinessKey=previous
                    if not ok then error(result)end
                    return result,rank
                end)
                if not ok then
                    note(job.key, "READINESS ERROR: " .. tostring(ready)) due[job.key] = now + 0.5
                elseif ready then
                    best, bestScore = job, rank
                    if rank == 0 then break end
                end
            end
        end
        return best, bestScore
    end
    function work.nextQueuedJob(jobs, now)
        local pending=work.pendingHandoff
        if not pending then return work.pick(jobs,now) end
        -- Re-check emergencies before honoring a routine handoff. Keep the
        -- handoff queued if survival work needs to run first.
        local emergency,rank=work.pick(jobs,now,nil,true)
        if emergency then return emergency,rank end
        work.pendingHandoff=nil
        local job=work.jobsByKey and work.jobsByKey[pending]
        if job then
            local ready,score=work.pick({job},now)
            if ready then return ready,score end
        end
        return work.pick(jobs,now)
    end
    function work.checkpoint(key)
        if not work.active or not work.currentJob or not work.jobs then return true end
        if work.preempted then return false end
        local held=work.interaction
        local validHold=held and held.key==key and os.clock()<(held.untilTime or 0)
        if work.nightPaused(work.currentJob)and not validHold then
            work.preempted = {from = work.active, to = "nightHold", rank = 10}
            motion.cancel("NIGHT HOLD • ROUTINE WORK PAUSED")
            return false
        end
        if key=="questAcquire"and work.questWork and not work.questPlanCurrent(work.questWork)then
            motion.cancel("MRBEAST REQUEST CHANGED • REPLANNING ACQUISITION")
            return false
        end
        if os.clock() < (work.nextPriorityCheck or 0) then return true end
        work.nextPriorityCheck = os.clock() + 0.03
        local now, r = os.clock(), root()
        local signature = work.signature()
        if signature ~= work.progressSignature or (r and work.progressPosition
            and (r.Position-work.progressPosition).Magnitude >= 2) then
            work.progressAt, work.progressSignature = now, signature
            work.progressPosition = r and r.Position
        end
        work.progressAt = work.progressAt or now
        work.progressPosition = work.progressPosition or (r and r.Position)
        local interaction = work.interaction
        local protected = interaction and interaction.key == key and now < interaction.untilTime
        -- Protect native holds and receipts, but travelling is interruptible.
        -- Movement alone must not keep a lower-priority job ahead of a ready
        -- food hunt, quest delivery or camp task indefinitely.
        local job, rank = work.pick(work.jobs, now, work.rank(work.currentJob), true)
        if not job and not protected and motion.owner==key and not work.bulkTrip then
            job,rank=work.pick(work.jobs,now,work.rank(work.currentJob))
            if job then work.pendingHandoff=job.key end
        end
        if not job and not protected and not work.isNight() and now-work.progressAt >= 7 then
            work.skipJob = key
            job, rank = work.pick(work.jobs, now)
            work.skipJob = nil
            if job then due[key] = now + 1 work.pendingHandoff = job.key end
        end
        if job then
            if job.key == "evade" then work.captureEvadeIntent() end
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
    function work.strike(tool, stats, targets, resources, key, retaliation)
        equip(tool)
        if work.setSprint then work.setSprint(false) end
        if not work.pause(key, math.max(0, (work.nextStrikeAt or 0) - os.clock())) then return false end
        if not work.checkpoint(key) then return false end
        local r = root()
        if not r or tool.Parent ~= player.Character then return false end
        for _, model in ipairs(targets) do
            if not model.Parent or not work.stanceScore(r.Position, model, stats, retaliation) then return false end
        end
        for _, model in ipairs(resources) do
            if not model.Parent or not work.safeResource(model)
                or (r.Position - pos(model)).Magnitude > (stats.range or 6) then return false end
        end
        work.nextStrikeAt = os.clock() + math.max(0, tonumber(stats.useCd) or 0.7)
        if #targets > 0 then
            -- Bound the commitment to this native windup/hit window. Survival
            -- checks still cancel on new damage, known strikes or unsafe health.
            local _,human=root()
            work.attackCommit={target=targets[1],health=human.Health,
                expires=os.clock()+math.min(tonumber(stats.windup)or 0,tonumber(stats.useCd)or .7)+.5}
            if work.activateWeapon then
                if not work.activateWeapon(tool,stats,targets[1],key)then work.attackCommit=nil return false end
            else tool:Activate() end
        else
            RS.Events.meleeHitRemote:FireServer(targets, resources)
        end
        work.sent = work.sent + 1
        if #targets>0 then work.attackRequests=(work.attackRequests or 0)+1 end
        return true
    end
    local function blueprintReady(onlySelected)
        local folder = world() and world():FindFirstChild("Buildings")
        if not folder then
            return false
        end
        local c = config()
        for id, info in pairs(c.build.byId) do
            if (flags.buildBoat or id ~= work.boatId()) and (not onlySelected or allowed("build", id))
                and folder:FindFirstChild(info.assetId .. "_Construct") then
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
        local _, human = root()
        if opts.emergencyEscape then
            if not human or human.Health / human.MaxHealth * 100 > opts.retreatHealth or not work.noFood()
                or not (work.shadowThreat() or work.baseThreat() or work.personalThreat()) then return false end
        end
        local w = world()
        if not w then
            return false
        end
        for _, o in ipairs(work.models("escape")) do
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
    work.counts = {felled = 0, picked = 0, guarded = 0, escapes = 0}
    work.artifactNames = {Compass = true, Map = true, ["Plastic Bucket"] = true, Radio = true}
    function work.progressionEnabled()
        return flags.quest or flags.progression or flags.toolLadder or flags.buildCamp or flags.buildBoat or flags.tidyBag or flags.fuel
    end
    function work.isNight()
        local scene = world()
        local phase = scene and scene:FindFirstChild("Phase")
        return phase and tostring(phase.Value):lower():find("night", 1, true) ~= nil or false
    end
    function work.nightPaused(job)
        if not flags.holdNight or not work.isNight() then return false end
        if flags.nightExplore and work.nightClear and work.nightClear()then return false end
        local routine = {greatWall=true,gather=true,drops=true,chests=true,puzzles=true,artifacts=true,travel=true,fish=true,stockpile=true}
        if routine[job.key] then return true end
        if job.key == "hunt" then return not work.foodHuntReady() end
        if job.key == "progression" then
            local goal = work.objective
            if not goal then return true end
            if goal.kind == "fuel" and campData.isOnFire == false then return false end
            if goal.kind == "build" and work.buildRank(goal.info) == 0 then return false end
            if goal.id and goal.id == work.boatId() then return true end
            return next(work.missing(goal.amounts)) ~= nil
        end
        return false
    end
    function work.resourceKind(info)
        local c,kind=config()
        for _,entry in pairs(c.itemDrop and c.itemDrop.byId[info.dropId]or{})do
            local item=type(entry)=="table"and c.item.byName[entry.itemCN]
            local id=item and(tostring(item.id).." "..tostring(item.displayName or"").." "..tostring(entry.itemCN or"")):lower()or""
            if item and(item.id==c.misc.furnaceMatter1Id or id:find("iron",1,true)or id:find("铁",1,true))then return "iron"end
            if id:find("stone",1,true)or id:find("rock",1,true)or id:find("石",1,true)then kind="stone"
            elseif not kind and(id:find("wood",1,true)or id:find("timber",1,true)or id:find("木",1,true))then kind="tree"end
        end
        return kind or(info.requireToolType=="axe"and"tree"or"other")
    end
    function work.resourceAllowed(info, key)
        if key == "progression" or key == "stockpile" or key == "structures" or key=="greatWall"or key=="questAcquire"then return true end
        local kind = work.resourceKind(info)
        return flags.gather or (kind == "tree" and flags.chopTrees)
            or (kind == "stone" and flags.mineStone) or (kind == "iron" and flags.mineIron)
    end
    function work.resourceTool(info)
        local stamp = math.floor(os.clock() * 120)
        if work.resourceToolStamp ~= stamp then work.resourceToolCache = {} work.resourceToolStamp = stamp end
        work.resourceToolCache = work.resourceToolCache or {}
        local key = info.requireToolType or "__unknown"
        local cached = work.resourceToolCache[key]
        if cached then return cached.tool, cached.stats end
        local best, stats
        for _, tool in ipairs(tools()) do
            local row = config().tool.byDisplayName[tool.Name]
            if row and (info.requireToolType == "any" or row.toolType == info.requireToolType)
                and (not stats or (row.useDmg or 0) > (stats.useDmg or 0)) then best, stats = tool, row end
        end
        work.resourceToolCache[key] = {tool = best, stats = stats}
        return best, stats
    end
    function work.boatId()
        for id, info in pairs(config().build.byId or {}) do
            if id == "boat" or tostring(info.assetId):lower():find("boat", 1, true) then return id end
        end
    end
    function work.artifactCandidate()
        local scene = world()
        return nearest(work.models("artifacts"), function(model)
            if not model:IsA("Model") or not work.artifactNames[model.Name] then return false end
            local part = model:FindFirstChild("promptPart")
            local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
            return prompt and prompt.Enabled and not work.artifacts[model.Name] and work.safeResource(model)
                and not (failed[model] and failed[model] > os.clock())
        end)
    end
    function work.exploreAvailable(kind)
        local c, scene = config(), world()
        local rows = kind == "chest" and c.chest.byId or c.mapProp.byCnId
        local folder = kind == "chest" and scene and scene:FindFirstChild("Chest") or scene
        for _, model in ipairs(work.models(kind == "chest" and "chests" or "explore")) do
            if model:IsA("Model") and rows[model.Name] and work.safeResource(model)
                and not (failed[model] and failed[model] > os.clock()) then return true end
        end
        return false
    end
    function work.fetchArtifact()
        local model = work.artifactCandidate()
        if not model then return false end
        local part = model:FindFirstChild("promptPart")
        local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
        if not prompt or not travel(part, "artifacts", math.max(1, prompt.MaxActivationDistance - 1)) then return false end
        if not work.interactPrompt(model, "artifacts") then return false end
        local confirmed = work.await("artifacts", function() return not model.Parent or work.artifacts[model.Name] end,
            math.max(2, prompt.HoldDuration + 1))
        if not work.preempted then failed[model] = os.clock() + (confirmed and 0.1 or 2) end
        note("artifacts", confirmed and "ARTIFACT COLLECTED" or "ARTIFACT NOT CONFIRMED / INTERRUPTED")
        return confirmed
    end
    work.artifacts = {}
    function work.bindSuite()
        if work.suiteBound then return end
        work.suiteBound = true
        local inventoryService = RS.Engine.Service:FindFirstChild("PlayerInventory")
        local inventoryChanged = inventoryService and inventoryService:FindFirstChild("inventoryChangedRemote")
        if inventoryChanged then connections[#connections + 1] = inventoryChanged.OnClientEvent:Connect(work.invalidateInventory) end
        local extra = RS.Engine.Service:FindFirstChild("BoatExtra")
        local changed = extra and extra:FindFirstChild("requiresUpdRemote")
        local function update(list)
            work.artifacts = {}
            for _, name in ipairs(type(list) == "table" and list or {}) do work.artifacts[name] = true end
        end
        if changed then connections[#connections + 1] = changed.OnClientEvent:Connect(update) end
        local get = extra and extra:FindFirstChild("requiresGetRemote")
        if get then task.spawn(function()
            local ok, list = pcall(function() return get:InvokeServer() end)
            if alive and ok then update(list) end
        end) end
        local result = RS.Engine.Service:FindFirstChild("GameResult")
        result = result and result:FindFirstChild("onResultRemote")
        if result then connections[#connections + 1] = result.OnClientEvent:Connect(function()
            if not work.finished then work.counts.escapes = work.counts.escapes + 1 end
            work.finished = true
        end) end
        connections[#connections + 1] = gui.Destroying:Connect(function()
            work.releaseHover(true)
            work.clearESP()
            work.clearSceneIndex()
            if work.espFolder then work.espFolder:Destroy() end
        end)
    end
    function work.shadowThreat()
        if not flags.runShadow or not work.isNight() then return end
        local r = root()
        if not r then return end
        for _, row in ipairs(work.hostiles()) do
            if (row.model.Name:lower():find("shadow", 1, true) or not row.attackable)
                and (row.point - r.Position).Magnitude < opts.shadowRadius then return row.model end
        end
    end
    function work.noFood()
        for _, tool in ipairs(tools()) do
            local item = config().item.byDisplayName[tool.Name]
            if item and work.foodAllowed("food", item.id) then return false end
        end
        return true
    end
    function work.rawFoodOwned()
        for _, tool in ipairs(tools()) do
            local item = config().item.byDisplayName[tool.Name]
            local food = item and config().food.byId[item.id]
            if food and food.canCook and (tonumber(tool:GetAttribute("count")) or 1) > 0 then return true end
        end
        return false
    end
    function work.foodDropCandidate()
        for i = #(work.huntLoot or {}), 1, -1 do
            if os.clock() > work.huntLoot[i].expires then table.remove(work.huntLoot, i) end
        end
        local c, req = config(), flags.quest and work.questRequirement
        local foodNeeded = (flags.killFoodOnSight or flags.stormStock and work.foodShortage())
            or flags.huntFood and work.noFood() and not work.rawFoodOwned() and (campData.readyCount or 0) == 0
        local wanted = work.huntWanted()
        return nearest(work.models("drops"), function(model)
            local item = c.item.byDisplayName[model.Name]
            if not item or not work.dropAllowed(model) or not work.safeResource(model)
                or work.pickupEligible and not work.pickupEligible(model) then return false end
            local questNeeded = req and item.id == req.itemId and work.questTotal(req) < req.count
            if questNeeded then return true end
            if foodNeeded and c.food.byId[item.id] then return true end
            for _, context in ipairs(work.huntLoot or {}) do
                local point = pos(model)
                if os.clock() <= context.expires and not context.before[model] and context.wanted[item.id]
                    and point and context.center and (point - context.center).Magnitude <= 16
                    and (flags.hunt or wanted[item.id] or work.taskDemand(item.id, "progression") > 0) then return true end
            end
            return false
        end)
    end
    function work.collectHuntedFood()
        local collected = false
        while work.canCollect() and work.checkpoint("foodPickup") do
            local drop = work.foodDropCandidate()
            if not drop then return collected end
            if not work.collectModel(drop, "foodPickup") then return collected end
            collected = true
            local info=config().item.byDisplayName[drop.Name]
            if info and work.isCookedFood and work.isCookedFood(info.id) then return true end
            local req = flags.quest and work.questRequirement
            if req and(not flags.bulkCollect or work.questTotal(req)>=req.count or not work.canCollect())then questTick("foodPickup",true)end
        end
        return collected
    end
    function work.foodHuntReady()
        if flags.killFoodOnSight or flags.stormStock then
            return work.foodHuntCandidate and work.foodHuntCandidate() ~= nil or false
        end
        if not flags.huntFood or not work.noFood() or work.rawFoodOwned() or not work.canCollect()
            or (campData.readyCount or 0) > 0 or not work.meleeWeapon() then return false end
        local r = root()
        if not r then return false end
        for _, row in ipairs(work.creatures()) do
            if row.attackable and work.mobDropsFood(row.model) and (row.point - r.Position).Magnitude <= opts.huntRadius then return true end
        end
        return false
    end
    function work.mobYields(model, wanted)
        local c = config()
        local mob=work.mobInfo and work.mobInfo(model)or c.mob and c.mob.byId[model.Name]
        for _, entry in pairs(mob and c.itemDrop and c.itemDrop.byId[mob.dropId] or {}) do
            local item = type(entry) == "table" and c.item.byName[entry.itemCN]
            if item and wanted[item.id] and wanted[item.id] > 0 then return true end
        end
        return false
    end
    function work.huntWanted()
        if work.huntingNeeds then return work.huntingNeeds end
        local wanted, c = {}, config()
        local req = flags.quest and work.questRequirement
        local goal = work.activeGoal or work.objective
        if req and work.questTotal(req) < req.count then wanted[req.itemId] = req.count - work.questTotal(req) end
        if flags.killFoodOnSight or flags.stormStock and work.foodShortage()
            or flags.huntFood and work.noFood() and not work.rawFoodOwned() and (campData.readyCount or 0) == 0 then
            for id in pairs(c.food.byId) do wanted[id] = math.max(1, wanted[id] or 0) end
        end
        return wanted
    end
    function work.huntEligible(model)
        if work.huntingPassive then return work.isPassiveFood(model)end
        if work.huntingNeeds then return work.mobYields(model,work.huntingNeeds) end
        if flags.killFoodOnSight and work.isPassiveFood and work.isPassiveFood(model) then return true end
        return (not work.huntingNeeds and flags.hunt) or work.mobYields(model, work.huntWanted())
    end
    function work.huntCandidate(wanted)
        local r=root();local tool,stats=work.meleeWeapon("hunt")
        if not r or not work.canCollect()or not tool then return end
        if flags.killFoodOnSight and os.clock()<(work.foodHuntAt or 0) then return end
        for _, row in ipairs(work.creatures()) do
            if row.attackable and row.human.Health > 0 and row.model.Parent
                and (row.point - r.Position).Magnitude <= opts.huntRadius
                and work.insideBorder(row.point)
                and(work.safeResource(row.model)or stats and work.combatPosition and work.combatPosition(row.model,stats))
                and not (failed[row.model] and failed[row.model] > os.clock())
                and work.mobYields(row.model, wanted) then return row.model end
        end
    end
    function work.huntForMaterials(key)
        if not work.huntCandidate(work.needs) then return false end
        local previous = work.huntingNeeds
        work.huntingNeeds, work.attackPlanCache = work.needs, nil
        local ok, result = pcall(defend, key)
        work.huntingNeeds, work.attackPlanCache = previous, nil
        if not ok then error(result) end
        return result
    end
    function work.mobDropsFood(model)
        local c = config()
        local info=work.mobInfo and work.mobInfo(model)or c.mob and c.mob.byId[model.Name]
        for _, entry in pairs(info and c.itemDrop and c.itemDrop.byId[info.dropId] or {}) do
            local item = type(entry) == "table" and c.item.byName[entry.itemCN]
            if item and c.food and c.food.byId[item.id] then return true end
        end
        local name=model.Name:lower()
        return name:find("chicken",1,true)~=nil or name:find("crab",1,true)~=nil
    end
    function work.bagSubmissionReady()
        if blueprintReady(false) then return true end
        local item = work.fuelItem()
        if flags.fuel and item and count(item.displayName) > 0 and work.maintenanceGoal() then return true end
        if flags.cook and work.cookReady() then return true end
        if flags.smelt and built("Furnace") then
            local c = config()
            for _, id in ipairs({c.misc.furnaceMatter1Id, c.misc.furnaceMatter2Id}) do
                local material = c.item.byId[id]
                if material and count(material.displayName) > 0 then return true end
            end
        end
        return false
    end
    function work.tidyBag(key, force)
        key = key or "tidyBag"
        local used, cap = work.bagState()
        if used < cap and not force and not flags.tidyBag then return false end
        if key == "tidyBag" then work.bagSweepRank = used >= cap and 4 or 5.8 end
        local acted = false
        local character, serial = player.Character, motion.serial
        if key == "tidyBag" and work.submitGoal(key, work.objective) then return true end
        local function proceed() return work.running(key, character, serial) end
        local item, fuelGoal = work.fuelItem(), flags.fuel and work.maintenanceGoal()
        if fuelGoal and item and count(item.displayName) > 0 then
            acted = work.addFireWood(key, fuelGoal.amounts[item.id]) or acted
        end
        if not proceed() then return acted end
        local req = flags.quest and work.questRequirement
        if req then
            local required = config().item.byId[req.itemId]
            if required and count(required.displayName) > 0 then acted = questTick(key) or acted end
        end
        if not proceed() then return acted end
        local goal = work.bagGoal()
        if goal then
            for id, amount in pairs(goal.amounts) do
                local material = config().item.byId[id]
                if amount > 0 and material and count(material.displayName) > 0 then
                    acted = work.stationTick(goal, key) or acted
                    break
                end
            end
        end
        if not proceed() then return acted end
        acted = work.contribute(key, false) or acted
        if not proceed() then return acted end
        if flags.smelt and built("Furnace") then acted = work.smeltBag(key) or acted end
        if not proceed() then return acted end
        if flags.cook and work.cookReady() then
            if travel(built("Campfire"), key) then
                for id, food in pairs(config().item.byId) do
                    if work.foodAllowed("cook", id) and work.cookCompatible(id) and count(food.displayName) > 0 then
                        acted = work.submitUnits(key, "MakeFire", "addFood", {[id] = count(food.displayName)}, id) or acted
                        break
                    end
                end
            end
        end
        if not acted then note(key, "NO USABLE DESTINATION; ITEMS KEPT") end
        work.refreshAt = 0
        return acted
    end
    function work.shelterNeeded()
        if not work.isNight()then work.hoverSuppressed=nil;return false end
        if flags.nightExplore and work.nightClear and work.nightClear()then return false end
        return flags.holdNight==true and flags.nightHover and not(work.hoverSuppressed and work.hoverSuppressed.scene==world()
            and work.hoverSuppressed.character==player.Character)or false
    end
    function work.releaseHover(force,service)
        local state = work.hover
        if not state then return true end
        local landing = state.land
        if not force and state.character == player.Character then
            if work.shelterNeeded()and not service then return false end
            landing = nil
            -- Check ground around camp instead of falling into the same swarm.
            for i=0,11 do
                local angle=i*math.pi/6
                local probe=state.land.Position+Vector3.new(math.cos(angle)*14,0,math.sin(angle)*14)
                local ground=motion.floor(probe,nil,20,20)
                if ground then
                    local _,human=root()
                    local point=ground+Vector3.new(0,(human and human.HipHeight or 2)+state.root.Size.Y/2,0)
                    if work.insideBorder(point,nil,"nightHold")and work.safeWorkPoint(point,8)
                        and(not work.hoverBodyClear or work.hoverBodyClear(point))then landing=CFrame.new(point)break end
                end
            end
            if not landing then note("nightHold","WAITING FOR CLEAR LANDING NEAR CAMP") return false end
        end
        work.hover = nil
        if state.root.Parent then
            if state.character == player.Character and landing then state.root.CFrame = landing end
            state.root.Anchored = state.anchored
        end
        return true
    end
    function work.hoverClearance(point,rows)
        local clearance=math.huge
        for _,row in ipairs(rows or work.hostiles(true))do
            if row.model.Parent and row.human.Health>0 then
                local predicted=row.point+(row.velocity or Vector3.new(0,0,0))*.35
                local dx,dz=point.X-predicted.X,point.Z-predicted.Z
                local reach=work.enemyReach(row.model)+(opts.combatMargin or 1)+6
                if not row.attackable or row.model.Name:lower():find("shadow",1,true)then reach=math.max(reach,opts.shadowRadius or 60)end
                clearance=math.min(clearance,math.sqrt(dx*dx+dz*dz)-reach)
            end
        end
        return clearance
    end
    function work.hoverBodyClear(point)
        local params=OverlapParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        local ignore={player.Character}
        local scene=world()
        for _,name in ipairs({"DroppedItems","Entities"})do local folder=scene and scene:FindFirstChild(name);if folder then ignore[#ignore+1]=folder end end
        params.FilterDescendantsInstances,params.RespectCanCollide=ignore,true
        local r=root();if r then params.CollisionGroup=r.CollisionGroup end
        for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(point),Vector3.new(3,4,3),params))do
            if part.CanCollide then return false end
        end
        return true
    end
    function work.hoverDestination(fire,height,previous,moved)
        local r,human=root();local center=pos(fire)
        if not r or not center then return nil end
        local candidates={};local threats=work.hostiles(true)
        for _,radius in ipairs({7,12,20,32,48,64})do
            for n=0,11 do
                local angle=n*math.pi/6
                local ground=motion.floor(center+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),fire,24,20)
                if ground then
                    local land=ground+Vector3.new(0,human.HipHeight+r.Size.Y/2,0)
                    local point=land+Vector3.new(0,height,0)
                    local clearance=work.hoverClearance(point,threats)
                    local shift=previous and Vector3.new(point.X-previous.X,0,point.Z-previous.Z).Magnitude or math.huge
                    if work.insideBorder(land,nil,"nightHold")and clearance>=0 and(not moved or shift>=10)then
                        local score=math.min(100,clearance)*2-radius*.5-(point-r.Position).Magnitude*.02
                        candidates[#candidates+1]={land=land,point=point,score=score,clearance=clearance}
                    end
                end
            end
        end
        table.sort(candidates,function(a,b)return a.score>b.score end)
        for n=1,math.min(12,#candidates)do if work.hoverBodyClear(candidates[n].point)then return candidates[n]end end
    end
    function work.hoverTick()
        local state=work.hover
        if not state then return false end
        local r,human=root()
        if not r or r~=state.root or player.Character~=state.character or flags.autoFarm==false then work.releaseHover(true);return false end
        local now=os.clock()
        if now<(state.nextCheck or 0)then return true end
        state.nextCheck=now+.15
        if not work.shelterNeeded()and work.releaseHover()then return true end
        local lost=math.max(0,state.health-human.Health)
        local damaged=lost>0
        state.health=human.Health
        local clearance=work.hoverClearance(r.Position)
        if damaged then
            state.damageHits=(state.damageHits or 0)+1
            if clearance>=0 then
                state.height=math.max(4,state.height-2)
                if state.damageHits>=2 or lost>=human.MaxHealth*.2 or human.Health/human.MaxHealth*100<=(opts.retreatHealth or 35)then
                    work.hoverSuppressed={scene=world(),character=player.Character}
                    note("nightHold","DAMAGE CONTINUES WITHOUT A NEARBY THREAT; STOPPING HOVER FOR THIS NIGHT")
                    if work.releaseHover(false,true)then return true end
                end
            end
        end
        if damaged or clearance<0 or not work.hoverBodyClear(r.Position)then
            local fire=built("Campfire")
            local candidate=fire and work.hoverDestination(fire,state.height,r.Position,true)
            if candidate then
                state.land=CFrame.new(candidate.land);r.CFrame=CFrame.new(candidate.point)
                r.AssemblyLinearVelocity=Vector3.new(0,0,0)
                note("nightHold",damaged and"HOVER DAMAGE: MOVED TO CHECKED CLEARANCE; HEIGHT "..state.height or"HOVER THREAT APPROACH: REPOSITIONED")
            else
                note("nightHold","NO CHECKED HOVER OPENING; REQUESTING SAFE GROUND RECOVERY")
                work.hoverSuppressed={scene=world(),character=player.Character}
                work.releaseHover(false,true)
            end
        end
        return true
    end
    function work.nightHold()
        local fire=built("Campfire");local r,human=root()
        if not fire or not r then return false end
        if work.hover and work.hover.character~=player.Character then work.releaseHover(true)end
        if work.hover then return work.hoverTick()end
        if not work.shelterNeeded()then return travel(fire,"nightHold",9)end
        local height=math.clamp(opts.hoverHeight,4,12)
        local candidate=work.hoverDestination(fire,height)
        if not candidate then note("nightHold","NO VERIFIED DRY HOVER POSITION; REMAINING ON CHECKED GROUND");return false end
        -- Torches are not a survival weapon and need not stay equipped during
        -- shelter. Do not falsify Bonfired or any server-owned health attribute.
        local character=player.Character
        if character and character.GetChildren then
            for _,tool in ipairs(character:GetChildren())do
                local item=config().item.byDisplayName[tool.Name]
                if item and item.isLightSource and human.UnequipTools then human:UnequipTools();break end
            end
        end
        work.hover={root=r,anchored=r.Anchored,character=character,land=CFrame.new(candidate.land),health=human.Health,height=height}
        r.Anchored=true;r.CFrame=CFrame.new(candidate.point);r.AssemblyLinearVelocity=Vector3.new(0,0,0)
        note("nightHold","LOW HOVER: LIVE HORIZONTAL THREAT CHECKS • NO ALTITUDE ESCALATION")
        return true
    end
    function work.evaluateLost()
        if work.finished then return false end
        local list = Players:GetPlayers()
        if #list == 0 then return false end
        for _, person in ipairs(list) do
            local character = person.Character
            local human = character and character:FindFirstChildOfClass("Humanoid")
            if not human or human.Health > 0 then return false end
        end
        local deathScreen = pg:FindFirstChild("DeathScreen")
        if not deathScreen then
            for _, screen in ipairs(pg:GetChildren()) do
                if screen:IsA("ScreenGui") and screen:FindFirstChild("DeathScreenClient", true) then deathScreen = screen break end
            end
        end
        return deathScreen and deathScreen.Enabled == true or false
    end
    function work.roundLost()
        if os.clock() >= (work.lostCheckAt or 0) then
            work.lostCheckAt = os.clock() + 0.25
            work.lostCached = work.evaluateLost()
        end
        return work.lostCached == true
    end
    function work.returnLobby()
        local lib = RS:FindFirstChild("Module")
        local service = lib and lib:FindFirstChild("ActiveService")
        local lobby = service and service:FindFirstChild("LobbyTeleport")
        local event = lobby and lobby:FindFirstChild("RemoteEvent")
        if not event then note("round", "LOBBY RETURN UNAVAILABLE") return false end
        event:FireServer()
        return true
    end
    function work.sessionTick(mode)
        if not flags.autoFarm or os.clock() < (work.nextSessionAt or 0) then return end
        work.nextSessionAt = os.clock() + 1
        local lost = mode == "match" and work.roundLost()
        if lost or work.finished then
            work.lostSince = work.lostSince or os.clock()
            work.releaseHover()
            if flags.autoRound and lost and player:GetAttribute("replay") ~= true then
                local replay = RS.Engine.Service:FindFirstChild("ReplayService")
                local vote = replay and replay:FindFirstChild("voteYesRemote")
                if vote and os.clock() >= (work.replayAt or 0) then
                    vote:FireServer() work.replayAt = os.clock() + 5
                    note("round", "REPLAY VOTE SENT; WAITING FOR TEAM")
                end
            end
            if (flags.leaveLost or (flags.autoRound and work.finished)) and os.clock() - work.lostSince >= opts.roundWait then
                if work.returnLobby() then work.nextSessionAt = os.clock() + 8 end
            end
        else
            work.lostSince = nil
        end
        if mode == "lobby" and flags.autoRound then
            local match = RS.Engine.Service:FindFirstChild("MatchRoom")
            if not match then note("round", "MATCH ROOM API UNAVAILABLE IN THIS SERVER") return end
            if player:GetAttribute("isInMatchRoom") then
                if player:GetAttribute("isRoomOwner") and os.clock() >= (work.startAt or 0) then
                    match.configRoomRemote:FireServer(1)
                    match.startGameRemote:FireServer()
                    work.startAt = os.clock() + 5
                end
            else
                local lobby = workspace:FindFirstChild("Lobby")
                local rooms = lobby and lobby:FindFirstChild("MatchRooms")
                for _, room in ipairs(rooms and rooms:GetChildren() or {}) do
                    local detector = room:FindFirstChild("Detect")
                    if detector then
                        local r = root()
                        if r then r.CFrame = detector.CFrame + Vector3.new(0, 3, 0) end
                        match.joinRoomRemote:FireServer(room)
                        note("round", "JOINING AVAILABLE MATCH ROOM")
                        work.nextSessionAt = os.clock() + 5
                        break
                    end
                end
            end
        end
    end
    function work.codeCatalogue()
        local candidates, seen, visited = {}, {}, {}
        local function add(raw)
            if type(raw) ~= "string" then return end
            local code = raw:upper():gsub("%s+", "")
            if #code > 0 and #code <= 64 and not seen[code] then
                seen[code] = true candidates[#candidates+1] = code
            end
        end
        local function scan(value, depth)
            if type(value) ~= "table" or visited[value] or depth > 4 then return end
            visited[value] = true
            if type(value.code) == "string" then add(value.code) return end
            for key, entry in pairs(value) do
                if type(entry) == "string" and type(key) == "number" then add(entry)
                elseif type(entry) == "table" then
                    if type(key) == "string" and (entry.grantReward or entry.reward) and not entry.code then add(key) end
                    scan(entry, depth+1)
                end
            end
        end
        scan(config().codes, 0)
        for code in tostring(opts.codes or ""):gmatch("[^,%s;]+") do add(code) end
        return candidates
    end
    function work.redeemTick()
        if not flags.autoFarm or not flags.redeemCodes or work.redeeming or os.clock() < (work.nextCodeAt or 0) then return end
        work.nextCodeAt = os.clock()+2.2
        work.codeAttempts = work.codeAttempts or {}
        selected.codeClaims = selected.codeClaims or {}
        local candidates = work.codeCatalogue()
        -- Net:RemoteFunction can wait forever where the lobby service is absent.
        local remote = RS:FindFirstChild("RF/RedeemCodeRedeem", true)
        if not remote then note("codes", "AUTO CATALOGUE READY; REDEMPTION SERVICE NOT AVAILABLE HERE") return end
        for _, raw in ipairs(candidates) do
            local code = raw:upper():gsub("%s+", "")
            if #code <= 64 and not selected.codeClaims[code] and not work.codeAttempts[code] then
                work.redeeming = true work.nextCodeAt = os.clock() + 2.2
                task.spawn(function()
                    local ok, result = pcall(function() return remote:InvokeServer(code) end)
                    if alive then
                        note("codes", code .. " • " .. tostring(ok and result or "ERROR"))
                        if ok and (result == "SUCCESS" or result == "CLAIMED") then selected.codeClaims[code] = true save() end
                        if ok and result ~= "PROCESSING" and result ~= "ERROR" then work.codeAttempts[code] = true end
                    end
                    work.redeeming = nil
                end)
                return
            end
        end
        if #candidates == 0 then note("codes", "AUTO CATALOGUE SCANNED • NO PUBLISHED CODES IN LOADED CONFIG") end
    end
    function work.espCategory(model, folderName)
        local c, name = config(), model.Name
        if folderName == "players" then return "espPlayers" end
        local mob = c.mob and c.mob.byId[name]
        if mob then return name:lower():find("shadow", 1, true) and "espShadow" or "espEnemies" end
        local resource = c.worldResource and c.worldResource.byId[model:GetAttribute("resourceId")]
        if resource then
            local kind = work.resourceKind(resource)
            return kind == "tree" and "espTrees" or kind == "stone" and "espStone" or kind == "iron" and "espIron" or "espOtherResources"
        end
        if work.artifactNames[name] then return "espArtifacts" end
        if folderName == "DroppedItems" then
            local item = c.item.byDisplayName[name]
            if item and c.food and c.food.byId[item.id] then return "espFood" end
            if item and ((c.bag and c.bag.byId[item.id]) or item.type == "tool") then return "espBags" end
            return "espDrops"
        end
        if folderName == "Buildings" then return name:find("_Construct", 1, true) and "espBlueprints" or "espCamp" end
        if folderName == "Chest" or (c.chest and c.chest.byId[name]) then return "espChests" end
        if c.mapProp and c.mapProp.byCnId[name] then return "espPuzzles" end
    end
    function work.clearESP()
        for model, marker in pairs(work.espMarkers or {}) do
            marker.billboard:Destroy() if marker.highlight then marker.highlight:Destroy() end
            work.espMarkers[model] = nil
        end
    end
    function work.espTick()
        work.espMarkers = work.espMarkers or {}
        local enabled = false
        for key, value in pairs(flags) do if key:sub(1, 3) == "esp" and value then enabled = true break end end
        if not enabled then work.clearESP() return end
        local scene, r = world(), root()
        if not scene or not r then work.clearESP() return end
        if not work.espFolder then
            work.espFolder = Instance.new("Folder") work.espFolder.Name = "EXIS_LOCAL_MARKERS" work.espFolder.Parent = workspace
        end
        local targets, seen = {}, {}
        local function add(model, folder)
            if not model:IsA("Model") or seen[model] or model == player.Character then return end
            seen[model] = true
            local category = work.espCategory(model, folder)
            local point = pos(model)
            if not category or not flags[category] or not point then return end
            local distance = (point - r.Position).Magnitude
            if distance <= opts.espDistance then targets[#targets + 1] = {model = model, category = category, distance = distance} end
        end
        local groups = {
            {"resources", "Static", flags.espTrees or flags.espStone or flags.espIron or flags.espOtherResources},
            {"entities", "Entities", flags.espEnemies or flags.espShadow},
            {"drops", "DroppedItems", flags.espDrops or flags.espFood or flags.espBags},
            {"buildings", "Buildings", flags.espCamp or flags.espBlueprints},
            {"chests", "Chest", flags.espChests},
            {"artifacts", "explore", flags.espArtifacts},
            {"explore", "explore", flags.espPuzzles},
        }
        for _, row in ipairs(groups) do
            if row[3] then for _, model in ipairs(work.models(row[1])) do add(model, row[2]) end end
        end
        if flags.espPlayers then
            for _, person in ipairs(Players:GetPlayers()) do if person ~= player and person.Character then add(person.Character, "players") end end
        end
        table.sort(targets, function(a, b) return a.distance < b.distance end)
        local keep = {}
        for i = 1, math.min(#targets, opts.espLimit) do
            local row, model = targets[i], targets[i].model
            local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            if part then
                keep[model] = true
                local marker = work.espMarkers[model]
                if not marker then
                    local billboard = make("BillboardGui", {Adornee = part, AlwaysOnTop = true,
                        Size = UDim2.fromOffset(150, 32), StudsOffsetWorldSpace = Vector3.new(0, 3, 0)}, pg)
                    local label = make("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
                        TextColor3 = white, TextStrokeTransparency = 0.35, TextSize = 10, Font = Enum.Font.BuilderSansBold,
                        TextWrapped = true}, billboard)
                    marker = {billboard = billboard, label = label}
                    work.espMarkers[model] = marker
                end
                if opts.espLabelsOnly and marker.highlight then marker.highlight:Destroy() marker.highlight = nil end
                if not opts.espLabelsOnly and not marker.highlight then
                    local highlight = Instance.new("Highlight") highlight.Adornee = model
                    highlight.FillTransparency = 0.9 highlight.OutlineTransparency = 0.15
                    highlight.FillColor = blue highlight.OutlineColor = blue
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop highlight.Parent = work.espFolder
                    marker.highlight = highlight
                end
                local c = config()
                local item = c.item.byDisplayName[model.Name]
                local title = item and itemLabel("item", item.id, item) or model.Name
                local human = model:FindFirstChildOfClass("Humanoid")
                marker.label.Text = title .. " • " .. math.floor(row.distance) .. " STUDS" .. (human and (" • HP " .. math.ceil(human.Health)) or "")
            end
        end
        for model, marker in pairs(work.espMarkers) do
            if not keep[model] or not model.Parent then marker.billboard:Destroy() if marker.highlight then marker.highlight:Destroy() end work.espMarkers[model] = nil end
        end
    end
    function work.statusTick()
        local scene, r, human = world(), root()
        r, human = root()
        local day = scene and scene:FindFirstChild("Day")
        local phase = scene and scene:FindFirstChild("Phase")
        local used, cap = work.bagState()
        local hunger = human and human:GetAttribute("hunger")
        local counts = work.counts
        local cookedReserve,rawReserve=work.foodCounts()
        local message = "DAY " .. tostring(day and day.Value or "—") .. " | " .. tostring(phase and phase.Value or "—")
            .. "\nHP " .. tostring(human and math.ceil(human.Health) or 0) .. " | FOOD " .. tostring(hunger or "—")
            .. " | COOKED " .. cookedReserve .. "/" .. work.foodReserveTarget() .. " RAW " .. rawReserve
            .. " | BAG " .. tostring(used or 0) .. "/" .. tostring(cap or "?")
            .. "\nFELLED " .. counts.felled .. " | PICKED " .. counts.picked .. " | GUARDED " .. counts.guarded .. " | ESCAPES " .. counts.escapes
            .. "\nJOB " .. tostring(work.active or "WAITING"):upper() .. "\nNOTE " .. tostring((work.active and taskStatus[work.active]) or taskStatus.queue or taskStatus.round or "READY")
        if work.statusLabel then work.statusLabel.Text = message end
        if work.liveLabel then work.liveLabel.Text = message work.liveLabel.Visible = flags.liveStatus == true end
        if work.shieldLabel then work.shieldLabel.Text = flags.cosmeticShield and "COSMETIC SHIELD: ON • REAL DAMAGE STILL APPLIES" or "COSMETIC SHIELD: OFF" end
    end
    -- Long-run survival adapters: native recipes, storage, food and attacks.
    function work.stormActive()
        local scene = world()
        local day = scene and scene:FindFirstChild("Day")
        local n = day and tonumber(day.Value) or 1
        local rain = scene and scene:FindFirstChild("IsRaining")
        local storm = scene and (scene:FindFirstChild("MegaStorm") or scene:FindFirstChild("IsStorm"))
        return storm and storm.Value == true or n > 0 and n % 7 == 0 and rain and rain.Value == true or false
    end
    function work.interruptsInteraction(job)
        local key=job.key
        if key=="evade" then return not work.retaliatingUntil or os.clock()>=work.retaliatingUntil end
        if key=="nightHold"then
            local _,human=root()
            return work.shelterNeeded()and human and human.Health/human.MaxHealth*100<=opts.retreatHealth or false
        end
        if key=="combat"then return not work.combatUrgent or work.combatUrgent()end
        if key=="shadowHunt" or key=="eat" or key=="autoAttack" then return true end
        if key=="foodCache"then return work.mealNeeded()and work.noFood()end
        if key=="escape" then return opts.emergencyEscape==true end
        if key=="fuel" then
            local state=work.fireState()
            return not work.stormActive() and (campData.isOnFire==false or state and state.remaining and state.remaining<=6)
        end
        if key=="cook" or key=="cooked" or key=="foodSupply" or key=="foodPickup" or key=="hunt" then
            local _,human=root()
            local hunger=human and human:GetAttribute("hunger")
            local maximum=human and (human:GetAttribute("maxHunger") or 100) or 100
            return human and (human.Health/human.MaxHealth*100<=opts.retreatHealth or hunger and hunger/maximum<0.15) or false
        end
        return false
    end
    function work.foodReserveTarget()
        local scene = world()
        local day = scene and scene:FindFirstChild("Day")
        local n = day and tonumber(day.Value) or 1
        return flags.stormStock and (n % 7 >= 5 or n > 0 and n % 7 == 0)
            and (opts.stormReserve or 20) or (opts.foodReserve or 8)
    end
    function work.isCookedFood(id)
        local c = config()
        local row = c.food and c.food.byId[id]
        if not row or row.canCook then return false end
        if row.isCooked == true then return true end
        if work.cookedConfig ~= c.food then
            work.cookedConfig,work.cookedIds=c.food,{}
            for _,raw in pairs(c.food.byId) do if raw.canCook and raw.cookTargetId then work.cookedIds[raw.cookTargetId]=true end end
        end
        return work.cookedIds[id] == true
    end
    function work.foodCounts()
        local raw, cooked, carried = 0, 0, 0
        local c = config()
        local function add(id, amount, own)
            local food = c.food.byId[id]
            if food and food.canCook then raw = raw + amount
            elseif food and work.isCookedFood(id) then cooked = cooked + amount if own then carried = carried + amount end end
        end
        for _, tool in ipairs(tools()) do
            local item = c.item.byDisplayName[tool.Name]
            if item then add(item.id, tonumber(tool:GetAttribute("count")) or 1, true) end
        end
        for _, slot in pairs(work.storageSnapshot or {}) do
            local item = c.item.byDisplayName[slot.displayName]
            if item then add(item.id, tonumber(slot.count) or 1) end
        end
        for _, drop in ipairs(work.models("drops")) do
            if drop.Parent and work.markCampDrop(drop) then
                local item = c.item.byDisplayName[drop.Name]
                if item then add(item.id,1)end -- native ItemCollect grants one unit per world model.
            end
        end
        cooked = cooked + (campData.readyCount or 0)
        raw = raw + (campData.pendingCookCount or 0)
        return cooked, raw, carried
    end
    function work.foodShortage()
        local cooked, raw = work.foodCounts()
        return cooked + raw < work.foodReserveTarget()
    end
    function work.mealNeeded()
        local _,human=root()
        if not human or human.Health<=0 or flags.eat==false then return false end
        local hunger=human.GetAttribute and human:GetAttribute("hunger")
        local maximum=human.GetAttribute and(human:GetAttribute("maxHunger")or 100)or 100
        return human.Health/human.MaxHealth*100<=(opts.health or 50)
            or hunger~=nil and hunger/math.max(1,maximum)*100<=(opts.hunger or 40)
    end
    function work.foodKeepCount(id,tool)
        if not work.mealNeeded() or not work.isCookedFood(id) then return 0 end
        for _,owned in ipairs(tools())do
            local item=config().item.byDisplayName[owned.Name]
            if item and work.foodAllowed("food",item.id)and(tonumber(owned:GetAttribute("count"))or 1)>0 then
                return item.id==id and(not tool or tool==owned)and 1 or 0
            end
        end
        return 0
    end
    function work.campFoodRecord(model)
        local c=config();local item=c.item.byDisplayName[model.Name]
        local food=item and c.food.byId[item.id]
        if not food then return nil end
        local owner=model:GetAttribute("ownerName")
        if owner and owner~=player.Name then return nil end
        if not owner and not work.isCookedFood(item.id)then return nil end
        local fire=built("Campfire");local center=fire and pos(fire);local point=pos(model)
        if center and point and(point-center).Magnitude<=22 then return{id=item.id,camp=fire,food=true}end
    end
    function work.foodPickupWanted(model,id)
        local req=flags.quest and work.questRequirement
        if req and req.itemId==id and work.questTotal(req)<req.count then return true end
        local food=config().food.byId[id]
        if work.isCookedFood(id)then
            if work.mealNeeded()and work.noFood()and work.foodAllowed("food",id)then return true end
            local stashed=work.campStash and work.campStash[model]
            if stashed or work.campFoodRecord(model)then return false end
            local _,_,carried=work.foodCounts()
            return carried<2 -- fresh distant loot is brought home, not reclaimed from our pile.
        end
        if not food or not food.canCook then return false end
        local raw=0
        for _,tool in ipairs(tools())do
            local item=config().item.byDisplayName[tool.Name]
            local row=item and config().food.byId[item.id]
            if row and row.canCook then raw=raw+(tonumber(tool:GetAttribute("count"))or 1)end
        end
        local _,cap=work.bagState()
        local stage=math.max(1,math.min(4,math.floor((cap or 15)/3)))
        return raw<stage and(flags.killFoodOnSight or work.foodShortage())and not work.stormActive()
    end
    function work.mealAvailable()
        if(campData.readyCount or 0)>0 and work.foodAllowed("food",campData.readyFoodId)then return true end
        for _,model in ipairs(work.models("drops"))do
            local item=config().item.byDisplayName[model.Name]
            if model.Parent and item and work.isCookedFood(item.id)and work.foodAllowed("food",item.id)
                and work.dropAllowed(model)and work.safeResource(model)then return true end
        end
        return false
    end
    function work.collectCookedUnit(key)
        local id=campData.readyFoodId;local item=id and config().item.byId[id]
        if not item or not work.isCookedFood(id)or(campData.readyCount or 0)<=0 or not work.canCollect()then return false end
        local pending=work.cookedRequest
        if pending then
            if count(pending.name)>pending.before then work.cookedRequest=nil;return true end
            if os.clock()<pending.untilTime then return false end
            work.cookedRequest=nil
        end
        local before=count(item.displayName)
        work.cookedRequest={name=item.displayName,before=before,untilTime=os.clock()+8}
        call("MakeFire","collectFood") -- Native server grants exactly one unit.
        local confirmed=work.await(key,function()return count(item.displayName)>before end,3)
        if confirmed then work.cookedRequest=nil;work.invalidateInventory()end
        return confirmed
    end
    function work.takeMeal(key)
        if not work.mealNeeded()or not work.noFood()then return not work.noFood()end
        if not work.canCollect()then return false end
        if(campData.readyCount or 0)>0 and work.foodAllowed("food",campData.readyFoodId)and work.collectCookedUnit(key)then return true end
        local model=nearest(work.models("drops"),function(drop)
            local item=config().item.byDisplayName[drop.Name]
            return item and work.isCookedFood(item.id)and work.foodAllowed("food",item.id)
                and work.dropAllowed(drop)and work.safeResource(drop)
        end)
        if not model then return false end
        if work.hover and not work.releaseHover(false,true)then return false end
        return work.collectModel(model,key)
    end
    function work.foodCacheCandidate()
        for _,tool in ipairs(tools())do
            local item=config().item.byDisplayName[tool.Name]
            if item and config().food.byId[item.id]and work.unloadCount(tool)>0 then
                local food=config().food.byId[item.id]
                if not food.canCook or not work.cookReady()then return tool end
            end
        end
    end
    function work.foodCacheReady()
        if not built("Campfire")then return false end
        if work.foodCacheCandidate()then return true end
        if flags.useStorage and work.canCollect()then
            for _,slot in pairs(work.storageSnapshot or{})do
                local item=config().item.byDisplayName[slot.displayName]
                if item and config().food.byId[item.id]then return true end
            end
        end
        local flag=RS:FindFirstChild("Flags");flag=flag and flag:FindFirstChild("CampfireSpitMeat")
        return not(flag and flag.Value==true)and(campData.readyCount or 0)>0 and(not work.mealNeeded()or not work.foodAllowed("food",campData.readyFoodId))and work.canCollect()
    end
    function work.foodCachePoint(fire)
        local r,human=root();local center=pos(fire)
        if not r or not center then return nil end
        local best,score
        for _,radius in ipairs({7,10,14,18})do
            for n=0,11 do
                local angle=n*math.pi/6
                local ground=motion.floor(center+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),fire,12,12)
                local point=ground and ground+Vector3.new(0,human.HipHeight+r.Size.Y/2,0)
                if point and work.safeWorkPoint(point,3)then
                    local clear=true
                    for _,zone in ipairs(work.campIntakeZones())do
                        if zone.Parent and not zone:IsDescendantOf(fire)then
                            local p=zone.CFrame:PointToObjectSpace(point)
                            if math.abs(p.X)<zone.Size.X/2+3 and math.abs(p.Z)<zone.Size.Z/2+3 then clear=false break end
                        end
                    end
                    local distance=(point-r.Position).Magnitude+radius*.1
                    if clear and(not score or distance<score)then best,score=point,distance end
                end
            end
            if best then return best end
        end
    end
    function work.cacheFood(key)
        key=key or"foodCache"
        local fire=built("Campfire")
        if not fire then return false end
        if work.hover and not work.releaseHover(false,true)then return false end
        if not work.foodCacheCandidate()and flags.useStorage and work.canCollect()then
            for _,slot in pairs(work.storageSnapshot or{})do
                local item=config().item.byDisplayName[slot.displayName]
                if item and config().food.byId[item.id]then
                    work.reclaimStorage({amounts={[item.id]=count(item.displayName)+1}},key)
                    break
                end
            end
        end
        local point=work.foodCachePoint(fire)
        if not point or not travel(point,key,.5)then return false end
        local watch={before={},expected={},point=point,camp=fire,expires=os.clock()+10}
        for _,drop in ipairs(work.models("drops"))do watch.before[drop]=true end
        work.campDropWatches=work.campDropWatches or{};work.campDropWatches[#work.campDropWatches+1]=watch
        local acted=false;local character,serial=player.Character,motion.serial
        local deadline=os.clock()+math.clamp(opts.jobTimeout,15,600)
        repeat
            if not work.running(key,character,serial)then break end
            local tool=work.foodCacheCandidate()
            if not tool then
                if(not work.mealNeeded()or not work.foodAllowed("food",campData.readyFoodId))and(campData.readyCount or 0)>0 and work.collectCookedUnit(key)then tool=work.foodCacheCandidate()end
            end
            if not tool then break end
            work.unloadWatch=watch
            local amount=work.batchDrop(tool,work.unloadCount(tool),key)
            work.unloadWatch=nil;work.captureCampDrops()
            if amount<=0 then return acted end
            acted=true;work.blockedBag,work.rejectedPickups=nil,0
            task.wait()
        until os.clock()>=deadline
        work.refreshAt=0
        note(key,"FOOD STOCKPILED AT CAMP • BAG SPACE FREED • RECLAIM ONE WHEN NEEDED")
        return acted
    end
    function work.isPassiveFood(model)
        local info=work.mobInfo and work.mobInfo(model)or config().mob and config().mob.byId[model.Name]
        return info and not work.isHostile(model, info) and work.mobDropsFood(model) or false
    end
    function work.foodHuntCandidate()
        if os.clock() < (work.foodHuntAt or 0) or not work.canCollect() or not work.meleeWeapon("foodHunt") then return end
        local r = root()
        if not r then return end
        return nearest(work.models("entities"), function(model)
            local human = model:FindFirstChildOfClass("Humanoid")
            return human and human.Health > 0 and human.Health < 10000 and work.isPassiveFood(model)
                and (pos(model) - r.Position).Magnitude <= opts.huntRadius and work.safeResource(model)
                and not (failed[model] and failed[model] > os.clock())
                and (flags.killFoodOnSight or work.foodShortage())
        end)
    end
    function work.structureRole(id, info)
        local text = (tostring(id) .. " " .. tostring(info and (info.displayName or info.assetId or info.name) or "")):lower()
        if text:find("storage", 1, true) or text:find("储", 1, true) or text:find("仓", 1, true) then return "storage" end
        if text:find("furnace", 1, true) or text:find("smelt", 1, true) or text:find("熔炉", 1, true) then return "furnace" end
        return "other"
    end
    function work.findStructure(role, id)
        local scene, c = world(), config()
        if not scene then return end
        for _, name in ipairs({"Buildings", "自由建筑"}) do
            local folder = scene:FindFirstChild(name)
            for _, model in ipairs(folder and folder:GetChildren() or {}) do
                if model:IsA("Model") and not model.Name:find("_Construct", 1, true) then
                    local cnId = model:GetAttribute("cnId")
                    if id and (cnId == id or model.Name == id) then return model end
                    if not id and work.structureRole(cnId or model.Name) == role then return model end
                    for buildId, info in pairs(c.build and c.build.byId or {}) do
                        if model.Name == info.assetId and (id and buildId == id or not id and work.structureRole(buildId, info) == role) then return model end
                    end
                end
            end
        end
    end
    function work.storageCount(id)
        local item, amount = config().item.byId[id], 0
        for _, slot in pairs(work.storageSnapshot or {}) do
            if item and slot.displayName == item.displayName then amount = amount + (tonumber(slot.count) or 1) end
        end
        return amount
    end
    function work.reclaimStorage(goal, key)
        if not flags.useStorage or not work.canCollect() then return false end
        local store = work.findStructure("storage")
        if not store or not work.safeResource(store) then return false end
        for index, slot in pairs(work.storageSnapshot or {}) do
            local item = config().item.byDisplayName[slot.displayName]
            if item and (goal.amounts[item.id] or 0) > count(item.displayName) then
                if not travel(store, key, 8) then return false end
                local before = count(item.displayName)
                call("Storage", "takeItem", tonumber(index))
                return work.await(key, function() return count(item.displayName) > before end, 3)
            end
        end
        return false
    end
    function work.storeBag(key)
        local store = work.findStructure("storage")
        if not store or not work.safeResource(store) or os.clock() < (work.storageBlockedAt or 0) then return false end
        for _, tool in ipairs(tools()) do
            local amount = work.unloadCount(tool)
            -- Native Storage stores a whole stack; never store our carry ration
            -- or a protected direct-crafting ingredient with it.
            if amount > 0 and not config().food.byId[(config().item.byDisplayName[tool.Name]or{}).id]
                and amount >= (tonumber(tool:GetAttribute("count")) or 1) then
                if not travel(store, key, 8) then return false end
                local name, before = tool.Name, count(tool.Name)
                call("Storage", "storeItem", tool)
                if work.await(key, function() return count(name) < before end, 2) then return true end
                work.storageBlockedAt = os.clock() + 3
                note(key, "STORAGE FULL / UNCONFIRMED; USING SAFE OVERFLOW BESIDE IT")
                return false
            end
        end
        return false
    end
    function work.foodSupplyGoal()
        local _, _, carried = work.foodCounts()
        local c, wanted = config(), {}
        if work.mealNeeded()and carried==0 then
            for id in pairs(c.food.byId)do if work.isCookedFood(id)then wanted[id]=1 end end
        end
        local cooked = work.foodCounts()
        if flags.cook==true and cooked<work.foodReserveTarget()and not work.stormActive()and not work.rawFoodOwned()then
            for id,food in pairs(c.food.byId)do if food.canCook and(not work.cookCompatible or work.cookCompatible(id))then wanted[id]=1 end end
        end
        return {amounts = wanted}
    end
    function work.foodSupplyReady()
        if not work.canCollect() then return false end
        local goal = work.foodSupplyGoal()
        for id, amount in pairs(goal.amounts) do
            if amount > 0 and work.storageCount(id) > 0 then return true end
        end
        return work.foodDropCandidate() ~= nil
    end
    function work.foodSupplyTick()
        if work.mealNeeded()and work.noFood()then return work.takeMeal("foodSupply")end
        if work.reclaimStorage(work.foodSupplyGoal(), "foodSupply") then return true end
        local acted,seen=false,{}
        local deadline=os.clock()+math.clamp(opts.jobTimeout,15,600)
        repeat
            local model=work.foodDropCandidate()
            if not model or seen[model]then break end
            seen[model]=true
            if not work.collectModel(model,"foodSupply")then break end
            acted=true
            if not flags.bulkCollect or not work.canCollect()or work.preempted then break end
        until os.clock()>=deadline
        return acted
    end
    function work.attackPhase(model)
        local human = model:FindFirstChildOfClass("Humanoid")
        local animator = human and human:FindFirstChildOfClass("Animator")
        if not animator then return "unknown" end
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local name = (track.Name .. " " .. (track.Animation and track.Animation.Name or "")):lower()
            if name:find("attack", 1, true) or name:find("atk", 1, true) or name:find("bite", 1, true) then
                local fraction = track.Length > 0 and track.TimePosition / track.Length or 0.5
                if fraction < 0.2 then return "windup" end
                return fraction < 0.8 and "strike" or "recovery"
            end
        end
        return "unknown"
    end
    function work.kite(target, key)
        local info=work.mobInfo and work.mobInfo(target)or config().mob and config().mob.byId[target.Name]
        if info and not work.isHostile(target, info) then return false end
        local r, human = root()
        if not r or not target.Parent then return false end
        local center, best, score = pos(target), nil, nil
        local radius = math.max(work.enemyReach(target) + opts.combatMargin + 3, 8)
        for i = 0, 11 do
            local angle = i * math.pi / 6
            local probe = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            local ground = motion.floor(probe, target, 12, 8)
            if ground then
                local point = ground + Vector3.new(0, human.HipHeight + r.Size.Y / 2, 0)
                local risk = work.danger(point, opts.dangerRadius)
                if work.insideBorder(point) and motion.clearSegment(r.Position, point, target)
                    and risk <= work.danger(r.Position, opts.dangerRadius) then
                    local value = risk * 100 + (point - r.Position).Magnitude
                    if not score or value < score then best, score = point, value end
                end
            end
        end
        if not best then return false end
        work.escapeMove = true
        local ok, result = pcall(travel, best, key, 0.5, opts.evadeMove)
        work.escapeMove = nil
        work.attackPlanCache, work.threatCacheAt = nil, 0
        if not ok then error(result) end
        return result
    end
    function work.activateWeapon(tool, stats, target, key)
        if tool.Parent ~= player.Character then return false end
        local ranged = stats.toolType == "gun" or stats.toolType == "infGun" or stats.toolType == "ranged"
        if ranged then
            -- GunClient has no mouse ray argument: its Aim.Adornee must exist.
            -- RangeClient maintains an internal target; allow its 0.1s scan to settle.
            if not work.await(key, function()
                local object=work.nativeAim
                if not object or not object.Parent then object=pg:FindFirstChild("Aim") work.nativeAim=object end
                return object and object:IsA("BillboardGui") and object.Enabled
                    and (object.Adornee==target or object.Adornee and object.Adornee:IsDescendantOf(target)) or false
            end, 0.6) then note(key, "WAITING FOR NATIVE RANGED TARGET LOCK") return false end
        end
        local client = RS.Engine:FindFirstChild("Tool")
        client = client and client:FindFirstChild("Client")
        local base = client and client:FindFirstChild("ClientToolBase")
        if base then
            local ok, api = pcall(require, base)
            if ok and api.getCooldownState then
                local remaining = api.getCooldownState()
                if remaining and remaining > 0 and not work.pause(key, remaining) then return false end
            end
        end
        -- Invoke the equipped Tool directly, just as MobileBtnsClient does.
        -- A fired GUI signal can exist without a live native button listener.
        tool:Activate()
        return true
    end
    function work.setSprint(enabled)
        if work.sprinting == enabled then return end
        local source = RS.Engine:FindFirstChild("Player")
        source = source and source:FindFirstChild("Sprint")
        if not source then return end
        local ok, sprint = pcall(require, source)
        if ok and sprint.client then
            if enabled then sprint.client.start() else sprint.client.stop() end
            work.sprinting = enabled
        end
    end
    function work.armourCandidate()
        local c=config()
        local best,stats
        for _,tool in ipairs(tools())do
            local item=c.item.byDisplayName[tool.Name]
            local info=item and c.armour and c.armour.byId[item.id]
            if info then
                local kind=info.typeCN or info.armourType or"armour"
                local ownedId=work.equippedArmour and work.equippedArmour[kind]
                local owned=ownedId and c.armour.byId[ownedId]
                if (tonumber(info.lvl)or 1)>(tonumber(owned and owned.lvl)or 0)
                    and(not stats or(tonumber(info.lvl)or 1)>(tonumber(stats.lvl)or 1))then best,stats=tool,info end
            end
        end
        return best,stats
    end
    function work.equipArmour()
        local tool,stats=work.armourCandidate()
        if not tool then return false end
        local item=config().item.byDisplayName[tool.Name]
        local kind=stats.typeCN or stats.armourType or"armour"
        equip(tool)
        local service=RS.Engine.Service:FindFirstChild("ToolService")
        local remote=service and service:FindFirstChild("armourRemote")
        if not remote or tool.Parent~=player.Character then note("equipArmour","NATIVE ARMOUR REMOTE / HELD ITEM UNAVAILABLE")return false end
        remote:FireServer(tool);work.sent=work.sent+1
        local confirmed=work.await("equipArmour",function()return work.equippedArmour and work.equippedArmour[kind]==item.id end,2)
        note("equipArmour",confirmed and"ARMOUR EQUIP CONFIRMED"or"ARMOUR EQUIP UNCONFIRMED; ITEM KEPT")
        return confirmed
    end
    function work.craftUnlocked(goal)
        if not goal or goal.kind~="craft"then return true end
        if not goal.info or not next(work.recipeAmounts(goal.info))then return false end
        local c=config()
        for _,entry in ipairs(c.craftingContent and c.craftingContent.list or{})do
            local item=c.item.byName[entry.itemName]
            if item and item.id==goal.id then
                local state=work.fireState()
                if (tonumber(entry.campfireLvl)or 1)>(state and state.level or 1)then return false end
                return work.stationSynced==true and work.station()~=nil
            end
        end
        return true
    end
    function work.gearPriority(goal)
        if not goal or goal.kind~="craft"or goal.questFor then return false end
        local _,cap=work.bagState()
        if cap<15 then return false end
        local c=config()
        return c.tool and c.tool.byId[goal.id]~=nil or c.armour and c.armour.byId[goal.id]~=nil or false
    end
    function work.batchReady(goal,key)
        if not flags.bulkCollect then return true end
        local used,cap=work.bagState()
        if used>=cap then return true end
        if not next(work.missing(work.goalAmounts(goal)))then return true end
        return not work.pickupCandidate(true,key)and not work.resourceCandidate(key,true)
            and not work.huntCandidate(work.needs)
    end
    function work.bulkUnloadReady()
        if not flags.bulkCollect then return true end
        local used,cap=work.bagState()
        if used>=cap then return true end
        if work.bulkTrip then return true end
        return not work.pickupCandidate(false,"stockpile")and not work.resourceCandidate("stockpile",false)
    end
    function work.buildBatchReady(onlySelected)
        if not flags.bulkCollect then return true end
        local used,cap=work.bagState()
        if used>=cap or work.bulkUnloadReady()then return true end
        local c=config();local scene=world();local folder=scene and scene:FindFirstChild("Buildings")
        for id,info in pairs(c.build and c.build.byId or{})do
            if folder and folder:FindFirstChild(info.assetId.."_Construct")and(not onlySelected or allowed("build",id))then
                if info.assetId=="Campfire"and not built("Campfire")then return true end
                if not next(work.missing(work.recipeAmounts(info,true)))then return true end
            end
        end
        return false
    end
    function work.nightClear()
        local scene=world()
        if not scene or not scene:FindFirstChild("Entities")then return false end
        for _,row in ipairs(work.hostiles())do
            if row.model.Parent and row.human.Health>0 then return false end
        end
        return true
    end
    function work.structureStation()
        for _, model in ipairs(work.models("stations")) do
            if model.Name == "建筑制作台" then return model, model:FindFirstChild("吸入范围") end
        end
    end
    function work.structureGoal()
        if not flags.structureCraft then return end
        local c, candidates = config(), {}
        for _, entry in ipairs(c.freeBuildList and c.freeBuildList.list or {}) do
            local item = entry.itemId and c.item.byId[entry.itemId]
            local free = item and c.freeBuild and c.freeBuild.byCnId[item.id]
            if free and item.recipeId and not work.findStructure(nil, item.id)
                and os.clock() >= (work.structureFailed and work.structureFailed[item.id] or 0) then
                local role = work.structureRole(item.id, item)
                -- A legacy built furnace/storage already satisfies that utility.
                if role ~= "other" and not work.findStructure(role) then
                    local recipe, amounts = work.recipeAmounts(item), {}
                    for id, n in pairs(recipe) do amounts[id] = math.max(0, n - ((work.buildingStock or {})[id] or 0)) end
                    candidates[#candidates + 1] = {id=item.id, key="structure:"..item.id, kind="structure", info=item,
                        free=free, stationKind="building", recipe=recipe, amounts=amounts,
                        role=role, rank=role=="storage" and 0 or role=="furnace" and 1 or 2}
                end
            end
        end
        table.sort(candidates, function(a,b) return a.rank < b.rank or a.rank==b.rank and tostring(a.id)<tostring(b.id) end)
        return candidates[1]
    end
    function work.structurePlacement(goal)
        work.structureSites=work.structureSites or{}
        local cached=work.structureSites[goal.id]
        local api=module("FreeBuild")
        if not api then return end
        if cached and work.safeWorkPoint(cached.frame.Position,5)
            and not api.checkOverlap(cached.frame,cached.size,{},0.1) then return cached.frame,cached.size end
        local anchor=work.findStructure("storage") or built("Campfire") or work.campDropAnchor()
        if not anchor then return end
        local ok,assets=pcall(require,RS.Assets.AssetsManager)
        if not ok then return end
        local template=assets.getFreeBuildModelByCnId(goal.id)
        local box=template and template:FindFirstChild("BoundingBox")
        if not box then if template then template:Destroy() end return end
        local size,center=box.Size,pos(anchor)
        template:Destroy()
        local frame
        local scene=world()
        local params=OverlapParams.new()
        params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={scene:FindFirstChild("Buildings")}
        params.RespectCanCollide=true
        for _,radius in ipairs(goal.role=="storage" and {32,40,48,56} or {12,20,32,44}) do
            for i=0,11 do
                local angle=i*math.pi/6
                local point=center+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
                local ground=motion.floor(point,nil,20,10)
                if ground and work.safeWorkPoint(ground,5) then
                    local probe=CFrame.new(ground+Vector3.new(0,size.Y/2,0))
                    if probe.Position.Y<=200 and not api.checkOverlap(probe,size,{},0.1)
                        and #workspace:GetPartBoundsInBox(probe,size,params)==0 then frame=probe break end
                end
            end
            if frame then break end
        end
        if frame then
            work.structureSites[goal.id]={frame=frame,size=size}
            if goal.role=="storage" then work.storagePlannedFrame=frame end
        end
        return frame,size
    end
    function work.placeStructure(goal,key)
        if count(goal.info.displayName)==0 then return false end
        local frame,size=work.structurePlacement(goal)
        if not frame or not travel(frame.Position,key,math.max(5,size.Magnitude/2)) then return false end
        call("FreeBuild","requestPlace",goal.id,frame)
        return work.await(key,function()return work.findStructure(nil,goal.id)~=nil end,4)
    end
    function work.structureReady()
        local goal=work.structureGoal()
        if not goal then return false end
        if count(goal.info.displayName)>0 then return true end
        return work.buildingSynced and work.structureStation()~=nil and work.goalRunnable(goal) or false
    end
    function work.structureUnloadPrep(key)
        local goal=work.structureGoal()
        if not goal or not work.buildingSynced or not work.structureStation() then return false end
        for id,n in pairs(goal.amounts) do
            local item=config().item.byId[id]
            if n>0 and item and count(item.displayName)>0 then return work.stationTick(goal,key) end
        end
        return false
    end
    function work.structureTick()
        local goal, key = work.structureGoal(), "structures"
        if not goal then return false end
        if goal.role=="storage" and not work.storagePlannedFrame then work.structurePlacement(goal) end
        if count(goal.info.displayName)>0 then
            local placed = work.placeStructure(goal,key)
            if not placed then work.structureFailed=work.structureFailed or{} work.structureFailed[goal.id]=os.clock()+3 end
            return placed
        end
        if not work.structureStation() or not work.buildingSynced then note(key,"WAITING FOR BUILDING STATION STATE") return false end
        work.activeGoal,work.needs,work.amounts,work.resourceNeeds,work.needTotals=goal,{},{},{},{}
        local supply=work.supplyAmounts(goal)
        local result=config().misc.furnaceResultId
        for id,n in pairs(supply) do if n>0 and (id~=result or not built("Furnace")) then work.needItem(id,n,100) end end
        if result and (goal.amounts[result] or 0)>count(config().item.byId[result].displayName) and built("Furnace") then
            if (furnaceData.readyCount or 0)>0 and work.canCollect() then
                return travel(built("Furnace"),key) and work.request(key,"Furnace","collectResult")
            end
            for _,id in ipairs({config().misc.furnaceMatter1Id,config().misc.furnaceMatter2Id}) do
                local item=config().item.byId[id]
                if item and (supply[id] or 0)>0 and count(item.displayName)>0 then return work.smeltBag(key,supply) end
            end
        end
        local supplied = false
        for id,n in pairs(goal.amounts) do
            local item=config().item.byId[id]
            if n>0 and count(item.displayName)>0 then supplied=true break end
        end
        if (supplied or not next(work.missing(goal.amounts)))and(not work.batchReady or work.batchReady(goal,key))then return work.stationTick(goal,key)end
        if work.reclaimStorage(goal,key) then return true end
        return pickups(key,true) or gatherResource(key,true)
    end
    function work.wallRecipe()
        local c,candidates=config(),{}
        for id,free in pairs(c.freeBuild and c.freeBuild.byCnId or{})do
            local item=c.item.byId[id]
            local name=(tostring(id).." "..tostring(item and item.displayName or"").." "..tostring(free.name or"") ):lower()
            if item and item.recipeId and(name:find("wall",1,true)or name:find("围墙",1,true)or name:find("木墙",1,true)or name:find("栅栏",1,true))then
                local recipe=work.recipeAmounts(item)
                if next(recipe)then candidates[#candidates+1]={id=id,info=item,free=free,recipe=recipe}end
            end
        end
        table.sort(candidates,function(a,b)
            local function cost(row)
                local label=(tostring(row.id).." "..tostring(row.info.displayName or"")):lower()
                local n=(label:find("half",1,true)or label:find("半",1,true))and 1000 or 0
                for id,v in pairs(row.recipe)do
                    local item=c.item.byId[id]or{}
                    local text=(tostring(id).." "..tostring(item.displayName or"")):lower()
                    local wood=text:find("wood",1,true)or text:find("木",1,true)
                    n=n+v+(wood and 0 or 10000)
                end
                return n
            end
            return cost(a)<cost(b)or cost(a)==cost(b)and tostring(a.id)<tostring(b.id)
        end)
        return candidates[1]
    end
    function work.wallTemplate(id)
        if work.wallAsset and work.wallAsset.id==id then return work.wallAsset end
        local ok,assets=pcall(require,RS.Assets.AssetsManager)
        if not ok then return end
        local template=assets.getFreeBuildModelByCnId(id)
        local box=template and template:FindFirstChild("BoundingBox")
        if not box then if template then template:Destroy()end return end
        local result={id=id,size=box.Size,offset=template:GetPivot():ToObjectSpace(box.CFrame)}
        template:Destroy();work.wallAsset=result
        return result
    end
    function work.wallPlan(asset)
        local scene=world()
        local tiles=scene and scene:FindFirstChild("Tiles")
        if not tiles then return end
        local beaches={}
        for _,tile in ipairs(tiles:GetChildren())do
            if tile.Name:lower():find("beach",1,true)then
                local box=tile:FindFirstChild("BoundingBox")
                if box and box:IsA("BasePart")then beaches[#beaches+1]={frame=box.CFrame,size=box.Size}end
            end
        end
        local signature={}
        for _,row in ipairs(beaches)do signature[#signature+1]=tostring(row.frame)..tostring(row.size)end
        table.sort(signature);signature=table.concat(signature,"|")
        local cached=work.wallPlanCache
        if cached and cached.scene==scene and cached.signature==signature and cached.id==asset.id then return cached end
        local longX=asset.size.X>=asset.size.Z
        local length=math.max(asset.size.X,asset.size.Z)
        local thickness=math.min(asset.size.X,asset.size.Z)
        if length<.5 or thickness<.05 or #beaches==0 then return end
        local candidates={}
        local function shared(point,own)
            for _,other in ipairs(beaches)do
                if other~=own then
                    local q=other.frame:PointToObjectSpace(point)
                    if math.abs(q.X)<other.size.X/2+.1 and math.abs(q.Z)<other.size.Z/2+.1 then return true end
                end
            end
            return false
        end
        for _,beach in ipairs(beaches)do
            for _,edge in ipairs({{axis="X",sign=-1},{axis="X",sign=1},{axis="Z",sign=-1},{axis="Z",sign=1}})do
                local across=edge.axis=="X"and beach.size.Z or beach.size.X
                local depth=edge.axis=="X"and beach.size.X or beach.size.Z
                local slots=math.floor(across/length)
                for i=1,slots do
                    local along=-across/2+(i-.5)*across/slots
                    local outside=edge.sign*(depth/2+.5)
                    local boundary=beach.frame:PointToWorldSpace(edge.axis=="X"and Vector3.new(outside,0,along)or Vector3.new(along,0,outside))
                    if not shared(boundary,beach)then
                        for layer=1,3 do
                            local inset=thickness/2+.3+(layer-1)*(thickness+.5)
                            local cross=edge.sign*(depth/2-inset)
                            local localPoint=edge.axis=="X"and Vector3.new(cross,0,along)or Vector3.new(along,0,cross)
                            local yaw=(edge.axis=="X"and math.pi/2 or 0)+(longX and 0 or math.pi/2)
                            local boxFrame=beach.frame*CFrame.new(localPoint)*CFrame.Angles(0,yaw,0)
                            candidates[#candidates+1]={box=boxFrame,layer=layer}
                        end
                    end
                end
            end
        end
        local anchor=work.campDropAnchor()
        local center=anchor and pos(anchor)
        local gate,distance
        for _,slot in ipairs(candidates)do
            local p=slot.box.Position
            local d=center and Vector3.new(p.X-center.X,0,p.Z-center.Z).Magnitude or math.huge
            if slot.layer==1 and(not distance or d<distance)then gate,distance=p,d end
        end
        local plan={scene=scene,signature=signature,id=asset.id,slots=candidates,gate=gate,gateWidth=math.max(10,length*1.5)}
        work.wallPlanCache=plan
        return plan
    end
    function work.wallOccupied(frame,asset)
        local scene=world()
        local folder=scene and scene:FindFirstChild("自由建筑")
        for _,model in ipairs(folder and folder:GetChildren()or{})do
            if model:IsA("Model")and model:GetAttribute("cnId")==asset.id then
                local box=model:FindFirstChild("BoundingBox")
                local point=box and box.Position or pos(model)
                local hp=model:GetAttribute("hp")
                if point and(type(hp)~="number"or hp>0)and(point-frame.Position).Magnitude<math.max(.7,math.min(asset.size.X,asset.size.Z)*.6)then return model end
            end
        end
    end
    function work.wallGround(point)
        local scene=world()
        local tiles=scene and scene:FindFirstChild("Tiles")
        if not tiles then return end
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={tiles,workspace.Terrain}
        params.IgnoreWater=false;params.RespectCanCollide=true
        local hit=workspace:Raycast(point+Vector3.new(0,30,0),Vector3.new(0,-80,0),params)
        if hit and not motion.water(hit)and hit.Normal.Y>=.65 then return hit.Position end
    end
    function work.wallFooting(frame,asset)
        for _,x in ipairs({-.45,.45})do for _,z in ipairs({-.45,.45})do
            local point=frame:PointToWorldSpace(Vector3.new(asset.size.X*x,-asset.size.Y/2,asset.size.Z*z))
            local floor=work.wallGround(point)
            if not floor or math.abs(floor.Y-point.Y)>1 or not work.insideBorder(point)then return false end
        end end
        local scene=world();local folder=scene and scene:FindFirstChild("Buildings")
        if folder then
            local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances={folder};params.RespectCanCollide=true
            if #workspace:GetPartBoundsInBox(frame,asset.size,params)>0 then return false end
        end
        return frame.Position.Y<=200
    end
    function work.wallSite(recipe)
        local asset=work.wallTemplate(recipe.id)
        local plan=asset and work.wallPlan(asset)
        local api=module("FreeBuild")
        if not plan or not api then return end
        work.wallRetry=work.wallRetry or{}
        local r=root()
        local best,score
        for index,slot in ipairs(plan.slots)do
            local p=slot.box.Position
            local gateGap=plan.gate and Vector3.new(p.X-plan.gate.X,0,p.Z-plan.gate.Z).Magnitude<plan.gateWidth
            if not gateGap and os.clock()>=(work.wallRetry[index]or 0)and work.insideBorder(p)then
                local ground=work.wallGround(p)
                if ground and work.safeWorkPoint(ground,3)then
                    local frame=CFrame.new(0,ground.Y+asset.size.Y/2-p.Y,0)*slot.box
                    if work.wallFooting(frame,asset)and not work.wallOccupied(frame,asset)and not api.checkOverlap(frame,asset.size,{},.1)then
                        local value=slot.layer*100000+(r and(frame.Position-r.Position).Magnitude or 0)
                        if not score or value<score then best,score={index=index,box=frame,frame=frame*asset.offset:Inverse(),asset=asset,plan=plan},value end
                    end
                end
            end
        end
        return best
    end
    function work.wallGoal()
        if not flags.greatWall then return end
        local recipe=work.wallRecipe()
        if not recipe then note("greatWall","WALL RECIPE NOT IN LIVE BUILDING CATALOGUE") return end
        local site=work.wallSite(recipe)
        if not site then note("greatWall","WAITING FOR A DRY, UNBLOCKED BEACH WALL SITE INSIDE THE BORDER") return end
        local amounts={}
        for id,n in pairs(recipe.recipe)do amounts[id]=math.max(0,n-((work.buildingStock or{})[id]or 0))end
        return{id=recipe.id,info=recipe.info,recipe=recipe.recipe,site=site,amounts=amounts,
            key="greatWall:"..recipe.id,kind="structure",stationKind="building"}
    end
    function work.wallReady()
        if os.clock()<(work.wallCheckAt or 0)then return work.wallReadyValue==true end
        work.wallCheckAt=os.clock()+1
        local goal=work.wallGoal()
        work.wallReadyValue=goal and(count(goal.info.displayName)>0 or work.buildingSynced and work.structureStation()~=nil and work.goalRunnable(goal))or false
        return work.wallReadyValue
    end
    function work.wallTick()
        local goal,key=work.wallGoal(),"greatWall"
        if not goal then return false end
        if count(goal.info.displayName)>0 then
            local site=goal.site
            if not travel(site.box.Position,key,math.max(4,site.asset.size.Magnitude/2))then return false end
            local api=module("FreeBuild")
            if not api or not work.wallFooting(site.box,site.asset)or api.checkOverlap(site.box,site.asset.size,{},.1)or work.wallOccupied(site.box,site.asset)then return false end
            local before=count(goal.info.displayName)
            call("FreeBuild","requestPlace",goal.id,site.frame);work.sent=work.sent+1
            local placed=work.await(key,function()return work.wallOccupied(site.box,site.asset)and count(goal.info.displayName)<before end,4)
            if not placed then work.wallRetry[site.index]=os.clock()+5 end
            note(key,placed and"EXI WALL PLACEMENT CONFIRMED"or"WALL PLACEMENT / INVENTORY RECEIPT UNCONFIRMED")
            return placed
        end
        work.activeGoal,work.needs,work.amounts,work.resourceNeeds,work.needTotals=goal,{},{},{},{}
        for id,n in pairs(goal.amounts)do if n>0 then work.needItem(id,n,100)end end
        if work.batchReady(goal,key)then
            local supplied=not next(work.missing(goal.amounts))
            for id,n in pairs(goal.amounts)do local item=config().item.byId[id];if n>0 and item and count(item.displayName)>0 then supplied=true end end
            if supplied then return work.stationTick(goal,key)end
        end
        if work.reclaimStorage(goal,key)then return true end
        return pickups(key,true)or gatherResource(key,true)
    end
    function work.automationReport()
        local c=config();local rows={"AUTOMATION AUDIT v2 • COMBAT HANDOFFS"}
        local torch=work.shadowWeapon()
        rows[#rows+1]="Shadow: "..(not flags.killShadow and"OFF"or torch and"TORCH AVAILABLE; CONFIRMS TorchHits"or"BLOCKED: NO NATIVE LIGHT-SOURCE TOOL")
        rows[#rows+1]="Craft station: "..(work.stationSynced and"SYNCED"or"WAITING FOR SERVER STOCK")
        rows[#rows+1]="Building station: "..(work.buildingSynced and"SYNCED"or"WAITING FOR SERVER STOCK")
        rows[#rows+1]="Smelting: "..(built("Furnace")and("READY OUTPUT "..tostring(furnaceData.readyCount or 0))or"BLOCKED: FURNACE NOT BUILT")
        local wall=flags.greatWall and work.wallRecipe()
        rows[#rows+1]="EXI wall: "..(not flags.greatWall and"OFF"or wall and("NATIVE RECIPE "..wall.id.."; THREE LAYERS; OPEN ENTRANCE")or"BLOCKED: WALL MISSING FROM LIVE CATALOGUE")
        local passive,hostile=0,0
        for _,row in ipairs(work.creatures())do if row.hostile then hostile=hostile+1 else passive=passive+1 end end
        rows[#rows+1]="Loaded living mobs: "..hostile.." hostile / "..passive.." passive; unstreamed mobs unknown"
        rows[#rows+1]="Quest acquisition: "..tostring(taskStatus.questAcquire or"WAITING FOR ACTIVE REQUEST")
        rows[#rows+1]="Attack cycles: "..tostring(work.attackRequests or 0).." activations attempted / "..tostring(work.attackReceipts or 0).." damage receipts"
        rows[#rows+1]="Defence urgent: "..tostring(work.combatUrgent()).." | Guard radius "..tostring(opts.guardRadius).." | Evade recovery "..tostring(math.max(0,(work.evadeRecoverUntil or 0)-os.clock()))
        rows[#rows+1]="Bulk collection: "..tostring(flags.bulkCollect).." | Recipe fire level: "..tostring((work.fireState()or{}).level or"UNKNOWN")
        rows[#rows+1]="Next reward retry in: "..tostring(math.max(0,math.ceil((work.choiceRetryAt or 0)-os.clock()))).."s"
        return table.concat(rows,"\n")
    end
    function work.followTrail()
        local target = work.chestCandidate()
        if not target then return false end
        work.chestResume = target
        local points = {}
        for _, mark in ipairs(target:GetChildren()) do
            if mark.Name=="footprint" and pos(mark) then points[#points+1]=mark end
        end
        local center=pos(target)
        table.sort(points,function(a,b)return(pos(a)-center).Magnitude>(pos(b)-center).Magnitude end)
        local state=work.chestState(target)
        for i=(state.trailIndex or 0)+1,#points do
            if not work.safeResource(points[i]) or not travel(points[i],"chests",4) then return false end
            state.trailIndex=i
        end
        return work.openChest()
    end
    function work.questAcquireGoal()
        local req=flags.quest and work.questRequirement
        if work.questSubmission or not req or work.questTotal(req)>=req.count then return end
        local c=config();local item=c.item.byId[req.itemId]
        if not item then return end
        local needed=math.max(0,req.count-work.questTotal(req))
        local goal={key="questAcquire:"..req.itemId,kind="questSupply",itemId=req.itemId,
            questFor=req.itemId,name="MRBEAST: "..item.displayName,mode="direct",amounts={[req.itemId]=req.count},
            requested=req.itemId,required=req.count,revision=work.questCache and work.questCache.revision,scene=world(),needed=needed}
        -- Existing exact outputs take precedence over producing another batch.
        if work.storageCount(req.itemId)>0 then return goal end
        for _,drop in ipairs(work.models("drops"))do
            if drop.Name==item.displayName and work.dropAllowed(drop)and work.safeResource(drop)then return goal end
        end
        for raw,food in pairs(c.food and c.food.byId or{})do
            if food.canCook and food.cookTargetId==req.itemId then
                goal.mode,goal.raw="cook",raw
                local pending=campData.currentFoodId==raw and(campData.pendingCookCount or 0)or 0
                goal.amounts={[raw]=math.max(0,needed-pending)}
                break
            end
        end
        if req.itemId==c.misc.furnaceResultId then goal.mode="smelt"end
        local prerequisite=goal.mode=="cook"and"Campfire"or goal.mode=="smelt"and"Furnace"
        if prerequisite and not built(prerequisite)then
            local folder=world()and world():FindFirstChild("Buildings")
            for id,info in pairs(c.build and c.build.byId or{})do
                if info.assetId==prerequisite and folder and folder:FindFirstChild(info.assetId.."_Construct")then
                    goal.mode,goal.kind,goal.id,goal.info="build","build",id,info
                    goal.amounts=work.recipeAmounts(info,true)
                    goal.name=goal.name.." • BUILD "..prerequisite.." FIRST"
                    return goal
                end
            end
            goal.blocked="REQUIRED "..prerequisite:upper().." BLUEPRINT NOT LOADED"
        elseif goal.mode=="direct"and item.recipeId and next(work.recipeAmounts(item))and not(c.food and c.food.byId[item.id])then
            goal.mode,goal.kind,goal.id,goal.info="craft","craft",item.id,item
            goal.amounts=work.goalAmounts(goal)
        end
        return goal
    end
    function work.questPlanCurrent(goal)
        local req=flags.quest and work.questRequirement
        return req and world()==goal.scene and req.itemId==goal.requested and req.count==goal.required
            and(not goal.revision or work.questCache and work.questCache.revision==goal.revision)or false
    end
    function work.questAcquireReady()
        local goal=work.questAcquireGoal()
        if not goal then return false end
        if goal.blocked then note("questAcquire",goal.blocked)return false end
        if goal.mode=="cook"then
            if campData.readyFoodId==goal.requested and(campData.readyCount or 0)>0 then return work.canCollect()end
            local raw=config().item.byId[goal.raw]
            if(campData.readyCount or 0)>0 and work.isCookedFood(campData.readyFoodId)and work.canCollect()then return true end
            if raw and(goal.amounts[goal.raw]or 0)>0 and count(raw.displayName)>0 and work.cookCompatible(goal.raw)and not work.stormActive()then return true end
            if not next(work.missing(goal.amounts))then note("questAcquire","WAITING FOR REQUESTED FOOD TO FINISH COOKING")return false end
        elseif goal.mode=="smelt"then
            if(furnaceData.readyCount or 0)>0 and work.canCollect()then return true end
            if math.min(furnaceData.matter1Count or 0,furnaceData.matter2Count or 0)>=goal.needed then
                note("questAcquire","WAITING FOR REQUESTED IRON TO FINISH SMELTING")return false
            end
            local supply=work.supplyAmounts(goal)
            for _,id in ipairs({config().misc.furnaceMatter1Id,config().misc.furnaceMatter2Id})do
                local item=config().item.byId[id]
                if item and(supply[id]or 0)>0 and count(item.displayName)>0 then return true end
            end
        end
        local ready=work.goalRunnable(goal)
        if not ready then note("questAcquire",goal.name.." • NO SAFE LOADED SOURCE / TOOL / STATION YET")end
        return ready
    end
    function work.questAcquireStep(goal)
        local key="questAcquire"
        if not work.questPlanCurrent(goal)then return false end
        work.activeGoal,work.needs,work.amounts,work.resourceNeeds,work.needTotals=goal,{},{},{},{}
        local supply=work.supplyAmounts(goal)
        for id,n in pairs(supply)do
            if n>0 and not(goal.mode=="smelt"and id==goal.requested)then work.needItem(id,n,100)end
        end
        for id,resource in pairs(config().worldResource.byId)do
            for _,drop in pairs(config().itemDrop and config().itemDrop.byId[resource.dropId]or{})do
                local item=type(drop)=="table"and config().item.byName[drop.itemCN]
                if item and work.needs[item.id]then work.resourceNeeds[id]=100 end
            end
        end
        note(key,goal.name.." • ACQUIRING REQUESTED SUPPLIES")
        -- Reclaim the exact output before spending ingredients on another one.
        if work.reclaimStorage({amounts={[goal.requested]=goal.required}},key)then return true end
        if goal.mode=="cook"then
            if campData.readyFoodId==goal.requested and(campData.readyCount or 0)>0 then
                if not travel(built("Campfire"),key)or not work.questPlanCurrent(goal)then return false end
                return work.collectCookedUnit(key)
            end
            local raw=config().item.byId[goal.raw]
            if(campData.readyCount or 0)>0 and work.isCookedFood(campData.readyFoodId)and work.canCollect()then
                if not travel(built("Campfire"),key)or not work.questPlanCurrent(goal)then return false end
                note(key,"CLEARING PREVIOUS COOKED BATCH FOR MRBEAST")
                return work.collectCookedUnit(key)
            end
            if raw and(goal.amounts[goal.raw]or 0)>0 and count(raw.displayName)>0 and work.cookCompatible(goal.raw)and not work.stormActive()then
                if not travel(built("Campfire"),key)or not work.questPlanCurrent(goal)then return false end
                return work.submitUnits(key,"MakeFire","addFood",{[goal.raw]=math.min(goal.amounts[goal.raw]or 0,count(raw.displayName))},goal.raw)
            end
        elseif goal.mode=="smelt"then
            if(furnaceData.readyCount or 0)>0 and work.canCollect()then
                if not travel(built("Furnace"),key)or not work.questPlanCurrent(goal)then return false end
                return work.request(key,"Furnace","collectResult")
            end
            local supplied=false
            for _,id in ipairs({config().misc.furnaceMatter1Id,config().misc.furnaceMatter2Id})do
                local item=config().item.byId[id]
                if item and(supply[id]or 0)>0 and count(item.displayName)>0 then supplied=true end
            end
            if supplied then return work.smeltBag(key,supply)end
        elseif goal.mode=="build"or goal.mode=="craft"then
            if work.batchReady(goal,key)and work.submitGoal(key,goal)then return true end
        end
        if not work.questPlanCurrent(goal)or work.preempted then return false end
        if not work.canCollect()then return work.unloadBag()end
        if work.reclaimStorage({amounts=supply},key)then return true end
        if pickups(key,true)or gatherResource(key,true)then return true end
        if work.huntForMaterials(key)then return true end
        note(key,goal.name.." • SOURCE BLOCKED / UNLOADED; REQUEST REMAINS ACTIVE")
        return false
    end
    function work.questAcquireTick()
        local goal=work.questAcquireGoal()
        if not goal or goal.blocked then return false end
        work.questWork=goal
        local ok,result=pcall(work.questAcquireStep,goal)
        work.questWork,work.huntingNeeds,work.attackPlanCache=nil,nil,nil
        work.refreshAt=0
        if not ok then error(result)end
        return result
    end
    function work.criticalMeal()
        local _,human=root()
        if not human then return false end
        local hunger=human.GetAttribute and human:GetAttribute("hunger")
        local maximum=human.GetAttribute and(human:GetAttribute("maxHunger")or 100)or 100
        return human.Health/human.MaxHealth*100<=opts.retreatHealth or hunger and hunger/math.max(1,maximum)<.15 or false
    end
    function work.autoAttackReady()
        if os.clock()<(work.nextStrikeAt or 0)or os.clock()<(work.evadeRecoverUntil or 0)then return false end
        local r=root();local tool,stats=work.meleeWeapon("autoAttack")
        if not r or not tool then return false end
        local target=work.enemy(stats.range or 6,false)
        return target and work.stanceScore(r.Position,target,stats)~=nil or false
    end
    function work.autoAttackTick()
        local r=root()
        local tool,stats=work.meleeWeapon()
        if not r or not tool then return false end
        local target=work.enemy(stats.range or 6, false)
        if not target or not work.stanceScore(r.Position,target,stats) then return false end
        return work.strike(tool,stats,{target},{},"autoAttack")
    end
    function work.readObjectiveHints()
        local lines, seen, c = {}, {}, config()
        for _,model in ipairs(work.models("artifacts")) do
            if not work.artifacts[model.Name] then
                local row=c.mapProp and (c.mapProp.byCnId[model.Name] or c.mapProp.byDisplayName and c.mapProp.byDisplayName[model.Name])
                local hint=row and (row.hint or row.txtDesc or row.description)
                local line=model.Name..(type(hint)=="string" and " · "..hint or " · FIND AND HOLD E TO COLLECT")
                lines[#lines+1]=line seen[line]=true
                for _,node in ipairs(model:GetDescendants()) do
                    if #lines>=8 then break end
                    if node:IsA("TextLabel") and node.Text~="" and not seen[node.Text] then lines[#lines+1]=node.Text seen[node.Text]=true end
                end
            end
            if #lines>=8 then break end
        end
        if flags.followFootprints then lines[#lines+1]="FOOTPRINTS → THEIR PARENT CHEST; OPEN AND COLLECT ITS LOOT" end
        if work.hintLabel then work.hintLabel.Text=#lines>0 and table.concat(lines,"\n") or "NO LOADED CLUES; EXPLORATION REMAINS ENABLED" end
    end
    function work.survivalSync()
        local scene=world()
        if not scene then return end
        if flags.autoFarm ~= false and flags.quest and os.clock()>=(work.questPollAt or 0) then work.questPollAt=os.clock()+.75 work.readQuest(true) end
        if os.clock()>=(work.hintPollAt or 0) then work.hintPollAt=os.clock()+2 work.readObjectiveHints() end
        if work.survivalScene==scene then return end
        work.survivalScene=scene
        work.storageSnapshot,work.buildingStock,work.buildingSynced={},{},false
        work.structureSites,work.storagePlannedFrame=nil,nil
        local service=RS.Engine.Service:FindFirstChild("Storage")
        local changed=service and service:FindFirstChild("snapshotRemote")
        local generation=0
        if changed then connections[#connections+1]=changed.OnClientEvent:Connect(function(stock)
            if world()==scene and type(stock)=="table" then generation=generation+1 work.storageSnapshot=stock work.storageBlockedAt=nil end
        end) end
        local snapshot=service and service:FindFirstChild("getSnapshotFunc")
        if snapshot then task.spawn(function()
            local ok,stock=pcall(function()return snapshot:InvokeServer()end)
            if alive and world()==scene and ok and type(stock)=="table" and generation==0 then work.storageSnapshot=stock end
        end) end
        task.spawn(function()
            safely("building station sync",function()
                connections[#connections+1]=work.net("BuildingStationStateChanged").OnClientEvent:Connect(function(stock)
                    if world()==scene and type(stock)=="table" then work.buildingStock=stock work.buildingSynced=true work.refreshAt=0 end
                end)
                work.net("BuildingStationRequestState"):FireServer()
            end)
        end)
    end
    local jobsList = {
        {key="questAcquire",enabled=function()return flags.quest end,ready=work.questAcquireReady,run=work.questAcquireTick},
        {key="equipArmour",enabled=function()return flags.progression end,ready=function()return work.armourCandidate()~=nil end,run=work.equipArmour},
        {key="greatWall",enabled=function()return flags.greatWall end,ready=work.wallReady,run=work.wallTick},
        {key="shadowHunt",enabled=function()return flags.killShadow end,ready=function()return work.shadowCandidate()~=nil end,
            run=function()return defend("shadowHunt")end},
        {key="toolTidy",enabled=function()return flags.tidyTools end,ready=function()return (not work.bulkUnloadReady or work.bulkUnloadReady()) and work.spareToolCandidate()~=nil and work.campDropAnchor()~=nil end,run=work.tidyTools},
        {key="foodHunt",enabled=function()return flags.killFoodOnSight end,ready=function()return work.foodHuntCandidate()~=nil end,
            run=function()
                work.huntingPassive,work.attackPlanCache=true,nil
                local ok,result=pcall(defend,"foodHunt")
                work.huntingPassive,work.attackPlanCache=nil,nil
                work.foodHuntAt=os.clock()+1
                if not ok then error(result)end
                return result
            end},
        {key="foodCache",enabled=function()return flags.unloadBag or flags.stormStock end,ready=function()return work.foodCacheReady()and(not work.bulkUnloadReady or work.bulkUnloadReady())end,run=work.cacheFood},
        {key="autoAttack", ready=work.autoAttackReady, run=work.autoAttackTick},
        {key="foodSupply", enabled=function()return flags.stormStock or flags.killFoodOnSight end, ready=work.foodSupplyReady, run=work.foodSupplyTick},
        {key="structures", enabled=function()return flags.structureCraft end, ready=work.structureReady, run=work.structureTick},
        {key="stockpile", enabled=function()return flags.scavengeAll end,
            ready=function()return work.canCollect() and (work.pickupCandidate(false,"stockpile") or work.resourceCandidate("stockpile",false))~=nil end,
            run=function()return pickups("stockpile",false) or gatherResource("stockpile",false) end},
        {
            key = "foodPickup", priority = 3.15, cooldown = 0,
            enabled = function() return flags.huntFood or flags.quest or flags.hunt or flags.killFoodOnSight or flags.stormStock end,
            ready = function() return work.canCollect() and work.foodDropCandidate() ~= nil end,
            run = work.collectHuntedFood,
        },
        {
            key = "unloadBag", priority = 3.9, cooldown = 0.1,
            ready = function()
                local used, cap = work.bagState()
                -- Finish a chest batch before making a camp trip, unless full.
                if work.chestResume and used < cap then return false end
                return (not work.bulkUnloadReady or work.bulkUnloadReady()) and work.unloadCandidate() ~= nil and work.campDropAnchor() ~= nil
            end,
            run = work.unloadBag,
        },
        {
            key = "tidyBag", priority = 4, cooldown = 0.15,
            enabled = function()
                return flags.tidyBag or work.progressionEnabled() or flags.gather or flags.chopTrees
                    or flags.mineStone or flags.mineIron or flags.drops or work.treeDrops ~= nil
                    or (work.dropQueue and #work.dropQueue > 0)
            end,
            ready = function()
                local used, cap = work.bagState()
                return used >= cap or (flags.tidyBag and work.bagSubmissionReady())
            end,
            run = work.tidyBag,
        },
        {
            key = "artifacts", priority = 8, cooldown = 0,
            ready = function() return work.artifactCandidate() ~= nil end,
            run = work.fetchArtifact,
        },
        {
            key = "nightHold", priority = 10, cooldown = 0,
            enabled = function() return work.hover ~= nil or work.shelterNeeded() or flags.holdNight and work.isNight() end,
            ready = function() return built("Campfire") ~= nil end,
            run = work.nightHold,
        },
        {
            key = "evade", priority = 0, cooldown = 0,
            enabled = function() return (opts.avoidEnemies or flags.runShadow) and work.automationOn() end,
            ready = function() return work.personalThreat() ~= nil end,
            run = work.evade,
        },
        {
            key = "mrbeastReward", priority = 3.6, cooldown = 0.02,
            enabled = function() return flags.choiceRewards end,
            ready = function()
                work.recoverChoices()
                if work.choices and work.choiceSentVersion == work.choiceVersion and os.clock() - (work.choiceSentAt or 0) >= 2.5 then
                    work.choiceSentVersion = nil
                end
                return work.choices and work.choiceSentVersion ~= work.choiceVersion and os.clock()>=(work.choiceRetryAt or 0)
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
            enabled = function() return work.treeDrops and work.contextEnabled(work.treeDrops.key) end,
            ready = function() return work.canCollect() and work.treeDrops and work.contextEnabled(work.treeDrops.key)
                and work.safeWorkPoint(work.treeDrops.center, 5) end,
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
            enabled = function() return flags.combat or flags.aura or flags.autoAttack end,
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
            enabled = work.progressionEnabled,
            priority = 2.5,
            cooldown = 0.2,
            ready = function() return work.objective ~= nil end,
            run = work.progressionTick,
        },
        {
            key = "hunt",
            enabled = function() return flags.hunt or work.foodHuntReady() or (flags.quest and work.huntCandidate(work.huntWanted()) ~= nil) end,
            priority = 8,
            cooldown = 1,
            ready = function() return work.meleeWeapon() ~= nil and (flags.hunt and work.enemy(opts.huntRadius, true) or work.huntCandidate(work.huntWanted())) ~= nil end,
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
                return item and count(item.displayName) > 0 and work.maintenanceGoal() ~= nil
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
                return blueprintReady(false)and work.buildBatchReady(false)
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
                local item=config().item.byId[req.itemId]
                return work.questSubmission~=nil or item and(work.questTotal(req)>=req.count or count(item.displayName)>0)
            end,
            run = function() return questTick("quest", true) end,
        },
        {
            key = "drops",
            priority = function()
                return next(work.needs) and 7 or 12
            end,
            cooldown = 0.4,
            ready = function() return work.canCollect() and work.pickupCandidate(false) ~= nil end,
            run = pickups,
        },
        {
            key = "cooked",
            priority = 4.5,
            cooldown = 3,
            ready = function()
                return work.canCollect()and built("Campfire")and(campData.readyCount or 0)>0 and work.mealNeeded()and work.noFood()
            end,
            run = function()return work.collectCookedUnit("cooked")end,
        },
        {
            key = "craft",
            enabled = function() return flags.quest or flags.craft or flags.progression or flags.toolLadder or flags.bagUpgrade end,
            priority = 3.5,
            cooldown = 0,
            ready = function() return work.nextReadyCraft() ~= nil end,
            run = craftTick,
        },
        {
            key = "build",
            priority = function()
                return built("Campfire") and 6 or 3.3
            end,
            cooldown = 4,
            ready = function()
                return not selectedEmpty("build") and blueprintReady(true)and work.buildBatchReady(true)
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
            enabled = function() return flags.smeltCollect or flags.smelt end,
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
                return built("Furnace") ~= nil and (not work.bulkUnloadReady or work.bulkUnloadReady())
                    and ((a and count(a.displayName) > 0) or (b and count(b.displayName) > 0))
            end,
            run = function()
                return work.smeltBag("smelt")
            end,
        },
        {
            key = "puzzles",
            ready = function() return work.exploreAvailable("puzzle") end,
            priority = 10,
            cooldown = 3,
            run = function()
                return exploreTick("puzzles", "puzzle", "PuzzlePropService", "isSolved", "requestSolve")
            end,
        },
        {
            key = "chests",
            ready = function() return work.chestCandidate() ~= nil end,
            priority = 11,
            cooldown = 3,
            run = function()
                if flags.followFootprints then return work.followTrail() end
                return exploreTick("chests", "chest", "ChestService", "isOpened", "requestOpen")
            end,
        },
        {
            key = "gather",
            enabled = function() return flags.gather or flags.chopTrees or flags.mineStone or flags.mineIron end,
            priority = function()
                return next(work.needs) and 7.5 or 13
            end,
            cooldown = 0.3,
            ready = function() return work.canCollect() and (work.treeDrops or work.resourceCandidate("gather", false)) ~= nil end,
            run = gatherResource,
        },
        {
            key = "fish",
            priority = 14,
            cooldown = 2,
            run = fishTick,
        },
    }
    work.seenCuts = setmetatable({}, {__mode = "k"})
    work.seenPickups = setmetatable({}, {__mode = "k"})
    work.seenGuards = setmetatable({}, {__mode = "k"})
    function work.recordCut(model, info)
        if not work.seenCuts[model] and work.resourceKind(info) == "tree" then
            work.counts.felled = work.counts.felled + 1 work.seenCuts[model] = true
        end
    end
    function work.recordPickup(model)
        if not work.seenPickups[model] then work.counts.picked = work.counts.picked + 1 work.seenPickups[model] = true end
    end
    function work.recordGuard(model)
        local human = model:FindFirstChildOfClass("Humanoid")
        if human and human.Health <= 0 and not work.seenGuards[model] then work.counts.guarded = work.counts.guarded + 1 work.seenGuards[model] = true end
    end
    work.jobs, work.jobsByKey = jobsList, {}
    for _, job in ipairs(jobsList) do work.jobsByKey[job.key] = job end
    function work.settleCuts()
        work.captureCampDrops()
        work.pollLateDrops()
        work.dropQueue = work.dropQueue or {}
        for model, context in pairs(work.resourcePlans or {}) do
            local hp = model:GetAttribute("hp")
            if not model.Parent or (type(hp) == "number" and hp <= 0) then
                local info = config().worldResource.byId[model:GetAttribute("resourceId")]
                if info then work.recordCut(model, info) end
                work.dropQueue[#work.dropQueue + 1] = context
                work.resourcePlans[model] = nil
            end
        end
        if not work.treeDrops and #work.dropQueue > 0 then
            work.treeDrops = table.remove(work.dropQueue, 1) work.treeDrops.queued = nil
        end
        work.rotateRecoveries()
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
                work.bindSuite()
                work.sessionTick(mode)
                work.redeemTick()
                if mode ~= "match" or flags.autoFarm == false or work.finished or work.roundLost()
                    or not root()
                    or (work.hover and work.hover.character ~= player.Character) then work.releaseHover(true)
                elseif work.hover and not work.shelterNeeded() then work.releaseHover() end
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
                safely("survival sync", work.survivalSync)
                safely("material planning", work.refreshNeeds)
                work.settleCuts()
                work.preempted = nil
                work.nextPriorityCheck = 0
                local now = os.clock()
                local job = safely("queue readiness", function()
                    return work.nextQueuedJob(jobsList, now)
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
                    note("queue", "NO SAFE READY JOB; CHECK RESOURCE / UPGRADE STATUS")
                    return
                end
                if job.key ~= "nightHold" and job.key ~= "fuel" and job.key ~= "eat" then
                    if not work.releaseHover(false,job.key=="foodCache") then return end
                end
                work.active = job.key
                work.currentJob = job
                work.bulkTrip=flags.bulkCollect and(job.key=="unloadBag"or job.key=="foodCache"or job.key=="tidyBag")or nil
                work.progressAt, work.progressSignature = os.clock(), work.signature()
                local progressRoot = root()
                work.progressPosition = progressRoot and progressRoot.Position
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
                due[job.key] = math.max(due[job.key] or 0, os.clock() + (work.preempted and 0 or (acted and 0 or backoff)))
                if work.preempted then
                    local nextKey = work.preempted.to
                    due[nextKey] = os.clock()
                    note(job.key, "PAUSED FOR " .. nextKey:upper() .. "; REMAINS ENABLED")
                end
                if requested and not acted and not work.preempted then
                    note("queue", job.key:upper() .. " REQUEST NOT CONFIRMED")
                end
                work.waiting[job.key] = nil
                work.bagSweepRank = nil
                work.unloadRank, work.unloadWatch = nil, nil
                work.activeGoal = nil
                work.bulkTrip=nil
                work.interaction = nil
                work.active, work.currentJob = nil, nil
                queueLabel.Text = "LAST JOB: " .. job.key:upper()
                if not acted and not work.preempted then
                    note("queue", job.key:upper() .. " STOPPED / WAITING / UNCONFIRMED; NEXT READY JOB")
                end
            end)
            if not ok then
                note("queue", "ERROR: " .. tostring(e))
                say(e)
                work.bagSweepRank = nil
                work.unloadRank, work.unloadWatch = nil, nil
                work.activeGoal = nil
                work.interaction = nil
                work.active, work.currentJob = nil, nil
                motion.cancel("JOB ERROR")
            end
            if os.clock() >= (work.nextDiagnosticAt or 0) then
                safely("diagnostic view", refreshDiagnostics)
                work.nextDiagnosticAt = os.clock() + 0.5
            end
            local wakeAt = os.clock() + math.max(0, opts.interval)
            repeat
                task.wait()
                local ready = work.pick(jobsList, os.clock(), 9)
                if ready then break end
            until not alive or os.clock() >= wakeAt
        end
    end)
    local hoverElapsed=0
    connections[#connections+1]=game:GetService("RunService").Heartbeat:Connect(function(dt)
        hoverElapsed=hoverElapsed+dt
        if hoverElapsed>=.15 then
            hoverElapsed=0
            if work.hover then safely("hover guard",work.hoverTick)end
        end
    end)
    task.spawn(function()
        while alive do
            safely("live status", work.statusTick)
            safely("survival sync", work.survivalSync)
            safely("categorized ESP", work.espTick)
            task.wait(0.5)
        end
    end)
    say("ISLAND ESCAPE LOADED • LONG RUN MODE • CONFIG SAVED PER GAME")
end
local ok, err = xpcall(runIslandEscape, Diagnostics.traceback)
if not ok then
    if diagnostic then diagnostic:record("startup",err,"ERROR") diagnostic:flush() end
    warn("EXIScript / MrbeastIslandEscape: " .. tostring(err))
end





