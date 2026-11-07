local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local V={};V.__index=function(t,k)if k=='Magnitude'then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
V.Dot=function(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
Vector3={new=vec}
local now,rows,r,h,lastMove,enemy
local function setup()
 now=0;os.clock=function()return now end;rows={};lastMove=nil
 opts={avoidEnemies=true,threatScanRadius=180,dangerRadius=20,shadowRadius=60,retreatHealth=35,enemyReach=4,combatMargin=1,evadeMove='Teleport'}
 flags={combat=true,runShadow=true};r={Position=vec(0,3,0),Size=vec(2,2,2)};h={Health=100,MaxHealth=100,HipHeight=2}
 root=function()return r,h end;work={hostiles=function()return rows end,insideBorder=function()return true end,enemyReach=function()return 4 end,
 shadowThreat=function()end,attackPhase=function()return'unknown'end,meleeWeapon=function()return{},{}end,attackPlan=function()return{}end,
 retargetEvade=function()return false end,active='gather'}
 pos=function(model)return model.point end
 motion={floor=function(p)return vec(p.X,0,p.Z)end,clearSegment=function()return false end}
 travel=function(point,key,_,mode)assert(key=='evade'and mode=='Teleport');lastMove=point;r.Position=point;return true end
 note=function()end
 body('    function work.projectedEnemyGap(', '    function work.automationOn()')
 body('    function work.personalThreat()', '    function work.baseThreat()')
 body('    function work.evade(key)', '    function work.enemy(')
 body('    function work.safeDestination(', '    function work.combatClear(')
end
local function hostile(x,z,vx,vz,name)
 local m={Name=name or'Spider',Parent=true,point=vec(x,3,z or 0)}
 rows[#rows+1]={model=m,point=m.point,velocity=vec(vx or 0,0,vz or 0),human={Health=50},attackable=true}
 return m
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('a fast approaching enemy triggers evasion fifty studs away before any damage',function()
 enemy=hostile(50,0,-30,0);assert(work.personalThreat()==enemy and h.Health==100 and work.observedHealth==100)
end)
test('the wide scan sees distant enemies without treating every distant mob as immediate contact',function()
 hostile(150,0,0,0);local margin,_,seen=work.threatEnvelope(r.Position,1.25)
 assert(seen==1 and margin>100 and not work.personalThreat())
end)
test('a receding enemy does not create a false predicted hit',function()
 hostile(50,0,30,0);assert(not work.incomingThreat(r.Position)and not work.personalThreat())
end)
test('closest approach is checked across the prediction interval rather than only at its endpoint',function()
 hostile(-35,0,100,0);assert(work.incomingThreat(r.Position))
end)
test('gathering yields before entering a stationary hostile buffer',function()
 enemy=hostile(18,0);assert(work.personalThreat()==enemy and h.Health==100)
end)
test('fresh evade recovery prevents immediate reengagement with an incoming windup',function()
 enemy=hostile(40,0,-20,0);work.active='combat';work.attackPhase=function()return'windup'end;work.evadeRecoverUntil=2
 assert(work.personalThreat()==enemy)
end)
test('an evade endpoint near a predicted enemy position is rejected despite lower current risk',function()
 hostile(60,0,-30,0);work.active='evade'
 assert(not work.safeDestination(vec(20,3,0),'evade'))
end)
test('evasion seeks a dry predicted-clear landing without requiring teleport travel through the wall segment',function()
 hostile(10,0,-6,0);hostile(-10,0,6,0);assert(work.evade('evade')and lastMove)
 assert(work.threatEnvelope(lastMove,1.25)>=3 and work.evadeRecoverUntil==2)
end)
test('escape never lands outside the unlocked boundary',function()
 hostile(8,0);work.insideBorder=function(point)return point.Magnitude<50 end
 assert(work.evade('evade')and lastMove.Magnitude<50)
end)
test('no valid landing reports failure rather than teleporting into danger',function()
 hostile(8,0);motion.floor=function()end
 assert(not work.evade('evade')and not lastMove)
end)
test('unknown living creature configs remain detectable instead of being silently filtered out',function()
 local m={Name='NewHostile',Parent=true,GetAttribute=function()end,FindFirstChildOfClass=function()return{Health=100}end,
 FindFirstChild=function()return{AssemblyLinearVelocity=vec(0,0,0)}end}
 config=function()return{mob={byId={}}}end;Players={GetPlayerFromCharacter=function()end}
 work.models=function()return{m}end;work.isNight=function()return false end;pos=function()return vec(10,3,0)end
 body('    function work.mobInfo(', '    function work.projectedEnemyGap(')
 local creatures=work.creatures(true);assert(#creatures==1 and creatures[1].hostile and work.hostiles(true)[1].model==m)
end)
print(n..' proactive hostile detection, prediction and checked escape tests passed')
