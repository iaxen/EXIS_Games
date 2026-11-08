# MrBeast team roles and survival — v6

> Historical v6 notes. The current menu uses [combined job toggles in v7](Mrbeast_Combined_Jobs_v7.md).

This update uses the supplied day-13 report, both saved configurations, the full report log and supplied parts 53–59 of session `20261108_133037_512473`. The user clarified that they control two accounts and repeatedly revived the character. The final HP-zero snapshot therefore does not explain the earlier live stalls by itself.

## Four job configurations

Open **Main → Team Job Configs** and choose one job on each account. Selection saves the job, flags and thresholds to that account's existing per-user configuration. Reopening EXI preserves those selections; it does not silently apply a different role. The generic Start Long Run button explicitly returns to Custom/solo operation instead of retaining a team specialization.

| Job | Focus | Fallback and supplies |
| --- | --- | --- |
| Explorer | Sweep loaded map tiles, open and loot chests, follow clues, interact with puzzles, collect artifacts and handle MrBeast requests. | Keep two cooked meals; collect useful guns left at camp; revisit mapped chunks and use safe camp patrol when exploration is temporarily blocked. |
| Defender | Guard camp, hunt nearby threats, maintain fuel and collect nearby wood. | Stay near the base for routine harvesting, keep one cooked meal and use a safe perimeter patrol between threats. Leave guns for the Explorer and retain melee tools/torch. |
| Camp / Builder | Gather food and materials, keep camp supplied, construct all available stations, craft/place walls, cook, smelt and sort stockpiles. | Keep one meal, build and collect missing ingredients before general stockpiling, and patrol/recheck the base when no safe construction site is ready. Donate guns. |
| Gatherer | Collect all safe material types in batches and return supplies to camp for storage/sorted drops. | Keep two meals; sweep/revisit loaded chunks to find more resources when local sources are exhausted. Donate guns. |

Every role retains eating, personal escape, immediate defence, gear and bag upgrades, torch capability, bulk collection, sorting and anti-idle. Only the Builder enables optional camp blueprint construction through progression; other roles can upgrade their own equipment without becoming additional builders. Critical survival remains above role work. Manual toggles still fine-tune a preset.

For two accounts, Builder + Explorer covers camp construction and map work. Roles can be changed when the immediate need becomes defence or bulk supplies. Presets do not vote to leave the current team or enable the legacy solo lobby auto-start.

## Continuous work and chunk exploration

Each loaded tile with a native BoundingBox supplies a center and four interior sweep points. The frontier chooses unvisited points first, records a visit only after checked travel succeeds, discovers newly streamed tiles, and revisits points after the configurable delay (default 30 seconds). Each destination pass checks at most eight possible points. Failed ground or safety probes get an eight-second retry rather than terminating exploration.

Water, missing ground, threats and the locked border still reject destinations. Loaded chunks alone cannot prove the whole server map is streamed. A critical meal/health need stops a new sweep while recovery runs. Role fallback is a low-priority job, so useful construction, collection, processing and combat preempt it. It keeps checking for work via safe chunk movement or camp patrol. If every route or required source is blocked, the queue reports that condition and keeps the role enabled; it does not fabricate a completed task or intentionally move onto unsafe ground just to appear active.

## Revival and survival

Native `ReviveService` can use `LoadCharacterAsync`, so revival may replace the character rather than merely restore the same Humanoid. The new handler detects both paths, including a character replacement whose down interval occurred between scheduler samples. It releases old hover/movement ownership, clears stale attack/interaction/quest leases, retries and threat/inventory caches, then resumes the saved job. It retains genuine completed escape state. While down, it reports waiting for a team revive rather than repeatedly dispatching jobs that cannot act.

Team presets use these starting values, all adjustable in the existing controls:

- Retreat at 55% health; eat/heal at 75% health or 60% hunger.
- Escape using checked dry teleport landings; avoid enemies with at least a 24-stud buffer and Shadow with at least 70 studs.
- Keep one cooked meal for camp roles and two for travelling roles. Only that reserve is protected from routine unloading; extra food still goes to camp.
- Observe health changes independently on Heartbeat. Damage cancels attack commitment and applies a three-second recovery window. Optional attacks do not begin below the retreat threshold or during recovery.
- Explorer/Gatherer favour escape over optional contact fights. Builder counters isolated threats only at high health; Defender retains guarded camp engagements. Torch hunts require at least 80% health in team roles and no recent damage. Missing torch rewards take precedence over another firearm.
- Disable the old all-night routine pause and hover in team presets. Night jobs still require their normal safe ground, border, health and native interaction checks.

A revival can drop non-tool inventory through the native death service. The script restocks travel food when available instead of assuming the old meals survived. Revival itself remains the native game action performed by the player/teammate; these presets do not automate purchase prompts. Damage, starvation, unavailable food, unstreamed enemies and server lag can still cause death. No invulnerability or guaranteed survival is claimed.

## Gun handoff

Defender, Builder and Gatherer explicitly drop carried `gun`/`infGun` tools at a checked camp handoff spot, overriding keep-best rules only for those guns. Axes, pickaxes, torches and armour remain governed by their usual keep rules. Donation requires inventory acknowledgement and a newly replicated matching ground drop; an unconfirmed action remains retryable. Donors reject gun pickups so they cannot immediately reclaim their donation.

Explorer checks the camp area for useful gun upgrades, respects the normal gear comparison and temporary owner protection, and can collect non-material-bag guns even with a full material bag. Drops use the native inventory service, preserving native ammunition/state. Protection delays and empty ammunition are not bypassed. Custom/solo Long Run does not silently give away its guns.

## Measured stalls and performance changes

The report recorded frame average **590.1 ms**, worst **6977 ms**, 1,850,936 hostile queries, average picker time **56.13 ms**, and average progression planning **49.68 ms**. These are elapsed-time counters; nested totals overlap and RPC totals include waiting. The late log parts also contain blocked unloading, unavailable snake materials, interrupted food/crafting jobs and character-not-ready attempts across the run. They do not establish that every stall occurred while dead.

Changes target the repeated work rather than increasing action spam:

- Creature/hostile snapshots can be reused within the current simulation frame. Explicit scene invalidation and force refresh still work.
- Threat envelope/danger results reuse exact-position, exact-argument and ignored-instance identity within a frame. New frames/threat snapshots invalidate them, and each frame is capped at 256 cached entries.
- Combat checks at most three candidate mobs: the closest two plus one rotating alternative. A valid safe stance is used immediately; failed plans are not rescanned in the same frame. Escape stops searching larger distance rings after finding a safe option.
- Food totals reuse the current frame and invalidate on native inventory, food, storage and drop updates.
- Camp intake zones are added to the existing streamed scene index, eliminating repeated whole-game descendant scans during drop-site checks. Partial/mock environments retain their bounded fallback.
- Ordinary quest polling is reduced while native quest events remain immediate. Progression/probe retries are less frequent; inventory and quest events still invalidate stale plans.
- Sorting/food drop searches can try wider safe rings when the growing camp fills the first rings. All intake, dry-ground, threat and border checks remain.

Diagnostics now include selected role, visited sweep points, observed revive resumptions, damage events, travel ration settings, gun-sharing mode and spatial-cache hits. The previous performance counters remain for comparison.

## Validation

All **14 MrBeast suites pass: 426 deterministic checks**, including full-module compilation and `git diff --check`. New tests cover role isolation, native job-table fallback dispatch and survival priority, interrupted/unreachable/streamed/revisited chunks, same-character and replacement-character revivals, between-sample replacement, health recovery, ration retention, real production gun drop/collection helpers with delayed owner access, frame-cache identity/invalidation/bounds, capped combat scans, missing-torch reward priority and streamed intake-zone indexing.

Actual survival, frame-rate improvement, station availability and server acceptance still require a live run on the user's executor. The tests demonstrate the control paths and receipts, not a live-game certification.
