-- Executes production adapters with native-style geometry/receipts. No live Roblox certification.
local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X^2+v.Y^2+v.Z^2)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
Vector3={new=vec};Vector2={new=function(x,y)return{Magnitude=math.sqrt(x*x+y*y)}end}
local F={};F.__index=F
local function frame(p,yaw)return setmetatable({Position=p,yaw=yaw or 0},F)end
function F:PointToWorldSpace(p)local c,s=math.cos(self.yaw),math.sin(self.yaw);return self.Position+vec(c*p.X+s*p.Z,p.Y,-s*p.X+c*p.Z)end
function F:PointToObjectSpace(p)local q=p-self.Position;local c,s=math.cos(self.yaw),math.sin(self.yaw);return vec(c*q.X-s*q.Z,q.Y,s*q.X+c*q.Z)end
function F:Inverse()local inv=frame(vec(0,0,0),-self.yaw);inv.Position=inv:PointToWorldSpace(self.Position*-1);return inv end
function F:ToObjectSpace(b)return self:Inverse()*b end
F.__mul=function(a,b)return frame(a:PointToWorldSpace(b.Position),a.yaw+b.yaw)end
CFrame={new=function(a,b,c)return frame(type(a)=='table'and a or vec(a or 0,b or 0,c or 0))end,Angles=function(_,yaw)return frame(vec(0,0,0),yaw)end}
local now,cfg,bag,stock,scene,r,h,hostiles,creatures,tiles,placed,blocked
local function object(name,class)
 local o={Name=name,ClassName=class or'Model',Parent=true,attrs={}}
 function o:IsA(c)return c==self.ClassName end
 function o:FindFirstChild(k)return self[k]end
 function o:FindFirstChildOfClass(k)return self[k]end
 function o:GetAttribute(k)return self.attrs[k]end
 return o
end
local function item(id,name,extra)
 local i={id=id,displayName=name};for k,v in pairs(extra or{})do i[k]=v end
 cfg.item.byId[id]=i;cfg.item.byDisplayName[name]=i;cfg.item.byName[name]=i;return i
end
local function setup()
 now=0;os.clock=function()return now end;bag={};stock={};hostiles={};creatures={};tiles={};placed={};blocked=false
 flags={bulkCollect=true,killShadow=true,combat=true,nightExplore=true,holdNight=true,progression=true,greatWall=true}
 opts={jobTimeout=15,retreatHealth=35,huntRadius=40,combatMargin=.75,avoidEnemies=true,onlyNeeded=true}
 cfg={item={byId={},byDisplayName={},byName={}},tool={byId={},byDisplayName={}},armour={byId={}},food={byId={}},recipe={byId={}},
  craftingContent={list={}},worldResource={byId={}},itemDrop={byId={}},freeBuild={byCnId={}},misc={furnaceMatter1Id='铁矿'}}
 item('wood','Wood');item('stone','Stone');item('ore','Iron Ore');item('axe','Axe',{recipeId='axe'})
 cfg.tool.byId.axe={atkDmg=15,toolType='axe',range=4};cfg.tool.byDisplayName.Axe=cfg.tool.byId.axe
 cfg.recipe.byId.axe={require_wood=4}
 config=function()return cfg end;tools=function()return bag end;count=function(name)return stock[name]or 0 end
 r={Position=vec(0,3,0),Size=vec(2,2,2)};h={HipHeight=2,Health=100,MaxHealth=100}
 root=function()return r,h end;pos=function(o)return o.point or o.CFrame and o.CFrame.Position end
 player={Character={},Name='Tester',GetAttribute=function()end};failed={};due={};campData={};furnaceData={};alive=true
 scene={Entities={},Tiles={GetChildren=function()return tiles end},['自由建筑']={GetChildren=function()return placed end}}
 function scene:FindFirstChild(n)return self[n]end
 world=function()return scene end;built=function()end;note=function()end
 typeof=function(o)return getmetatable(o)==V and'Vector3'or'Instance'end
 motion={serial=0,floor=function(p)return vec(p.X,0,p.Z)end,water=function(hit)return hit.water==true end}
 workspace={Terrain={},GetPartBoundsInBox=function()return blocked and{1}or{}end}
 Enum={RaycastFilterType={Include=1}};OverlapParams={new=function()return{}end};RaycastParams={new=function()return{}end}
 module=function()return{checkOverlap=function()return false end}end
 work={sent=0,needs={},resourceNeeds={},hostiles=function()return hostiles end,creatures=function()return creatures end,
  isNight=function()return true end,insideBorder=function()return true end,safeWorkPoint=function()return true end,
  safeResource=function()return true end,canCollect=function()return true end,bagState=function()return 1,15 end,
  pickupCandidate=function()end,resourceCandidate=function()end,huntCandidate=function()end,
  station=function()end,stationSynced=true,fireState=function()return{level=2}end,
  campDropAnchor=function()return{point=vec(0,0,0)}end,
  recipeAmounts=function(i)local out={}for k,n in pairs(cfg.recipe.byId[i.recipeId]or{})do local id=k:match('^require_(.+)$');if id then out[id]=n end end return out end,
  goalAmounts=function(g)return g.amounts or{}end,
  missing=function(amounts)local out={}for id,n in pairs(amounts)do local it=cfg.item.byId[id];if n>count(it.displayName)then out[id]=n-count(it.displayName)end end return out end}
 body('    function work.isShadow(', '    function work.meleeWeapon(')
 body('    function work.craftUnlocked(', '    function work.structureStation(')
 body('    function work.wallRecipe(', '    function work.followTrail(')
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
local function torch()
 local i=item('火把','Torch',{isLightSource=true});local stats={toolType='torch',range=4,atkDmg=0,useCd=.5}
 cfg.tool.byId[i.id]=stats;cfg.tool.byDisplayName.Torch=stats
 local t=object('Torch','Tool');t.Parent=player.Character;bag[#bag+1]=t;return t,stats
end
local function shadow()
 local m=object('Shadow');m.Humanoid={Health=100000};m.TorchHits={Value=0};m.attrs.TorchHitsMax=3;m.point=vec(4,3,0)
 hostiles={{model=m,human=m.Humanoid,point=m.point}};return m
end
local function wall()
 local i=item('木墙','Wood Wall',{recipeId='wall'});cfg.recipe.byId.wall={require_wood=3};cfg.freeBuild.byCnId[i.id]={}
 local asset={id=i.id,size=vec(8,4,2),offset=CFrame.new(1,0,0)}
 work.wallTemplate=function()return asset end
 work.wallGround=function(p)return vec(p.X,0,p.Z)end
 return asset
end
local function beach(x)
 local t=object('Beach Block 01');t.BoundingBox=object('BoundingBox','BasePart');t.BoundingBox.Size=vec(48,2,48);t.BoundingBox.CFrame=CFrame.new(x,0,0);tiles[#tiles+1]=t;return t
end
test('half-stud actions get dry approach positions instead of an impossible one-stud ring',function()
 body('    function motion.goals(', '    function motion.valid(')
 local p=vec(10,3,0);local goals=motion.goals(p,.5);assert(#goals==9)
 for _,g in ipairs(goals)do assert((g-p).Magnitude<=.5)end
end)
test('precise approaches still reject missing dry floors',function()
 body('    function motion.goals(', '    function motion.valid(')
 motion.floor=function()end;assert(#motion.goals(vec(10,3,0),.5)==0)
end)
test('a deposited station recipe crafts with an empty material bag',function()
 body('    function work.submitGoal(', '    function work.stockCount(')
 work.stationGoal=function()return{id='axe',info=cfg.item.byId.axe,recipe={wood=4}}end
 work.goalAmounts=function()return{wood=0}end
 local called=false;work.stationTick=function(g,key)assert(g.id=='axe'and key=='craft');called=true;return true end
 work.station=function()return{}end
 assert(work.submitGoal('craft',{kind='craft',id='axe',info=cfg.item.byId.axe})and called)
end)
test('native campfire recipe gates block an unavailable craft',function()
 cfg.craftingContent.list={{itemName='Axe',campfireLvl=3}};work.station=function()return{}end
 assert(not work.craftUnlocked{kind='craft',id='axe',info=cfg.item.byId.axe})
 work.fireState=function()return{level=3}end;assert(work.craftUnlocked{kind='craft',id='axe',info=cfg.item.byId.axe})
 work.stationSynced=false;assert(not work.craftUnlocked{kind='craft',id='axe',info=cfg.item.byId.axe})
end)
test('gear priority starts at fifteen capacity and excludes repeat quest products',function()
 assert(work.gearPriority{kind='craft',id='axe'})
 work.bagState=function()return 0,14 end;assert(not work.gearPriority{kind='craft',id='axe'})
 work.bagState=function()return 0,15 end;assert(not work.gearPriority{kind='craft',id='axe',questFor='axe'})
end)
test('partial bags keep collecting while a safe resource remains',function()
 work.resourceCandidate=function()return{}end
 assert(not work.bulkUnloadReady());assert(not work.batchReady({amounts={wood=4}},'progression'))
 work.bagState=function()return 15,15 end;assert(work.bulkUnloadReady()and work.batchReady({amounts={wood=4}},'progression'))
end)
test('completed ingredient batches and exhausted safe targets can return to base',function()
 stock.Wood=4;work.resourceCandidate=function()return{}end
 assert(work.batchReady({amounts={wood=4}},'progression'))
 work.resourceCandidate=function()end;assert(work.bulkUnloadReady())
end)
test('base sorting trips finish even when more field collection becomes possible',function()
 work.resourceCandidate=function()return{}end;work.bulkTrip=true;assert(work.bulkUnloadReady())
end)
test('native Chinese stone iron and wood drop names select the right mining category',function()
 body('    function work.resourceKind(', '    function work.resourceAllowed(')
 for id,name in pairs({['石头']='Stone',['铁矿']='Ore',['木头']='Wood'})do item(id,name);cfg.itemDrop.byId[id]={{itemCN=name}}end
 assert(work.resourceKind{dropId='石头'}=='stone');assert(work.resourceKind{dropId='铁矿'}=='iron');assert(work.resourceKind{dropId='木头'}=='tree')
end)
test('explicit stone and iron mining is allowed without a current recipe shortage',function()
 body('    function work.resourceEligible(', '    function work.alternativeWork(')
 flags.mineStone=true;motion.blocked={};work.resourceKind=function()return'stone'end;work.resourceAllowed=function()return true end;work.resourceTool=function()return{}end
 local m=object('Stone');m.attrs.resourceId='s';cfg.worldResource.byId.s={}
 assert(work.resourceEligible(m,'gather',false));assert(not work.resourceEligible(m,'progression',true))
 flags.mineStone=false;flags.mineIron=true;work.resourceKind=function()return'iron'end;assert(work.resourceEligible(m,'gather',false))
end)
test('Shadow requires a real native light-source tool and uses its torch counter',function()
 local m=shadow();assert(not work.shadowCandidate());local t,stats=torch()
 assert(work.shadowCandidate()==m and work.canHitMob(m,stats))
 assert(work.mobRemaining(m)==3);m.TorchHits.Value=1;assert(work.mobRemaining(m)==2)
 m.TorchHits.Value=3;assert(work.mobRemaining(m)==0 and not work.shadowCandidate())
end)
test('an axe cannot damage Shadow and a low-health player does not start a torch hunt',function()
 local m=shadow();torch();assert(not work.canHitMob(m,cfg.tool.byId.axe))
 h.Health=50;assert(not work.shadowCandidate());h.Health=100;work.isNight=function()return false end
 assert(not work.shadowCandidate())
end)
test('Treant remains an ordinary hostile rather than an invulnerable Shadow',function()
 local m=object('Treant');m.Humanoid={Health=200};assert(work.canHitMob(m,cfg.tool.byId.axe)and work.mobRemaining(m)==200)
end)
test('night exploration requires a loaded entity folder and no living hostiles',function()
 assert(work.nightClear());local m=shadow();assert(not work.nightClear())
 m.Humanoid.Health=0;assert(work.nightClear());scene.Entities=nil;assert(not work.nightClear())
end)
test('night pause resumes automatically when a new hostile is loaded',function()
 body('    function work.nightPaused(', '    function work.resourceKind(')
 assert(not work.nightPaused{key='chests'});shadow();assert(work.nightPaused{key='chests'})
end)
test('wall selection prefers the native three-wood recipe over non-wood alternatives',function()
 wall();item('brick','Brick Wall',{recipeId='brick'});cfg.recipe.byId.brick={require_stone=1};cfg.freeBuild.byCnId.brick={}
 assert(work.wallRecipe().id=='木墙'and work.wallRecipe().recipe.wood==3)
end)
test('beach plan contains three parallel layers with an entrance',function()
 local asset=wall();beach(0);local plan=work.wallPlan(asset);assert(#plan.slots==72 and plan.gate and plan.gateWidth>=10)
 local counts={};for _,s in ipairs(plan.slots)do counts[s.layer]=(counts[s.layer]or 0)+1 end
 assert(counts[1]==24 and counts[2]==24 and counts[3]==24)
end)
test('adjacent beach tiles do not build a wall across their shared interior edge',function()
 local asset=wall();beach(0);beach(48);assert(#work.wallPlan(asset).slots==108)
end)
test('the Basic Block station beach is enclosed even without any Beach-named tiles',function()
 local asset=wall();local t=beach(0);t.Name='Basic Block'
 local plan=assert(work.wallPlan(asset));assert(plan.regionTiles==1 and #plan.slots==72)
end)
test('the wall perimeter covers the connected base beach and every adjacent station tile',function()
 local asset=wall();beach(0).Name='Basic Block';beach(48);beach(96).Name='Station Ground'
 local station=object('Crafting Station');station.point=vec(96,3,0)
 work.models=function(key)return key=='stations'and{station}or{}end
 local plan=assert(work.wallPlan(asset))
 assert(plan.regionTiles==3 and plan.stationCount==1 and plan.uncoveredStations==0 and #plan.slots==144)
 for _,slot in ipairs(plan.slots)do
  local p=slot.box.Position
  assert(not(math.abs(p.X-24)<7 and math.abs(p.Z)<16),'internal walls must not split camp from its stations')
 end
end)
test('remote beach patches do not divert the base wall project',function()
 local asset=wall();beach(0).Name='Basic Block';beach(1000)
 local plan=assert(work.wallPlan(asset));assert(plan.regionTiles==1 and #plan.slots==72)
 for _,slot in ipairs(plan.slots)do assert(math.abs(slot.box.Position.X)<24)end
end)
test('streamed base-beach expansion invalidates the perimeter cache',function()
 local asset=wall();beach(0).Name='Basic Block'
 local first=assert(work.wallPlan(asset));assert(work.wallPlan(asset)==first)
 beach(48);local nextPlan=assert(work.wallPlan(asset))
 assert(first~=nextPlan and nextPlan.regionTiles==2 and #nextPlan.slots==108)
end)
test('the wall entrance prefers a dry land exit over the water-facing side',function()
 local asset=wall();beach(0).Name='Basic Block'
 work.wallGround=function(p)if p.X>20 then return vec(p.X,0,p.Z)end end
 local plan=assert(work.wallPlan(asset));assert(plan.gate.X>20)
end)
test('stations outside the loaded connected base region are reported as uncovered',function()
 local asset=wall();beach(0).Name='Basic Block';beach(1000)
 local station=object('Station');station.point=vec(1000,3,0)
 work.models=function(key)return key=='stations'and{station}or{}end
 local plan=assert(work.wallPlan(asset));assert(plan.uncoveredStations==1)
end)
test('a connected coast cannot expand camp walls across the entire island',function()
 local asset=wall();beach(0).Name='Basic Block'
 for i=1,20 do beach(i*48)end
 local plan=assert(work.wallPlan(asset));assert(plan.regionTiles==2 and #plan.slots==108)
end)
test('a wall site has supported corners and applies the model pivot offset',function()
 local asset=wall();beach(0);local site=assert(work.wallSite(work.wallRecipe()))
 assert((site.frame*asset.offset).Position.X==site.box.Position.X)
 assert((site.frame*asset.offset).Position.Z==site.box.Position.Z)
 assert(Vector3.new(site.box.Position.X-site.plan.gate.X,0,site.box.Position.Z-site.plan.gate.Z).Magnitude>=site.plan.gateWidth)
end)
test('water unsupported corners occupied buildings and borders block wall placement',function()
 local asset=wall();beach(0);work.wallGround=function()end;assert(not work.wallSite(work.wallRecipe()))
 work.wallGround=function(p)return vec(p.X,0,p.Z)end;scene.Buildings={};blocked=true;assert(not work.wallSite(work.wallRecipe()))
 blocked=false;work.insideBorder=function()return false end;assert(not work.wallSite(work.wallRecipe()))
end)
test('wall occupancy detects built segments and permits replacement after destruction',function()
 local asset=wall();beach(0);local site=assert(work.wallSite(work.wallRecipe()))
 local m=object('Wall');m.attrs.cnId=asset.id;m.BoundingBox={Position=site.box.Position};placed={m}
 assert(work.wallOccupied(site.box,asset)==m);m.attrs.hp=0;assert(not work.wallOccupied(site.box,asset));placed={};assert(not work.wallOccupied(site.box,asset))
end)
test('wall ground rays ignore constructed walls so existing segments are not stacked upward',function()
 body('    function work.wallGround(', '    function work.wallFooting(')
 workspace.Raycast=function(_,_,_,params)assert(params.FilterDescendantsInstances[1]==scene.Tiles and params.FilterDescendantsInstances[2]==workspace.Terrain);return{Position=vec(0,0,0),Normal=vec(0,1,0)}end
 assert(work.wallGround(vec(0,5,0)).Y==0)
end)
test('wall crafting follows the regular native catalogue when listed there',function()
 wall();cfg.craftingContent.list={{itemName='Wood Wall',campfireLvl=2}};cfg.freeBuildList={list={{itemId='木墙'}}}
 work.stationStock={wood=1};work.buildingStock={wood=99}
 local goal=work.wallGoal();assert(goal.stationKind=='crafting'and goal.amounts.wood==2 and goal.fireLevel==2)
end)
test('building-only wall recipes retain the building service and its stock',function()
 wall();cfg.freeBuildList={list={{itemId='木墙'}}};work.buildingStock={wood=2};work.stationStock={wood=99}
 local goal=work.wallGoal();assert(goal.stationKind=='building'and goal.amounts.wood==1)
end)
test('an unsupported wall catalogue reports a blocked craft without spending materials',function()
 wall();assert(not work.wallReady());assert(work.wallStage:find('EITHER NATIVE',1,true))
end)
test('a synced stock response does not pretend a missing physical intake exists',function()
 wall();cfg.freeBuildList={list={{itemId='木墙'}}};work.buildingSynced=true
 work.structureStation=function()end
 assert(not work.wallReady());assert(work.wallStage=='BUILDING STATION / INTAKE NOT LOADED')
end)
test('a regular table wall is runnable without a separate building station',function()
 wall();cfg.craftingContent.list={{itemName='Wood Wall',campfireLvl=2}}
 work.station=function()return{},{}end;work.structureStation=function()error('wrong station')end
 work.goalRunnable=function()return true end
 assert(work.wallReady()and work.wallStage=='ACQUIRING WALL MATERIALS')
end)
test('wall crafting waits for the native campfire unlock level',function()
 wall();cfg.craftingContent.list={{itemName='Wood Wall',campfireLvl=3}};work.station=function()return{},{}end
 assert(not work.wallReady()and work.wallStage=='CAMPFIRE LEVEL 3 REQUIRED')
end)
test('one wall can be crafted before a free safe perimeter slot is found',function()
 wall();cfg.craftingContent.list={{itemName='Wood Wall'}};stock.Wood=3
 work.station=function()return{},{}end;work.stationStock={};work.goalRunnable=function()return true end
 work.wallSite=function()error('crafting must not require placement geometry')end
 assert(work.wallReady())
 work.needItem=function()end;work.stationTick=function(goal,key)
  assert(goal.stationKind=='crafting'and key=='greatWall'and goal.recipe.wood==3)
  stock.Wood=0;stock['Wood Wall']=1;return true
 end
 assert(work.wallTick()and count('Wood Wall')==1)
 work.wallSite=function()end
 assert(not work.wallReady()and work.wallHaveItem and work.wallStage:find('WAITING FOR SAFE',1,true))
 work.wallCheckAt=0;work.wallSite=function()return{}end
 assert(work.wallReady(),'carried wall should resume placement once a slot becomes safe')
end)
test('wall job deposits three wood crafts the native output and places the carried segment',function()
 local asset=wall();beach(0);cfg.craftingContent.list={{itemName='Wood Wall'}}
 body('    function work.stationTick(', '    function work.choiceScore(')
 local zone={};work.station=function()return{},zone end;work.stationStock={};stock.Wood=3
 work.goalRunnable=function()return true end;work.needItem=function()end
 work.batchReady=function()error('complete wall recipe must not wait for bulk bag fill')end
 work.insideStation=function()return true end;work.prepareStationDrop=function()return true end
 work.running=function()return true end;work.await=function(_,fn)return fn()end
 local wood=object('Wood','Tool');wood.Parent=player.Character;tools=function()return{wood}end
 travel=function()return true end
 work.batchDrop=function(tool,n)assert(tool==wood and n==3);stock.Wood=0;work.stationStock.wood=3;return 3 end
 work.net=function(event)assert(event=='CraftingStationCraft');return{FireServer=function(_,id)
  assert(id==asset.id);stock['Wood Wall']=1;work.stationStock.wood=0
 end}end
 assert(work.wallReady()and work.wallTick()and count('Wood Wall')==1)
 local site={box=CFrame.new(0,2,0),frame=CFrame.new(0,2,0),asset=asset,index=1}
 work.wallSite=function()return site end;work.wallRetry={}
 call=function(_,_,id)
  assert(id==asset.id);local m=object('Wall');m.attrs.cnId=id;m.BoundingBox={Position=site.box.Position};placed={m};stock['Wood Wall']=0
 end
 assert(work.wallReady()and work.wallTick()and #placed==1 and count('Wood Wall')==0)
end)
test('wall planning readiness survives the immediate queue handoff recheck',function()
 work.wallGoal=function()return{info={displayName='Wood Wall'}}end;stock['Wood Wall']=1
 work.wallSite=function()return{}end
 assert(work.wallReady()and work.wallReady())
end)
test('wall placement needs both a replicated structure and an inventory deduction',function()
 local asset=wall();beach(0);stock['Wood Wall']=1
 travel=function()return true end;call=function()end;work.await=function(_,fn)return fn()end
 assert(not work.wallTick(),'sending the request is not a placement receipt')
 work.wallRetry={};work.wallSite=function()return{box=CFrame.new(0,2,0),frame=CFrame.new(0,2,0),asset=asset,index=1}end
 call=function()local m=object('Wall');m.attrs.cnId=asset.id;m.BoundingBox={Position=vec(0,2,0)};placed={m};stock['Wood Wall']=0 end
 assert(work.wallTick())
end)
test('empty placeholder recipes never become ready craft goals',function()
 cfg.recipe.byId.axe={};assert(not work.craftUnlocked{kind='craft',id='axe',info=cfg.item.byId.axe})
end)
test('short melee tools can approach outside their own minimum safety clearance',function()
 body('    function work.meleeClearance(', '    function work.safeWorkPoint(')
 body('    function work.stanceScore(', '    function work.retaliationTarget(')
 body('    function work.combatPosition(', '    function work.attackPlan(')
 opts.enemyReach=4;opts.safeCombat=true;work.enemyReach=function()return 4 end;work.isHostile=function()return true end
 work.lineOfSight=function()return true end;motion.clearSegment=function()return true end
 local target=object('Treant');target.point=vec(4,3,0)
 local point=work.combatPosition(target,{range=4,toolType='axe'})
 assert(point and work.stanceScore(point,target,{range=4,toolType='axe'}))
 assert((point-target.point).Magnitude>=work.meleeClearance(target,{range=4}))
end)
test('a complete native torch fight confirms three TorchHits without changing invulnerable Humanoid health',function()
 local t,stats=torch();local target=shadow();hostiles[1].attackable=true;hostiles[1].velocity=vec(0,0,0)
 body('    function work.meleeWeapon(', '    function work.clearSceneIndex(')
 body('    function work.strike(', '    local function blueprintReady(')
 local defend=assert(load(extract('    local function defend(', '    function work.pickupCandidate(')..'\nreturn defend'))()
 equip=function()end;work.setSprint=function()end;work.checkpoint=function()return true end
 work.running=function()return now<15 end;work.pause=function(_,seconds)now=now+(seconds or 0);return true end
 work.await=function(_,fn)if fn()then return true end;now=now+.1;return fn()end
 work.attackPlan=function(key)assert(key=='shadowHunt');return target,r.Position end
 work.stanceScore=function()return 1 end;work.attackPhase=function()return'unknown'end
 work.kite=function()end;work.recordGuard=function()end;work.danger=function()return 0,nil,1 end
 CFrame.lookAt=function(p)return CFrame.new(p)end
 local swings=0;function t:Activate()swings=swings+1;target.TorchHits.Value=target.TorchHits.Value+1 end
 work.activateWeapon=function(tool)tool:Activate();return true end
 assert(defend('shadowHunt')and swings==3 and target.TorchHits.Value==3 and target.Humanoid.Health==100000)
end)
test('new crafted armour is equipped using the native tool remote and a confirmed equip event',function()
 body('    function work.armourCandidate(', '    function work.craftUnlocked(')
 item('vest','Vest',{type='armour'});cfg.armour.byId.vest={typeCN='body',lvl=2}
 cfg.armour.byId.old={typeCN='body',lvl=1};work.equippedArmour={body='old'}
 local t=object('Vest','Tool');t.Parent=player.Character;bag={t};equip=function()end
 local called=false
 RS={Engine={Service={FindFirstChild=function()return{FindFirstChild=function()return{FireServer=function(_,tool)assert(tool==t);called=true;work.equippedArmour.body='vest'end}end}end}}}
 work.await=function(_,fn)return fn()end
 assert(work.equipArmour()and called and not work.armourCandidate())
end)
test('critical eating outranks ordinary attack jobs while escape remains first',function()
 body('    function work.criticalMeal(', '    function work.autoAttackTick(')
 body('    function work.rank(job)', '    function work.pick(')
 h.Health=20;assert(work.rank{key='eat'}<work.rank{key='autoAttack'}and work.rank{key='eat'}<work.rank{key='shadowHunt'})
 assert(work.rank{key='evade'}<work.rank{key='eat'})
end)
test('auto attack is not ready merely because a mob is inside the wider guard radius',function()
 body('    function work.criticalMeal(', '    function work.autoAttackTick(')
 work.meleeWeapon=function()return{},cfg.tool.byId.axe end
 work.enemy=function(range)assert(range==4);return nil end
 assert(not work.autoAttackReady())
 work.enemy=function()return{}end;work.stanceScore=function()end;assert(not work.autoAttackReady())
 work.stanceScore=function()return 1 end;assert(work.autoAttackReady())
end)
test('bulk pickup collects a whole available batch without submitting each individual item',function()
 body('    function work.collectModel(', '    function work.pickupEligible(')
 local pickups=assert(load(extract('    local function pickups(', '    function work.resourceCandidate(')..'\nreturn pickups'))()
 local drops={object('Wood'),object('Wood'),object('Wood')}
 for _,m in ipairs(drops)do m.point=vec(0,0,0);m.FindFirstChildWhichIsA=function()end end
 work.pickupCandidate=function()for _,m in ipairs(drops)do if m.Parent then return m end end end
 work.objective={kind='craft',amounts={wood=4}}
 work.pickupEligible=function()return true end;work.dropAllowed=function()return true end;work.needsDrop=function()return true end;work.interactPrompt=function()return nil end
 work.recordPickup=function()end;work.submitGoal=function()error('must not submit one item at a time')end
 travel=function()return true end
 call=function(_,_,m)stock[m.Name]=(stock[m.Name]or 0)+1;m.Parent=nil end
 work.await=function(_,fn)return fn()end
 assert(pickups('drops',true)and stock.Wood==3)
end)
test('field stockpiling rotates to stone then iron instead of selecting only nearby trees',function()
 body('    function work.resourceCandidate(', '    local function gatherResource(')
 local tree,stone,iron=object('Elf Tree'),object('Stone'),object('Iron')
 tree.attrs.resourceId='t';stone.attrs.resourceId='s';iron.attrs.resourceId='i'
 cfg.worldResource.byId={t={kind='tree'},s={kind='stone'},i={kind='iron'}}
 work.models=function()return{tree,stone,iron}end;work.resourceEligible=function()return true end
 work.resourceKind=function(info)return info.kind end
 nearest=function(list,predicate,score)local best,value;for _,m in ipairs(list)do local n=score(m);if predicate(m)and(not value or n>value)then best,value=m,n end end return best end
 work.lastHarvestKind='tree';assert(work.resourceCandidate('stockpile',false)==stone)
 work.lastHarvestKind='stone';assert(work.resourceCandidate('stockpile',false)==iron)
end)
test('an old pinned camp upgrade cannot outrank useful gear after fifteen slots',function()
 body('    function work.goalQueueRank(', '    function work.planProgression(')
 local camp={key='campfire:2',kind='fuel',rank=4,amounts={wood=10}}
 local gear={key='craft:axe',kind='craft',id='axe',rank=3,info=cfg.item.byId.axe}
 work.upgradeCandidates=function()return{camp,gear}end;work.signature=function()return'unchanged'end;work.goalRunnable=function()return true end
 work.objective=camp;work.objectiveSignature='unchanged';work.objectiveProgressAt=0
 assert(work.chooseUpgrade()==gear)
end)
test('optional construction batches wait for a full bag or complete ingredients',function()
 work.resourceCandidate=function()return{}end;work.recipeAmounts=function()return{wood=4}end
 cfg.build={byId={hut={assetId='Hut'}}};scene.Buildings={FindFirstChild=function()return{}end}
 stock.Wood=1;assert(not work.buildBatchReady(false))
 stock.Wood=4;assert(work.buildBatchReady(false))
 stock.Wood=1;work.bagState=function()return 15,15 end;assert(work.buildBatchReady(false))
end)
test('a missing essential campfire may be built before filling the bag',function()
 work.resourceCandidate=function()return{}end;work.recipeAmounts=function()return{wood=4}end
 cfg.build={byId={campfire={assetId='Campfire'}}};scene.Buildings={FindFirstChild=function()return{}end}
 stock.Wood=1;assert(work.buildBatchReady(false))
end)
test('iron nodes with mixed stone drops still belong to the iron mining category',function()
 body('    function work.resourceKind(', '    function work.resourceAllowed(')
 cfg.itemDrop.byId.mixed={{itemCN='Stone'},{itemCN='Iron Ore'}}
 assert(work.resourceKind{dropId='mixed',requireToolType='pickaxe'}=='iron')
end)
test('eighty-stud guard targets are ordinary hunts rather than immediate defence emergencies',function()
 body('    function work.combatUrgent(', '    function work.personalThreat(')
 local m=object('Treant');m.point=vec(70,3,0);hostiles={{model=m,point=m.point,human={Health=100},attackable=true}}
 work.enemyReach=function()return 4 end;opts.guardRadius=80
 assert(not work.combatUrgent())
 hostiles[1].point=vec(5,3,0);assert(work.combatUrgent())
end)
test('food gathering and equipment work outrank ordinary distant hostile hunting',function()
 body('    function work.rank(job)', '    function work.pick(')
 work.combatUrgent=function()return false end
 assert(work.rank{key='foodHunt'}<work.rank{key='combat'})
 assert(work.rank{key='craft'}<work.rank{key='combat'})
 work.combatUrgent=function()return true end;assert(work.rank{key='combat'}<work.rank{key='foodHunt'})
end)
test('a healthy combat job does not get interrupted by routine night shelter during approach',function()
 body('    function work.rank(job)', '    function work.pick(')
 work.shelterNeeded=function()return true end;work.combatUrgent=function()return true end
 assert(work.rank{key='nightHold'}>work.rank{key='combat'})
 h.Health=20;assert(work.rank{key='nightHold'}<work.rank{key='combat'})
end)
test('a queued night shelter is not discarded for an ordinary far-away hunt',function()
 body('    function work.rank(job)', '    function work.checkpoint(')
 body('    function work.interruptsInteraction(', '    function work.foodReserveTarget(')
 local fight={key='combat',ready=function()return true end};local shelter={key='nightHold',ready=function()return true end}
 work.combatUrgent=function()return false end;work.shelterNeeded=function()return true end
 work.jobEnabled=function()return true end;work.jobsByKey={nightHold=shelter};work.pendingHandoff='nightHold'
 assert(work.nextQueuedJob({fight,shelter},now)==shelter and work.pendingHandoff==nil)
end)
test('a native-range counter finishes its hit window despite an unknown incoming animation',function()
 body('    function work.combatUrgent(', '    function work.baseThreat(')
 body('    function work.strike(', '    local function blueprintReady(')
 local target=object('Treant');target.point=vec(3,3,0);target.Humanoid={Health=50}
 work.active='combat';work.shadowThreat=function()end;work.incomingThreat=function()return target end
 work.danger=function()return 0,target,1 end;work.attackPhase=function()return'unknown'end
 work.meleeWeapon=function()return{}, {range=4,windup=.2,useCd=1}end
 work.stanceScore=function()return 1 end;work.checkpoint=function()return work.personalThreat()==nil end
 work.pause=function(_,seconds)now=now+seconds;return work.checkpoint()end
 equip=function()end;work.setSprint=function()end
 local t=object('Axe','Tool');t.Parent=player.Character;local swings=0
 work.activateWeapon=function()
  swings=swings+1
  for i=1,5 do now=now+.05;assert(not work.personalThreat(),'counter was evaded before the native hit window')end
  target.Humanoid.Health=40;return true
 end
 assert(work.strike(t,{range=4,windup=.2,useCd=1},{target},{},'combat')and swings==1 and target.Humanoid.Health==40)
end)
test('counter commitment does not suppress evasion after damage known strikes or crowding',function()
 body('    function work.combatUrgent(', '    function work.personalThreat(')
 local target=object('Treant');target.point=vec(3,3,0)
 work.attackCommit={target=target,expires=1,health=100};work.danger=function()return 0,target,1 end
 h.Health=90;assert(not work.counterWindow(target,'combat'))
 h.Health=100;work.attackPhase=function()return'strike'end;assert(not work.counterWindow(target,'combat'))
 work.attackPhase=function()return'unknown'end;work.danger=function()return 0,target,3 end;assert(not work.counterWindow(target,'combat'))
end)
test('completed evade recovery prevents immediately restarting the same attack job',function()
 local enemyReady=assert(load(extract('    local function enemyReady()', '    function work.needItem(')..'\nreturn enemyReady'))()
 work.evadeRecoverUntil=2;work.meleeWeapon=function()return{},{}end;work.attackPlan=function()return{}end
 assert(not enemyReady());now=2.1;assert(enemyReady())
end)
test('full wooden wall is preferred over a cheaper half wall',function()
 wall();local half=item('木半墙','Wood Half Wall',{recipeId='half'});cfg.recipe.byId.half={require_wood=1};cfg.freeBuild.byCnId[half.id]={}
 assert(work.wallRecipe().id=='木墙')
end)
test('immediate player contact takes targeting priority over a more distant camp mob',function()
 body('    function work.attackPlan(', '    local function defend(')
 local near,far=object('NearMob'),object('CampMob');near.point=vec(53,3,0);far.point=vec(10,3,0)
 near.Humanoid={Health=100};far.Humanoid={Health=100}
 hostiles={{model=near,point=near.point,human=near.Humanoid,attackable=true},{model=far,point=far.point,human=far.Humanoid,attackable=true}}
 r.Position=vec(50,3,0);opts.baseRadius=45;opts.guardRadius=80;opts.dangerRadius=20
 built=function()return{point=vec(0,3,0)}end;work.enemyReach=function()return 4 end
 work.combatPosition=function(m)return m.point,10 end
 assert(work.attackPlan('combat',{range=4,toolType='axe'})==near)
end)
test('resource strikes activate the bound native tool and never send a raw hit report',function()
 body('    function work.strike(', '    local function blueprintReady(')
 local tree=object('Tree');tree.point=vec(2,0,0);local tool=object('Axe','Tool');tool.Parent=player.Character
 equip=function()end;work.pause=function()return true end;work.checkpoint=function()return true end
 work.resourceReach=function()return true end;work.setSprint=function()end
 local activated=0;work.activateWeapon=function(t,stats,target,key)assert(t==tool and target==tree and key=='questAcquire');activated=activated+1;return true end
 RS={Events={meleeHitRemote={FireServer=function()error('raw resource hit packet must not be sent')end}}}
 assert(work.strike(tool,{range=4,useCd=.8},{},{tree},'questAcquire')and activated==1 and work.harvestRequests==1)
end)
test('resource tool selection rejects matching tools with zero harvesting damage',function()
 body('    function work.resourceTool(', '    function work.boatId(')
 local axe=object('Axe','Tool');local torchTool=object('Torch','Tool');bag={torchTool,axe}
 cfg.tool.byDisplayName.Torch={toolType='axe',useDmg=0};cfg.tool.byDisplayName.Axe.useDmg=2
 assert(work.resourceTool{requireToolType='axe'}==axe)
 bag={torchTool};now=.1;assert(not work.resourceTool{requireToolType='axe'})
end)
test('resource reach requires native part overlap rather than model-pivot distance alone',function()
 body('    function work.resourceReach(', '    function work.harvestPosition(')
 local tree=object('Tree');tree.point=vec(2,0,0)
 workspace.GetPartBoundsInRadius=function()return{}end
 assert(not work.resourceReach(r.Position,tree,{range=4}))
 workspace.GetPartBoundsInRadius=function()return{{FindFirstAncestorOfClass=function()return tree end}}end
 assert(work.resourceReach(r.Position,tree,{range=4}))
end)
test('native resource line of sight aims two studs above the resource pivot',function()
 body('    function work.resourceReach(', '    function work.harvestPosition(')
 local tree=object('Tree');tree.point=vec(2,0,0)
 workspace.Raycast=function(_,from,delta)assert((from+delta).Y==2);return nil end
 assert(work.resourceReach(r.Position,tree,{range=4}))
end)
test('quest acquisition is the sole quest-material planner instead of racing progression',function()
 body('    function work.upgradeCandidates()', '    function work.stationGoal(')
 item('feather','Chicken Feather');work.questRequirement={itemId='feather',count=1}
 work.questAcquireGoal=function()error('candidate planning must not recursively invoke acquisition')end
 work.questDrops=function()return{}end;work.questTotal=function()return 0 end
 work.bagGoal=function()end;work.campfireGoal=function()end;work.maintenanceGoal=function()end
 selected={craft={}};itemLabel=function(_,id)return id end
 for _,goal in ipairs(work.upgradeCandidates())do assert(goal.kind~='quest'and not goal.questFor)end
end)
test('failed native harvesting backs off the resource candidate search',function()
 body('    function work.resourceCandidate(', '    local function gatherResource(')
 work.harvestRetryAt=3;work.models=function()error('must not rescan during harvest backoff')end
 assert(not work.resourceCandidate('questAcquire',true))
end)
test('a disabled native tool is awaited without pretending an activation was sent',function()
 body('    function work.activateWeapon(', '    function work.setSprint(')
 local tool=object('Axe','Tool');tool.Parent=player.Character;tool.Enabled=false
 work.await=function()return false end;tool.Activate=function()error('disabled tool must not activate')end
 assert(not work.activateWeapon(tool,{toolType='axe'},{},'questAcquire'))
end)
local function harvestSimulation(damage,baseline,timeSlice)
 body('    function work.resourceReach(', '    local function gatherResource(')
 body('    function work.strike(', '    local function blueprintReady(')
 body('    function work.activateWeapon(', '    function work.setSprint(')
 local gather=assert(load(extract('    local function gatherResource(', '    function work.chestState(')..'\nreturn gatherResource'))()
 local tree=object('Tree');tree.point=vec(6,0,0);tree.attrs.resourceId='Tree'
 function tree:GetPivot()return CFrame.new(self.point)end
 cfg.worldResource.byId.Tree={hp=baseline==nil and 6 or baseline,requireToolType='axe',dropId='tree'}
 if baseline and baseline>0 then tree.attrs.hp=baseline end
 local stats={toolType='axe',range=4,useDmg=2,useCd=.8,windup=.4}
 local tool=object('Axe','Tool');tool.Parent=player.Character;tool.Enabled=true
 scene.Static={};opts.move='Teleport';opts.jobTimeout=timeSlice or 90
 local scheduled,times={},{};local cut=0
 local function advance(dt)
  now=now+dt
  for _,e in ipairs(scheduled)do if not e.done and now>=e.at then e.done=true;tree.attrs.hp=math.max(0,(tree.attrs.hp or 6)-2)end end
 end
 function tool:Activate()
  if #times>0 then assert(now-times[#times]>=.799,'native cooldown was bypassed')end
  times[#times+1]=now
  if damage then scheduled[#scheduled+1]={at=now+.4+.0667+.2}end
 end
 work.models=function(kind)return kind=='resources'and{tree}or{}end
 work.resourceEligible=function(m)return m.Parent and not(failed[m]and failed[m]>now)end
 nearest=function(list,predicate)for _,m in ipairs(list)do if predicate(m)then return m end end end
 work.resourceTool=function()return tool,stats end;work.resourceKind=function()return'tree'end
 work.treeDropContext=function()return{center=tree.point,wanted={wood=1}}end
 work.running=function()return now<90 end;work.checkpoint=function()return true end
 work.pause=function(_,dt)advance(dt);return true end;work.setSprint=function()end
 work.await=function(_,predicate,seconds)
  local deadline=now+seconds
  repeat if predicate()then return true end;advance(.05)until now>=deadline
  return predicate()
 end
 work.recordCut=function()cut=cut+1 end;work.setRecovery=function(c)work.treeDrops=c end
 work.recoverTreeDrops=function()stock.Wood=1;work.treeDrops=nil;return true end
 equip=function()end;travel=function(p)r.Position=p;return true end;CFrame.lookAt=function(p)return CFrame.new(p)end
 RS={Engine={FindFirstChild=function()return nil end},Events={meleeHitRemote={FireServer=function()error('native cycle required')end}}}
 workspace.GetPartBoundsInRadius=function(_,p,range)
  return Vector3.new(p.X-tree.point.X,0,p.Z-tree.point.Z).Magnitude<=range and{{FindFirstAncestorOfClass=function()return tree end}}or{}
 end
 local result=gather('questAcquire',true)
 return result,times,cut,tree
end
test('wood harvesting waits for delayed native hits and collects only after confirmed resource depletion',function()
 local result,times,cut,tree=harvestSimulation(true)
 assert(result and #times==3 and cut==1 and tree.attrs.hp==0 and stock.Wood==1)
 assert(work.harvestRequests==3 and work.harvestReceipts==3)
end)
test('three unconfirmed native harvest cycles back off without inventing a cut or collected wood',function()
 local result,times,cut,tree=harvestSimulation(false)
 assert(not result and #times==3 and cut==0 and not stock.Wood)
 assert(failed[tree]>=now+9.9 and work.harvestRetryAt>=now+2.9)
 assert(work.harvestStatus:find('USE DAMAGE 2',1,true)and work.harvestStatus:find('CONFIG 6',1,true))
 assert(not work.resourceCandidate('questAcquire',true))
end)
test('zero configuration health without a replicated HP value is not proof of a cut',function()
 local result,times,cut=harvestSimulation(false,0)
 assert(not result and #times==3 and cut==0 and not stock.Wood)
end)
test('productive harvesting completes one resource even beyond the configured task slice',function()
 local result,times,cut,tree=harvestSimulation(true,40,15)
 assert(result and #times==20 and cut==1 and tree.attrs.hp==0 and now>15)
end)
test('native cooldown expiry does not activate during frame-rounded recovery',function()
 body('    function work.activateWeapon(', '    function work.setSprint(')
 local t=object('Axe','Tool');t.Parent=player.Character;t.Enabled=true
 work.frameDuration=.03;work.pause=function(_,seconds)now=now+seconds;return true end
 local idleAt,cdUntil,attempts,accepted=0,0,0,0
 function t:Activate()
  attempts=attempts+1
  if now>=idleAt then accepted=accepted+1;idleAt=now+.63;cdUntil=now+.57 end
 end
 local oldRequire=require;require=function()return{getCooldownState=function()return math.max(0,cdUntil-now)end}end
 RS={Engine={FindFirstChild=function()return{FindFirstChild=function()return{FindFirstChild=function()return{}end}end}end}}
 for i=1,3 do assert(work.activateWeapon(t,{toolType='axe',useCd=.57},{},'questAcquire'))end
 require=oldRequire
 assert(attempts==3 and accepted==3 and now>=1.31 and now<1.4 and work.nextStrikeAt>=now+.65)
end)
test('Long Run restores disabled essentials in one action including walls while retaining fishing and replay choices',function()
 body('    work.automationBundles =', '    function work.makeSuiteUI(p)')
 flags={autoFarm=false,greatWall=false,fish=true,autoRound=false,escape=true,craft=false,progression=false,bulkCollect=false,tidyTools=false}
 local saved,cancelled,rendered=false,false,false
 save=function()saved=true end;say=function()end;motion.cancel=function()cancelled=true end
 toggles={test=function()rendered=true end}
 opts.chestHoldPadding=4;work.chestHoldField={Text='4'}
 work.applyLongRun()
 assert(opts.chestHoldPadding==.15 and work.chestHoldField.Text=='0.15')
 assert(flags.autoFarm and flags.quest and flags.choiceRewards and flags.chests and flags.antiAfk)
 assert(flags.craft and flags.progression and flags.buildCurrent and flags.mineIron and flags.smelt and flags.killShadow)
 assert(flags.bulkCollect and flags.tidyTools and flags.unloadBag and flags.cook and flags.eat)
 assert(not flags.escape and flags.greatWall and flags.fish and not flags.autoRound)
 assert(opts.onlyNeeded and opts.fastHarvest and opts.safeCombat and opts.interval==0 and saved and cancelled and rendered)
end)
test('quick controls reflect partial settings and change only their own group',function()
 body('    work.automationBundles =', '    function work.makeSuiteUI(p)')
 body('    function work.makeSuiteUI(p)', '    local main=page(')
 local controls,buttons={},{}
 group=function(_,name,open)return{name=name,open=open}end
 switch=function(_,label,get,set)controls[label]={get=get,set=set};return function()end end
 toggle=function()end;number=function()end;work.slider=function()end;text=function()return{}end
 button=function(_,label,fn)buttons[label]=fn;return{}end
 make=function()return{Text='',FocusLost={Connect=function()end}}end;corner=function()end
 Color3={fromRGB=function()return{}end};UDim2={new=function()return{}end};Enum.Font={BuilderSans=1}
 save=function()end;say=function()end;motion.cancel=function()end;toggles={}
 opts.evadeMove='Teleport';opts.codes='';flags={autoFarm=false,eat=true,fish=true}
 work.makeSuiteUI({main={},combat={},gather={},survival={},food={},inventory={},craft={},camp={},explore={},quests={},rounds={},rewards={},esp={},status={},settings={}})
 assert(not flags.autoFarm and not flags.quest,'building the menu must preserve saved settings')
 local survival=controls['Survival and food'];assert(survival.get()==nil)
 survival.set(true);assert(survival.get()==true and flags.eat and flags.killShadow and not flags.quest and flags.fish)
 survival.set(false);assert(survival.get()==false and not flags.eat and not flags.killShadow and flags.fish)
 assert(buttons['START LONG RUN • ENABLE ESSENTIALS']==work.applyLongRun)
 local wallControl=assert(controls['AUTO CRAFT & PLACE BEACH WALLS']);wallControl.set(true);assert(flags.greatWall and wallControl.get())
 buttons['ENABLE ALL BEACH STATIONS']();assert(flags.buildCamp and flags.buildCurrent and flags.structureCraft and flags.progression)
 local count=0;for _ in pairs(controls)do count=count+1 end;assert(count>=7)
end)
test('station footprints stay wholly on the base beach including shared tile seams',function()
 wall();beach(0).Name='Basic Block';beach(48)
 assert(work.inBaseBeach(vec(24,2,0),vec(8,4,8)))
 assert(not work.inBaseBeach(vec(70,2,0),vec(8,4,8)))
 work.wallGround=function()return nil end
 assert(not work.inBaseBeach(vec(0,2,0),vec(8,4,8)))
end)
test('every live camp blueprint is available for material acquisition rather than only the campfire',function()
 body('    function work.upgradeCandidates()', '    function work.stationGoal(')
 cfg.build={byId={}}
 for _,name in ipairs({'Campfire','Furnace','Water Maker','Crafting Station'})do cfg.build.byId[name]={assetId=name}end
 local folder={FindFirstChild=function()return{}end};scene.Buildings=folder
 flags.buildCamp=true;work.boatId=function()return'boat'end;work.buildRank=function()return 2 end
 itemLabel=function(_,id)return id end;work.bagGoal=function()end;work.campfireGoal=function()end
 selected={craft={}};work.questAcquireGoal=function()end
 local found={}
 for _,goal in ipairs(work.upgradeCandidates())do if goal.kind=='build'then found[goal.info.assetId]=true end end
 assert(found.Campfire and found.Furnace and found['Water Maker'] and found['Crafting Station'])
end)
test('utility stations are recognized without treating decorative walls as stations',function()
 body('    function work.structureRole(', '    function work.findStructure(')
 assert(work.structureRole('建筑制作台')=='buildingStation')
 assert(work.structureRole('制作台')=='craftingStation')
 assert(work.structureRole('Water Maker')=='water' and work.structureRole('Cooking Station')=='cooking')
 assert(work.structureRole('Wood Wall')=='other')
end)
test('station construction diagnostics distinguish built unfinished and unavailable models',function()
 cfg.build={byId={fire={assetId='Campfire'},furnace={assetId='Furnace'},water={assetId='Water Maker'}}}
 built=function(name)if name=='Campfire'then return{}end end;work.boatId=function()return'boat'end
 scene.Buildings={FindFirstChild=function(_,name)if name=='Furnace_Construct'then return{}end end}
 local report=work.beachStationReport()
 assert(report:find('Campfire: BUILT',1,true)and report:find('Furnace: NEEDS CONSTRUCTION',1,true)and report:find('Water Maker: NOT LOADED / NOT OFFERED',1,true))
end)
test('a six-hundred-slot blocked wall plan checks at most twelve sites per batch and advances',function()
 local asset=wall();local plan={slots={},regionTiles=60,stationCount=2,uncoveredStations=0}
 for i=1,600 do plan.slots[i]={box=CFrame.new(i*10,0,0),layer=1}end
 work.wallPlan=function()return plan end;module=function()return{checkOverlap=function()return true end}end
 local rays=0;work.wallGround=function(p)rays=rays+1;return vec(p.X,0,p.Z)end
 work.wallFooting=function()return true end
 assert(not work.wallSite(work.wallRecipe())and rays==12 and work.wallScan.index==13)
 assert(not work.wallSite(work.wallRecipe())and rays==24 and work.wallScan.index==25)
 assert(work.wallStatus:find('LAST BATCH 12 CHECKED',1,true))
end)
test('readiness and execution reuse a checked wall site without repeating its ground rays',function()
 local asset=wall();beach(0).Name='Basic Block'
 local plan=assert(work.wallPlan(asset));work.wallPlan=function()return plan end
 local rays=0;work.wallGround=function(p)rays=rays+1;return vec(p.X,0,p.Z)end
 local recipe=work.wallRecipe();local site=assert(work.wallSite(recipe));local initial=rays
 assert(work.wallSite(recipe)==site and rays==initial and work.wallSiteHits==1)
end)
test('unchanged base geometry reuses region results while newly streamed tiles invalidate them',function()
 wall();beach(0).Name='Basic Block';local first=work.wallRegion();assert(work.wallRegion()==first)
 beach(48);local second=work.wallRegion();assert(second~=first and #second==2)
end)
test('performance diagnostics retain slow elapsed work and label remote waits honestly',function()
 body('    function work.recordCost(', '    function work.boundedRead(')
 work.recordCost('wallSite',.08);work.recordCost('wallSite',.02);work.recordCost('RPC ChestService.isOpened',6.5)
 assert(work.costs.wallSite.calls==2 and work.costs.wallSite.slow==1 and work.costs.wallSite.max==.08)
 local report=work.performanceReport()
 assert(report:find('REMOTE WAITS INCLUDED',1,true)and report:find('6500',1,true)and report:find('not CPU attribution',1,true))
end)
assert(loadfile('Games/MrbeastIslandEscape.lua'))
print(n..' automation, native geometry, bulk collection, gear, Shadow and wall checks passed; module compiles')
