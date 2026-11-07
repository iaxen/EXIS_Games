# MrBeast camp stockpiles, survival and task queue

This describes the current `Games/MrbeastIslandEscape.lua` behavior against the two supplied MrBeast ZIP exports. The earlier chest/pickup audit remains in `Mrbeast_AFK_Interaction_Audit.md`. README retains only its launch command and supported games.

## Ground stockpiles and one-meal retrieval

Collected supplies go to a camp ground stockpile after usable quest/build/cook/smelt submissions. Food has a separate, higher-priority cache job beside the campfire; other supplies use the checked camp drop area outside automatic intake zones. New stock is no longer deposited into Storage by the unload job.

The bot retains one torch, one best working tool per native tool type, current quest supplies and exactly the ingredients required for a current direct craft. Non-swapping special tools retain their independent identities. It drops surplus ingredients, duplicate tools, spare torches, spare bags/armour and loose parts. This operational minimum is necessary to continue gathering and fighting; worn equipment remains governed by the native game. Unknown/unclassified items are retained instead of discarded blindly.

Food does not keep a permanent carried reserve. A healthy player drops every carried meal. A hungry or injured player retains at most one usable cooked meal across all stacks, retrieves one when needed, and cannot reclaim a second from the camp pile before using the first. Raw food and uncookable fruit remain excluded from eating. Food with negative configured health regeneration is excluded; zero-healing food is not consumed solely because health is low while hunger is already above the threshold.

The native contracts matter:

| Exported source | Observed behavior | Automation consequence |
| --- | --- | --- |
| PlayerInventory.onDropItem | Removes one inventory unit and creates one owned world model | Drop in acknowledged bounded batches; do not assume one call drops a stack |
| ItemCollect.onCollect | Adds one unit and destroys the collected world model | World reserves count collectible models, not a potentially misleading model count attribute |
| MakeFire.collectFoodRemote | Grants exactly one cooked item per accepted request | One confirmed request for a meal; retain a short pending lease after a delayed receipt |
| MakeFire / CampfireSpitMeat | Can emit ownerless cooked food at the fireZone perimeter | Recognize native cooked camp drops without immediately collecting them |
| Storage.takeItem | Takes the addable part of a whole slot rather than a requested single unit | Move legacy food stacks out to the camp pile; do not use whole-slot retrieval as a normal carried meal reserve |
| FoodClient | Sends eatRemote after its eating animation completes; unequipping stops it | Allow the native animation and receipt to complete, with a 12-second local bound and protected interaction state |
| ToolService.onEat | Applies configured health/hunger/thirst regeneration; raw meat may activate a damage challenge | Keep the cooked whitelist and check the native health regeneration field |

Fresh distant food loot can be brought home in small batches. Cooked camp food remains excluded from normal gather, chest and on-sight pickup loops until a meal or exact MrBeast request needs it. Raw staging is capped to a small part of bag capacity. Reclaiming raw stock also requires cooking to be enabled and compatible with the current fire queue, preventing an incompatible-food pickup/drop cycle.

Both bag drops and camp stock capture use receipts. Local stockpile markers help a script reload recognize still-loaded items that it previously deposited. They are not server persistence. Unconfirmed operations are reported; destroyed/streamed-out items are not claimed as available. Legacy storage remains readable and reclaimable. Current normal/storm reserve targets are 8/20, measured across actual supplies rather than a bag-filling carry target.

## Do dropped items despawn after a timer?

No general timed-despawn rule was found in the inspected exported paths for PlayerInventory drops, DropService resource loot, MakeFire cooked drops, AssetsManager drop-model creation, or ItemCollect. `misc.dropProtectTime` and `lockedFor_<owner>` are protection/ownership timing, not a deletion deadline. `spitMeatDelay` delays creation of a cooked drop; it is not its lifetime. The 0.75-second destruction in MrbeastQuest is cleanup after accepted contribution, not expiration of ordinary stock.

This does **not** establish that items never disappear. Pickup consumes/removes them, quest/build intake can consume them, a round/map reset removes round-world state, and missing authoritative scripts could contain other cleanup. The exports do not provide a defensible universal lifetime in seconds, minutes or days. Ground stockpiles are for the active round, with availability checked again before use.

## Night damage and hover recovery

The reported screenshots show substantial health loss while hunger remains high. That alone does not identify the damage source. The previous automation stayed anchored at a single low-hover location after damage, and the scheduler blocked ground evade/combat movement while hovered. It could also infer safety from vertical separation even where the game did not honor it.

The new hover guard runs independently every 0.15 seconds, including while a native food or fuel receipt is yielding. It evaluates horizontal clearance against loaded hostile positions, their movement, native attack reach and the larger Shadow margin. It checks dry ground, unlocked-border limits, and a character-sized collision volume. A threat approaching the current hover causes lateral relocation. Height is never increased automatically.

Unexplained damage at a position without a nearby detected threat lowers the hover first. Repeated unexplained hits, a severe hit, or critical health suspend hover for the rest of that night and request a checked ground landing. If landing is still unsafe, the guard keeps checking/repositioning rather than freezing an anchored player. The suspension resets at dawn. Stop, death, character replacement and shutdown restore the script-owned anchor state. No server health, damage or debuff attribute is falsified.

Night hovering requires the optional Pause Routine Work at Night setting. Turning that pause off permits routine night work and releases its hover. With the pause on, valid interaction holds finish before the ordinary night handoff; genuine survival emergencies can still interrupt. Native cooked-meal collection can operate while hovered; a world-drop meal or stockpile service uses a checked landing when necessary.

Full authoritative enemy/anti-hover logic is not present in the exports. This is a reactive survival change, not an invulnerability guarantee. Unknown damage sources, server corrections and special attacks remain live-test concerns.

## Passive food animals and MrBeast requests

A dedicated on-sight food hunt completes one passive animal, then yields the targeting mode and briefly cools down. Survival, fire maintenance and MrBeast requests/rewards retain priority. It does not interrupt a progressing ordinary action merely because another animal appeared.

Mob lookup now supports native ID attributes, configuration IDs, names, display names and model aliases. Recognized chicken/crab names remain eligible when their config lookup is missing; unrecognized creatures are not invented as food targets. Exact material/quest hunts keep their requested yields rather than being replaced by the on-sight mode.

The native MeleeClient first queries a **3D overlap sphere**, then tests horizontal reach and facing. A stance that passes only a horizontal-distance check can miss a short chicken/crab before the later test runs. Passive approaches now account for body height/bounds when choosing horizontal attack distance. Hunting favors a working melee tool over an unreliable ranged lock where a melee option exists. Native windup, cooldown, hit window, line of sight and damage receipts remain in control; no fabricated damage call is added.

Quest pushes remain revision-aware. Background quest refresh runs on a 0.75-second cadence, uses the existing bounded fetch, retains an active request after a failed fetch, and retries it. Failed goal backoffs expire; the request remains eligible until its native revision/item/quantity changes. Requested craft output is still produced through its native recipe, and partial owned contributions can be deposited before collecting the remainder. A changed request takes priority over a pinned optional upgrade at the next action boundary.

Routine action delay is reset to zero. The current task keeps running while it progresses; a stalled daytime task yields to queued work after seven seconds. Native holds, animations, cooldowns, unavailable/unsafe targets and network receipts still require their real time. The script does not pretend that an unavailable target has been completed just to avoid showing a wait state.

## Categories and exploration border

| Page | Controls |
| --- | --- |
| Main | Master and long-run preset |
| Survival | Night pause/hover and Shadow avoidance |
| Combat | Defence, attack input, aura, hunting and passive food animals |
| Food | Eating thresholds, cooking, cooked stock targets, meal/cook selections and water collection |
| Inventory | Bag upgrades, capacity, camp unloading, submission and legacy storage reclaim |
| Gather | Resource loops, drop selection and all-material stockpiling |
| Camp | Fuel, construction, camp upgrades and free-build structures |
| Craft | Tools/armour, recipe progression and furnace processing |
| Quests | MrBeast requests and choice rewards |
| Rewards | Daily/weekly/playtime/daily-quest claims and code redemption |
| Explore | Chests, interaction padding, puzzles, artifacts, clues, boat preparation/escape, travel and border setting |
| Fishing | Rod automation |
| Rounds | Replay/round controls |
| ESP | Categorized world markers |
| Status | Live display and status-only indicators |
| Settings | Session/config, movement, watchdog and diagnostics |

The saved **Allow Exploration Outside Unlocked Border** option affects only chest, puzzle, artifact and selected-travel target checks. Readiness probes carry the same temporary scope as execution. Explicit combat, hunting, camp and night-shelter checks keep their border limit. It does not remove a server wall, stop border damage or authorize an unsafe landing. The default remains inside-border exploration.

## Validation

All **547 checks across 30 suites pass**, and the complete script compiles with Roblox Luau. Tests execute production helpers with simulated native inventories, delayed receipts, world drops, native-style tool data and hostile movement. They cover food-bag recovery, one-meal gating across stacks, legacy storage migration, spare-tool unloading, current-recipe retention, native food animation timing, short-animal overlap reach, passive aliases/priorities, quest retry, scoped border checks, category placement, optional night pause and reactive hover/ground recovery. Other games' regression suites and whole-file Roblox Luau compilation are included. No live executor session or long-duration AFK soak test was available.

## Proactive ground evasion and quest delivery follow-up

The Combat page now separates the broad hostile scan (180 studs by default, adjustable from 40 to 500) from the near avoidance buffer. The bot projects current replicated horizontal enemy velocity over 1.25 seconds and measures closest approach across that interval. A closing hostile can therefore trigger evasion before contact or a health-loss receipt. Missing mob config no longer silently removes a living non-player Entity from threat detection; known passive animals and inactive daytime Shadow retain their classification.

Escape searches dry in-border landing points at 24/40/64/96/144 studs over sixteen directions, excludes predicted occupied positions and keeps a two-second caution window before reengaging an incoming attacker. Teleport dodge validates its destination without requiring an unobstructed walking segment; walk/tween dodge keeps its route check. Threat movement is an estimate from loaded replicated actors, not unseen server state or immunity.

Inventory now has a dedicated duplicate-tool cleanup toggle and job. It keeps one torch and one best matching working tool, reserves exact quest/active-recipe quantities, and drops only unused copies at a checked camp point. Torches are excluded from general melee weapon selection. Current quest supplies are also reserved from routine cooking, smelting, direct recipes, station deposits and whole-recipe construction; critical fire maintenance remains a survival exception.

[Mrbeast_Quest_Audit.md](Mrbeast_Quest_Audit.md) documents the native delivery/reward contracts, cloud-config boundaries, revision/acceptance checks, live quest catalogue and receipt tests.
