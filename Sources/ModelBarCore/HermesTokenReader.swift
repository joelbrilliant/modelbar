import Foundation
import SQLite3

public protocol AgentTokenSource: Sendable {
    func fetch(now: Date) async -> [AgentTokenSnapshot]
}

public struct HermesTokenReader: AgentTokenSource {
    public let hermesHome: URL

    public init(hermesHome: URL) {
        self.hermesHome = hermesHome
    }

    public func fetch(now: Date) async -> [AgentTokenSnapshot] {
        await Task.detached(priority: .utility) {
            fetchBlocking(now: now)
        }.value
    }

    public func discoverProfiles() -> [HermesProfile] {
        var profiles: [HermesProfile] = []
        let rootDatabase = hermesHome.appendingPathComponent("state.db")
        if FileManager.default.fileExists(atPath: rootDatabase.path) {
            profiles.append(
                HermesProfile(id: "default", displayName: "Rocky", databaseURL: rootDatabase)
            )
        }

        let profilesDirectory = hermesHome.appendingPathComponent(
            "profiles",
            isDirectory: true
        )
        let children = (try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for directory in children {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let database = directory.appendingPathComponent("state.db")
            guard FileManager.default.fileExists(atPath: database.path) else {
                continue
            }
            let id = directory.lastPathComponent
            profiles.append(
                HermesProfile(
                    id: id,
                    displayName: id.capitalized,
                    databaseURL: database
                )
            )
        }

        let priority = ["default", "frank", "chad", "oscar"]
        return profiles.sorted { left, right in
            let leftIndex = priority.firstIndex(of: left.id) ?? Int.max
            let rightIndex = priority.firstIndex(of: right.id) ?? Int.max
            if leftIndex != rightIndex {
                return leftIndex < rightIndex
            }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }

    private func fetchBlocking(now: Date) -> [AgentTokenSnapshot] {
        discoverProfiles().map { profile in
            do {
                let result = try readTokens(databaseURL: profile.databaseURL, now: now)
                return AgentTokenSnapshot(
                    id: profile.id,
                    displayName: profile.displayName,
                    tokens: TokenUsage(
                        recentTokens: result.recent,
                        sevenDayTokens: result.sevenDays,
                        recentLabel: "24h"
                    ),
                    issue: nil,
                    usesLegacySchema: result.legacy,
                    fetchedAt: now
                )
            } catch {
                return AgentTokenSnapshot(
                    id: profile.id,
                    displayName: profile.displayName,
                    tokens: nil,
                    issue: SourceIssue(
                        kind: .unavailable,
                        message: "Token totals unavailable"
                    ),
                    usesLegacySchema: false,
                    fetchedAt: now
                )
            }
        }
    }

    private func readTokens(
        databaseURL: URL,
        now: Date
    ) throws -> (recent: Int64, sevenDays: Int64, legacy: Bool) {
        var database: OpaquePointer?
        let uri = databaseURL.absoluteString + "?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &database, flags, nil) == SQLITE_OK,
              let database else {
            if database != nil {
                sqlite3_close(database)
            }
            throw HermesTokenError.openFailed
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 250)
        guard sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil) == SQLITE_OK else {
            throw HermesTokenError.queryFailed
        }

        let hasUsageTable = try tableExists("session_model_usage", database: database)
        let recentCutoff = now.timeIntervalSince1970 - 86_400
        let sevenDayCutoff = now.timeIntervalSince1970 - 604_800
        let recent = try totalTokens(
            since: recentCutoff,
            database: database,
            hasUsageTable: hasUsageTable
        )
        let sevenDays = try totalTokens(
            since: sevenDayCutoff,
            database: database,
            hasUsageTable: hasUsageTable
        )
        return (recent, sevenDays, !hasUsageTable)
    }

    private func tableExists(
        _ tableName: String,
        database: OpaquePointer
    ) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesTokenError.queryFailed
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, tableName, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func totalTokens(
        since cutoff: TimeInterval,
        database: OpaquePointer,
        hasUsageTable: Bool
    ) throws -> Int64 {
        let sql = hasUsageTable ? Self.reconciledTokenSQL : Self.legacyTokenSQL
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesTokenError.queryFailed
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HermesTokenError.queryFailed
        }
        return max(0, sqlite3_column_int64(statement, 0))
    }

    private static let legacyTokenSQL = """
        SELECT COALESCE(SUM(
            COALESCE(input_tokens, 0) +
            COALESCE(output_tokens, 0) +
            COALESCE(cache_read_tokens, 0) +
            COALESCE(cache_write_tokens, 0)
        ), 0)
        FROM sessions
        WHERE started_at >= ?
        """

    private static let reconciledTokenSQL = """
        WITH selected_sessions AS (
            SELECT id,
                COALESCE(input_tokens, 0) AS input_tokens,
                COALESCE(output_tokens, 0) AS output_tokens,
                COALESCE(cache_read_tokens, 0) AS cache_read_tokens,
                COALESCE(cache_write_tokens, 0) AS cache_write_tokens
            FROM sessions
            WHERE started_at >= ?
        ),
        usage_by_session AS (
            SELECT usage.session_id,
                SUM(COALESCE(usage.input_tokens, 0)) AS input_tokens,
                SUM(COALESCE(usage.output_tokens, 0)) AS output_tokens,
                SUM(COALESCE(usage.cache_read_tokens, 0)) AS cache_read_tokens,
                SUM(COALESCE(usage.cache_write_tokens, 0)) AS cache_write_tokens
            FROM session_model_usage usage
            JOIN selected_sessions session ON session.id = usage.session_id
            GROUP BY usage.session_id
        )
        SELECT COALESCE(SUM(
            MAX(session.input_tokens, COALESCE(usage.input_tokens, 0)) +
            MAX(session.output_tokens, COALESCE(usage.output_tokens, 0)) +
            MAX(session.cache_read_tokens, COALESCE(usage.cache_read_tokens, 0)) +
            MAX(session.cache_write_tokens, COALESCE(usage.cache_write_tokens, 0))
        ), 0)
        FROM selected_sessions session
        LEFT JOIN usage_by_session usage ON usage.session_id = session.id
        """
}

public struct HermesProfile: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let databaseURL: URL

    public init(id: String, displayName: String, databaseURL: URL) {
        self.id = id
        self.displayName = displayName
        self.databaseURL = databaseURL
    }
}

public enum HermesTokenError: Error {
    case openFailed
    case queryFailed
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
