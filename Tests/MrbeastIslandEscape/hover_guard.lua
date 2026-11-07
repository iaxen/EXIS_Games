local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
math.clamp=function(n,a,b)return math.max(a,math.min(b,n))end
local V={};V.__index=function(p,k)if k=='Magnitude'then return math.sqrt(p.X*p.X+p.Y*p.Y+p.Z*p.Z)end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
local CF={};CF.__add=function(a,b)return setmetatable({Position=a.Position+b},CF)end
local function frame(p)return setmetatable({Position=p},CF)end
local now,props,r,h,rows,scene,camp,events,collisions
local function setup()
 now=0;rows={};events={};collisions={};os.clock=function()return now end
 flags={autoFarm=true,holdNight=true,nightHover=true,quest=true};opts={hoverHeight=8,enemyReach=4,combatMargin=1,shadowRadius=20,exploreOutsideBorder=false}
 player={Character={GetChildren=function()return{}end},Name='Tester'}
 props={Position=vec(0,3,0),Size=vec(2,2,2),CFrame=frame(vec(0,3,0)),Parent=true,Anchored=false,CollisionGroup='Characters'}
 r=setmetatable({},{__index=props,__newindex=function(_,k,v)props[k]=v;if k=='CFrame'then props.Position=v.Position end end})
 h={Health=100,MaxHealth=100,HipHeight=2}
 scene={FindFirstChild=function()return nil end};camp={point=vec(0,0,0)}
 root=function()return r,h end;world=function()return scene end;built=function()return camp end;pos=function(m)return m.point end
 config=function()return{item={byDisplayName={}}}end
 Vector3={new=vec};CFrame={new=frame};OverlapParams={new=function()return{}end};Enum={RaycastFilterType={Exclude='Exclude'}}
 workspace={GetPartBoundsInBox=function(_,cf,size,params)workspace.last={cf=cf,size=size,params=params};return collisions end}
 motion={floor=function(p)return vec(p.X,0,p.Z)end}
 work={isNight=function()return true end,hostiles=function()return rows end,enemyReach=function()return 4 end,
  insideBorder=function(p)return p.X*p.X+p.Z*p.Z<10000 end,safeWorkPoint=function()return true end}
 travel=function()return true end;note=function(k,text)events[#events+1]=text end
 body('    function work.shelterNeeded()', '    function work.evaluateLost()')
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
local function enemy(name,x,z)
 local model={Name=name,Parent=true};local row={model=model,human={Health=100},point=vec(x,0,z),velocity=vec(0,0,0),attackable=name~='Shadow'}
 rows[#rows+1]=row;return row
end

test('a nearby Shadow remains a threat despite vertical hover separation',function()
 enemy('Shadow',0,0);assert(work.hoverClearance(vec(0,40,0))<0)
 assert(work.nightHold());assert(work.hover.height==8 and work.hoverClearance(r.Position)>=0 and r.Position.Y==11)
end)
test('a threat approaching a parked hover causes lateral relocation without climbing',function()
 assert(work.nightHold());local old=r.Position
 enemy('Spider',old.X,old.Z);now=.2;assert(work.hoverTick())
 assert(work.hover.height==8 and(r.Position-old).Magnitude>=10 and work.hoverClearance(r.Position)>=0)
end)
test('unexplained damage lowers the hover and persistent damage switches to checked ground for this night',function()
 assert(work.nightHold())
 h.Health=90;now=.2;work.hoverTick();assert(work.hover and work.hover.height==6)
 h.Health=80;now=.4;work.hoverTick();assert(not work.hover and not r.Anchored and r.Position.Y==3 and work.hoverSuppressed)
 assert(not work.shelterNeeded())
 work.isNight=function()return false end;assert(not work.shelterNeeded()and not work.hoverSuppressed)
end)
test('a severe unexplained hit stops hover immediately instead of waiting for another damaging tick',function()
 assert(work.nightHold());h.Health=60;now=.2;work.hoverTick()
 assert(not work.hover and not r.Anchored and work.hoverSuppressed)
end)
test('a ground fallback does not freeze the airborne guard while its landing is still unsafe',function()
 assert(work.nightHold());work.safeWorkPoint=function()return false end
 for index=1,3 do now=index*.2;h.Health=100-index*10;work.hoverTick()end
 assert(work.hover and work.hoverSuppressed and r.Anchored)
 local old=r.Position;enemy('Spider',old.X,old.Z);now=.9;work.hoverTick()
 assert(work.hover and(r.Position-old).Magnitude>=10)
end)
test('body overlap rejects a hover point inside a collidable object',function()
 collisions={{CanCollide=true}};assert(not work.nightHold()and not r.Anchored)
 assert(workspace.last.size.X==3 and workspace.last.params.CollisionGroup=='Characters')
end)
test('disabling the optional night hold allows routine work instead of anchoring the player',function()
 flags.holdNight=false;assert(not work.shelterNeeded());assert(work.nightHold()and not work.hover and not r.Anchored)
end)
test('the independent heartbeat guard reacts while a native fuel or meal request is yielding',function()
 assert(work.nightHold());local old=r.Position
 local callback;connections={};game={GetService=function()return{Heartbeat={Connect=function(_,fn)callback=fn;return{}end}}end}
 safely=function(_,fn)return fn()end;alive=true
 body('    local hoverElapsed=0', '    task.spawn(function()\n        while alive do\n            safely("live status"')
 work.active='fuel';enemy('Spider',old.X,old.Z);now=.2;callback(.16)
 assert((r.Position-old).Magnitude>=10)
end)
test('stop restores the anchor state that existed before the script owned it',function()
 r.Anchored=true;assert(work.nightHold());assert(work.releaseHover(true)and r.Anchored)
end)
test('the border exception is restricted to exploration and explicit combat checks retain the border',function()
 work.borderState=function()return vec(0,0,0),30 end
 body('    function work.insideBorder(', '    function work.meleeClearance(')
 local point=vec(60,0,0);assert(not work.insideBorder(point,nil,'chests'))
 opts.exploreOutsideBorder=true
 for _,key in ipairs({'chests','puzzles','artifacts','travel'})do assert(work.insideBorder(point,nil,key),key)end
 for _,key in ipairs({'combat','hunt','foodHunt','fuel','nightHold','gather'})do assert(not work.insideBorder(point,nil,key),key)end
end)
test('exploration readiness applies its scope temporarily and restores it even if a probe fails',function()
 opts.exploreOutsideBorder=true;work.borderState=function()return vec(0,0,0),30 end
 body('    function work.insideBorder(', '    function work.meleeClearance(')
 body('    function work.pick(', '    function work.nextQueuedJob(')
 due={};work.rank=function()return 5 end;work.jobEnabled=function()return true end
 local point=vec(60,0,0);local job={key='chests',ready=function()assert(work.insideBorder(point));return true end}
 assert(work.pick({job},0)==job and work.readinessKey==nil)
 job.ready=function()error('probe rejected')end;assert(work.pick({job},0)==nil and work.readinessKey==nil)
end)
test('quest polling continues on a short bounded cadence while other jobs run',function()
 body('    function work.survivalSync()', '    local jobsList = {')
 work.survivalScene=scene;local polls=0;work.readQuest=function(force)assert(force);polls=polls+1 end;work.readObjectiveHints=function()end
 work.active='gather';work.survivalSync();now=.7;work.survivalSync();assert(polls==1)
 now=.76;work.survivalSync();assert(polls==2)
end)
print(n..' reactive night hover, landing, exploration scope and persistent quest checks passed')
