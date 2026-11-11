# OpenSwitch UI preview

This separate development project previews the real menu header and row components with sample data. It does not create `AppModel`, register global shortcuts, read app settings or pairing secrets, or issue display, network, or Logitech commands. The buttons update preview-only text.

Generate the project from this directory with `xcodegen generate`, then open `OpenSwitchUI.xcodeproj` in Xcode and select `SwitchMenuPreview.swift` to use its preview canvas. Xcode's license and first-run setup must be complete. The generated project is ignored by Git and can be regenerated. The preview has its own bundle identifier and is not the installed OpenSwitch app.

For a command-line smoke test using only the macOS Command Line Tools, compile the two preview sources and `../../Apps/OpenDisplay/Sources/SwitchMenuComponents.swift` with `swiftc -swift-version 6 -D OPENSWITCH_STANDALONE`. The flag omits the Xcode-only preview macro.
