# MrBeast and ZombieRush diagnostics

Both games have a **Diagnostics** category after Settings, at the end of the sidebar. Expand **Failures and Full Session Log** to read the session state, failed action names, their latest reasons and occurrence counts, current waiting states, and the latest 80 log entries.

**Copy Diagnostics** copies the state snapshot and complete available session history. **Save Full Log** writes the same report to the game's executor-workspace folder. The report name and save result appear in the status display. Clipboard errors are recorded and Save Full Log remains available as an alternative.

Automatic logs use `diagnostic_<UTC-session>_<part>.log` files in:

- `EXIGames/MrbeastIslandEscape/`
- `EXIGames/ZombieRushSurvival/`

The logger periodically saves the current chunk and rolls into a new file after 200 entries. Export combines all saved chunks with the current unsaved entries, rather than copying only the visible tail. Unchanged per-action statuses are counted rather than repeated every frame; explicit remote request entries are retained individually. The live view shortens long stack traces, while exports preserve their full text.

The recorded events include script status transitions, protected-job errors, server rejection reasons, missing service/remote failures, request starts and returned results, and startup/shutdown information. A sent event or returned response does not by itself prove the gameplay objective completed; game receipt/status checks remain authoritative. MrBeast records timeouts from its bounded reads, and ZombieRush records callback and worker exceptions. Diagnostics refresh independently of long-running MrBeast jobs. The view includes current job, day/wave, HP, bag/cash, map/class and enabled automation context where available.

Ordinary waiting, unsafe approaches and insufficient funds are shown as waiting states. They are distinct from exceptions and rejected interactions. A previous failure remains in the failure history after an action recovers, while its current state updates.

If file saving is unavailable, the view explicitly reports the error, retries are throttled, and up to 2,000 recent entries stay in memory. Any discarded older entries or unreadable saved chunks are identified in the report. Automatic chunk saves do not include the full live snapshot; use Copy Diagnostics or Save Full Log for a combined report. These are script-session logs, not Roblox server-internal logs or previous sessions' history.

# ZombieRush boundary correction

The drawn polygon is an outer limit. Runtime planning first creates an inset area with a one-stud border gap; rectangular bounds are aligned inward to the native grid. Barricade, turret and support footprints remain within that interior while retaining the existing row and middle-spacing plan.

Immediately before a Place request, the requested point is snapped using the defense's native grid and facing footprint. The complete rectangle must remain strictly inside the original polygon, with no touching or crossing of its lines. Rejected boundary checks appear in Diagnostics. Existing defenses are not moved or deleted.
