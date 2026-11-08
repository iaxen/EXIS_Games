-- Production helpers exercised without a Roblox/executor session.
math.clamp=function(x,a,b)return math.max(a,math.min(b,x))end
local f=assert(io.open('Games/MrbeastIslandEscape.lua'));local source=f:read('*a');f:close()
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
local V={};V.__index=function(v,k)if k=='Magnitude'then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)elseif k=='Unit'then return v/v.Magnitude end return V[k]end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
V.__mul=function(a,b)return vec(a.X*b,a.Y*b,a.Z*b)end
V.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
Vector3={new=vec};local F={};F.__index=F
function F:PointToWorldSpace(v)return self.Position+v end
CFrame={new=function(x,y,z)return setmetatable({Position=type(x)=='table'and x or vec(x,y,z)},F)end}
local now,cfg,bag,drops,tiles,r,h,scene,camp,log,calls
local function object(name,point)
 local m={Name=name,Parent=true,point=point or vec(0,0,0),attrs={}}
 function m:GetAttribute(k)return self.attrs[k]end
 function m:IsA(c)return c=='Model'or c==self.class end
 function m:FindFirstChild(k)return self[k]end
 function m:FindFirstChildOfClass(k)return self[k]end
 function m:FindFirstChildWhichIsA()return nil end
 return m
end
local function item(id,name,extra)
 local it={id=id,displayName=name,isBagItem=true}
 for k,v in pairs(extra or{})do it[k]=v end
 cfg.item.byId[id]=it;cfg.item.byDisplayName[name]=it;return it
end
local function held(name,n)local t=object(name);t.Parent=player.Character;t.attrs.count=n or 1;bag[#bag+1]=t;return t end
local function tile(name,x,z)
 local t=object(name);t.BoundingBox={class='BasePart',Size=vec(40,2,40),CFrame=CFrame.new(x,0,z or 0),IsA=function(_,c)return c=='BasePart'end};tiles[#tiles+1]=t;return t
end
local function setup()
 now=0;os.clock=function()return now end;bag={};drops={};tiles={};log={};calls={}
 cfg={item={byId={},byDisplayName={}},tool={byId={},byDisplayName={}},food={byId={}},armour={byId={}},bag={byId={}},misc={collectRadius=3},build={byId={}},worldResource={byId={}}}
 item('wood','Wood');item('meal','Cooked Meal');cfg.food.byId.meal={}
 item('pistol','Pistol',{isBagItem=false,type='tool'});cfg.tool.byDisplayName.Pistol={toolType='gun',lvl=1,useSwapUpgrade=true};cfg.tool.byId.pistol=cfg.tool.byDisplayName.Pistol
 item('axe','Axe',{isBagItem=false,type='tool'});cfg.tool.byDisplayName.Axe={toolType='axe',lvl=1,useSwapUpgrade=true}
 item('torch','Torch',{isBagItem=false,type='tool',isLightSource=true});cfg.tool.byDisplayName.Torch={toolType='torch',lvl=1}
 config=function()return cfg end
 player={Name='Explorer',Character={},GetAttribute=function()return nil end};alive=true
 opts={teamRole='Custom',jobTimeout=15,chunkRevisit=30,campWorkRadius=120,retreatHealth=35,health=50,hunger=40,travelRation=0,dangerRadius=20,shadowRadius=60}
 flags={autoFarm=true};due={};failed={};toggles={};motion={serial=0}
 motion.cancel=function(reason)motion.serial=motion.serial+1;log.cancel=reason end
 motion.floor=function(p)return vec(p.X,0,p.Z)end
 h={Health=100,MaxHealth=100,HipHeight=2,GetAttribute=function(_,k)if k=='hunger'then return 100 elseif k=='maxHunger'then return 100 end end}
 r={Position=vec(0,3,0),Size=vec(2,2,2)}
 root=function()return h.Health>0 and r or nil,h end;pos=function(m)return m.point end
 scene={Tiles={GetChildren=function()return tiles end}};function scene:FindFirstChild(k)return self[k]end
 world=function()return scene end;camp=object('Campfire');built=function(name)if name=='Campfire'then return camp end end
 tools=function()local out={}for _,t in ipairs(bag)do if t.Parent then out[#out+1]=t end end return out end
 count=function(name)local n=0 for _,t in ipairs(tools())do if t.Name==name then n=n+(t.attrs.count or 1)end end return n end
 save=function()log.saved=true end;say=function()end;note=function(k,v)log[k]=v end
 nearest=function(list,predicate)local best,dist for _,m in ipairs(list)do if m.Parent and predicate(m)then local d=(pos(m)-r.Position).Magnitude;if not dist or d<dist then best,dist=m,d end end end return best end
 task={wait=function()now=now+.05 end}
 travel=function(target,key)r.Position=type(target)=='table'and target.X and target or pos(target);return true end
 local threatRows={}
 work={sent=0,artifacts={},needs={},resourceNeeds={},
  models=function(kind)return kind=='drops'and drops or{}end,
  safeResource=function()return true end,safeWorkPoint=function()return true end,
  campDropAnchor=function()return camp end,campDropPoint=function()return vec(32,3,0)end,
  criticalMeal=function()return false end,canCollect=function()return true end,
  roundLost=function()return false end,nightPaused=function()return false end,
  releaseHover=function()end,invalidateInventory=function()end,recordPickup=function()end,
  markCampDrop=function()end,stashWanted=function()return false end,
  isCookedFood=function(id)return id=='meal'end,foodAllowed=function()return true end,
  mealNeeded=function()return false end,noFood=function()return count('Cooked Meal')==0 end,
  foodCounts=function()return count('Cooked Meal'),0,count('Cooked Meal')end,
  foodPickupWanted=function()return true end,interactPrompt=function()return nil end,
  checkpoint=function()return true end,needsDrop=function()return true end,
  bagState=function()return 0,25 end,hostiles=function()return threatRows end,
  pause=function(_,seconds)now=now+seconds;return not work.preempted end,
  await=function(_,pred,seconds)local deadline=now+seconds repeat if pred()then return true end;if work.preempted then return false end;task.wait()until now>=deadline return false end}
 workspace={GetServerTimeNow=function()return now end};campData={};furnaceData={}
 call=function(name,action,t)
  calls[#calls+1]=name..'.'..action
  if name=='PlayerInventory'and action=='dropItem'then
   t.attrs.count=t.attrs.count-1;if t.attrs.count<=0 then t.Parent=nil end
   local d=object(t.Name,r.Position);d.attrs.ownerName=player.Name;d.attrs.protectEndTick=now+10;drops[#drops+1]=d
  elseif name=='ItemCollect'then held(t.Name);t.Parent=nil end
 end
 body('    work.automationBundles =', '    function work.makeSuiteUI(p)')
 body('    function work.observeHealth()', '    local jobsList = {')
 body('    function work.collectModel(', '    function work.treeDropContext(')
 body('    function work.dropAllowed(', '    function work.interactPrompt(')
 body('    function work.batchDrop(', '    function work.watchLateDrops(')
 body('    function work.rank(job)', '    function work.pick(')
end
local passed=0
local function test(name,fn)setup();fn();passed=passed+1;print('PASS '..name)end

test('four team presets enable distinct work and retain personal survival',function()
 for _,role in ipairs({'Explorer','Defender','Builder','Gatherer'})do
  assert(work.applyTeamRole(role));assert(opts.teamRole==role and log.saved)
  assert(flags.autoFarm and flags.eat and flags.runShadow and flags.autoAttack and flags.roleFallback)
  assert(not flags.escape and not flags.autoRound and not flags.leaveLost and not flags.nightHover)
  assert(opts.retreatHealth==55 and opts.health==75 and opts.hunger==60)
 end
end)
test('switching roles clears the previous specialist jobs',function()
 work.applyTeamRole('Explorer');assert(flags.chests and flags.quest and flags.exploreMap and not flags.takeTeamGuns and not flags.shareGuns)
 work.applyTeamRole('Builder');assert(flags.greatWall and flags.structureCraft and flags.stormStock and not flags.shareGuns and not flags.chests and not flags.takeTeamGuns)
 work.applyTeamRole('Gatherer');assert(flags.scavengeAll and flags.mineIron and not flags.greatWall and not flags.buildCamp)
 work.applyTeamRole('Defender');assert(flags.hunt and opts.guardRadius==45 and not flags.scavengeAll and not flags.exploreMap)
end)
test('role toggles combine all four jobs without silently donating solo guns',function()
 for _,name in ipairs({'Explorer','Builder','Gatherer','Defender'})do assert(work.setRole(name,true))end
 assert(opts.teamRole=='Mixed'and flags.chests and flags.quest and flags.greatWall and flags.mineIron and flags.hunt)
 assert(flags.roleExplorer and flags.roleBuilder and flags.roleGatherer and flags.roleDefender)
 assert(not flags.shareGuns and not flags.takeTeamGuns)
end)
test('the first role selection clears unrelated specialist defaults',function()
 flags.quest=true;flags.chests=true;flags.exploreMap=true
 work.setRole('Builder',true)
 assert(flags.greatWall and flags.mineIron and not flags.quest and not flags.chests and not flags.exploreMap)
end)
test('disabling one role preserves material jobs needed by another role',function()
 work.setRole('Builder',true);work.setRole('Gatherer',true);work.setRole('Explorer',true)
 work.setRole('Builder',false)
 assert(flags.mineIron and flags.chopTrees and flags.scavengeAll and flags.chests and not flags.greatWall)
 assert(opts.teamRole=='Mixed')
 work.setRole('Gatherer',false);assert(not flags.mineIron and flags.chests and opts.teamRole=='Explorer')
end)
test('gun handoff preference remains independent of role changes',function()
 flags.shareGuns=true;work.setRole('Builder',true);work.setRole('Explorer',true)
 assert(flags.shareGuns);flags.shareGuns=false;work.setRole('Defender',true);assert(not flags.shareGuns)
end)
test('a starved specialist gets a bounded turn before routine crafting',function()
 work.rank{key='exploreMap'};now=31
 assert(work.rank{key='exploreMap'}<work.rank{key='craft'})
 assert(work.rank{key='evade'}<work.rank{key='exploreMap'})
 work.criticalMeal=function()return true end
 assert(work.rank{key='eat'}<work.rank{key='exploreMap'})
end)
test('an interrupted trip resumes its committed chunk instead of switching tiles',function()
 tile('A',40);tile('B',80)
 travel=function()work.preempted=true;return false end
 assert(not work.exploreMapTick());local target=work.chunkTarget;assert(target)
 assert(work.chunkDestination()==target)
end)
test('native map snapshot adds unknown frontier cells beyond streamed tiles',function()
 local snapshot={0,0,0,0,2,0,0,0,0}
 typeof=function(value)return type(value)=='table'and 'buffer'or type(value)end
 buffer={len=function(value)return #value end,readu8=function(value,index)return value[index+1]end}
 local oldRequire=require;require=function()return{client={requestSnapshot=function()return snapshot,3,100 end}}end
 RS={Engine={World={MapSyncService={}}}};task.spawn=function(fn)fn()end
 work.boundedRead=function(fn)return fn()end
 work.requestMapFrontier();require=oldRequire
 assert(work.mapFrontier and #work.mapFrontier.active==5)
 local center=work.mapFrontier.rows[4];assert(center.probe.X==175 and center.probe.Z==175)
 assert(work.mapFrontier.rows[1].frontier and not work.mapFrontier.rows[0])
 work.insideBorder=function()return true end
 local target=assert(work.chunkDestination());assert(target.needsStreaming and target.row.probe)
end)
test('water and server boundary cells are excluded from the native map frontier',function()
 local snapshot={4,1,4,1,3,1,4,1,4}
 typeof=function()return 'buffer'end
 buffer={len=function(v)return #v end,readu8=function(v,i)return v[i+1]end}
 local oldRequire=require;require=function()return{client={requestSnapshot=function()return snapshot,3,0 end}}end
 RS={Engine={World={MapSyncService={}}}};task.spawn=function(fn)fn()end
 work.boundedRead=function(fn)return fn()end;work.requestMapFrontier();require=oldRequire
 assert(#work.mapFrontier.active==1 and work.mapFrontier.rows[4]and not work.mapFrontier.rows[0])
end)
test('an unstreamed frontier without safe ground is never visited or teleported to',function()
 work.insideBorder=function()return true end
 work.chunkDestination=function()return{row={probe=vec(500,0,0),tile={Name='Grid'},blocked={},visited={}},index=1,probe=vec(500,0,0),needsStreaming=true}end
 motion.floor=function()return nil end
 travel=function()error('must not move to unverified ground')end
 assert(not work.exploreMapTick()and not work.chunkVisits and log.exploreMap:find('NO LANDING ATTEMPTED',1,true))
end)
test('an invalid role cannot change a running configuration',function()
 flags.quest=true;assert(not work.applyTeamRole('unknown')and flags.quest and opts.teamRole=='Custom')
end)
test('solo Long Run does not silently donate its guns',function()
 work.applyTeamRole('Builder');work.applyLongRun()
 assert(opts.teamRole=='Custom'and not flags.shareGuns and not flags.takeTeamGuns and opts.travelRation==0)
end)
test('exploration advances only after actual arrival and sweeps distinct points',function()
 tile('Chunk A',0);tile('Chunk B',80)
 assert(work.exploreMapTick());assert(work.chunkVisits==1)
 local candidate=assert(work.chunkDestination());assert(not candidate.row.visited[candidate.index])
 assert(work.exploreMapTick()and work.chunkVisits==2)
end)
test('an interrupted approach cannot mark a chunk visited',function()
 tile('A',40);travel=function()work.preempted=true;return false end
 assert(not work.exploreMapTick()and not work.chunkVisits)
 local row=work.chunkRows()[1];for _ in pairs(row.visited)do error('interrupted chunk was marked visited')end
end)
test('water and unsafe or locked chunks are rejected without disabling exploration',function()
 tile('Water',100);motion.floor=function()return nil end;flags.exploreMap=true
 assert(not work.exploreMapTick()and flags.exploreMap and not work.chunkVisits)
 motion.floor=function(p)return vec(p.X,0,p.Z)end;now=9;work.safeWorkPoint=function()return false end
 assert(not work.exploreMapTick()and flags.exploreMap)
end)
test('streamed chunks update the frontier and completed chunks become revisitable',function()
 tile('A',0);local first=work.chunkRows();tile('B',80);assert(#work.chunkRows()==2 and work.chunkRows()~=first)
 for _,row in ipairs(work.chunkRows())do for i=1,5 do row.visited[i]=0 end end
 assert(not work.chunkDestination());now=31;assert(work.chunkDestination())
end)
test('role fallback does not duplicate an enabled explorer trip',function()
 tile('A',0);flags.exploreMap=true
 for _,row in ipairs(work.chunkRows())do for i=1,5 do row.visited[i]=0 end end
 assert(not work.roleFallbackTick()and log.roleFallback:find('EXPLORATION QUEUED',1,true))
end)
test('lack of a safe patrol is reported and never disables the assigned role',function()
 flags.roleFallback=true;work.safeWorkPoint=function()return false end
 assert(not work.roleFallbackTick()and flags.roleFallback and log.roleFallback:find('RETRYING',1,true))
end)
test('revival of the same character clears stale leases and resumes its saved role',function()
 work.applyTeamRole('Builder');held('Axe');work.nativeCycleUntil=999;work.damageUntil=999;due.greatWall=999
 local bad=object('Bad');failed[bad]=999;work.attackCommit={};work.interaction={};work.preempted={}
 h.Health=0;assert(not work.reviveSync()and work.wasDown)
 h.Health=100;assert(work.reviveSync()and not work.wasDown and work.reviveCount==1)
 assert(opts.teamRole=='Builder'and flags.greatWall and due.greatWall==0 and not failed[bad])
 assert(not work.preempted and not work.attackCommit and not work.interaction and work.nativeCycleUntil==0 and work.damageUntil==0)
 assert(work.reviveSync()and work.reviveCount==1)
end)
test('damage ends an attack commitment and applies a three-second recovery window',function()
 work.observeHealth();work.attackCommit={};h.Health=80;work.observeHealth()
 assert(not work.attackCommit and work.damageUntil==3 and work.damageEvents==1)
 work.observeHealth();assert(work.damageEvents==1)
end)
test('a gun handoff drops the gun with both inventory and ground confirmation and keeps melee and torch',function()
 local gun=held('Pistol');local axe=held('Axe');local torch=held('Torch');flags.shareGuns=true
 assert(work.shareGunsTick()and not gun.Parent and axe.Parent and torch.Parent and #drops==1)
 assert(drops[1].Name=='Pistol'and log.shareGuns:find('GUN LEFT AT CAMP',1,true))
end)
test('an unconfirmed gun drop remains carried and can be retried',function()
 local gun=held('Pistol');call=function()end
 assert(not work.shareGunsTick()and gun.Parent and log.shareGuns:find('UNCONFIRMED',1,true))
end)
test('a late gun drop survives combat preemption and uses the native throw radius',function()
 held('Pistol');local sent=0
 work.nativeDropReach=function()return 25 end
 work.batchDrop=function(tool)sent=sent+1;tool.Parent=nil;work.preempted=true;return 1 end
 assert(not work.shareGunsTick()and work.gunHandoff and sent==1)
 work.preempted=nil;local d=object('Pistol',r.Position+vec(25,0,0));d.attrs.ownerName=player.Name;drops={d}
 assert(work.shareGunsTick()and not work.gunHandoff and sent==1)
end)
test('an unresolved gun receipt never issues a second donation',function()
 held('Pistol');local sent=0
 work.batchDrop=function(tool)sent=sent+1;tool.Parent=nil;return 1 end
 assert(not work.shareGunsTick());held('Pistol')
 assert(not work.shareGunsTick()and sent==1 and count('Pistol')==1)
end)
test('donors never reclaim the gun they just shared',function()
 local gun=object('Pistol');flags.shareGuns=true
 assert(not work.pickupEligible(gun));flags.shareGuns=false;assert(work.pickupEligible(gun))
end)
test('the explorer respects owner protection then receives a camp gun even with a full material bag',function()
 local d=object('Pistol',vec(32,3,0));d.attrs.ownerName='Builder';d.attrs.protectEndTick=10;drops={d}
 flags.takeTeamGuns=true;work.canCollect=function()return false end
 assert(not work.teamGunCandidate());now=11
 assert(work.teamGunCandidate()==d and work.takeTeamGunTick()and count('Pistol')==1 and not d.Parent)
end)
test('equal guns remain available for an explorer who does not already own that tier',function()
 held('Pistol');local d=object('Pistol',vec(32,3,0));drops={d}
 assert(not work.teamGunCandidate())
end)
test('melee weapons and torches are never mistaken for guns to donate',function()
 held('Axe');held('Torch');assert(not work.carriedGun())
end)
test('travel rations survive ordinary unloading without retaining every cooked stack',function()
 body('    function work.foodKeepCount(', '    function work.campFoodRecord(')
 opts.travelRation=2;local a=held('Cooked Meal',1);local b=held('Cooked Meal',3)
 assert(work.foodKeepCount('meal',a)==1 and work.foodKeepCount('meal',b)==1)
 opts.travelRation=0;assert(work.foodKeepCount('meal',a)==0)
end)
test('a ration job collects cooked food before departure even at full health',function()
 opts.travelRation=2;local d=object('Cooked Meal');drops={d}
 assert(work.travelFoodReady()and work.travelFoodTick()and count('Cooked Meal')==1)
end)
test('spatial results are reused only within the same frame and exact position',function()
 work.frameSerial=1;local calls=0;local original=function()calls=calls+1;return calls,nil,3 end
 local p=vec(1,2,3);local first,none,third=work.memoThreat('danger',original,p,20)
 assert(first==1 and none==nil and third==3)
 assert(work.memoThreat('danger',original,vec(1,2,3),20)==1 and calls==1)
 assert(work.memoThreat('danger',original,vec(2,2,3),20)==2)
 work.frameSerial=2;assert(work.memoThreat('danger',original,p,20)==3)
end)
test('spatial caching distinguishes ignored instances even when their names match',function()
 work.frameSerial=1;local calls=0;local original=function()calls=calls+1;return calls end
 local a,b=object('Zombie'),object('Zombie');local p=vec(0,0,0)
 assert(work.memoThreat('danger',original,p,20,a)==1)
 assert(work.memoThreat('danger',original,p,20,b)==2)
end)
test('new threat snapshots invalidate same-frame spatial results',function()
 work.frameSerial=1;local rows={};work.hostiles=function()return rows end
 local n=0;local original=function()n=n+1;return n end;local p=vec(0,0,0)
 assert(work.memoThreat('danger',original,p,20)==1);rows={};assert(work.memoThreat('danger',original,p,20)==2)
end)
test('spatial caches remain bounded in a long frame',function()
 work.frameSerial=1;local original=function()return 0 end
 for i=1,400 do work.memoThreat('danger',original,vec(i,0,0),20)end
 assert(work.threatMemoCache.count==256)
end)
test('role ranks retain survival before guns and specialist tasks',function()
 work.combatUrgent=function()return true end;work.criticalMeal=function()return true end
 assert(work.rank{key='evade'}<work.rank{key='eat'})
 assert(work.rank{key='eat'}<work.rank{key='shareGuns'})
 assert(work.rank{key='takeTeamGuns'}<work.rank{key='exploreMap'})
 assert(work.rank{key='exploreMap'}<work.rank{key='roleFallback'})
end)
test('camp intake zones are indexed once and streamed changes do not rescan the whole game',function()
 body('    function work.clearSceneIndex()', '    function work.captureEvadeIntent(')
 body('    function work.campIntakeZones()', '    function work.campDropClear(')
 local added,removed,scans
 scans=0
 local function zone(name)return{Name=name,Parent=true,IsA=function(_,kind)return kind=='BasePart'end}end
 local fire=zone('fireZone')
 scene.DescendantAdded={Connect=function(_,fn)added=fn;return{Disconnect=function()end}end}
 scene.DescendantRemoving={Connect=function(_,fn)removed=fn;return{Disconnect=function()end}end}
 scene.GetDescendants=function()scans=scans+1;return{fire}end
 assert(#work.campIntakeZones()==1 and scans==1)
 now=20;assert(#work.campIntakeZones()==1 and scans==1)
 local crafting=zone('吸入范围');added(crafting)
 assert(#work.campIntakeZones()==2 and scans==1)
 fire.Parent=nil;removed(fire);assert(#work.campIntakeZones()==1 and scans==1)
end)
test('repeated hostile queries reuse a single frame snapshot but invalidation still refreshes',function()
 body('    function work.hostiles(', '    function work.projectedEnemyGap(')
 work.frameSerial=1;local builds=0
 work.creatures=function()builds=builds+1;return{{hostile=true}}end
 work.hostiles();now=1;work.hostiles();assert(builds==1)
 work.threatCacheAt=0;work.hostiles();assert(builds==2)
 work.frameSerial=2;now=2;work.hostiles();assert(builds==3)
end)
test('optional attacks stop while recovering health or recent damage',function()
 body('    function work.autoAttackReady()', '    function work.autoAttackTick()')
 work.meleeWeapon=function()error('recovery should stop before finding a weapon')end
 h.Health=40;opts.retreatHealth=55;assert(not work.autoAttackReady())
 h.Health=100;work.damageUntil=3;assert(not work.autoAttackReady())
end)
test('an urgent meal pauses a chunk sweep before it moves away from recovery supplies',function()
 tile('A',40);work.criticalMeal=function()return true end
 travel=function()error('critically injured explorer should not leave to map a chunk')end
 assert(not work.exploreMapTick()and not work.chunkVisits)
end)
test('role presets also refresh displayed numeric and movement settings',function()
 local renders=0;work.optionRenders={guard=function()renders=renders+1 end}
 work.renderMove=function()assert(opts.move=='Teleport');renders=renders+1 end
 work.applyTeamRole('Defender');assert(renders==2)
end)
test('the production job table keeps a camp patrol ready when specialist targets are blocked',function()
 work.applyTeamRole('Defender')
 local jobs=assert(load(extract('    local jobsList = {','        {key="questAcquire"')..'\n}\nreturn jobsList'))()
 body('    function work.jobEnabled(', '    function work.keyEnabled(')
 body('    function work.pick(', '    function work.nextQueuedJob(')
 local job=assert(work.pick(jobs,now));assert(job.key=='roleFallback'and job.run())
end)
test('survival takes priority while the assigned fallback stays queued',function()
 work.applyTeamRole('Gatherer');work.criticalMeal=function()return true end
 local jobs=assert(load(extract('    local jobsList = {','        {key="questAcquire"')..'\n}\nreturn jobsList'))()
 jobs[#jobs+1]={key='eat',ready=function()return true end}
 body('    function work.jobEnabled(', '    function work.keyEnabled(')
 body('    function work.pick(', '    function work.nextQueuedJob(')
 assert(work.pick(jobs,now).key=='eat'and flags.roleFallback)
end)
test('a new character created by native revival also resumes without re-executing the script',function()
 work.applyTeamRole('Explorer');h.Health=0;assert(not work.reviveSync())
 player.Character={};h={Health=60,MaxHealth=100,HipHeight=2}
 assert(work.reviveSync()and flags.exploreMap and not flags.takeTeamGuns and opts.teamRole=='Explorer')
 assert(not work.lostCached and work.reviveCount==1)
end)
test('food-count caching refreshes when native inventory changes within the same frame',function()
 body('    function work.foodCounts()', '    function work.foodShortage()')
 body('    function work.invalidateInventory()', '    local function tools()')
 work.frameSerial=1
 local cooked=work.foodCounts();assert(cooked==0)
 held('Cooked Meal');assert(work.foodCounts()==0)
 work.invalidateInventory();assert(work.foodCounts()==1)
end)
test('a replacement character clears old work even when the down interval fell between scheduler samples',function()
 work.applyTeamRole('Gatherer');assert(work.reviveSync());due.gather=999
 player.Character={};assert(work.reviveSync()and work.reviveCount==1 and due.gather==0)
 assert(opts.teamRole=='Gatherer'and flags.scavengeAll)
end)
test('combat stance work is capped at three candidates and failed plans are not rescanned in one frame',function()
 body('    function work.attackPlan(', '    local function defend(')
 work.frameSerial=1;opts.teamRole='Defender';opts.retreatHealth=55;opts.baseRadius=100;opts.guardRadius=100;opts.huntRadius=100;flags.combat=true
 local rows={};for i=1,8 do local m=object('Zombie',vec(i*10,3,0));m.Humanoid={Health=100};rows[#rows+1]={model=m,point=m.point,human=m.Humanoid,hostile=true,attackable=true}end
 work.hostiles=function()return rows end;work.enemyReach=function()return 4 end;work.insideBorder=function()return true end
 local checked={};work.combatPosition=function(m)checked[#checked+1]=m;return nil end
 local stats={toolType='axe',range=11};assert(not work.attackPlan('combat',stats)and #checked==3)
 assert(not work.attackPlan('combat',stats)and #checked==3)
 work.frameSerial=2;assert(not work.attackPlan('combat',stats)and #checked==6 and checked[6]==rows[4].model)
 h.Health=40;work.frameSerial=3;assert(not work.attackPlan('combat',stats)and #checked==6)
end)
test('the pending reward pool prioritizes a missing torch over another firearm',function()
 body('    function work.choiceScore(', '    function work.choicePanel()')
 work.baseThreat=function()end;work.personalThreat=function()end;work.shadowWeapon=function()end
 flags.killShadow=true
 assert(work.choiceScore{itemId='torch',count=1}>work.choiceScore{itemId='pistol',count=1})
end)
test('ordinary threat checks cannot shorten the independent damage recovery window',function()
 body('    function work.personalThreat()', '    function work.baseThreat()')
 opts.avoidEnemies=true;work.shadowThreat=function()end;work.danger=function()return 0,nil,0 end
 work.observedHealth=100;work.damageUntil=3;h.Health=90;work.personalThreat()
 assert(work.damageUntil==3)
end)
assert(loadfile('Games/MrbeastIslandEscape.lua'))
print(passed..' team role, chunk exploration, revival, gun handoff and survival checks passed; module compiles')
