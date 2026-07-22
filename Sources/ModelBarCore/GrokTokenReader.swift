import Foundation

public struct GrokLocalTokenReader: ProviderTokenReading {
    public let sessionsDirectory: URL
    public let maximumFiles: Int

    public init(sessionsDirectory: URL, maximumFiles: Int = 5_000) {
        self.sessionsDirectory = sessionsDirectory
        self.maximumFiles = maximumFiles
    }

    public func read(
        using runner: any CommandRunning,
        now: Date
    ) async throws -> TokenUsage {
        try await Task.detached(priority: .utility) {
            try readBlocking(now: now)
        }.value
    }

    private func readBlocking(now: Date) throws -> TokenUsage {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: sessionsDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return TokenUsage(
                recentTokens: 0,
                sevenDayTokens: 0,
                recentLabel: "24h",
                qualifier: "local"
            )
        }

        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .isRegularFileKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw GrokTokenError.unreadableDirectory
        }

        let oneDayAgo = now.addingTimeInterval(-86_400)
        let sevenDaysAgo = now.addingTimeInterval(-604_800)
        var recent: Int64 = 0
        var sevenDays: Int64 = 0
        var inspected = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "signals.json" else {
                continue
            }
            inspected += 1
            if inspected > maximumFiles {
                throw GrokTokenError.fileLimitExceeded
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= sevenDaysAgo,
                  let tokens = try? tokenCount(at: fileURL) else {
                continue
            }
            sevenDays += tokens
            if modifiedAt >= oneDayAgo {
                recent += tokens
            }
        }

        return TokenUsage(
            recentTokens: recent,
            sevenDayTokens: sevenDays,
            recentLabel: "24h",
            qualifier: "local"
        )
    }

    private func tokenCount(at url: URL) throws -> Int64 {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokTokenError.invalidFile
        }
        let context = (object["contextTokensUsed"] as? NSNumber)?.int64Value ?? 0
        let compacted = (object["totalTokensBeforeCompaction"] as? NSNumber)?.int64Value ?? 0
        return max(0, context) + max(0, compacted)
    }
}

public enum GrokTokenError: Error {
    case unreadableDirectory
    case fileLimitExceeded
    case invalidFile
}
