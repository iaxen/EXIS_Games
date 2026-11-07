local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local pages,controls,values,order={},{},{},{}
work={slider=function(parent,key)values[key]=values[key]or{};values[key][#values[key]+1]=parent.page end}
flags={};opts={evadeMove='Teleport',move='Walk',codes=''};toggles={};motion={};connections={};selected={}
Color3={fromRGB=function()return{}end};UDim2={new=function()return{}end,fromOffset=function()return{}end};Enum={Font={BuilderSans='Sans'}}
pg={};gui={};blue={};white={};save=function()end;corner=function()end
page=function(name)order[#order+1]=name;local p={page=name};pages[name]=p;return p end
group=function(parent,name)assert(parent,'missing parent for '..name);return{page=parent.page,title=name}end
text=function()return{}end
button=function(_,label)return{Text=label}end
number=function(parent,key)values[key]=values[key]or{};values[key][#values[key]+1]=parent.page end
switch=function()return function()end end
toggle=function(parent,key)
 assert(not controls[key],'duplicate control '..key);controls[key]=parent.page
end
make=function()return{FocusLost={Connect=function()end}}end
assert(load(extract('    function work.makeSuiteUI(p)', '    local main=page("Main")')))()
local head=extract('    local main=page("Main")', '    local function stopAll()')
local aliases=assert(load(head..'\nreturn{main=main,gather=resources,camp=camp,craft=craft,quests=questPage,explore=explore,settings=settings,combat=combatPage,food=foodPage,inventory=inventoryPage,survival=survivalPage,rewards=rewardsPage,rounds=roundsPage,esp=espPage,status=statusPage}'))()
work.makeSuiteUI(aliases)
local expected={eat='Food',combat='Combat',autoAttack='Combat',killFoodOnSight='Combat',huntFood='Combat',
 unloadBag='Inventory',tidyTools='Inventory',tidyBag='Inventory',bagUpgrade='Inventory',quest='Quests',choiceRewards='Quests',
 redeemCodes='Rewards',daily='Rewards',weekly='Rewards',playtime='Rewards',dailyQuest='Rewards',
 fuel='Camp',cook='Food',cooked='Food',smelt='Craft',smeltCollect='Craft',build='Camp',buildCurrent='Camp',
 buildCamp='Camp',buildBoat='Explore',nightHover='Survival',holdNight='Survival',runShadow='Survival',
 fish='Fishing',autoRound='Rounds',leaveLost='Rounds',liveStatus='Status'}
for key,wanted in pairs(expected)do assert(controls[key]==wanted,key..' is in '..tostring(controls[key])..' instead of '..wanted)end
assert(values.threatScanRadius[1]=='Combat')
assert(#values.hunger==1 and values.hunger[1]=='Food'and #values.hoverHeight==1 and values.hoverHeight[1]=='Survival')
print('PASS production controls have one category each and meal thresholds are not duplicated')
for _,name in ipairs({'Main','Survival','Combat','Food','Inventory','Gather','Camp','Craft','Quests','Rewards','Explore','Fishing','Rounds','ESP','Status','Settings'})do assert(pages[name],name)end
print('PASS related game settings have dedicated pages within the universal shell')
assert(controls.redeemCodes=='Rewards'and controls.liveStatus=='Status')
print('PASS reward codes and live display no longer sit in unrelated round and master groups')

assert(order[#order]=='Diagnostics'and order[#order-1]=='Settings')
print('PASS diagnostics is the final sidebar category')
