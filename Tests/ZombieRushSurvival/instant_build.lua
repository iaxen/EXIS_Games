local source=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
local function signal()
 local handlers={};local s={}
 function s:Connect(fn)local connection={Connected=true};handlers[#handlers+1]={fn=fn,c=connection}
  function connection:Disconnect()self.Connected=false end
  return connection
 end
 function s:Fire()for _,h in ipairs(handlers)do if h.c.Connected then h.fn()end end end
 return s
end
local function setup()
 local queue,waits={},0
 local app={alive=true,mode='MATCH',mapId='Map1',className='Rookie',revision=1,next={},notes={}}
 local cfg={enabled=true,autoPlace=true}
 local node={Value=0,Changed=signal()}
 function node:GetPropertyChangedSignal(name)assert(name=='Value');return self.Changed end
 app.data=function()return node end;app.active=function()return true end
 app.note=function(k,v)app.notes[k]=v end
 app.connect=function(s,fn)return s:Connect(fn)end
 app.matchTick=function()if node.Value>=50 then node.Value=node.Value-50;app.placedSerial=(app.placedSerial or 0)+1 end end
 local env=setmetatable({app=app,cfg=cfg,Diagnostics={traceback=debug.traceback},
 task={defer=function(fn)queue[#queue+1]=fn end,wait=function(delay)assert(delay==nil,'extra placement timer');waits=waits+1 end}},{__index=_G})
 assert(load(extract('    function app.requestBuildWake()', '    function app.skipTick()'),'instant builder','t',env))()
 local function drain()
  local count=0;while #queue>0 do count=count+1;assert(count<100,'wake loop never settled');table.remove(queue,1)()end
 end
 return{app=app,cfg=cfg,node=node,env=env,queue=queue,drain=drain,waits=function()return waits end}
end
test('cash reaching the next price starts a placement without waiting for the polling loop',function()
 local h=setup();h.node.Value=49;h.app.bindBuildCash();h.drain();assert(not h.app.placedSerial)
 h.node.Value=50;h.node.Changed:Fire();assert(#h.queue==1);h.drain();assert(h.app.placedSerial==1)
end)
test('confirmed purchases continue until the available money is spent',function()
 local h=setup();h.node.Value=150;h.app.runMatchBurst()
 assert(h.app.placedSerial==3 and h.node.Value==0 and h.waits()==3 and not h.app.matchBusy)
end)
test('eight is only a yield batch and does not cap total defenses',function()
 local h=setup();h.node.Value=1000;h.app.runMatchBurst();assert(h.app.placedSerial==8)
 h.drain();assert(h.app.placedSerial==20 and h.node.Value==0)
end)
test('income during an active request cannot run a second placement worker',function()
 local h=setup();local depth,maximum=0,0;h.node.Value=150
 h.app.matchTick=function()
  depth=depth+1;maximum=math.max(maximum,depth)
  h.app.requestBuildWake();h.app.runMatchBurst()
  if h.node.Value>=50 then h.node.Value=h.node.Value-50;h.app.placedSerial=(h.app.placedSerial or 0)+1 end
  depth=depth-1
 end
 -- Only request another wake while a purchase actually succeeds.
 local action=h.app.matchTick
 h.app.matchTick=function()if h.node.Value>=50 then action()end end
 h.app.runMatchBurst();h.drain();assert(maximum==1 and h.app.placedSerial==3)
end)
test('new income clears only funds retry cooldown and preserves rejected spatial slots',function()
 local h=setup();h.app.bindBuildCash();h.drain();h.app.next.place=10;h.app.placeFailureReason='funds';h.app.rejected={bad=8}
 h.node.Value=50;h.node.Changed:Fire();assert(h.app.next.place==0 and h.app.rejected.bad==8)
 h.drain();h.app.next.place=10;h.app.placeFailureReason='cooldown';h.node.Value=100;h.node.Changed:Fire()
 assert(h.app.next.place==10)
end)
test('disabled automation editor and lobby do not schedule new purchases',function()
 for _,kind in ipairs({'enabled','autoPlace','editing','lobby','stopped'})do
  local h=setup()
  if kind=='enabled'then h.cfg.enabled=false elseif kind=='autoPlace'then h.cfg.autoPlace=false
  elseif kind=='editing'then h.app.editing=true elseif kind=='lobby'then h.app.mode='LOBBY'else h.app.alive=false end
  h.app.requestBuildWake();assert(#h.queue==0)
 end
end)
test('rebinding replicated cash disconnects the previous listener',function()
 local h=setup();h.app.bindBuildCash();h.drain();local previous=h.app.buildCashConnection
 local newer={Value=0,Changed=signal(),GetPropertyChangedSignal=h.node.GetPropertyChangedSignal}
 h.app.data=function()return newer end;h.app.bindBuildCash();h.drain()
 assert(not previous.Connected);h.node.Value=50;h.node.Changed:Fire();assert(#h.queue==0)
end)
test('a failed action releases the worker lock and later income can retry',function()
 local h=setup();h.app.matchTick=function()error('temporary native failure')end;h.app.runMatchBurst()
 assert(not h.app.matchBusy and h.app.notes.worker:find('temporary native failure',1,true))
 h.app.matchTick=function()if not h.app.placedSerial then h.app.placedSerial=1 end end
 h.app.requestBuildWake();h.drain();assert(h.app.placedSerial==1)
end)
test('changing map during a burst stops purchases against the previous map',function()
 local h=setup();local calls=0
 h.app.matchTick=function()calls=calls+1;h.app.placedSerial=1;h.app.mapId='Map2'end
 h.app.runMatchBurst();assert(calls==1)
end)
print(tests..' cash-wake, burst-purchase and serialized worker checks passed')
