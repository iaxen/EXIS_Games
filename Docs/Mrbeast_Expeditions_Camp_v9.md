# MrBeast Explorer expeditions, shared map and camp infrastructure — v9

## Evidence from the supplied run

Reviewed `diagnostic_20261108_223749_126670_report.txt`. It records v8, all four roles selected, day 8, HP 0 and one artifact confirmed collected. The crafting table, furnace, storage and tent remained construction blueprints. Only two construction-finished messages occur, with no greatWall action. The wall planner expanded to 252 connected beach tiles and 2,880 slots; wallRegion averaged 31.57 ms and wallSite 45.97 ms, including nested elapsed time. These timings are not independent CPU totals.

The log includes 233 deferred required-fight messages, 250 unlock job starts, 697 evade starts and 320 recovery starts. Its final damage-budget decision rejects a large tentacle with weak close-range gear. Repeatedly retrying that fight cannot replace building the stations needed for better equipment. The final old furnace-prerequisite status also does not mean the newly visible furnace blueprint should be ignored.

No recent unhandled error is listed. Four optional daily / weekly / playtime modules are unavailable and are already skipped. The report does not establish a single cause for all 125 observed damage events or the final death.

## Explorer

Two expedition switches are available under **Explorer • Tribal / Pirate Expeditions**. They use the existing chest and puzzle flags and remain compatible with combined roles.

- Tribal: explicitly activate the native `原始部落头骨` skull through PuzzlePropService, confirm its solve receipt, then open the tribal chest and collect eligible native loot. A protected refuge skull remains untouched. Missing lock metadata is reported rather than replaced with a guessed unlock.
- Pirate ship: identify the native `章鱼海盗船` tile from lock metadata or loaded tile geometry. Its chest can be named `Kidnapped`; the route does not depend on an English chest-name guess. Locked ship chests focus the normal required-mob / puzzle unlock job. Actual unlock is still confirmed before opening.
- Loot keeps the existing upgrade / ownership / bag rules. Completion means the native chest and eligible loot were confirmed, not that a random reward pool is guaranteed to drop a particular item.
- Unsupported or unsafe fights back off progressively, allowing gear and camp jobs to run instead of repeatedly requesting the same impossible encounter.

## Chunk exploration means registering the shared map

Explorer now teleports to one center per reachable chunk instead of sweeping five points inside an already visited chunk. It skips centers already visible in the native map snapshot. Revealed land is not added again as an unexplored frontier destination. Unrevealed frontier cells remain candidates for checked streaming and dry-floor validation.

After arrival, a fresh normal MapSyncService snapshot checks whether that location is server-visible. A landing without that receipt is logged as unconfirmed and deferred for another attempt. Arrival count and confirmed-map count are distinct. Explorer-only configurations prioritize available registration trips; combined Builder / Gatherer configurations retain infrastructure and material priorities, plus bounded exploration opportunities.

The Map artifact receives a strong preference because it enables the native shared viewing feature. The script never invokes reveal-all, writes map cells, fabricates visibility, teleports into unverified water, or removes world locks. Further coverage can still require the Map artifact, streaming or campfire / border progression. Team visibility remains the game's normal server behavior.

## Stations, campfire and walls

| Priority | Behavior |
| --- | --- |
| Immediate survival | Evasion, critical food and fire service retain priority |
| Essential infrastructure | Dedicated material / submission job builds campfire, crafting stations, furnace, storage and tent before optional chicken coops and ordinary expedition work; required free-build utility stations also get elevated priority |
| Station supplies | Builder / Gatherer material plans read native remaining blueprint requirements and account for carried, storage and nearby staged supplies |
| Campfire upgrades | A dedicated upgrade job continues the existing confirmed native wood / level path, with scheduling priority before another routine wall craft |
| Ready walls | An already-crafted wall places promptly; wall crafting also keeps its bounded scheduling opportunities |
| Wall region | Preserve the camp/station beach footprint and margin rather than flooding along the island's entire connected coast; disconnected / excluded stations remain visible in the uncovered count |

Routine crafting and smelting reserve the next essential station's carried materials. The dedicated station job can submit those materials directly. Optional crafts do not make Gatherer retain the station supplies it should stage, and ordinary gathering does not immediately reclaim those staged piles. Native station receipts, recipe requirements and safety checks remain enforced.

## Gatherer

Missing station resources receive a real first-pass selection before nearer unrelated resources. A harvest approach checks the nearest side first and returns after the first valid hit position, avoiding a complete 64-ray search for every approach. Native swing cooldowns and damage receipts are unchanged.

Overflow sorting separates wood, stone, iron, food, tools, gear and other materials. Each available group is drained before switching piles, reducing trips between interleaved stacks. Storage is still preferred when enabled, and surviving bag / quest / tool protections remain in place.

## Validation

527 checks pass across 16 deterministic production-helper suites, including complete module compilation. New cases cover station order and reserves, staged materials from another player, native skull solve / interruption / protection, explicit tribal and pirate chest targeting, locked-ship handoff, sorted groups, first-pass gathering, bounded coast expansion, one-teleport-per-chunk behavior, skipping native-visible centers and map-confirmed versus unconfirmed arrivals. `git diff --check` also passes.

No live Roblox client was available. Native skull effects, pirate combat, actual gear drops, construction receipts, shared map viewing on another account, wall coverage, FPS and unattended survival need a fresh in-game run. The audit panel identifies v9 so the next report can be distinguished from this v8 evidence.
