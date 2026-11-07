-- Whole-script startup with a small Roblox client surface. No live engine claim.
local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
local function signal()return{Connect=function()return{Disconnect=function()end}end}end
local methods={}
local instances={}
local function node(class)
 local n={ClassName=class,children={},props={}}
 setmetatable(n,{__index=function(t,k)
  if methods[k]then return methods[k]end
  if t.props[k]~=nil then return t.props[k]end
  if k=='AbsoluteSize'or k=='ViewportSize'then return{X=800,Y=600}end
  if k=='Activated'or k=='InputBegan'or k=='Destroying'or k=='OnClientEvent'or k=='Idled'or k=='OnTeleport'or k=='CharacterRemoving'or k=='InputEnded'or k=='InputChanged'or k=='RenderStepped'or k=='ErrorMessageChanged'or k=='DescendantAdded'then local s=signal();t.props[k]=s;return s end
 end,__newindex=function(t,k,v)
  if k=='Parent'and v then v.children[#v.children+1]=t end
  t.props[k]=v
 end})
 instances[#instances+1]=n
 return n
end
function methods:FindFirstChild(name)for _,c in ipairs(self.children)do if c.Name==name then return c end end end
function methods:WaitForChild(name)local c=self:FindFirstChild(name);if c then return c end;c=node('Folder');c.Name=name;c.Parent=self;return c end
function methods:GetChildren()return self.children end
function methods:GetDescendants()local out={}local function walk(o)for _,c in ipairs(o.children)do out[#out+1]=c;walk(c)end end;walk(self);return out end
function methods:IsA(class)return self.ClassName==class end
function methods:IsDescendantOf(other)local p=self.Parent;while p do if p==other then return true end;p=p.Parent end return false end
function methods:GetPropertyChangedSignal()return signal()end
function methods:Destroy()self.Parent=nil end
function methods:GetAttribute()end
local now=0;local warnings={};local modules={};local services={}
local function mount(root,path,value)
 local parent=root
 local names={}for x in path:gmatch('[^.]+')do names[#names+1]=x end
 for i,name in ipairs(names)do
  local c=parent:FindFirstChild(name)
  if not c then c=node(i==#names and 'ModuleScript'or'Folder');c.Name=name;c.Parent=parent end
  parent=c
 end
 modules[parent]=value
end
local player=node('Player');player.Name='Test';player.UserId=1;player:WaitForChild('PlayerGui')
services.Players={LocalPlayer=player};local rs=node('ReplicatedStorage');services.ReplicatedStorage=rs
services.UserInputService=node('UserInputService');services.PathfindingService={};services.HttpService={}
services.Lighting=node('Lighting');services.RunService=node('RunService');services.GuiService=node('GuiService')
workspace=node('Workspace');workspace.CurrentCamera=node('Camera');function workspace:GetServerTimeNow()return now end
services.Workspace=workspace
local eggs={ReadCarryState=function()return{IsCarrying=false}end,ReadOwnerEggs=function()return{}end,HasFieldSnapshot=function()return true end}
local plots={ResolvePlot=function()end,ReadOwners=function()return{}end}
local remotes={Treadmill={AssignedBeltShifted={OnClientEvent=signal()}},LightVsDarkness={RingCollected={OnClientEvent=signal()}},SammyEvent={PickupCollected={OnClientEvent=signal()}}}
for path,value in pairs({['Client.EggState']=eggs,['Client.PlotState']=plots,['Shared.Remotes']=remotes,
 ['Data.Assets']={Directory={}},['Data.Areas']={Directory={}},['Data.Rarity']={Rarities={}},['Shared.Save']={Peek=function()end},
 ['Client.BaseUpgrade']={},['Data.Treadmills']={},['Shared.Util.FuseKernel']={},['Shared.Flags.GameplayBalance']={},
 ['Shared.Preferences']={IsOn=function()return false end}})do mount(rs,path,value)end
require=function(module)return assert(modules[module],'unexpected module')end
Instance={new=node};Color3={fromRGB=function(...)return{...}end};ColorSequence={new=function()return{}end}
UDim={new=function(a,b)return{Scale=a,Offset=b}end};UDim2={new=function(a,b,c,d)return{X={Scale=a,Offset=b},Y={Scale=c,Offset=d}}end,fromOffset=function(x,y)return{X={Offset=x},Y={Offset=y}}end,fromScale=function(x,y)return{X={Scale=x},Y={Scale=y}}end}
Vector2={new=function()return{X=0,Y=0}end};Enum=setmetatable({},{__index=function(t,k)local v=setmetatable({},{__index=function(_,key)return key end});rawset(t,k,v);return v end})
game={PlaceId=107778070777162,GameId=1,JobId='test',GetService=function(_,key)return assert(services[key],key)end}
local threads={}
task={wait=function()return coroutine.yield()end,defer=function(fn,...)return task.spawn(fn,...)end}
task.spawn=function(fn,...)
 local co=coroutine.create(fn);local ok,err=coroutine.resume(co,...);assert(ok,err)
 if coroutine.status(co)~='dead'then threads[#threads+1]=co end;return co
end
warn=function(v)warnings[#warnings+1]=v end
local originalClock=os.clock;os.clock=function()now=now+.001;return now end
local success,err=assert(load(source))()
os.clock=originalClock
assert(success==true,err or table.concat(warnings,'\n'))
local panel=false;local startupAlive=false
for _,o in ipairs(instances)do
 if o.Name=='EXIPanel'and o.Parent then panel=true end
 if o.Name=='EXISEggStartup'and o.Parent then startupAlive=true end
end
assert(panel and not startupAlive)
print('PASS complete game script reaches its main panel with all native modules present')
-- A missing required adapter must propagate a failure return, not false success.
services.ReplicatedStorage=node('ReplicatedStorage');now=0
os.clock=function()now=now+1;return now end
task.wait=function()end
local result,message=assert(load(source))()
os.clock=originalClock
assert(result==false and tostring(message):find('Client.EggState',1,true))
print('PASS complete script returns the missing adapter error to the universal loader')
print('2 complete startup and error propagation checks passed')
