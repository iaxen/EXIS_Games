# Steal an Egg: native automation and verified coverage

Entry point: `Games/StealAnEgg.lua`. Run the standalone file in the same client environment used for the other EXIS scripts. Configure categories, use Enable core automation, then Master. The default master is off. The paired EXIScript universal-loader update adds Place 107778070777162 and native EggState/PlotState detection. Both repository updates must reach main when using the universal loader; the standalone game file can also be executed directly.

The script uses the supplied Place 107778070777162 export. The decoded source was inspected for the contracts below; the export contains client code and shared schemas, not the complete authoritative server implementation. User descriptions of event schedules and popularity were not used as executable rules.

## Native contracts

| Source module | Verified contract and usage |
| --- | --- |
| Client.EggState / Shared.Types.AreaEggs | Field snapshot has Records containing Uid, AreaId, NestId, AssetCategory, State, BottomCFrame, BoundsCFrame and BoundsSize. Eligible states match the native prompt controller: Slot and Dropped. GuardCarried is excluded until the native controller exposes a pickup prompt. CarryFieldEgg(uid, optionalSlotKey), ReadCarryState and ownership changes drive the loop. Carried and Claimed entries are excluded. |
| AreaEggsController / AreaEggSlotIdentity | CarryAreaEgg normally holds 1.2 seconds, or 0.25 with workspace FastEggPickupTime. The native call gets `AreaId:NestId` only for FirstAreaEgg_ UIDs. SmartProximityPrompt puts the prompt on a detached Workspace.SmartPromptPart, so egg-model ancestry cannot identify it. After a checked native-duration hold, the script sends exactly one EggState.CarryFieldEgg(uid, optionalSlotKey) request, as the controller does. No prompt input is dispatched alongside it. Native rejection reasons and exact-UID carry replication are recorded separately. |
| CarryRunBackEffects | RunBackWakeDelayRequired delays audiovisual run-back effects until Chasing; it is not a movement lock. Start running immediately after exact carry confirmation to retain the native waking head start. No CFrame changes during return; no fabricated safe-zone claim. |
| Client.PlotState | ResolvePlot(userId) returns PlotFolder, CenterPoint and PetArea. Own base and placement are resolved at runtime; no fixed world coordinates. |
| EggPlacementController / Client.EggState | PlantEgg(uid, localCFrame) expects a frame relative to CenterPoint. Grid placement stays within PetArea, separates existing eggs and requires replicated Placement. Attempts are bounded so a full plot cannot starve ready hatches. |
| PlacedEggRenderer / EggHatchAnimation | The native PlacedEggPrompt owns BeginHatch, presentation and FinishHatch. Automation triggers that prompt only for a ready egg near its own placement. It does not bypass growth or send a premature FinishHatch. An ownership-removal receipt marks completion. |
| Data.Assets / Data.Areas / Data.Rarity | Live directories populate pet, biome and rarity selectors. Rarity.Rank determines priority; spawned BoundsSize volume, AssetScale, distance and stable UID break ties in that order. Unknown categories and explicitly excluded tiers/biomes/pets are skipped. |
| PetListController / Shared.Remotes | Haul.WearBest:InvokeServer() performs native best-equipment selection. There is no guessed custom damage or earnings formula. |
| TreadmillStaticController / TreadmillUIController | Walk onto own PlotFolder.TreadmillBottom, then Treadmill.AskWearStill(). AskDoff() must confirm before other movement. AssignedBeltShifted(nil) clears a stale training state. No forged speed awards. |
| Client.BaseUpgrade / Data.Treadmills | IsNextTierAffordable / PurchaseNextTier for base tiers; GetByUpgradeLevel and AskTierRaise(id) for affordable cash treadmill upgrades. Paid-product tiers are skipped. |
| IndexController | Codex.AskRedeemAll claims discovered index rewards. This is not a promotional-code system. |
| FuseKernel / FuseMachineController | Use native INPUT_COUNT, MayEnterFuse and PriceFor(serializedItems). Select matching, unequipped, nonfavorite permanent duplicates. LoadPet(uid,false) then BeginFuse. Resume this session's partial plan; preserve unrelated pre-existing inputs. Native reveal owns reward completion. Fusion consumes pets/cash and has a separate off-by-default toggle. |
| LightVsDarkness RingSystem / Sammy CollectSystem | FetchRings and FetchPickups return wave IDs, encoded zone data and already-removed IDs. Decode with the corresponding Data module, walk to the pickup and observe native RingCollected/PickupCollected. The game collector sends the actual wave/zone/id request. |

## Scheduler and confirmations

One worker owns movement. Carried eggs return before planting/hatching, equipment, upgrades, fusion, events, another steal, or training. Approach may teleport after streaming the egg's location. Return uses pathfinding and Humanoid:MoveTo with jump waypoints, character checks, carry-loss checks and a seven-second movement watchdog. Failed paths are retried without teleporting the carried egg.

Remote calls have a 6.5-second local wait bound. A timed-out mutation retains its in-flight lease until its actual reply, preventing duplicate writes. Carry/placement pending leases also block another approach/plant attempt. Missing ownership, placement, hatch or event receipts are reported as unconfirmed. Definitively rejected carry requests have a two-second backoff; unsuccessful surface approaches use one second. An accepted but unconfirmed carry has a separate reconciliation lease. Fresh record versions and native resets invalidate old egg backoffs. Lost eggs do not increment the claimed count.

Settings are under EXIGames/StealAnEgg. Master starts off on each load. Stop/close halts movement, disconnects owned listeners and requests treadmill exit. Death clears transient training/hatch state; the native modules continue to supply fresh records after respawn. UI copies the Fuzzotopia palette, compact header/sidebar, accordion groups and minimize/reopen controls.

## Coverage boundaries

Implemented: field/event eggs in the native snapshot, selected-biome/rarity/pet targeting, approach teleport plus walking return, planting/native hatching, native best equipment, idle treadmill, optional cash base/treadmill upgrades, discovered index rewards, optional matching-pet fusion, Light vs Darkness rings and Sammy pickups.

Not implemented: stealing already-owned pets/eggs from another player's inventory/base through separate paid/PvP flows; complete Dragon Lair/Monster Obby routes; Mount Race driving; Halloween dimension boss fights; UFO, train, Beanstalk and other special multi-stage quest completion; automatic rebirth, selling, trade-ins, Robux purchases or promotional codes. The event toggle does not claim to finish these unrelated systems. Their presence in Remotes does not establish valid prerequisites, arguments, movement or completion timing. These require further individual adapters and live validation.

No live Roblox session was available. Teleport approach may be rejected by the current server. Pathfinding may fail on streamed or special-event geometry. Native hatch automation requires executor fireproximityprompt support and a streamed prompt. Client scripts, paid unlocks, full inventories/pens and server corrections can reject work; this implementation reports that instead of fabricating progress. It is not a guarantee of flawless or all-mechanics AFK play.

## Verification

Run `texlua Tests/StealAnEgg/core.lua` and `texlua Tests/StealAnEgg/runtime.lua` from the repository root. Tests cover rarity-first ordering, ties, exclusions, states, retry backoff, first-area payloads, duplicate-only fusion, return ownership receipts, carry loss, unavailable base, treadmill exit, in-flight mutation leases and complete-module compilation. Existing MrBeast, ZombieRush, UI and storage tests remain part of regression verification.


## Startup, performance and universal EXIS tools

The original universal loader did not contain a Steal an Egg route. The companion EXIScript change adds the route and tests actual downloaded-chunk execution, not just route-table text. The game now shows a startup stage panel before requiring native adapters, waits for initially absent module paths, and displays the failing module/error instead of only printing a warning. A failed startup still requires the actual displayed error to diagnose runtime-specific failures.

Performance has separate controls for other-plot ToUpdate visuals, native Shared.Preferences HideOtherPets/HideSelfPets/DisableVideos, plain materials, removed textures/shadows and disabled visual effects. The native hide-pet preferences suppress rendering work in ActiveAssetsController. Other-pen hiding never destroys objects or changes collisions, physics, prompts or record tables. Property snapshots restore on mode changes and close; the script also attempts to restore the native preferences it changed. Newly streamed visuals are processed through descendant listeners. FPS improvements are device-dependent and were not measured live.

Tools include current FPS/task/save/base/carry/module/pending-request diagnostics, recent log, copy/print/save diagnostics, settings save/reload while paused, queued snapshot refresh, anti-idle input, optional teleport execution, manual rejoin and connection-loss reconnect. Reconnect handles error 277/279 and connection-loss text without a different explicit error code. Teleport autorun reads saved autoExecute at execution time so disabling it cancels a previously queued launcher. New sessions remain paused. Files and clipboard/teleport hooks depend on executor capabilities; failure is reported rather than silently assumed successful.

Performance/session tools work independently of the farm master. They do not clear uncertain mutation leases. Rejoin controls intentionally leave the session when clicked. The new performance tests verify property ownership/restoration, exclusion of own plot, preserved collisions/prompts and distinct mode invalidation signatures. No live executor startup or FPS benchmark has been performed.


## Launch-stage follow-up

The loader now shows detecting/download/compile/startup stages and retains actual failures. Its download URL includes a build/time query. The Steal an Egg file explicitly returns `false, error` after a caught startup failure so the loader cannot mistake it for success. A complete-script mocked client test reaches the main panel and separately verifies missing-adapter propagation. Roblox Luau compilation also passes. These checks do not reproduce the reported live executor failure; the displayed stage/error remains necessary to diagnose it. Both repositories' READMEs retain only the launch command and supported games; technical troubleshooting stays here.


## Pickup acknowledgement and detached native prompts

A failed steal could previously fall through to idle treadmill movement, which also walks home and looks like a completed steal. The earlier fix required a CarryAreaEgg prompt under the selected egg's model. That assumption was incorrect: `Client.SmartProximityPrompt.FollowerLoop.MakeAnchor/Add` parents a separate `SmartPromptPart` directly to Workspace and puts the prompt under that anchor. The anchor has no UID ancestry. Matching nearby anonymous anchors could also select another egg.

Pickup now uses the exact adapter in `AreaEggsController.Triggered`: `EggState.CarryFieldEgg(uid, slotKey)`; `slotKey` is `AreaId:NestId` only for `FirstAreaEgg_` records. It waits the native 1.2-second hold (0.25 with FastEggPickupTime), continuously validates record version/state, selection, reach, character and barriers, then dispatches once. It never combines a direct request with prompt input. A native rejection includes the returned reason. An accepted reply still requires the exact carry UID; timed-out requests retain their in-flight lease. A failed pickup cannot trigger a home/training walk in the same pass.

Approach tests four points outside the egg's oriented bounding box, preferring the side toward home, rather than teleporting inside a large egg. It checks surface reach and prepares a running path before sending pickup. During return, movement stays under Humanoid:MoveTo. No carried teleport or fabricated claim is used. A no-path result remains a defer, not a successful steal.

Successful return waits for exact UID ownership or a newly owned matching category, since redemption can assign a new inventory UID. The category fallback cannot distinguish simultaneous same-category rewards; it is not a server identity guarantee. Native rejection, server movement correction, full capacity and unreachable routes still need live observation.

## Egg lists and shared switch controls

The Eggs page now includes the native egg-name catalogue, rarity labels, pet-category identities, search, pagination and include/exclude-all controls. An independent saved eggTypes map filters collection before rarity/distance ranking. A live map list displays native egg names, current biome, rarity and field state with pagination. Shared names retain their pet-category identity so selecting a Forest Egg variant is unambiguous. EggRecords.DisplayName is used when available; native asset egg labels provide a fallback.

The dot-text buttons have been replaced throughout Steal an Egg by the shared Fuzzotopia track/knob switch design. Whole-script UI tests create and click the actual controls to verify on/off knob movement. READMEs intentionally contain only the original launch command and supported game list; technical coverage/limitations remain in this audit.


## Deep carry, chase and execution audit

The export's remote declaration inventory and literal client call sites are in [StealAnEgg_Call_Map.md](StealAnEgg_Call_Map.md): 414 declarations across 96 namespaces, with 162 declarations matched to literal replicated-module call sites. This is an index for tracing, not 414 implemented automations. Some calls are server-to-client notifications. Dynamic references, non-replicated scripts and authoritative server validation are outside that inventory.

### Conflicts found and corrected

| Conflict | Result before | Correction |
| --- | --- | --- |
| Treating CarryRunBackEffects' visual wake delay as a movement prerequisite | Waiting for Chasing spent the waking head start while holding an egg | Walk immediately after exact-UID carry acknowledgement |
| Root-to-ground 3D arrival distance | A root above a reached ground waypoint could wait up to three seconds | Horizontal arrival distance with an eight-stud height tolerance; skip reached waypoints |
| Computing the first home path after pickup | Path computation could consume the escape window | Compute and cache a home path before starting the pickup hold; defer pickup when no path is found |
| Waiting for carry release after a failed route | Standing still despite still carrying and being chased | Preserve carry priority and retry routing on the next worker pass |
| Loading optional guardian modules inside the running loop | A require could yield up to the adapter wait bound during escape | Preload before pickup; chase snapshots only read cached data and observed speeds |
| Late carry replication during another approach or ordinary walk | A newly acquired egg could be moved by an unrelated job | Guard after yielding streaming/training work, before both approach CFrame writes, during every walk poll, and between scheduler phases |
| Switching speed modes and overlapping native modifiers | Conflicting speed requests or restoring an obsolete value | Exclusive modes, one temporary speed owner, preserve newer native values, restore on stop, close, pause/reload, route exit and character removal |
| A slow native hatch finishing after the local receipt wait | Another job could start while the native animation remained pending | Bounded hatch lease reconciles late receipts before resuming ordinary jobs |

The return route uses Humanoid:MoveTo and native jump waypoints. It never assigns character CFrame, velocity or guardian properties. A cached path is consumed only for the same character, within 15 seconds and near its original start/goal. Otherwise pathfinding retries. Paths may still become invalid as geometry streams or barriers change. Rejected paths retain the egg and report the retry; there is no teleport-return fallback.

### Chase computations and controls

`GuardChasePolicy.ResolveWalkSpeed(base, flatRadius, gap)` uses horizontal gap. At or below flatRadius, speed equals base. Above it:

`guardianSpeed = min(base * (1 + (gap / flatRadius - 1) * strength), base * multiplierCap)`

The supplied GameplayBalance defaults are strength 0.5, multiplierCap 4, and waking duration 0.63 seconds. Runtime balance/config values are read rather than freezing those defaults into every guardian. A larger lead can therefore make the guardian faster. With a reference guardian base 16 and flatRadius 10, gap 20 gives 24, and a sufficiently large gap gives 64. The supplied Forest config instead has flatRadius 20 and hit distance 2.5; gap 40 gives 24, and the speed ceiling is 64. Enchanted Forest's exported base 251.075 can reach 1004.3 before live balance overrides. A fixed 64 or an auto cap of 300 cannot promise to outrun every biome.

At native Forest speed 16, preserving 0.63 seconds of waking permits about 10.08 studs of travel before chase starts, assuming immediate unobstructed movement. Actual distance depends on local execution, collision, modifiers and server corrections. The native GuardEscapePrediction models changing chase speed and uses a binary search for required escape speed; a constant-speed catch-time shortcut is not an equivalent model.

The Training page now exposes:

- Fixed running speed: editable studs per second, temporarily requested during walks.
- Auto speed from my chasing guardians: the maximum of the native baseline and each relevant guardian's observed/predicted speed plus the chosen advantage, bounded by the chosen cap. Snapshots refresh while moving. It includes the carrying area's waking/sleeping guardian so it can prepare before Chasing, and excludes guardians chasing another player.
- Auto advantage and maximum requested run speed: separately saved numeric settings. Fixed and auto modes cannot be enabled together. Both off preserves native running speed.
- Defer eggs above native escape-speed estimate: compare published `GuardEscapeSpeeds.Y` to selected running speed/cap, or native speed adjusted by the carry ratio. Recheck after streaming. An absent sign is unknown, not evidence of a safe escape.

The native sign describes an ideal area exit, not the entire obstacle-filled route to the base. Passing the check is an estimate, not a safety guarantee. Auto mode compares its cap during preflight; its actual requested speed follows the guardians and can be lower. Reaching the cap is exposed in diagnostics, alongside measured movement, requested speed and guardian speed. A speed request is a local Humanoid.WalkSpeed change; it does not award SpeedPower, grant treadmill progress, defeat native speed overrides or ensure server acceptance. Native WalkSpeedGovernor applies its own modifiers/overrides. Anchored, seated, PlatformStand, Physics, Ragdoll and Dead states are left to native control.

### Verification of this change

Tests execute production helpers with mocked native state for immediate waking-phase return, root-height arrival, cached-path use, no CFrame writes on return, carry-UID replacement, carry acquisition during unrelated movement, path rejection, no-path pickup deferral, late carry during streaming/approach, guardian chase calculations, target-player filtering, exclusive switch controls, cap/preflight decisions, speed cleanup and native correction preservation. All 502 regression checks across 27 suites passed, including complete-file UI startup. The updated game file also compiled successfully with the Roblox Luau compiler. No live executor/server session was available, so successful live pickup, guardian escape, every event adapter and long-term AFK survival remain unverified.

## Reset response and largest-of-rarest priority (build 4)

Selection reads the live native field snapshot and orders eligible eggs by:

1. Highest native `Rarity.Rank`.
2. Largest spawned `BoundsSize` volume within that rarity.
3. Highest `AssetScale` if volume ties (scale cubed substitutes when bounds are absent).
4. Nearest distance, then stable UID.

A huge common egg never outranks a smaller higher-rarity egg. Biome, pet, egg and rarity exclusions still apply. The optional native escape-speed estimate deferral remains available but defaults off for highest-rarity collection; legacy settings are migrated once via `priorityVersion = 2`. Later explicit choices persist. This changes target choice, not the server's speed requirement. The live egg list uses the same ranking and displays native scale.

`FieldRefreshed`, `FieldShifted`, `FieldGone` and `RarityRevealed` invalidate selection. New record versions clear the affected UID's old rejection backoff. `ResetCountdown.DayStartsAt`, `AreaEggCycle.PeriodIndexAt/NextResetTime` and the native ServerClock track reset boundaries, including runtime schedule overrides and disabled cycles. The clock and single farm worker poll at 0.05 seconds; signal callbacks only update state and never launch another movement worker. Duplicate/older reveal periods and countdowns do not retrigger the same reset. A missing field batch queues a native field sync; timer prediction does not invent new egg records.

The reset announcement is not proof the field has reopened. `ResetStartTimerController` waits until DayStartsAt plus two seconds, then runs a three-second wall countdown and drops the wall. Collection observes `AreaEggResetWall.IsSealed`, rather than teleporting repeatedly into the closed field. The worker acts on replicated candidates once the wall opens; local latency, native rendering/pathfinding and server acceptance still bound real pickup time.

Available eggs preempt idle treadmill sessions and uncommitted routine walks. Selection is checked again after streaming, path preparation and throughout the pickup hold, so a fresh larger/higher-rarity egg can replace an obsolete uncommitted target. Confirmed carries, pending carry mutations and committed hatch animations retain ownership until resolved; a reset does not clear them. A full egg inventory disables this walk preemption so hatching can free space. No carried egg is abandoned merely because a rarer one spawns.

Regression coverage includes the detached-prompt failure, one native dispatch after a complete hold, first-area slot payloads, exact carry acknowledgement, native denial/timeout behavior, short and oversized egg surfaces, full selection-to-return flows, reset replacement during approach/hold, native wall opening, timer overrides, duplicate reset events, full-inventory hatching and preservation of in-flight ownership. No live executor session or guardian escape soak test was available.
