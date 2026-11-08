local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local V={};V.__index=function(p,k)if k=='Magnitude'then return math.sqrt(p.X*p.X+p.Y*p.Y+p.Z*p.Z)end return V[k]end
local function v(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function setup()
 local now,frames,commands=0,0,0
 local root={Position=v(5,3,0),AssemblyLinearVelocity=v(20,-1,4)}
 local human={MoveTo=function()commands=commands+1 end}
 local app={alive=true,mode='MATCH',mapId='Map1',className='Rookie',revision=1,notes={}}
 local cfg={autoPlace=true};local candidate={map='Map1',class='Rookie',revision=1,slot={x=0,z=0,name='Turret',spec={buildDuration=1}}}
 app.root=function()return root,human end;app.active=function()return app.alive end
 app.stopWalk=function()end;app.placementSafe=function()return true end;app.floorSupport=function()return true end
 app.note=function(k,n)app.notes[k]=n end;app.defenseBoxes=function()return{}end
 local onFrame
 local env=setmetatable({app=app,cfg=cfg,Vector3={new=v},os={clock=function()return now end},
 workspace={GetServerTimeNow=function()return 100+now end},
 task={wait=function()now=now+1/60;frames=frames+1;if onFrame then onFrame(now,frames)end end}},{__index=_G})
 assert(load(extract('    function app.freezePlacement(', '    function app.placeTick()'),'hold helpers','t',env))()
 return{app=app,cfg=cfg,root=root,candidate=candidate,now=function()return now end,frames=function()return frames end,
 onFrame=function(fn)onFrame=fn end,commands=function()return commands end}
end
test('a placement settles across two stable frames and clears horizontal momentum',function()
 local h=setup();local hold=h.app.stabilizePlacement(h.candidate)
 assert(hold and h.app.placing and h.frames()>=2 and h.commands()>=2)
 assert(h.root.AssemblyLinearVelocity.X==0 and h.root.AssemblyLinearVelocity.Z==0 and h.root.AssemblyLinearVelocity.Y==-1)
end)
test('a recent teleport gets a short replication settle window before placing',function()
 local h=setup();h.app.lastDodgeAt=0;assert(h.app.stabilizePlacement(h.candidate))
 assert(h.now()>=.12 and h.now()<.75)
end)
test('position drift during settling cancels the hold',function()
 local h=setup();h.onFrame(function()h.root.Position=v(7,3,0)end)
 assert(not h.app.stabilizePlacement(h.candidate)and not h.app.placing and not h.app.placementHold)
end)
test('damage or danger interrupts waiting without anchoring the character',function()
 for _,mode in ipairs({'danger','damage','floor'})do
  local h=setup();h.onFrame(function(now)
   if mode=='danger'then h.app.placementSafe=function()return false end
   elseif mode=='damage'then h.app.damageEvadeUntil=now+1
   else h.app.floorSupport=function()return false end
   end
  end)
  assert(not h.app.stabilizePlacement(h.candidate),mode)
  assert(not h.root.Anchored)
 end
end)
test('server acceptance waits for the matching defense and native build completion',function()
 local h=setup();local hold=h.app.stabilizePlacement(h.candidate)
 local attrs={Building=true,Built=false};local model={Parent=true,GetAttribute=function(_,k)return attrs[k]end}
 h.app.defenseBoxes=function()return{{model=model,owned=true,name='Turret',x=0,z=0}}end
 h.onFrame(function(now)if now>=.25 then attrs.Building=false;attrs.Built=true end end)
 assert(h.app.confirmPlacement(h.candidate,hold)and h.now()>=.25 and h.now()<.3)
 assert(h.app.placing);h.app.finishPlacementHold(hold);assert(not h.app.placing)
end)
test('native BuildEndServerTime can confirm construction when Built is not supplied',function()
 local h=setup();local hold=h.app.stabilizePlacement(h.candidate)
 local attrs={BuildEndServerTime=100.2};local model={Parent=true,GetAttribute=function(_,k)return attrs[k]end}
 h.app.defenseBoxes=function()return{{model=model,owned=true,name='Turret',x=0,z=0}}end
 assert(h.app.confirmPlacement(h.candidate,hold)and h.now()>=.199)
end)
test('a different owner type or grid slot cannot confirm this purchase',function()
 local h=setup();h.candidate.slot.spec.buildDuration=0;local hold=h.app.stabilizePlacement(h.candidate)
 local model={Parent=true,GetAttribute=function(_,k)if k=='Built'then return true end end}
 h.app.defenseBoxes=function()return{{model=model,owned=false,name='Turret',x=0,z=0},
 {model=model,owned=true,name='Wall',x=0,z=0},{model=model,owned=true,name='Turret',x=10,z=0},
 {model={Parent=false,GetAttribute=model.GetAttribute},owned=true,name='Turret',x=0,z=0}}end
 assert(not h.app.confirmPlacement(h.candidate,hold)and h.now()<3.2)
 assert(h.app.notes.defense:find('NOT CONFIRMED',1,true))
end)
test('map class area change or disabling placement cancels construction waiting',function()
 for _,kind in ipairs({'map','class','area','disabled'})do
  local h=setup();local hold=h.app.stabilizePlacement(h.candidate)
  h.onFrame(function()
   if kind=='map'then h.app.mapId='Map2'elseif kind=='class'then h.app.className='Medic'
   elseif kind=='area'then h.app.revision=2 else h.cfg.autoPlace=false end
  end)
  assert(not h.app.confirmPlacement(h.candidate,hold),kind)
 end
end)
print(tests..' stationary placement, native construction and interruption checks passed')
