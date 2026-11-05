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
  end
 end
 local function itemLabel(kind,id,info,index)
  local c=modules.Config;local item=c and c.item and c.item.byId and c.item.byId[id]
  for _,entry in ipairs({info,item or {}})do
   for _,field in ipairs({"displayName","DisplayName","englishName","enName","name","assetId","id"})do
    local t=readable(entry[field]);if t then return t end
   end
  end
  return ({["木板1"]="Wooden Planks",["原始部落宝箱"]="Tribal Chest",["森林守护者宝箱"]="Forest Guardian Chest"})[id]or readable(tostring(id))or(kind:upper().." "..string.format("%03d",index or 0))
 end
 local function save()if type(writefile)=="function"then local ok,e=pcall(function()writefile(path,HTTP:JSONEncode({version=1,flags=flags,selected=selected,options=opts}))end);if not ok then say(e)end end end
 if type(readfile)=="function"then pcall(function()local d=HTTP:JSONDecode(readfile(path));if d.version==1 then
  if type(d.flags)=="table"then for k,v in pairs(d.flags)do if type(v)=="boolean"then flags[k]=v end end end
  if type(d.selected)=="table"then selected=d.selected end
  if type(d.options)=="table"then if d.options.move=="Walk"or d.options.move=="Teleport"or d.options.move=="Tween"then opts.move=d.options.move end;for _,k in ipairs({"interval","health","hunger","fuel"})do local n=tonumber(d.options[k]);if n and n==n and n>=0 and n<10000 then opts[k]=n end end end
 if type(d.options)=="table"then
  if type(d.options.autoJump)=="boolean"then opts.autoJump=d.options.autoJump end
  for key,range in pairs({tweenSpeed={8,120},routeTimeout={6,30}})do local n=tonumber(d.options[key]);if n and n==n then opts[key]=math.clamp(n,range[1],range[2])end end
 end
 end end)end
 local function module(name)
  if modules[name]then return modules[name]end
  if name=="Config"then
   local lib=RS:FindFirstChild("Module");local service=lib and lib:FindFirstChild("Service");local cloud=service and service:FindFirstChild("CloudConfig");local remote=cloud and cloud:FindFirstChild("getAllConfigFunction")
   if remote then local ok,data=pcall(function()return remote:InvokeServer()end);if ok and type(data)=="table"and data.item then modules.Config=data;return data end end
  end
  if failed[name]and os.clock()-failed[name]<15 then return end
  local engine=RS:FindFirstChild("Engine");local lib=RS:FindFirstChild("Module")
  local source=(engine and engine:FindFirstChild("Service")and engine.Service:FindFirstChild(name))or(lib and lib:FindFirstChild("Service")and lib.Service:FindFirstChild(name))
  if not source then failed[name]=os.clock();return end
  local ok,m=pcall(require,source);if ok then modules[name]=m;return m end
  failed[name]=os.clock();say(name.." unavailable")
 end
 local remoteActions={
  ItemCollect={collect="collectRemote"},MakeFire={addWood="addWoodRemote",addFood="addFoodRemote",collectFood="collectFoodRemote"},
  Furnace={addBoth="addTaskRemote",collectResult="collectResultRemote"},WaterMaker={collect="collectRemote"},
  CraftItems={craft="craftRemote"},BuildBuilding={build="buildRemote"},
  ChestService={requestOpen="RequestOpenEvent",isOpened="IsOpenedFunction",isLocked="IsLockedFunction"},
  PuzzlePropService={requestSolve="RequestSolveEvent",isSolved="IsSolvedFunction"},
  DailyReward={claim="claimRemote"},WeekReward={claim="claimRemote"},PlayTimeReward={claim="claimRemote"},DailyQuest={claim="claimRemote"},
 }
 local function call(name,action,...)
  local remoteName=remoteActions[name]and remoteActions[name][action]
  if remoteName then
   local source=RS.Engine.Service:FindFirstChild(name)
   local lib=RS:FindFirstChild("Module");source=source or(lib and lib:FindFirstChild("Service")and lib.Service:FindFirstChild(name))
   local remote=source and source:FindFirstChild(remoteName)
   assert(remote,name.." remote unavailable in this server")
   if remote:IsA("RemoteFunction")then return remote:InvokeServer(...)end
   work.sent=work.sent+1
   if name=="Furnace"and action=="addBoth"then remote:FireServer("both")else remote:FireServer(...)end
   note(name.."."..action,"REQUEST SENT");return true
  end
  local m=module(name);assert(m and m.client and type(m.client[action])=="function",name.."."..action.." unavailable")
  return m.client[action](...)
 end
 local function world()return workspace:FindFirstChild("Game")end
 local function serverMode()
  local lib=RS:FindFirstChild("Module");local service=lib and lib:FindFirstChild("Service");local source=service and service:FindFirstChild("GetServerType");local cache=source and source:FindFirstChild("cache")
  if cache and cache:IsA("StringValue")and cache.Value~=""then return cache.Value=="ReservedServer"and"match"or"lobby"end
  local w=world();return w and w:FindFirstChild("Static")and w:FindFirstChild("Day")and"match"or"loading"
 end
 local function built(name)
  local w=world();local folder=w and w:FindFirstChild("Buildings")
  return folder and folder:FindFirstChild(name)
 end
 local function root()local c=player.Character;local h=c and c:FindFirstChildOfClass("Humanoid");return h and h.Health>0 and c:FindFirstChild("HumanoidRootPart"),h end
 local function pos(o)if o:IsA("BasePart")then return o.Position elseif o:IsA("Model")then return o:GetPivot().Position end end
 local motion={owner=nil,serial=0,tween=nil,manual=nil,blocked={},pulse=nil}
 function motion.cancel(reason)
  motion.serial=motion.serial+1
  if motion.tween then motion.tween:Cancel();motion.tween=nil end
  local r,h=root();if r and h then h:MoveTo(r.Position)end
  if motion.owner then note(motion.owner,reason or "MOVEMENT CANCELLED")end
 end
 function motion.water(hit)
  if not hit then return false end
  if hit.Material==Enum.Material.Water then return true end
  local node=hit.Instance
  while node and node~=workspace do
   local n=node.Name:lower()
   if n=="ocean"or n=="water"or n=="sea"then return true end
   node=node.Parent
  end
  return false
 end
 function motion.floor(point,target,drop,raise)
  local ignore={};if player.Character then ignore[#ignore+1]=player.Character end
  if typeof(target)=="Instance"then ignore[#ignore+1]=target end
  local w=world()
  if w then for _,name in ipairs({"DroppedItems","Entities"})do local folder=w:FindFirstChild(name);if folder then ignore[#ignore+1]=folder end end end
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.IgnoreWater=false
  local up=raise or 4
  for _=1,5 do
   params.FilterDescendantsInstances=ignore
   local hit=workspace:Raycast(point+Vector3.new(0,up,0),Vector3.new(0,-((drop or 8)+up),0),params)
   if not hit or motion.water(hit)then return end
   if hit.Instance==workspace.Terrain or hit.Instance.CanCollide then
    if hit.Normal.Y<0.65 then return end
    return hit.Position
   end
   ignore[#ignore+1]=hit.Instance
  end
 end
 function motion.clearSegment(a,b,target)
  local delta=b-a;local steps=math.max(1,math.ceil(delta.Magnitude/2))
  if steps>240 then return false end
  for i=1,steps do
   if not motion.floor(a+delta*(i/steps),target,7,3)then return false end
  end
  return true
 end
 function motion.goals(target,radius)
  local r,h=root();local p=typeof(target)=="Vector3"and target or pos(target)
  if not r or not p then return {}end
  local result={};local distance=math.max(1,math.min(4,radius*0.6))
  local height=math.max(2,h.HipHeight+r.Size.Y/2)
  for i=0,7 do
   local angle=i*math.pi/4
   local probe=p+Vector3.new(math.cos(angle)*distance,0,math.sin(angle)*distance)
   local floor=motion.floor(probe,target,120,12)
   if floor then
    local stand=floor+Vector3.new(0,height,0)
    local horizontal=Vector2.new(stand.X-p.X,stand.Z-p.Z).Magnitude
    if horizontal<=radius and math.abs(stand.Y-p.Y)<=math.max(8,radius)then result[#result+1]=stand end
   end
  end
  table.sort(result,function(a,b)return(a-r.Position).Magnitude<(b-r.Position).Magnitude end)
  return result
 end
 function motion.valid(key,serial,character)
  return alive and flags[key]==true and serial==motion.serial and player.Character==character and not not root()
 end
 function motion.pathTo(start,goal)
  local path=game:GetService("PathfindingService"):CreatePath({AgentRadius=2,AgentHeight=5,
   AgentCanJump=opts.autoJump~=false,AgentCanClimb=true,WaypointSpacing=3,Costs={Water=math.huge}})
  local ok=pcall(function()path:ComputeAsync(start,goal)end)
  if not ok or path.Status~=Enum.PathStatus.Success then return end
  return path
 end
 function motion.walkPath(path,goal,key,serial,character,deadline)
  local waypoints=path:GetWaypoints();local index=2;local blocked=false
  local connection=path.Blocked:Connect(function(i)if i>=index then blocked=true end end)
  local ok,result=pcall(function()
   for i=2,#waypoints do
    index=i
    local r,h=root();if not r or not motion.valid(key,serial,character)then return false end
    local wp=waypoints[i];local jumping=wp.Action==Enum.PathWaypointAction.Jump
    if not motion.floor(wp.Position,nil,8,4)then note(key,"UNSAFE LANDING - REPLANNING");return false end
    if not jumping and not motion.clearSegment(r.Position,wp.Position,nil)then note(key,"WATER OR DROP AHEAD - REPLANNING");return false end
    if jumping then
     if opts.autoJump==false then return false end
     h.Jump=true;h:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    h:MoveTo(wp.Position)
    local last=r.Position;local progressed=os.clock();local attemptedJump=false
    while alive do
     task.wait(0.08);r,h=root()
     if not r or not motion.valid(key,serial,character)or blocked or os.clock()>deadline then return false end
     if motion.pulse and motion.pulse()then note(key,"YIELDING TO SURVIVAL");return false end
     if(r.Position-wp.Position).Magnitude<=math.max(2.2,h.HipHeight+0.5)then break end
     if(r.Position-last).Magnitude>0.5 then last=r.Position;progressed=os.clock()
     elseif os.clock()-progressed>1 then
      if opts.autoJump~=false and not attemptedJump and motion.floor(wp.Position,nil,8,4)then
       h.Jump=true;h:ChangeState(Enum.HumanoidStateType.Jumping);attemptedJump=true;progressed=os.clock()
      else note(key,"STUCK - REPLANNING");return false end
     end
     if not jumping and h.FloorMaterial~=Enum.Material.Air then
      local delta=wp.Position-r.Position
      if delta.Magnitude>0.1 and not motion.floor(r.Position+delta.Unit*math.min(2,delta.Magnitude),nil,7,2)then h:MoveTo(r.Position);return false end
     end
    end
   end
   local r=root();return r and(r.Position-goal).Magnitude<=4
  end)
  connection:Disconnect()
  if not ok then error(result)end
  return result
 end
 function motion.tweenPath(path,goal,key,serial,character,deadline)
  local r,h=root();if not r then return false end
  local points=path:GetWaypoints()
  for i=2,#points do
   r,h=root();if not r or not motion.valid(key,serial,character)then return false end
   local floor=motion.floor(points[i].Position,nil,8,4)
   if not floor then note(key,"UNSAFE TWEEN ROUTE");return false end
   local destination=floor+Vector3.new(0,math.max(2,h.HipHeight+r.Size.Y/2),0)
   if not motion.clearSegment(r.Position,destination,nil)then note(key,"TWEEN ROUTE CROSSES WATER OR A DROP");return false end
   local delta=destination-r.Position
   if delta.Magnitude>0.2 then
    local facing=Vector3.new(goal.X,destination.Y,goal.Z)
    local cf=(facing-destination).Magnitude>0.1 and CFrame.lookAt(destination,facing)or CFrame.new(destination)
    motion.tween=game:GetService("TweenService"):Create(r,TweenInfo.new(math.max(0.05,delta.Magnitude/opts.tweenSpeed),Enum.EasingStyle.Linear),{CFrame=cf})
    motion.tween:Play()
    while motion.tween and motion.tween.PlaybackState==Enum.PlaybackState.Playing do
     task.wait(0.05)
     if not motion.valid(key,serial,character)or os.clock()>deadline or(motion.pulse and motion.pulse())then motion.tween:Cancel();motion.tween=nil;return false end
    end
    motion.tween=nil
   end
  end
  r=root();return r and(r.Position-goal).Magnitude<=4
 end
 local function travel(target,key,radius)
  local r,h=root();if not r then note(key,"CHARACTER NOT READY");return false end
  if motion.owner and motion.owner~=key then note(key,"WAITING FOR MOVEMENT");return false end
  if typeof(target)=="Instance"and motion.blocked[target]and motion.blocked[target]>os.clock()then return false end
  local character=player.Character;local serial=motion.serial;radius=radius or 6
  local p=typeof(target)=="Vector3"and target or pos(target)
  if not p then return false end
  -- Already in range needs no movement, preserving a manually chosen position.
  if(r.Position-p).Magnitude<=radius and motion.floor(r.Position,nil,8,3)then return true end
  motion.owner=key;local goals=motion.goals(target,radius);local deadline=os.clock()+opts.routeTimeout
  local ok,result=pcall(function()
   if #goals==0 then note(key,"NO SAFE DRY APPROACH");return false end
   for index=1,math.min(3,#goals)do
    r,h=root();if not r or not motion.valid(key,serial,character)or os.clock()>deadline then return false end
    local goal=goals[index]
    if opts.move=="Teleport"then
     local facing=Vector3.new(p.X,goal.Y,p.Z)
     r.CFrame=(goal-facing).Magnitude>0.1 and CFrame.lookAt(goal,facing)or CFrame.new(goal)
     task.wait(0.15);return motion.valid(key,serial,character)
    end
    local path=motion.pathTo(r.Position,goal)
    if path then
     note(key,opts.move:upper().." - FOLLOWING SAFE ROUTE")
     local reached=opts.move=="Tween"and motion.tweenPath(path,goal,key,serial,character,deadline)or(opts.move=="Walk"and motion.walkPath(path,goal,key,serial,character,deadline))
     if reached then return true end
    end
   end
   note(key,"NO REACHABLE DRY ROUTE - TARGET DEFERRED");return false
  end)
  if motion.tween then motion.tween:Cancel();motion.tween=nil end
  r,h=root();if r and h then h:MoveTo(r.Position)end
  motion.owner=nil
  if not ok then note(key,"MOVEMENT ERROR: "..tostring(result));result=false end
  if not result and serial==motion.serial and alive and flags[key]and typeof(target)=="Instance"then motion.blocked[target]=os.clock()+8 end
  return result==true and motion.valid(key,serial,character)
 end
 local function tools()local t={};for _,p in ipairs({player:FindFirstChild("Backpack"),player.Character})do if p then for _,o in ipairs(p:GetChildren())do if o:IsA("Tool")then t[#t+1]=o end end end end;return t end
 local function count(name)local n=0;for _,o in ipairs(tools())do if o.Name==name then n=n+(o:GetAttribute("count")or 1)end end;return n end
 local function equip(t)local _,h=root();if h and t.Parent~=player.Character then h:EquipTool(t);task.wait(0.15)end end
 local function nearest(list,predicate,score)local r=root();if not r then return end;local best,d=nil,math.huge;for _,o in ipairs(list)do if o.Parent and not(motion.blocked[o]and motion.blocked[o]>os.clock())and predicate(o)then local p=pos(o);if p then local n=(p-r.Position).Magnitude/(1+math.max(0,score and score(o)or 0)*0.05);if n<d then best,d=o,n end end end end;return best end
 local function config()local m=module("Config");assert(m,"Game config unavailable");return m end
 local function allowed(kind,id)return type(selected[kind])=="table"and selected[kind][id]==true end
 local function selectedEmpty(kind)for _,v in pairs(selected[kind]or{})do if v==true then return false end end;return true end
 local function recipeReady(info)
  local c=config();local recipe=c.recipe.byId[info.recipeId];if not recipe then return false end
  for k,n in pairs(recipe)do local id=type(k)=="string"and k:match("^require_(.+)$");if id and type(n)=="number"and n>0 then local item=c.item.byId[id];if not item or count(item.displayName)<n then return false end end end;return true
 end
 local pages={};local groups={};local toggles={};local tabButtons={}
 local nav=sidebar
 local function page(name)
  local frame=make("ScrollingFrame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,
   ScrollBarImageColor3=blue,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),Visible=false},content)
  make("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},frame);pages[name]=frame
  local index=0;for _ in pairs(tabButtons)do index=index+1 end
  local b=make("TextButton",{Position=UDim2.fromOffset(4,4+index*24),Size=UDim2.new(1,-8,0,21),Text="  "..name:upper(),
   TextXAlignment=Enum.TextXAlignment.Left,BackgroundColor3=Color3.fromRGB(15,19,27),BorderSizePixel=0,TextColor3=white,
   Font=Enum.Font.BuilderSansMedium,TextSize=10},nav);corner(b,7)
  make("UIStroke",{Color=Color3.fromRGB(35,56,79),Thickness=1},b)
  b.Activated:Connect(function()pageTitle.Text=name:upper();for n,other in pairs(pages)do other.Visible=n==name;tabButtons[n].TextColor3=n==name and blue or white;tabButtons[n].BackgroundColor3=n==name and Color3.fromRGB(23,45,71)or Color3.fromRGB(15,19,27)end end)
  tabButtons[name]=b;nav.CanvasSize=UDim2.fromOffset(0,4+(index+1)*24);return frame
 end
local function text(container,text)
    return make("TextLabel",{Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,Text=text,TextWrapped=true,TextSize=10,
        TextColor3=Color3.fromRGB(156,175,198),Font=Enum.Font.BuilderSans,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},container)
end
local function group(container,name)
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
            for _,other in ipairs(groups) do
                if other.frame:IsDescendantOf(body) then other.setOpen(false) end
            end
        end
    end
    groups[#groups+1]=entry
    header.Activated:Connect(function()
        local open=not body.Visible
        if open then
            for _,other in ipairs(groups) do
                if other~=entry and other.frame.Parent==frame.Parent then other.setOpen(false) end
            end
        end
        entry.setOpen(open)
    end)
    return body
end
 local function switch(p,label,get,set)
  local b=button(p,"",function()set(not get());save()end);b.BackgroundColor3=Color3.fromRGB(21,30,43)
  make("TextLabel",{Position=UDim2.fromOffset(7,0),Size=UDim2.new(1,-53,1,0),Text=label:upper(),TextSize=10,
   TextWrapped=true,Font=Enum.Font.BuilderSans,TextColor3=white,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left},b)
  local track=make("Frame",{Position=UDim2.new(1,-33,0.5,-6),Size=UDim2.fromOffset(25,12),BorderSizePixel=0},b);round(track)
  local knob=make("Frame",{Size=UDim2.fromOffset(8,8),BackgroundColor3=white,BorderSizePixel=0},track);round(knob)
  local function render()track.BackgroundColor3=get()and blue or Color3.fromRGB(47,59,75);knob.Position=UDim2.fromOffset(get()and 15 or 2,2)end
  b.Activated:Connect(render);render();return render
 end
 local function toggle(p,key,label,description)
  toggles[key]=switch(p,label,function()return flags[key]==true end,function(value)flags[key]=value;note(key,value and "ENABLED"or"OFF");toggles[key]()end)
  if description then text(p,description)end
 end
 local function number(p,key,label,min,max)
  text(p,label);local b=make("TextBox",{Size=UDim2.new(1,0,0,26),Text=tostring(opts[key]),ClearTextOnFocus=false,TextSize=11,Font=Enum.Font.BuilderSans,TextColor3=white,BackgroundColor3=Color3.fromRGB(21,32,47)},p);round(b)
  b.FocusLost:Connect(function()local n=tonumber(b.Text);if n and n==n and n<math.huge then opts[key]=math.clamp(n,min,max);save()end;b.Text=tostring(opts[key])end)
 end
 local main=page("Main");local resources=page("Gather");local camp=page("Camp");local craft=page("Craft");local questPage=page("Quests");local explore=page("Explore");local settings=page("Settings")
 local survival=group(main,"SURVIVAL")
 toggle(survival,"eat","Auto eat","Uses selected food when health or hunger is low. Select food below.")
 number(survival,"health","HEALTH BELOW (%)",1,100);number(survival,"hunger","HUNGER BELOW (%)",1,100)
 local combat=group(main,"DEFENCE")
 toggle(combat,"combat","Auto defend against nearby enemies","Uses your equipped melee tool on nearby NPCs. Never targets players.")
 local fishing=group(main,"FISHING")
 toggle(fishing,"fish","Auto cast and reel","Equip a rod and face water. Casts and reels automatically; complete the fish minigame normally. Movement pauses only during an active cast.")
 local gather=group(resources,"RESOURCE FARMING")
 toggle(gather,"gather","Auto gather selected resources","Uses a matching owned tool. No selection = all available resources.")
 local drops=group(resources,"DROPPED ITEMS")
 toggle(drops,"drops","Auto collect drops","All unprotected drops when no items are selected below. Respects owner protection.")
 local fire=group(camp,"CAMPFIRE")
 toggle(fire,"fuel","Auto add wood","Adds wood only below the fuel target.");number(fire,"fuel","FUEL TARGET (WOOD)",1,100)
 toggle(fire,"cook","Auto cook selected food","Consumes selected cookable food.")
 toggle(fire,"cooked","Auto collect cooked food")
 button(fire,"ADD ONE WOOD / REFRESH FUEL STATE",function()assert(built("Campfire"),"Build the campfire first");call("MakeFire","addWood")end)
 local furnace=group(camp,"FURNACE")
 toggle(furnace,"smelt","Auto feed furnace","Consumes smelting ingredients.");toggle(furnace,"smeltCollect","Auto collect results")
 local water=group(camp,"WATER MAKER");toggle(water,"water","Auto collect coconuts")
 local crafting=group(craft,"TOOLS AND ARMOUR");toggle(crafting,"craft","Auto craft selected items","Crafts one missing selected item when materials are available.")
 local building=group(craft,"CONSTRUCTION");toggle(building,"build","Auto contribute selected buildings","Spends recipe materials on selected unfinished buildings.")
 toggle(building,"buildCurrent","Auto build active blueprints","Uses owned materials on available unfinished buildings, including the first campfire. No selection required.")
 local questBody=group(questPage,"MRBEAST QUESTS");toggle(questBody,"quest","Auto deliver required items","Moves owned matching drops or carried items into the quest area. Submits the current revision only.")
 local questInfo=text(questBody,"QUEST: WAITING")
 local rewards=group(questPage,"REWARDS");toggle(rewards,"daily","Auto daily reward");toggle(rewards,"weekly","Auto weekly reward");toggle(rewards,"playtime","Auto playtime rewards");toggle(rewards,"dailyQuest","Claim completed daily quests")
 local chestUI=group(explore,"CHESTS AND PUZZLES");toggle(chestUI,"chests","Auto open unlocked chests");toggle(chestUI,"puzzles","Auto interact with puzzle props")
 local escape=group(explore,"ESCAPE BOAT")
 toggle(escape,"escape","Auto use available escape boat","Uses the boat interaction when its prompt is enabled. Ends your run.")
 local destination=group(explore,"BUILDING TRAVEL")
 local session=group(settings,"SESSION")
 toggle(session,"antiAfk","Anti idle")
 toggle(session,"autoExecute","Auto execute after teleport","Reloads EXIScript when entering the match if your executor supports teleport queues.")
 button(session,"SAVE CONFIG",save)
 local function stopAll()motion.manual=nil;motion.cancel("ALL TASKS STOPPED");for k in pairs(flags)do flags[k]=false end;for _,render in pairs(toggles)do render()end;local r,h=root();if r and h then h:MoveTo(r.Position)end;save();say("ALL TASKS STOPPED")end
 button(session,"STOP ALL",stopAll)
 local moveButton;moveButton=button(session,"MOVE: "..opts.move,function()
  motion.cancel("MOVEMENT MODE CHANGED")
  opts.move=opts.move=="Walk"and"Teleport"or(opts.move=="Teleport"and"Tween"or"Walk")
  moveButton.Text="MOVE: "..opts.move:upper();save()
 end)
 number(session,"tweenSpeed","TWEEN SPEED (STUDS / SECOND)",8,120)
 number(session,"routeTimeout","ROUTE TIMEOUT (SECONDS)",6,30)
 switch(session,"AUTO JUMP WHEN BLOCKED",function()return opts.autoJump end,function(v)opts.autoJump=v;motion.cancel("JUMP OPTION CHANGED")end)
 text(session,"Walk uses dry paths, jump waypoints and stuck recovery. Tween follows checked paths. Teleport uses a dry landing; blocked routes are skipped.")
 local jobGroup=group(settings,"TASK PRIORITIES")
 text(jobGroup,"Survival → escape → campfire → ready quests → needed drops → crafting / construction → processing → puzzles / chests → gathering → fishing.")
 text(jobGroup,"One action at a time. Critical survival can interrupt travel. Blocked jobs retry later; lower-priority ready jobs gain waiting time.")
 local queueLabel=text(jobGroup,"JOB: IDLE")
 for _,category in ipairs({{"SURVIVAL",{"eat","combat"}},{"GATHER",{"gather","drops"}},{"CAMP",{"fuel","cook","cooked","smelt","smeltCollect","water"}},{"CRAFT",{"craft","build","buildCurrent"}},{"QUESTS",{"quest","daily","weekly","playtime","dailyQuest"}},{"EXPLORE",{"escape","chests","puzzles","travel"}},{"FISHING",{"fish"}}})do
  local categoryName,keys=category[1],category[2]
  button(jobGroup,"STOP "..categoryName,function()for _,key in ipairs(keys)do flags[key]=false;if toggles[key]then toggles[key]()end;if motion.owner==key then motion.cancel("CATEGORY STOPPED")end end;save()end)
 end
 number(session,"interval","ACTION DELAY (SECONDS)",0.2,5)
 local diag=group(settings,"DIAGNOSTICS");button(diag,"CHECK GAME SERVICES",function()local ready={};for _,n in ipairs({"Config","ItemCollect","MakeFire","Furnace","CraftItems","BuildBuilding","MrbeastQuest","ChestService"})do ready[#ready+1]=n..": "..(module(n)and"OK"or"UNAVAILABLE")end;say(table.concat(ready," | "))end)
 local diagnosticText=text(diag,"NO ERRORS RECORDED")
 local function refreshDiagnostics()
  local lines={};for key in pairs(toggles)do lines[#lines+1]=key:upper()..": "..(flags[key]and(taskStatus[key]or"WAITING")or"OFF")end;table.sort(lines)
  diagnosticText.Text="QUEUE: "..tostring(taskStatus.queue or"IDLE").."\nMOVEMENT: "..tostring(motion.owner or"IDLE").."\n"..table.concat(lines,"\n").."\n\nRECENT ERRORS\n"..(#recentErrors>0 and table.concat(recentErrors,"\n")or"NONE")
 end
 button(diag,"COPY DIAGNOSTICS",function()refreshDiagnostics();assert(type(setclipboard)=="function","Clipboard unavailable");setclipboard(diagnosticText.Text);say("DIAGNOSTICS COPIED")end)
 local modeLabel=text(main,"SERVER: CHECKING")
 local clockLabel=text(main,"DAY / PHASE: WAITING")
 connections[#connections+1]=player.OnTeleport:Connect(function(state)
  if not flags.autoExecute or state~=Enum.TeleportState.Started then return end
  local queue=queue_on_teleport or queueonteleport or(syn and syn.queue_on_teleport)
  if type(queue)~="function"then say("TELEPORT QUEUE NOT SUPPORTED");return end
  save();queue('loadstring(game:HttpGet("https://raw.githubusercontent.com/iaxen/EXIScript/main/EXIScript.lua"))()')
 end)
local grip=make("TextButton", {AnchorPoint=Vector2.new(1,1),Position=UDim2.fromScale(1,1),
    Size=UDim2.fromOffset(25,22),BackgroundTransparency=1,Text="◢",TextColor3=blue,
    TextSize=17,Active=true},panel)
local icon=make("TextButton",{Name="OpenEXISIslandEscape",Size=UDim2.fromOffset(32,32),
    Position=UDim2.fromOffset(12,90),BackgroundColor3=Color3.fromRGB(8,15,25),
    Text="EXIS",TextColor3=Color3.fromRGB(240,247,255),Font=Enum.Font.BuilderSansBold,TextSize=10,
    Visible=false,BorderSizePixel=0},screen)
corner(icon,4)
make("UIStroke",{Color=blue,Thickness=1.5},icon)
close.Activated:Connect(function()stopAll();gui:Destroy()end)
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
connections[#connections+1]=UIS.InputChanged:Connect(function(input)
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
connections[#connections+1]=UIS.InputEnded:Connect(function(input)
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
connections[#connections+1]=screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitScreen)
task.defer(fitScreen)
 connections[#connections+1]=player.Idled:Connect(function()if flags.antiAfk then pcall(function()local v=game:GetService("VirtualUser");v:CaptureController();v:ClickButton2(Vector2.new())end)end end)
 gui.Destroying:Connect(function()alive=false;motion.cancel("UI CLOSED");for _,c in ipairs(connections)do c:Disconnect()end;local r,h=root();if r and h then h:MoveTo(r.Position)end end)
 pages.Main.Visible=true;tabButtons.Main.TextColor3=blue;tabButtons.Main.BackgroundColor3=Color3.fromRGB(23,45,71)
 -- Build selections from live configuration, never from guessed item identifiers.
 task.spawn(function()
  local ok,e=pcall(function()
   local c=config()
   local function choices(parent,kind,rows,predicate)
    local g=group(parent,"SELECT "..kind)
    selected[kind]=selected[kind]or{}
    local ids={};for id,info in pairs(rows or{})do if type(info)=="table"and(not predicate or predicate(info))then ids[#ids+1]=id end end;table.sort(ids,function(a,b)return tostring(a)<tostring(b)end)
    local renders={}
    button(g,"SELECT ALL",function()for _,id in ipairs(ids)do selected[kind][id]=true end;for _,r in ipairs(renders)do r()end;save()end)
    button(g,"CLEAR SELECTION",function()selected[kind]={};for _,r in ipairs(renders)do r()end;save()end)
    for index,id in ipairs(ids)do local item=rows[id];local key=id
     renders[#renders+1]=switch(g,itemLabel(kind,id,item,index),function()return selected[kind][key]==true end,function(v)selected[kind][key]=v end)
    end
   end
   choices(resources,"resources",c.worldResource.byId)
   choices(resources,"drops",c.item.byId)
   choices(main,"food",c.food.byId)
   choices(camp,"cook",c.food.byId,function(i)return i.canCook==true end)
   choices(craft,"craft",c.item.byId,function(i)return i.recipeId and(i.type=="tool"or i.type=="armour")end)
   choices(craft,"build",c.build.byId)
   for _,info in ipairs(c.build.list or{})do local name=info.assetId;if type(name)=="string"then button(destination,"GO TO "..itemLabel("building",info.id or name,info),function()local w=world();local b=w and w:FindFirstChild("Buildings");local target=b and(b:FindFirstChild(name)or b:FindFirstChild(name.."_Construct"));if target then motion.manual={target=target};flags.travel=true;say("TRAVEL QUEUED")else say("BUILDING NOT LOADED")end end)end end
  end);if not ok then say(e)end
 end)
 -- Reward data is read from the game's real replicated state.
 local rewardData={};local campData={};local furnaceData={}
 for _,binding in ipairs({{"DailyReward","onSync","daily"},{"WeekReward","onSync","week"},{"PlayTimeReward","sync","play"},{"DailyQuest","sync","quest"}})do
  task.spawn(function()safely("sync "..binding[1],function()call(binding[1],binding[2],function(v)rewardData[binding[3]]=v end)end)end)
 end
 task.spawn(function()
 local function syncRemote(name,fn)local m=RS:FindFirstChild("Engine");m=m and m:FindFirstChild("Service");m=m and m:FindFirstChild(name);local e=m and m:FindFirstChild("syncRemote");if e then connections[#connections+1]=e.OnClientEvent:Connect(fn)end end
 syncRemote("MakeFire",function(v)if type(v)=="table"then campData=v end end);syncRemote("Furnace",function(v)if type(v)=="table"then furnaceData=v end end)
 end)
 task.spawn(function()
  local source=RS.Engine.Service:FindFirstChild("BuildBuilding")
  local event=source and source:WaitForChild("progressChangedRemote",10)
  if alive and event then connections[#connections+1]=event.OnClientEvent:Connect(function(assetId,remaining)
   if type(assetId)=="string"and type(remaining)=="table"then work.buildRemaining[assetId]=remaining;work.refreshAt=0 end
  end)end
 end)
 local function eat()
  local r,h=root();if not r then return end;local hunger=h:GetAttribute("hunger");local max=h:GetAttribute("maxHunger")or 100
  if h.Health/h.MaxHealth*100>opts.health and(not hunger or hunger/max*100>opts.hunger)then return end
  local c=config();for _,t in ipairs(tools())do local info=c.item.byDisplayName[t.Name];if info and allowed("food",info.id)then equip(t);t:Activate();note("eat","FOOD ACTIVATED");return true end end;note("eat","SELECT FOOD YOU OWN")
 end
 local function defend()
  local r,h=root();if not r then return end
  local c=config();local t,tc
  for _,tool in ipairs(tools())do local candidate=c.tool.byDisplayName[tool.Name]
   if candidate and type(candidate.atkDmg)=="number"and candidate.atkDmg>0 and candidate.toolType~="gun"and candidate.toolType~="ranged"and candidate.toolType~="infGun"and(not tc or candidate.atkDmg>tc.atkDmg)then t,tc=tool,candidate end
  end
  if not t then note("combat","MELEE WEAPON REQUIRED");return end
  local mobs={};for _,part in ipairs(workspace:GetPartBoundsInRadius(r.Position,tc.range or 6))do
   local m=part:FindFirstAncestorOfClass("Model");local human=m and m:FindFirstChildOfClass("Humanoid")
   if human and c.mob and c.mob.byId[m.Name] and human.Health>0 and human.Health<10000 and #mobs<(tc.capAOE or 1) and not Players:GetPlayerFromCharacter(m)and not table.find(mobs,m)then mobs[#mobs+1]=m end
  end
  if #mobs>0 then equip(t);RS.Events.meleeHitRemote:FireServer(mobs,{});work.sent=work.sent+1;task.wait(math.max(0.2,tc.useCd or 0.7));say("DEFENDING");return true end
 end
 local function pickups()
  local w=world();local folder=w and w:FindFirstChild("DroppedItems");if not folder then return end
  local c=config();local o=nearest(folder:GetChildren(),function(x)
   local owner=x:GetAttribute("ownerName");local protected=x:GetAttribute("protectEndTick")or 0
   if owner and owner~=player.Name and protected>workspace:GetServerTimeNow()then return false end
   local info=c.item.byDisplayName[x.Name];return not x:GetAttribute("collecting")and info and(selectedEmpty("drops")or allowed("drops",info.id))and not(failed[x]and failed[x]>os.clock())
  end,function(x)local info=c.item.byDisplayName[x.Name];return info and work.needs[info.id]or 0 end)
  if not o then note("drops","NO ELIGIBLE DROPS")end
  if o and travel(o,"drops")then call("ItemCollect","collect",o);failed[o]=os.clock()+5;note("drops","COLLECT REQUEST SENT");say("COLLECT: "..(readable(o.Name)or"ITEM"));return true end
 end
 local function gatherResource()
  local w=world();local static=w and w:FindFirstChild("Static");if not static then note("gather","MATCH RESOURCES NOT LOADED");return end;local c=config();local best=nearest(static:GetChildren(),function(o)return o:IsA("Model")and o:GetAttribute("resourceId") and (selectedEmpty("resources") or allowed("resources",o:GetAttribute("resourceId"))) and not(failed[o]and failed[o]>os.clock())end,function(o)return work.resourceNeeds[o:GetAttribute("resourceId")]or 0 end)
  if not best then note("gather","NO LOADED MATCHING RESOURCES");return end
  local rc=c.worldResource.byId[best:GetAttribute("resourceId")];local tool,tc
  for _,t in ipairs(tools())do local info=c.tool.byDisplayName[t.Name];if info and(rc.requireToolType=="any"or info.toolType==rc.requireToolType)and(not tc or(info.useDmg or 0)>(tc.useDmg or 0))then tool,tc=t,info end end
  if not tool then note("gather","MATCHING TOOL REQUIRED");say("GATHER: MATCHING TOOL REQUIRED");failed[best]=os.clock()+5;return end
  if travel(best,"gather",math.max(1,(tc.range or 6)-0.5))then
   equip(tool);local r=root();if not r then return end
   local p=best:GetPivot().Position;r.CFrame=CFrame.lookAt(r.Position,Vector3.new(p.X,r.Position.Y,p.Z))
   local hp=best:GetAttribute("hp");tool:Activate();task.wait(math.max(0.7,(tc.useCd or 0.7)+0.15))
   if not best.Parent or(type(hp)=="number"and type(best:GetAttribute("hp"))=="number"and best:GetAttribute("hp")<hp)then
    note("gather","RESOURCE DAMAGE CONFIRMED")
   else note("gather","SWING SENT; DAMAGE NOT CONFIRMED");failed[best]=os.clock()+6 end
   say("GATHER: "..itemLabel("resource",best:GetAttribute("resourceId"),rc));return true
  end
 end
 local function exploreTick(key,kind,service,check,request)
  local w=world();if not w then return end;local c=config();local rows=kind=="chest"and c.chest.byId or c.mapProp.byCnId
  local search=kind=="chest"and w:FindFirstChild("Chest")or w
  local obj=nearest(search and search:GetDescendants()or{},function(o)return o:IsA("Model")and rows[o.Name]and not(failed[o]and failed[o]>os.clock())end)
  if not obj then return end;failed[obj]=os.clock()+20
  if call(service,check,obj)then return end
  if kind=="chest"and call(service,"isLocked",obj)then return end
  if travel(obj,key)then call(service,request,obj);note(key,"INTERACTION REQUEST SENT");say(request..": "..(readable(obj.Name)or"OBJECT"));return true end
 end
 local function escapeTick()
  local w=world();if not w then return end
  for _,o in ipairs(w:GetDescendants())do
   if o:IsA("LocalScript")and o.Name=="BoatEscapeClient"then
    local boat=o.Parent;local part=boat:FindFirstChild("promptPart");local prompt=part and part:FindFirstChildOfClass("ProximityPrompt")
    if prompt and prompt.Enabled and travel(part,"escape")then
     assert(type(fireproximityprompt)=="function","Executor prompt support required for the boat")
     fireproximityprompt(prompt,prompt.HoldDuration);due.escape=os.clock()+10;return true
    end
   end
  end
 end
 local function questTick()
  local scene=world();if not scene or not scene:FindFirstChild("Mrbeast",true)then note("quest","QUEST AREA NOT LOADED");return end
  local q=module("MrbeastQuest");if not q then return end;local index,alt,revision=q.client.fetchQuest();local req=index and q.getQuestRequirement(index,alt)
  if not req then questInfo.Text="NO ACTIVE QUEST";return end
  local c=config();local info=c.item.byId[req.itemId];questInfo.Text="NEEDS: "..tostring(req.count).." "..itemLabel("quest item",req.itemId,info or{})
  if not info then return end
  local w=world();local mr=w and w:FindFirstChild("Mrbeast",true);local area=mr and mr:FindFirstChild("SuckArea");local drops=w and w:FindFirstChild("DroppedItems");if not area or not drops then return end
  local owned={};for _,o in ipairs(drops:GetChildren())do if o.Name==info.displayName and o:GetAttribute("ownerName")==player.Name then owned[#owned+1]=o end end
  local held=count(info.displayName);if #owned+held<req.count then return end
  if not travel(area,"quest",1.8)then return end
  task.wait(0.2)
  for _,t in ipairs(tools())do if t.Name==info.displayName then equip(t);break end end
  for _,o in ipairs(owned)do if o.Parent and pos(o)and(pos(o)-area.Position).Magnitude>5 then
   if not travel(o,"quest")then return end;call("ItemCollect","collect",o);task.wait(0.3);return true
  end end
  q.client.submitQuest(owned,revision);note("quest","SUBMISSION REQUEST SENT");task.wait(1);say("QUEST SUBMITTED");return true
 end
 local fish={state="idle",at=0,tool=nil,mini=nil}
 local events=RS:FindFirstChild("Events")
 if events then
  local bite=events:FindFirstChild("fishBiteRemote");if bite then connections[#connections+1]=bite.OnClientEvent:Connect(function(yes)if flags.fish and yes and fish.tool then events.fishReelRemote:FireServer(fish.tool);fish.state="reeling";fish.at=os.clock()end end)end
  local mini=events:FindFirstChild("fishMinigameRemote");if mini then connections[#connections+1]=mini.OnClientEvent:Connect(function(action,token,id,settings)
   if not flags.fish or action~="start"or not fish.tool then return end
   fish.state="minigame";fish.at=os.clock();local source=RS.Engine.Tool.Client:FindFirstChild("FishingMinigame")
   if source then local ok,e=pcall(function()fish.mini=require(source).new(token,settings);fish.mini:start(function(success)if alive and flags.fish then mini:FireServer("result",success,id);fish.state=success and"reeling"or"waiting";fish.at=os.clock()end;fish.mini=nil end)end);if not ok then say(e)end end
  end)end
  local reel=events:FindFirstChild("fishReelRemote");if reel then connections[#connections+1]=reel.OnClientEvent:Connect(function()if flags.fish then fish.state="reeling";fish.at=os.clock()end end)end
  local cancel=events:FindFirstChild("fishCancelRemote");if cancel then connections[#connections+1]=cancel.OnClientEvent:Connect(function()fish.state="idle";fish.at=os.clock()end)end
 end
 connections[#connections+1]=gui.Destroying:Connect(function()
  if fish.mini then pcall(function()fish.mini:cancel()end)end
  if fish.state~="idle"and events and events:FindFirstChild("fishCancelRemote")then pcall(function()events.fishCancelRemote:FireServer()end)end
 end)
 local function fishTick()
  local r=root();if not r or not events then return end
  if fish.state=="minigame"then say("COMPLETE FISH MINIGAME");return true end
  if fish.state=="reeling"and os.clock()-fish.at>4 then fish.state="idle"end
  if fish.state~="idle"then if os.clock()-fish.at>45 then events.fishCancelRemote:FireServer();fish.state="idle"end;return fish.state~="idle"end
  local c=config();local rod
  for _,t in ipairs(tools())do local info=c.tool.byDisplayName[t.Name];if info and info.toolType=="鱼竿"then rod=t;break end end
  if not rod then note("fish","FISHING ROD REQUIRED");return false end
  equip(rod);fish.tool=rod
  local direction=r.CFrame.LookVector*Vector3.new(1,0,1);local p=r.Position+direction.Unit*18
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={workspace.Terrain,world().Tiles};params.IgnoreWater=false
  local hit=workspace:Raycast(p+Vector3.new(0,50,0),Vector3.new(0,-200,0),params)
  if not hit or hit.Material~=Enum.Material.Water then note("fish","FACE WATER TO CAST");return false end
  events.fishVisualRemote:FireServer("castBegin",rod.Name);events.fishCastRemote:FireServer(rod,hit.Position+Vector3.new(0,0.05,0));fish.state="waiting";fish.at=os.clock();say("FISHING: WAITING FOR BITE");return true
 end
 local function limited(key,seconds,fn)
  if not flags[key]or(due[key]and os.clock()<due[key])then return end
  due[key]=os.clock()+seconds
  return safely(key,fn)
 end
 local function craftTick()
  local c=config();if selectedEmpty("craft")then note("craft","SELECT ITEMS FIRST");return end
  for id in pairs(selected.craft or{})do local i=c.item.byId[id];if allowed("craft",id)and i and count(i.displayName)==0 and recipeReady(i)then call("CraftItems","craft",id);note("craft","CRAFT REQUEST SENT");return end end
  note("craft","OWNED ALREADY OR NEED MATERIALS")
 end
 local function buildTick()
  local w=world();local c=config();local b=w and w:FindFirstChild("Buildings")
  if selectedEmpty("build")then note("build","SELECT BUILDINGS FIRST");return end
  for id in pairs(selected.build or{})do local i=c.build.byId[id];if allowed("build",id)and i and b and b:FindFirstChild(i.assetId.."_Construct")then call("BuildBuilding","build",id);note("build","CONTRIBUTION REQUEST SENT");return end end
  note("build","NO SELECTED ACTIVE CONSTRUCTION")
 end
 local function buildCurrentTick()
  local w=world();local folder=w and w:FindFirstChild("Buildings");if not folder then return end
  local c=config()
  for _,i in pairs(c.build.byId)do
   if folder:FindFirstChild(i.assetId.."_Construct")then
    local recipe=c.recipe.byId[i.recipeId];local hasMaterial=false
    for key,n in pairs(recipe or{})do local id=type(key)=="string"and key:match("^require_(.+)$");local item=id and c.item.byId[id]
     if item and type(n)=="number"and work.remaining(i,id,n)>0 and count(item.displayName)>0 then hasMaterial=true;break end
    end
    if hasMaterial then call("BuildBuilding","build",i.id);note("buildCurrent","BLUEPRINT MATERIALS SUBMITTED");return end
   end
  end
  note("buildCurrent","NO ACTIVE BLUEPRINT OR NEED MATERIALS")
 end
 local function foodReady()
  local r,h=root();if not r then return false end
  local hunger=h:GetAttribute("hunger");local max=h:GetAttribute("maxHunger")or 100
  if h.Health/h.MaxHealth*100>opts.health and(not hunger or hunger/max*100>opts.hunger)then return false end
  local c=config();for _,t in ipairs(tools())do local item=c.item.byDisplayName[t.Name];if item and allowed("food",item.id)then return true end end
  return false
 end
 local function enemyReady()
  local r=root();local w=world();local entities=w and w:FindFirstChild("Entities");if not r or not entities then return false end
  local c=config();local weapon=false
  for _,t in ipairs(tools())do local tc=c.tool.byDisplayName[t.Name];if tc and type(tc.atkDmg)=="number"and tc.atkDmg>0 and tc.toolType~="gun"and tc.toolType~="ranged"and tc.toolType~="infGun"then weapon=true;break end end
  if not weapon then return false end
  for _,m in ipairs(entities:GetChildren())do local human=m:FindFirstChildOfClass("Humanoid");local p=pos(m)
   if human and human.Health>0 and p and c.mob and c.mob.byId[m.Name]and(p-r.Position).Magnitude<9 then return true end
  end
  return false
 end
 function work.needItem(id,amount,priority)
  local c=config();local item=c.item.byId[id]
  if item and count(item.displayName)<amount then work.needs[id]=math.max(work.needs[id]or 0,priority)end
 end
 function work.needRecipe(info,priority)
  local c=config();local recipe=c.recipe.byId[info.recipeId]
  for key,n in pairs(recipe or{})do local id=type(key)=="string"and key:match("^require_(.+)$")
   if id and type(n)=="number"and n>0 then work.needItem(id,work.remaining(info,id,n),priority)end
  end
 end
 function work.refreshNeeds()
  if work.refreshAt and os.clock()<work.refreshAt then return end
  work.refreshAt=os.clock()+3;work.needs={};work.resourceNeeds={};local c=config()
  if flags.fuel and built("Campfire")and(campData.campfireWoodCount or 0)<opts.fuel then
   local info=c.build.byId.campfire;local fuel=info and info.config and info.config["燃料"]
   local item=fuel and c.item.byName[fuel];if item then work.needItem(item.id,math.max(1,opts.fuel-(campData.campfireWoodCount or 0)),100)end
  end
  local w=world();local folder=w and w:FindFirstChild("Buildings")
  if folder and(flags.build or flags.buildCurrent)then
   for id,info in pairs(c.build.byId)do if folder:FindFirstChild(info.assetId.."_Construct")and(flags.buildCurrent or allowed("build",id))then work.needRecipe(info,info.assetId=="Campfire"and 95 or 55)end end
  end
  if flags.craft then for id,v in pairs(selected.craft or{})do local item=c.item.byId[id];if v and item and count(item.displayName)==0 then work.needRecipe(item,60)end end end
  if flags.quest then
   local mr=w and w:FindFirstChild("Mrbeast",true)
   work.questRequirement=nil
   if mr then local q=module("MrbeastQuest");if q then local index,alt=q.client.fetchQuest();local req=index and q.getQuestRequirement(index,alt)
    work.questRequirement=req;if req then work.needItem(req.itemId,req.count,80)end
   end end
  else work.questRequirement=nil end
  for id,info in pairs(c.worldResource.byId)do
   local drops=c.itemDrop and c.itemDrop.byId and c.itemDrop.byId[info.dropId]
   for _,entry in pairs(drops or{})do
    if type(entry)=="table"then local item=c.item.byName[entry.itemCN]
     if item then work.resourceNeeds[id]=math.max(work.resourceNeeds[id]or 0,work.needs[item.id]or 0)end
    end
   end
  end
 end
 work.waitReasons={eat="HEALTH / HUNGER OK OR NO SELECTED FOOD",combat="NO NEARBY ENEMY OR NO MELEE WEAPON",travel="NO MANUAL TRAVEL REQUEST",escape="BOAT PROMPT NOT AVAILABLE",fuel="CAMPFIRE MISSING, FUEL READY OR STATE UNKNOWN",quest="NO READY QUEST ITEMS",build="SELECT BUILDING / NEED MATERIALS",buildCurrent="NO ACTIVE BLUEPRINT OR NEED MATERIALS",craft="SELECT ITEMS TO CRAFT",cook="CAMPFIRE MISSING OR NO FOOD SELECTED",cooked="NO READY FOOD / CAMPFIRE MISSING",smelt="BUILD THE FURNACE FIRST",smeltCollect="NO READY OUTPUT / FURNACE MISSING",water="BUILD THE WATER MAKER FIRST"}
 function work.pick(jobs,now)
  local best,bestScore
  for _,job in ipairs(jobs)do
   if flags[job.key]and now>=(due[job.key]or 0)then
    local ok,ready,rank=pcall(function()local ready=not job.ready or job.ready();return ready,ready and(type(job.priority)=="function"and job.priority()or job.priority)or 0 end)
    if not ok then note(job.key,"READINESS ERROR: "..tostring(ready));due[job.key]=now+5;ready=false end
    if ready then
     work.waiting[job.key]=work.waiting[job.key]or now
     local age=job.urgent and 0 or math.min(4,math.max(0,rank-4),(now-work.waiting[job.key])/15)
     local score=rank-age
     if not bestScore or score<bestScore then best,bestScore=job,score end
    else work.waiting[job.key]=nil;if ok then note(job.key,work.waitReasons[job.key]or"WAITING FOR PREREQUISITES")end end
   end
  end
  return best
 end
 motion.pulse=function()
  if flags.combat and os.clock()>=(due.combat or 0)and safely("enemy readiness",enemyReady)==true then return true end
  if not flags.eat or os.clock()<(due.eat or 0)then return false end
  local _,h=root();return h and h.Health/h.MaxHealth<0.3 and safely("food readiness",foodReady)==true
 end
 local function blueprintReady(onlySelected)
  local folder=world()and world():FindFirstChild("Buildings");if not folder then return false end
  local c=config()
  for id,info in pairs(c.build.byId)do
   if(not onlySelected or allowed("build",id))and folder:FindFirstChild(info.assetId.."_Construct")then
    for key,n in pairs(c.recipe.byId[info.recipeId]or{})do local itemId=type(key)=="string"and key:match("^require_(.+)$");local item=itemId and c.item.byId[itemId]
     if item and type(n)=="number"and work.remaining(info,itemId,n)>0 and count(item.displayName)>0 then return true end
    end
   end
  end
  return false
 end
 local function escapeReady()
  local w=world();if not w then return false end
  for _,o in ipairs(w:GetDescendants())do if o:IsA("LocalScript")and o.Name=="BoatEscapeClient"then local part=o.Parent:FindFirstChild("promptPart");local prompt=part and part:FindFirstChildOfClass("ProximityPrompt");if prompt and prompt.Enabled then return true end end end
  return false
 end
 local jobsList={
  {key="eat",priority=0,urgent=true,cooldown=2,ready=foodReady,run=eat},
  {key="combat",priority=1,urgent=true,cooldown=0.5,ready=enemyReady,run=defend},
  {key="travel",priority=2,cooldown=0.2,ready=function()return motion.manual~=nil end,run=function()
   local request=motion.manual;motion.manual=nil;if request then travel(request.target,"travel")end;flags.travel=false;return true
  end},
  {key="escape",priority=2.5,cooldown=4,ready=escapeReady,run=escapeTick},
  {key="fuel",priority=function()local w=world();local phase=w and w:FindFirstChild("Phase");return phase and tostring(phase.Value):lower():find("night")and 2.8 or 3.5 end,cooldown=4,
   ready=function()return built("Campfire")and type(campData.campfireWoodCount)=="number"and campData.campfireWoodCount<opts.fuel end,run=function()return call("MakeFire","addWood")end},
  {key="buildCurrent",priority=function()return built("Campfire")and 8 or 3.2 end,cooldown=4,ready=function()return blueprintReady(false)end,run=buildCurrentTick},
  {key="quest",priority=4,cooldown=3,ready=function()
   local req=work.questRequirement;if not req then return false end
   local c=config();local info=c.item.byId[req.itemId];if not info then return false end
   local w=world();local folder=w and w:FindFirstChild("DroppedItems");local n=count(info.displayName)
   if folder then for _,o in ipairs(folder:GetChildren())do if o.Name==info.displayName and o:GetAttribute("ownerName")==player.Name then n=n+1 end end end
   return n>=req.count
  end,run=questTick},
  {key="drops",priority=function()return next(work.needs)and 4.8 or 7 end,cooldown=0.4,run=pickups},
  {key="cooked",priority=5,cooldown=3,ready=function()return built("Campfire")and(campData.readyCount or 0)>0 end,run=function()return call("MakeFire","collectFood")end},
  {key="craft",priority=6,cooldown=3,ready=function()return not selectedEmpty("craft")end,run=craftTick},
  {key="build",priority=function()return built("Campfire")and 8 or 3.3 end,cooldown=4,ready=function()return not selectedEmpty("build")and blueprintReady(true)end,run=buildTick},
  {key="cook",priority=8,cooldown=4,ready=function()return built("Campfire")and not selectedEmpty("cook")end,run=function()
   local c=config();for id in pairs(selected.cook or{})do local i=c.item.byId[id];if allowed("cook",id)and i and count(i.displayName)>0 then return call("MakeFire","addFood",id)end end;note("cook","NO SELECTED FOOD IN BAG")
  end},
  {key="smeltCollect",priority=8.5,cooldown=3,ready=function()return built("Furnace")and(furnaceData.readyCount or 0)>0 end,run=function()return call("Furnace","collectResult")end},
  {key="water",priority=9,cooldown=10,ready=function()return built("Water Maker")~=nil end,run=function()return call("WaterMaker","collect")end},
  {key="smelt",priority=9.5,cooldown=5,ready=function()return built("Furnace")~=nil end,run=function()return call("Furnace","addBoth")end},
  {key="puzzles",priority=10,cooldown=3,run=function()return exploreTick("puzzles","puzzle","PuzzlePropService","isSolved","requestSolve")end},
  {key="chests",priority=11,cooldown=3,run=function()return exploreTick("chests","chest","ChestService","isOpened","requestOpen")end},
  {key="gather",priority=function()return next(work.needs)and 6.5 or 12 end,cooldown=0.3,run=gatherResource},
  {key="fish",priority=14,cooldown=2,run=fishTick},
 }
 local function cancelFishing()
  if fish.mini then fish.mini:cancel();fish.mini=nil end
  if fish.state~="idle"and events and events:FindFirstChild("fishCancelRemote")then events.fishCancelRemote:FireServer()end
  fish.state="idle";fish.tool=nil;due.fish=os.clock()+3
 end
 local function claimRewards()
  limited("daily",10,function()if rewardData.daily=="canClaim"then call("DailyReward","claim")else note("daily","NOT CLAIMABLE")end end)
  limited("weekly",10,function()for i,v in pairs((rewardData.week or{}).days or{})do if v=="Claim"then call("WeekReward","claim",i);return end end;note("weekly","NOT CLAIMABLE")end)
  limited("playtime",10,function()for id,v in pairs((rewardData.play or{}).rewards or{})do if v.canClaim and not v.claimed then call("PlayTimeReward","claim",id);return end end;note("playtime","NOT CLAIMABLE")end)
  limited("dailyQuest",10,function()for _,v in pairs((rewardData.quest or{}).list or{})do if v.completed and not v.claimed then call("DailyQuest","claim",v.id);return end end;note("dailyQuest","NO COMPLETED REWARDS")end)
 end
 task.spawn(function()
  while alive do
   local ok,e=pcall(function()
    safely("clock",function()local w=world();if w then local d=w:FindFirstChild("Day");local phase=w:FindFirstChild("Phase");clockLabel.Text="DAY "..tostring(d and d.Value or"—").." | "..tostring(phase and phase.Value or"—")end end)
    local mode=serverMode();modeLabel.Text=mode=="match"and"SERVER: MATCH"or(mode=="lobby"and"SERVER: LOBBY - ENTER A MATCH"or"SERVER: LOADING")
    claimRewards()
    if mode~="match"then
     for _,job in ipairs(jobsList)do if flags[job.key]then note(job.key,"ENTER A MATCH FIRST")end end
     if fish.state~="idle"then cancelFishing()end;return
    end
    safely("material planning",work.refreshNeeds)
    local now=os.clock();local job=safely("queue readiness",function()return work.pick(jobsList,now)end)
    if fish.state~="idle"and flags.fish then
     -- Do not interrupt an active minigame for routine chores.
     local urgent=job and(job.key=="eat"or job.key=="combat"or job.key=="escape"or job.key=="fuel")
     if not urgent then safely("fish",fishTick);return end
     cancelFishing()
    elseif fish.state~="idle"then cancelFishing()end
    if not job then queueLabel.Text="JOB: WAITING";note("queue","WAITING FOR READY JOBS");return end
    work.active=job.key;queueLabel.Text="JOB: "..job.key:upper();note("queue","ACTIVE: "..job.key:upper());local before=work.sent
    local result=safely(job.key,job.run)
    local acted=result==true or work.sent>before
    due[job.key]=os.clock()+(acted and job.cooldown or math.max(2,job.cooldown))
    work.waiting[job.key]=nil;work.active=nil;queueLabel.Text="LAST JOB: "..job.key:upper()
    if not acted then note("queue",job.key:upper().." WAITING; OTHER JOBS CAN RUN")end
   end)
   if not ok then note("queue","ERROR: "..tostring(e));say(e);work.active=nil;motion.cancel("JOB ERROR")end
   refreshDiagnostics();task.wait(math.max(0.2,opts.interval))
  end
 end)

 say("ISLAND ESCAPE LOADED • CONFIG SAVED PER GAME")
end

runIslandEscape()
