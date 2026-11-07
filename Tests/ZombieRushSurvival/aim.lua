local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local V={}
V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v:Dot(v))elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function v(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__unm=function(a)return v(-a.X,-a.Y,-a.Z)end
V.__mul=function(a,b)return v(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return v(a.X/b,a.Y/b,a.Z/b)end
function V:Dot(b)return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function V:Cross(b)return v(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X)end
local F={}
local function frame(p,r,u,b)return setmetatable({Position=p,r=r or v(1,0,0),u=u or v(0,1,0),b=b or v(0,0,1)},F)end
F.__index=function(f,k)
 if k=='Rotation'then return frame(v(0,0,0),f.r,f.u,f.b)elseif k=='LookVector'then return-f.b end
 return F[k]
end
function F:transform(p)return self.r*p.X+self.u*p.Y+self.b*p.Z end
F.__mul=function(a,b)return frame(a.Position+a:transform(b.Position),a:transform(b.r),a:transform(b.u),a:transform(b.b))end
local CF={new=function(p)return frame(p)end}
function CF.lookAt(p,to)local forward=(to-p).Unit;local right=forward:Cross(v(0,1,0)).Unit;return frame(p,right,right:Cross(forward),-forward)end
function CF.fromAxisAngle(axis,angle)
 local function rotate(p)return p*math.cos(angle)+axis:Cross(p)*math.sin(angle)+axis*(axis:Dot(p)*(1-math.cos(angle)))end
 return frame(v(0,0,0),rotate(v(1,0,0)),rotate(v(0,1,0)),rotate(v(0,0,1)))
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function setup(offsetX,offsetY)
 local camera={CFrame=frame(v(0,3,0))};local head=v(10,8,-40)
 local model={Parent=true,Name='Zombie_1'}
 local app={mode='MATCH',target={model=model,boss=false},next={}}
 local cfg={fight=true,headAim=true,bossFirst=true,dodgeTeleport=true,autoPlace=true}
 local crosshair={GetAimCameraRay=function(cam)
  local direction=cam.CFrame:transform(v(offsetX or 0,offsetY or 0,-1)).Unit
  return{Origin=cam.CFrame.Position+direction*.1,Direction=direction}
 end}
 local env=setmetatable({app=app,cfg=cfg,CFrame=CF,Vector3={new=v},workspace={CurrentCamera=camera},
  shared={FindFirstChild=function()return{}end}},{__index=_G})
 app.active=function()return true end;app.head=function()return head end;app.module=function()return crosshair end
 app.root=function()return{Position=v(0,3,0)},{Health=100,MaxHealth=100}end
 assert(load(extract('    function app.aimTick()', '    -- Compact EXIS interface:'),'production aim','t',env))()
 local function aligned()
  local ray=crosshair.GetAimCameraRay(camera)
  assert(ray.Direction:Dot((head-ray.Origin).Unit)>.99999,'crosshair ray misses head')
 end
 return{app=app,cfg=cfg,camera=camera,model=model,env=env,aligned=aligned,
 setHead=function(p)head=p end}
end
test('head aim tracks a target while a defense approach is active',function()
 local h=setup();h.app.buildGoal=v(20,3,10);h.app.aimTick();h.aligned()
 assert(h.app.aimStatus:find('TRACKING HEAD',1,true))
end)
test('offset crosshair correction aligns the actual native ray rather than only the camera center',function()
 local h=setup(.4,-.3);h.app.aimTick();h.aligned()
end)
test('aim keeps following a moving head after a teleport changes the camera origin',function()
 local h=setup(.3,.1);h.app.aimTick();h.camera.CFrame=frame(v(30,3,20));h.setHead(v(-10,10,-25))
 h.app.aimTick();h.aligned()
end)
test('native ray absence falls back to camera-center aim without throwing',function()
 local h=setup();h.app.module=function()return{}end;h.app.aimTick();h.aligned()
 assert(h.app.aimStatus:find('camera center',1,true))
end)
test('disabled head aim or fight mode leaves camera control alone',function()
 for _,key in ipairs({'fight','headAim'})do
  local h=setup();local before=h.camera.CFrame;h.cfg[key]=false;h.app.aimTick()
  assert(h.camera.CFrame==before and h.app.aimStatus:find('OFF',1,true))
 end
end)
test('missing target camera or head reports a waiting reason',function()
 local h=setup();h.app.target=nil;h.app.aimTick();assert(h.app.aimStatus:find('no live zombie',1,true))
 h=setup();h.env.workspace.CurrentCamera=nil;h.app.aimTick();assert(h.app.aimStatus:find('unavailable',1,true))
 h=setup();h.app.head=function()return nil end;h.app.aimTick();assert(h.app.aimStatus:find('not loaded',1,true))
end)
test('removing a target does not keep rotating toward its old position',function()
 local h=setup();local before=h.camera.CFrame;h.model.Parent=nil;h.app.aimTick();assert(h.camera.CFrame==before)
end)
test('aim render step executes after the native camera shake priority',function()
 local bound,callback
 local env=setmetatable({RunService={BindToRenderStep=function(_,name,priority,fn)assert(name=='EXIS_ZOMBIE_AIM');bound=priority;callback=fn end},
  Enum={RenderPriority={Camera={Value=200},Last={Value=2000}}},app={aimTick=function()end,note=function()end}},{__index=_G})
 assert(load(extract('    RunService:BindToRenderStep("EXIS_ZOMBIE_AIM"', '    task.spawn(function()'),'render order','t',env))()
 assert(bound>205);callback()
end)
test('combat aligns the camera before issuing the first native fire input',function()
 local h=setup(.4,-.2);local fired=false
 h.app.stopWalk=function()end;h.app.teleportDodgeTick=function()end
 h.app.weapon=function()return{},{}end;h.app.reload=function()return false end
 h.app.raycast=function()return nil end;h.app.mapFilters=function()return{}end
 h.app.holdFire=function()h.aligned();fired=true end
 assert(load(extract('    function app.combatTick(', '    function app.aimTick()'),'fire order','t',h.env))()
 h.app.combatTick(.016);assert(fired)
end)
print(tests..' real production aiming, crosshair and camera-order checks passed')
