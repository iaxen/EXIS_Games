local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local Core=assert(load(source:sub(1,assert(source:find('-- Runtime adapters.',1,true))-1)..'\nreturn Core'))()
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
local function cf(p,down)
 return{Position=p,UpVector=vec(0,1,0),PointToWorldSpace=function(_,q)return p+q end,
 PointToObjectSpace=function(_,q)local d=q-p;if down then return vec(d.X,-d.Z,d.Y)end return d end,
 VectorToWorldSpace=function(_,q)if down then return vec(q.X,q.Z,-q.Y)end return q end}
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function setup(number)
 local sources,clones={},{}
 local function part(y,x)
  local p={Name='Floor',ClassName='Part',Parent=true,Size=vec(40,2,40),Position=vec(x or 0,y,0),CFrame=cf(vec(x or 0,y,0)),
   Archivable=true,CanCollide=true,Transparency=0,LocalTransparencyModifier=.15}
  p.IsA=function(_,kind)return kind=='BasePart'or kind=='Part'end
  p.GetDescendants=function()return{}end
  p.Clone=function(self)
   local c=part(self.Position.Y,self.Position.X);c.Clone=nil;c.GetDescendants=function()return{}end
   c.CFrame=self.CFrame;c.Destroy=function(n)n.Parent=nil;n.destroyed=true end;clones[#clones+1]=c;return c
  end
  return p
 end
 for i=1,number or 3 do sources[i]=part(i==2 and 10 or 0,i*2)end
 local world
 local Instance={new=function(kind)
  local n={Parent=true,ClassName=kind}
  n.Destroy=function(self)self.Parent=nil;self.destroyed=true end
  if kind=='WorldModel'then
   world=n;n.Raycast=function(self,origin,direction,params)self.ray={origin=origin,direction=direction,params=params};return{Instance=clones[1],Position=vec(2,1,0),Normal=vec(0,1,0)}end
  end
  return n
 end}
 local live={CFrame=cf(vec(30,4,20)),CameraType='Custom',FieldOfView=70};local liveFrame=live.CFrame
 local UIS={MouseBehavior='LockCenter',MouseIconEnabled=false}
 local screens={Gameplay={Enabled=true},Toolbar={Enabled=true},TouchGui={Enabled=true}}
 local app={alive=true,mapId='Map1',mode='MATCH',editing=true,notes={},
  viewport={AbsoluteSize={X=640,Y=400},AbsolutePosition={X=8,Y=150}}}
 app.mapFilters=function()return{{GetDescendants=function()return sources end}}end
 app.navigation=function()return{hull={{x=-40,y=1,z=-40},{x=40,y=1,z=-40},{x=40,y=1,z=40},{x=-40,y=1,z=40}}}end
 app.note=function(k,v)app.notes[k]=v end
 local jobs,yields={},0
 local tasks={spawn=function(fn)jobs[#jobs+1]=coroutine.create(fn)end,wait=function()coroutine.yield()end}
 local env=setmetatable({app=app,Core=Core,workspace={CurrentCamera=live},UIS=UIS,Instance=Instance,
  pg={FindFirstChild=function(_,name)return screens[name]end},task=tasks,Vector3={new=vec},Vector2={new=function(x,y)return{X=x,Y=y}end},
  CFrame={new=cf,lookAt=function(p)return cf(p,true)end},Enum={MouseBehavior={Default='Default'},RaycastFilterType={Include='Include'}},
  RaycastParams={new=function()return{}end}},{__index=_G})
 assert(load(extract('    function app.stopMapView()', '    function app.navigation()'),'replica','t',env))()
 local function drain()
  for _,job in ipairs(jobs)do while coroutine.status(job)~='dead'do local ok,err=coroutine.resume(job);assert(ok,err);yields=yields+1 end end
 end
 return{app=app,env=env,sources=sources,clones=clones,UIS=UIS,live=live,liveFrame=liveFrame,screens=screens,drain=drain,
  yields=function()return yields end,world=function()return world end,part=part}
end
test('replica camera is independent and never replaces the live combat camera',function()
 local h=setup();assert(h.app.startMapView(1));h.drain();h.app.renderMapView()
 assert(h.app.mapView.camera~=h.live and h.live.CFrame==h.liveFrame and h.live.CameraType=='Custom'and h.live.FieldOfView==70)
 assert(h.app.viewport.CurrentCamera==h.app.mapView.camera)
end)
test('all loaded geometry parts are cloned without a display count cap',function()
 local h=setup(55);h.app.startMapView(1);h.drain();assert(#h.clones==55 and #h.app.mapView.parts==55)
 assert(h.app.mapView.count==55 and h.app.mapView.total==55 and not h.app.mapView.loading)
end)
test('copying yields in bounded batches so the fight thread can keep running',function()
 local h=setup(55);h.app.startMapView(1);assert(h.app.mapView.loading and #h.clones==0)
 h.drain();assert(h.yields()>=3)
end)
test('replica geometry retains source transforms with source-to-clone mapping',function()
 local h=setup();h.app.startMapView(1);h.drain()
 for i,c in ipairs(h.clones)do assert(c.CFrame==h.sources[i].CFrame and h.app.mapView.sources[c]==h.sources[i])end
end)
test('map copying never hides live parts or disables the gameplay and weapon HUD',function()
 local h=setup();h.app.startMapView(1);h.drain();h.app.mapView.cutaway=true;h.app.mapLayer(1)
 assert(h.sources[2].LocalTransparencyModifier==.15)
 assert(h.screens.Gameplay.Enabled and h.screens.Toolbar.Enabled and h.screens.TouchGui.Enabled)
 assert(h.clones[2].LocalTransparencyModifier==1)
end)
test('full map and floor cutaway are both available within the replica',function()
 local h=setup();h.app.startMapView(1);h.drain();assert(h.clones[2].LocalTransparencyModifier==.15)
 h.app.mapView.cutaway=true;h.app.mapLayer(1);assert(h.clones[2].LocalTransparencyModifier==1)
 h.app.mapView.cutaway=false;h.app.mapLayer(1);assert(h.clones[2].LocalTransparencyModifier==.15)
end)
test('replica selection rays use replica coordinates and only its floor layer',function()
 local h=setup();h.app.startMapView(1);h.drain();h.app.renderMapView()
 local hit=h.app.mapViewRay({X=328,Y=350});assert(hit and h.world().ray)
 assert(h.world().ray.params.FilterDescendantsInstances==h.app.mapView.floors)
 assert(h.app.mapView.sources[hit.Instance]==h.sources[1])
end)
test('clicks outside the replica or before geometry loads cannot create corners',function()
 local h=setup();h.app.startMapView(1);assert(not h.app.mapViewRay({X=328,Y=350}));h.drain();h.app.renderMapView()
 assert(not h.app.mapViewRay({X=1,Y=1}))
end)
test('projected corner markers and viewport ray origins agree at map center',function()
 local h=setup();h.app.startMapView(1);h.drain();h.app.renderMapView()
 local pixel=h.app.projectMapPoint(h.app.mapView.center);assert(math.abs(pixel.X-320)<.001 and math.abs(pixel.Y-200)<.001)
end)
test('closing destroys the replica and restores the cursor without touching combat state',function()
 local h=setup();h.app.startMapView(1);h.drain();h.app.renderMapView();local state=h.app.mapView
 h.app.stopMapView();assert(state.world.destroyed and state.camera.destroyed and not h.app.mapView)
 assert(h.UIS.MouseBehavior=='LockCenter'and not h.UIS.MouseIconEnabled and h.live.CFrame==h.liveFrame)
end)
test('cancelled copy jobs do not keep adding parts to a destroyed editor',function()
 local h=setup(55);h.app.startMapView(1);h.app.stopMapView();h.drain();assert(#h.clones==0)
end)
test('opening selection leaves auto fight enabled and active',function()
 local h=setup();local cfg={enabled=true,fight=true}
 h.env.cfg=cfg;h.env.frame={};h.env.editor={};h.env.dotOverlay={};h.env.mapHolder={}
 h.app.root=function()return{Position=vec(0,4,0),Size=vec(2,2,2)},{HipHeight=2}end
 h.app.region=function()return{points={}}end;h.app.clearMarkers=function()end
 h.app.stopFlight=function()error('must not stop flight to select')end;h.app.releaseFire=function()error('must not stop firing to select')end
 assert(load(extract('    function app.active()', '    function app.note('),'active','t',h.env))()
 assert(load(extract('    function app.openMapEditor(', '    local function editorButton('),'open','t',h.env))()
 h.app.openMapEditor('new');assert(cfg.fight and h.app.editing and h.app.active())
end)
test('archivable flags are restored when an individual part clone fails',function()
 local h=setup();local p=h.sources[1];p.Archivable=false;p.Clone=function()error('mock copy failure')end
 assert(h.app.cloneMapPart(p)==nil and p.Archivable==false)
end)
test('replica parts cannot collide with or touch the real game world',function()
 local h=setup();local clone=h.app.cloneMapPart(h.sources[1])
 assert(clone.Anchored and not clone.CanCollide and not clone.CanTouch and clone.CanQuery)
end)
print(tests..' independent replica-editor checks passed')
