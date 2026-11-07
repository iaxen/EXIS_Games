local Core=assert(loadfile('Games/StealAnEgg.lua'))('EXIS_TEST')
local V={};V.__index=function(t,k)if k=='Magnitude'then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z)end end
local function vec(x,y,z)return setmetatable({X=x,Y=y,Z=z},V)end
V.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
local assets={Chicken={Rarity={_id='Common',Rank=1}},Dragon={Rarity={_id='Secret',Rank=10}}}
local function egg(uid,category,area,state,d)return{Uid=uid,AssetCategory=category,AreaId=area,NestId='Slot_001',State=state or'Slot',BottomCFrame={Position=vec(d or 10,0,0)}}end
local options={excluded={},excludedPets={},rarities={}}
local n=0
local function check(name,fn)options={excluded={},excludedPets={},rarities={}};fn();n=n+1;print('PASS '..name)end
check('rarity outranks distance',function()local a=egg('a','Chicken','Forest',nil,1);local b=egg('b','Dragon','Volcano',nil,100);assert(Core.choose({a,b},options,assets,vec(0,0,0),{},0)==b)end)
check('equal rarities prefer nearest',function()local a=egg('a','Dragon','Forest',nil,1);local b=egg('b','Dragon','Forest',nil,100);assert(Core.choose({b,a},options,assets,vec(0,0,0),{},0)==a)end)
check('excluded biome is never targeted',function()options.excluded.Volcano=true;assert(not Core.allowed(egg('b','Dragon','Volcano'),options,assets))end)
check('pet exclusion is independent from biome',function()options.excludedPets.Dragon=true;assert(not Core.allowed(egg('b','Dragon','Forest'),options,assets))end)
check('rarity exclusion applies to all pets in tier',function()options.rarities.Secret=false;assert(not Core.allowed(egg('b','Dragon','Forest'),options,assets))end)
check('carried and claimed eggs are not stolen again',function()for _,s in ipairs({'Carried','Claimed','GuardCarried'})do assert(not Core.allowed(egg('a','Chicken','Forest',s),options,assets))end end)
check('dropped eggs remain eligible',function()for _,s in ipairs({'Dropped'})do assert(Core.allowed(egg('a','Chicken','Forest',s),options,assets))end end)
check('unknown categories are skipped',function()assert(not Core.allowed(egg('a','Unknown','Forest'),options,assets))end)
check('rejected eggs back off without hiding other targets',function()local a=egg('a','Dragon','Forest');local b=egg('b','Chicken','Forest');assert(Core.choose({a,b},options,assets,vec(0,0,0),{a=5},1)==b);assert(Core.choose({a,b},options,assets,vec(0,0,0),{a=5},6)==a)end)
check('first-area carry includes native slot key',function()assert(Core.firstSlot(egg('FirstAreaEgg_4','Chicken','Forest'))=='Forest:Slot_001');assert(Core.firstSlot(egg('ordinary','Chicken','Forest'))==nil)end)
check('larger highest-rarity egg outranks a nearer smaller egg',function()
 local a=egg('small','Dragon','Forest',nil,1);a.BoundsSize=vec(2,4,2);a.AssetScale=1
 local b=egg('big','Dragon','Volcano',nil,1000);b.BoundsSize=vec(4,8,4);b.AssetScale=2
 assert(Core.choose({a,b},options,assets,vec(0,0,0),{},0)==b)
end)
check('rarity always outranks size across tiers',function()
 local a=egg('common','Chicken','Forest',nil,1);a.BoundsSize=vec(100,100,100)
 local b=egg('rare','Dragon','Volcano',nil,1000);b.BoundsSize=vec(1,1,1)
 assert(Core.choose({a,b},options,assets,vec(0,0,0),{},0)==b)
end)
check('scale resolves size when bounds are absent',function()
 local a=egg('a','Dragon','Forest',nil,1);a.AssetScale=1
 local b=egg('b','Dragon','Forest',nil,100);b.AssetScale=3
 assert(Core.choose({a,b},options,assets,vec(0,0,0),{},0)==b)
end)
check('identical rarity size and distance select a stable UID',function()
 local a=egg('a','Dragon','Forest');local b=egg('b','Dragon','Forest')
 assert(Core.choose({b,a},options,assets,vec(0,0,0),{},0)==a)
 assert(Core.choose({a,b},options,assets,vec(0,0,0),{},0)==a)
end)
local kernel={MayEnterFuse=function(_,item)return not item.IsFavorite and not item.InFuse end}
check('fusion takes exactly native input count of matching duplicates',function()local inv={}for i=1,4 do inv[tostring(i)]={Category='Chicken'}end;local g=Core.fuseGroup(inv,{},assets,kernel,3);assert(#g==3 and g[1]=='1'and g[3]=='3')end)
check('fusion excludes equipped favorite and temporary pets',function()local inv={a={Category='Chicken'},b={Category='Chicken',IsFavorite=true},c={Category='Chicken',CreatorTemporary=true},d={Category='Chicken'}};assert(not Core.fuseGroup(inv,{a=true},assets,kernel,2))end)
check('fusion cannot mix categories or load already fused pets',function()local inv={a={Category='Chicken'},b={Category='Dragon'},c={Category='Chicken',InFuse=true}};assert(not Core.fuseGroup(inv,{},assets,kernel,2))end)
check('unrelated ownership gains do not count as egg redemption',function()
 assert(not Core.claimReceipt('u','Chicken',{}, {reward={AssetCategory='Dragon'}}))
 assert(Core.claimReceipt('u','Chicken',{}, {newId={AssetCategory='Chicken'}}))
 assert(not Core.claimReceipt('u','Chicken',{old={AssetCategory='Chicken'}},{old={AssetCategory='Chicken'}}))
end)
check('egg type switches filter independently of pet exclusions',function()
 options.eggTypes={Dragon=false};assert(not Core.allowed(egg('b','Dragon','Forest'),options,assets))
 options.eggTypes.Dragon=true;assert(Core.allowed(egg('b','Dragon','Forest'),options,assets))
 options.excludedPets.Dragon=true;assert(not Core.allowed(egg('b','Dragon','Forest'),options,assets))
end)
print(n..' egg selection and native fusion policy checks passed')
