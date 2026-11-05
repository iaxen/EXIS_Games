-- EXIScript: Island Escape module. Client APIs verified against the supplied export.
local function runIslandEscape()
 local Players=game:GetService("Players")
 local RS=game:GetService("ReplicatedStorage")
 local UIS=game:GetService("UserInputService")
 local HTTP=game:GetService("HttpService")
 local player=Players.LocalPlayer
 local pg=player:WaitForChild("PlayerGui")
 local engineReady=RS:WaitForChild("Engine",30)
 if not engineReady or not engineReady:WaitForChild("Service",15)or not engineReady.Service:WaitForChild("Config",15)then warn("EXIScript: Island Escape services are not loaded");return end
 local previous=pg:FindFirstChild("EXISIslandEscape")
 if previous then previous:Destroy() end
 local gui=Instance.new("ScreenGui");gui.Name="EXISIslandEscape";gui.ResetOnSpawn=false;gui.DisplayOrder=2147483647;gui.Parent=pg
 local alive=true;local connections={};local flags={};local selected={};local modules={};local failed={};local due={};local taskStatus={};local recentErrors={}
 local opts={move="Walk",interval=0.7,health=50,hunger=40,fuel=3,tweenSpeed=32,routeTimeout=15,autoJump=true}
 local work={needs={},resourceNeeds={},waiting={},sent=0,active=nil,buildRemaining={}}
 function work.remaining(info,id,total)
  local progress=info.assetId and work.buildRemaining[info.assetId]
  return progress and type(progress[id])=="number"and math.max(0,progress[id])or total
 end
 local path="exis_island_"..player.UserId.."_"..game.PlaceId..".json"
 local blue=Color3.fromRGB(83,158,244);local white=Color3.fromRGB(226,234,245)
 local function make(class,props,parent)local o=Instance.new(class);for k,v in pairs(props)do o[k]=v end;o.Parent=parent;return o end
 local function corner(o,radius)make("UICorner",{CornerRadius=UDim.new(0,radius or 6)},o)end
 local function round(o)corner(o,6)end
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
    Size=UDim2.new(1,-75,1,0),BackgroundTransparency=1,
    Text="EXIScript | MRBEAST ISLAND ESCAPE",TextColor3=blue,Font=Enum.Font.BuilderSansBold,
    TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left}, header)
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
 local function button(parent,text,fn)
  local b=make("TextButton",{Size=UDim2.new(1,0,0,25),Text=text:upper(),TextSize=10,Font=Enum.Font.BuilderSans,TextColor3=white,BackgroundColor3=Color3.fromRGB(23,45,71),BorderSizePixel=0},parent);round(b)
  b.Activated:Connect(function()local ok,e=pcall(fn);if not ok then warn("EXIScript: "..tostring(e))end end);return b
 end
 local status=make("TextLabel",{Position=UDim2.new(0,90,1,-20),Size=UDim2.new(1,-95,0,18),Text="READY",TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,Font=Enum.Font.BuilderSans,TextColor3=blue,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left},panel)
 local function say(s)status.Text=tostring(s)end
 local function note(key,message)taskStatus[key]=message end
 local function safely(key,fn)
  local ok,result=pcall(fn)
  if not ok then
   local message=tostring(result):gsub("^.-:%d+: ","")
   note(key,"ERROR: "..message);say(key:upper()..": "..message)
   recentErrors[#recentErrors+1]=key..": "..message;if #recentErrors>12 then table.remove(recentErrors,1)end
   return false
  end
  return result
 end
 local englishTranslator=nil
 local labelCache={}
 task.spawn(function()pcall(function()englishTranslator=game:GetService("LocalizationService"):GetTranslatorForLocaleAsync("en-us")end)end)
 local function readable(value)
  if type(value)~="string"or value==""then return end
  if not value:find("[\128-\255]")and value:find("%a")then return value end
  if labelCache[value]then return labelCache[value]end
  if englishTranslator then local ok,t=pcall(function()return englishTranslator:Translate(game,value)end)
   if ok and type(t)=="string"and t:find("%a")and not t:find("[\128-\255]")then labelCache[value]=t;return t end
