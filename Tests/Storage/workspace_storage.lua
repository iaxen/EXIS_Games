-- Run from the repository root: lua Tests/Storage/workspace_storage.lua
-- Executes each game's real storage helper with an in-memory executor filesystem.
local passed = 0
local cases = {
    {"Games/Fuzzotopia.lua", "Fuzzotopia"},
    {"Games/MrbeastIslandEscape.lua", "MrbeastIslandEscape"},
    {"Games/ZombieRushSurvival.lua", "ZombieRushSurvival"},
}
local function productionHelper(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find("-- Executor-workspace storage.", 1, true))
    local finish = assert(source:find("function storage.exists(name)", start, true))
    finish = assert(source:find("return ok", finish, true))
    finish = assert(source:find("end", finish, true)) + 2
    return source:sub(start, finish) .. "\nreturn storage"
end
local function filesystem(helper, initial)
    local files, folders, writes = initial or {}, {}, {}
    readfile = function(path)
        if files[path] == nil then error("file missing: " .. path) end
        return files[path]
    end
    isfolder = function(path) return folders[path] == true end
    makefolder = function(path)
        local parent = path:match("^(.*)/[^/]+$")
        assert(not parent or folders[parent], "parent must exist first")
        folders[path] = true
    end
    writefile = function(path, contents)
        local parent = path:match("^(.*)/[^/]+$")
        assert(parent and folders[parent], "writes require the game folder")
        files[path] = contents
        writes[#writes + 1] = path
    end
    return assert(load(helper))(), files, folders, writes
end
local function check(name, fn)
    fn()
    passed = passed + 1
    print("PASS " .. name)
end
for _, game in ipairs(cases) do
    local path, name = game[1], game[2]
    local helper = productionHelper(path)
    local root = "EXIGames/" .. name
    check(name .. ": creates parent before game directory and writes inside it", function()
        local storage, files, folders, writes = filesystem(helper)
        storage.write("config.json", "new")
        assert(folders.EXIGames and folders[root])
        assert(files[root .. "/config.json"] == "new")
        assert(files["config.json"] == nil and #writes == 1)
    end)
    check(name .. ": fully qualified paths are not prefixed twice", function()
        local storage, files = filesystem(helper)
        storage.write(root .. "/config.json", "new")
        assert(storage.read(root .. "/config.json") == "new")
        assert(files[root .. "/" .. root .. "/config.json"] == nil)
    end)
    check(name .. ": copies a legacy root file and preserves the original", function()
        local storage, files = filesystem(helper, {["config.json"] = "old"})
        assert(storage.read(root .. "/config.json") == "old")
        assert(files[root .. "/config.json"] == "old" and files["config.json"] == "old")
    end)
    check(name .. ": an existing namespaced save wins over the old root save", function()
        local storage, files = filesystem(helper, {
            ["config.json"] = "old",
            [root .. "/config.json"] = "new",
        })
        assert(storage.read("config.json") == "new" and files["config.json"] == "old")
    end)
    check(name .. ": missing save stays missing instead of writing empty data", function()
        local storage, files, folders, writes = filesystem(helper)
        assert(not storage.exists("missing.json") and not pcall(storage.read, "missing.json"))
        assert(#writes == 0 and next(files) == nil)
    end)
    check(name .. ": legacy reading works without write support", function()
        local storage, files = filesystem(helper, {["config.json"] = "old"})
        writefile = nil
        assert(storage.read("config.json") == "old")
        assert(files[root .. "/config.json"] == nil)
        assert(not pcall(storage.write, "config.json", "changed"))
    end)
    check(name .. ": folder errors never cause writes back into workspace root", function()
        local storage, files, _, writes = filesystem(helper)
        makefolder = function() error("folder creation rejected") end
        assert(not pcall(storage.write, "config.json", "new"))
        assert(#writes == 0 and files["config.json"] == nil)
    end)
    check(name .. ": backslash paths normalize to the game's directory", function()
        local storage, files = filesystem(helper)
        storage.write(root .. "/config.json", "new")
        assert(storage.read((root .. "/config.json"):gsub("/", "\\")) == "new")
    end)
end
-- A shared leaf filename cannot overwrite another game's configuration.
local helpers = {}
for _, game in ipairs(cases) do helpers[#helpers + 1] = productionHelper(game[1]) end
local first, files = filesystem(helpers[1])
first.write("config.json", "Fuzzotopia")
for index = 2, #cases do
    local storage = assert(load(helpers[index]))()
    storage.write("config.json", cases[index][2])
end
for _, game in ipairs(cases) do assert(files["EXIGames/" .. game[2] .. "/config.json"] == game[2]) end
passed = passed + 1
print(passed .. " workspace storage checks passed")
