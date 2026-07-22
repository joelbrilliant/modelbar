import Foundation
import XCTest
@testable import ModelBarCore

final class GrokTokenReaderTests: XCTestCase {
    func testMissingSessionsDirectoryIsAValidZero() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelBarMissing-\(UUID().uuidString)")
        let reader = GrokLocalTokenReader(sessionsDirectory: directory)

        let tokens = try await reader.read(using: UnusedRunner(), now: Date())

        XCTAssertEqual(tokens.recentTokens, 0)
        XCTAssertEqual(tokens.sevenDayTokens, 0)
    }

    func testReadsOnlyValidSignalsInsideTheSevenDayWindow() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        try writeSignal(
            at: directory.appendingPathComponent("recent/signals.json"),
            context: 100,
            compacted: 20,
            modifiedAt: now.addingTimeInterval(-3_600)
        )
        try writeSignal(
            at: directory.appendingPathComponent("week/signals.json"),
            context: 50,
            compacted: 0,
            modifiedAt: now.addingTimeInterval(-172_800)
        )
        try writeSignal(
            at: directory.appendingPathComponent("old/signals.json"),
            context: 999,
            compacted: 0,
            modifiedAt: now.addingTimeInterval(-691_200)
        )
        let malformed = directory.appendingPathComponent("broken/signals.json")
        try FileManager.default.createDirectory(
            at: malformed.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: malformed)
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: malformed.path
        )

        let reader = GrokLocalTokenReader(sessionsDirectory: directory)
        let tokens = try await reader.read(using: UnusedRunner(), now: now)

        XCTAssertEqual(tokens.recentTokens, 120)
        XCTAssertEqual(tokens.sevenDayTokens, 170)
        XCTAssertEqual(tokens.qualifier, "local")
    }

    private func writeSignal(
        at url: URL,
        context: Int,
        compacted: Int,
        modifiedAt: Date
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let object: [String: Any] = [
            "contextTokensUsed": context,
            "totalTokensBeforeCompaction": compacted,
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: url.path
        )
    }
}
