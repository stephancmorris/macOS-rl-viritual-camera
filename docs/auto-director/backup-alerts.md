# Backup alerts and live controls (C-09)

`DirectorSection.BackupAlert` carries facts reported by the fallback adapter: the actual new Program input after a successful switch, both inputs stale, or a retained pause after fallback. Its view cannot switch, resume, dismiss or qualify anything. Successful fallback text says to hand control back explicitly when ready. Reconnect does not clear the pause.

The live console mirrors status at its existing rate of at most 15 Hz. Its current-controller proxy forwards actions only to an already attached Director and reads that instance again at the action boundary. Disabled or detached controls do not instantiate a lazy Director. An old painted notice cannot consume Escape after the actual notice disappeared or became an uncancellable Backup notice.

A compact control row occupies the existing space between input tiles and the operator pill, keeping the 1280×800 layout. Manual takeover remains visible. Command Shift H hands back or takes over; the single current cancellable Auto notice owns Escape. Refusals remain visible and accessible. Backup next-cut notices show the target without a countdown or Cancel action.

The gallery provides four synthetic outcome cards, including both possible destination inputs. These cards are illustrations; live alert correctness is exercised through synthetic Take/router tests and still needs an attended physical fault drill. No production qualification or threshold is created by the UI.
