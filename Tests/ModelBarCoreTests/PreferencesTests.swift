import Foundation
import XCTest
@testable import ModelBarCore

final class PreferencesTests: XCTestCase {
    func testFutureIdentifiersDefaultToVisible() {
        let preferences = ModelBarPreferences(
            disabledProviderIDs: ["claude"],
            hiddenAgentIDs: ["frank"]
        )

        XCTAssertFalse(preferences.isProviderEnabled("claude"))
        XCTAssertTrue(preferences.isProviderEnabled("future-provider"))
        XCTAssertFalse(preferences.isAgentVisible("frank"))
        XCTAssertTrue(preferences.isAgentVisible("future-profile"))
    }

    func testPreferencesRoundTripThroughUserDefaults() throws {
        let suiteName = "ModelBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferencesStore(defaults: defaults)
        let expected = ModelBarPreferences(
            disabledProviderIDs: ["grok"],
            hiddenAgentIDs: ["oscar", "chad"],
            refreshInterval: .sixtyMinutes
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testUnknownRefreshIntervalFallsBackToFifteenMinutes() throws {
        let suiteName = "ModelBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(42, forKey: "refreshInterval")

        XCTAssertEqual(
            PreferencesStore(defaults: defaults).load().refreshInterval,
            .fifteenMinutes
        )
    }

    func testRefreshIntervalsMapToExpectedDurations() {
        XCTAssertNil(RefreshInterval.manual.seconds)
        XCTAssertEqual(RefreshInterval.fifteenMinutes.seconds, 900)
        XCTAssertEqual(RefreshInterval.thirtyMinutes.seconds, 1_800)
        XCTAssertEqual(RefreshInterval.sixtyMinutes.seconds, 3_600)
    }
}
