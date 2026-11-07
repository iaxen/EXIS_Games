local source=assert(io.open('Games/StealAnEgg.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true));local j=assert(source:find(b,i+#a,true));return source:sub(i,j-1)end
local function obj(class,parent)
 local o={Parent=parent or true,LocalTransparencyModifier=.2,Transparency=.25,Enabled=true,Material='Wood',Reflectance=.4,CastShadow=true}
 function o:IsA(k)return k==class end
 function o:IsDescendantOf(root)return self.root==root end
 return o
end
local function setup()
 perf={saved=setmetatable({},{__mode='k'}),prefs={}};options={};api={plots={ReadOwners=function()return{}end}};player={UserId=1}
 restoreVisuals,writeVisual,hideVisual=assert(load(extract('local function restoreVisuals()', 'local function otherPlotRoots()')..'\nreturn restoreVisuals,writeVisual,hideVisual'))()
 applyVisual=assert(load(extract('local function applyVisual(', 'local preferences')..'\nreturn applyVisual'))()
 Enum={Material={SmoothPlastic='Plain'}}
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('visual restoration preserves original values across repeated writes',function()
 local part=obj('BasePart');writeVisual(part,'Reflectance',0);writeVisual(part,'Reflectance',.1);restoreVisuals();assert(part.Reflectance==.4)
end)
test('false properties are retained in the restoration snapshot',function()
 local effect=obj('ParticleEmitter');effect.Enabled=false;writeVisual(effect,'Enabled',true);restoreVisuals();assert(effect.Enabled==false)
end)
test('pen hiding only affects the other plot subtree and never collision',function()
 options.hidePens=true;local root={};local other=obj('BasePart');other.root=root;other.CanCollide=true
 local own=obj('BasePart');applyVisual(other,{root});applyVisual(own,{root})
 assert(other.LocalTransparencyModifier==1 and other.CanCollide and own.LocalTransparencyModifier==.2)
 restoreVisuals();assert(other.LocalTransparencyModifier==.2)
end)
test('low detail restores textures materials reflectance and shadows',function()
 options.lowDetail=true;local part=obj('BasePart');local decal=obj('Decal');applyVisual(part,{});applyVisual(decal,{})
 assert(part.Material=='Plain'and part.Reflectance==0 and not part.CastShadow and decal.Transparency==1)
 restoreVisuals();assert(part.Material=='Wood'and part.Reflectance==.4 and part.CastShadow and decal.Transparency==.25)
end)
test('effects toggle never disables a proximity prompt',function()
 options.disableEffects=true;local effect=obj('ParticleEmitter');local prompt=obj('ProximityPrompt')
 applyVisual(effect,{});applyVisual(prompt,{});assert(not effect.Enabled and prompt.Enabled);restoreVisuals();assert(effect.Enabled)
end)
test('different performance modes have different invalidation signatures',function()
 local signature=assert(load(extract('local function performanceSignature()', 'local function refreshPerformance()')..'\nreturn performanceSignature'))()
 options.hidePens=true;options.lowDetail=false;options.disableEffects=false;local a=signature()
 options.hidePens=false;options.lowDetail=true;assert(a~=signature())
end)
test('other pen roots exclude the local player and never return the whole plot',function()
 local ownDetail={},{};local otherDetail={}
 options.hidePens=true;api.plots.ReadOwners=function()return{[1]=1,[2]=9}end
 api.plots.ResolveFolder=function()return{FindFirstChild=function(_,slot)return{FindFirstChild=function(_,name)assert(name=='ToUpdate');return slot=='1'and ownDetail or otherDetail end}end}end
 local roots=assert(load(extract('local function otherPlotRoots()', 'local function applyVisual(')..'\nreturn otherPlotRoots'))()
 local list=roots();assert(#list==1 and list[1]==otherDetail)
end)
test('queued teleport loader honors the saved disabled flag',function()
 local queued;queue_on_teleport=function(code)queued=code end;syn=nil;savePath='EXIGames/StealAnEgg/settings_1.json'
 local queue=assert(load(extract('local function queueLoader()', 'button(session,"Rejoin current server"')..'\nreturn queueLoader'))()
 assert(queue());local enabled=false;local started=false
 game={PlaceId=107778070777162,GetService=function()return{JSONDecode=function()return{autoExecute=enabled}end}end,HttpGet=function()return'launch'end}
 readfile=function(path)assert(path==savePath)return'config'end;loadstring=function()return function()started=true end end
 assert(load(queued))();assert(not started)
 enabled=true;assert(load(queued))();assert(started)
end)
test('native preference toggles restore their original setting',function()
 local value=false;preferences={IsOn=function()return value end,Set=function(_,on)value=on;return true end}
 call=function(_,fn,...)return fn(...)end
 local sync=assert(load(extract('local function syncPreference(', 'local function restorePreferences()')..'\nreturn syncPreference'))()
 sync('HideOtherPets',true);assert(value and perf.prefs.HideOtherPets==false)
 sync('HideOtherPets',false);assert(not value and perf.prefs.HideOtherPets==nil)
end)
assert(loadfile('Games/StealAnEgg.lua'))
print(n..' performance ownership and restoration checks passed; module compiles')
