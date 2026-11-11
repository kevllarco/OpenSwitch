# OpenSwitch settings decisions

The settings redesign uses native macOS grouped forms and a sidebar. Computer switching profiles,
pairing, menu-bar presentation, switching HUD, troubleshooting, and attribution remain available.

## Decisions made with the user

Keep monitor brightness, volume, contrast, and color controls; keep brightness matching to the
built-in display as one toggle; keep the hardware brightness and volume key integration; keep the option to prevent display sleep while an external display is connected. Keep display connection and disconnection notifications as an optional setting. Keep resolution, refresh-rate, and software dimming controls.

Remove favorite resolutions, third-party HUD integration, display groups, manual display disconnect and rotation controls, display arrangement and protected layouts, Scenes, automatic evening warmth, brightness
schedules, location-based brightness, app-specific presets, XDR brightness boost, and automatic
built-in-display shutdown when an external display connects. `OpenSwitchFeaturePolicy` disables
these removed automation switches at launch without deleting saved configurations or recovery
state. Any owed app-preset and color-preset restorations still run. Brightness matching waits for a
built-in brightness reading instead of applying a hidden schedule when that reading is unavailable.

## Still to review with the user

Recovery for displays disconnected by older versions remains available when needed. This completes the current list of features to review.

The current UI no longer exposes Scenes or arrangement. Some inherited engine and compatibility
code remains in the fork; further source cleanup requires dependency and recovery review.
