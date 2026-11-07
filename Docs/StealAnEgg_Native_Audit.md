# Steal an Egg: native automation and verified coverage

Entry point: `Games/StealAnEgg.lua`. Run the standalone file in the same client environment used for the other EXIS scripts. Configure categories, use Enable core automation, then Master. The default master is off. The paired EXIScript universal-loader update adds Place 107778070777162 and native EggState/PlotState detection. Both repository updates must reach main when using the universal loader; the standalone game file can also be executed directly.

The script uses the supplied Place 107778070777162 export. The decoded source was inspected for the contracts below; the export contains client code and shared schemas, not the complete authoritative server implementation. User descriptions of event schedules and popularity were not used as executable rules.

## Native contracts

| Source module | Verified contract and usage |
| --- | --- |
| Client.EggState / Shared.Types.AreaEggs | Field snapshot has Records containing Uid, AreaId, NestId, AssetCategory, State, BottomCFrame, BoundsCFrame and BoundsSize. Eligible states are Slot, Dropped and GuardCarried. CarryFieldEgg(uid, optionalSlotKey), ReadCarryState and ownership changes drive the loop. Carried and Claimed entries are excluded. |
| AreaEggsController / AreaEggSlotIdentity | CarryAreaEgg normally holds 1.2 seconds, or 0.25 with workspace FastEggPickupTime. The native call gets `AreaId:NestId` only for FirstAreaEgg_ UIDs. The script waits the same minimum before one native call. |
| CarryRunBackEffects | Some eggs wait for the area's Guard.GuardState to become Chasing. Honor this before walking. No CFrame changes during return; no fabricated safe-zone claim. |
| Client.PlotState | ResolvePlot(userId) returns PlotFolder, CenterPoint and PetArea. Own base and placement are resolved at runtime; no fixed world coordinates. |
| EggPlacementController / Client.EggState | PlantEgg(uid, localCFrame) expects a frame relative to CenterPoint. Grid placement stays within PetArea, separates existing eggs and requires replicated Placement. Attempts are bounded so a full plot cannot starve ready hatches. |
| PlacedEggRenderer / EggHatchAnimation | The native PlacedEggPrompt owns BeginHatch, presentation and FinishHatch. Automation triggers that prompt only for a ready egg near its own placement. It does not bypass growth or send a premature FinishHatch. An ownership-removal receipt marks completion. |
| Data.Assets / Data.Areas / Data.Rarity | Live directories populate pet, biome and rarity selectors. Rarity.Rank determines priority; distance breaks ties. Unknown categories and explicitly excluded tiers/biomes/pets are skipped. |
| PetListController / Shared.Remotes | Haul.WearBest:InvokeServer() performs native best-equipment selection. There is no guessed custom damage or earnings formula. |
| TreadmillStaticController / TreadmillUIController | Walk onto own PlotFolder.TreadmillBottom, then Treadmill.AskWearStill(). AskDoff() must confirm before other movement. AssignedBeltShifted(nil) clears a stale training state. No forged speed awards. |
| Client.BaseUpgrade / Data.Treadmills | IsNextTierAffordable / PurchaseNextTier for base tiers; GetByUpgradeLevel and AskTierRaise(id) for affordable cash treadmill upgrades. Paid-product tiers are skipped. |
| IndexController | Codex.AskRedeemAll claims discovered index rewards. This is not a promotional-code system. |
| FuseKernel / FuseMachineController | Use native INPUT_COUNT, MayEnterFuse and PriceFor(serializedItems). Select matching, unequipped, nonfavorite permanent duplicates. LoadPet(uid,false) then BeginFuse. Resume this session's partial plan; preserve unrelated pre-existing inputs. Native reveal owns reward completion. Fusion consumes pets/cash and has a separate off-by-default toggle. |
| LightVsDarkness RingSystem / Sammy CollectSystem | FetchRings and FetchPickups return wave IDs, encoded zone data and already-removed IDs. Decode with the corresponding Data module, walk to the pickup and observe native RingCollected/PickupCollected. The game collector sends the actual wave/zone/id request. |

## Scheduler and confirmations

One worker owns movement. Carried eggs return before planting/hatching, equipment, upgrades, fusion, events, another steal, or training. Approach may teleport after streaming the egg's location. Return uses pathfinding and Humanoid:MoveTo with jump waypoints, character checks, carry-loss checks and a seven-second movement watchdog. Failed paths are retried without teleporting the carried egg.

Remote calls have a 6.5-second local wait bound. A timed-out mutation retains its in-flight lease until its actual reply, preventing duplicate writes. Carry/placement pending leases also block another approach/plant attempt. Missing ownership, placement, hatch or event receipts are reported as unconfirmed. Rejected eggs have an eight-second backoff. Lost eggs do not increment the claimed count.

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

The loader now shows detecting/download/compile/startup stages and retains actual failures. Its download URL includes a build/time query. The Steal an Egg file explicitly returns `false, error` after a caught startup failure so the loader cannot mistake it for success. A complete-script mocked client test reaches the main panel and separately verifies missing-adapter propagation. Roblox Luau compilation also passes. These checks do not reproduce the reported live executor failure; the displayed stage/error remains necessary to diagnose it. Both repositories' READMEs include the current fresh-launch command and troubleshooting guide.
