import XCTest
@testable import TopologyCore

final class OpenSwitchFeaturePolicyTests: XCTestCase {
    func testRemovedAutomationsAreOffAndChosenFeaturesStayOn() {
        var saved = OpenDisplaySettings.default
        saved.autoDisconnectBuiltInOnExternal = true
        saved.adaptiveWarmthEnabled = true
        saved.adaptiveLocationModeEnabled = true
        saved.clockScheduleEnabled = true
        saved.appPresetsEnabled = true
        saved.xdrBrightnessEnabled = true
        saved.layoutProtectionEnabled = true
        saved.adaptiveBrightnessSyncEnabled = true
        saved.mediaKeyInterceptionEnabled = true
        saved.preventDisplaySleepWithExternal = true
        saved.publishOSDEventsEnabled = true
        saved.osdStyle = .external
        saved.displayGroups = [DisplayGroup(name: "Test displays", syncBrightness: true, syncContrast: true)]
        let result = OpenSwitchFeaturePolicy.applying(to: saved)
        XCTAssertFalse(result.autoDisconnectBuiltInOnExternal)
        XCTAssertFalse(result.adaptiveWarmthEnabled)
        XCTAssertFalse(result.adaptiveLocationModeEnabled)
        XCTAssertFalse(result.clockScheduleEnabled)
        XCTAssertFalse(result.appPresetsEnabled)
        XCTAssertFalse(result.xdrBrightnessEnabled)
        XCTAssertFalse(result.layoutProtectionEnabled)
        XCTAssertTrue(result.adaptiveBrightnessSyncEnabled)
        XCTAssertTrue(result.mediaKeyInterceptionEnabled)
        XCTAssertTrue(result.preventDisplaySleepWithExternal)
        XCTAssertFalse(result.publishOSDEventsEnabled)
        XCTAssertEqual(result.osdStyle, .native)
        XCTAssertEqual(result.displayGroups.count, 1)
        XCTAssertEqual(result.displayGroups[0].id, saved.displayGroups[0].id)
        XCTAssertFalse(result.displayGroups[0].syncBrightness)
        XCTAssertFalse(result.displayGroups[0].syncContrast)
        XCTAssertEqual(result.hotkeyShortcuts, saved.hotkeyShortcuts)
        XCTAssertEqual(result.adaptiveDayPresetByDisplay, saved.adaptiveDayPresetByDisplay)
        XCTAssertEqual(result.appPresetPriorStateByDisplay, saved.appPresetPriorStateByDisplay)
    }

    func testApplyingPolicyTwiceDoesNotChangeSettingsAgain() {
        var saved = OpenDisplaySettings.default
        saved.clockScheduleEnabled = true
        let once = OpenSwitchFeaturePolicy.applying(to: saved)
        XCTAssertEqual(OpenSwitchFeaturePolicy.applying(to: once), once)
    }
}
