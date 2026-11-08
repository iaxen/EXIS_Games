# MrBeast artifact objectives, combat recovery and refuge — v8

## Findings from the supplied run

Reviewed the `172236_316640` report, log parts 5–19 and both saved configurations. This run already uses v7 with all four role switches enabled. The final snapshot is day 3, HP 0, with 54 observed damage events and 32 attack activations / 17 damage receipts. It does not contain a day-7 death trace; the user's report that other runs fail by day 7 is treated as a separate live observation.

No artifact action appears in the supplied session log. Artifact readiness excludes disabled prompts and guarded locations, while locked chests are deferred. There was no job to satisfy native lock requirements. Artifact work also ranked below recurring camp work. The supplied BoatExtra source makes artifact prompts five-second holds and publishes a shared collected-artifact list; collecting Map also exposes the MapManager Map in Buildings. Artifact progress can therefore affect later construction availability, not only escape progress.

Combat repeatedly switches to Auto Attack or Evade. The travel warning envelope uses the large danger radius, but that same envelope also vetoed short kite endpoints and interrupted valid combat spacing. The script could move after every hit even with adequate weapon reach. Artifact interaction also stopped when the full hold completed without a Triggered event; it had no prompt fallback or fresh server-list receipt check.

## Changes

| Area | Current behavior |
| --- | --- |
| Artifact priority | Available artifacts rank ahead of routine acquisition; bounded fairness also includes artifact and unlock work |
| Native locks | Read the live MapLockCnId / MapLockTileId and native configuration; handle kill ratios, named-mob counts and puzzle counts |
| Required targets | Match the objective tile and required mob identity; no substitution of unrelated kills for native requirements |
| Guarded objectives | An already-unlocked but guarded objective can request local hostile clearing before its hold |
| Completion | A kill is progress, not a claim of unlock; native lock state is checked again before opening / collection |
| Artifact pickup | Complete at least five seconds of hold; if the executor did not dispatch Triggered, use its prompt trigger only after the full hold; confirm the shared BoatExtra list, including a bounded refresh if the update event was missed |
| Combat ownership | Auto Attack cannot interrupt an active combat / hunt / unlock cycle; distant opportunistic attacks cannot interrupt a protected artifact hold |
| Weapon changes | Recheck the best usable weapon each cycle, including ammunition depletion and lost Tools |
| Fight selection | Estimate close-range hit time and retaliation cost; defer a bad damage trade for gear or ranged reach |
| Attack spacing | Actual enemy reach governs combat spacing; the wider travel warning buffer stays available outside combat |
| Kiting | Hold a valid safe attack distance instead of always moving closer; kite away from strike / contact risk and validate its actual attack clearance |
| Recovery | Low health or a recent damage burst latches recovery until at least 85% HP and a quiet damage window; healing thresholds follow recovery instead of stopping at the usual 75% |
| Storm behavior | Pause optional exploration / unlock trips during active storms and restrict resource / stockpile pickups to the camp vicinity; existing pre-storm food reserves remain in place |
| Diagnostics | Show collected / loaded / locked / guarded artifacts, the required unlock rule and tile, combat decision, recovery / recent damage, and refuge damage events |

## Tribal room controls

Open **Emergency Refuge / Unlock Tasks** under exploration:

1. Stand inside the exact room, then press **Set refuge here**.
2. Enable **Use saved emergency refuge** for emergency teleport retreat.
3. Independently choose **Keep refuge room locked**. It defaults off, so unlock tasks remain included. Turning it on excludes locks associated with the saved refuge tile; other tiles still receive unlock work. Lock protection can stay on even if automatic refuge travel is off.
4. **Clear native chest / artifact unlock tasks** controls automatic native unlock work globally.

No room coordinates are guessed. The point is tied to the map seed, checks a dry interior floor and body clearance, and rejects visible nearby attackers or nearby Shadow. Interior movement probes downward from within the room so a low ceiling is not selected as the landing surface. The shelter exception applies only near the saved point and only with occluded nearby hostiles; it is not a general exemption from movement checks. If damage occurs within ten studs of the point, it is rejected for 60 seconds and the event is logged. A new map seed requires a new matching refuge.

These checks do not prove a wall blocks every attack or that the room is invulnerable. An unlocked native chest can still be opened from inside when its real prompt and server checks permit it. The script does not report a locked chest as opened merely because the player reached the room.

## Validation and remaining live checks

499 checks pass across 15 deterministic production-helper suites, including complete module compilation. The new suite covers native rule parsing, exact tile / mob targeting, puzzle receipts, actual combat kill flow with ammo-driven weapon switching, close-range damage budgeting, attack-job ownership, recovery hysteresis, storm restrictions, lock-protection switches, artifact full holds / fallback / server receipts, kite clearance, low-ceiling landings, seed mismatch and damage at the refuge.

No live Roblox client was available for this change. Native target membership, streamed objective availability, weapon timing, real artifact collection, room safety, FPS and survival beyond seven days still need an in-game run. Unsupported rules, absent lock metadata, missing targets, unavailable executor prompt support and missing server receipts are reported rather than treated as success.
