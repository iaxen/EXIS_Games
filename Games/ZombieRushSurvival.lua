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

function Core.fits(p, width, depth, poly, touching)
    local corners = Core.rectangle(p, width, depth)
    for _, corner in ipairs(corners) do if not Core.inside(corner, poly) then return false end end
    -- Checking corners alone is insufficient for a concave boundary.
    for i, a in ipairs(poly) do
        local b = poly[i % #poly + 1]
        if touching and a.x > p.x - width/2 + 0.00001 and a.x < p.x + width/2 - 0.00001
            and a.z > p.z - depth/2 + 0.00001 and a.z < p.z + depth/2 - 0.00001 then return false end
        for j, c in ipairs(corners) do
            local d = corners[j % 4 + 1]
            if Core.intersects(a, b, c, d) then
                if not touching or Core.cross(a, b, c) * Core.cross(a, b, d) < -0.000001
                    and Core.cross(c, d, a) * Core.cross(c, d, b) < -0.000001 then return false end
            end
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
    if name:find("Barricade") or info.Style == "Barrier" or info.Classification and info.Classification.Barricade then return "wall" end
    if info.PlayerBuff or name == "ReconTower" then return "support" end
    if info.Placement and info.Placement.Ability then return "ability" end
    if name:find("Barrel") or name:find("Mine") or name:find("Bomb") or name:find("Trap") then return "trap" end
    return "turret"
end

-- Offset every edge inward. Reject collapsed/self-crossing offsets instead of
-- bridging a narrow concavity with an imaginary wall.
function Core.insetPolygon(poly, inset)
    local area, edges = 0, {}
    for i, a in ipairs(poly) do local b = poly[i % #poly + 1]; area = area + a.x * b.z - b.x * a.z end
    local sign = area > 0 and 1 or -1
    for i, a in ipairs(poly) do
        local b = poly[i % #poly + 1]
        local dx, dz = b.x - a.x, b.z - a.z
        local length = math.sqrt(dx * dx + dz * dz)
        edges[i] = {x = a.x - sign * dz / length * inset, z = a.z + sign * dx / length * inset,
            dx = dx, dz = dz}
    end
    local result = {}
    for i, edge in ipairs(edges) do
        local prev = edges[(i - 2) % #edges + 1]
        local cross = prev.dx * edge.dz - prev.dz * edge.dx
        local x, z = edge.x, edge.z
        if math.abs(cross) > 0.00001 then
            local t = ((edge.x - prev.x) * edge.dz - (edge.z - prev.z) * edge.dx) / cross
            x, z = prev.x + t * prev.dx, prev.z + t * prev.dz
        end
        local point = {x = x, y = poly[i].y, z = z}
        if not Core.inside(point, poly) then return nil end
        -- An offset larger than a narrow corridor can fold back inside it.
        for j, a in ipairs(poly) do
            if Core.edgeDistance(point, a, poly[j % #poly + 1]) < inset - 0.001 then return nil end
        end
        result[#result + 1] = point
    end
    for i, a in ipairs(result) do
        local b = result[i % #result + 1]
        if (a.x-b.x)^2+(a.z-b.z)^2 < 0.000001 then return nil end
        for j = i+2, #result do
            if not (i==1 and j==#result) and Core.intersects(a,b,result[j],result[j % #result+1]) then return nil end
        end
    end
    return result
end

function Core.containsBox(point, box)
    return math.abs(point.x - box.x) <= box.w / 2 + 0.00001
        and math.abs(point.z - box.z) <= box.d / 2 + 0.00001
end

-- Exact segment/rectangle intervals reveal even gaps narrower than the planner's
-- sampling step. Only real blocking walls count, never turret firing circles.
function Core.wallCoverage(ring, boxes, role)
    local gaps, total, uncovered = {}, 0, 0
    for i, a in ipairs(ring or {}) do
        local b, intervals = ring[i % #ring + 1], {}
        local dx, dz = b.x - a.x, b.z - a.z
        local length = math.sqrt(dx * dx + dz * dz)
        total = total + length
        for _, box in ipairs(boxes) do
            if box.role == (role or "wall") and ((role and role~="wall") or box.blocking ~= false) then
                local low, high = 0, 1
                for _, axis in ipairs({{"x", dx, box.w}, {"z", dz, box.d}}) do
                    local key, delta, size = axis[1], axis[2], axis[3]
                    if math.abs(delta) < 0.000001 then
                        if math.abs(a[key] - box[key]) > size / 2 + 0.00001 then high = -1 end
                    else
                        local t1, t2 = (box[key] - size / 2 - a[key]) / delta, (box[key] + size / 2 - a[key]) / delta
                        low, high = math.max(low, math.min(t1, t2)), math.min(high, math.max(t1, t2))
                    end
                end
                if high >= low then intervals[#intervals + 1] = {low, high} end
            end
        end
        table.sort(intervals, function(x, y) return x[1] < y[1] end)
        local cursor = 0
        local function gap(to)
            if to > cursor + 0.00001 then
                local mid = (cursor + to) / 2
                gaps[#gaps + 1] = {edge = i, x = a.x + dx * mid, z = a.z + dz * mid,
                    start = {x = a.x + dx * cursor, z = a.z + dz * cursor},
                    finish = {x = a.x + dx * to, z = a.z + dz * to},
                    length = (to - cursor) * length}
                uncovered = uncovered + (to - cursor) * length
            end
        end
        for _, span in ipairs(intervals) do gap(span[1]); cursor = math.max(cursor, span[2]) end
        gap(1)
    end
    return {gaps = gaps, uncovered = uncovered, total = total}
end

-- Exact union of axis-aligned deployment footprints clipped to the selected
-- polygon. Sweep events include sloping-polygon / box-height intersections.
-- Targeting range is deliberately not treated as spawn suppression coverage.
function Core.areaCoverage(poly, boxes)
    local xs, area = {}, 0
    for i, a in ipairs(poly) do
        local b = poly[i % #poly + 1]
        xs[#xs + 1] = a.x; area = area + a.x * b.z - b.x * a.z
    end
    local minX, maxX = math.huge, -math.huge
    for _, x in ipairs(xs) do minX, maxX = math.min(minX, x), math.max(maxX, x) end
    for _, box in ipairs(boxes) do
        xs[#xs + 1], xs[#xs + 2] = math.max(minX, box.x - box.w/2), math.min(maxX, box.x + box.w/2)
        for i, a in ipairs(poly) do
            local b = poly[i % #poly + 1]
            if math.abs(b.z - a.z) > 0.000001 then
                for _, z in ipairs({box.z - box.d/2, box.z + box.d/2}) do
                    local t = (z - a.z) / (b.z - a.z)
                    if t > 0 and t < 1 then xs[#xs + 1] = a.x + (b.x - a.x) * t end
                end
            end
        end
    end
    table.sort(xs)
    local covered = 0
    for i = 1, #xs - 1 do
        local left, right = math.max(minX, xs[i]), math.min(maxX, xs[i+1])
        if right > left + 0.000001 then
            local x, cuts, spans = (left + right)/2, {}, {}
            for j, a in ipairs(poly) do
                local b = poly[j % #poly + 1]
                if (a.x > x) ~= (b.x > x) then cuts[#cuts + 1] = a.z + (b.z-a.z) * (x-a.x)/(b.x-a.x) end
            end
            table.sort(cuts)
            for _, box in ipairs(boxes) do
                if x > box.x-box.w/2 and x < box.x+box.w/2 then spans[#spans+1] = {box.z-box.d/2,box.z+box.d/2} end
            end
            table.sort(spans,function(a,b)return a[1]<b[1]end)
            local merged = {}
            for _, span in ipairs(spans) do
                local last = merged[#merged]
                if last and span[1] <= last[2] then last[2] = math.max(last[2],span[2]) else merged[#merged+1] = {span[1],span[2]} end
            end
            local length = 0
            for j = 1, #cuts-1, 2 do
                for _, span in ipairs(merged) do length = length + math.max(0,math.min(cuts[j+1],span[2])-math.max(cuts[j],span[1])) end
            end
            covered = covered + length * (right-left)
        end
    end
    area = math.abs(area)/2
    return {area = area, covered = math.min(area,covered), uncovered = math.max(0,area-covered)}
end

function Core.plan(poly, specs, limit, existing, yieldWork, middleSpacing)
    existing = existing or {}
    -- No runtime count cap: the selected geometry and native affordability bound placement.
    limit = Core.finite(limit) and math.max(0,math.floor(limit)) or math.huge
    middleSpacing = Core.finite(middleSpacing) and math.max(6,math.min(40,middleSpacing)) or 12
    if not Core.validPolygon(poly) then return {}, "SELECT A VALID AREA" end
    local minX,maxX,minZ,maxZ,y=math.huge,-math.huge,math.huge,-math.huge,0
    for _,p in ipairs(poly)do
        minX,maxX,minZ,maxZ=math.min(minX,p.x),math.max(maxX,p.x),math.min(minZ,p.z),math.max(maxZ,p.z)
        y=y+p.y/#poly
    end
    if maxX-minX>600 or maxZ-minZ>600 then return {},"SELECT A SMALLER AREA" end
    local roles={wall={},turret={},support={},trap={}}
    local wallSize,turretSize,grid=0,0,1
    for _,spec in ipairs(specs)do
        if roles[spec.role]then roles[spec.role][#roles[spec.role]+1]=spec end
        local size=math.max(spec.w,spec.d)*(spec.grid or 1)
        if spec.role=="wall"and spec.blocking~=false then wallSize=math.max(wallSize,size)end
        if spec.role=="turret"then turretSize=math.max(turretSize,size)end
        grid=math.max(grid,spec.grid or 1)
    end
    local result,used,reserve={}, {},nil
    for _,box in ipairs(existing)do used[#used+1]=box end
    local work=0
    local function snapped(spec,point,facing)
        local g,w,d=spec.grid or 1,spec.w,spec.d
        if facing%2==1 then w,d=d,w end
        return{x=(math.floor(point.x/g-w/2+.5)+w/2)*g,y=y,
            z=(math.floor(point.z/g-d/2+.5)+d/2)*g,w=w*g,d=d*g,
            name=spec.name,role=spec.role,facing=facing,blocking=spec.role=="wall"and spec.blocking~=false,spec=spec}
    end
    local function available(box,ignoreReserve)
        work=work+1;if yieldWork and work%256==0 then yieldWork()end
        if not Core.fits(box,box.w,box.d,poly,true)then return false end
        for _,other in ipairs(used)do
            if not(ignoreReserve and other==reserve)and Core.overlap(box,other,0)then return false end
        end
        return true
    end
    local function add(box)
        if #result>=limit or not available(box)then return false end
        result[#result+1],used[#used+1]=box,box;return true
    end
    local center={x=(minX+maxX)/2,z=(minZ+maxZ)/2}
    -- Reserve an actual selected support unit, never a phantom hole for a class
    -- that cannot build one. The middle is intentionally spaced, not tiled.
    if roles.support[1]then
        local best
        for x=minX,maxX,math.max(2,(maxX-minX)/16)do
            for z=minZ,maxZ,math.max(2,(maxZ-minZ)/16)do
                local box=snapped(roles.support[1],{x=x,z=z},roles.support[1].facing or 0)
                local d=(x-center.x)^2+(z-center.z)^2
                if available(box)and(not best or d<best)then reserve,best=box,d end
            end
        end
        if reserve then used[#used+1]=reserve end
    end
    local rectangle=#poly==4
    for _,p in ipairs(poly)do
        if math.min(math.abs(p.x-minX),math.abs(p.x-maxX))>.0001
            or math.min(math.abs(p.z-minZ),math.abs(p.z-maxZ))>.0001 then rectangle=false end
    end
    local layers,counts={},{}
    local function layer(name,role,inset,quota,types,bounds)
        local ring=Core.insetPolygon(poly,inset)
        local reference=types[1]
        if role=="wall"then for _,spec in ipairs(types)do if spec.blocking~=false then reference=spec;break end end end
        if bounds and reference then
            local w,d=reference.w*(reference.grid or 1),reference.d*(reference.grid or 1)
            if bounds.maxX-bounds.minX>w and bounds.maxZ-bounds.minZ>d then
                ring={{x=bounds.minX+w/2,y=y,z=bounds.minZ+d/2},{x=bounds.maxX-w/2,y=y,z=bounds.minZ+d/2},
                    {x=bounds.maxX-w/2,y=y,z=bounds.maxZ-d/2},{x=bounds.minX+w/2,y=y,z=bounds.maxZ-d/2}}
            else ring=nil end
        end
        local row={name=name,role=role,ring=ring,inset=inset,planned=0}
        layers[#layers+1]=row
        if not ring then row.unfit=true;return end
        local pool,seen={},{}
        if bounds then
            -- A picked rectangular floor can be tiled exactly on its native
            -- grid. Fixed rows avoid greedy corner gaps and work for barriers
            -- whose native contract does not support rotation.
            for _,spec in ipairs(types)do
                if role~="wall"or spec.blocking~=false then
                    local g=spec.grid or 1;local w,d=spec.w*g,spec.d*g
                    local function candidate(x,z,edge)
                        local box=snapped(spec,{x=x,z=z},0)
                        local key=spec.name..":"..box.x..":"..box.z
                        if not seen[key]and available(box)then
                            seen[key]=true;box.edge,box.layer=edge,name;pool[#pool+1]=box
                        end
                    end
                    for x=bounds.minX+w/2,bounds.maxX-w/2+.0001,w do
                        candidate(x,bounds.minZ+d/2,1);candidate(x,bounds.maxZ-d/2,3)
                    end
                    for z=bounds.minZ+d*1.5,bounds.maxZ-d*1.5+.0001,d do
                        candidate(bounds.minX+w/2,z,4);candidate(bounds.maxX-w/2,z,2)
                    end
                end
            end
        else
        for i,a in ipairs(ring)do
            local b=ring[i%#ring+1];local dx,dz=b.x-a.x,b.z-a.z
            local length=math.sqrt(dx*dx+dz*dz)
            local n=math.max(1,math.min(math.ceil(length/grid),math.floor(2048/#ring)))
            for j=0,n do
                for _,spec in ipairs(types)do
                    if role~="wall"or spec.blocking~=false then
                        local facing=spec.facing or 0
                        if spec.canRotate then
                            facing=math.floor(-math.atan2(dz,dx)/(math.pi/2)+.5)%4
                            if spec.w<spec.d then facing=(facing+1)%4 end
                        end
                        local box=snapped(spec,{x=a.x+dx*j/n,z=a.z+dz*j/n},facing)
                        local key=spec.name..":"..box.x..":"..box.z..":"..facing
                        if not seen[key]and available(box)then
                            seen[key]=true;box.edge,box.layer=i,name;pool[#pool+1]=box
                        end
                    end
                end
            end
        end
        end
        local nextEdge=1
        while row.planned<quota and #result<limit do
            local coverage=Core.wallCoverage(ring,used,role)
            if coverage.uncovered<.001 then break end
            local choice,best,chosenEdge
            table.sort(coverage.gaps,function(a,b)return(a.edge-nextEdge+#ring)%#ring<(b.edge-nextEdge+#ring)%#ring end)
            for pass=1,3 do
                for _,gap in ipairs(coverage.gaps)do
                    local target=pass==1 and gap.start or pass==2 and gap.finish or gap
                    for _,box in ipairs(pool)do
                        if Core.containsBox(target,box)and available(box)then
                            local a,b=ring[gap.edge],ring[gap.edge%#ring+1]
                            local dx,dz=b.x-a.x,b.z-a.z
                            local length=math.sqrt(dx*dx+dz*dz)
                            local direction=pass==2 and -1 or 1
                            local probe={x=target.x+dx/length*.01*direction,z=target.z+dz/length*.01*direction}
                            if Core.containsBox(probe,box)then
                                local gain=0
                                for k=1,8 do
                                    local t=k/8
                                    local point={x=gap.start.x+(gap.x-gap.start.x)*2*t,z=gap.start.z+(gap.z-gap.start.z)*2*t}
                                    if Core.containsBox(point,box)then gain=gain+1 end
                                end
                                local score=gain*100-(counts[box.name]or 0)
                                if not best or score>best then choice,best,chosenEdge=box,score,gap.edge end
                            end
                        end
                    end
                    if choice then break end
                end
                if choice then break end
            end
            if not choice or not add(choice)then break end
            counts[choice.name]=(counts[choice.name]or 0)+1;row.planned=row.planned+1;nextEdge=chosenEdge%#ring+1
        end
        row.coverage=Core.wallCoverage(ring,used,role)
    end
    local supportBudget=reserve and 1 or 0
    local middleBudget=math.min(3,limit)
    local outerInset=wallSize>0 and wallSize/2+grid*.6 or grid*.6
    local wallBudget=#roles.turret>0 and math.floor(math.max(0,limit-middleBudget-supportBudget)*.3)or math.max(0,limit-middleBudget-supportBudget)
    local wallReference
    for _,spec in ipairs(roles.wall)do if spec.blocking~=false then wallReference=spec break end end
    local bounds=rectangle and {minX=minX,maxX=maxX,minZ=minZ,maxZ=maxZ}or nil
    if wallSize>0 then layer("BARRICADE","wall",outerInset,wallBudget,roles.wall,bounds)end
    local firstInset=outerInset+(wallSize>0 and wallSize/2 or 0)+turretSize/2+grid*.1
    local fitted=0
    if #roles.turret>0 then
        for n=1,3 do
            local quota=math.max(0,math.floor((limit-#result-middleBudget-supportBudget)/(4-n)))
            local frame
            if rectangle then
                local wx=wallReference and wallReference.w*(wallReference.grid or 1)or 0
                local wz=wallReference and wallReference.d*(wallReference.grid or 1)or 0
                frame={minX=minX+wx+(n-1)*turretSize,maxX=maxX-wx-(n-1)*turretSize,
                    minZ=minZ+wz+(n-1)*turretSize,maxZ=maxZ-wz-(n-1)*turretSize}
            end
            layer("TURRET "..n,"turret",firstInset+(n-1)*turretSize,quota,roles.turret,frame)
            if not layers[#layers].unfit then fitted=fitted+1 end
        end
    end
    if reserve and #result<limit and available(reserve,true)then
        result[#result+1]=reserve;reserve.layer="SUPPORT"
    end
    local innerInset=firstInset+2*turretSize+turretSize/2
    local inner=Core.insetPolygon(poly,innerInset)
    if rectangle then
        local wx=wallReference and wallReference.w*(wallReference.grid or 1)or 0
        local wz=wallReference and wallReference.d*(wallReference.grid or 1)or 0
        if maxX-minX>2*(wx+3*turretSize)and maxZ-minZ>2*(wz+3*turretSize)then
            inner={{x=minX+wx+3*turretSize,y=y,z=minZ+wz+3*turretSize},{x=maxX-wx-3*turretSize,y=y,z=minZ+wz+3*turretSize},
                {x=maxX-wx-3*turretSize,y=y,z=maxZ-wz-3*turretSize},{x=minX+wx+3*turretSize,y=y,z=maxZ-wz-3*turretSize}}
        else inner=nil end
    end
    local middleAdded=0
    middleBudget=math.max(0,limit-#result)
    local function middleUnit(spec,point,anchor)
        if not spec or middleAdded>=middleBudget or #result>=limit then return nil end
        local box=snapped(spec,point,spec.facing or 0)
        if not inner or not Core.fits(box,box.w,box.d,inner,true)then return nil end
        if add(box)then box.layer,box.fill,box.anchor="MIDDLE",true,anchor;middleAdded=middleAdded+1;return box end
    end
    if inner then
        local spacing=math.max(middleSpacing,wallSize+grid,turretSize+grid)
        local startX=center.x-math.floor((center.x-minX)/spacing)*spacing
        local startZ=center.z-math.floor((center.z-minZ)/spacing)*spacing
        local anchors={}
        for x=startX,maxX,spacing do for z=startZ,maxZ,spacing do
            if Core.inside({x=x,z=z},inner)then anchors[#anchors+1]={x=x,z=z}end
        end end
        table.sort(anchors,function(a,b)return(a.x-center.x)^2+(a.z-center.z)^2<(b.x-center.x)^2+(b.z-center.z)^2 end)
        for index,anchor in ipairs(anchors)do
            if middleAdded>=middleBudget or #result>=limit then break end
            local primary=roles.wall[1]or roles.turret[(index-1)%math.max(1,#roles.turret)+1]
            local box=middleUnit(primary,anchor,index)
            if box and #roles.turret>0 then
                local gun=roles.turret[(index-1)%#roles.turret+1]
                -- A nearby shooter covers each middle barricade. Keep the
                -- native footprints separate and retain routes between groups.
                local gx,gz=gun.w*(gun.grid or 1),gun.d*(gun.grid or 1)
                for _,offset in ipairs({{(box.w+gx)/2+grid,0},{-(box.w+gx)/2-grid,0},{0,(box.d+gz)/2+grid},{0,-(box.d+gz)/2-grid}})do
                    if middleUnit(gun,{x=box.x+offset[1],z=box.z+offset[2]},index)then break end
                end
            end
            if roles.trap[1]and box then
                middleUnit(roles.trap[1],{x=box.x,z=box.z+box.d/2+roles.trap[1].d*(roles.trap[1].grid or 1)/2+grid},index)
            end
        end
    end
    local placed={};for _,box in ipairs(used)do if box~=reserve then placed[#placed+1]=box end end
    if reserve and reserve.layer then placed[#placed+1]=reserve end
    local coverage={layers=layers,fitted=fitted,middle=middleAdded,spacing=middleSpacing,floor=Core.areaCoverage(poly,placed)}
    local incomplete=0
    for _,row in ipairs(layers)do if row.unfit or not row.coverage or row.coverage.uncovered>.001 then incomplete=incomplete+1 end end
    coverage.incomplete=incomplete
    local reason="1 BARRICADE + 3 TURRET ROWS · MIDDLE SPACING "..middleSpacing
    if wallSize==0 then reason="NO BLOCKING BARRICADE IN SELECTION · "..reason end
    if fitted<3 then reason=reason.." · AREA FITS "..fitted.."/3 TURRET ROWS" end
    if incomplete>0 then reason=reason.." · "..incomplete.." ROWS HAVE GAPS / LIMITS" end
    return result,reason,reserve,coverage
end

-- Runtime placements must stay clear of the drawn boundary, including their
-- entire server-snapped footprint. The raw planner remains usable for geometry tests.
function Core.placementBox(slot, x, z)
    local grid = slot.spec and slot.spec.grid or 1
    local w, d = slot.w/grid, slot.d/grid
    return {x=(math.floor(x/grid-w/2+.5)+w/2)*grid,
        z=(math.floor(z/grid-d/2+.5)+d/2)*grid,w=slot.w,d=slot.d}
end
function Core.strictFits(box, poly)
    return Core.fits(box, box.w+.1, box.d+.1, poly, false)
end
function Core.planInside(poly, specs, limit, existing, yieldWork, middleSpacing)
    if not Core.validPolygon(poly) then return {}, "SELECT A VALID AREA" end
    local inset = Core.insetPolygon(poly, 1)
    if not inset or not Core.validPolygon(inset) then return {}, "NO DEFENSE FITS INSIDE THE BORDER GAP" end
    local minX,maxX,minZ,maxZ,grid=math.huge,-math.huge,math.huge,-math.huge,1
    for _,p in ipairs(inset)do minX,maxX,minZ,maxZ=math.min(minX,p.x),math.max(maxX,p.x),math.min(minZ,p.z),math.max(maxZ,p.z)end
    for _,spec in ipairs(specs)do grid=math.max(grid,spec.grid or 1)end
    local rectangle=#inset==4
    for _,p in ipairs(inset)do
        if math.min(math.abs(p.x-minX),math.abs(p.x-maxX))>.0001
            or math.min(math.abs(p.z-minZ),math.abs(p.z-maxZ))>.0001 then rectangle=false end
    end
    if rectangle then
        minX,maxX,minZ,maxZ=math.ceil(minX/grid)*grid,math.floor(maxX/grid)*grid,math.ceil(minZ/grid)*grid,math.floor(maxZ/grid)*grid
        inset={{x=minX,y=poly[1].y,z=minZ},{x=maxX,y=poly[1].y,z=minZ},{x=maxX,y=poly[1].y,z=maxZ},{x=minX,y=poly[1].y,z=maxZ}}
        if not Core.validPolygon(inset) then return {}, "NO DEFENSE FITS INSIDE THE BORDER GAP" end
    end
    local plan,reason,reserve,coverage=Core.plan(inset,specs,limit,existing,yieldWork,middleSpacing)
    local safe={}
    for _,slot in ipairs(plan)do if Core.strictFits(slot,poly)then safe[#safe+1]=slot end end
    return safe,"INSIDE ONLY · 1 STUD BORDER GAP · "..reason,reserve,coverage
end

function Core.teleportClearance(point, mobs, horizon)
    local clearance, margin = math.huge, math.huge
    for _, mob in ipairs(mobs) do
        local from={x=mob.x,z=mob.z}
        local to={x=mob.x+(mob.vx or 0)*horizon,z=mob.z+(mob.vz or 0)*horizon}
        if not point.y or not mob.point or math.abs(point.y-mob.point.Y) <= math.max(8,(mob.range or 3)+4) then
            local distance=Core.edgeDistance(point,from,to)
            clearance=math.min(clearance,distance)
            margin=math.min(margin,distance-math.max(0,mob.range or 3)-3)
        end
    end
    return clearance,margin
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
    diagnostic = Diagnostics.new("ZombieRushSurvival", storage)
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
    local cfg = {version = 1, layoutVersion = 2, enabled = true, autoSkip = false, buyClasses = {}, upgradeClasses = {},
        buyWeapons = {}, upgradeWeapons = {}, loadout = {}, autoLoadout = false,
        health = false, gun = false, melee = false, autoPlace = false, defenseTypes = {},
        regions = {}, showBoundary = false, middleSpacing = 12, reserveCash = 0, fight = false, fly = false, turretLeash = 20,
        headAim = true, bossFirst = true, dodgeTeleport = true, dodgeClearance = 35, dodgeInterval = 0.3, clearance = 14, moveMode = "Smooth", placeSpawnArea = false, fireInput = "Mobile", flyHeight = 14, orbitRadius = 16, flySpeed = 32}
    local file = storage.path("EXIS_ZombieRushSurvival_" .. player.UserId .. ".json")
    if type(readfile) == "function" then
        local ok, data = pcall(function() if storage.exists(file) then return Http:JSONDecode(storage.read(file)) end end)
        if ok and type(data) == "table" and data.version == 1 then
            for key, value in pairs(data) do if type(value) == type(cfg[key]) then cfg[key] = value end end
            cfg.layoutVersion=2
        end
    end
    -- Migrate old hover saves: combat now uses grounded dodging.
    cfg.maxDefenses = nil -- Ignore legacy per-player limits, including saved values.
    cfg.fly, cfg.moveMode, cfg.placeSpawnArea = false, "Ground", false
    for key, limits in pairs({dodgeClearance = {3,40}, dodgeInterval = {.12,1}, turretLeash = {8, 60}, middleSpacing = {6,40}, reserveCash = {0, 1e12}, flyHeight = {5, 50},
        orbitRadius = {6, 90}, flySpeed = {8, 100}, clearance = {8, 60}}) do
        local value = cfg[key]
        cfg[key] = Core.finite(value) and math.clamp(value, limits[1], limits[2]) or limits[1]
    end
    function app.save()
        if type(writefile) == "function" then
            local ok, err = pcall(function() storage.write(file, Http:JSONEncode(cfg)) end)
            if not ok then app.notes.config = "CONFIG SAVE FAILED: " .. tostring(err)
                if diagnostic then diagnostic:record("config", app.notes.config, "ERROR") end end
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
        local connection = signal:Connect(function(...)
            local args=table.pack(...)
            local ok,err=xpcall(function() callback(table.unpack(args,1,args.n)) end,Diagnostics.traceback)
            if not ok and diagnostic then diagnostic:record("callback",err,"ERROR") end
        end)
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
        if diagnostic then diagnostic:record("module "..name,result,"ERROR") end
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
        if diagnostic then diagnostic:record(key, value) end
    end
    function app.invoke(key, remote, ...)
        if not app.alive or (not cfg.enabled and key ~= "skip") then return nil end
        if not remote or not remote:IsA("RemoteFunction") then
            app.note(key, "UNAVAILABLE: native RemoteFunction is missing") return nil
        end
        if os.clock() < (app.next[key] or 0) then return nil end
        app.next[key] = os.clock() + 1
        if diagnostic then diagnostic:record(key,"REQUEST STARTED","INFO",true) end
        local ok, result = pcall(remote.InvokeServer, remote, ...)
        if not app.alive then return nil end
        if not ok then
            app.next[key] = os.clock() + 5
            app.note(key, "ERROR: " .. tostring(result))
            return nil
        end
        if type(result) == "table" and result.ok == false then
            app.next[key] = os.clock() + (result.reason == "funds" and 3 or 5)
            app.note(key, "REJECTED: " .. tostring(result.reason or "UNKNOWN"))
        else app.note(key, "RESPONSE RECEIVED: " .. (diagnostic and Diagnostics.describe(result) or tostring(result))) end
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
        local poly = app.region().points or {}
        local folder = workspace:FindFirstChild("Deployables")
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            local name = model:GetAttribute("TypeName")
            local info = name and defs.Types[name]
            if model:GetAttribute("OwnerUserId") == player.UserId and model:GetAttribute("Destroyed") ~= true
                and (model:GetAttribute("Health") or 1) > 0 and info and Core.role(name, info) == "turret"
                and model.PrimaryPart and Core.inside({x=model.PrimaryPart.Position.X,z=model.PrimaryPart.Position.Z},poly) then return true end
        end
        for _, pending in pairs(app.pendingPlacements or {}) do
            if os.clock() < pending.expires and pending.slot.role == "turret" and Core.inside(pending.slot,poly) then return true end
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
                if not first.affordable or first.inRange == false then
                    first = app.getPlacement()
                    if not first then app.note("economy", "WAITING FOR DEFENSE FUNDS / SPACE") app.buildGoal = nil end
                end
                if first then
                    app.placementTask = first
                    local result = app.placeTick()
                    if result ~= nil then app.placementTask = nil end
                    return
                end
            end
        end
        if app.placementTask and not boss then
            local result = app.placeTick()
            if result == nil then return end -- Keep a moving placement until it completes.
            if app.matchMix and app.placementKey then Core.finishChoice(app.matchMix, app.placementKey) end
            app.placementTask, app.placementKey = nil, nil
        end
        if cfg.autoPlace and not boss then
            local candidate = app.getPlacement()
            if candidate then
                app.placementTask = candidate
                local result = app.placeTick()
                if result ~= nil then app.placementTask = nil end
                return
            end
        end
        app.buildGoal = nil
        app.upgradeTick()
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
    function app.stepMapLayer(direction)
        local state = app.mapView
        if not state or state.loading then return false end
        local best, distance
        for _, part in ipairs(state.parts) do
            if part.Parent and part.Transparency < 1 and part.CFrame.UpVector.Y >= 0.65 then
                local top = part.CFrame:PointToWorldSpace(Vector3.new(0, part.Size.Y / 2, 0)).Y
                local delta = (top - state.layer) * direction
                if delta > 0.5 and (not distance or delta < distance) then best, distance = top, delta end
            end
        end
        return best ~= nil and app.mapLayer(best) or false
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
            if not app.mapLayer(state.layer) then
                -- Saved hover height is not a floor. Recover the closest visible
                -- upward surface rather than leaving every map tap unselectable.
                local nearest, distance
                for _, part in ipairs(state.parts) do
                    if part.Parent and part.Transparency < 1 and part.CFrame.UpVector.Y >= 0.65 then
                        local top = part.CFrame:PointToWorldSpace(Vector3.new(0, part.Size.Y / 2, 0))
                        local delta = math.abs(top.Y - state.layer)
                        if not distance or delta < distance then nearest, distance = top.Y, delta end
                    end
                end
                if not nearest or not app.mapLayer(nearest) then app.editorMessage = "NO SELECTABLE FLOOR; TRY ANOTHER LAYER" end
            end
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
        params.RespectCanCollide = false -- Replica parts are non-colliding but queryable.
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
        if #nav.hull >= 3 and Core.inside({x = point.X, z = point.Z}, nav.hull) then return true end
        if cfg.autoPlace and app.buildGoal then
            local poly = app.placementRegion().points or {}
            return Core.validPolygon(poly) and Core.inside({x=point.X,z=point.Z}, poly)
                and math.abs(point.Y - app.buildGoal.Y) <= 5
        end
        return false
    end
    function app.travelHit(origin, direction)
        if direction.Magnitude < 0.01 then return nil end
        local root = app.root()
        if not root then return true end
        local params = RaycastParams.new()
        local filters = {}
        for _, folder in ipairs(app.navigation().filters) do filters[#filters + 1] = folder end
        local defenses = workspace:FindFirstChild("Deployables")
        if defenses then filters[#filters + 1] = defenses end
        params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Include, filters
        params.RespectCanCollide, params.CollisionGroup = true, root.CollisionGroup
        -- Sweep a character-sized volume, not just a ray through its center.
        return workspace:Blockcast(CFrame.new(origin), Vector3.new(3, 4, 3), direction, params)
    end
    function app.groundRoute(a, b)
        local cached = app.groundRouteCache
        if cached and os.clock() < cached.untilTime and (cached.a - a).Magnitude < 1
            and (cached.b - b).Magnitude < 1 then return cached.ok end
        local root, human = app.root()
        if not root then return false end
        local delta, lift = b - a, human.HipHeight + root.Size.Y / 2
        local steps = math.ceil(delta.Magnitude / 4)
        local ok = steps <= 32
        if ok then
            for i = 0, math.max(1, steps) do
                local point = a + delta * (i / math.max(1, steps))
                local hit = app.raycast(point + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), app.mapFilters())
                if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.65
                    or math.abs(hit.Position.Y - (point.Y - lift)) > 3.5 then ok = false break end
            end
        end
        app.groundRouteCache = {a = a, b = b, ok = ok, untilTime = os.clock() + 0.2}
        return ok
    end
    function app.placementRegion()
        -- The saved map-part selection is the only placement region. Legacy
        -- spawn-area options must never silently override the user's boundary.
        return app.region()
    end
    function app.routeHop(goal)
        local root = app.root()
        if not root or not app.inPlayableMap(goal) then return nil end
        if app.airRoute(root.Position, goal) and app.groundRoute(root.Position, goal)
            and not app.travelHit(root.Position, goal - root.Position) then return goal end
        local cached = app.routeCache
        if cached and os.clock() < cached.untilTime and (cached.goal - goal).Magnitude < 1
            and (cached.from - root.Position).Magnitude < 3 then
            if not cached.hop then return nil end
            if app.airRoute(root.Position, cached.hop) and app.groundRoute(root.Position, cached.hop)
                and not app.travelHit(root.Position, cached.hop - root.Position) then return cached.hop end
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
                    and app.airRoute(hop, goal) and app.groundRoute(root.Position, hop) and app.groundRoute(hop, goal)
                    and not app.travelHit(root.Position, hop - root.Position)
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
    function app.syncBoundary(force)
        local key = app.mapId .. ":" .. app.revision .. ":" .. tostring(cfg.showBoundary) .. ":" .. tostring(app.editing)
        if not force and key == app.boundaryKey then return end
        app.boundaryKey = key
        if cfg.showBoundary and not app.editing and app.mode == "MATCH" then app.drawRegion(app.region().points or {},true)
        else app.clearMarkers() end
    end
    function app.specs()
        local result = {}
        if not app.className then return result end
        local region = app.placementRegion()
        local poly = region.points or {}
        for _, name in ipairs(classes.GetDeployableSlots(app.className)) do
            local info = defs.Types[name]
            if info and cfg.defenseTypes[name] ~= false and not (info.Placement and info.Placement.Ability) then
                local templates = RS:FindFirstChild("Deployables")
                local template = templates and templates:FindFirstChild(defs.GetTemplateName(name, info))
                local primary = template and utils.GetRootPrimaryPart(template)
                if primary then
                    local w, d = utils.GetFootprint(primary)
                    local facing = 0
                    local level = tonumber(app.value(app.data("Classes", "DeployableLevels", name), 1)) or 1
                    local effective = deployUpgrades.ApplyLevelToTypeInfo(name, info, level)
                    result[#result + 1] = {name = name, role = Core.role(name, info), w = w, d = d,
                        grid = defs.GetNumber(info, "Placement", "GridSize", 1), facing = facing,
                        canRotate = placement.FacesCharacter(info),
                        blocking = defs.GetBoolean(info,"Physics","ZombieBlocking",false) or defs.GetBoolean(info,"FakeWall","Enabled",false),
                        info = info, primary = primary, range = placement.GetFunctionalRange(effective),
                        maxElevation = defs.GetNumber(info,"Placement","MaxElevationDifference",5)}
                else app.note("layout", "MISSING DEFENSE TEMPLATE: " .. name) end
            end
        end
        return result
    end
    function app.layout()
        local boxes = app.defenseBoxes()
        local signatures = {}
        for _, box in ipairs(boxes) do
            signatures[#signatures+1] = table.concat({box.name or "?",box.x,box.z,box.w,box.d},":")
        end
        for _, row in pairs(app.pendingPlacements or {}) do
            if os.clock() < row.expires then
                local found = false
                for _, box in ipairs(boxes) do if Core.overlap(row.slot,box,0) then found = true break end end
                if not found then boxes = {table.unpack(boxes)};boxes[#boxes+1] = row.slot end
                signatures[#signatures+1] = "pending:"..row.slot.name..":"..row.slot.x..":"..row.slot.z
            end
        end
        table.sort(signatures)
        local selected = {}
        for name, enabled in pairs(cfg.defenseTypes or {}) do selected[#selected+1] = name .. ":" .. tostring(enabled) end
        table.sort(selected)
        -- Templates may arrive after map/class data. Include the resolved specs
        -- so a temporarily empty layout does not stay cached for the whole run.
        local specs, specKeys = app.specs(), {}
        for _, spec in ipairs(specs) do
            specKeys[#specKeys+1] = table.concat({spec.name,spec.w,spec.d,spec.grid or 1,spec.range or 0}, ":")
        end
        local shape = tostring(cfg.middleSpacing) .. ":" .. table.concat(selected, ",") .. ":" .. table.concat(specKeys, ",")
        local key = app.mapId .. ":" .. tostring(app.className) .. ":" .. app.revision .. ":" .. shape .. ":" .. table.concat(signatures,";")
        if key == app.planKey then return app.plan or {} end
        local map, class, revision = app.mapId, app.className, app.revision
        local poly = app.placementRegion().points or {}
        local blueprintKey = map .. ":" .. tostring(class) .. ":" .. revision .. ":" .. shape
        if app.blueprintKey ~= blueprintKey then
            local plan, reason, reserve, coverage = Core.planInside(poly, specs, nil, {}, function()
                task.wait()
                if not app.alive or app.mapId ~= map or app.className ~= class or app.revision ~= revision then error("LAYOUT CHANGED; REPLANNING") end
            end, cfg.middleSpacing)
            if app.mapId ~= map or app.className ~= class or app.revision ~= revision then return {} end
            app.blueprintKey, app.blueprint, app.blueprintReason = blueprintKey, plan, reason
            app.reserve, app.planCoverage = reserve, coverage
        end
        local plan = {}
        for _, slot in ipairs(app.blueprint or {}) do
            local occupied = false
            for _, box in ipairs(boxes) do if Core.overlap(slot, box, 0) then occupied = true break end end
            if not occupied then plan[#plan+1] = slot end
        end
        if app.mapId ~= map or app.className ~= class or app.revision ~= revision then return {} end
        app.plan, app.planKey = plan, key
        if #plan==0 then
            if #specs==0 then app.note("layout","NO DEFENSE TYPES READY: check selected class, enabled defense types and loaded templates")
            elseif #(app.blueprint or {})==0 then app.note("layout","NO INTERIOR SLOTS: "..tostring(app.blueprintReason))
            else app.note("layout","AREA FULL; WAITING FOR FREE PLANNED SPACE") end
        else app.note("layout",app.blueprintReason .. " · " .. #plan .. " FREE SLOTS") end
        return plan
    end
    function app.coverageStatus()
        local poly = app.region().points or {}
        if not Core.validPolygon(poly) then return "SELECT A MAP PART FIRST" end
        local boxes, confirmed = app.defenseBoxes(), {}
        for _, box in ipairs(boxes) do confirmed[#confirmed+1] = box end
        local count=0
        for _,box in ipairs(confirmed)do if Core.inside(box,poly)then count=count+1 end end
        local text="BUILT "..count.." DEFENSES · OUTER BARRICADE + 3 TURRET ROWS · MIDDLE "..cfg.middleSpacing.." STUDS"
        local plan=app.planCoverage
        if plan and plan.fitted<3 then text=text.." · ONLY "..plan.fitted.."/3 ROWS FIT" end
        if plan and plan.incomplete>0 then text=text.." · PLAN: "..plan.incomplete.." ROWS HAVE GAPS / LIMITS" end
        return text
    end
    function app.defenseBoxes()
        if app.defenseCache and os.clock() < app.defenseCache.untilTime then return app.defenseCache.boxes end
        local folder, boxes = workspace:FindFirstChild("Deployables"), {}
        local poly, floorY = app.placementRegion().points or {}, 0
        for _, p in ipairs(poly) do floorY = floorY + p.y / #poly end
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            if model:IsA("Model") and model:GetAttribute("Destroyed") ~= true and (model:GetAttribute("Health") or 1)>0 then
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
                    local name = model:GetAttribute("TypeName")
                    local info = name and defs.Types[name]
                    box.name, box.role, box.owned = name, info and Core.role(name,info) or "unknown", model:GetAttribute("OwnerUserId") == player.UserId
                    box.blocking = info and (defs.GetBoolean(info,"Physics","ZombieBlocking",false) or defs.GetBoolean(info,"FakeWall","Enabled",false)) or false
                    boxes[#boxes + 1] = box
                end
            end
        end
        app.defenseCache = {boxes = boxes, untilTime = os.clock() + 0.1}
        return boxes
    end
    function app.occupied(slot)
        for _, box in ipairs(app.defenseBoxes()) do if Core.overlap(slot, box, 0) then return true end end
        for _, pending in pairs(app.pendingPlacements or {}) do
            if os.clock() < pending.expires and Core.overlap(slot, pending.slot, 0) then return true end
        end
        return false
    end
    function app.placementSafe(point)
        local _, margin = Core.teleportClearance({x=point.X,y=point.Y,z=point.Z}, app.enemyRows(), .3)
        return margin >= 2
    end
    function app.getPlacement(preferred, allowUnfunded)
        if os.clock() < (app.next.place or 0) then
            app.placementReadiness="WAITING: native placement request retry cooldown" return nil
        end
        if app.mode ~= "MATCH" or not cfg.autoPlace or app.editing or app.mapId == "Unknown" or not app.className then
            app.placementReadiness = app.mode~="MATCH" and "WAITING: enter a match"
                or not cfg.autoPlace and "OFF: AUTO PLACE CURRENT CLASS is disabled"
                or app.editing and "PAUSED: close / connect the area editor"
                or app.mapId=="Unknown" and "WAITING: map not detected" or "WAITING: class not detected"
            return nil
        end
        local client = app.module(app.find(player, "PlayerScripts", "Client"), "DeployableSystem")
        if not client then app.note("defense", "WAITING FOR NATIVE DEPLOYABLE MODULE") return nil end
        local choices,root = {},app.root()
        for _,slot in ipairs(app.layout())do
            local key=app.mapId..":"..app.revision..":"..slot.name..":"..slot.x..":"..slot.z..":"..slot.facing
            if(not preferred or slot.name==preferred or slot.role==preferred)and os.clock()>=(app.rejected[key]or 0)then
                local priority=slot.layer=="BARRICADE"and 1 or slot.layer=="TURRET 1"and 2
                    or slot.layer=="TURRET 2"and 3 or slot.layer=="TURRET 3"and 4 or slot.role=="support"and 5 or 6
                local distance=root and(slot.x-root.Position.X)^2+(slot.z-root.Position.Z)^2 or 0
                local spec = slot.spec or {}
                local reach = placement.GetPlacementDistances(spec.info or {},spec.grid or 1)
                local height = root and math.abs(root.Position.Y-slot.y) or math.huge
                local inRange = root ~= nil and distance+height*height <= reach*reach and height <= (spec.maxElevation or 5)
                choices[#choices+1]={slot=slot,key=key,priority=priority,distance=distance,inRange=inRange}
            end
        end
        table.sort(choices,function(a,b)
            if a.inRange ~= b.inRange then return a.inRange end
            if a.priority~=b.priority then return a.priority<b.priority end
            if a.distance~=b.distance then return a.distance<b.distance end
            return a.key<b.key
        end)
        local prices, funded={},0
        -- A large layered layout must not perform hundreds of floor/risk
        -- queries per class type on every worker tick.
        local checked = 0
        local map, class, revision = app.mapId, app.className, app.revision
        for index=1,#choices do
            local row=choices[index];local slot=row.slot
            if not app.occupied(slot)then
                local price=prices[slot.name]
                if not price then local currency,cost=client.GetCurrentPrice(slot.name);price={currency,cost};prices[slot.name]=price end
                local affordable=app.afford(price[1],price[2])
                if affordable then funded=funded+1 end
                if affordable or allowUnfunded then
                    checked = checked + 1
                    if checked % 32 == 0 then
                        task.wait()
                        if not app.active() or app.editing or app.mapId ~= map or app.className ~= class or app.revision ~= revision then return nil end
                    end
                    local hit=app.ground(slot.x,slot.z,slot.y)
                    if hit then
                        -- A defense can be deployed ahead of the player, including
                        -- near enemies. Only the player's firing/approach position
                        -- needs attack clearance, not the defense's destination.
                        app.placementReadiness = (affordable and "READY " or "WAITING FOR CASH ")..slot.name.." | PRICE "..tostring(price[2]).." "..tostring(price[1])
                            .." | "..(row.inRange and "IN RANGE" or "NEEDS SAFE APPROACH")
                        return{key=row.key,slot=slot,point=hit.Position,class=app.className,map=app.mapId,
                            revision=app.revision,affordable=affordable,inRange=row.inRange}
                    end
                    app.rejected[row.key]=os.clock()+8
                    app.placementReadiness = "WAITING: selected floor has no valid support at "..slot.x..","..slot.z
                    if diagnostic then diagnostic:record("placement probe",slot.name.." @ "..slot.x..","..slot.z..": "..
                        "WAITING: selected floor has no valid support here","WAIT") end
                end
            else app.rejected[row.key]=os.clock()+.2 end
        end
        if #choices>0 and funded==0 and not allowUnfunded then
            app.placementReadiness = "WAITING FOR CASH: no selected defense is affordable (reserve "..tostring(cfg.reserveCash or 0)..")"
            app.note("defense",app.placementReadiness)
        elseif #choices==0 then
            app.placementReadiness = "WAITING: no free eligible slot; "..tostring(app.notes and app.notes.layout or "check saved area / selected defense types / retry timers")
        end
        return nil
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
        if not app.placementSafe(root.Position) then
            app.buildGoal = nil app.note("defense", "WAITING FOR SAFE PLACEMENT OPENING") return false
        end
        local spec = candidate.slot.spec
        local maxDistance = placement.GetPlacementDistances(spec.info, spec.grid or 1)
        local inRange = (root.Position - candidate.point).Magnitude <= maxDistance
            and math.abs(root.Position.Y-candidate.point.Y) <= (spec.maxElevation or 5)
        -- The native range is to the requested surface point. Do not force a
        -- move to an arbitrary side/height when we can already place safely.
        local lift = human.HipHeight + root.Size.Y / 2
        local outward = Vector3.new(root.Position.X - candidate.point.X, 0, root.Position.Z - candidate.point.Z)
        if outward.Magnitude < 0.1 then outward = Vector3.new(1, 0, 0) end
        local side = candidate.point + outward.Unit * math.min(8, math.max(candidate.slot.w, candidate.slot.d) / 2 + 3)
        local sideHit = app.ground(side.X, side.Z, candidate.point.Y)
        local stand = (sideHit and sideHit.Position or candidate.point) + Vector3.new(0, lift, 0)
        if not inRange and (not sideHit or not app.placementSafe(stand)) then
            local safe, best
            -- Stay out of reach while placing up to the native distance ahead.
            -- Tight floors can use a closer ring when the outer ring has no support.
            for _,radius in ipairs({math.max(3,maxDistance-3),6}) do
                for i = 0, 15 do
                    local angle = i * math.pi / 8
                    local probe = candidate.point + Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
                    local floor = app.ground(probe.X,probe.Z,candidate.point.Y)
                    if floor then
                        local position = floor.Position+Vector3.new(0,lift,0)
                        local distance = (position-root.Position).Magnitude
                        if (position-candidate.point).Magnitude<=maxDistance and app.placementSafe(position)
                            and (not best or distance<best) then safe,best=position,distance end
                    end
                end
            end
            if not safe then
                app.buildGoal=nil app.placementReadiness="WAITING: no safe supported approach within native placement range"
                app.note("defense",app.placementReadiness) return false
            end
            stand = safe
        end
        if not inRange then
            app.buildGoal = stand
            app.note("defense", "MOVING INTO PLACEMENT RANGE")
            return nil
        end
        app.buildGoal = nil
        -- Re-check after movement; selection, class, occupancy and cash can change.
        if candidate.class ~= app.className or candidate.map ~= app.mapId or candidate.revision ~= app.revision
            or not cfg.autoPlace or not app.active() or app.occupied(candidate.slot) then return false end
        local region = app.placementRegion()
        local snapped = Core.placementBox(candidate.slot, candidate.point.X, candidate.point.Z)
        if not Core.strictFits(snapped, region.points or {}) then
            app.note("defense", "REJECTED: complete defense footprint must stay inside the selected border")
            return false
        end
        local client = app.module(app.find(player, "PlayerScripts", "Client"), "DeployableSystem")
        if not client then return false end
        local currency, price = client.GetCurrentPrice(candidate.slot.name)
        if not app.afford(currency, price) then return false end
        app.stopWalk()
        app.placing = true
        local result = app.invoke("place", app.find(RS, "DeployableSystem_Remotes", "Place"),
            candidate.slot.name, candidate.point, {Facing = candidate.slot.facing or spec.facing})
        app.placing = false
        if type(result) == "table" and result.ok == true then
            app.pendingPlacements = app.pendingPlacements or {}
            app.pendingPlacements[candidate.key] = {slot = candidate.slot, expires = os.clock() + 5}
            app.next.place = os.clock()
            app.defenseCache = nil
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
    function app.move(goal, dt)
        app.stopFlight()
        local root, human = app.root()
        if not root or not goal then app.stopWalk() return end
        local hop = app.routeHop(goal)
        if not hop then
            app.routeBlockedSince = app.routeBlockedSince or os.clock()
            if app.placementTask and os.clock() - app.routeBlockedSince >= 1 then
                app.rejected[app.placementTask.key] = os.clock() + 8
                if app.matchMix and app.placementKey then Core.finishChoice(app.matchMix, app.placementKey) end
                app.placementTask, app.placementKey, app.buildGoal = nil, nil, nil
            end
            human:MoveTo(root.Position)
            app.walkGoal = nil
            app.airGoal = nil
            return
        end
        app.routeBlockedSince = nil
        -- Preserve native gravity, collisions and WalkSpeed. Revalidate routes
        -- every tick but avoid spamming the same Humanoid movement command.
        if not app.walkGoal or (app.walkGoal - hop).Magnitude > 1
            or os.clock() >= (app.next.walk or 0) then
            app.walkGoal, app.next.walk = hop, os.clock() + 0.2
            human:MoveTo(hop)
        end
    end
    function app.stopWalk()
        local root, human = app.root()
        if app.walkGoal and root and human then human:MoveTo(root.Position) end
        app.walkGoal, app.groundRouteCache = nil, nil
    end
    function app.enemyRows()
        if app.enemyCache and os.clock() < app.enemyCache.untilTime then return app.enemyCache.rows end
        local folder, rows = workspace:FindFirstChild("Zombie_ClientVisuals"), {}
        local types = app.module(shared:FindFirstChild("Zombies"), "ZombieTypes")
        app.enemyMotion=app.enemyMotion or setmetatable({},{__mode="k"})
        local now=os.clock()
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            if model:IsA("Model") and model:GetAttribute("ZombieId") ~= nil then
                local point = app.head(model)
                local human = model:FindFirstChildOfClass("Humanoid")
                if point and (not human or human.Health > 0) then
                    local info = types and types.GetById(model:GetAttribute("ZombieTypeId"))
                    local previous=app.enemyMotion[model]
                    local vx,vz=0,0
                    if previous and now-previous.at>.01 then
                        vx,vz=(point.X-previous.x)/(now-previous.at),(point.Z-previous.z)/(now-previous.at)
                        local speed=math.sqrt(vx*vx+vz*vz)
                        local maximum=math.max(32,(info and tonumber(info.speed)or 16)*2)
                        if speed>maximum then vx,vz=vx/speed*maximum,vz/speed*maximum end
                    end
                    app.enemyMotion[model]={x=point.X,z=point.Z,at=now}
                    rows[#rows + 1] = {model = model, point = point, x = point.X, z = point.Z,vx=vx,vz=vz,
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
        return base
    end
    function app.turretAnchor()
        local cached = app.turretCache
        if cached and os.clock() < cached.untilTime and cached.model.Parent
            and cached.model:GetAttribute("Destroyed") ~= true
            and (cached.model:GetAttribute("Health") or 1) > 0 then return cached end
        local root = app.root()
        if not root then return end
        local folder, best, bestScore = workspace:FindFirstChild("Deployables"), nil, nil
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            local name = model:GetAttribute("TypeName")
            local info, primary = name and defs.Types[name], model.PrimaryPart
            if model:IsA("Model") and model:GetAttribute("OwnerUserId") and primary and info
                and Core.role(name, info) == "turret" and model:GetAttribute("Destroyed") ~= true
                and (model:GetAttribute("Health") or 1) > 0
                and math.abs(primary.Position.Y - root.Position.Y) < 12 then
                local distance = (primary.Position - root.Position).Magnitude
                local score = distance + (model:GetAttribute("OwnerUserId") == player.UserId and 0 or 12)
                if not bestScore or score < bestScore then
                    bestScore = score
                    best = {model = model, point = primary.Position,
                        radius = math.max(6, math.min(cfg.turretLeash or 20, (info.Targeting and info.Targeting.Range or 30) - 3)),
                        untilTime = os.clock() + 0.5}
                end
            end
        end
        app.turretCache = best
        return best
    end
    function app.safeAirGoal(target)
        local root = app.root()
        if not root then return nil end
        local turret = app.turretAnchor()
        local anchor = turret and turret.point or root.Position
        local initialRisk = app.airRisk(root.Position)
        local unsafe = initialRisk > 0 or os.clock() < (app.damageEvadeUntil or 0)
        if not turret and not unsafe then return root.Position end
        -- Already safely covered by a turret: hold position and keep shooting.
        local toAnchor = Vector3.new(root.Position.X - anchor.X, 0, root.Position.Z - anchor.Z).Magnitude
        if turret and not unsafe and toAnchor <= turret.radius and toAnchor >= 5 then return root.Position end
        local candidates = {}
        local angle = os.clock() * 0.2 * (app.orbitDirection or 1)
        local radii = turret and {6, math.max(8, turret.radius * 0.6), turret.radius} or {8, 14, 22}
        for _, distance in ipairs(radii) do
            for i = 0, 15 do
                local a = angle + i * math.pi / 8
                local point = anchor + Vector3.new(math.cos(a) * distance, 0, math.sin(a) * distance)
                local risk = app.airRisk(point)
                local cost = (point - root.Position).Magnitude
                if risk == 0 or initialRisk > 0 and risk < initialRisk then
                    if unsafe and cost < 6 then cost = cost + 50 end
                    candidates[#candidates + 1] = {point = point, score = risk * 1000 + cost + distance * 0.2}
                end
            end
        end
        -- Safety can temporarily take us outside turret coverage. Never walk
        -- through a swarm just to remain close to a turret.
        if unsafe then
            for i = 0, 15 do
                local a = angle + i * math.pi / 8
                local point = root.Position + Vector3.new(math.cos(a) * 10, 0, math.sin(a) * 10)
                local risk = app.airRisk(point)
                if risk < initialRisk then
                    candidates[#candidates + 1] = {point = point, score = risk * 1000 + 100
                        + (point - anchor).Magnitude}
                end
            end
        end
        table.sort(candidates, function(a, b) return a.score < b.score end)
        for i = 1, math.min(12, #candidates) do
            local goal = app.flightPoint(candidates[i].point)
            if goal and app.routeHop(goal) then return goal end
        end
        app.note("movement", "NO SAFE GROUND ROUTE; HOLDING / RECHECKING")
        return nil
    end
    function app.orbitGoal(target)
        local cached, root = app.airGoal, app.root()
        if cached and root and os.clock() < cached.untilTime and app.airRisk(cached.point) == 0
            and app.airRoute(root.Position, cached.point) then return cached.point end
        local goal = app.safeAirGoal(target)
        app.airGoal = goal and {point = goal, untilTime = os.clock() + 0.2} or nil
        return goal
    end
    function app.teleportLanding(point)
        local root=app.root()
        if not root then return nil end
        local goal=app.flightPoint(point)
        if not goal then return nil end
        local filters={}
        for _,folder in ipairs(app.navigation().filters)do filters[#filters+1]=folder end
        local defenses=workspace:FindFirstChild("Deployables")
        if defenses then filters[#filters+1]=defenses end
        local params=OverlapParams.new()
        params.FilterType,params.FilterDescendantsInstances=Enum.RaycastFilterType.Include,filters
        params.RespectCanCollide,params.CollisionGroup=true,root.CollisionGroup
        for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(goal),Vector3.new(3,4,3),params))do
            if part.CanCollide then return nil end
        end
        -- Check the feet around the destination, not just a single floor ray.
        for _,offset in ipairs({{1.2,0},{-1.2,0},{0,1.2},{0,-1.2}})do
            local hit=app.raycast(goal+Vector3.new(offset[1],3,offset[2]),Vector3.new(0,-16,0),app.mapFilters())
            local _,human=app.root()
            if not human or not hit or hit.Material==Enum.Material.Water or hit.Normal.Y<.65
                or math.abs(hit.Position.Y-(goal.Y-human.HipHeight-root.Size.Y/2))>2 then return nil end
        end
        return goal
    end
    function app.teleportDodgeTick()
        if not app.active()or not cfg.fight or not cfg.dodgeTeleport then return false end
        local root,human=app.root()
        if not root or root.Anchored or human.Sit or human.PlatformStand then return false end
        local phase=human:GetState()
        if phase==Enum.HumanoidStateType.Physics or phase==Enum.HumanoidStateType.Ragdoll or phase==Enum.HumanoidStateType.Dead then return false end
        local now=os.clock()
        if now<(app.next.dodgeScan or 0)then return false end
        app.next.dodgeScan=now+.1
        local mobs=app.enemyRows()
        if #mobs==0 and not app.buildGoal then return false end
        local horizon=math.max(.15,cfg.dodgeInterval or .3)
        local _,currentMargin=Core.teleportClearance({x=root.Position.X,y=root.Position.Y,z=root.Position.Z},mobs,horizon)
        local emergency=currentMargin<2 or now<(app.damageEvadeUntil or 0)
        if app.placing and not emergency then return false end
        if now<(app.next.dodgeTeleport or 0)and not(emergency and now-(app.lastDodgeAt or -10)>=.12)then return false end
        local candidates,seen={},{}
        app.dodgeRejected=app.dodgeRejected or {}
        for key,expires in pairs(app.dodgeRejected)do if expires<=now then app.dodgeRejected[key]=nil end end
        local turret=app.turretAnchor()
        -- Hold a safe arrived approach for the worker to issue its placement.
        if app.buildGoal and (root.Position-app.buildGoal).Magnitude <= 3 and not emergency then return false end
        local function candidate(point,build)
            local dx,dz=point.X-root.Position.X,point.Z-root.Position.Z
            local distance=math.sqrt(dx*dx+dz*dz)
            if distance<(build and 3 or 10)or not app.inPlayableMap(point)then return end
            local key=math.floor(point.X/2)..":"..math.floor(point.Z/2)
            if seen[key]or app.dodgeRejected[key]then return end;seen[key]=true
            local clearance,margin=Core.teleportClearance({x=point.X,y=point.Y,z=point.Z},mobs,horizon)
            if margin<2 then return end -- A smaller opening must still clear native attack reach.
            local preferred=clearance>=(cfg.dodgeClearance or 35)
            local score=(preferred and 100000 or 0)+math.min(100,margin)*100-distance*.05
            if build then score=score+200000 end
            if turret and(point-turret.point).Magnitude<=turret.radius then score=score+25 end
            for _,old in ipairs(app.dodgeHistory or {})do
                if now-old.at<3 and(point-old.point).Magnitude<16 then score=score-800 end
            end
            candidates[#candidates+1]={point=point,score=score,clearance=clearance,margin=margin,build=build,key=key}
        end
        if app.buildGoal then candidate(app.buildGoal,true)end
        if #mobs>0 then
            local angle=now*.7
            for _,radius in ipairs({12,24,40,64})do
                for n=0,15 do local a=angle+n*math.pi/8;candidate(root.Position+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius))end
            end
            local nav=app.navigation()
            local count=#nav.spawns
            for n=1,math.min(32,count)do
                local index=((n-1+math.floor(now*4))%count)+1;candidate(nav.spawns[index].point)
            end
            if #nav.hull>=3 then
                local minX,maxX,minZ,maxZ=math.huge,-math.huge,math.huge,-math.huge
                for _,p in ipairs(nav.hull)do minX,maxX,minZ,maxZ=math.min(minX,p.x),math.max(maxX,p.x),math.min(minZ,p.z),math.max(maxZ,p.z)end
                for x=1,5 do for z=1,5 do candidate(Vector3.new(minX+(maxX-minX)*x/6,root.Position.Y,minZ+(maxZ-minZ)*z/6))end end
            end
        end
        table.sort(candidates,function(a,b)return a.score>b.score end)
        for n=1,math.min(12,#candidates)do
            local choice=candidates[n]
            local landing=app.teleportLanding(choice.point)
            if not landing then app.dodgeRejected[choice.key]=now+1 end
            if landing and app.active()and cfg.fight and cfg.dodgeTeleport then
                -- Re-read both threats and character after all ground queries.
                local fresh=app.root()
                local _,margin=Core.teleportClearance({x=landing.X,y=landing.Y,z=landing.Z},app.enemyRows(),horizon)
                if fresh==root and margin>=2 and not root.Anchored then
                    human:MoveTo(root.Position)
                    root.CFrame=CFrame.new(landing)*root.CFrame.Rotation
                    root.AssemblyLinearVelocity=Vector3.new(0,0,0)
                    app.walkGoal,app.airGoal,app.groundRouteCache=nil,nil,nil
                    app.lastDodgeAt,app.next.dodgeTeleport=now,now+(cfg.dodgeInterval or .3)
                    app.dodgeHistory=app.dodgeHistory or {};app.dodgeHistory[#app.dodgeHistory+1]={point=landing,at=now}
                    if #app.dodgeHistory>8 then table.remove(app.dodgeHistory,1)end
                    app.note("movement",string.format("GROUND TP · %.1f STUD ZOMBIE CLEARANCE",choice.clearance))
                    return true
                end
            end
        end
        app.note("movement","NO VALID GROUND OPENING; RESCANNING / FIRING")
        return false
    end
    function app.combatTick(dt)
        if app.mode ~= "MATCH" or not app.active() then
            app.releaseFire() app.stopFlight() app.stopWalk() app.buildGoal = nil return
        end
        if not cfg.fight and not cfg.autoPlace then app.releaseFire() app.stopFlight() app.stopWalk() app.buildGoal = nil return end
        local target = cfg.fight and app.target or nil
        if target and not target.model.Parent then target = nil end
        local build = cfg.autoPlace and not app.editing and app.buildGoal
        local root, human = app.root()
        if human and app.observedHealth and human.Health < app.observedHealth then
            app.airGoal, app.damageEvadeUntil = nil, os.clock() + 1.2
            app.orbitDirection = -(app.orbitDirection or 1)
        end
        app.observedHealth = human and human.Health
        -- Do not leave native range while the server is processing a placement.
        -- An incoming threat can still interrupt this brief hold.
        if app.placing and root and app.placementSafe(root.Position) then return end
        local teleportMode=cfg.fight and cfg.dodgeTeleport
        if teleportMode then app.stopWalk();app.teleportDodgeTick() end
        local danger = not teleportMode and root and (app.airRisk(root.Position) > 0 or os.clock() < (app.damageEvadeUntil or 0))
        if danger and (cfg.fight or cfg.autoPlace) then
            build = nil
            app.move(app.orbitGoal(target), dt)
            app.note("movement", "DODGING ZOMBIES ON SAFE GROUND")
        end
        if target and target.boss and cfg.bossFirst then build = nil end
        if build and not teleportMode then app.releaseFire() app.move(build, dt) return end
        if not target then
            app.releaseFire()
            if not danger and not teleportMode then app.move(app.orbitGoal(nil), dt) end
            return
        end
        local tool, info = app.weapon()
        if not danger and not teleportMode then app.move(app.orbitGoal(target), dt) end
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
    ui.blue, ui.text, ui.muted = Color3.fromRGB(80, 160, 255), Color3.fromRGB(232, 238, 248), Color3.fromRGB(156, 175, 198)
    function ui.new(class, properties, parent)
        local node = Instance.new(class)
        for key, value in pairs(properties) do
            if key == "Text" and class == "TextButton" and type(value) == "string" then value = value:upper() end
            node[key] = value
        end
        node.Parent = parent
        return node
    end
    function ui.round(node, radius)
        ui.new("UICorner", {CornerRadius = UDim.new(0, radius or 7)}, node)
    end
    function ui.stroke(node, color)
        ui.new("UIStroke", {Color = color or Color3.fromRGB(32, 44, 61), Thickness = 1}, node)
    end
    function ui.stack(parent, padding)
        ui.new("UIListLayout", {Padding = UDim.new(0, padding or 4), SortOrder = Enum.SortOrder.LayoutOrder}, parent)
    end
    function ui.textLabel(parent, text, height)
        return ui.new("TextLabel", {Size = UDim2.new(1, 0, 0, height or 25), BackgroundTransparency = 1,
            Text = text, TextColor3 = ui.muted, Font = Enum.Font.BuilderSans, TextSize = 10,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left}, parent)
    end
    function ui.button(parent, text, callback)
        local button = ui.new("TextButton", {Size = UDim2.new(1, 0, 0, 25), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(23, 45, 71),
            Text = text, TextColor3 = ui.text, Font = Enum.Font.BuilderSansMedium, TextSize = 10, AutoButtonColor = true}, parent)
        ui.round(button, 6)
        app.connect(button.Activated, callback)
        return button
    end
    function ui.toggle(parent, text, object, key)
        local row = ui.new("TextButton", {Size = UDim2.new(1, 0, 0, 25), Text = "", BorderSizePixel = 0,
            BackgroundColor3 = Color3.fromRGB(21, 30, 43)}, parent)
        ui.round(row, 5)
        ui.new("TextLabel", {Position = UDim2.fromOffset(7, 0), Size = UDim2.new(1, -53, 1, 0),
            BackgroundTransparency = 1, Text = text:upper(), TextColor3 = ui.text, TextSize = 10, TextWrapped = true,
            Font = Enum.Font.BuilderSans, TextXAlignment = Enum.TextXAlignment.Left}, row)
        local track = ui.new("Frame", {Position = UDim2.new(1, -32, 0.5, -6), Size = UDim2.fromOffset(25, 12),
            BackgroundColor3 = Color3.fromRGB(47, 59, 75), BorderSizePixel = 0}, row)
        ui.round(track, 8)
        local knob = ui.new("Frame", {Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = ui.text, BorderSizePixel = 0}, track)
        ui.round(knob, 8)
        local function refresh()
            track.BackgroundColor3 = object[key] and ui.blue or Color3.fromRGB(47, 59, 75)
            knob.Position = UDim2.fromOffset(object[key] and 15 or 2, 2)
        end
        app.connect(row.Activated, function()
            object[key] = not object[key]
            if object == cfg and (key == "fight" or key == "enabled" or key == "headAim") then app.releaseFire() end
            if object == cfg and key == "showBoundary" then app.syncBoundary(true); app.save()
            else app.changed() end
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
            BackgroundColor3 = Color3.fromRGB(17, 28, 44), TextColor3 = ui.text, Font = Enum.Font.BuilderSans, TextSize = 10}, row)
        ui.round(input, 5)
        app.connect(input.FocusLost, function()
            local value = tonumber(input.Text)
            if Core.finite(value) then cfg[key] = math.clamp(value, low, high) app.changed() end
            input.Text = tostring(cfg[key])
        end)
    end
    -- Universal EXIS shell: copied from the Fuzzotopia design.
    local gui = ui.new("ScreenGui", {Name = "EXIS_ZOMBIE_RUSH", ResetOnSpawn = false,
        IgnoreGuiInset = false, DisplayOrder = 2147483647, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, pg)
    local screen = ui.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, gui)
    local frame = ui.new("Frame", {Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(392, 272),
        BackgroundColor3 = Color3.fromRGB(8, 12, 18), BorderSizePixel = 0, ClipsDescendants = true}, screen)
    ui.round(frame, 9)
    ui.stroke(frame, Color3.fromRGB(48, 76, 111))
    function app.resize()
        local view = screen.AbsoluteSize
        if view.X <= 0 or view.Y <= 0 then return end
        local w, h = math.min(app.windowWidth or 392, math.max(1, view.X - 16)), math.min(app.windowHeight or 272, math.max(1, view.Y - 16))
        frame.Size = UDim2.fromOffset(w, h)
        if not app.windowPositioned then
            frame.Position = UDim2.fromOffset((view.X - w) / 2, (view.Y - h) / 2)
            app.windowPositioned = true
        else
            frame.Position = UDim2.fromOffset(math.clamp(frame.Position.X.Offset, 0, math.max(0, view.X - w)),
                math.clamp(frame.Position.Y.Offset, 0, math.max(0, view.Y - h)))
        end
    end
    app.resize()
    local titlebar = ui.new("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(17, 22, 31),
        BorderSizePixel = 0, Active = true}, frame)
    ui.new("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(175, 209, 255), Color3.fromRGB(105, 125, 152)), Rotation = 12}, titlebar)
    ui.new("Frame", {Position = UDim2.fromOffset(7, 11), Size = UDim2.fromOffset(2, 12), BackgroundColor3 = ui.blue, BorderSizePixel = 0}, titlebar)
    local title = ui.textLabel(titlebar, "EXIScript | ZOMBIE RUSH SURVIVAL", 30)
    title.Position, title.Size, title.TextColor3, title.Font = UDim2.fromOffset(18, 0), UDim2.new(1, -75, 1, 0), ui.blue, Enum.Font.BuilderSansBold
    title.TextWrapped, title.TextTruncate, title.TextSize = false, Enum.TextTruncate.AtEnd, 11
    local icon
    local minimize = ui.button(titlebar, "−", function() frame.Visible = false icon.Visible = true end)
    minimize.Size, minimize.Position, minimize.TextSize = UDim2.fromOffset(25, 23), UDim2.new(1, -57, 0, 3), 20
    minimize.BackgroundColor3 = Color3.fromRGB(14, 19, 27)
    local close = ui.button(titlebar, "×", function() app.stop() end)
    close.Size, close.Position, close.TextSize = UDim2.fromOffset(25, 23), UDim2.new(1, -29, 0, 3), 20
    close.BackgroundColor3 = Color3.fromRGB(14, 19, 27)
    icon = ui.new("TextButton", {Name = "OpenEXIScript", Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(12, 90),
        BackgroundColor3 = Color3.fromRGB(8, 15, 25), Text = "EXIS", TextColor3 = Color3.fromRGB(240, 247, 255),
        TextSize = 10, Font = Enum.Font.BuilderSansBold, Visible = false, BorderSizePixel = 0, ZIndex = 20}, screen)
    ui.round(icon, 4) ui.stroke(icon, ui.blue)
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
                    local size = screen.AbsoluteSize
                    target.Position = UDim2.fromOffset(math.clamp(origin.X.Offset + delta.X, 0, math.max(0, size.X - target.AbsoluteSize.X)),
                        math.clamp(origin.Y.Offset + delta.Y, 0, math.max(0, size.Y - target.AbsoluteSize.Y)))
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
        else frame.Visible, icon.Visible = true, false end
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
            app.windowWidth, app.windowHeight = math.clamp(resizeSize.X + delta.X, 310, 800), math.clamp(resizeSize.Y + delta.Y, 210, 650)
            app.resize()
        end
    end)
    app.connect(UIS.InputEnded, function(input)
        if input == resizePointer or input.UserInputType == Enum.UserInputType.MouseButton1 then resizePointer = nil end
    end)
    local shellBody = ui.new("Frame", {Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1}, frame)
    local navigation = ui.new("ScrollingFrame", {Size = UDim2.new(0, 82, 1, 0), BackgroundColor3 = Color3.fromRGB(15, 19, 27),
        BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, shellBody)
    ui.new("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4)}, navigation)
    ui.stack(navigation, 3)
    local body = ui.new("Frame", {Position = UDim2.fromOffset(90, 29), Size = UDim2.new(1, -99, 1, -51), BackgroundTransparency = 1}, shellBody)
    local pageTitle = ui.textLabel(shellBody, "MAIN", 26)
    pageTitle.Position, pageTitle.Size, pageTitle.TextColor3, pageTitle.Font = UDim2.fromOffset(91, 0), UDim2.new(1, -101, 0, 26), ui.text, Enum.Font.BuilderSansBold
    pageTitle.TextSize = 12
    ui.new("Frame", {Position = UDim2.fromOffset(82, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.fromRGB(31, 43, 59), BorderSizePixel = 0}, shellBody)
    ui.new("Frame", {Position = UDim2.fromOffset(91, 25), Size = UDim2.new(1, -102, 0, 1), BackgroundColor3 = Color3.fromRGB(31, 43, 59), BorderSizePixel = 0}, shellBody)
    local footer = ui.textLabel(shellBody, "READY", 19)
    footer.Position, footer.Size = UDim2.new(0, 91, 1, -22), UDim2.new(1, -119, 0, 19)
    footer.TextTruncate, footer.TextWrapped, footer.TextSize = Enum.TextTruncate.AtEnd, false, 10
    ui.pages, ui.nav, ui.groups = {}, {}, {}
    function ui.page(name)
        local page = ui.new("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = ui.blue,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false}, body)
        ui.stack(page, 3)
        ui.pages[name] = page
        local button = ui.button(navigation, "  " .. name, function() ui.show(name) end)
        button.Size, button.TextXAlignment, button.Font = UDim2.new(1, 0, 0, 21), Enum.TextXAlignment.Left, Enum.Font.BuilderSansMedium
        ui.round(button, 7) ui.stroke(button, Color3.fromRGB(35, 56, 79))
        ui.nav[name] = button
        return page
    end
    function ui.show(name)
        if app.selectedPage == name then body.Visible = not body.Visible return end
        app.selectedPage = name
        body.Visible, pageTitle.Text = true, name:upper()
        for key, page in pairs(ui.pages) do
            page.Visible = key == name
            ui.nav[key].BackgroundColor3 = key == name and Color3.fromRGB(23, 45, 71) or Color3.fromRGB(15, 19, 27)
            ui.nav[key].TextColor3 = key == name and ui.blue or ui.text
        end
    end
function ui.group(container,name)
    local frame=ui.new("Frame",{Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundColor3=Color3.fromRGB(16,22,31),BorderSizePixel=0},container)
    ui.round(frame,6)
    local border=ui.new("UIStroke",{Color=Color3.fromRGB(32,44,61),Thickness=1},frame)
    ui.new("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,0)},frame)
    local header=ui.new("TextButton",{LayoutOrder=0,Size=UDim2.new(1,0,0,25),
        BackgroundTransparency=1,Text="",AutoButtonColor=false},frame)
    ui.new("TextLabel",{Position=UDim2.fromOffset(9,0),Size=UDim2.new(1,-35,1,0),
        BackgroundTransparency=1,Text=name:upper(),TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,TextColor3=ui.text,TextSize=10,
        Font=Enum.Font.BuilderSansMedium},header)
    local arrow=ui.new("TextLabel",{Position=UDim2.new(1,-24,0,0),Size=UDim2.fromOffset(20,25),
        BackgroundTransparency=1,Text="›",TextColor3=Color3.fromRGB(126,149,179),TextSize=17,
        Font=Enum.Font.BuilderSans},header)
    local body=ui.new("Frame",{LayoutOrder=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,Visible=false},frame)
    ui.new("UIPadding",{PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6),
        PaddingTop=UDim.new(0,2),PaddingBottom=UDim.new(0,5)},body)
    ui.new("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},body)
    local accent=ui.new("Frame",{Position=UDim2.fromOffset(0,7),Size=UDim2.fromOffset(2,11),
        BackgroundColor3=ui.blue,BackgroundTransparency=0.7,BorderSizePixel=0},header)
    local entry={frame=frame,body=body}
    function entry.setOpen(open)
        body.Visible=open
        arrow.Text=open and "⌄" or "›"
        arrow.TextColor3=open and ui.blue or Color3.fromRGB(126,149,179)
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
    app.connect(header.Activated, function()
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
    local main = ui.page("MAIN")
    local classPage = ui.page("CLASSES")
    local weaponPage = ui.page("WEAPONS")
    local upgradesPage = ui.page("UPGRADES")
    local defensePage = ui.page("DEFENSE")
    local areaPage = ui.page("AREA")
    local settings = ui.page("SETTINGS")
    ui.diagnosticsPage = ui.page("DIAGNOSTICS")
    local contextLabel = ui.textLabel(main, "DETECTING CLASS / MAP", 42)
    contextLabel.TextColor3, contextLabel.Font = ui.text, Enum.Font.BuilderSansMedium
    local fight = ui.group(main, "FIGHT MODE")
    ui.toggle(fight, "AUTO FIGHT", cfg, "fight")
    ui.toggle(fight, "HEAD AIM", cfg, "headAim")
    ui.toggle(fight, "BOSS FIRST", cfg, "bossFirst")
    ui.textLabel(fight, "Uses your equipped gun's normal fire, ammo and reload rules.", 30)
    local movement = ui.group(main, "DODGE NEAR TURRETS")
    ui.textLabel(movement, "Fight mode checks fresh ground openings and relocates by TP. Turn it off to use grounded turret dodging.", 44)
    ui.toggle(movement, "TELEPORT DODGE IN FIGHT MODE", cfg, "dodgeTeleport")
    ui.number(movement, "PREFERRED ZOMBIE CLEARANCE", "dodgeClearance", 3, 40)
    ui.number(movement, "TP INTERVAL (SECONDS)", "dodgeInterval", .12, 1)
    ui.number(movement, "TURRET DISTANCE", "turretLeash", 8, 60)
    ui.number(movement, "ZOMBIE CLEARANCE", "clearance", 8, 60)
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
    ui.textLabel(upgrades, "Low HP prioritizes health. Build affordable defenses first; upgrades run while waiting for funds or space.", 30)
    local upgradeState = ui.textLabel(upgradesPage, "", 50)
    function ui.buildDefenses()
        for _, child in ipairs(defensePage:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        local group = ui.group(defensePage, "AUTO DEFENSE")
        ui.toggle(group, "AUTO PLACE CURRENT CLASS", cfg, "autoPlace")
        ui.textLabel(group, "NO COUNT LIMIT · Build when affordable; replace destroyed defenses when space opens.", 44)
        ui.number(group, "MIDDLE DEFENSE SPACING", "middleSpacing", 6, 40)
        ui.textLabel(group, "Inside only: 1-stud gap from boundary. 1 barricade row + 3 turret rows, with spaced middle defenses.", 44)
        app.coverageLabel = ui.textLabel(group,"SELECT A MAP PART FIRST",44)
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
    ui.textLabel(area, "Pick a floor part, then CONNECT. Edit the saved corners when needed.", 32)
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
    local mapCapture = ui.new("TextButton", {Name = "MapCornerInput", Size = UDim2.fromScale(1, 1),
        Text = "", BackgroundTransparency = 1, AutoButtonColor = false, Active = true, Modal = true, ZIndex = 8}, mapHolder)
    local dots, lines = {}, {}
    function app.refreshMapDots(camera)
        local points = app.draft or {}
        for i = 1, 24 do
            local dot, line = dots[i], lines[i]
            if not dot then
                dot = ui.new("TextLabel", {Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0.5, 0.5),
                    Text = tostring(i), TextSize = 10, Font = Enum.Font.BuilderSansBold, BackgroundColor3 = ui.blue,
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
                local nextPoint = points[i + 1] or (#points >= 3 and i == #points and points[1])
                local b = nextPoint and app.projectMapPoint(Vector3.new(nextPoint.x, nextPoint.y, nextPoint.z))
                if a and b then
                    local delta = Vector2.new(b.X - a.X, b.Y - a.Y)
                    line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
                    line.Size = UDim2.fromOffset(delta.Magnitude, 2)
                    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                    line.BackgroundColor3 = i == 1 and Color3.fromRGB(255, 190, 75) or ui.blue
                    line.BackgroundTransparency = i == #points and 0.45 or 0
                    line.Visible = true
                end
            end
        end
    end
    function app.closeMapEditor(saved)
        app.stopMapView()
        app.editing, app.pickPart, app.draftSurface, app.clearSurface = false, false, nil, nil
        editor.Visible, dotOverlay.Visible, mapHolder.Visible, frame.Visible = false, false, false, true
        app.syncBoundary(true)
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
        local floor = app.raycast(root.Position, Vector3.new(0, -256, 0), app.mapFilters())
        local layer = floor and floor.Normal.Y >= 0.65 and floor.Position.Y
            or root.Position.Y - human.HipHeight - root.Size.Y / 2
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
            if app.stepMapLayer(-1) then app.editorMessage = nil else app.editorMessage = "NO LOWER FLOOR" end
        end
    end)
    editorButton("FLOOR +", 0.75, 0.25, 97, function()
        if app.mapView then
            if app.stepMapLayer(1) then app.editorMessage = nil else app.editorMessage = "NO HIGHER FLOOR" end
        end
    end)
    editorButton("FULL / CUTAWAY", 0.25, 0.5, 97, function()
        if app.mapView and not app.mapView.loading then
            app.mapView.cutaway = not app.mapView.cutaway
            app.mapLayer(app.mapView.layer)
        end
    end)
    ui.button(area, "PICK MAP PART", function() app.openMapEditor("part") end)
    ui.button(area, "EDIT SAVED BOUNDARY", function() app.openMapEditor("saved") end)
    ui.toggle(area, "SHOW SAVED BOUNDARY", cfg, "showBoundary")
    local system = ui.group(settings, "AUTOMATION / CONFIG")
    ui.toggle(system, "MASTER ENABLED", cfg, "enabled")
    ui.number(system, "KEEP CASH RESERVE", "reserveCash", 0, 1e12)
    ui.button(system, "SAVE CONFIG NOW", function() app.save() app.note("config", "SAVED") end)
    ui.button(system, "STOP MOVEMENT / FIRING", function()
        cfg.fight, cfg.autoPlace = false, false
        app.releaseFire() app.stopFlight() app.stopWalk() app.buildGoal = nil app.changed()
    end)
    local diagnostics = ui.group(ui.diagnosticsPage, "FAILURES AND FULL SESSION LOG")
    local diagnosticLabel = ui.textLabel(diagnostics, "", 150)
    diagnosticLabel.TextYAlignment = Enum.TextYAlignment.Top
    diagnosticLabel.AutomaticSize = Enum.AutomaticSize.Y
    diagnosticLabel.LayoutOrder = 100000
    ui.button(diagnostics, "COPY DIAGNOSTICS", function()
        assert(type(setclipboard) == "function", "Clipboard unavailable; use SAVE FULL LOG")
        setclipboard(diagnostic:report(app.diagnosticSnapshot)) app.note("diagnostics", "COPIED FULL LOG")
    end)
    ui.button(diagnostics, "SAVE FULL LOG", function()
        local file, err = diagnostic:saveReport(app.diagnosticSnapshot)
        assert(file, err)
        app.note("diagnostics", "LOG SAVED: " .. file)
    end)
    task.spawn(function()
        while app.alive do diagnostic:flush() task.wait(3) end
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
    ui.button(resize, "CENTER / FIT SCREEN", function() app.windowPositioned = false app.resize() end)
    function app.tapMap(input)
        if not app.editing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not app.mapView or app.mapView.loading then app.editorMessage = "MAP IS STILL LOADING" return end
        if #app.mapView.floors == 0 then app.editorMessage = "NO FLOOR SELECTED; USE FLOOR CONTROLS" return end
        local screen = Vector2.new(input.Position.X, input.Position.Y)
        local at, size = app.viewport.AbsolutePosition, app.viewport.AbsoluteSize
        if screen.X < at.X or screen.Y < at.Y or screen.X > at.X + size.X or screen.Y > at.Y + size.Y then return end
        if not app.pickPart and #app.draft >= 3 then
            local first = app.draft[1]
            local pixel = app.projectMapPoint(Vector3.new(first.x, first.y, first.z))
            if pixel and (pixel + app.viewport.AbsolutePosition - screen).Magnitude <= 14 then
                app.commitArea()
                return
            end
        end
        local hit = app.mapViewRay(screen)
        if not hit or not hit.Instance:IsA("BasePart") or hit.Normal.Y < 0.65 then app.editorMessage = "TAP A VISIBLE FLOOR; TRY FLOOR + / -" app.note("area", app.editorMessage) return end
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
            if #app.draft >= 24 then app.editorMessage = "MAXIMUM 24 DOTS; CONNECT OR UNDO" app.note("area", app.editorMessage) return end
            local p = hit.Position
            app.draft[#app.draft + 1] = {x = p.X, y = p.Y, z = p.Z}
        end
        app.editorMessage = "CORNER " .. #app.draft .. " MARKED · TAP MORE OR CONNECT"
        if app.mapView then app.refreshMapDots(app.mapView.camera) end
    end
    app.connect(mapCapture.InputBegan, function(input)
        local ok, err = pcall(app.tapMap, input)
        if not ok then app.editorMessage = "MAP INPUT ERROR: " .. tostring(err) app.note("area", app.editorMessage) end
    end)
    app.connect(UIS.InputEnded, function(input)
        if app.editing and app.held and input ~= app.held.token
            and input.UserInputType == Enum.UserInputType.MouseButton1 then app.releaseFire() end
    end)
    function app.stop()
        if not app.alive then return end
        diagnostic:record("session","STOPPED","INFO",true) diagnostic:flush()
        app.alive = false
        app.save()
        app.releaseFire() app.stopFlight() app.stopWalk() app.stopMapView() app.clearMarkers()
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
        app.releaseFire() app.stopFlight() app.stopWalk() app.buildGoal = nil
        app.turretCache, app.airGoal, app.observedHealth = nil, nil, nil
        app.dodgeHistory,app.enemyMotion,app.enemyCache,app.dodgeRejected=nil,nil,nil,nil
    end)
    RunService:BindToRenderStep("EXIS_ZOMBIE_MAP", Enum.RenderPriority.Camera.Value + 20, function()
        local ok, err = pcall(app.renderMapView)
        if not ok then
            app.note("area", "ERROR: " .. tostring(err))
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
            if not ok then app.note("target", "ERROR: " .. tostring(err)) end
        end
        local ok, err = pcall(app.combatTick, dt)
        if not ok then app.releaseFire() app.stopFlight() app.stopWalk() app.note("combat", "ERROR: " .. tostring(err)) end
    end)
    RunService:BindToRenderStep("EXIS_ZOMBIE_AIM", Enum.RenderPriority.Camera.Value + 5, function()
        local ok, err = pcall(app.aimTick)
        if not ok then app.note("aim", "ERROR: " .. tostring(err)) end
    end)
    task.spawn(function()
        while app.alive do
            local ok, err = pcall(function()
                local before = app.mapId .. tostring(app.className) .. app.mode
                app.detect()
                if before ~= app.mapId .. tostring(app.className) .. app.mode then
                    if app.mapView and app.mapView.map ~= app.mapId then app.closeMapEditor(false) end
                    app.planKey, app.target, app.buildGoal, app.surface, app.defenseCache = nil, nil, nil, nil, nil
                    app.rejected, app.pendingPlacements, app.blueprintKey = {}, {}, nil
                    app.enemyCache, app.airGoal, app.navCache, app.spawnAnchor = nil, nil, nil, nil
                    app.turretCache, app.groundRouteCache, app.walkGoal, app.observedHealth = nil, nil, nil, nil
                    app.matchMix, app.placementTask = nil, nil
                    app.dodgeHistory,app.enemyMotion,app.dodgeRejected=nil,nil,nil
                    ui.buildClasses() ui.buildDefenses()
                end
                app.syncBoundary()
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
            if not ok then app.note("worker", "ERROR: " .. tostring(err)) end
            task.wait(0.2)
        end
    end)
    task.spawn(function()
        while app.alive do
            local ok, err = pcall(app.skipTick)
            if not ok then app.note("skip", "ERROR: " .. tostring(err)) end
            task.wait(2)
        end
    end)
    task.spawn(function()
        while app.alive do
            local ok, err = xpcall(function()
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
            local coverage = app.coverageStatus()
            if app.coverageLabel then app.coverageLabel.Text = coverage end
            local lines = {coverage, "PLACE " .. game.PlaceId, "MAP " .. app.mapId, "CLASS " .. tostring(app.className),
                liveLabel.Text, "MASTER "..tostring(cfg.enabled).." | AUTO PLACE "..tostring(cfg.autoPlace).." | FIGHT "..tostring(cfg.fight),
                "EDITING "..tostring(app.editing==true).." | BUILD TASK "..tostring(app.placementTask and app.placementTask.slot.name or "NONE"),
                "PLACEMENT: "..tostring(app.placementReadiness or "No placement scan yet; check AUTO PLACE and master switches"),
                "FIRE SIGNAL " .. tostring(type(firesignal) == "function"), "CONFIG WRITE " .. tostring(type(writefile) == "function")}
            local keys = {}
            for key in pairs(app.notes) do keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do lines[#lines + 1] = key:upper() .. ": " .. app.notes[key] end
            app.diagnosticSnapshot = table.concat(lines, "\n")
            diagnosticLabel.Text = app.diagnosticSnapshot .. "\n\n" .. diagnostic:summary(true) .. "\n\nRECENT LOG\n" .. diagnostic:tail()
            end, Diagnostics.traceback)
            if not ok then app.note("diagnostic view", "ERROR: " .. tostring(err)) end
            task.wait(0.5)
        end
    end)
end

local ok, err = xpcall(run, Diagnostics.traceback)
if not ok then
    if diagnostic then diagnostic:record("startup",err,"ERROR") diagnostic:flush() end
    warn("EXIScript / ZombieRushSurvival: " .. tostring(err))
end
