# MrBeast automation audit — 8 November 2026

This update responds to a live run that reached day 4, bag capacity 15, and then died. It uses the supplied diagnostics, extracted client/shared game sources, and the live MrBeast quest configuration supplied by the user. It does not certify live gameplay or server acceptance.

## Confirmed code blockers

| Evidence / trigger | Cause | Change |
| --- | --- | --- |
| Combat, food hunting and base sorting reported `NO SAFE DRY APPROACH`. | Actions asked for a 0.5-stud destination radius, but `motion.goals` generated offsets at least 1 stud away and rejected them. | Generate the center and positions inside the requested radius; finish the last step of imprecise walk arrivals. Logs include dry/safe candidate counts and radius. |
| Short weapons had no valid planned combat position. | The attack ring could fall inside `meleeClearance`, so the stance validator rejected every planned position. | Choose a reachable ring outside that clearance and inside native range; permit movement away from an existing unsafe proximity. |
| `Cooked Crab • READY` repeatedly occupied progression without crafting. | Placeholder/empty recipes could create craft goals; cooked foods were considered direct crafts. | Reject empty craft recipes and route cooked quest foods through existing hunting/cooking flows. |
| Station materials were deposited, then crafting stalled. | `submitGoal` only invoked the station while ingredients remained in the carried bag. | Allow a fully deposited recipe to craft from station stock with an empty bag. Respect native station synchronization and campfire-level requirements. |
| The log shows `EAT: PAUSED FOR AUTOATTACK`, with repeated unproductive attack jobs. | Auto-attack readiness used the wide guard radius instead of a valid immediate weapon stance; critical eating ranked below it. | Auto-attack requires a hittable current target and completed cooldown. Critical eating outranks routine combat; evasion still comes first. Combat readiness requires an actual planned stance or native-range counter. |
| One resource was collected and then immediately submitted. | The pickup success path submitted after each individual item. Unload/build/smelt jobs could become ready after a single item. | Batch pickups and ingredient collection. Delay routine sorting, optional construction and smelting until a batch is ready, the bag fills, or safe targets are exhausted. Essential fire/survival tasks may run sooner. |
| Stone/iron toggles could appear enabled without mining those resources. | Resource classification relied on English IDs; the live configuration uses names including 石头 and 铁矿. Needed-only mode could also suppress explicit mining toggles. | Recognize native Chinese IDs/display/drop names, honor explicit mining/chopping toggles, and rotate general harvesting from trees to stone to iron. |

## Requested behavior

| Task | Implemented behavior / receipt |
| --- | --- |
| Auto craft | Uses live recipes, station material stock, fire-level gates and native craft events. Confirms an output/bag change. Empty placeholder recipes never report ready. |
| Bag, then better gear | After capacity reaches 15, useful tool/armour upgrades rank ahead of larger bags and optional camp upgrades. Active quests and urgent survival retain priority. An old pinned optional upgrade cannot override a higher-ranked gear goal. |
| Wear crafted armour | Uses the same `ToolService.armourRemote(tool)` as `ArmourClient`; confirms the matching equipped-armour event. Already worn armour counts toward the upgrade ladder. |
| Bulk collect / sort | Field pickups and food supplies are collected in batches. At base, usable ingredients are submitted, eligible stacks are stored, and overflow is dropped in separate wood/mining/food/tools/gear/other sectors on checked ground. Keeps best working tools, one torch, quest reservations and required direct-craft ingredients and one pending wall/utility placement item. |
| Stone / iron / Elf Tree | Uses each resource's native `resourceId`, tool requirements and live drop table. Explicit mining/chopping flags override needed-only filtering. General stockpiling rotates resource types when available. Elf Tree follows the tree/axe resource path. |
| Hostiles / Treant | Enabled combat searches the configured hunt radius and camp threats, selects valid stances, uses native tool cycles and confirms damage. `Treant` uses ordinary hostile combat. Unsafe health, crowds and known strike windows still trigger retreat. |
| Shadow | Dedicated torch job. Only a native light-source melee tool can target Shadow. Success is a change in `TorchHits` toward `TorchHitsMax`, not damage to its invulnerable Humanoid. A missing torch becomes a craft goal when its native recipe is available. Low health and unsafe crowding still defer the fight. |
| Crab / chicken | Existing passive-food recognition and real native part-overlap checks are retained. The precise-approach fix removes the movement blocker. Food supply collection batches its pickups. |
| Build buildings | Active native `_Construct` blueprints use existing contribution receipts. Storage/furnace free-build utilities use the BuildingStation pipeline. Decorative structures are not automatically crafted just because they exist in a catalogue. |
| Smelt iron | Uses native furnace ingredient IDs, individual add-matter calls, inventory deductions and replicated ready output. Full-bag processing can submit batches before sorting leftovers. |
| Chests | Existing native prompt duration plus padding, opened receipt, delayed animation/loot tracking, full-bag trips and rejected-loot handling are retained. The shared approach fix benefits exact loot/base actions. |
| Night exploration | Optional enabled policy resumes routine exploration when the entity folder is loaded and no living loaded hostiles remain. Newly loaded/spawned hostiles restore the night pause. This does not claim that unstreamed enemies are dead. |
| Great Wall of EXI | Finds a native wooden wall recipe; reads the actual cost instead of imposing a fictional cost. Plans three parallel layers on loaded beach tile boundaries, omits internal shared edges and leaves an entrance. Checks dry support at the wall corners, unlocked border, slope and overlaps. Applies the template's pivot offset. Confirms both a placed model and inventory deduction; detects removed/destroyed segments for rebuilding. |
| Diagnostics | Adds station/torch/furnace/wall/loaded-mob audit information and precise movement rejection counts. Optional reward modules absent from the server skip their sync adapter. Unconfirmed MrBeast reward requests back off instead of continuously dominating the queue. |

## Native evidence

- `MeleeClient.onHitWindowTick` uses a part-overlap sphere, facing/range/line-of-sight tests and allows an otherwise invulnerable `Shadow` only for a light-source tool.
- `ClientToolBase` owns the tool cooldown, windup, hit window and recovery. `MobileBtnsClient` invokes the equipped tool's `Activate` method.
- `ShadowHealthBarClient` reads `TorchHits` and `TorchHitsMax` (default 3).
- `CraftingStation`, `CraftingCatalog` and `BuildingStationCatalog` use native catalogued recipes, station stock and campfire-level gates. `FreeBuild` accepts the configured `cnId` and placement frame.
- `ArmourClient` sends the actual armour Tool to `ToolService.armourRemote`; `ArmourService` publishes the equipped type/id change.
- `Furnace` uses the configured two ingredient IDs and result ID. Chest behavior remains covered in `Mrbeast_AFK_Interaction_Audit.md` and the existing regression suites.

## Validation and live limits

Validation completed: **311 mocked checks across 12 suites passed**, the complete module compiled, and `git diff --check` passed.

The regression suite executes extracted production adapters with simulated native geometry, delayed receipts, inventory changes, cooldowns, interrupts, failed requests and scene changes. It also compiles the complete module. It is not a Roblox physics, executor or network test.

The supplied report shows real blockers in the older run; it does not prove the new build fixed that live run. A new execution is required after merging. Existing running scripts do not automatically update.

Some server-only scripts and live configuration tables are absent from the export. Native server rules, recipes, map unlocks, missing tools, rain, terrain, streaming and available inventory remain authoritative. A wall recipe absent from the current catalogue is reported as blocked. Unloaded beach tiles cannot be enclosed yet; irregular terrain can leave skipped wall sites. The entrance and rejection of unsupported/water sites intentionally prevent a fully sealed perimeter. The wall planner does not promise an impenetrable defence or uninterrupted routes through every future map configuration.

If any action still fails, export diagnostics from the updated run. The useful evidence is the active job, precise movement candidate counts, station synchronization, live wall recipe, equipped torch/armour state and whether native damage/placement/inventory receipts arrived. No action is declared successful just because a remote request was sent.


## Follow-up: session 20261108_061511_149761

The new report confirms automation v1, synchronized crafting/building stations, a torch, bag capacity 15 and no recent script errors. The previous dry-approach blocker is absent. The character nevertheless died on day 3. These files are chunks/report data from the same session.

The report contains 103 `COMBAT → EVADE` interruptions and 9 `COMBAT → NIGHTHOLD` interruptions. Night-hold handoffs immediately restarted combat. Saved guard radius was 80, so distant hunts could continually interrupt food/progression. Incoming enemies with unknown animation names could also cancel every swing before its hit window. The report identified `木半墙`, exposing an unintended preference for the cheaper half-wall.

The follow-up separates native-contact/base defence from ordinary distant hunting. Ordinary hunts rank behind food, quests and gear. Immediately contacting attackers take targeting precedence over distant camp mobs, including entry into the top-eight stance search. A bounded native windup/receipt commitment permits a healthy, native-range counter against an unknown animation; actual strike phases, new damage, low health, fresh evade recovery and crowds still defer it. Combat/auto-attack respect the two-second evade recovery instead of instantly restarting. Healthy night shelter no longer preempts combat travel, and a queued shelter handoff is not displaced by a nonurgent hunt. Full wooden walls outrank half walls. Quest polling pauses while the character is dead. Diagnostics v2 distinguish attempted tool activations from confirmed damage receipts.

Validation: **320 mocked checks across all 12 MrBeast suites passed**, the complete module compiles, and `git diff --check` passes. New regressions reproduce the guard-radius, shelter handoff, unknown-animation counter, interruption-safety and full-wall selection cases. The uploaded saved settings were inspected without modification. This remains an offline validation; another live run is required to confirm hits, survival and productive progression under the server's actual population and latency.
