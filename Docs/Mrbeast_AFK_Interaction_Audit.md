# MrBeast AFK interaction audit

Scope: the supplied `MrbeastIslandEscapeIngameFiles.zip` export and the MrBeast module after PR #22. Relevant source was recovered from the Roblox binary chunks despite the exported files having `.txt` extensions. This is a source review and deterministic simulation, not a live Roblox certification. Cloud configuration and server-only services absent from the export cannot be fully validated offline.

## Verified chest sequence and timing

`ChestClient` creates a ProximityPrompt on `UpperTorso` for humanoid chests, otherwise `PrimaryPart`. Its hold is:

`H = chest.openSec * (1 - ProfessionService.client.getActiveStats().chestOpenReduceRate)`

The live prompt's HoldDuration is authoritative. Its Triggered callback calls `ChestService.client.requestOpen(chest)`, which fires `RequestOpenEvent`. The server checks map locks and distance from HumanoidRootPart to the chest PrimaryPart (at most `2 * openDistance`, default distance 10). It marks the chest opened per UserId and sends `RemoteEvent` **before** the loot exists. It waits for the animation's Length to load, waits `0.9 * Length`, then invokes DropService.

Therefore an opened receipt is not a loot receipt. Time to loot is approximately:

`H + request travel/processing time + animation-load wait + 0.9 * animation Length + drop replication time`

For an illustrative 4-second configured hold, 25% class reduction, and 2-second loaded animation, the local hold and server animation alone take `4 * 0.75 + 2 * 0.9 = 4.8 seconds`. These numbers are an example, not measured configuration for a particular chest. The script's three-second acceptance timeout starts **after** the hold; it was not itself proof that every long chest hold was too short.

The old helper released E exactly at HoldDuration and could miss a later-frame Triggered dispatch. It could then force a zero-duration prompt call without a receipt. The scheduler also allowed routine work to interrupt holds: resumed chest rank 4.2 versus craft 3.5, rewards 3.6 and unload 3.9/4.05. A routine interrupt every interval shorter than H prevents completion indefinitely, even when every individual job looks valid.

### Changes

- Hold E through the native duration and a bounded receipt grace (up to 0.35 seconds, stopping as soon as a receipt arrives). Never force a zero-duration prompt trigger.
- Fall back to the verified native open/collect call only after an uninterrupted full hold when synthetic E dispatch fails. Disabled prompts and survival interruptions cannot use this fallback.
- Protect the current hold/chest batch from routine preemption. Jobs ranked below 3.5 (danger, defence, eating, fire and urgent food) can still interrupt. Ownership expires and is cleared on completion/error.
- Approach the actual activation anchor; keep the configured range margin.
- Keep the accepted chest and remaining loot across interruption or a full-bag trip. Avoid a second open request after acceptance.
- Bound an unproductive wait to 15 seconds; extend it for an observed longer animation within the configured job timeout. Defer an unresolved chest for five seconds so other work can run. A timeout never means loot was collected.

## Other confirmed AFK conflicts

| Conflict | Source evidence / calculation | Handling |
|---|---|---|
| Leaving after the first chest item | `collectModel` submitted the current objective after every chest pickup, causing travel to a different destination mid-batch. | Chest loot bypasses per-item objective submission; ordinary task gathering retains immediate submission. Unload takes over when full. |
| Prompt created but not ready | `pickUpClient` disables the pickup prompt, waits 0.5 seconds, then sets its collection radius and connects Triggered. | A disabled prompt reports not ready; it cannot fall through to a premature remote request. |
| Rejected inferior equipment | `ItemCollect` rejects non-upgrade bags by level and `useSwapUpgrade` tools by type/level. The old chest loop kept retrying such drops. | Filter those known rejections using the native level rules. Leave these items on the ground. |
| Successful armour mistaken for failed collection | With `misc.useArmourCollectEquip`, ItemCollect equips armour and destroys its drop without creating a backpack Tool. | Accept removal as the auto-equip receipt; allow this path when the material bag is full. This is not a general replacement for inventory confirmation. |
| No physical loot | DropService can give currency directly, spawn creatures, or select no item entry. | An observed completed chest animation plus a one-second quiet window can finish an empty physical batch. Unknown animation state remains retryable. |
| Wrong station takes stash | MakeFire and station intake zones can consume dropped items automatically; CraftingStation scans every 0.5 seconds and destroys consumed drop models 0.75 seconds later. | Preserve existing intake-zone clearance and use inventory/station receipts rather than immediate object disappearance as a crafting receipt. |
| Holding unsubmitable crafting ingredients | Direct CraftItems requires all ingredients; CraftingStation uses its own shared material stock. | Preserve needed direct-craft ingredients and existing station-specific demand/deposit logic. Blanket empty-bag logic would conflict with direct crafting. |

## Remaining limits and further AFK risks

- An unknown/unloaded animation has no server “all loot finished” event. Existing recovery of an already-open empty chest uses a heuristic; complete certainty is unavailable from the exported API. Very late replication remains possible. No blanket promise of flawless AFK is justified.
- An InvokeServer call can yield for network/server reasons. `ChestService.isOpened`, `isLocked` and configuration reads are synchronous in this module. Local job deadlines cannot interrupt an already-yielding call. A future bounded asynchronous read adapter would be needed for that failure mode.
- Inferior automatically equipped armour can still be rejected server-side based on equipped armour state; the new filter covers bags/swap tools, not every armour rejection. Such unresolved loot is deferred, not falsely collected.
- Standard camp `_Construct` blueprints use BuildBuilding and its partial material submissions. BuildingStation/free-build items use a **different** catalog, material stock and placement flow. This patch does not implement automatic free-build structure placement. Missing `_Construct` blueprints must not be assumed to be built or craftable through BuildBuilding.
- Fire-level gates, rain/fire outages, missing tools, locked map sectors, unsafe/unreachable routes, disabled selections, and full bags containing protected ingredients can legitimately leave no ready job. Offline checks verify fallbacks but cannot guarantee that every live state has a productive route.
- Chest loot matching currently uses owned drops within 16 studs. Native scatter radius is `3 + 1.5 * floor((dropIndex - 1) / 6)` studs, so unusually large batches can exceed this radius. Avoid claiming complete coverage for arbitrary future drop tables.
- Fresh runtime config may differ from the saved export. The live prompt and current server config remain authoritative; do not hard-code costs from the earlier written guide.

## Validation

Tests execute extracted production functions with simulated clock, delayed prompt events, server receipts, inventory changes, interrupts, animation duration, bag trips and rejected pickups. They also compile the entire Lua module. They do not simulate the full Roblox engine, actual executor input dispatch, physics or network behavior.
