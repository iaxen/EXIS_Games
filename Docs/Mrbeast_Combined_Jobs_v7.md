# MrBeast combined jobs, native receipts and resource loot — v7

This update replaces the single-role menu with independent Explorer, Defender, Builder and Gatherer switches. Any combination works on one account, including solo play. The first role selection sets its related work; later switches add or remove specialist jobs without disabling jobs shared by another selected role. Survival, food, equipment progression and inventory handling stay available. Existing single-role saves remain readable.

Gun donation and receiving are separate optional controls. Leave **Leave all guns at camp** off for solo play. Start Long Run retains its solo behavior and does not enable donation. Role switches preserve an explicit donation preference.

## Audit evidence

Reviewed the supplied `151729_75496` report, log parts 63–67 and both saved configurations. Deduplicated the overlapping log lines before classifying failures. They contain 12,446 unique timestamped events. Findings are based on this session and the supplied native source exports, not a new Roblox playtest.

| Finding | Evidence / cause | Change |
| --- | --- | --- |
| Role selection overwrites other jobs | Four exclusive preset buttons | Four saved additive switches; combined roles preserve shared jobs |
| Furnace drains wood | No aggregate limit in material submission; 91 feed sends in report | Six queued wood maximum for this client, including in-flight requests, indirect progression and tidy calls; replenish only as native stock falls |
| Craft deposits repeat without intake receipts | 62 station-receipt waits in report | Native drop-size approach calculation, predicted intake position check and persistent pending deposit record; request fresh stock instead of sending more wood |
| Wooden walls never execute | No wall job events despite a valid beach layout | Structure goals use building stock, accept partial supplies and submit through the building station; ready wall crafting / placement outranks routine gear crafting |
| Routine jobs starve specialization | Repeated food, craft and inventory preemptions | Ready exploration, walls, structures and stockpile jobs receive a bounded scheduling opportunity after 30 seconds; urgent survival still interrupts |
| Gun removed without observed ground drop | Three pending-ground messages in report | Persist transaction before native request, retain it across combat and use native throw distance when checking ground receipt |
| Exploration revisits loaded terrain | Loaded Tiles were the only destinations | Native 50-stud map grid plus adjacent unrevealed frontier, streamed loading before floor checks, retained target across interruptions and per-cell arrival confirmation |
| Recovery skips surplus harvest loot | Recipe-demand filter applied to fresh resource drops | Collect every eligible new tree / stone drop in the resource batch, including surplus, before another harvest or submission |
| Pickup requires repeated attempts | Disabled startup prompts and individual round-trip waits | Await prompt initialization, send up to eight nearby native pickup requests in a group limited by free bag slots, then confirm inventory and disappearance together |
| Late or interrupted resource loot is missed | Short background watch; routine work can interrupt | Protect a short loot recovery window, preserve in-flight pickup receipts, scan delayed drops for 30 seconds and prioritize recovery; full bags retain overflow for after unloading |
| Destroyed Iron Spear crashes food hunting | One locked-Parent error | Validate Tool ownership and health, then catch an equip race instead of reparenting a destroyed instance |
| Optional reward modules are missing | Four unavailable-module errors | These features are already skipped when absent; they are not the cause of the furnace, walls or harvesting failures |

The combined logs also show 596 pickup requests awaiting confirmation, 254 unconfirmed interaction messages, 232 full-bag messages and 104 explicit tree-pickup retry messages. These are wait / rejection evidence, not proof that every request failed. The final HP 0 snapshot does not explain the entire session; the user repeatedly revived the account.

## Runtime behavior and limits

Resource collection uses the existing native ItemCollect action and its three-dimensional distance limit. Each drop still needs its own server request; nearby requests share a receipt wait. Nonzero native prompt holds are respected. A full bag, unsafe ground, ownership protection, immediate danger or a missing server receipt can delay pickup. The resource batch remains queued rather than being called collected without confirmation.

Furnace stock already above six is not removed. Requests by another account cannot be controlled by this client's limit. If authoritative fuel stock is unavailable, feeding waits rather than guessing. Pending crafting deposits deliberately block further deposits until intake stock is confirmed; the diagnostic names the station, material and expected / confirmed amount. If a station never absorbs correctly positioned materials, its native intake needs a live server check.

Exploration uses the server's normal map snapshot, not reveal-all or wall-radius changes. Unrevealed cells are frontier candidates, not assumed land. Water, locked borders, unavailable streaming and failed floor checks remain blocked. The script cannot force the server to generate or unlock inaccessible terrain and does not report the entire map completed from loaded tiles alone.

The audit panel identifies v7, active jobs, queued furnace wood and allowance, pending station intakes, map coverage and gun ground receipt state. Existing performance timing remains available. Runtime FPS, all native station receipts, complete island coverage and unattended survival still need a fresh in-game session.

## Validation

All 455 checks across 14 production-helper suites pass, including the full module compile check. Added cases cover combined roles, shared-job removal, solo gun preferences, furnace reservation and replenishment, partial walls and correct station stock, deposit retry suppression, stale Tool races, native map coordinates / frontier / water rejection, interrupted gun handoff, grouped loot pickup, free-space budgeting, delayed prompts, surplus materials and interrupted pickup receipts.
