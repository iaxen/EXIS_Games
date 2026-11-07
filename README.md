# EXIS Games

Game implementations used by the [EXIScript universal loader](https://github.com/iaxen/EXIScript).

## Launch

After joining a supported game, execute:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/iaxen/EXIScript/main/EXIScript.lua?exis=" .. tostring(os.time())))()
```

The loader selects the current game and downloads its file from this repository. Changes in either repository must be merged to `main` to affect this command. The URL query requests a fresh launcher; the launcher also adds its build/time to the game-file URL.

| Game | File |
| --- | --- |
| Fuzzotopia: Cozy Hideaway | [Games/Fuzzotopia.lua](Games/Fuzzotopia.lua) |
| MrBeast Island Escape | [Games/MrbeastIslandEscape.lua](Games/MrbeastIslandEscape.lua) |
| Zombie Rush Survival | [Games/ZombieRushSurvival.lua](Games/ZombieRushSurvival.lua) |
| Steal an Egg | [Games/StealAnEgg.lua](Games/StealAnEgg.lua) |

## Steal an Egg

Known place: `107778070777162`. Select filters, use **Enable core automation**, then enable **Master switch**. Master starts off each session.

- Rarity-first field egg selection; biome/rarity/pet exclusions
- Teleport approach with native pickup timing; walking return and ownership receipts
- Planting/native hatching, equip best and own-treadmill training
- Optional cash upgrades, index rewards and matching-pet fusion
- Supported event pickups: Light vs Darkness rings and Sammy pickups; event eggs in the field snapshot
- Performance page: hide pen visuals and pets, reduce textures/material detail/shadows/effects/videos
- Tools page: FPS/task/module/request diagnostics, copy/save logs, settings save/reload, snapshot refresh, anti-idle and optional session/reconnect controls

Visual changes are reversible. Fusion consumes pets/cash and has a separate toggle. Full race/obby/boss/multi-stage-event completion is not implemented. See [native audit and limitations](Docs/StealAnEgg_Native_Audit.md).

## Startup troubleshooting

The universal loader shows **Detecting → Downloading → Compiling → Starting**. Errors stay visible with the build and actual error. The game shows the native module currently loading and returns startup failure to the loader instead of silently swallowing it.

If no panel opens, copy the last visible stage and full error, plus PlaceId/GameId. If the main panel opens but automation fails, use **Tools → Copy diagnostics** or save the diagnostics text. A paused Master is not a failed startup. New modules, executor HTTP/loadstring/require support and server behavior require live verification.

## Checks

The Lua files under `Tests/*/` run from this repository root using Lua 5.3+ or `texlua`. The Steal an Egg suite includes a mocked whole-script startup plus failure propagation; it is not a live Roblox test. Scripts are also checked with a Roblox Luau compiler when available. No guarantee of flawless AFK play or measured FPS gain is made.
