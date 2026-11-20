# Input-switching device compatibility

This catalog tracks evidence for the two hardware parts OpenSwitch switches: monitor inputs and
Logitech keyboard/mouse hosts. It does not treat a feature advertised by a manufacturer or support
in another app as proof that the complete setup works in OpenSwitch.

## Confidence labels

| Label | Meaning |
| --- | --- |
| **Verified in OpenSwitch** | OpenSwitch successfully performed the listed action on the named setup. |
| **Protocol evidence** | Another implementation has sent the needed protocol command to the model; OpenSwitch has not been verified with it. |
| **Candidate to probe** | The model has a related feature, but we have not confirmed the required command path. |
| **No evidence yet** | No useful compatibility evidence has been collected. |

## Logitech keyboards and mice

OpenSwitch looks for Logitech HID++ **ChangeHost** support (`0x1814`). Logitech Easy-Switch is a
good way to find multi-host models, but Easy-Switch by itself does not prove that the model exposes
the remote ChangeHost command OpenSwitch needs.

| Model | Type | Evidence | OpenSwitch status |
| --- | --- | --- | --- |
| MX Mechanical | Keyboard | ChangeHost detected and both-way switching exercised | **Verified in OpenSwitch** |
| MX Master 3S | Mouse | ChangeHost detected and both-way switching exercised | **Verified in OpenSwitch** |
| MX Keys | Keyboard | [Community HID++ ChangeHost command documented](https://github.com/marcelhoffs/input-switcher) | **Protocol evidence** |
| MX Keys S | Keyboard | [Community HID++ ChangeHost command documented](https://github.com/marcelhoffs/input-switcher); feature index differs by device | **Protocol evidence** |
| MX Anywhere 3 | Mouse | [Community HID++ ChangeHost command documented](https://github.com/marcelhoffs/input-switcher) | **Protocol evidence** |
| MX Anywhere 3S | Mouse | [Community HID++ ChangeHost command documented](https://github.com/marcelhoffs/input-switcher) | **Protocol evidence** |
| MX Keys for Business, MX Keys Mini, MK850, K780, Wave Keys, ERGO K860, POP Keys, K580, Keys-To-Go 2 | Keyboards | [Logitech lists Easy-Switch](https://www.logitech.com/en-gb/discover/a/easy-switch-technology); ChangeHost command has not been confirmed here | **Candidate to probe** |
| LIFT, MX Ergo S, Pebble Mouse 2 M350s | Mice | [Logitech lists Easy-Switch](https://www.logitech.com/en-gb/discover/a/easy-switch-technology); ChangeHost command has not been confirmed here | **Candidate to probe** |

The **Protocol evidence** rows come from third-party HID++ command examples, not OpenSwitch
testing. Connection variants also matter: the same product may behave differently through direct
Bluetooth, Logi Bolt, Unifying, or another receiver. Report the exact connection used.

## Monitors

| Model | Evidence | OpenSwitch status |
| --- | --- | --- |
| LG UltraWide (exact model not recorded) | DDC/CI input switching exercised as part of the maintainer's two-Mac setup | **Verified in OpenSwitch** |
| LG 27UL850 | [BetterDisplay discussion](https://github.com/waydabber/BetterDisplay/discussions/3725) reports input switching trouble on USB-C with default values and recommends checking model-specific input values | **Unverified report; investigate per connection** |

For monitor input switching, useful evidence is whether the monitor exposes DDC/CI VCP `0x60`
(Input Source), which values select each port, and whether the command reaches the monitor through
the tested Mac, dock, hub, adapter, and cable. DDC/CI brightness support alone is not enough.
Input values and DDC pass-through can vary by model and connection path, so we are not assigning
compatibility by brand.

## Other KVM hardware

No third-party USB switch or hardware KVM model is currently listed as supported. These devices
often need a model-specific control interface, so list one only after its control path is known
and tested with OpenSwitch.

## Sources and what they establish

| Source | Useful evidence | What it does not prove |
| --- | --- | --- |
| [Logitech Easy-Switch guide](https://www.logitech.com/en-gb/discover/a/easy-switch-technology) | Official list of selected multi-host keyboard and mouse models | That a model exposes HID++ ChangeHost or works with OpenSwitch |
| [Logitech HID++ documentation](https://github.com/Logitech/cpg-docs/tree/master/hidpp20) | Defines the HID++ feature protocol, including Change Host (`0x1814`) | A complete current product-by-product compatibility table |
| [Solaar device documentation](https://pwr-solaar.github.io/Solaar/devices/) and [feature list](https://github.com/pwr-Solaar/Solaar/blob/master/docs/features.md) | Broad community device/receiver data and implementation of ChangeHost; helpful for finding models and protocol variations | OpenSwitch behavior on macOS or every device/transport combination |
| [input-switcher](https://github.com/marcelhoffs/input-switcher) | Community ChangeHost examples for named models and transports | Maintainer verification in OpenSwitch |
| [MonitorControl troubleshooting](https://github.com/MonitorControl/MonitorControl/wiki/Monitor-Troubleshooting) | Real-world DDC/CI and connection-path limitations | A model-specific input-switch result for OpenSwitch |
| [BetterDisplay LG 27UL850 discussion](https://github.com/waydabber/BetterDisplay/discussions/3725) | Model/port-specific input-value troubleshooting | A general result for other LG models or ports |
| [ddcutil monitor notes](https://www.ddcutil.com/archived/monitor_notes/) | Historical user-reported monitor DDC quirks | A current certification list for input switching |

## How to add evidence

For a device we do not own, request a volunteer report with the exact model, connection type,
firmware when available, macOS and OpenSwitch versions, and the monitor/cable/dock route. Start
with a read-only capability probe. If it finds the required feature, ask the owner to perform a
controlled switch with a recovery path ready. For a combined setup, verify monitor, keyboard, and
mouse separately and then together in both directions; repeat after sleep and wake.

Record **Protocol evidence**, **Works on one setup**, and **Maintainer verified** as separate
levels. A volunteer's successful report is valuable evidence, but only a maintainer-reproduced
setup should receive the final label. Never request serial numbers, pairing codes, or private keys.
Use the [Compatibility report form](../../.github/ISSUE_TEMPLATE/compatibility_report.yml) to
submit results.
