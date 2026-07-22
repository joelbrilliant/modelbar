import Foundation
import SQLite3
import XCTest
@testable import ModelBarCore

final class HermesTokenReaderTests: XCTestCase {
    func testDiscoversOnlyLiveRootAndImmediateProfiles() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        try createCurrentDatabase(at: home.appendingPathComponent("state.db"), now: Date())
        try createLegacyDatabase(
            at: home.appendingPathComponent("profiles/rusty/state.db"),
            now: Date()
        )
        try createLegacyDatabase(
            at: home.appendingPathComponent("backups/old/state.db"),
            now: Date()
        )

        let profiles = HermesTokenReader(hermesHome: home).discoverProfiles()

        XCTAssertEqual(profiles.map(\.id), ["default", "rusty"])
        XCTAssertEqual(profiles.map(\.displayName), ["Rocky", "Rusty"])
    }

    func testReconcilesAuxiliaryUsageAndPositiveSessionResiduals() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try createCurrentDatabase(at: home.appendingPathComponent("state.db"), now: now)

        let snapshots = await HermesTokenReader(hermesHome: home).fetch(now: now)
        let rocky = try XCTUnwrap(snapshots.first)

        XCTAssertEqual(rocky.tokens?.recentTokens, 185)
        XCTAssertEqual(rocky.tokens?.sevenDayTokens, 215)
        XCTAssertFalse(rocky.usesLegacySchema)
    }

    func testLegacyProfileFallsBackToSessionAggregate() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try createLegacyDatabase(
            at: home.appendingPathComponent("profiles/rusty/state.db"),
            now: now
        )

        let snapshots = await HermesTokenReader(hermesHome: home).fetch(now: now)
        let rusty = try XCTUnwrap(snapshots.first)

        XCTAssertEqual(rusty.tokens?.recentTokens, 15)
        XCTAssertEqual(rusty.tokens?.sevenDayTokens, 15)
        XCTAssertTrue(rusty.usesLegacySchema)
    }

    func testUnreadableProfileDoesNotHideHealthyProfiles() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try createCurrentDatabase(at: home.appendingPathComponent("state.db"), now: now)
        let broken = home.appendingPathComponent("profiles/broken/state.db")
        try FileManager.default.createDirectory(
            at: broken.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not sqlite".utf8).write(to: broken)

        let snapshots = await HermesTokenReader(hermesHome: home).fetch(now: now)

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertNotNil(snapshots.first { $0.id == "default" }?.tokens)
        XCTAssertEqual(
            snapshots.first { $0.id == "broken" }?.issue?.kind,
            .unavailable
        )
    }

    func testReadDoesNotChangeDatabaseSizeOrModificationTime() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = home.appendingPathComponent("state.db")
        try createCurrentDatabase(at: database, now: now)
        let fixedModificationDate = Date(timeIntervalSince1970: 1_900_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: database.path
        )
        let before = try database.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
        ])

        _ = await HermesTokenReader(hermesHome: home).fetch(now: now)

        let after = try database.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
        ])
        XCTAssertEqual(after.fileSize, before.fileSize)
        XCTAssertEqual(after.contentModificationDate, before.contentModificationDate)
    }

    private func createCurrentDatabase(at url: URL, now: Date) throws {
        let database = try openWritableDatabase(at: url)
        defer { sqlite3_close(database) }
        try execute(database, """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                started_at REAL,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_write_tokens INTEGER
            );
            CREATE TABLE session_model_usage (
                session_id TEXT,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_write_tokens INTEGER
            );
            INSERT INTO sessions VALUES
                ('recent', \(now.timeIntervalSince1970 - 3600), 100, 50, 10, 5),
                ('older', \(now.timeIntervalSince1970 - 172800), 20, 10, 0, 0);
            INSERT INTO session_model_usage VALUES
                ('recent', 80, 40, 2, 0),
                ('recent', 40, 0, 0, 0);
            """)
    }

    private func createLegacyDatabase(at url: URL, now: Date) throws {
        let database = try openWritableDatabase(at: url)
        defer { sqlite3_close(database) }
        try execute(database, """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                started_at REAL,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_write_tokens INTEGER
            );
            INSERT INTO sessions VALUES
                ('legacy', \(now.timeIntervalSince1970 - 3600), 10, 5, 0, 0);
            """)
    }

    private func openWritableDatabase(at url: URL) throws -> OpaquePointer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw TestDatabaseError.openFailed
        }
        return database
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestDatabaseError.statementFailed
        }
    }
}

private enum TestDatabaseError: Error {
    case openFailed
    case statementFailed
}
