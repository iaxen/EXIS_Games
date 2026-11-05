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
 local alive=true;local connections={};local flags={};local selected={};local modules={};local failed={};local due={}
 local opts={move="Walk",interval=0.7,health=50,hunger=40,fuel=3}
 local path="exis_island_"..player.UserId.."_"..game.PlaceId..".json"
 local blue=Color3.fromRGB(83,158,244);local white=Color3.fromRGB(226,234,245)
 local function make(class,props,parent)local o=Instance.new(class);for k,v in pairs(props)do o[k]=v end;o.Parent=parent;return o end
 local function round(o)make("UICorner",{CornerRadius=UDim.new(0,6)},o)end
 local size=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800,600)
 local panel=make("Frame",{Size=UDim2.fromOffset(math.min(390,size.X-16),math.min(290,size.Y-20)),Position=UDim2.fromOffset(12,40),BackgroundColor3=Color3.fromRGB(9,14,22),BorderSizePixel=0,ClipsDescendants=true},gui);round(panel)
 make("UIStroke",{Color=Color3.fromRGB(45,76,112),Thickness=1},panel)
 local head=make("TextLabel",{Size=UDim2.new(1,-60,0,30),Text="  EXIScript | MrbeastIslandEscape",TextSize=11,Font=Enum.Font.BuilderSansBold,TextColor3=blue,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,Active=true},panel)
 local function button(parent,text,fn)
  local b=make("TextButton",{Size=UDim2.new(1,0,0,27),Text=text:upper(),TextSize=10,Font=Enum.Font.BuilderSansMedium,TextColor3=white,BackgroundColor3=Color3.fromRGB(20,33,50),BorderSizePixel=0},parent);round(b)
  b.Activated:Connect(function()local ok,e=pcall(fn);if not ok then warn("EXIScript: "..tostring(e))end end);return b
 end
 local status=make("TextLabel",{Position=UDim2.new(0,90,1,-20),Size=UDim2.new(1,-95,0,18),Text="READY",TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,Font=Enum.Font.BuilderSans,TextColor3=blue,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left},panel)
 local function say(s)status.Text=tostring(s)end
 local function save()if type(writefile)=="function"then local ok,e=pcall(function()writefile(path,HTTP:JSONEncode({version=1,flags=flags,selected=selected,options=opts}))end);if not ok then say(e)end end end
 if type(readfile)=="function"then pcall(function()local d=HTTP:JSONDecode(readfile(path));if d.version==1 then
  if type(d.flags)=="table"then for k,v in pairs(d.flags)do if type(v)=="boolean"then flags[k]=v end end end
  if type(d.selected)=="table"then selected=d.selected end
  if type(d.options)=="table"then if d.options.move=="Walk"or d.options.move=="Teleport"then opts.move=d.options.move end;for _,k in ipairs({"interval","health","hunger","fuel"})do local n=tonumber(d.options[k]);if n and n==n and n>=0 and n<10000 then opts[k]=n end end end
 end end)end
 local function module(name)
  if modules[name]then return modules[name]end
  if failed[name]and os.clock()-failed[name]<15 then return end
  local engine=RS:FindFirstChild("Engine");local lib=RS:FindFirstChild("Module")
  local source=(engine and engine:FindFirstChild("Service")and engine.Service:FindFirstChild(name))or(lib and lib:FindFirstChild("Service")and lib.Service:FindFirstChild(name))
  if not source then failed[name]=os.clock();return end
  local ok,m=pcall(require,source);if ok then modules[name]=m;return m end
  failed[name]=os.clock();say(name.." unavailable")
 end
 local function call(name,action,...)
  local m=module(name);assert(m and m.client and type(m.client[action])=="function",name.."."..action.." unavailable")
  return m.client[action](...)
 end
 local function world()return workspace:FindFirstChild("Game")end
 local function root()local c=player.Character;local h=c and c:FindFirstChildOfClass("Humanoid");return h and h.Health>0 and c:FindFirstChild("HumanoidRootPart"),h end
 local function pos(o)if o:IsA("BasePart")then return o.Position elseif o:IsA("Model")then return o:GetPivot().Position end end
 local function travel(o,key)
  local r,h=root();local p=typeof(o)=="Vector3"and o or pos(o);if not r or not p then return false end
  local distance=(r.Position-p).Magnitude
  if distance<=6 then return true end
  if opts.move=="Teleport"then r.CFrame=CFrame.lookAt(p+Vector3.new(3,2,3),p);task.wait(0.2);return alive and flags[key]==true end
  h:MoveTo(p);local started=os.clock()
  repeat task.wait(0.1);r,h=root();if not alive or not flags[key]or not r then return false end until (r.Position-p).Magnitude<=6 or os.clock()-started>=2
  return (r.Position-p).Magnitude<=6
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
 local function text(p,t)return make("TextLabel",{Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=t,TextSize=10,TextWrapped=true,Font=Enum.Font.BuilderSans,TextColor3=Color3.fromRGB(164,181,202),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left},p)end
 local function group(p,name)
  local f=make("Frame",{Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=Color3.fromRGB(16,24,35),BorderSizePixel=0},p);round(f);make("UIStroke",{Color=Color3.fromRGB(35,53,76),Thickness=1},f);make("UIListLayout",{},f)
  local body=make("Frame",{LayoutOrder=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Visible=false,BackgroundTransparency=1},f);make("UIListLayout",{Padding=UDim.new(0,3)},body);make("UIPadding",{PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5),PaddingBottom=UDim.new(0,5)},body)
  local b
  b=button(f,name.."  ›",function()local open=not body.Visible;for _,g in ipairs(groups)do if g.frame.Parent==f.Parent then g.body.Visible=false;g.button.Text=g.name.."  ›"end end;body.Visible=open;b.Text=name:upper()..(open and "  ⌄"or"  ›")end)
  -- The callback resolves the stored entry after construction.
  local entry={frame=f,body=body,button=b,name=name:upper()};groups[#groups+1]=entry;b.LayoutOrder=0
  return body,entry
 end
 local function toggle(p,key,label,description)
  local b=button(p,"",function()flags[key]=not flags[key];toggles[key]();save()end)
  toggles[key]=function()b.Text=(flags[key]and"●  "or"○  ")..label:upper();b.TextColor3=flags[key]and blue or white end;toggles[key]();if description then text(p,description)end
 end
 local function number(p,key,label,min,max)
  text(p,label);local b=make("TextBox",{Size=UDim2.new(1,0,0,26),Text=tostring(opts[key]),ClearTextOnFocus=false,TextSize=11,Font=Enum.Font.BuilderSans,TextColor3=white,BackgroundColor3=Color3.fromRGB(21,32,47)},p);round(b)
  b.FocusLost:Connect(function()local n=tonumber(b.Text);if n and n==n and n<math.huge then opts[key]=math.clamp(n,min,max);save()end;b.Text=tostring(opts[key])end)
 end
 local main=page("Main");local resources=page("Gather");local camp=page("Camp");local craft=page("Craft");local questPage=page("Quests");local explore=page("Explore");local settings=page("Settings")
 local survival=group(main,"SURVIVAL")
 toggle(survival,"eat","Auto eat","Uses selected food below when health or hunger is low. No food selected = disabled.")
 number(survival,"health","HEALTH BELOW (%)",1,100);number(survival,"hunger","HUNGER BELOW (%)",1,100)
 local combat=group(main,"DEFENCE")
 toggle(combat,"combat","Auto defend against nearby enemies","Uses your equipped melee tool on nearby NPCs. Never targets players.")
 local fishing=group(main,"FISHING")
 toggle(fishing,"fish","Auto cast and reel","Equip a rod and face water. Casts and reels automatically; complete the fish minigame normally. Pauses movement jobs.")
 local gather=group(resources,"RESOURCE FARMING")
 toggle(gather,"gather","Auto gather selected resources","Uses a matching owned tool. Choose resources below.")
 local drops=group(resources,"DROPPED ITEMS")
 toggle(drops,"drops","Auto collect drops","All unprotected drops when no items are selected below. Respects owner protection.")
 local fire=group(camp,"CAMPFIRE")
 toggle(fire,"fuel","Auto add wood","Adds wood only below the fuel target.");number(fire,"fuel","FUEL TARGET (WOOD)",1,100)
 toggle(fire,"cook","Auto cook selected food","Consumes selected cookable food.")
 toggle(fire,"cooked","Auto collect cooked food")
 local furnace=group(camp,"FURNACE")
 toggle(furnace,"smelt","Auto feed furnace","Consumes smelting ingredients.");toggle(furnace,"smeltCollect","Auto collect results")
 local water=group(camp,"WATER MAKER");toggle(water,"water","Auto collect coconuts")
 local crafting=group(craft,"TOOLS AND ARMOUR");toggle(crafting,"craft","Auto craft selected items","Crafts one missing selected item when materials are available.")
 local building=group(craft,"CONSTRUCTION");toggle(building,"build","Auto contribute selected buildings","Spends recipe materials on selected unfinished buildings.")
 local questBody=group(questPage,"MRBEAST QUESTS");toggle(questBody,"quest","Auto deliver required items","Moves owned matching drops or carried items into the quest area. Submits the current revision only.")
 local questInfo=text(questBody,"QUEST: WAITING")
 local rewards=group(questPage,"REWARDS");toggle(rewards,"daily","Auto daily reward");toggle(rewards,"weekly","Auto weekly reward");toggle(rewards,"playtime","Auto playtime rewards");toggle(rewards,"dailyQuest","Claim completed daily quests")
 local chestUI=group(explore,"CHESTS AND PUZZLES");toggle(chestUI,"chests","Auto open unlocked chests");toggle(chestUI,"puzzles","Auto interact with puzzle props")
 local escape=group(explore,"ESCAPE BOAT")
 toggle(escape,"escape","Auto use available escape boat","Uses the boat interaction when its prompt is enabled. Ends your run.")
 local destination=group(explore,"BUILDING TRAVEL")
 local session=group(settings,"SESSION")
 toggle(session,"antiAfk","Anti idle");button(session,"SAVE CONFIG",save)
 local function stopAll()for k in pairs(flags)do flags[k]=false end;for _,render in pairs(toggles)do render()end;local r,h=root();if r and h then h:MoveTo(r.Position)end;save();say("ALL TASKS STOPPED")end
 button(session,"STOP ALL",stopAll)
 local moveButton;moveButton=button(session,"MOVE: "..opts.move,function()opts.move=opts.move=="Walk"and"Teleport"or"Walk";moveButton.Text="MOVE: "..opts.move:upper();save()end)
 number(session,"interval","ACTION DELAY (SECONDS)",0.2,5)
 local diag=group(settings,"DIAGNOSTICS");button(diag,"CHECK GAME SERVICES",function()local ready={};for _,n in ipairs({"Config","ItemCollect","MakeFire","Furnace","CraftItems","BuildBuilding","MrbeastQuest","ChestService"})do ready[#ready+1]=n..": "..(module(n)and"OK"or"UNAVAILABLE")end;say(table.concat(ready," | "))end)
 local clockLabel=text(main,"DAY / PHASE: WAITING")
 local launcher=button(gui,"EXIS",function()panel.Visible=true end);launcher.Size=UDim2.fromOffset(46,28);launcher.Position=UDim2.fromOffset(12,90);launcher.Visible=false
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
    for _,id in ipairs(ids)do local item=rows[id];local key=id;local b;b=button(g,"",function()selected[kind][key]=not selected[kind][key];b.Text=(selected[kind][key]and"●  "or"○  ")..tostring(item.displayName or item.name or key):upper();save()end);b.Text=(selected[kind][key]and"●  "or"○  ")..tostring(item.displayName or item.name or key):upper()end
   end
   choices(resources,"resources",c.worldResource.byId)
   choices(resources,"drops",c.item.byId)
   choices(main,"food",c.food.byId)
   choices(camp,"cook",c.food.byId,function(i)return i.canCook==true end)
   choices(craft,"craft",c.item.byId,function(i)return i.recipeId and(i.type=="tool"or i.type=="armour")end)
   choices(craft,"build",c.build.byId)
   for _,info in ipairs(c.build.list or{})do local name=info.assetId;if type(name)=="string"then button(destination,"GO TO "..name,function()flags.travel=true;task.spawn(function()local w=world();local b=w and w:FindFirstChild("Buildings");local target=b and(b:FindFirstChild(name)or b:FindFirstChild(name.."_Construct"));if target then travel(target,"travel")else say("BUILDING NOT LOADED")end;flags.travel=false end)end)end end
  end);if not ok then say(e)end
 end)
 -- Reward data is read from the game's real replicated state.
 local rewardData={};local campData={};local furnaceData={}
 task.spawn(function()pcall(function()call("DailyReward","onSync",function(v)rewardData.daily=v end)end);pcall(function()call("WeekReward","onSync",function(v)rewardData.week=v end)end);pcall(function()call("PlayTimeReward","sync",function(v)rewardData.play=v end)end);pcall(function()call("DailyQuest","sync",function(v)rewardData.quest=v end)end)
 local function syncRemote(name,fn)local m=RS:FindFirstChild("Engine");m=m and m:FindFirstChild("Service");m=m and m:FindFirstChild(name);local e=m and m:FindFirstChild("syncRemote");if e then connections[#connections+1]=e.OnClientEvent:Connect(fn)end end
 syncRemote("MakeFire",function(v)if type(v)=="table"then campData=v end end);syncRemote("Furnace",function(v)if type(v)=="table"then furnaceData=v end end)
 end)
 local function rewardTick()
  if flags.daily and rewardData.daily=="canClaim"then call("DailyReward","claim")end
  if flags.weekly and type(rewardData.week)=="table"then for i,v in pairs(rewardData.week.days or{})do if v=="Claim"then call("WeekReward","claim",i);break end end end
  if flags.playtime and type(rewardData.play)=="table"then for id,v in pairs(rewardData.play.rewards or{})do if v.canClaim and not v.claimed then call("PlayTimeReward","claim",id);break end end end
  if flags.dailyQuest and type(rewardData.quest)=="table"then for _,v in pairs(rewardData.quest.list or{})do if v.completed and not v.claimed then call("DailyQuest","claim",v.id);break end end end
 end
 local function eat()
  local r,h=root();if not r then return end;local hunger=h:GetAttribute("hunger");local max=h:GetAttribute("maxHunger")or 100
  if h.Health/h.MaxHealth*100>opts.health and(not hunger or hunger/max*100>opts.hunger)then return end
  local c=config();for _,t in ipairs(tools())do local info=c.item.byDisplayName[t.Name];if info and allowed("food",info.id)then equip(t);t:Activate();return end end
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
  if o and travel(o,"drops")then call("ItemCollect","collect",o);failed[o]=os.clock()+5;say("COLLECT: "..o.Name);return true end
 end
 local function gatherResource()
  local w=world();if not w then return end;local c=config();local best=nearest(w:GetDescendants(),function(o)return o:IsA("Model")and allowed("resources",o:GetAttribute("resourceId"))end)
  if not best then return end
  local rc=c.worldResource.byId[best:GetAttribute("resourceId")];local tool,tc
  for _,t in ipairs(tools())do local info=c.tool.byDisplayName[t.Name];if info and(rc.requireToolType=="any"or info.toolType==rc.requireToolType)and(not tc or(info.useDmg or 0)>(tc.useDmg or 0))then tool,tc=t,info end end
  if not tool then say("MATCHING TOOL REQUIRED: "..best.Name);return end
  if travel(best,"gather")then equip(tool);local r=root();local p=best:GetPivot().Position;r.CFrame=CFrame.lookAt(r.Position,Vector3.new(p.X,r.Position.Y,p.Z));local e=RS:FindFirstChild("Events");e=e and e:FindFirstChild("meleeHitRemote");if e then e:FireServer({},{best});task.wait(math.max(0.2,tc.useCd or 0.7));say("GATHER: "..best.Name)end;return true end
 end
 local function exploreTick(key,kind,service,check,request)
  local w=world();if not w then return end;local c=config();local rows=kind=="chest"and c.chest.byId or c.mapProp.byCnId
  local obj=nearest(w:GetDescendants(),function(o)return o:IsA("Model")and rows[o.Name]and not(failed[o]and failed[o]>os.clock())end)
  if not obj then return end;failed[obj]=os.clock()+20
  if call(service,check,obj)then return end
  if kind=="chest"and call(service,"isLocked",obj)then return end
  if travel(obj,key)then call(service,request,obj);say(request..": "..obj.Name);return true end
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
  local q=module("MrbeastQuest");if not q then return end;local index,alt,revision=q.client.fetchQuest();local req=index and q.getQuestRequirement(index,alt)
  if not req then questInfo.Text="NO ACTIVE QUEST";return end
  local c=config();local info=c.item.byId[req.itemId];questInfo.Text="NEEDS: "..tostring(req.count).." "..tostring(info and info.displayName or req.itemId)
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
  q.client.submitQuest(owned,revision);task.wait(1);say("QUEST SUBMITTED");return true
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
  if fish.state=="minigame"then say("COMPLETE FISH MINIGAME");return end
  if fish.state=="reeling"and os.clock()-fish.at>4 then fish.state="idle"end
  if fish.state~="idle"then if os.clock()-fish.at>45 then events.fishCancelRemote:FireServer();fish.state="idle"end;return end
  local c=config();local rod
  for _,t in ipairs(tools())do local info=c.tool.byDisplayName[t.Name];if info and info.toolType=="鱼竿"then rod=t;break end end
  if not rod then say("FISHING ROD REQUIRED");return end
  equip(rod);fish.tool=rod
  local direction=r.CFrame.LookVector*Vector3.new(1,0,1);local p=r.Position+direction.Unit*18
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={workspace.Terrain,world().Tiles};params.IgnoreWater=false
  local hit=workspace:Raycast(p+Vector3.new(0,50,0),Vector3.new(0,-200,0),params)
  if not hit or hit.Material~=Enum.Material.Water then say("FACE WATER TO CAST");return end
  events.fishVisualRemote:FireServer("castBegin",rod.Name);events.fishCastRemote:FireServer(rod,hit.Position+Vector3.new(0,0.05,0));fish.state="waiting";fish.at=os.clock();say("FISHING: WAITING FOR BITE")
 end
 task.spawn(function()
  while alive do
   local ok,e=pcall(function()
    local w=world();if w then local d=w:FindFirstChild("Day");local phase=w:FindFirstChild("Phase");clockLabel.Text="DAY "..tostring(d and d.Value or"—").."  |  "..tostring(phase and phase.Value or"—")end
    if not due.rewards or os.clock()>due.rewards then due.rewards=os.clock()+10;rewardTick()end
    if flags.eat then eat()end
    if flags.combat then defend()end
    if flags.fish then fishTick();return elseif fish.state~="idle"then if fish.mini then fish.mini:cancel();fish.mini=nil end;if events and events:FindFirstChild("fishCancelRemote")then events.fishCancelRemote:FireServer()end;fish.state="idle"end
    if flags.travel then return end
    if flags.escape and(not due.escape or os.clock()>due.escape)and escapeTick()then return end
    if flags.quest and(not due.quest or os.clock()>due.quest)then due.quest=os.clock()+4;if questTick()then return end end
    if flags.fuel and(not due.fuel or os.clock()>due.fuel)then due.fuel=os.clock()+4;if type(campData.campfireWoodCount)=="number"and campData.campfireWoodCount<opts.fuel then call("MakeFire","addWood")end end
    if flags.cooked and(campData.readyCount or 0)>0 then call("MakeFire","collectFood")end
    if flags.cook and(not due.cook or os.clock()>due.cook)then due.cook=os.clock()+4;local c=config();for id in pairs(selected.cook or{})do local info=c.item.byId[id];if allowed("cook",id)and info and count(info.displayName)>0 then call("MakeFire","addFood",id);break end end end
    if flags.smeltCollect and(furnaceData.readyCount or 0)>0 then call("Furnace","collectResult")end
    if flags.smelt and(not due.smelt or os.clock()>due.smelt)then due.smelt=os.clock()+5;call("Furnace","addBoth")end
    if flags.water and(not due.water or os.clock()>due.water)then due.water=os.clock()+10;call("WaterMaker","collect")end
    local c=config()
    if flags.craft then for id in pairs(selected.craft or{})do local i=c.item.byId[id];if allowed("craft",id)and i and count(i.displayName)==0 and recipeReady(i)then call("CraftItems","craft",id);task.wait(0.5);return end end end
    if flags.build and(not due.build or os.clock()>due.build)then due.build=os.clock()+5;local b=w and w:FindFirstChild("Buildings");for id in pairs(selected.build or{})do local i=c.build.byId[id];if allowed("build",id)and i and b and b:FindFirstChild(i.assetId.."_Construct")then call("BuildBuilding","build",id);return end end end
    if flags.chests and exploreTick("chests","chest","ChestService","isOpened","requestOpen")then return end
    if flags.puzzles and exploreTick("puzzles","puzzle","PuzzlePropService","isSolved","requestSolve")then return end
    if flags.drops and pickups()then return end
    if flags.gather then gatherResource()end
   end)
   if not ok then say(tostring(e));warn("EXIScript Island: "..tostring(e))end
   task.wait(math.max(0.2,opts.interval))
  end
 end)
 say("ISLAND ESCAPE LOADED • CONFIG SAVED PER GAME")
end

runIslandEscape()
