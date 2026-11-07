# MrBeast quests, rewards and duplicate tools

Audited both supplied archives: `mr beast island escape files.zip` and `MrbeastIslandEscapeIngameFiles.zip`. The important replicated modules are `Engine.Service.MrbeastQuest`, `Engine.Service.MrbeastChoice`, `Engine.Service.PlayerInventory`, `Engine.Service.CraftItems`, `Engine.Service.ArmourService`, `Module.Service.CloudConfig`, the MrbeastQuest client and the choice UI client. The exported server-function bodies are decompiled and some control flow is malformed; their available validation and call contracts were checked against the client consumers instead of treating the export as runnable authoritative server code.

## What the quest actually is

MrBeast maintains a current **delivery request per player**, identified by quest index, selected alternate and revision. Completion is not a dialogue click or a visit to the NPC. The bot must obtain the requested item and quantity, present eligible supplies and submit that current revision. Acceptance advances the request and offers a separately selected reward.

| Native data | Meaning |
| --- | --- |
| `Config.mrbeastQuestList.list` | Quest indices, requirement alternatives, tutorial-only flag and preferred fixed reward |
| `require` | `ItemNamexCount` entries separated by `|`; the server selects **one alternate**, not all entries together; absent quantity defaults to one |
| `getQuestRequirement(index, alt)` | Resolves the selected alternate into the actual item ID and count |
| `MrbeastQuestIndex`, `MrbeastQuestAlt`, `MrbeastQuestRevision` | Replicated player attributes describing the request revision |
| `Config.mrbeastQuestTiming.list` | Day/appearance descriptions and eligible quest-index reset ranges |
| `newbieOnly`, TutorialData and `misc.isMrbeastQuestLoop` | Native tutorial filtering and whether completed quest ranges can be reassigned |
| `Config.mrbeastQuestPrior.list` | Reward pools, weights and fallback/edge pools |

**Neither ZIP contains the populated cloud quest, timing or reward-pool tables.** `Config` calls `CloudConfig.getAll()`, which retrieves configuration through `getAllConfigFunction`; the backing data is server cloud configuration. The archives contain the consumer schema and remote handlers. They do not justify publishing a fixed list of quest names, counts, days or rewards.

Automation therefore reads the current server's real config and request. The Quests page shows the selected alternate, required quantity, carried count, eligible owned drops, missing quantity, preferred reward and actual pending offered rewards. **Copy Live Quests and Reward Pools** exports the live configured list, timings and pools for inspection; it does not choose or replace the player's assigned quest.

## Exact completion conditions

The exported `serverSubmitQuest` checks:

1. The submitted revision is a number equal to the player's current revision.
2. The model list is a table, the player has an active quest and its selected item exists.
3. Each submitted contribution is a unique Model under Workspace, is not `collecting`, belongs to the player through `ownerName`, and resolves to the requested item ID.
4. The character's **equipped matching Tool** contributes its stack count. Items sitting only in Backpack, or additional separate unequipped tools, do not contribute to that held stack.
5. Eligible model count plus equipped stack count must meet the requirement. A world model contributes one unit even if it has an unrelated `count` attribute.

The native client normally checks the NPC's SuckArea before submitting. The inspected server function validates owned models without a separate distance check in that body. Automation still travels to the NPC, equips and verifies the matching stack, and stages partial or separate non-stacking items there. It preserves partial owned drops for the remaining delivery.

Accepted contributions are consumed; accepted drop models receive `collecting` and a 0.75-second effect cleanup. The server records the completed quest, advances/revises the request, fires `questSubmittedRemote`, then offers reward choices. That cleanup is not an ordinary dropped-item despawn timer.

## Corrections to the automation

| Failure or conflict | Resulting behavior |
| --- | --- |
| Any revision/index change was treated as completion | Only `questSubmittedRemote` confirms acceptance; day changes, nil snapshots and a changed alternate cannot fabricate success |
| Request captured before travel could become stale | Recheck index, alternate and revision during delivery and immediately before submission |
| Backpack stock counted without verifying equip | Verify the matching Tool is actually under the character before sending |
| A failed attempt could clear the current cache | Preserve the request and use a short submission lease; refresh and retry unconfirmed attempts without immediate duplicate sends |
| A late acknowledgement arrived after local preemption | Reconcile the existing lease before another submission |
| Old scene callback remained bound to the same remote | Rebind for the current scene; obsolete reads cannot overwrite a newer push or clear a newer fetch token |
| NPC streamed out | Preserve the current request and reserved supplies; wait for its delivery area to return |
| Routine processing or construction consumed requested stock | Reserve exact quest quantities from optional consumption; allow critical extinguished-fire maintenance first |
| Quest gathering disappeared when another goal was selected | Maintain current request needs in the shared needed-material set, alongside crafting requirements |

Quest material/craft goals already rank ahead of optional upgrade/gather/explore work, while urgent evasion, food recovery and fire remain higher priority. Required animal yields remain exact, and requested craft output is produced through native recipe/submission adapters. A failed or unavailable source does not mark the quest finished; short goal backoffs expire and the request is checked again. Protected native interactions and survival retain their existing task ownership rules.

## How rewards work

`MrbeastChoice.offerChoices(player, completedQuestIndex)` first considers the quest's preferred fixed reward when it would improve that player's relevant family. Otherwise the server generates choices from configured weighted pools using native owned/equipped levels, with edge/fallback pools when needed. Those choices enter a per-player queue.

The bot chooses one item from the **actual received queue head**, using `playerSelectRemote(index)`. Selection zero skips the reward and is not a claim. Native bag rewards call `upgradeBag`; armour can equip through ArmourService when enabled; other rewards call `addItemById`. Reward selection does not grant every item in a pool.

The selector prioritizes needed healing under critical conditions, useful bag/armour/weapon upgrades, then needed materials. Already-held torches score below useful upgrades. Bag-only config entries remain valid candidates. Equipped armour state is initially read through the native read function and kept current by `equipChangedRemote`.

A claim is confirmed by the selected item arriving, the selected bag ID changing, the selected armour equip change, an explicit close, or the next native queue head. An unrelated inventory change is not confirmation. If the native choice protocol supplies no observable receipt, the UI reports the claim as unconfirmed instead of fabricating it.

## Duplicate tools and preventive evasion

Inventory's duplicate-tool job keeps **one torch**, one best tool per ordinary native family, and independent identities for non-swapping special tools. Exact quest and active-recipe quantities stay reserved. It drops unused copies at a checked camp point instead of waiting for a full bag, and never treats a torch as a general melee weapon. A quest can still legitimately consume an item that it requires.

The broad hostile scan defaults to 180 studs and supports 40–500 in Combat settings. It is distinct from the near avoidance buffer. Closest approach is forecast over 1.25 seconds using replicated velocity. Unknown living non-player Entities remain visible to the threat detector; known passive animals and daytime Shadow remain excluded from hostile avoidance. Incoming threats can preempt gathering before any damage occurs. Escape checks dry in-border landing positions against predicted enemy positions, then preserves a brief caution window before reengagement.

## Validation

All **547 checks across 30 suites pass**, full-file Roblox Luau compilation passes and `git diff --check` passes. New production-helper tests cover exact native submission, equipped/owned contributions, stale and nil quest snapshots, late receipts, retries, scene/streaming changes, live metadata, selected reward receipts, duplicate torches, requested-material protection, unknown creatures and pre-damage evasion. Existing Steal an Egg, Zombie Rush, UI and storage tests also pass.

No live Roblox executor session or long-duration survival run was available. Predicted movement and loaded client state cannot guarantee zero damage, reveal unstreamed enemies or prove a particular survival-day target.
