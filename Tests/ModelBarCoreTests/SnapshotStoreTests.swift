import Foundation
import XCTest
@testable import ModelBarCore

final class SnapshotStoreTests: XCTestCase {
    func testLoadsPreBrandSnapshotCache() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json")
        let legacyJSON = """
        {
          "agents": [],
          "providers": [{
            "displayName": "Future",
            "fetchedAt": 100,
            "id": "future",
            "isStale": false,
            "quotaWindows": []
          }],
          "refreshedAt": 100
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)
        let store = SnapshotStore(fileURL: fileURL)

        let snapshot = await store.load()

        XCTAssertEqual(snapshot?.providers[0].displayName, "Future")
        XCTAssertNil(snapshot?.providers[0].brand)
    }

    func testUnchangedDisplayContentDoesNotWriteAgain() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        let first = sampleSnapshot(at: Date(timeIntervalSince1970: 100))
        let second = sampleSnapshot(at: Date(timeIntervalSince1970: 200))

        let firstWrite = try await store.saveIfDisplayChanged(first)
        let secondWrite = try await store.saveIfDisplayChanged(second)

        XCTAssertTrue(firstWrite)
        XCTAssertFalse(secondWrite)
    }

    private func sampleSnapshot(at date: Date) -> ModelBarSnapshot {
        ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "codex",
                    displayName: "OpenAI",
                    quotaWindows: [
                        QuotaWindow(name: "Weekly", usedPercent: 50, resetsAt: nil),
                    ],
                    tokens: nil,
                    serviceStatus: nil,
                    issue: nil,
                    fetchedAt: date
                ),
            ],
            agents: [],
            refreshedAt: date
        )
    }
}
