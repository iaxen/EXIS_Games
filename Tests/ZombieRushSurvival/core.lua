local f=assert(io.open('Games/ZombieRushSurvival.lua'));local source=f:read('*a');f:close()
local cut=assert(source:find('-- Runtime adapters.',1,true))
local Core=assert(load(source:sub(1,cut-1)..'\nreturn Core'))()
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function square(n)return{{x=0,y=0,z=0},{x=n,y=0,z=0},{x=n,y=0,z=n},{x=0,y=0,z=n}}end
local specs={
 {name='AutoTurret',role='turret',w=3,d=3,grid=1},
 {name='Barricade',role='wall',w=5,d=2,grid=1},
 {name='ExplosiveBarrel',role='trap',w=2,d=2,grid=1}}
test('valid polygon accepts clockwise and counterclockwise boundaries',function()
 assert(Core.validPolygon(square(40)));local p=square(40);p[2],p[4]=p[4],p[2];assert(Core.validPolygon(p))
end)
test('crossing edges cannot define a build area',function()
 local p=square(40);p[2],p[3]=p[3],p[2];assert(not Core.validPolygon(p))
end)
test('too few dots and duplicate adjacent dots are rejected',function()
 assert(not Core.validPolygon({{x=0,y=0,z=0}}));local p=square(40);p[2]=p[1];assert(not Core.validPolygon(p))
end)
test('nonfinite coordinates and overlarge vertex lists are rejected',function()
 local p=square(40);p[1].x=0/0;assert(not Core.validPolygon(p));p={};for i=1,25 do p[i]={x=i,y=0,z=i}end;assert(not Core.validPolygon(p))
end)
test('point containment handles horizontal and vertical edges',function()
 local p=square(20);assert(Core.inside({x=10,z=10},p));assert(Core.inside({x=0,z=10},p));assert(not Core.inside({x=-1,z=10},p))
end)
test('whole footprints must stay inside the selected polygon',function()
 assert(Core.fits({x=10,z=10},3,3,square(20)));assert(not Core.fits({x=1,z=1},4,4,square(20)))
end)
test('a concave notch cannot be bridged by a rectangle',function()
 local p={{x=0,y=0,z=0},{x=30,y=0,z=0},{x=30,y=0,z=30},{x=20,y=0,z=30},{x=20,y=0,z=10},{x=10,y=0,z=10},{x=10,y=0,z=30},{x=0,y=0,z=30}}
 assert(Core.validPolygon(p));assert(not Core.fits({x=15,z=15},22,4,p))
end)
test('class defense roles match turret barricade healing and ability mechanics',function()
 assert(Core.role('HealingStation',{Heal={}})=='support');assert(Core.role('BuffBarricade',{Classification={Barricade=true}})=='wall')
 assert(Core.role('Barricade',{Style='Barrier',Physics={ZombieBlocking=true}})=='wall');assert(Core.role('FlameBarricade',{})=='wall')
 assert(Core.role('AutoTurret',{})=='turret');assert(Core.role('ReconGhost',{Placement={Ability=true}})=='ability');assert(Core.role('LureBomb',{})=='trap')
end)
test('no phantom support space is left when the selected class has no support defense',function()
 local plan,_,reserve=Core.plan(square(40),specs,18);assert(#plan>0 and reserve==nil)
end)
test('planned slots remain in bounds touching only at legal cell edges and obey the limit',function()
 local p=square(40);local plan=Core.plan(p,specs,18);assert(#plan<=18 and #plan>3)
 for i,a in ipairs(plan)do assert(Core.fits(a,a.w,a.d,p,true));for j,b in ipairs(plan)do if i~=j then assert(not Core.overlap(a,b,0))end end end
end)
test('blocking barricades are planned on all four border sides',function()
 local plan=Core.plan(square(40),specs,64);local sides={}
 for _,s in ipairs(plan)do if s.role=='wall'and not s.fill then sides[s.edge]=true end end
 assert(sides[1]and sides[2]and sides[3]and sides[4])
end)
test('medic support is placed in its reserved space while turrets cover separate border positions',function()
 local medic={{name='PulseTurret',role='turret',w=3,d=3},{name='BuffBarricade',role='wall',w=5,d=2},{name='HealingStation',role='support',w=4,d=4,range=24}}
 local plan,_,reserve=Core.plan(square(40),medic,64);local healer,turrets=0,0
 for _,s in ipairs(plan)do if s.name=='HealingStation'then healer=healer+1;assert(Core.containsBox(s,reserve))elseif s.role=='turret'then turrets=turrets+1 end end
 assert(healer==1 and turrets>=4)
end)
test('a tiny selection reports uncovered space instead of inventing a complete layout',function()
 local plan,reason,_,coverage=Core.plan(square(5),specs,18)
 assert(#plan<=18 and (not coverage or coverage.floor.uncovered>0)and not reason:find('FULL AREA PLAN READY',1,true))
end)
test('planning work is bounded on excessively large areas',function()
 local plan,reason=Core.plan(square(1000),specs,18);assert(#plan==0 and reason:find('SMALLER'))
end)
test('native grid parity is respected for odd and even footprints',function()
 local plan=Core.plan(square(40),specs,18)
 for _,s in ipairs(plan)do assert((s.x-s.w*.5)%1==0 and (s.z-s.d*.5)%1==0)end
end)
test('boss priority beats a closer regular zombie',function()
 assert(Core.targetScore(300,true,true,false)>Core.targetScore(3,false,true,false))
 assert(Core.targetScore(300,true,false,false)<Core.targetScore(3,false,false,false))
end)
test('existing defenses cannot be overwritten by new slots',function()
 local existing={{x=20,z=20,w=6,d=6}}
 local plan,_,reserve=Core.plan(square(40),specs,18,existing)
 assert(reserve==nil)
 for _,slot in ipairs(plan)do assert(not Core.overlap(slot,existing[1],0))end
end)
test('all selected structural roles receive slots when enough space is available',function()
 local plan=Core.plan(square(60),specs,256);local found={}
 for _,slot in ipairs(plan)do found[slot.name]=true end
 assert(found.AutoTurret and found.Barricade and found.ExplosiveBarrel)
end)
assert(loadfile('Games/ZombieRushSurvival.lua'))
print(tests..' planning checks passed; complete module compiles')
