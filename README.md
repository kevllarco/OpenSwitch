# OpenSwitch

OpenSwitch is a macOS menu-bar app for switching a monitor and configured keyboard and mouse between computers. It combines monitor input switching over DDC/CI with Logitech Easy-Switch handoff, global shortcuts, a switching HUD, and guided setup between nearby Macs.

The app also retains selected OpenDisplay monitor controls, including brightness, contrast, volume, colour, resolution, refresh rate, and software dimming. OpenSwitch focuses on computer switching while keeping these useful display controls.

## Project status

OpenSwitch is an early-stage project. You can build it from source and try it on your own setup. There is no prebuilt public app download yet. The code is based on [OpenDisplay](https://github.com/aquitaine/OpenDisplay) and retains its GPL-3.0 license and contributor attribution. OpenSwitch is an independent project and is not affiliated with the OpenDisplay maintainers.

The app has been exercised on a two-Mac setup with an LG display and Logitech keyboard and mouse. Other display and peripheral combinations need hardware testing before they can be described as supported.

## Build on macOS

Requirements: Xcode, Xcode Command Line Tools, and XcodeGen.

```sh
xcodegen generate --spec project.yml
xcodebuild -project OpenDisplay.xcodeproj -scheme OpenDisplay -configuration Debug build
```

The cross-platform Swift packages can be built and tested separately:

```sh
swift build
swift test
```

Development signing and installation are machine-specific. Do not commit signing identities, private update keys, pairing codes, or signed application bundles.

## Project notes

- [Guided computer setup](Docs/COMPUTER-SETUP-DESIGN.md)
- [Kept and removed settings](Docs/SETTINGS-DIRECTION.md)
- [Input hotkeys](Docs/INPUT_HOTKEYS.md)
- [Upstream project](https://github.com/aquitaine/OpenDisplay)

## License

OpenSwitch remains under GNU GPL version 3 or later, as specified in [LICENSE](LICENSE). Preserve upstream notices and mark changes when redistributing modified versions.
