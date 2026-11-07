local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
local function extract(a,b)local x=assert(source:find(a,1,true));local y=assert(source:find(b,x+#a,true));return source:sub(x,y-1)end
local code=extract('local function wakeEggs(', 'watchEggSignals()\n-- These listeners')..'\nreturn {watch=watchEggSignals,poll=pollEggReset,observe=observeField}'
local function signal()
 local handlers={};return{Connect=function(_,fn)local entry={fn=fn};handlers[#handlers+1]=entry;return{Disconnect=function()entry.off=true end}end,
 Fire=function(_,...)for _,h in ipairs(handlers)do if not h.off then h.fn(...)end end end}
end
local now,period,running,records,methods
local function setup()
 now=100;period=1;running=true;records={{Uid='egg',Version=1}}
 state={};blocked={};pending={};cooldown={steal=50};connections={}
 api={eggs={ReadFieldEggs=function()return{Records=records}end},clock={Now=function()return now end},cycle={IsRunning=function()return running end,PeriodIndexAt=function()return period end,NextResetTime=function()return 1234 end}}
 for _,name in ipairs({'FieldRefreshed','FieldShifted','FieldGone','ResetCountdown','RarityRevealed'})do api.eggs[name]=signal()end
 methods=assert(load(code))();methods.watch();state.eggUrgent=nil
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('native field batch immediately wakes selection and clears changed-version cooldown',function()
 blocked.egg=999;cooldown.steal=999
 api.eggs.FieldRefreshed:Fire{Records={{Uid='egg',Version=2}}}
 assert(blocked.egg==nil and cooldown.steal==0 and state.eggUrgent and state.fieldVersions.egg==2)
end)
test('same-version refresh preserves rejection backoff',function()
 blocked.egg=999;api.eggs.FieldRefreshed:Fire{Records={{Uid='egg',Version=1}}}
 assert(blocked.egg==999)
end)
test('individual native spawn reopens a reused UID with a new version',function()
 blocked.egg=999;api.eggs.FieldShifted:Fire{Uid='egg',Version=2}
 assert(not blocked.egg and state.fieldVersions.egg==2 and state.eggUrgent)
end)
test('native field removal invalidates target eligibility',function()
 blocked.egg=999;api.eggs.FieldGone:Fire('egg')
 assert(not blocked.egg and not state.fieldVersions.egg and state.eggUrgent)
end)
test('reset countdown arms the server deadline without clearing retry backoff early',function()
 blocked.egg=999;api.eggs.ResetCountdown:Fire{DayStartsAt=105};methods.poll()
 assert(blocked.egg==999 and state.countdownAt==105 and not state.resetSync)
end)
test('countdown boundary wakes once and preserves uncertain pickup ownership',function()
 methods.poll();pending.carry={};state.pickupPending={uid='egg'};state.hatchInFlight={uid='owned'};blocked.egg=999;blocked['SammyEvent:1:zone:1']=999
 api.eggs.ResetCountdown:Fire{DayStartsAt=105};now=105;methods.poll()
 assert(state.resetSync and not blocked.egg and blocked['SammyEvent:1:zone:1']==999)
 assert(pending.carry and state.pickupPending.uid=='egg'and state.hatchInFlight.uid=='owned')
 state.resetSync=nil;state.eggUrgent=nil;methods.poll();assert(not state.resetSync and not state.eggUrgent)
end)
test('a repeated expired countdown cannot retrigger the reset or clear fresh backoff',function()
 methods.poll();api.eggs.ResetCountdown:Fire{DayStartsAt=105};now=105;methods.poll()
 state.resetSync=nil;state.eggUrgent=nil;blocked.egg=999
 api.eggs.ResetCountdown:Fire{DayStartsAt=105};api.eggs.ResetCountdown:Fire{DayStartsAt=104};methods.poll()
 assert(not state.resetSync and not state.eggUrgent and blocked.egg==999)
end)
test('native schedule override drives timer rather than a hardcoded five-minute loop',function()
 methods.poll();assert(state.nextResetAt==1234);period=2;methods.poll();assert(state.resetSync and state.resetPeriod==2)
end)
test('disabled native reset timer never fabricates another reset',function()
 methods.poll();running=false;period=99;methods.poll();assert(not state.resetSync and not state.nextResetAt)
end)
test('rarity reveal invalidates old rejects and only accepts increasing periods',function()
 blocked.egg=999;api.eggs.RarityRevealed:Fire{PeriodIndex=4};assert(not blocked.egg and state.resetSync and state.revealPeriod==4)
 state.resetSync=nil;state.eggUrgent=nil;blocked.egg=999
 api.eggs.RarityRevealed:Fire{PeriodIndex=4};api.eggs.RarityRevealed:Fire{PeriodIndex=3}
 assert(not state.eggUrgent and blocked.egg==999 and not state.resetSync)
end)
test('fresh field batch satisfies a queued reset refresh',function()
 state.resetSync=true;api.eggs.FieldRefreshed:Fire{Records={{Uid='new',Version=1}}}
 assert(not state.resetSync and not state.fieldVersions.egg and state.fieldVersions.new==1)
end)
test('close disconnects all field listeners without spawning a movement worker',function()
 assert(#connections==5);for _,c in ipairs(connections)do c:Disconnect()end
 state.eggUrgent=nil;api.eggs.FieldShifted:Fire{Uid='other',Version=1};assert(not state.eggUrgent)
end)
print(n..' native field signals, reset clock and in-flight ownership checks passed')
