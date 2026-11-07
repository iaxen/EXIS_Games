local paths={'Games/MrbeastIslandEscape.lua','Games/ZombieRushSurvival.lua'}
local block
for _,path in ipairs(paths)do
 local source=assert(io.open(path)):read('*a')
 local ending=assert(source:find('local diagnostic\n-- End session diagnostics.',1,true))
 local candidate=source:sub(1,ending-1)
 if block then assert(block==candidate,'embedded diagnostic implementations diverged')else block=candidate end
 assert(load(source),'complete game module does not compile')
end
local now,files,writes,fail=0,{},0,false
local env=setmetatable({os={clock=function()return now end,date=function()return'20261107_120000'end}},{__index=_G})
local D=assert(load(block..'\nreturn Diagnostics','logger','t',env))()
local function setup()
 now=0;files={};writes=0;fail=false
 local storage={path=function(p)return'EXIGames/Test/'..p end,
 write=function(p,data)writes=writes+1;if fail then error('disk unavailable')end;files[p]=data end,
 read=function(p)assert(files[p],'missing saved chunk');return files[p]end}
 return D.new('Test',storage),storage
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
test('both standalone games embed the same tested diagnostics and compile',function()assert(block)end)
test('ordinary waiting is distinguished from an action failure',function()
 assert(D.level('WAITING FOR FUNDS')=='WAIT');assert(D.level('BAG FULL; SUBMITTING')=='WAIT')
 assert(D.level('NO COMPLETED REWARDS')=='INFO');assert(D.level('COPIED FULL LOG')=='INFO')
 assert(D.level('REJECTED: outside range')=='ERROR');assert(D.level('UNAVAILABLE: Place')=='ERROR')
end)
test('failures retain the failing action reason count and time',function()
 local log=setup();now=5;log:record('chest','ERROR: prompt hold expired')
 now=6;log:record('chest','ERROR: prompt hold expired')
 assert(log.failures.chest.count==2 and log.failures.chest.at==6 and log.suppressed==1)
 assert(log:summary():find('prompt hold expired',1,true))
end)
test('unchanged status spam is counted without growing the log',function()
 local log=setup();for i=1,1000 do log:record('gather','WAITING FOR DROP')end
 assert(#log.chunk==2 and log.suppressed==999 and log.latest.gather.count==1000)
end)
test('force logging preserves separate identical remote requests',function()
 local log=setup();for i=1,5 do log:record('Place','REQUEST STARTED','INFO',true)end
 assert(#log.chunk==6)
end)
test('status transitions update current waits while retaining past errors',function()
 local log=setup();log:record('Place','ERROR: funds');log:record('Place','WAITING FOR CASH');log:record('Place','PLACED')
 assert(log.failures.Place and log.latest.Place.level=='INFO')
 assert(not log:summary():find('Place: WAITING',1,true))
end)
test('persisted chunks preserve older entries outside the eighty-row live view',function()
 local log=setup();for i=1,550 do log:record('Place','ACTION '..i,'INFO',true)end
 assert(#log.parts==2 and #log.recent==80 and #log.chunk==151)
 local report=log:report('MAP Skyline')
 for i=1,550 do assert(report:find('ACTION '..i..'\n',1,true)or report:sub(-#('ACTION '..i))=='ACTION '..i)end
 assert(not log:tail():find('ACTION 1\n',1,true)and report:find('MAP Skyline',1,true))
end)
test('the full export includes complete traces while the live view is shortened',function()
 local log=setup();local reason='ERROR: '..string.rep('x',1600)..' trace end'
 log:record('worker',reason);assert(log:report():find(reason,1,true))
 assert(not log:tail():find('trace end',1,true)and log:summary(true):find('full reason in export',1,true))
end)
test('saving a full report stays inside the game save folder',function()
 local log=setup();log:record('craft','ERROR: missing recipe')
 local path=log:saveReport('BAG 1/10');assert(path:find('EXIGames/Test/diagnostic_',1,true)==1)
 assert(files[path:sub(#'EXIGames/Test/'+1)]:find('missing recipe',1,true))
end)
test('periodic flush skips unchanged buffers',function()
 local log=setup();assert(log:flush());local before=writes;assert(log:flush()and writes==before)
end)
test('file failures remain visible and retries are throttled',function()
 local log=setup();fail=true;assert(not log:flush());local before=writes
 for i=1,500 do log:record('work','ROW '..i,'INFO',true)end
 assert(writes==before and log:summary():find('LOG SAVE FAILED',1,true))
 fail=false;now=4;assert(log:flush()and log.storageError==nil)
end)
test('file-less sessions bound memory and explicitly report incomplete history',function()
 local log=setup();fail=true
 for i=1,2500 do log:record('work','ROW '..i,'INFO',true)end
 assert(#log.chunk==2000 and #log.recent==80 and log.discarded==501)
 assert(log:report():find('INCOMPLETE LOG',1,true))
end)
test('missing saved chunks are explicitly identified rather than silently skipped',function()
 local log=setup();for i=1,201 do log:record('work','ROW '..i,'INFO',true)end
 files[log.parts[1]]=nil;assert(log:report():find('LOG READ FAILED',1,true))
end)
test('response descriptions preserve rejection details without traversing instance arguments',function()
 assert(D.describe({ok=false,reason='occupied'}):find('occupied',1,true))
 assert(D.describe(nil)=='nil'and D.describe(false)=='false')
end)
print(tests..' session diagnostic, persistence and export checks passed')
