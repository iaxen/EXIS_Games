-- Production native-rule, recovery and refuge helpers in deterministic fixtures.
local f=assert(io.open('Games/MrbeastIslandEscape.lua'));local source=f:read('*a');f:close()
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__mul=function(a,n)return vec(a.X*n,a.Y*n,a.Z*n)end
V.__div=function(a,n)return vec(a.X/n,a.Y/n,a.Z/n)end
V.Dot=function(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
Vector3={new=vec}
local now,r,h,cfg,rows,objects,tiles,scene,notes,requests,fights,moves
local function object(name,point)
 local m={Name=name,Parent=true,point=point or vec(0,3,0),attrs={}}
 function m:GetAttribute(k)return self.attrs[k]end
 function m:FindFirstChild(k)return self[k]end
 function m:FindFirstChildWhichIsA(k)return k=='ProximityPrompt'and self.prompt end
 function m:FindFirstChildOfClass(k)return k=='Humanoid'and self.human end
 function m:IsA(k)return k=='Model'end
 return m
end
local function setup()
 fireproximityprompt=nil
 now=0;os.clock=function()return now end;notes={};requests={};fights=0;moves=0;rows={};tiles={}
 objects={artifacts={},chests={},explore={}}
 cfg={mapLock={byCnId={}},mob={byName={['蜘蛛']={id='Spider'}},byId={Spider={id='Spider'},Bear={id='Bear'}}}}
 opts={jobTimeout=90,retreatHealth=55,health=75,combatMargin=.75,dangerRadius=24,shadowRadius=70,useRefuge=false,keepRefugeLocked=false,unlockObjectives=true,evadeMove='Teleport'}
 flags={artifacts=true,chests=true,combat=true,autoAttack=true,autoFarm=true}
 r={Position=vec(0,3,0),Size=vec(2,2,2)};h={Health=100,MaxHealth=100,HipHeight=2,GetAttribute=function()return 100 end}
 root=function()return r,h end;pos=function(m)return m.point end;config=function()return cfg end
 scene={Seed={Value=99},Tiles={GetChildren=function()return tiles end}}
 function scene:FindFirstChild(k)return self[k]end
 world=function()return scene end;player={Character={}};motion={serial=1,floor=function(p)return vec(p.X,0,p.Z)end}
 due={};failed={};toggles={};save=function()end;say=function()end
 note=function(k,v)notes[k]=v end
 travel=function(point,key,_,mode)moves=moves+1;r.Position=point;return true end
 work={artifacts={},models=function(k)return objects[k]or{}end,hostiles=function()return rows end,
  insideBorder=function()return true end,safeResource=function()return true end,safeWorkPoint=function()return true end,
  stormActive=function()return false end,lineOfSight=function()return false end,enemyReach=function()return 4 end,
  isShadow=function(m)return m.Name=='Shadow'end,
  mobInfo=function(m)return cfg.mob.byId[m.Name]end,isHostile=function(m)return m.Name~='Chicken'end,
  projectedEnemyGap=function(row,p)return(p-row.point).Magnitude end,
  chestKnowledgeFor=function(m)m.knowledge=m.knowledge or{};return m.knowledge end,chestOpened=function(m)return m.opened==true end,
  readChestField=function(m,field)return field=='opened'and m.opened==true or field=='locked'and m.locked~=false end,
  campDropAnchor=function()end,campDropPoint=function()end,
  interactPrompt=function()return true,true end,
  await=function(_,predicate,seconds)if predicate()then return true end;now=now+(seconds or 0);return predicate()end}
 defend=function(key)
  assert(key=='unlockObjective'and work.unlockWork);fights=fights+1
  for _,row in ipairs(rows)do if work.unlockTargetMatches(row.model,work.unlockWork)then row.human.Health=0;return true end end
  return false
 end
 call=function(service,op,m)requests[#requests+1]=op;if op=='requestSolve'then m.solved=true end;return op=='isSolved'and m.solved==true end
 body('    function work.unlockRule(', '    function work.artifactCandidate()')
end
local function goal(kind,trigger,name)
 local m=object(name or(kind=='chests'and'Chest'or'Compass'),vec(20,3,0))
 m.attrs.MapLockCnId='lock';m.attrs.MapLockTileId='A';m.prompt={Enabled=false,MaxActivationDistance=8,HoldDuration=5,Parent=m}
 cfg.mapLock.byCnId.lock={unlockTrigger=trigger};objects[kind]={m}
 return m
end
local function enemy(name,tile,x)
 local m=object(name,vec(x or 15,3,0));m.attrs.spawnBlockId=tile;m.human={Health=50}
 local row={model=m,point=m.point,human=m.human,attackable=true,hostile=true};rows[#rows+1]=row;return m
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end

test('native kill ratio is parsed without turning a ratio into a guessed kill count',function()
 local m=goal('artifacts','击杀地块内任意怪物50%');local rule=work.unlockRule(m)
 assert(rule.kind=='kill_ratio'and rule.ratio==.5)
end)
test('native specific kill rules resolve the live Chinese mob name',function()
 local m=goal('chests','击杀地块内蜘蛛x3');local rule=work.unlockRule(m)
 assert(rule.kind=='kill_mob_count'and rule.mobId=='Spider'and rule.count==3)
end)
test('native puzzle rules keep the required puzzle ID and count',function()
 local m=goal('artifacts','解谜石柱x2');local rule=work.unlockRule(m)
 assert(rule.kind=='puzzle_count'and rule.puzzleId=='石柱'and rule.count==2)
end)
test('unknown rules never authorize random mob kills',function()
 goal('chests','pay 20 coins');assert(not work.unlockObjectiveTick()and fights==0)
 assert(notes.unlockObjective:find('UNSUPPORTED',1,true))
end)
test('specific required kills cannot target a different mob or tile',function()
 local m=goal('artifacts','击杀地块内蜘蛛x3');local g=work.unlockCandidate()
 assert(work.unlockTargetMatches(enemy('Spider','A'),g))
 assert(not work.unlockTargetMatches(enemy('Spider','B'),g))
 assert(not work.unlockTargetMatches(enemy('Bear','A'),g))
end)
test('an artifact unlock fight confirms a kill but does not claim the artifact unlocked',function()
 local m=goal('artifacts','击杀地块内蜘蛛x1');enemy('Spider','A')
 assert(work.unlockObjectiveTick()and fights==1 and not m.prompt.Enabled and not work.artifacts.Compass)
 assert(not work.unlockWork and notes.unlockObjective:find('SERVER UNLOCK STILL CHECKED',1,true))
end)
test('an already unlocked chest returns to opening without an unnecessary fight',function()
 local m=goal('chests','击杀地块内蜘蛛x1');m.locked=false;enemy('Spider','A')
 assert(not work.unlockObjectiveTick()and fights==0 and due.chests==0)
end)
test('protected refuge locks are optional and do not remove other unlock work',function()
 local m=goal('artifacts','击杀地块内蜘蛛x1');opts.refuge={x=0,y=3,z=0,tileId='A',seed=99};opts.useRefuge=true
 assert(work.unlockCandidate())
 opts.keepRefugeLocked=true;assert(not work.unlockCandidate())
 opts.keepRefugeLocked=false;assert(work.unlockCandidate())
end)
test('a native puzzle solve uses its verified action after a full hold and confirms completion',function()
 goal('artifacts','解谜石柱x1');local puzzle=object('石柱');puzzle.attrs.MapLockTileId='A'
 puzzle.prompt={Enabled=true,HoldDuration=1,MaxActivationDistance=8,Parent=puzzle};objects.explore={puzzle}
 work.interactPrompt=function()return false,true end
 assert(work.unlockObjectiveTick()and fights==0 and puzzle.solved)
 assert(requests[1]=='isSolved'and requests[2]=='requestSolve')
end)
test('failed puzzle holds cannot send native solve requests',function()
 goal('artifacts','解谜石柱x1');local puzzle=object('石柱');puzzle.attrs.MapLockTileId='A'
 puzzle.prompt={Enabled=true,MaxActivationDistance=8,Parent=puzzle};objects.explore={puzzle}
 work.interactPrompt=function()return false,false end
 assert(not work.unlockObjectiveTick()and #requests==1 and not puzzle.solved)
end)
test('low health latches recovery until 85 percent and a quiet damage window',function()
 h.Health=50;assert(work.recoveryNeeded());h.Health=65;assert(work.recoveryNeeded())
 h.Health=85;work.damageUntil=3;assert(work.recoveryNeeded());now=3;assert(not work.recoveryNeeded())
end)
test('a large recent damage burst starts recovery before health reaches retreat threshold',function()
 h.Health=70;work.damageBurst=30;work.damageBurstAt=now;work.damageUntil=3
 assert(work.recoveryNeeded());now=4;h.Health=84;assert(work.recoveryNeeded());h.Health=90;assert(not work.recoveryNeeded())
end)
test('recovery pauses optional unlock fights without discarding the requirement',function()
 goal('artifacts','击杀地块内蜘蛛x1');enemy('Spider','A');h.Health=40
 assert(not work.unlockObjectiveTick()and fights==0 and work.unlockPlan)
end)
test('actual combat reach does not reuse the much larger travel warning buffer',function()
 enemy('Spider','A',8)
 assert(work.attackEnvelope(r.Position,.7)>1)
 rows[1].point=vec(4,3,0);assert(work.attackEnvelope(r.Position,.7)<0)
end)
test('a saved refuge is used only on its original map seed',function()
 opts.useRefuge=true;opts.refuge={x=50,y=3,z=0,tileId='A',seed=99}
 assert(work.refugePoint());scene.Seed.Value=100;assert(not work.refugePoint())
end)
test('refuge destination keeps native dry floor and border validation',function()
 opts.useRefuge=true;opts.refuge={x=50,y=3,z=0,seed=99}
 motion.floor=function()end;assert(not work.refugePoint())
 motion.floor=function()return vec(50,0,0)end;work.insideBorder=function()return false end;assert(not work.refugePoint())
end)
test('a visible hostile inside refuge attack reach invalidates that refuge',function()
 opts.useRefuge=true;opts.refuge={x=10,y=3,z=0,seed=99};enemy('Spider','A',12)
 work.lineOfSight=function()return true end;assert(not work.refugePoint())
 work.lineOfSight=function()return false end;assert(work.refugePoint())
end)
test('walls are not assumed to protect a refuge from nearby Shadow',function()
 opts.useRefuge=true;opts.refuge={x=10,y=3,z=0,seed=99};enemy('Shadow','A',20)
 assert(not work.refugePoint())
end)
test('refuge travel uses the designated point and does not change unlock switches',function()
 opts.useRefuge=true;opts.refuge={x=50,y=3,z=0,seed=99}
 assert(work.tryRefuge('evade')and moves==1 and r.Position.X==50 and not opts.keepRefugeLocked and opts.unlockObjectives)
end)
test('damage inside refuge triggers a temporary rejection instead of repeated return trips',function()
 opts.useRefuge=true;opts.refuge={x=0,y=3,z=0,seed=99}
 body('    function work.observeHealth()', '    function work.memoThreat(')
 work.observeHealth();h.Health=90;work.observeHealth()
 assert(work.refugeFailedUntil==60 and work.refugeDamageEvents==1 and not work.refugePoint())
 now=61;assert(work.refugePoint())
end)
test('storm work stays within the camp material radius',function()
 work.stormActive=function()return true end
 local camp=object('Camp');work.campDropAnchor=function()return camp end
 assert(work.weatherWorkAllowed(vec(40,3,0))and not work.weatherWorkAllowed(vec(100,3,0)))
end)
test('artifact diagnostics separate locked, guarded and already collected artifacts',function()
 local m=goal('artifacts','击杀地块内蜘蛛x1');work.artifacts.Map=true
 assert(work.artifactProgress():find('1 / 4 collected',1,true)and work.artifactProgress():find('1 locked',1,true))
end)
test('production attack planning selects only the required mob in the required tile',function()
 goal('artifacts','击杀地块内蜘蛛x1');enemy('Spider','B',3);enemy('Bear','A',4);local wanted=enemy('Spider','A',15)
 work.unlockWork=work.unlockCandidate();work.creatures=function()return rows end
 work.combatPosition=function(m)return m.point,10 end;work.stanceScore=function()return 10 end
 built=function()end;opts.guardRadius=14;opts.huntRadius=60;opts.baseRadius=45
 body('    function work.attackPlan(', '    function work.retreat(')
 local target=work.attackPlan('unlockObjective',{toolType='spear',range=11,atkDmg=25,useCd=.57})
 assert(target==wanted)
end)
test('production combat finishes a native objective kill and reselects after ammunition runs out',function()
 goal('artifacts','击杀地块内蜘蛛x1');local target=enemy('Spider','A',15);target.human.Health=100
 work.unlockWork=work.unlockCandidate()
 local gun,melee={Parent=player.Character,ammo=1},{Parent=player.Character}
 local gunStats={toolType='gun',atkDmg=50,range=30,capAOE=1};local meleeStats={toolType='spear',atkDmg=50,range=11,capAOE=1}
 local equipped,shots={},{}
 equip=function(t)equipped[#equipped+1]=t;return true end
 work.meleeWeapon=function()if gun.ammo>0 then return gun,gunStats end;return melee,meleeStats end
 work.attackPlan=function()return target,vec(7,3,0)end;work.stanceScore=function()return 10 end
 work.pause=function(_,dt)now=now+dt;return true end
 local cycles=0;work.running=function()cycles=cycles+1;return cycles<6 end
 work.mobRemaining=function(m)return m.human.Health end;work.attackPhase=function()return'unknown'end
 work.strike=function(t,stats)
  shots[#shots+1]=t;target.human.Health=target.human.Health-stats.atkDmg
  if t==gun then gun.ammo=0 end;work.nextStrikeAt=now+.57;return true
 end
 work.kite=function()return false end;work.recordGuard=function()end
 CFrame={lookAt=function(a,b)return{LookVector=(b-a).Unit}end}
 local fight=assert(load(extract('    local function defend(key)','    function work.pickupCandidate(')..'\nreturn defend'))()
 assert(fight('unlockObjective')and target.human.Health==0)
 assert(#shots==2 and shots[1]==gun and shots[2]==melee and equipped[2]==melee and work.attackReceipts==2)
end)
test('Auto Attack does not interrupt an active combat job',function()
 body('    function work.autoAttackReady()', '    function work.readObjectiveHints()')
 for _,key in ipairs({'combat','unlockObjective','hunt','foodHunt','shadowHunt'})do work.active=key;assert(not work.autoAttackReady())end
end)
test('an unrelated opportunistic attack cannot cancel a protected artifact hold',function()
 body('    function work.interruptsInteraction(', '    function work.foodReserveTarget()')
 work.combatUrgent=function()return false end
 assert(not work.interruptsInteraction{key='autoAttack'})
 work.combatUrgent=function()return true end
 assert(work.interruptsInteraction{key='autoAttack'})
end)
test('a long-reach attacker holds a safe position instead of kiting closer after every hit',function()
 local m=enemy('Spider','A',0);r.Position=vec(11,3,0)
 work.attackPhase=function()return'unknown'end
 body('    function work.kite(', '    function work.activateWeapon(')
 assert(not work.kite(m,'combat')and moves==0 and notes.combat==nil)
 assert(work.lastFightDecision:find('HOLD SAFE RANGE',1,true))
end)
test('a refuge shelter exception is confined to nearby occluded positions',function()
 opts.useRefuge=true;opts.refuge={x=10,y=3,z=0,seed=99};enemy('Spider','A',12)
 assert(work.refugeAllowsPoint(vec(10,3,0)))
 assert(not work.refugeAllowsPoint(vec(40,3,0)))
 work.lineOfSight=function()return true end;assert(not work.refugeAllowsPoint(vec(10,3,0)))
end)
test('storm policy pauses exploration but keeps camp food tasks enabled',function()
 work.roundLost=function()return false end;work.nightPaused=function()return false end;work.stormActive=function()return true end
 flags.exploreMap=true;flags.cook=true
 body('    function work.jobEnabled(', '    function work.keyEnabled(')
 assert(not work.jobEnabled{key='exploreMap'}and work.jobEnabled{key='cook'})
end)
test('recovery policy keeps food service enabled while preventing renewed optional fights',function()
 work.roundLost=function()return false end;work.nightPaused=function()return false end;h.Health=40
 flags.cook=true
 body('    function work.jobEnabled(', '    function work.keyEnabled(')
 assert(not work.jobEnabled{key='combat'}and work.jobEnabled{key='cook'})
end)
test('an unlocked guarded artifact can request local threat clearing before its five-second hold',function()
 local m=goal('artifacts','击杀地块内蜘蛛x1');m.prompt.Enabled=true
 work.safeResource=function()return false end
 local target=enemy('Spider','A',25);local g=work.unlockCandidate()
 assert(g and g.rule.kind=='guard_area'and work.unlockTargetMatches(target,g))
 assert(not work.unlockTargetMatches(enemy('Spider','B',22),g))
end)
test('lock protection remains independent when automatic refuge travel is disabled',function()
 local m=goal('artifacts','击杀地块内蜘蛛x1');opts.refuge={x=0,y=3,z=0,tileId='A',seed=99}
 opts.keepRefugeLocked=true;opts.useRefuge=false
 assert(work.protectedObjective(m)and not work.unlockCandidate())
end)
test('turning off one objective category invalidates its cached unlock plan',function()
 goal('artifacts','击杀地块内蜘蛛x1');assert(work.unlockCandidate())
 flags.artifacts=false;assert(not work.unlockCandidate())
end)
local function artifactFixture()
 local m=object('Compass');m.prompt={Enabled=true,HoldDuration=5,MaxActivationDistance=10}
 m.promptPart={FindFirstChildOfClass=function()return m.prompt end}
 work.artifactCandidate=function()return m end
 body('    function work.fetchArtifact()', '    work.artifacts = {}')
 return m
end
test('artifact fallback triggers only after its complete five-second hold and confirms the server list',function()
 local m=artifactFixture();local sent=0
 work.interactPrompt=function()now=now+5;return false,true end
 fireproximityprompt=function(prompt)assert(now>=5 and prompt==m.prompt);sent=sent+1;work.artifacts.Compass=true end
 assert(work.fetchArtifact()and sent==1 and work.artifacts.Compass)
end)
test('an interrupted artifact hold cannot fire the executor prompt fallback',function()
 artifactFixture();work.interactPrompt=function()return false,false end
 fireproximityprompt=function()error('interrupted prompt must not trigger')end
 assert(not work.fetchArtifact())
end)
test('artifact disappearance without server collection confirmation is not success',function()
 local m=artifactFixture()
 work.interactPrompt=function()now=now+5;m.Parent=false;return true,true end
 work.refreshArtifactState=function()return false end
 assert(not work.fetchArtifact()and not work.artifacts.Compass)
end)
test('a late artifact server-list refresh can confirm a pickup after a missed update event',function()
 local m=artifactFixture()
 work.interactPrompt=function()now=now+5;m.Parent=false;return true,true end
 work.refreshArtifactState=function()work.artifacts.Compass=true;return true end
 assert(work.fetchArtifact())
end)
test('artifact collection always requests at least five seconds of native hold time',function()
 local m=artifactFixture();m.prompt.HoldDuration=0
 work.interactPrompt=function(_,_,extra)assert(extra==5);now=now+extra;work.artifacts.Compass=true;return true,true end
 assert(work.fetchArtifact()and now>=5)
end)
test('kiting validates actual attack clearance instead of rejecting every endpoint within the travel buffer',function()
 enemy('Spider','A',0);work.kiting=true;work.escapeMove=true;work.active='combat'
 work.danger=function()return 100 end;work.threatEnvelope=function()return -16 end;work.combatClear=function()return true end
 body('    function work.safeDestination(', '    function work.combatClear(')
 assert(work.safeDestination(vec(8,3,0),'combat'))
 work.kiting=nil;assert(not work.safeDestination(vec(8,3,0),'combat'))
end)
test('an occluded refuge does not loop evasion forever because enemies are outside its walls',function()
 opts.avoidEnemies=true;opts.useRefuge=true;opts.refuge={x=0,y=3,z=0,seed=99}
 enemy('Spider','A',6);work.shadowThreat=function()end
 work.danger=function()error('valid refuge must be recognized before travel danger scan')end
 body('    function work.personalThreat()', '    function work.baseThreat()')
 assert(not work.personalThreat())
end)
test('indoor refuge movement probes down from inside the room instead of landing on its roof',function()
 opts.useRefuge=true;opts.refuge={x=10,y=3,z=0,seed=99};work.refugeTravel=vec(10,3,0)
 typeof=function(value)return getmetatable(value)==V and 'Vector3'or type(value)end
 Vector2={new=function(x,y)return vec(x,y,0)end}
 local probes=0
 motion.floor=function(point,_,drop,raise)assert(raise==0 and point.Y==3);probes=probes+1;return vec(point.X,0,point.Z)end
 body('    function motion.goals(', '    function motion.valid(')
 local goals=motion.goals(vec(10,3,0),.5)
 assert(probes==9 and #goals==9)
 for _,point in ipairs(goals)do assert(point.Y==3)end
end)
test('pre-fight damage budget rejects a dangerous close-range boss with a weak weapon',function()
 local m=enemy('Bear','A');m.human.Health=300;cfg.mob.byId.Bear={id='Bear',atkDmg=50,atkCd=1}
 assert(not work.engagementAllowed(m,{range=3,atkDmg=11,useCd=.57,windup=.2}))
 assert(work.lastFightDecision:find('UPGRADE / RANGE NEEDED',1,true))
end)
test('ranged reach permits fighting a dangerous boss without planning a close-range trade',function()
 local m=enemy('Bear','A');m.human.Health=300;cfg.mob.byId.Bear={id='Bear',atkDmg=50,atkCd=1}
 assert(work.engagementAllowed(m,{range=30,atkDmg=25,useCd=.57,windup=.2}))
end)
test('the hostile damage budget does not block passive food collection',function()
 local m=enemy('Chicken','A');m.human.Health=30
 assert(work.engagementAllowed(m,{range=3,atkDmg=11,useCd=.57,windup=.2}))
end)
assert(load(source),'full module must compile')
print(n..' objective combat, artifact unlock, recovery and refuge checks passed; module compiles')
