local source=assert(io.open('Games/MrbeastIslandEscape.lua')):read('*a')
local function extract(a,b)local i=assert(source:find(a,1,true),a);local j=assert(source:find(b,i+#a,true),b);return source:sub(i,j-1)end
local function body(a,b)assert(load(extract(a,b)))()end
local now,cfg,stock,bagId,chosen,reply
local function setup()
 now=0;os.clock=function()return now end;stock={Wood=0,Axe=0,Torch=1};bagId='bag1';chosen=nil;reply=nil
 cfg={item={byId={},byDisplayName={}},tool={byId={},byDisplayName={}},food={byId={}},bag={byId={bag2={displayName='Better bag',cap=30,lvl=2}}},armour={byId={vest={typeCN='body',lvl=2},oldVest={typeCN='body',lvl=1}}}}
 for id,name in pairs({wood='Wood',axe='Axe',torch='Torch',vest='Vest'})do local it={id=id,displayName=name};cfg.item.byId[id]=it;cfg.item.byDisplayName[name]=it end
 cfg.tool.byId.axe={lvl=2,toolType='axe',atkDmg=15};cfg.tool.byDisplayName.Axe=cfg.tool.byId.axe
 cfg.tool.byId.torch={lvl=1,toolType='torch',atkDmg=1};cfg.tool.byDisplayName.Torch=cfg.tool.byId.torch
 config=function()return cfg end;opts={retreatHealth=35};player={GetAttribute=function()return bagId end}
 root=function()return{},{Health=100,MaxHealth=100,GetAttribute=function(_,k)return k=='hunger'and 80 or 100 end}end
 count=function(name)return stock[name]or 0 end
 tools=function()return{{Name='Torch'}}end
 work={sent=0,choiceVersion=1,equippedArmour={body='oldVest'},needs={},bagState=function()return 5,15 end,
 baseThreat=function()end,personalThreat=function()end,bagRank=function(id)return id=='bag2'and 30 end,
 questTotal=function()return 0 end,choicePanel=function()return{Visible=true}end}
 RS={Engine={Service={FindFirstChild=function()return{FindFirstChild=function()return{FireServer=function(_,index)chosen=index;if reply then reply()end end}end}end}}}
 work.await=function(_,fn,seconds)local untilTime=now+seconds repeat if fn()then return true end;now=now+.1 until now>=untilTime;return false end
 body('    function work.choiceScore(', '    function work.choicePanel()')
 body('    function work.rewardChoiceTick()', '    local fish = {')
end
local n=0
local function test(name,fn)setup();fn();n=n+1;print('PASS '..name)end
test('a native bag-only config remains a valid reward candidate',function()
 assert(work.choiceScore{itemId='bag2',count=1}>700000)
end)
test('equipped armour upgrades outrank optional crafting materials',function()
 work.objective={amounts={wood=10}};assert(work.choiceScore{itemId='vest'}>work.choiceScore{itemId='wood'})
end)
test('useful weapon upgrades outrank ordinary material rewards',function()
 work.objective={amounts={wood=10}};assert(work.choiceScore{itemId='axe'}>work.choiceScore{itemId='wood'})
end)
test('already-held torches do not outrank equipment upgrades',function()
 assert(work.choiceScore{itemId='torch'}<0 and work.choiceScore{itemId='axe'}>0)
end)
test('armour equip change confirms the selected reward',function()
 work.choices={{itemId='vest',count=1}};reply=function()work.equippedArmour.body='vest'end
 assert(work.rewardChoiceTick()and chosen==1 and not work.choices)
end)
test('the selected bag ID confirms its capacity upgrade',function()
 work.choices={{itemId='bag2',count=1}};reply=function()bagId='bag2'end
 assert(work.rewardChoiceTick()and chosen==1 and not work.choices)
end)
test('an unrelated inventory change cannot confirm an unreceived weapon reward',function()
 work.choices={{itemId='axe',count=1}};work.signature=function()return tostring(stock.Torch)end;reply=function()stock.Torch=0 end
 assert(not work.rewardChoiceTick()and work.choices and work.choiceSentVersion==1)
end)
test('native receipt of the selected item confirms the claim',function()
 work.choices={{itemId='axe',count=1}};reply=function()stock.Axe=1 end
 assert(work.rewardChoiceTick()and not work.choices)
end)
test('advancing the native reward queue retains the newly offered choices',function()
 local nextChoices={{itemId='bag2',count=1}};work.choices={{itemId='axe',count=1}}
 reply=function()work.choices=nextChoices;work.choiceVersion=2 end
 assert(work.rewardChoiceTick()and work.choices==nextChoices)
end)
test('unchanged already-equipped armour is not a fabricated reward receipt',function()
 work.equippedArmour.body='vest';work.choices={{itemId='vest',count=1}}
 assert(not work.rewardChoiceTick()and work.choices)
end)
print(n..' MrBeast reward selection and exact receipt checks passed')
