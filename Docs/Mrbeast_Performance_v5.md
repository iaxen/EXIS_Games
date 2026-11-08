> Team presets, chunk exploration, gun handoff, revival recovery and further survival/performance changes are documented in [Mrbeast_Team_Roles_v6.md](Mrbeast_Team_Roles_v6.md).

# MrBeast performance and chest ESP — v5

Reviewed inputs: all five supplied `20261108_123354_119897` log parts, its report and saved configuration, plus the two supplied late parts of `20261108_114008_3449440`. Native behavior was checked against the extracted ChestClient/ChestService sources. These logs lack frame timings; the code hotspots below are supported explanations, not measured FPS attribution.

## Findings

| Evidence | Problem / interpretation | Change |
| --- | --- | --- |
| Latest complete session: 28 chest job starts and 27 unconfirmed/stopped outcomes. Repeated `NO SAFE DRY APPROACH` interrupted food hunting. | Unreachable chests kept becoming ready after a short general retry. | A failed safe approach defers that chest for 12 seconds. Other targets and jobs continue. Survival interruptions do not receive this penalty. |
| Three chest status read timeouts and four MrBeast fetch timeouts; reads have a 6.5-second bound. | Blocking reads stalled the active opener; repeated failed fetches also added network pressure. | Chest state is cached, native enabled prompts avoid unnecessary reads, open events update immediately, failed chest reads back off 15 seconds, and timed-out quest fetches retain the request with a five-second retry delay. |
| 32 `isOpened` and 28 `isLocked` read starts in that session. | Readiness/ESP must not repeatedly ask the server for the same state. | ESP probes are asynchronous and single-flight, with a minimum 0.5-second start spacing. False results cache for 30 seconds; timeouts defer that chest 30 seconds and all background probes five seconds. A pending probe prevents a duplicate foreground opener. |
| Opened chest models remain in the world; old ESP classified them by name alone. | Used chests kept markers. A disabled prompt can mean either locked or opened. | Confirmed per-player opening state removes the billboard/highlight immediately. Chests opened before EXI started are checked in the background. Disabled prompts alone never count as opened. Loot recovery remains independent of marker visibility. |
| Report: 60 base-beach tiles, 621 wall slots, 332 blocked in the previous full scan. | Each full readiness scan could perform hundreds of ground/footing/overlap tests, and execution could repeat the scan. This is a likely frame-cost hotspot. | Region results cache for one second while loaded tile count/facility positions invalidate changes. Wall selection checks at most 12 slots per batch, advances a cursor, and reuses a valid site for 0.75 seconds. Batches continue at 0.1-second readiness intervals while coverage remains; placement invalidates the selected site. Coverage is retained. |
| Source: the picker ranked jobs before checking whether they were enabled. Final saved configuration has Auto Farm OFF and ESP enabled. | Disabled combat priority still scanned threats. This unnecessary work also occurred with the master stopped. The paused final snapshot does not explain earlier automation failures. | A stopped master exits the picker immediately. Disabled jobs skip rank, round and night scans. Paused material planning is also skipped, the paused scheduler body runs at a lower frequency, and the zero-delay scheduler no longer performs an extra picker pass each frame. Enabled job priorities and survival interrupts remain. |
| Saved `chestHoldPadding` is four seconds. | This adds four seconds beyond the native hold for each chest. | Applying Long Run now selects 0.15 seconds of extra padding. The real native hold and receipt grace remain; an existing custom setting changes only when the preset is explicitly applied. |

The four unavailable optional reward modules are logged and skipped. They are not evidence that resource harvesting failed. The earlier partial session's available parts mainly show inventory changes; they cannot establish that session's complete failure counts.

## Diagnostics and other reductions

The new PERFORMANCE section reports frame average/worst time and frames over 50 ms; each measured helper's call count, total/average/max elapsed time and slow calls; RPC wait costs; background probe failures; wall checks and site-cache hits. The top eight helpers are listed by total elapsed time. Nested totals overlap and remote elapsed time includes waiting, so these numbers are not additive CPU percentages.

Profiled work includes scheduler selection, ESP, wall sites/regions, progression planning, hostile scans, scene indexing and automation reports. Measurements accumulate in bounded per-helper records without a log event for every sample. Background diagnostic snapshots rebuild at most every two seconds; the visible Diagnostics tab can refresh every 0.5 seconds, and copy/save forces a fresh snapshot. Hidden diagnostic text and unchanged ESP label text avoid unnecessary UI updates. Bundle aliases no longer appear as fake OFF features in the report.

Wall diagnostics now describe the current batch/next site rather than pretending a partial scan is a complete count of installed walls. The three-layer connected beach plan, station-footprint checks, native crafting, full chest holds and collection receipts remain.

## Validation

All 13 MrBeast suites pass: **388 deterministic checks**, including full-module compilation and `git diff --check`. New cases exercise immediate and initial-run chest ESP removal, locked-versus-open distinction, cached server state, single-flight timeout backoff, no duplicate foreground read, inaccessible targets, disabled-master/disabled-job short circuits, a 600-slot blocked plan capped at 12 checks, site reuse, region invalidation and honest elapsed-time reporting. Existing hold, delayed loot, full-bag recovery, combat, quests, station and wall checks still pass.

A live server run is still needed to measure actual frame improvement, remote latency and executor overhead. After merging/reloading, applying Main → Start Long Run restores essentials if desired; the supplied final configuration has automation paused. Copy the new diagnostics after a representative run to compare helper timing and frame spikes. No speed setting bypasses native hold durations, cooldowns or server validation.
