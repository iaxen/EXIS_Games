local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
local Core=assert(loadfile('Games/StealAnEgg.lua'))('EXIS_TEST');_G.Core=Core
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local V={};V.__index=function(t,k)if k=='Magnitude'then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
math.clamp=math.clamp or function(x,a,b)return math.max(a,math.min(b,x))end
local now,r,h,c,held,moves,restored,computed,afterWait
local function setup()
 now=0;os.clock=function()return now end;moves={};restored=0;computed=0;afterWait=nil
 c={};held={IsCarrying=true,Uid='u'};player={Character=c,UserId=1}
 r=setmetatable({Position=vec(0,3,0)},{__newindex=function(t,k,v)assert(k~='CFrame','return must never teleport');rawset(t,k,v)end})
 h={Parent=true,WalkSpeed=16,MoveTo=function(_,p)moves[#moves+1]=p;r.Position=vec(p.X,3,p.Z)end}
 character=function()return r,h,c end;carrying=function()return held end
 active=function()return true end;state={};options={master=true};motion={};note=function()end
 applyRunSpeed=function()end;restoreRunSpeed=function()restored=restored+1 end
 Enum={PathStatus={Success='Success'},PathWaypointAction={Jump='Jump'},HumanoidStateType={Physics='Physics',Ragdoll='Ragdoll',Dead='Dead'}}
 task={wait=function()now=now+.03;if afterWait then afterWait()end end}
 Pathfinding={CreatePath=function()return{Status='Success',ComputeAsync=function()computed=computed+1 end,
  GetWaypoints=function()return{{Position=vec(0,0,0)},{Position=vec(15,0,0)},{Position=vec(30,0,0)}}end}end}
 guardianRows=function()return{}end;newEggOpportunity=function()return false end
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
local function walker()return assert(load(extract('local function walk(goal,carryUid)', 'connections[#connections+1]=api.remotes.Treadmill')..'\nreturn walk'))()end
test('root height does not delay an already reached ground waypoint',function()
 assert(Core.reached(vec(0,3,0),vec(0,0,0),3))
 assert(not Core.reached(vec(0,20,0),vec(0,0,0),3))
 assert(walker()(vec(30,0,0),'u')and now<.2 and #moves==3 and restored==1)
end)
test('return uses Humanoid movement and the pre-pickup path without a fresh compute',function()
 state.returnPath={character=c,at=0,from=r.Position,goal=vec(30,0,0),points={{Position=vec(30,0,0)}}}
 assert(walker()(vec(30,0,0),'u')and computed==0 and state.returnPath==nil)
end)
test('a carry UID change stops the old route and restores movement state',function()
 afterWait=function()held={IsCarrying=true,Uid='other'}end
 assert(not walker()(vec(30,0,0),'u')and #moves==2 and restored==1)
end)
test('a non-carry routine walk yields immediately if an egg is acquired',function()
 assert(not walker()(vec(30,0,0))and computed==0 and #moves==1)
end)
test('an uncommitted routine walk yields when a better spawned egg becomes available',function()
 held={IsCarrying=false};newEggOpportunity=function()return true end
 assert(not walker()(vec(30,0,0))and computed==0 and #moves==1)
end)
test('a confirmed carry keeps its route even when another egg spawns',function()
 newEggOpportunity=function()return true end
 assert(walker()(vec(30,0,0),'u')and restored==1)
end)
test('native path rejection cancels the old movement target',function()
 Pathfinding.CreatePath=function()return{Status='NoPath',ComputeAsync=function()end}end
 assert(not walker()(vec(30,0,0),'u')and #moves==1 and restored==1)
end)
test('guard chase speed grows with gap and obeys the native maximum multiplier',function()
 local policy={DISTANCE_MULTIPLIER_STRENGTH=.5,MAX_DISTANCE_MULTIPLIER=4}
 assert(Core.guardSpeed(16,10,10,policy)==16)
 assert(Core.guardSpeed(16,10,20,policy)==24)
 assert(Core.guardSpeed(16,10,100,policy)==64)
end)
test('automatic running selects the fastest active chaser plus margin and reports caps',function()
 options.autoRunSpeed=true;options.runMargin=12;options.runSpeedCap=120
 local speed,capped=Core.runningSpeed(options,16,{{speed=60},{speed=100}})
 assert(speed==112 and not capped)
 options.runSpeedCap=80;speed,capped=Core.runningSpeed(options,16,{{speed=100}});assert(speed==80 and capped)
end)
test('fixed mode uses the selected speed and native mode performs no override',function()
 options.fixedRunSpeed=true;options.runSpeed=70;assert(Core.runningSpeed(options,16,{})==70)
 options.fixedRunSpeed=false;assert(Core.runningSpeed(options,16,{})==nil)
end)
test('speed overrides restore their original value and preserve a newer native correction',function()
 restoreRunSpeed,applyRunSpeed=assert(load(extract('local function restoreRunSpeed()', 'local function prepareReturnPath()')..'\nreturn restoreRunSpeed,applyRunSpeed'))()
 options.fixedRunSpeed=true;options.runSpeed=64
 applyRunSpeed(r,h);assert(h.WalkSpeed==64);restoreRunSpeed();assert(h.WalkSpeed==16)
 applyRunSpeed(r,h);h.WalkSpeed=20;restoreRunSpeed();assert(h.WalkSpeed==20)
end)
test('guard snapshot ignores guardians chasing another player',function()
 local function guard(target)
  return{Name='Guard',IsA=function(_,k)return k=='Model'end,GetAttribute=function(_,k)if k=='GuardState'then return'Chasing'elseif k=='TargetPlayer'then return target end end,
   FindFirstChild=function()return{Position=vec(-20,3,0)}end,FindFirstChildOfClass=function()return{WalkSpeed=16}end}
 end
 local own=guard('1');local other=guard('2')
 local area={Name='Forest',GetChildren=function()return{own,other}end}
 local folder={GetChildren=function()return{area}end}
 local areas={FindFirstChild=function()return folder end};local world={FindFirstChild=function()return areas end}
 workspace={FindFirstChild=function()return world end}
 api={balance={GuardChase={DISTANCE_MULTIPLIER_STRENGTH=.5,MAX_DISTANCE_MULTIPLIER=4}},areas={Directory={Forest={GuardId='Forest'}}},guards={Directory={Forest={WalkSpeed=16,FlatRadius=10,HitDistance=10}}}}
 optionalAPI=function()error('guardian snapshot must never load or yield during running')end
 options.autoRunSpeed=true;api.guards=nil;own.FindFirstChildOfClass=function()return{WalkSpeed=24}end
 local get=assert(load(extract('local function guardianRows()', 'local function restoreRunSpeed()')..'\nreturn guardianRows'))()
 local rows=get();assert(#rows==1 and rows[1].model==own and rows[1].speed==24)
end)
test('native escape-speed estimates defer targets above the selected cap',function()
 options.skipUnsafeEggs=true;options.autoRunSpeed=true;options.runSpeedCap=80
 local area={GetAttribute=function()return{X=100,Y=90}end}
 local guards={FindFirstChild=function()return area end};local areas={FindFirstChild=function()return guards end};local world={FindFirstChild=function()return areas end}
 workspace={FindFirstChild=function()return world end};api={balance={GuardRequirements={CARRY_SPEED_RATIO=.9}}}
 local preflight=assert(load(extract('local function escapePreflight(', 'local function stealEgg()')..'\nreturn escapePreflight'))()
 assert(not preflight({AreaId='Forest'},h));options.runSpeedCap=100;assert(preflight({AreaId='Forest'},h))
 options.autoRunSpeed=false;options.fixedRunSpeed=true;options.runSpeed=70;assert(not preflight({AreaId='Forest'},h))
end)
test('anchored or ragdolled characters are not forced into a running override',function()
 restoreRunSpeed,applyRunSpeed=assert(load(extract('local function restoreRunSpeed()', 'local function prepareReturnPath()')..'\nreturn restoreRunSpeed,applyRunSpeed'))()
 options.fixedRunSpeed=true;options.runSpeed=64;r.Anchored=true;applyRunSpeed(r,h);assert(h.WalkSpeed==16)
 r.Anchored=false;h.GetState=function()return'Ragdoll'end;applyRunSpeed(r,h);assert(h.WalkSpeed==16)
end)
print(n..' running route, carry priority and guardian speed checks passed')
