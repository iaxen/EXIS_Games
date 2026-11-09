# Categories, solo progression, active recovery and two-storey house v12

This update follows the requested ten-category menu and the supplied square/two-storey sketch. It builds on merged PR58, retaining the optional TP-only map sweep and native bandage revival.

## Menu ownership

The sidebar order is **MAIN, EXPLORER, DEPENDER, GATHERER, BUILDER (CRAFTER), SURVIVAL, QUEST, ESP, SETTINGS, DIAGNOSTIC**. The requested DEPENDER spelling is the category label; the saved Defender role key remains compatible.

Main owns the master, long-run preset, automatic solo option, role summary and Stop All. Each role switch lives with that role's detailed controls. Explorer owns map sweeps, expeditions, chests, artifacts, travel and unlock objectives. Depender owns combat, tree-perch policy and teammate rescue. Gatherer owns mining, food hunting, bags, material collection/sorting, storage reclaim and gun donations. Builder owns stations, recipes, tools, furnace, campfire fuel and build presets. Survival owns meals, thresholds, storms, Shadow and refuge. Quest owns requests/rewards/codes. ESP owns all markers. Settings owns session/round behavior, movement and general overrides.

Live Run, its optional external-status switch, queue priority information, collection troubleshooting and full logs are under Diagnostic. Stop-category actions live in their own categories. There is one direct toggle per feature, including one Builder wall switch; group switches remain with their category. Sidebar buttons wrap the long crafter label and remain scrollable on mobile. Saved feature keys and selection lists are retained.

## Productive recovery

The existing 85% recovery hysteresis remains a restriction on renewed hostile fights. It no longer blanket-blocks stations, wall work, gathering, quest acquisition, chests, artifacts or map exploration. Those jobs still perform their normal safe-destination, terrain, weather and resource checks.

Recovery relocation is ready only while the player's current position is unsafe. It first tries a safe alternative for the interrupted resource/drop task, then uses the existing checked refuge/camp fallback. Once safe, the player is not repeatedly recalled to base just because HP has not reached 85%. Critical meals still have priority; the recovery latch by itself no longer labels an otherwise healthy-enough player as critically hungry.

## Ordered solo progression

Automatic Solo is on by default and can be disabled on Main for custom task choices. With one player and normal master automation active, it enables the four role tasks plus survival essentials once on entry. It does not enable TP-only mode, paid actions, gun sharing or escape. On leaving solo mode it restores the flags it automatically changed, while retaining tasks the user manually disabled. The separate TP-only mode continues to exclude all other work.

Solo ranks are deterministic before ordinary team-role fairness is considered:

| Order | Ready work |
|---|---|
| 1 | Threat escape, critical eating, checked recovery, emergency conditions |
| 2 | Bandage rescue where applicable, armour/bag pickups, ready quest rewards and deliveries |
| 3 | Full-bag processing and essential camp-station construction |
| 4 | Active quest acquisition, larger bags, tool/armour progression, useful gear chests |
| 5 | Campfire upgrades, smelting/result collection and cooked-food reserves |
| 6 | Core materials, collection, sorting and travel supplies |
| 7 | Artifacts, chests, expeditions and bounded chunk exploration |
| 8 | House/perimeter crafting, floors, stairs, walls and roof |
| 9 | Extra stockpiles, optional hunts and fallback patrol |

Unavailable, unsafe or unconfirmed steps yield through the existing readiness/backoff system. A waited optional task cannot leap ahead of stations or quest delivery in solo mode. Basic camp reserves are checked against native item IDs: 36 wood, 24 stone and 16 iron ore when those items are available. Once supplied, generic stockpiling yields to exploration/building rather than gathering forever. Chunk exploration retains its twelve-arrival burst and gets a twenty-second gap before its next routine solo turn, allowing the Builder to progress. These are scheduling priorities, not a promise that the server offers every station or objective.

## Hostile combat and tree perches

Hostile attack input requires an iron-tier-or-better spear or a usable gun. Weapon selection, ordinary combat, counter windows, auto attack, objective engagements and the final strike gate use that policy. Empty guns are not treated as usable. Axes/weaker tools remain usable for resources and passive food animals. Shadow retains its separate native torch-hit requirement. Existing damage-budget, low-health, cooldown, range, reload/input and hit-receipt checks remain in force.

With a gun, a nearby tree can supply an elevated fighting position. The bounded search checks at most six trees and five probes per tree, requiring a collidable, reasonably level surface, supported avatar footing, border allowance and an accepted native-range/line-of-sight stance. The player teleports onto that checked surface through the normal movement code. Cooldown kiting retains a valid perch instead of immediately dropping back onto the ground. Destroyed supports, invalid range/sight or damage invalidate the safe hold. A tree is not considered invulnerable cover; when no suitable perch exists, existing checked ranged positioning/escape behavior applies.

## Square two-storey preset

Builder can switch between **Square Two-Storey House** (the new default) and the existing **Classic Three-Layer Wall**. The house interprets the clarified sketch as two storeys, with a lower shell around camp stations, a second-floor platform, upper walls, a roof and a slope staircase along one side. It is not two concentric square fences.

Wall, floor and slope pieces are resolved from the live native free-build/crafting catalogues. Recipe materials, stock pools, craft events, bounding boxes and pivot offsets remain native. There are no invented floor/stair item IDs. Missing floor/slope recipes, unavailable geometry, incompatible native grids or insufficient dry square space produce an explicit blocked reason.

The square fits the station footprint with room for an entrance and staircase. Completed camp-station bounding boxes determine room clearance; escape-boat geometry is excluded. Storey height starts at two native wall courses and increases if needed to clear station tops and align the native slope rise. Floor and wall grids are aligned before planning. The square is clamped inside loaded beach bounds, and each actual footprint still requires dry, inside-beach/border corners. The intermediate floor leaves a stair opening; the roof covers the full square.

The progression is **lower walls → slope staircase → second floor → upper walls → roof**. Raised wall courses and consecutive slopes need their preceding support receipts. Previous stages must exist before higher stages proceed. Placement is attempted from checked ground, avoiding a teleport onto the still-unbuilt platform. Native item-count increases confirm crafting; both a replicated placed model and inventory decrease confirm placement. Destroyed lower pieces are repaired before later work. Conflicting unrelated structures remain blocked and are rechecked after thirty seconds; coverage gaps are reported rather than called a complete enclosure.

An indexed cache avoids rescanning every placed model for every planned piece. Planned square-corner seams may overlap each other, but not unrelated structures. The fort-specific overlap check examines all returned bounding-box parts: the supplied native helper can stop after the first ignored model, which is insufficient when both a valid seam and an unrelated obstruction are present.

## Validation and limits

584 deterministic production-helper checks pass across sixteen suites, including complete module compilation and `git diff --check`. New tests execute the complete menu construction in a mock UI and verify exact category order, unique direct controls and feature ownership; check productive recovery and safe alternative/fallback behavior; verify solo ordering, reserve limits, role restoration and bounded explorer turns; enforce weapon policy and supported tree perches; and exercise native house recipe selection, square/grid coverage, stair openings, stage/support receipts, repairs, ground-side platform placement and strict overlap handling.

No live Roblox session was available for this change. The current server's floor/slope catalogue, model orientation/collision shape, actual tree surfaces, station layout and available beach square remain live checks. In particular, slope rise/run come from native bounding geometry; the real slope's orientation and walkability must be verified in-game. Adapters certify control flow, not FPS, long-run survival, gun accuracy or a fully built live house. Diagnostics v12 reports the active priority mode, recovery policy, hostile-weapon availability and build stage/blockage.
