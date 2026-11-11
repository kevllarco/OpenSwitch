import Foundation

/// Migrate removed feature switches off without deleting settings or recovery data.
public enum OpenSwitchFeaturePolicy {
    public static func applying(to saved: OpenDisplaySettings) -> OpenDisplaySettings {
        var result = saved
        result.autoDisconnectBuiltInOnExternal = false
        result.adaptiveWarmthEnabled = false
        result.adaptiveLocationModeEnabled = false
        result.clockScheduleEnabled = false
        result.appPresetsEnabled = false
        result.xdrBrightnessEnabled = false
        result.layoutProtectionEnabled = false
        result.publishOSDEventsEnabled = false
        if result.osdStyle == .external { result.osdStyle = .native }
        result.displayGroups = result.displayGroups.map { group in
            var disabled = group
            disabled.syncBrightness = false
            disabled.syncContrast = false
            return disabled
        }
        return result
    }
}
