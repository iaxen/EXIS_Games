-- Execute the real UI constructors and events with a lightweight Roblox UI model.
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return s end
local zombie=read('Games/ZombieRushSurvival.lua')
local fuzz=read('Games/Fuzzotopia.lua')
local beast=read('Games/MrbeastIslandEscape.lua')
local function extract(s,a,b)local i=assert(s:find(a,1,true),a);local j=assert(s:find(b,i+#a,true),b);return s:sub(i,j-1)end
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local function signal()
 local s={callbacks={}};function s:Connect(fn)self.callbacks[#self.callbacks+1]=fn;return{Disconnect=function()end}end
 function s:Fire(...)for _,fn in ipairs(self.callbacks)do fn(...)end end;return s
end
local function dims(xs,xo,ys,yo)return{X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}}end
local function mock()
 local nodes={};local function new(class,props,parent)
  local n={ClassName=class,children={},Visible=true,Name=class}
  n.IsDescendantOf=function(self,ancestor)local p=self.Parent;while p do if p==ancestor then return true end;p=p.Parent end;return false end
  n.GetChildren=function(self)return self.children end
  n.Destroy=function(self)self.Parent=nil end
  n.IsA=function(self,kind)return self.ClassName==kind end
  n.GetPropertyChangedSignal=function()return signal()end
  setmetatable(n,{__newindex=function(self,key,value)rawset(self,key,value);if key=='Parent'and value then value.children[#value.children+1]=self end end,__index=function(self,key)
   if key=='AbsoluteSize'then
    local p=self.Parent and self.Parent.AbsoluteSize or{X=800,Y=600};local size=rawget(self,'Size')or dims(1,0,1,0)
    return{X=p.X*size.X.Scale+size.X.Offset,Y=p.Y*size.Y.Scale+size.Y.Offset}
   elseif key=='AbsolutePosition'then return{X=0,Y=0}
   elseif key:find('Input')or key=='Activated'or key=='FocusLost'then local s=signal();rawset(self,key,s);return s end
  end})
  for k,v in pairs(props or{})do n[k]=v end
  n.Parent=parent
  nodes[#nodes+1]=n;return n
 end
 local function enum()return setmetatable({},{__index=function(_,k)return k end})end
 local E={};for _,k in ipairs({'Font','AutomaticSize','SortOrder','TextXAlignment','TextYAlignment','TextTruncate','ZIndexBehavior','UserInputType'})do E[k]=enum()end
 local env=setmetatable({Enum=E,UDim2={new=dims,fromScale=function(x,y)return dims(x,0,y,0)end,fromOffset=function(x,y)return dims(0,x,0,y)end},
  UDim={new=function(s,o)return{Scale=s,Offset=o}end},Vector2={new=function(x,y)return{X=x,Y=y}end},
  Color3={fromRGB=function(r,g,b)return r..','..g..','..b end},ColorSequence={new=function()return{}end},
  Instance={new=function(class)return new(class)end},UIS={InputChanged=signal(),InputEnded=signal()},
  pg=new('PlayerGui'),workspace={CurrentCamera={ViewportSize={X=800,Y=600}}}}, {__index=_G})
 env.app={connections={},connect=function(s,fn)return s:Connect(fn)end,releaseFire=function()end,changed=function()end}
 env.cfg={};env.blue='80,160,255';env.white='232,238,248'
 env.make=new;env.corner=function()end;env.groups={};env.states={};env.renderToggle={};env.configChanged=function()end
 return env,new,nodes
end
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function zombieUI()
 local env,new,nodes=mock()
 local start=assert(zombie:find('    local ui = {}',1,true));local finish=assert(zombie:find('    local main = ui.page(',start,true))
 local ui=assert(load(zombie:sub(start,finish-1)..'\nreturn ui','ui','t',env))()
 env.ui=ui;return env,ui,new,nodes
end
test('ZombieRush shell matches Fuzzotopia compact sizing palette sidebar and header',function()
 local env,ui,_,nodes=zombieUI();local frame,header,sidebar
 for _,n in ipairs(nodes)do
  if n.ClassName=='Frame'and n.BackgroundColor3=='8,12,18'and n.ClipsDescendants then frame=n end
  if n.ClassName=='Frame'and n.BackgroundColor3=='17,22,31'and n.Active then header=n end
  if n.ClassName=='ScrollingFrame'and n.BackgroundColor3=='15,19,27'then sidebar=n end
 end
 assert(frame and frame.AbsoluteSize.X==392 and frame.AbsoluteSize.Y==272)
 assert(header.Size.Y.Offset==30 and sidebar.Size.X.Offset==82)
 assert(ui.blue=='80,160,255'and ui.text=='232,238,248')
end)
test('ZombieRush groups collapse siblings and recursively close nested groups',function()
 local env,ui,new=zombieUI();local page=new('Frame');local a=ui.group(page,'Alpha');local nested=ui.group(a,'Nested');local b=ui.group(page,'Beta')
 local entries=ui.groups;entries[1].setOpen(false)
 local function click(body)for _,n in ipairs(body.Parent.children)do if n.ClassName=='TextButton'then n.Activated:Fire();return end end end
 click(a);click(nested);assert(a.Visible and nested.Visible)
 click(b);assert(b.Visible and not a.Visible and not nested.Visible)
end)
test('same selected tab toggles content while switching tabs preserves page selection',function()
 local _,ui=zombieUI();local a=ui.page('MAIN');local b=ui.page('AREA')
 ui.show('MAIN');assert(a.Visible and not b.Visible and a.Parent.Visible)
 ui.show('MAIN');assert(not a.Parent.Visible)
 ui.show('AREA');assert(b.Visible and not a.Visible and b.Parent.Visible)
end)
test('ZombieRush full switch row toggles the saved option and uses Fuzzotopia track dimensions',function()
 local env,ui,new=zombieUI();local options={fight=false};local row=ui.toggle(new('Frame'),'Fight',options,'fight')
 assert(row.ClassName=='TextButton'and row.Size.Y.Offset==25)
 local track=row.children[3];assert(track.Size.X.Offset==25 and track.Size.Y.Offset==12)
 row.Activated:Fire();assert(options.fight and track.BackgroundColor3==ui.blue)
 row.Activated:Fire();assert(not options.fight)
end)
test('MrBeast and Fuzzotopia retain the same accordion dimensions and sibling behavior',function()
 for _,kind in ipairs({'Fuzzotopia','MrBeast'})do
  local env,new=mock();local group
  if kind=='Fuzzotopia'then
   env.ui={groups={}};assert(load(extract(fuzz,'function ui.group(container,name)','local extras='),'fuzz-group','t',env))();group=env.ui.group
  else
   group=assert(load(extract(beast,'    local function group(container, name)','    local function switch(')..'\nreturn group','beast-group','t',env))()
  end
  local page=new('Frame');local a=group(page,'First');local b=group(page,'Second')
  local function header(body)for _,n in ipairs(body.Parent.children)do if n.ClassName=='TextButton'then return n end end end
  assert(header(a).Size.Y.Offset==25)
  header(a).Activated:Fire();assert(a.Visible and not b.Visible)
  header(b).Activated:Fire();assert(not a.Visible and b.Visible)
 end
end)
test('minimize and the floating icon preserve the Fuzzotopia open-close interaction',function()
 local env,ui,_,nodes=zombieUI();local minimize,icon,frame
 for _,n in ipairs(nodes)do
  if n.ClassName=='TextButton'and n.Text=='−'then minimize=n end
  if n.Name=='OpenEXIScript'then icon=n end
  if n.ClassName=='Frame'and n.ClipsDescendants then frame=n end
 end
 assert(minimize and icon and not icon.Visible and frame.Visible)
 minimize.Activated:Fire();assert(not frame.Visible and icon.Visible)
 local input={UserInputType=env.Enum.UserInputType.MouseButton1,Position={X=0,Y=0}}
 icon.InputBegan:Fire(input);env.UIS.InputEnded:Fire(input)
 assert(frame.Visible and not icon.Visible)
end)
print(passed..' universal EXIS UI behavior checks passed')
