# MrBeast Long Run v4 — menu, harvesting, base stations and walls

This update follows the day-three report with 264 harvest activations / 154 damage receipts, slow repeated swings, delayed resource drops, and a request to simplify the menu and protect the whole station beach. Validation uses the supplied client/shared source export and deterministic tests. Live server acceptance and mobile layout are not certified.

## Controls

The menu has nine tabs: Main, Survival, Gather & Bag, Camp & Gear, Quests, Explore, Settings, ESP and Diagnostics. Run Controls opens by default; detailed sections remain collapsed. Main contains:

- **Start Long Run • Enable Essentials**: enables survival/food, defence and food hunting, gathering, batch collection, gear progression, every camp blueprint, utility stations, smelting, sorting, MrBeast requests/rewards, chests, wall building, anti-idle and sprint. Auto escape is disabled. Fishing and replay retain the user's settings.
- **Auto Craft & Place Beach Walls**: the same saved wall flag as the detailed Camp control.
- **Enable All Beach Stations**: enables camp blueprint construction, active blueprint contributions, utility crafting/placement and material-acquiring progression together.
- **Quick Controls**: seven grouped switches; amber indicates partially enabled flags. Turning a partial group on enables all its components. Individual settings remain available in the detail tabs and changes refresh the grouped indicators.

Creating the menu does not replace saved preferences. Applying Long Run explicitly restores essentials previously saved OFF. Utility stations and survival take priority over the wall project.

## Harvesting and loot

`ClientToolBase` runs several frame-rounded waits before becoming idle. Its global cooldown timestamp can expire slightly earlier than that recovery phase. Activations now wait for the native cooldown and a recovery guard measured from the actual activation, with three observed frames of slack (0.035–0.3 seconds). No raw resource damage packets are sent and the native cooldown is retained.

Confirmed resource damage renews the work slice so a productive resource is not abandoned merely because the original timeout elapsed. Three unconfirmed cycles still back off, and survival or changed quest requirements can interrupt. Completion requires replicated depletion/despawn.

After depletion, the script waits for eligible drops, retries transient pickup failures and waits at least 0.75 seconds of quiet after confirmed collection. Missing loot receives a bounded four-second observation window and a three-second late-drop watcher. Missing or ambiguous receipts are logged explicitly, never described as collected. Full bags retain the recovery batch for unloading; unloaded item folders retain recovery rather than succeeding.

Safe chests rank ahead of routine gathering and crafting, below immediate survival, fuel and choice rewards. Existing full-hold, native open acceptance and animation checks remain. Chest completion requires a one-second loot quiet interval. A resumed full-bag chest yields to unloading. Items not counted by the native material bag can still be collected when that bag is full. Bags and swap-upgrade tools retain native upgrade comparisons; armour now checks both equipped and carried gear. Equal or better owned armour is not collected again.

## Whole station beach

The former wall plan only included names containing `Beach`. The revised region includes **Basic Block**, connected beach tiles and station-bearing tiles. It includes camp blueprints/built facilities and known utility structures when identifying the station area. Disconnected beach patches do not divert the base project. A newly streamed adjoining tile invalidates the cached outline.

The wall follows the outer outline of this connected area in three layers, suppresses shared internal edges and prefers a dry exit for its entrance. The live native full wooden-wall recipe is selected; the supplied configuration uses three wood. Wall crafting uses the native building station. Each placement requires both a matching replicated wall and an inventory deduction; destroyed segments become eligible again. Water, unsupported corners, the locked border, existing stations and native overlap checks block invalid placements.

Wall diagnostics show region tiles, facilities, planned non-entrance slots, present walls, blocked slots and stations outside the loaded connected region. These are coverage diagnostics, not a claim that every planned slot has been built.

## Build all stations

Camp progression considers every live unfinished non-boat building blueprint and acquires its missing ingredients. Utility crafting recognizes storage, furnace, crafting/building tables, cooking, water, campfire and repair roles from the live catalogue. Existing functional equivalents satisfy a role; decorative walls are excluded and empty recipes are rejected. Missing native stations/recipes cannot be invented.

Utility placements must fit fully on the connected base beach, stay inside the unlocked border, have supported ground under their footprint, and pass native overlap checks. Closer fallback positions allow small base beaches to fit storage when the preferred outer rings are unavailable. Placement confirmation needs the new structure and consumption of its crafted item. Blueprint disappearance alone is no longer labelled finished construction. Diagnostics distinguish `BUILT`, `NEEDS CONSTRUCTION` and `NOT LOADED / NOT OFFERED` for the live building catalogue. Cooking/smelting still need their normal fuel, materials and server state.

## Validation and remaining limits

All 13 MrBeast suites pass: 371 deterministic checks, including module compilation. Added cases cover phase/cooldown rounding, a productive resource exceeding its original work slice, delayed/rejected/ambiguous loot, chest quiet time, armour comparison, full material bags, preset restoration, grouped-control wiring, the Basic Block omission, whole connected station areas, internal-edge removal, streamed expansion, dry entrances, unsupported station footprints and complete blueprint enumeration.

Live checks still needed: mobile rendering, actual server hit/placement acceptance, resource and loot replication timing, and construction unlocks. An HP-zero character cannot work until revived or respawned. Unstreamed tiles/stations and locked or occupied ground remain explicit blockers; no offline test proves those locations are buildable.
