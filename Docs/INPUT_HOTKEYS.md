# Input hotkeys on monitors with non-standard input commands

Settings → Health & Recovery → Input hotkeys supports two explicit command modes:

- **Standard DDC:** VCP `0x60`, source address `0x51`. Existing bindings retain this behavior.
- **LG alternate:** VCP `0xF4`, source address `0x50`. Select this only for a monitor known to support it.

LG input values vary by model. `0xD1` is DP2/USB-C on many models, while others use `0xD2`,
`0xC0`, or `0xE0`. The menu deliberately does not infer an exact USB-C value from the vendor
name. Both modes offer a custom hexadecimal value (`0` through `FFFF`, optional `0x` prefix).
The dedicated “USB-C (LG alt)” menu option uses `0xD2` (decimal 210), matching
BetterDisplay's default entry with that name. It is distinct from DP2/USB-C (`0xD1`, 209).
The public protocol notes and model reports are here:
https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors

To change an existing binding, remove it and add it again with the same shortcut and the
correct command mode/value. Use the known working value from another utility or a report
for your exact model. Do not cycle through unknown manufacturer commands.

Use **Test** beside the binding to send that command without the keyboard shortcut. If Test
works but the shortcut does not, check for another app claiming the chord. Failed Carbon
registrations appear as unavailable in the row and generate a notification. This status is
independent of Accessibility permission: Carbon hotkeys do not need that permission.

The “Sent” OSD means the transport accepted the write, not that the monitor changed input.
LG alternate writes do not populate the standard VCP `0x60` read cache, because these are
different registers/channels. Reads and brightness/volume writes continue using `0x51`;
the alternate source address applies to the selected input write only, under the same bus
lock and pacing as other DDC operations.

The target must be in the live macOS display list with a usable DDC channel. A powered-down
or disconnected input may not expose a channel; this patch cannot promise to switch a monitor
back to a Mac that macOS no longer sees. Existing display identity behavior is unchanged.

## Hardware verification before release

1. Confirm an old settings file still registers its original binding with Standard DDC.
2. On a supported LG, configure the exact known alternate value and press Test. Observe
   the physical input change; do not count the OSD alone as verification.
3. Restore the original input using the monitor controls/known working utility; exercise
   the same binding using its global shortcut and observe the physical input change.
4. Confirm brightness and volume still work on their standard channels.
5. Claim a chord in another app, then add the same chord here; confirm the unavailable
   message appears. Release it, re-register the binding and confirm the warning clears.
6. Run `make test`, SwiftLint and both full/public-API-only Xcode builds before release.

## Active computer indicator

The menu checkmark and optional menu-bar label follow the configured Logitech keyboard and mouse.
OpenSwitch observes their native HID connections and activity without taking exclusive control.
Only device names, connected flags, and elapsed time since activity are exchanged through the
existing paired, authenticated TLS connection. No key contents, coordinates, or event history are
retained. A fresh challenge authenticates each status response; availability checks remain compatible.

Recent input confirms ownership when devices remain enumerated on more than one host. Connection
reports can establish ownership when every configured peer responds and only one has each device.
Both configured devices must agree. A split shows a warning; idle or sleeping devices preserve the
last confirmed selection. The indicator describes input-device ownership, not monitor verification.

The saved pairing key remains in Keychain. The signed `desk-switch-keychain` helper starts only to
read that item, validates the parent app's identifier and signing certificate, and exits after the
read. Its code hash remains stable across ordinary app builds; rebuilds of the helper itself may
require renewed Keychain approval. Run `Tools/DeskSwitchKeychain/check-helper.sh` for the helper's
hash and caller-identity checks.
