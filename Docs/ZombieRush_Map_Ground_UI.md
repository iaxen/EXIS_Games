# Zombie Rush Survival: map boundary, layered defenses and teleport dodging

## Area controls

AREA contains **Pick Map Part**, **Edit Saved Boundary**, and a persistent **Show Saved Boundary** switch. Off removes the world markers; on draws the current map's saved boundary. Visibility is independent of Master and does not change the selected polygon or interrupt a placement by changing the layout revision. Closing or cancelling the editor respects the switch instead of automatically showing markers. Map changes refresh the displayed boundary.

The independent map replica retains mouse/touch selection, immediately visible numbered corners, CONNECT, undo, clear, cancel, zoom/pan, and real floor controls. Pick Map Part generates the clicked source part's four corners. Edit Saved Boundary reloads the saved corners. Opening the editor keeps combat active. The removed Area actions were new free-form selection, separate show/hide buttons, and removing the map-part lock. Old saved regions remain readable; the saved part remains the placement surface. The legacy automatic spawn-area override is disabled so it cannot silently replace the selected area.

## Final defense layout

The requested layout is **one outer barricade row plus three turret rows behind it**, with spaced middle defenses rather than solid interior tiling. Middle barricade anchors are approximately **12 studs apart by default**, with nearby shooting defenses, including missile defenses when exposed by the equipped class and enabled. Selected traps can use remaining space beside these groups. Native grid snapping may offset the anchor by part of a stud. Middle Defense Spacing is adjustable from 6–40 studs.

Ordinary Barricade, FlameBarricade, ExplosiveBarricade and other barrier names are classified as walls even when Classification.Barricade is absent. The supplied ordinary Barricade has Style=Barrier, Physics.ZombieBlocking=true, and FakeWall.Enabled=true; the previous classifier incorrectly treated it as a turret. Nonblocking support barricades are not credited as a blocking outer wall.

For an axis-aligned rectangular map part, the planner creates aligned frame rows using the native footprints. Adjacent grid cells can touch. This avoids the artificial 0.3-stud spacing and greedy corner holes in the earlier planner. Turret frames shrink behind the actual barricade dimensions, preserving three separate rows. Other valid polygons use inward offset rows and interval-based gap checks. Collapsed, narrow, concave or otherwise unsupported offsets are reported rather than bridged with imaginary placements.

Per-slot facing follows the native contract: only types supported by DeployablePlacement.FacesCharacter can rotate in the general polygon planner. Native nonrotating barricades keep facing zero. Placement sends the chosen slot's facing, not one shared orientation derived from the first boundary edge. Every slot is rechecked against its full selected-area footprint, surface, live occupancy, safety, cash reserve, class and map before the native Place call.

A selected support unit gets actual reserved space; classes without support no longer leave a phantom support hole. Existing defenses and unreplicated accepted placements participate in planning. A changed defense footprint signature invalidates the plan, allowing destroyed defenses to be replaced. Rejections use map/revision/type/coordinate/facing keys, so replanning cannot erase their backoff. Pending placements are excluded from confirmed built counts and are not placed over.

Defense limits are ceilings, not spending targets. The middle stops at its spaced groups instead of filling every available cell. The new default ceiling is 256, adjustable up to 512. Old saves with the original 18-slot default migrate once to 256; other configured limits are retained. Cash reserve and native prices still gate purchases. Each row reports gaps or insufficient space/budget; a small map part may not fit all three turret rows. No collision, class, cost or no-deployable-zone rule is bypassed. Native rejection remains a rejection.

The user reported that placed defenses suppress spawns locally. The planner follows the final requested spaced-middle design; it does not claim that intentional interior gaps become a server-enforced no-spawn zone. Complete server spawn validation was not available in the supplied exports.

## Fight mode teleport dodging

Fight defaults to **Teleport Dodge in Fight Mode**, with preferred zombie clearance **35 studs** and a normal TP interval of **0.3 seconds**. Clearance is adjustable from 3–40 studs; interval from 0.12–1 second. Disabling this option retains the previous grounded turret-aware dodge mode. No hover or high-altitude flight is created.

Fight checks threats on a 0.1-second cadence and relocates repeatedly while enemies exist, even when its old spot remains clear. Candidate positions include nearby rings, native navigation points and a coarse spread across the playable map. A recent-location penalty discourages repeatedly attracting the swarm to one spot. Friendly turret coverage is a small preference; empty space and attack clearance take priority. A safe placement approach can be chosen as a landing so defense work can still progress.

Destination scoring uses all available visual zombie positions, native attackRange, and recent movement projected over the TP interval. Zombie motion is estimated from replicated visual displacement, with extreme visual jumps bounded against the native speed reference. It prefers the requested empty radius; if unavailable, a smaller opening is eligible only when predicted attack clearance remains positive with body/safety margin. Boss reach is included. Newly arrived enemies and the character are checked again immediately before teleporting.

Landing validation requires a playable-map floor, a clear character-sized volume using the player's collision group, and four foot-support samples. Walls, collidable deployables, holes, water, steep support and excessive drops reject the landing. Rejected cells have a short backoff. The scan and expensive landing queries are bounded. Normal TP cooldown remains enforced, with a 0.12-second minimum emergency relocation when a new threat or damage arrives. Anchored, seated, PlatformStand, Physics, Ragdoll, Dead, stopped and disabled states cannot issue teleport movement.

Teleport cancels the outstanding walk, preserves orientation, lands at normal standing height and clears residual velocity. It does not alter zombie AI or health. Gun selection, firing, reload and boss targeting continue independently; the old hold-near-turret walk does not resume after a TP. With no enemies it does not roam unnecessarily, while a safe build approach can still move. When no validated opening is found it reports that and continues rechecking/firing.

Actual server acceptance, latency, special boss abilities beyond the exported attack range, and live executor behavior remain unverified. These are local movement requests and cannot guarantee zero damage or survival.

## Source and verification

The implementation uses the supplied CrystalMap and SkylineCity exports, including DeployableDefinitions, DeployablePlacement, DeployableUtils, ClassDefinitions, ZombieTypes and native map/navigation geometry. Their matching shared contracts were checked previously. The universal Fuzzotopia-style EXIS shell and existing per-game save paths remain in use. README is unchanged.

Production-helper tests cover closed rectangular row geometry, all four border sides, three distinct turret rows, approximately 12-stud middle groups, native facing restrictions, exact interval/footprint geometry, live/pending/destroyed occupancy, row limits, marker visibility, Area controls, repeated ground TP, emergency cooldown, small openings, boss reach, incoming-zombie prediction, late threats, blocked/unsupported landings, and continued firing. Other EXIS game and UI/storage regressions are included. All 428 checks across 22 suites passed, and the updated game file compiled with the Roblox Luau compiler. These are simulated tests, not a live Roblox benchmark.
