local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local Core=assert(load(source:sub(1,assert(source:find('-- Runtime adapters.',1,true))-1)..'\nreturn Core'))()
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function square(n)return{{x=0,y=0,z=0},{x=n,y=0,z=0},{x=n,y=0,z=n},{x=0,y=0,z=n}}end
local turret={name='AutoTurret',role='turret',w=3,d=3,grid=1}
local wall={name='Barricade',role='wall',w=5,d=2,grid=1,blocking=true}
local function close(a,b)assert(math.abs(a-b)<.0001,tostring(a)..' ~= '..tostring(b))end

test('layout has one outer barricade row and three separate inner turret rows',function()
 local p,reason,reserve,c=Core.plan(square(60),{turret,wall},256)
 assert(#p>20 and reserve==nil and #c.layers==4 and c.fitted==3)
 assert(c.layers[1].name=='BARRICADE')
 for n=2,4 do assert(c.layers[n].name=='TURRET '..(n-1)and c.layers[n].inset>c.layers[n-1].inset)end
 assert(reason:find('MIDDLE SPACING 12',1,true))
 for i,a in ipairs(p)do for j,b in ipairs(p)do if i~=j then assert(not Core.overlap(a,b,0))end end end
end)
test('a native-grid rectangular part closes the outer barricade and all three turret rows without corner gaps',function()
 local p,reason,_,c=Core.plan(square(40),{turret,wall},256)
 assert(#c.layers==4 and #p<256 and not reason:find('GAPS',1,true))
 for _,row in ipairs(c.layers)do assert(row.coverage and row.coverage.uncovered<.001)end
 assert(c.floor.uncovered>0) -- intentional middle spacing remains.
end)
test('middle barricades are distributed about twelve studs apart with nearby shooting defenses',function()
 local p,_,_,c=Core.plan(square(60),{turret,wall},512)
 local barriers,guns={},{}
 for _,box in ipairs(p)do if box.layer=='MIDDLE'then if box.role=='wall'then barriers[#barriers+1]=box elseif box.role=='turret'then guns[#guns+1]=box end end end
 assert(#barriers>=4 and #guns>=4 and c.floor.uncovered>0)
 for i,a in ipairs(barriers)do
  for j,b in ipairs(barriers)do if i~=j then assert(math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)>=11.5)end end
  local covered=false;for _,gun in ipairs(guns)do if gun.anchor==a.anchor then covered=true end end
  assert(covered)
 end
 assert(#p<512) -- no attempt to spend the entire limit filling the middle.
end)
test('a low defense budget stays bounded and reports incomplete border rows',function()
 local p,reason,_,c=Core.plan(square(60),{turret,wall},8)
 assert(#p<=8 and reason:find('ROWS HAVE GAPS / LIMITS',1,true)and #c.layers==4)
end)
test('small selected floors report that three turret rows cannot fit',function()
 local _,reason,_,c=Core.plan(square(16),{turret,wall},128)
 assert(c.fitted<3 and reason:find('/3 TURRET ROWS',1,true))
end)
test('native boundary cells may touch the chosen floor edge while concave cuts remain protected',function()
 assert(Core.fits({x=1.5,z=1.5},3,3,square(24),true))
 local notch={{x=0,y=0,z=0},{x=30,y=0,z=0},{x=30,y=0,z=30},{x=20,y=0,z=30},{x=20,y=0,z=10},{x=10,y=0,z=10},{x=10,y=0,z=30},{x=0,y=0,z=30}}
 assert(not Core.fits({x=15,z=15},22,4,notch,true))
end)
test('full-area coverage is a footprint union and never double-counts overlap',function()
 local c=Core.areaCoverage(square(20),{{x=5,z=10,w=10,d=20},{x=10,z=10,w=10,d=20}})
 close(c.covered,300);close(c.uncovered,100)
end)
test('sloped boundaries clip deployment footprints without counting outside coverage',function()
 local diamond={{x=0,y=0,z=10},{x=10,y=0,z=0},{x=0,y=0,z=-10},{x=-10,y=0,z=0}}
 local c=Core.areaCoverage(diamond,{{x=0,z=0,w=10,d=10}});close(c.area,200);close(c.covered,100)
 c=Core.areaCoverage(diamond,{{x=0,z=0,w=40,d=40}});close(c.uncovered,0)
end)
test('a narrow floor hole is detected even when every turret has a large firing range',function()
 local boxes={{x=4.9,z=10,w=9.8,d=20,range=1000},{x=15.1,z=10,w=9.8,d=20,range=1000}}
 close(Core.areaCoverage(square(20),boxes).uncovered,8)
end)
test('perimeter interval checks detect sub-grid gaps and ignore nonblocking turrets',function()
 local ring=square(20)
 local boxes={{x=4.9,z=0,w=9.8,d=2,role='wall'},{x=15.1,z=0,w=9.8,d=2,role='wall'},
  {x=10,z=0,w=20,d=2,role='turret'}}
 local c=Core.wallCoverage(ring,boxes)
 close(c.uncovered,58.4)
end)
test('existing wall footprints and clockwise selection keep placements on all sides',function()
 local poly=square(40);poly[2],poly[4]=poly[4],poly[2]
 local plan,_,_,c=Core.plan(poly,{turret,wall},80,{{x=20,z=4,w=5,d=2,role='wall',blocking=true}})
 local edges={}
 for _,box in ipairs(plan)do
  assert(Core.fits(box,box.w,box.d,poly,true))
  if box.role=='wall'and not box.fill then edges[box.edge]=true end
 end
 assert(edges[1]and edges[2]and edges[3]and edges[4]and c.floor.uncovered>=0)
end)
test('nonrotatable native barriers never request an invented yaw',function()
 local p=Core.plan(square(24),{turret,wall},100)
 for _,box in ipairs(p)do if box.name=='Barricade'then assert(box.facing==0 and box.w==5 and box.d==2)end end
 local rotating={name='ReconWall',role='wall',w=5,d=2,grid=1,canRotate=true,blocking=true}
 local rotated=false
 local diamond={{x=0,y=0,z=20},{x=20,y=0,z=0},{x=40,y=0,z=20},{x=20,y=0,z=40}}
 for _,box in ipairs(Core.plan(diamond,{turret,rotating},100))do if box.name=='ReconWall'and box.facing%2==1 then rotated=true;assert(box.w==2 and box.d==5)end end
 assert(rotated)
end)
test('planner yields bounded batches so a dense layout does not starve live combat',function()
 local yields=0
 Core.plan(square(24),{turret,wall},128,{},function()yields=yields+1 end)
 assert(yields>0)
end)
test('layout reconciles placed pending and destroyed defenses without duplicate cells',function()
 local boxes={};local app={mapId='Map1',className='Rookie',revision=1,alive=true,pendingPlacements={}}
 local cfg={maxDefenses=128}
 app.defenseBoxes=function()return boxes end;app.specs=function()return{turret}end
 app.placementRegion=function()return{points=square(18)}end;app.note=function()end
 local env=setmetatable({app=app,cfg=cfg,Core=Core,task={wait=function()end},os={clock=function()return 0 end}},{__index=_G})
 assert(load(extract('    function app.layout()', '    function app.coverageStatus()'),'layout','t',env))()
 local first=app.layout();assert(#first>5);local oldKey=app.planKey
 local slot=first[1]
 app.pendingPlacements.p={slot=slot,expires=5}
 local pending=app.layout();assert(app.planKey~=oldKey and #pending<=127)
 for _,b in ipairs(pending)do assert(not Core.overlap(b,slot,0))end
 boxes={{x=slot.x,z=slot.z,w=slot.w,d=slot.d,role='turret',name='AutoTurret',owned=true}}
 local confirmed=app.layout();assert(#confirmed<=127);local confirmedKey=app.planKey
 app.pendingPlacements={};boxes={};local repaired=app.layout();assert(app.planKey~=confirmedKey and #repaired==#first)
end)
test('adjacent native grid cells remain available and an actual overlap is rejected',function()
 local now=0;local app={pendingPlacements={p={slot={x=6,z=0,w=2,d=2},expires=5}}}
 app.defenseBoxes=function()return{{x=0,z=0,w=2,d=2}}end
 local env=setmetatable({app=app,Core=Core,os={clock=function()return now end}},{__index=_G})
 assert(load(extract('    function app.occupied(', '    function app.getPlacement('),'occupied','t',env))()
 assert(not app.occupied{x=2,z=0,w=2,d=2})
 assert(app.occupied{x=1.9,z=0,w=2,d=2})
 assert(app.occupied{x=6,z=0,w=2,d=2});now=6;assert(not app.occupied{x=6,z=0,w=2,d=2})
end)
test('boundary visibility works independently of automation and tracks map changes',function()
 local points=square(20);local drawn,cleared=0,0
 local app={mapId='Map1',revision=1,mode='MATCH',editing=false};local cfg={showBoundary=false,enabled=false}
 app.region=function()return{points=points}end
 app.drawRegion=function(p,closed)assert(p==points and closed);drawn=drawn+1 end
 app.clearMarkers=function()cleared=cleared+1 end
 local env=setmetatable({app=app,cfg=cfg},{__index=_G})
 assert(load(extract('    function app.syncBoundary(', '    function app.specs()'),'boundary','t',env))()
 app.syncBoundary();assert(cleared==1 and drawn==0)
 cfg.showBoundary=true;app.syncBoundary();assert(drawn==1)
 app.syncBoundary();assert(drawn==1)
 app.editing=true;app.syncBoundary();assert(cleared==2)
 app.editing=false;app.mapId='Map2';app.syncBoundary();assert(drawn==2)
 cfg.showBoundary=false;app.syncBoundary();assert(cleared==3 and #points==4)
end)
test('Area exposes only part picking saved editing and the visibility switch',function()
 local controls,opened={},{}
 local app={openMapEditor=function(mode)opened[#opened+1]=mode end};local cfg={showBoundary=false}
 local ui={button=function(_,text,fn)controls[#controls+1]={text=text,fn=fn}end,
  toggle=function(_,text,object,key)assert(object==cfg and key=='showBoundary');controls[#controls+1]={text=text,toggle=true}end}
 local env=setmetatable({ui=ui,app=app,cfg=cfg,area={}},{__index=_G})
 assert(load(extract('    ui.button(area, "PICK MAP PART"', '    local system = ui.group(settings'),'area controls','t',env))()
 assert(#controls==3 and controls[1].text=='PICK MAP PART'and controls[2].text=='EDIT SAVED BOUNDARY'and controls[3].toggle)
 controls[1].fn();controls[2].fn();assert(opened[1]=='part'and opened[2]=='saved')
end)
print(tests..' layered border, spaced middle, repair and boundary controls checks passed')
