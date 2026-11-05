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
 local opts={move="Teleport",interval=0.7,health=50,hunger=40,fuel=3}
 local path="exis_island_"..player.UserId.."_"..game.PlaceId..".json"
 local blue=Color3.fromRGB(83,158,244);local white=Color3.fromRGB(226,234,245)
 local function make(class,props,parent)local o=Instance.new(class);for k,v in pairs(props)do o[k]=v end;o.Parent=parent;return o end
 local function round(o)make("UICorner",{CornerRadius=UDim.new(0,6)},o)end
 local size=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800,600)
 local panel=make("Frame",{Size=UDim2.fromOffset(math.min(390,size.X-16),math.min(290,size.Y-20)),Position=UDim2.fromOffset(12,40),BackgroundColor3=Color3.fromRGB(9,14,22),BorderSizePixel=0,ClipsDescendants=true},gui);round(panel)
 make("UIStroke",{Color=Color3.fromRGB(45,76,112),Thickness=1},panel)
 local head=make("TextLabel",{Size=UDim2.new(1,-60,0,30),Text="  EXIScript | MrbeastIslandEscape",TextSize=11,Font=Enum.Font.BuilderSansBold,TextColor3=blue,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,Active=true},panel)
 local function button(parent,text,fn)
  local b=make("TextButton",{Size=UDim2.new(1,0,0,27),Text=text:upper(),TextSize=11,Font=Enum.Font.BuilderSansMedium,TextColor3=white,BackgroundColor3=Color3.fromRGB(20,33,50),BorderSizePixel=0},parent);round(b)
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
  if type(d.options)=="table"then if d.options.move=="Walk"or d.options.move=="Teleport"then opts.move=d.options.move end;for _,k in ipairs({"interval","health","hunger","fuel"})do local n=tonumber(d.options[k]);if n and n==n and n>=0 and n<10000 then opts[k]=n end end end
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
 local function travel(o,key,radius)
  local r,h=root();local p=typeof(o)=="Vector3"and o or pos(o);if not r or not p then note(key,"CHARACTER OR TARGET NOT READY");return false end
  radius=radius or 6
  local distance=(r.Position-p).Magnitude
  if distance<=radius then return true end
  if opts.move=="Teleport"then r.CFrame=CFrame.lookAt(p+Vector3.new(math.min(2,radius/2),0.5,0),p);task.wait(0.2);return alive and flags[key]==true end
  note(key,"WALKING TO TARGET");h:MoveTo(p);local started=os.clock()
  repeat task.wait(0.1);r,h=root();if not alive or not flags[key]or not r then return false end until (r.Position-p).Magnitude<=radius or os.clock()-started>=2
  return (r.Position-p).Magnitude<=radius
 end
 local function tools()local t={};for _,p in ipairs({player:FindFirstChild("Backpack"),player.Character})do if p then for _,o in ipairs(p:GetChildren())do if o:IsA("Tool")then t[#t+1]=o end end end end;return t end
 local function count(name)local n=0;for _,o in ipairs(tools())do if o.Name==name then n=n+(o:GetAttribute("count")or 1)end end;return n end
 local function equip(t)local _,h=root();if h and t.Parent~=player.Character then h:EquipTool(t);task.wait(0.15)end end
 local function nearest(list,predicate)local r=root();if not r then return end;local best,d=nil,math.huge;for _,o in ipairs(list)do if o.Parent and predicate(o)then local p=pos(o);if p then local n=(p-r.Position).Magnitude;if n<d then best,d=o,n end end end end;return best end
 local function config()local m=module("Config");assert(m,"Game config unavailable");return m end
 local function allowed(kind,id)return type(selected[kind])=="table"and selected[kind][id]==true end
 local function selectedEmpty(kind)for _,v in pairs(selected[kind]or{})do if v==true then return false end end;return true end
 local function recipeReady(info)
  local c=config();local recipe=c.recipe.byId[info.recipeId];if not recipe then return false end
  for k,n in pairs(recipe)do local id=type(k)=="string"and k:match("^require_(.+)$");if id and type(n)=="number"and n>0 then local item=c.item.byId[id];if not item or count(item.displayName)<n then return false end end end;return true
 end
 local pages={};local groups={};local toggles={};local tabButtons={}
 local nav=make("ScrollingFrame",{Position=UDim2.fromOffset(0,30),Size=UDim2.new(0,82,1,-30),BackgroundColor3=Color3.fromRGB(13,20,30),BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ScrollBarThickness=2},panel)
 make("UIListLayout",{Padding=UDim.new(0,3)},nav)
 local function page(name)
  local p=make("ScrollingFrame",{Position=UDim2.fromOffset(90,33),Size=UDim2.new(1,-98,1,-56),BackgroundTransparency=1,BorderSizePixel=0,Visible=false,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ScrollBarThickness=2},panel)
  make("UIListLayout",{Padding=UDim.new(0,5)},p);pages[name]=p
  local b=button(nav,name,function()for n,f in pairs(pages)do f.Visible=n==name;tabButtons[n].TextColor3=n==name and blue or white end end);tabButtons[name]=b;return p
 end
 local function text(p,t)return make("TextLabel",{Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=t,TextSize=11,TextWrapped=true,Font=Enum.Font.BuilderSans,TextColor3=Color3.fromRGB(164,181,202),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left},p)end
 local function group(p,name)
  local f=make("Frame",{Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(16,24,35),BorderSizePixel=0},p);round(f);make("UIStroke",{Color=Color3.fromRGB(35,53,76),Thickness=1},f);make("UIListLayout",{},f)
  local body=make("Frame",{LayoutOrder=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Visible=false,BackgroundTransparency=1},f);make("UIListLayout",{Padding=UDim.new(0,3)},body);make("UIPadding",{PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5),PaddingBottom=UDim.new(0,5)},body)
  local b
  b=button(f,name.."  ›",function()local open=not body.Visible;for _,g in ipairs(groups)do if g.frame.Parent==f.Parent then g.body.Visible=false;g.button.Text=g.name.."  ›"end end;body.Visible=open;b.Text=name:upper()..(open and "  ⌄"or"  ›")end)
  -- The callback resolves the stored entry after construction.
  local entry={frame=f,body=body,button=b,name=name:upper()};groups[#groups+1]=entry;b.LayoutOrder=0
  return body,entry
 end
 local function switch(p,label,get,set)
  local b=button(p,"",function()set(not get());save()end)
  make("TextLabel",{Position=UDim2.fromOffset(7,0),Size=UDim2.new(1,-47,1,0),Text=label:upper(),TextSize=11,
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
 local function stopAll()for k in pairs(flags)do flags[k]=false end;for _,render in pairs(toggles)do render()end;local r,h=root();if r and h then h:MoveTo(r.Position)end;save();say("ALL TASKS STOPPED")end
 button(session,"STOP ALL",stopAll)
 local moveButton;moveButton=button(session,"MOVE: "..opts.move,function()opts.move=opts.move=="Walk"and"Teleport"or"Walk";moveButton.Text="MOVE: "..opts.move:upper();save()end)
 number(session,"interval","ACTION DELAY (SECONDS)",0.2,5)
 local diag=group(settings,"DIAGNOSTICS");button(diag,"CHECK GAME SERVICES",function()local ready={};for _,n in ipairs({"Config","ItemCollect","MakeFire","Furnace","CraftItems","BuildBuilding","MrbeastQuest","ChestService"})do ready[#ready+1]=n..": "..(module(n)and"OK"or"UNAVAILABLE")end;say(table.concat(ready," | "))end)
 local diagnosticText=text(diag,"NO ERRORS RECORDED")
 local function refreshDiagnostics()
  local lines={};for key in pairs(toggles)do lines[#lines+1]=key:upper()..": "..(flags[key]and(taskStatus[key]or"WAITING")or"OFF")end;table.sort(lines)
  diagnosticText.Text=table.concat(lines,"\n").."\n\nRECENT ERRORS\n"..(#recentErrors>0 and table.concat(recentErrors,"\n")or"NONE")
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
 local launcher=button(gui,"EXIS",function()panel.Visible=true;launcher.Visible=false end);launcher.Size=UDim2.fromOffset(32,32);launcher.TextSize=10;launcher.Font=Enum.Font.BuilderSansBold;launcher:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(0,4);launcher.Position=UDim2.fromOffset(12,90);launcher.Visible=false
 local mini=button(panel,"−",function()panel.Visible=false;launcher.Visible=true end);mini.Position=UDim2.new(1,-55,0,3);mini.Size=UDim2.fromOffset(24,24)
 local close=button(panel,"×",function()stopAll();gui:Destroy()end);close.Position=UDim2.new(1,-28,0,3);close.Size=UDim2.fromOffset(24,24)
 local dragging,start,origin
 head.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=i;start=i.Position;origin=panel.Position end end)
 connections[#connections+1]=UIS.InputChanged:Connect(function(i)if dragging and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-start;panel.Position=UDim2.fromOffset(math.clamp(origin.X.Offset+d.X,0,math.max(0,workspace.CurrentCamera.ViewportSize.X-panel.AbsoluteSize.X)),math.max(0,origin.Y.Offset+d.Y))end end)
 connections[#connections+1]=UIS.InputEnded:Connect(function(i)if i==dragging or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=nil end end)
 connections[#connections+1]=player.Idled:Connect(function()if flags.antiAfk then pcall(function()local v=game:GetService("VirtualUser");v:CaptureController();v:ClickButton2(Vector2.new())end)end end)
 gui.Destroying:Connect(function()alive=false;for _,c in ipairs(connections)do c:Disconnect()end;local r,h=root();if r and h then h:MoveTo(r.Position)end end)
 pages.Main.Visible=true
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
   for _,info in ipairs(c.build.list or{})do local name=info.assetId;if type(name)=="string"then button(destination,"GO TO "..itemLabel("building",info.id or name,info),function()flags.travel=true;task.spawn(function()local w=world();local b=w and w:FindFirstChild("Buildings");local target=b and(b:FindFirstChild(name)or b:FindFirstChild(name.."_Construct"));if target then travel(target,"travel")else say("BUILDING NOT LOADED")end;flags.travel=false end)end)end end
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
 local function eat()
  local r,h=root();if not r then return end;local hunger=h:GetAttribute("hunger");local max=h:GetAttribute("maxHunger")or 100
  if h.Health/h.MaxHealth*100>opts.health and(not hunger or hunger/max*100>opts.hunger)then return end
  local c=config();for _,t in ipairs(tools())do local info=c.item.byDisplayName[t.Name];if info and allowed("food",info.id)then equip(t);t:Activate();note("eat","FOOD ACTIVATED");return end end;note("eat","SELECT FOOD YOU OWN")
 end
 local function defend()
  local r,h=root();if not r then return end
  local t=player.Character:FindFirstChildOfClass("Tool");if not t then return end
  local c=config();local tc=c.tool.byDisplayName[t.Name];if not tc or tc.toolType=="gun"or tc.toolType=="ranged"then return end
  local mobs={};for _,part in ipairs(workspace:GetPartBoundsInRadius(r.Position,tc.range or 6))do
   local m=part:FindFirstAncestorOfClass("Model");local human=m and m:FindFirstChildOfClass("Humanoid")
   if human and c.mob and c.mob.byId[m.Name] and human.Health>0 and human.Health<10000 and #mobs<(tc.capAOE or 1) and not Players:GetPlayerFromCharacter(m)and not table.find(mobs,m)then mobs[#mobs+1]=m end
  end
  if #mobs>0 and(not due.combat or os.clock()>due.combat)then due.combat=os.clock()+math.max(0.2,tc.useCd or 0.7);RS.Events.meleeHitRemote:FireServer(mobs,{});say("DEFENDING")end
 end
 local function pickups()
  local w=world();local folder=w and w:FindFirstChild("DroppedItems");if not folder then return end
  local c=config();local o=nearest(folder:GetChildren(),function(x)
   local owner=x:GetAttribute("ownerName");local protected=x:GetAttribute("protectEndTick")or 0
   if owner and owner~=player.Name and protected>workspace:GetServerTimeNow()then return false end
   local info=c.item.byDisplayName[x.Name];return not x:GetAttribute("collecting")and info and(selectedEmpty("drops")or allowed("drops",info.id))and not(failed[x]and failed[x]>os.clock())
  end)
  if not o then note("drops","NO ELIGIBLE DROPS")end
  if o and travel(o,"drops")then call("ItemCollect","collect",o);failed[o]=os.clock()+5;note("drops","COLLECT REQUEST SENT");say("COLLECT: "..(readable(o.Name)or"ITEM"));return true end
 end
 local function gatherResource()
  local w=world();local static=w and w:FindFirstChild("Static");if not static then note("gather","MATCH RESOURCES NOT LOADED");return end;local c=config();local best=nearest(static:GetChildren(),function(o)return o:IsA("Model")and o:GetAttribute("resourceId") and (selectedEmpty("resources") or allowed("resources",o:GetAttribute("resourceId"))) and not(failed[o]and failed[o]>os.clock())end)
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
   else note("gather","SWING SENT; DAMAGE NOT CONFIRMED")end
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
  if not travel(area,"quest")then return end
  local r=root();r.CFrame=CFrame.new(area.Position+Vector3.new(0,2,0));task.wait(0.2)
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
 local movementTurn=0
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
     if item and type(n)=="number"and n>0 and count(item.displayName)>0 then hasMaterial=true;break end
    end
    if hasMaterial then call("BuildBuilding","build",i.id);note("buildCurrent","BLUEPRINT MATERIALS SUBMITTED");return end
   end
  end
  note("buildCurrent","NO ACTIVE BLUEPRINT OR NEED MATERIALS")
 end
 local moves={
  {"quest",questTick},{"escape",escapeTick},
  {"chests",function()return exploreTick("chests","chest","ChestService","isOpened","requestOpen")end},
  {"puzzles",function()return exploreTick("puzzles","puzzle","PuzzlePropService","isSolved","requestSolve")end},
  {"drops",pickups},{"gather",gatherResource},
 }
 task.spawn(function()
  while alive do
   safely("clock",function()local w=world();if w then local d=w:FindFirstChild("Day");local phase=w:FindFirstChild("Phase");clockLabel.Text="DAY "..tostring(d and d.Value or"—").." | "..tostring(phase and phase.Value or"—")end end)
   local mode=serverMode();modeLabel.Text=mode=="match"and"SERVER: MATCH"or(mode=="lobby"and"SERVER: LOBBY - ENTER A MATCH"or"SERVER: LOADING")
   if mode=="match"then limited("eat",2,eat);limited("combat",opts.interval,defend)end
   -- Failed reward calls cannot abort camp jobs or movement workers.
   limited("daily",10,function()if rewardData.daily=="canClaim"then call("DailyReward","claim")else note("daily","NOT CLAIMABLE")end end)
   limited("weekly",10,function()for i,v in pairs((rewardData.week or{}).days or{})do if v=="Claim"then call("WeekReward","claim",i);return end end;note("weekly","NOT CLAIMABLE")end)
   limited("playtime",10,function()for id,v in pairs((rewardData.play or{}).rewards or{})do if v.canClaim and not v.claimed then call("PlayTimeReward","claim",id);return end end;note("playtime","NOT CLAIMABLE")end)
   limited("dailyQuest",10,function()for _,v in pairs((rewardData.quest or{}).list or{})do if v.completed and not v.claimed then call("DailyQuest","claim",v.id);return end end;note("dailyQuest","NO COMPLETED REWARDS")end)
   if mode=="match"then
   limited("fuel",4,function()
    if not built("Campfire")then note("fuel","BUILD THE CAMPFIRE FIRST");return end
    if type(campData.campfireWoodCount)~="number"then note("fuel","WAITING FOR CAMPFIRE STATE")elseif campData.campfireWoodCount<opts.fuel then call("MakeFire","addWood")else note("fuel","FUEL TARGET REACHED")end end)
   limited("cooked",3,function()if not built("Campfire")then note("cooked","BUILD THE CAMPFIRE FIRST");return end;if(campData.readyCount or 0)>0 then call("MakeFire","collectFood")else note("cooked","NO READY FOOD / WAITING FOR STATE")end end)
   limited("cook",4,function()if not built("Campfire")then note("cook","BUILD THE CAMPFIRE FIRST");return end;local c=config();for id in pairs(selected.cook or{})do local i=c.item.byId[id];if allowed("cook",id)and i and count(i.displayName)>0 then call("MakeFire","addFood",id);return end end;note("cook","SELECT COOKABLE FOOD YOU OWN")end)
   limited("smeltCollect",3,function()if not built("Furnace")then note("smeltCollect","BUILD THE FURNACE FIRST");return end;if(furnaceData.readyCount or 0)>0 then call("Furnace","collectResult")else note("smeltCollect","NO READY OUTPUT / WAITING FOR STATE")end end)
   limited("smelt",5,function()if not built("Furnace")then note("smelt","BUILD THE FURNACE FIRST");return end;call("Furnace","addBoth")end)
   limited("water",10,function()if not built("Water Maker")then note("water","BUILD THE WATER MAKER FIRST");return end;call("WaterMaker","collect")end)
   limited("craft",3,craftTick);limited("build",5,buildTick);limited("buildCurrent",4,buildCurrentTick)
   local fishingActive=false
   if flags.fish then fishingActive=safely("fish",fishTick)==true
   elseif fish.state~="idle"then safely("fish",function()if fish.mini then fish.mini:cancel();fish.mini=nil end;if events and events:FindFirstChild("fishCancelRemote")then events.fishCancelRemote:FireServer()end;fish.state="idle"end)end
   if not fishingActive and not flags.travel then
    -- One bounded movement action per loop; every enabled worker gets a turn.
    for _=1,#moves do movementTurn=movementTurn%#moves+1;local job=moves[movementTurn]
     if flags[job[1]]then safely(job[1],job[2]);break end
    end
   end
   else
    for _,key in ipairs({"eat","combat","fuel","cook","cooked","smelt","smeltCollect","water","craft","build","buildCurrent","quest","escape","chests","puzzles","drops","gather","fish"})do if flags[key]then note(key,"ENTER A MATCH FIRST")end end
   end
   refreshDiagnostics()
   task.wait(math.max(0.2,opts.interval))
  end
 end)
 say("ISLAND ESCAPE LOADED • CONFIG SAVED PER GAME")
end

runIslandEscape()
