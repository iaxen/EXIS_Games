local mr=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local zr=assert(io.open('Games/ZombieRushSurvival.lua')):read('*a')
local function extract(s,a,b)local i=assert(s:find(a,1,true));local j=assert(s:find(b,i+#a,true));return s:sub(i,j-1)end
local D=assert(load(mr:sub(1,assert(mr:find('local diagnostic\n-- End session diagnostics.',1,true))-1)..'\nreturn Diagnostics'))()
local function logger()return D.new('Test',{write=function()end,read=function()return''end,path=function(p)return'EXIGames/Test/'..p end})end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('PASS '..name)end
test('MrBeast protected job failures include their action and complete traceback',function()
 local log=logger();local env=setmetatable({taskStatus={},recentErrors={},diagnostic=log,Diagnostics=D,say=function()end},{__index=_G})
 local safe=assert(load(extract(mr,'    local function note(', '    local englishTranslator = nil')..'\nreturn safely','job logger','t',env))()
 assert(safe('chests',function()error('hold interaction broke')end)==false)
 assert(log.failures.chests.reason:find('hold interaction broke',1,true))
 assert(log:report():find('stack traceback:',1,true))
 assert(safe('progression',function()return false end)==false and not log.failures.progression)
end)
test('ZombieRush remote rejections preserve the server reason and action',function()
 local log=logger();local app={alive=true,next={},notes={}}
 local env=setmetatable({diagnostic=log,Diagnostics=D,app=app,cfg={enabled=true},os={clock=function()return 0 end}},{__index=_G})
 assert(load(extract(zr,'    function app.note(', '    function app.ownedClass('),'request logger','t',env))()
 local remote={IsA=function()return true end,InvokeServer=function()return{ok=false,reason='occupied'}end}
 app.invoke('place',remote,'Turret');assert(log.failures.place.reason=='REJECTED: occupied')
 assert(log:report():find('REQUEST STARTED',1,true))
end)
test('ZombieRush missing remotes and thrown transport errors are recorded',function()
 local log=logger();local app={alive=true,next={},notes={}}
 local env=setmetatable({diagnostic=log,Diagnostics=D,app=app,cfg={enabled=true},os={clock=function()return 0 end}},{__index=_G})
 assert(load(extract(zr,'    function app.note(', '    function app.ownedClass('),'request logger','t',env))()
 assert(app.invoke('place',nil)==nil and log.failures.place.reason:find('RemoteFunction',1,true))
 local remote={IsA=function()return true end,InvokeServer=function()error('transport failure')end}
 app.invoke('upgrade',remote);assert(log.failures.upgrade.reason:find('transport failure',1,true))
end)
test('ZombieRush callback exceptions reach diagnostics without killing later callbacks',function()
 local log=logger();local app={connections={}};local callback
 local signal={Connect=function(_,fn)callback=fn;return{}end}
 local env=setmetatable({diagnostic=log,Diagnostics=D,app=app},{__index=_G})
 assert(load(extract(zr,'    function app.connect(', '    function app.find('),'callback logger','t',env))()
 app.connect(signal,function()error('save full log failed')end);callback()
 assert(log.failures.callback.reason:find('save full log failed',1,true))
 local done=false;app.connect(signal,function()done=true end);callback();assert(done)
end)
test('Diagnostics is the final ZombieRush sidebar category',function()
 local order={};local ui={page=function(name)order[#order+1]=name;return{}end}
 local env=setmetatable({ui=ui},{__index=_G})
 assert(load(extract(zr,'    local main = ui.page("MAIN")','    local contextLabel ='),'sidebar','t',env))()
 assert(order[#order]=='DIAGNOSTICS'and order[#order-1]=='SETTINGS')
end)
test('copy and save actions use complete session exports in both games',function()
 for _,source in ipairs({mr,zr})do
  local callbacks={};local copied,saved
  local group={}
  local log={report=function(_,snapshot)assert(snapshot=='SNAPSHOT');return'COMPLETE HISTORY'end,
    saveReport=function(_,snapshot)saved=snapshot;return'EXIGames/Test/report.txt'end}
  local env=setmetatable({diagnostic=log,diag=group,diagnostics=group,work={diagnosticSnapshot='SNAPSHOT'},
    app={diagnosticSnapshot='SNAPSHOT',note=function()end},setclipboard=function(value)copied=value end,
    refreshDiagnostics=function()end,say=function()end,button=function(_,name,fn)callbacks[name]=fn end,
    ui={button=function(_,name,fn)callbacks[name]=fn end}},{__index=_G})
  local start=source==mr and '    button(diag, "COPY DIAGNOSTICS"'or'    ui.button(diagnostics, "COPY DIAGNOSTICS"'
  assert(load(extract(source,start,'    task.spawn(function()'),'export actions','t',env))()
  callbacks['COPY DIAGNOSTICS']();callbacks['SAVE FULL LOG']()
  assert(copied=='COMPLETE HISTORY'and saved=='SNAPSHOT')
 end
end)
print(tests..' game diagnostic wiring, callback and export checks passed')
