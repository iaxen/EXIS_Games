local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local Core=assert(load(source:sub(1,assert(source:find('-- Runtime adapters.',1,true))-1)..'\nreturn Core'))()
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local V={};V.__index=V
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
local function cf(p)return{Position=p,UpVector=vec(0,1,0),PointToWorldSpace=function(_,q)return p+q end}end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function setup()
 local function part(y,modifier)
  return{Parent=true,Size=vec(40,2,40),CFrame=cf(vec(0,y,0)),LocalTransparencyModifier=modifier or 0,
   CanCollide=true,Transparency=0,IsA=function(_,kind)return kind=='BasePart'end}
 end
 local floor,roof=part(0,.15),part(10,.3)
 local folder={GetDescendants=function()return{floor,roof}end}
 local camera={Parent=true,CameraType='Custom',CameraSubject={},FieldOfView=70,ViewportSize={X=1000,Y=700},CFrame=cf(vec(10,4,20)),Focus={old=true}}
 local original={frame=camera.CFrame,focus=camera.Focus,subject=camera.CameraSubject}
 local screens={Gameplay={Parent=true,Enabled=true},Toolbar={Parent=true,Enabled=false},TouchGui={Parent=true,Enabled=true}}
 for _,screen in pairs(screens)do screen.IsA=function(_,class)return class=='ScreenGui'end end
 local bound=false
 local CAS={BindActionAtPriority=function()bound=true end,UnbindAction=function()bound=false end}
 local UIS={MouseBehavior='LockCenter',MouseIconEnabled=false}
 local app={mapId='Map1',editing=true,notes={}}
 app.note=function(k,v)app.notes[k]=v end
 app.mapFilters=function()return{folder}end
 local workspace={CurrentCamera=camera}
 local rays={}
 app.raycast=function(origin,direction,filters)rays[#rays+1]={origin=origin,direction=direction,filters=filters};return{Position=vec(0,1,0),Normal=vec(0,1,0),Material='Concrete'}end
 local env=setmetatable({app=app,Core=Core,workspace=workspace,UIS=UIS,
  pg={FindFirstChild=function(_,k)return screens[k]end},game={GetService=function()return CAS end},
  Vector3={new=vec},Enum={CameraType={Scriptable='Scriptable'},MouseBehavior={Default='Default'},
  ContextActionResult={Sink='Sink'},PlayerActions={CharacterForward=1,CharacterBackward=2,CharacterLeft=3,CharacterRight=4,CharacterJump=5},Material={Water='Water'}},
  CFrame={new=cf,lookAt=function(p,target,up)local result=cf(p);result.target=target;result.up=up;return result end},
  GuiService={GetGuiInset=function()return{X=0,Y=36}end}},{__index=_G})
 camera.ViewportPointToRay=function(_,x,y)return{Origin=vec(x,100,y),Direction=vec(0,-1,0)}end
 assert(load(extract('    function app.stopMapView()', '    function app.resolveSurface()'),'map-view','t',env))()
 return{app=app,camera=camera,original=original,floor=floor,roof=roof,screens=screens,UIS=UIS,workspace=workspace,rays=rays,bound=function()return bound end}
end
test('wide map is fitted in landscape and portrait screens',function()
 local b={minX=-100,maxX=100,minZ=-50,maxZ=50}
 local landscape=Core.mapViewHeight(b,1200,700,50)
 local portrait=Core.mapViewHeight(b,400,900,50)
 assert(portrait>landscape)
 local tan=math.tan(math.rad(50)/2)
 assert(landscape*tan*1200/700>=100 and portrait*tan*400/900>=100)
end)
test('top toolbar space is included in the fit calculation',function()
 local b={minX=0,maxX=20,minZ=0,maxZ=100}
 assert(Core.mapViewHeight(b,1000,600,50,150)>Core.mapViewHeight(b,1000,600,50))
end)
test('editor uses the real loaded floor and locally hides the cave roof',function()
 local h=setup();assert(h.app.startMapView(1));assert(#h.app.mapView.floors==1 and h.app.mapView.floors[1]==h.floor)
 assert(h.floor.LocalTransparencyModifier==.15 and h.roof.LocalTransparencyModifier==1)
end)
test('opening the editor hides the game HUD and blocks character navigation',function()
 local h=setup();assert(h.app.startMapView(1));assert(not h.screens.Gameplay.Enabled and not h.screens.TouchGui.Enabled and h.bound())
end)
test('the map camera looks vertically down with north at the top',function()
 local h=setup();h.app.startMapView(1);h.app.renderMapView()
 assert(h.camera.CameraType=='Scriptable'and h.camera.FieldOfView==50)
 assert(h.camera.CFrame.Position.X==h.camera.CFrame.target.X and h.camera.CFrame.Position.Z==h.camera.CFrame.target.Z)
 assert(h.camera.CFrame.Position.Y>h.camera.CFrame.target.Y and h.camera.CFrame.up.Z==-1)
 assert(h.UIS.MouseBehavior=='Default'and h.UIS.MouseIconEnabled)
end)
test('zoom and pan move the overview without changing selected world points',function()
 local h=setup();h.app.startMapView(1);h.app.draft={{x=3,y=1,z=4}};h.app.renderMapView();local before=h.app.mapView.height
 h.app.mapView.zoom=.5;h.app.mapView.panX=10;h.app.renderMapView()
 assert(h.app.mapView.height==before*.5 and h.camera.CFrame.Position.X==10)
 assert(h.app.draft[1].x==3 and h.app.draft[1].z==4)
end)
test('camera and pre-existing HUD mouse and transparency states restore exactly',function()
 local h=setup();h.app.startMapView(1);h.app.renderMapView();h.app.stopMapView()
 assert(h.camera.CameraType=='Custom'and h.camera.FieldOfView==70 and h.camera.CFrame==h.original.frame)
 assert(h.camera.CameraSubject==h.original.subject and h.camera.Focus==h.original.focus)
 assert(h.screens.Gameplay.Enabled and h.screens.TouchGui.Enabled and not h.screens.Toolbar.Enabled)
 assert(h.floor.LocalTransparencyModifier==.15 and h.roof.LocalTransparencyModifier==.3)
 assert(h.UIS.MouseBehavior=='LockCenter'and not h.UIS.MouseIconEnabled and not h.bound())
 assert(h.app.mapView==nil)
end)
test('a replacement CurrentCamera is also restored when the editor closes',function()
 local h=setup();h.app.startMapView(1);h.app.renderMapView()
 local other={Parent=true,CameraType='Custom2',CameraSubject={},FieldOfView=65,ViewportSize={X=800,Y=600},CFrame=cf(vec(8,3,6)),Focus={}}
 h.workspace.CurrentCamera=other;h.app.renderMapView();assert(other.CameraType=='Scriptable')
 h.app.stopMapView();assert(other.CameraType=='Custom2'and other.FieldOfView==65 and h.camera.CameraType=='Custom')
end)
test('floor changes update the selectable geometry',function()
 local h=setup();h.app.startMapView(1);assert(h.app.mapLayer(11));assert(h.app.mapView.floors[1]==h.roof and h.floor.LocalTransparencyModifier==1)
end)
test('failed editor initialization restores partially hidden parts',function()
 local h=setup();assert(not h.app.startMapView(100));assert(h.app.mapView==nil)
 assert(h.floor.LocalTransparencyModifier==.15 and h.roof.LocalTransparencyModifier==.3)
end)
test('top view taps raycast only against the selected floor layer',function()
 local h=setup();h.app.startMapView(1);h.app.renderMapView();local hit=h.app.mapViewRay({X=100,Y=136})
 assert(hit and #h.rays==1);assert(h.rays[1].origin.X==100 and h.rays[1].origin.Z==100)
 assert(h.rays[1].filters==h.app.mapView.floors and h.rays[1].direction.Y<0)
end)
test('invalid polygons cannot overwrite the saved region',function()
 local h=setup();local saved={points={{x=1,y=1,z=1}}};local cfg={regions={Map1=saved}}
 local env=setmetatable({app=h.app,cfg=cfg,Core=Core},{__index=_G})
 h.app.region=function()return saved end;h.app.draft={{x=0,y=1,z=0}}
 assert(load(extract('    function app.commitArea()', '    function app.openMapEditor('),'commit','t',env))()
 assert(not h.app.commitArea()and cfg.regions.Map1==saved)
end)
test('new dot area clears an old map-part lock while saved edits preserve it',function()
 for _,clear in ipairs({true,false})do
  local h=setup();local surface={name='Floor'};local saved={surface=surface};local cfg={regions={Map1=saved}}
  local env=setmetatable({app=h.app,cfg=cfg,Core=Core},{__index=_G})
  h.app.region=function()return saved end;h.app.draft={{x=0,y=1,z=0},{x=20,y=1,z=0},{x=20,y=1,z=20},{x=0,y=1,z=20}}
  h.app.clearSurface=clear;local closed=false;h.app.closeMapEditor=function(ok)closed=ok end;h.app.changed=function()end
  assert(load(extract('    function app.commitArea()', '    function app.openMapEditor('),'commit','t',env))()
  assert(h.app.commitArea()and closed);assert((cfg.regions.Map1.surface==nil)==clear)
 end
end)
print(tests..' top-down editor checks passed')
