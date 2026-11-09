# Wall crafting and placement audit v10

## Evidence from the supplied run

`diagnostic_20261108_235345_729538_report.txt` reaches day 36 with three revivals and all four artifacts collected. Campfire, Chicken Coop, Crafting Table, Furnace, Storage and Tent are built. The wall planner finds 108 slots over four connected base tiles containing eight stations, but the log contains no GreatWall job start or wall-craft receipt. It includes repeated unconfirmed station deposits. The final snapshot has all toggles off; that does not establish when each toggle was enabled earlier.

A free wall slot proves only that placement geometry passed. A synced stock event proves only that the station service responded. Neither proves a usable physical crafting station or an actual wall item exists.

## Changes

- Select the station from native catalogue membership: `craftingContent` resolves through `item.byName`, while `freeBuildList` resolves through `itemId`. Use the corresponding stock and craft event. Apply the same routing to utility structures, including station recipes, rather than assuming every placeable item uses the building station.
- Require a loaded physical intake, stock sync and the native recipe's campfire level. A regular-table recipe no longer requires a separate building station. Building-only recipes still require their native building station.
- Craft one pending wall before looking for a safe perimeter slot. Retain that wall while the area is blocked, then place it once a supported free slot is available. Do not accumulate more walls while one is carried.
- Send a complete wall recipe to the station immediately rather than waiting for bulk collection to fill a larger bag. Partial recipes retain the existing bulk-gather behavior.
- A fully funded shared-stock recipe can proceed even if an older deposit expected a higher stock count. Unconfirmed, unfunded deposits still block additional spending; an acknowledgement is not invented and a missing intake is not bypassed.
- A changed bag ID cannot confirm a wall craft. Wall output requires the actual item count to increase; placement still requires both a replicated structure and an inventory deduction.
- Report the wall job's stage and selected crafting service separately from perimeter coverage. Site scans now happen when an actual carried wall is ready for placement, rather than as a prerequisite for gathering and crafting.

## Validation and limits

537 checks pass across 16 production-helper suites, including complete module compilation. Added cases cover both native catalogues and stock pools, missing intake despite synced stock, absent catalogue entries, native campfire gating, crafting before safe placement, queue handoff, a full three-wood deposit → craft → placement sequence, obsolete deposit expectations, and unrelated bag upgrades. `git diff --check` passes.

These are deterministic adapters, not a live Roblox session. The report does not include the live wall's membership in both catalogues, so the previous hardcoded building-station gate is a confirmed code defect, not proof of the exact live server rejection. The next v10 report will identify the selected service and missing prerequisite. An intake that never acknowledges a deposit remains explicitly blocked rather than consuming unlimited materials; server intake behavior cannot be repaired by a client script. FPS, combat survival and live wall coverage are not certified by these checks.
