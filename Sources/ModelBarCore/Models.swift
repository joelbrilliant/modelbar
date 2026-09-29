import Foundation

public enum SourceIssueKind: String, Codable, Sendable {
    case authentication
    case timeout
    case network
    case provider
    case unavailable
    case invalidData
}

public struct SourceIssue: Codable, Equatable, Sendable {
    public let kind: SourceIssueKind
    public let message: String

    public init(kind: SourceIssueKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let name: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(name: String, usedPercent: Double, resetsAt: Date?) {
        self.name = name
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        100 - usedPercent
    }

    /// A window that has never been used and has no reset time. The menu
    /// hides these; a 0%-used window that carries a reset time is real.
    public var isUnused: Bool {
        usedPercent == 0 && resetsAt == nil
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public let recentTokens: Int64
    public let sevenDayTokens: Int64
    public let recentLabel: String
    public let qualifier: String?

    public init(
        recentTokens: Int64,
        sevenDayTokens: Int64,
        recentLabel: String,
        qualifier: String? = nil
    ) {
        self.recentTokens = max(0, recentTokens)
        self.sevenDayTokens = max(0, sevenDayTokens)
        self.recentLabel = recentLabel
        self.qualifier = qualifier
    }
}

public enum ServiceCondition: String, Codable, Sendable {
    case operational
    case degraded
    case outage
    case unknown
}

public struct ServiceStatus: Codable, Equatable, Sendable {
    public let condition: ServiceCondition
    public let description: String
    public let url: URL?

    public init(condition: ServiceCondition, description: String, url: URL?) {
        self.condition = condition
        self.description = description
        self.url = url
    }
}

public struct ProviderBrandColour: Codable, Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct ProviderBrand: Codable, Equatable, Sendable {
    public let lightModeAccent: ProviderBrandColour
    public let darkModeAccent: ProviderBrandColour

    public init(
        lightModeAccent: ProviderBrandColour,
        darkModeAccent: ProviderBrandColour
    ) {
        self.lightModeAccent = lightModeAccent
        self.darkModeAccent = darkModeAccent
    }

    public static let openAI = ProviderBrand(
        lightModeAccent: ProviderBrandColour(red: 16, green: 163, blue: 127),
        darkModeAccent: ProviderBrandColour(red: 16, green: 163, blue: 127)
    )
    public static let claude = ProviderBrand(
        lightModeAccent: ProviderBrandColour(red: 217, green: 119, blue: 87),
        darkModeAccent: ProviderBrandColour(red: 217, green: 119, blue: 87)
    )
    public static let grok = ProviderBrand(
        lightModeAccent: ProviderBrandColour(red: 31, green: 31, blue: 31),
        darkModeAccent: ProviderBrandColour(red: 240, green: 240, blue: 240)
    )
}

public struct ProviderReading: Equatable, Sendable {
    public let quotaWindows: [QuotaWindow]
    public let tokens: TokenUsage?
    public let serviceStatus: ServiceStatus?
    public let issue: SourceIssue?

    public init(
        quotaWindows: [QuotaWindow],
        tokens: TokenUsage?,
        serviceStatus: ServiceStatus?,
        issue: SourceIssue?
    ) {
        self.quotaWindows = quotaWindows
        self.tokens = tokens
        self.serviceStatus = serviceStatus
        self.issue = issue
    }
}

public struct ProviderSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public var brand: ProviderBrand?
    public var quotaWindows: [QuotaWindow]
    public var tokens: TokenUsage?
    public var serviceStatus: ServiceStatus?
    public var issue: SourceIssue?
    public var fetchedAt: Date
    public var isStale: Bool

    public init(
        id: String,
        displayName: String,
        brand: ProviderBrand? = nil,
        quotaWindows: [QuotaWindow],
        tokens: TokenUsage?,
        serviceStatus: ServiceStatus?,
        issue: SourceIssue?,
        fetchedAt: Date,
        isStale: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.brand = brand
        self.quotaWindows = quotaWindows
        self.tokens = tokens
        self.serviceStatus = serviceStatus
        self.issue = issue
        self.fetchedAt = fetchedAt
        self.isStale = isStale
    }

    public var highestUsedPercent: Double? {
        quotaWindows.map(\.usedPercent).max()
    }

    /// Windows the menu lists: unused windows are hidden unless every window
    /// is unused, so a provider never shows an empty card that reads as
    /// unavailable.
    public var displayedQuotaWindows: [QuotaWindow] {
        let used = quotaWindows.filter { !$0.isUnused }
        return used.isEmpty ? quotaWindows : used
    }

    /// The window with the least remaining capacity. Ties keep the first
    /// window in provider order.
    public var tightestQuotaWindow: QuotaWindow? {
        quotaWindows.reduce(nil) { tightest, window in
            guard let tightest, tightest.remainingPercent <= window.remainingPercent else {
                return window
            }
            return tightest
        }
    }
}

public struct AgentTokenSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public var tokens: TokenUsage?
    public var issue: SourceIssue?
    public let usesLegacySchema: Bool
    public var fetchedAt: Date
    public var isStale: Bool

    public init(
        id: String,
        displayName: String,
        tokens: TokenUsage?,
        issue: SourceIssue?,
        usesLegacySchema: Bool,
        fetchedAt: Date,
        isStale: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.tokens = tokens
        self.issue = issue
        self.usesLegacySchema = usesLegacySchema
        self.fetchedAt = fetchedAt
        self.isStale = isStale
    }
}

public struct ModelBarSnapshot: Codable, Equatable, Sendable {
    public var providers: [ProviderSnapshot]
    public var agents: [AgentTokenSnapshot]
    public var refreshedAt: Date

    public init(
        providers: [ProviderSnapshot],
        agents: [AgentTokenSnapshot],
        refreshedAt: Date
    ) {
        self.providers = providers
        self.agents = agents
        self.refreshedAt = refreshedAt
    }

    public var highestUsedPercent: Double? {
        providers.compactMap(\.highestUsedPercent).max()
    }

    public var hasIssues: Bool {
        providers.contains { $0.issue != nil } || agents.contains { $0.issue != nil }
    }

    public func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(refreshedAt) > 1_800 ||
            providers.contains { $0.isStale } ||
            agents.contains { $0.isStale }
    }

    public func hasSameDisplayContent(as other: ModelBarSnapshot) -> Bool {
        var left = self
        var right = other
        left.normaliseFetchDates()
        right.normaliseFetchDates()
        return left == right
    }

    private mutating func normaliseFetchDates() {
        refreshedAt = .distantPast
        for index in providers.indices {
            providers[index].fetchedAt = .distantPast
        }
        for index in agents.indices {
            agents[index].fetchedAt = .distantPast
        }
    }
}

public enum SnapshotMerger {
    public static func merge(
        fresh: ModelBarSnapshot,
        previous: ModelBarSnapshot?
    ) -> ModelBarSnapshot {
        guard let previous else {
            return fresh
        }

        let previousProviders = Dictionary(
            uniqueKeysWithValues: previous.providers.map { ($0.id, $0) }
        )
        let previousAgents = Dictionary(
            uniqueKeysWithValues: previous.agents.map { ($0.id, $0) }
        )

        let providers = fresh.providers.map { current in
            guard current.issue != nil, let cached = previousProviders[current.id] else {
                return current
            }
            var merged = current
            // Only quota taken from the cache makes a provider stale. Tokens
            // and service status may be backfilled while fresh quota stays
            // fresh, and the issue text keeps the failed source visible.
            if merged.quotaWindows.isEmpty, !cached.quotaWindows.isEmpty {
                merged.quotaWindows = cached.quotaWindows
                // The quota is only as old as the refresh that produced it,
                // so repeated failures must not reset the displayed age.
                merged.fetchedAt = cached.fetchedAt
                merged.isStale = true
            }
            if merged.tokens == nil {
                merged.tokens = cached.tokens
            }
            if merged.serviceStatus == nil, cached.serviceStatus != nil {
                merged.serviceStatus = cached.serviceStatus
            }
            return merged
        }

        let agents = fresh.agents.map { current in
            guard current.issue != nil, let cached = previousAgents[current.id] else {
                return current
            }
            var merged = current
            if merged.tokens == nil {
                merged.tokens = cached.tokens
            }
            merged.isStale = true
            return merged
        }

        return ModelBarSnapshot(
            providers: providers,
            agents: agents,
            refreshedAt: fresh.refreshedAt
        )
    }
}
