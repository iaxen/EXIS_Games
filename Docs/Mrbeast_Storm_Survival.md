# MrBeast survival and task queue audit

This update follows the exported native modules and the reported Day 5 swarm. ZombieRush map input, grounded turret combat and the shared Fuzzotopia design were delivered in the preceding merged change.

## Interaction and priority conflicts

| Issue | Change |
| --- | --- |
| Chest opening ends short | Hold the live prompt duration plus configurable padding, default 1.5 seconds. A 3.5-second prompt now receives 5 seconds before receipt grace. Early Triggered events cannot shorten it. Ordinary pickups retain their own timing. |
| Short food animals cannot be hit | Native melee uses horizontal distance; the old 3D test could reject a small chicken. Match native horizontal reach with a separate vertical limit. |
| Crowds reject every attack stance | Permit one native retaliatory hit from current range and sight, then kite. Preserve weapon cooldown and active-strike retreat. No fabricated damage. |
| Ranged weapon fails to fire | Wait for the native Aim target, choose an ammo-capable weapon, and use a single native input path. The Attack toggle uses the mobile button signal where supported, otherwise Tool input. |
| Routine jobs interrupt tasks | Queue routine work behind the current action. Daytime work yields after seven seconds without inventory, movement or receipt progress. Valid holds retain their full duration. Survival emergencies can interrupt. Progressing material objectives remain selected across steps. |
| Network reads freeze work | Bound configuration/chest/native RemoteFunction reads to 6.5 seconds locally. A timeout is not success. Cancelling the local wait cannot undo a request already received by the server. |
| Shadow stops morning work | Central threat classification treats Shadow as hostile only at night. Its daytime model no longer vetoes resources or routes. |
| Raw stock hides cooked shortages | Count raw/cooked separately; reclaim raw for cooking until the cooked target is met. Never eat uncooked food, including uncookable fruit. |
| Full bags loop indefinitely | Use native whole-stack storage with inventory receipts. Protect equipment, direct ingredients and carried cooked rations. Overflow goes beside storage or its planned camp site, outside intake zones; reclaim needed stock later. |
| Craftable structures use the wrong service | BuildingStation/FreeBuild have separate stock and placement from legacy BuildBuilding/Furnace. Prioritize storage/furnace, validate native template bounds, overlap and ground, then confirm placement. This supersedes the earlier audit's missing free-build support. |
| Footprints confused with plane clues | Native footprints lead to their owning chest. Read loaded artifact hint text separately; preserve the artifact's native five-second pickup hold. |

## Survival behavior

The survival-settings migration enables food/cooking, camp upgrades, quests/rewards, base preparation, artifacts/chests, footprint following, all-material stockpiling, code scanning and shelter. Escape stays off. The long-run preset prepares the boat without automatically leaving.

On-sight food hunting has its own toggle. Cooked reserve defaults to 8, rises to 20 on days 5–7 of each seven-day cycle, and preserves 3 carried meals. These configurable targets are not proof of sufficient food for every live storm duration. Actual storm state blocks cooking assumptions. A short gap between hunts lets cooking and deliveries run. Poll MrBeast's current quest every two seconds; prioritize deliveries and equipment rewards over optional upgrades.

Stockpiling includes loaded crystals and other materials without current recipe demand. Skip inferior equipment rejected by native collection rules. Use beach camp storage/planned storage for bulk. Unloaded or unreachable items are not claimed as collected.

Night hover uses the previous fixed 8-stud height by default, adjustable from 4–12 studs. Saved high settings reset to 8 once. Automatic altitude increases and daytime emergency flight have been removed after reports of damage at high altitude. Cooked meals and native refueling remain available while hovering; stopping automation restores the original anchor state. Ground threats still use combat/evasion. Neither low hover nor client anchoring guarantees immunity.

MrBeast requests now take priority over pinned optional upgrades, routine food hunting, cooking and storage work at action boundaries. Emergency survival retains priority. Quest-only mode also enables material planning. Exact requested hunting yields remain active even when another objective was selected, and on-sight food mode cannot replace a material hunt. Requested craftable outputs get a native recipe goal and are delivered before crafting further output. Partial-delivery readiness now matches its execution path instead of repeatedly reporting ready without depositing. Quest fetches have a bounded read and can retry after a timeout.

Automatic code discovery reads native config lists and keyed reward records, normalizes/deduplicates entries, preserves saved claims and uses 2.2-second request spacing. It skips servers without the redemption service. Manual input is supplementary. The exported server's private code set has no client enumeration API; no guessed active codes are embedded. The official game description checked for this update supplied no verifiable code.

## Verification and limits

Run the Lua files under Tests/MrbeastIslandEscape, Tests/ZombieRushSurvival, Tests/UI and Tests/Storage from the repository root. Lua 5.3+ or texlua runs the extracted-production-helper tests and whole-module compilation checks.

New checks cover padded chest/artifact holds, native targeting/input/cooldowns, short-animal reach, crowd retaliation, storage receipts/reclaim, structure placement, crystal gathering, footprints/hints, cooked reserves, queue handoff, objective persistence, daytime Shadow, fixed low-hover damage/landing/cleanup and bounded reads.

No live Roblox session or 500-day soak test was performed. Full server enemy AI is absent from the export; named attack-animation phases are a heuristic. Native input support, server corrections, physics, latency, unloaded regions and future content still require live verification. Invincibility and completion of every quest are not established.
