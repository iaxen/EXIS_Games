# Map-only teleport sweep and teammate revival v11

## Map-only switch

The optional **Reveal map — TP ONLY / 0.3s** switch defaults off and is independent of the four role switches. While enabled, the scheduler admits only this job, including when master farming is paused. It suppresses ordinary reward/code claims and material/survival planning, cancels fishing, and releases hover. Crafting, hunting, chests, station work, teammate reviving and fallback patrols do not run. Turning it off restores scheduling of the unchanged role flags; an already paused master stays paused.

The sweep teleports to unrevealed chunk centers in batches of at most twelve landings, with a target 300 ms pause after each completed landing. The batch yields to the scheduler and checks the toggle between landings. It uses the existing dry-floor, boundary and destination checks. Unstreamed terrain receives a bounded streaming request; a missing safe floor is deferred rather than a blind teleport. Network, streaming and frame delays can make the actual interval longer than 300 ms.

## Why exploration stopped early

The supplied v9 report says 2,883 cells are visible and zero black unknown/frontier cells remain. That does not count gray cells. The native IslandMapClient palette distinguishes black (0), gray (1), land (2/3) and water (4); markers become visible only at palette >=2. The old explorer searched only black cells adjacent to visible land, so gray unrevealed targets could never enter its frontier. Gray cells now remain targets, filtered by the current border. Water is excluded from the frontier.

Already visible cells remain skipped. Streamed tiles and snapshot targets in the same cell are deduplicated. Snapshot updates invalidate cached row lists without discarding the visit state. Arrival and reveal are separate: background snapshots confirm pending arrivals, or release an unconfirmed arrival for a later retry. A 1.5-second blocking map-confirmation wait no longer follows every teleport.

A border-locked or unsafe chunk remains deferred. A pending snapshot or an empty current safe target list does not claim that the whole map was revealed. The switch stays enabled until the user turns it off.

## Auto revive teammates

A separate **Auto revive fallen teammates (bandage)** toggle is enabled by default and included in the Survival bundle. Normal automation selects a nearby fallen player's enabled native torso prompt when a bandage and safe approach are available. It pauses routine work, approaches within prompt reach, and holds for the prompt's actual HoldDuration, including native profession reductions already applied to that prompt.

The interaction follows ReviveClient/ReviveService: a completed executor hold without Triggered may use `ReviveService.client.reviveTeammate(player)`. An observed bandage consumption suppresses that fallback. A successful revive requires the target player's current Humanoid to have positive health; merely triggering the prompt or sending the request does not count. An unconfirmed attempt backs off ten seconds, and unfinished/interrupted holds never send the fallback. Own critical health/food and unsafe approaches defer rescue. One carried bandage is retained during ordinary unloading. No missing-bandage purchase prompt is opened.

The TP-only sweep deliberately pauses revival too, as requested for a mode that only teleports.

## Validation

550 deterministic checks pass across 16 production-helper suites, including full module compilation and `git diff --check`. Added cases cover exclusive scheduling with the master paused, restoring other jobs, twelve 300 ms simulated arrivals, toggle interruption, delayed map receipts, gray-only snapshots, water exclusion, tile/grid deduplication, native revive holds, no-bandage behavior, unfinished holds, native fallback, confirmed HP, duplicate-request suppression after bandage consumption, retry backoff and mode/health exclusions.

These adapters do not certify live Roblox teleport timing or server map/revive receipts. The actual server must still load safe terrain, accept the player's landing and register the map or revival.
