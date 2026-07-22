import Foundation

public struct MenuPresentation: Equatable, Sendable {
    public let statusTitle: String
    public let accessibilityLabel: String
    public let providerRows: [MenuPresentationRow]
    public let providerCards: [ProviderCardPresentation]
    public let agentRows: [MenuPresentationRow]
    public let footer: String

    public init(
        statusTitle: String,
        accessibilityLabel: String,
        providerRows: [MenuPresentationRow],
        providerCards: [ProviderCardPresentation],
        agentRows: [MenuPresentationRow],
        footer: String
    ) {
        self.statusTitle = statusTitle
        self.accessibilityLabel = accessibilityLabel
        self.providerRows = providerRows
        self.providerCards = providerCards
        self.agentRows = agentRows
        self.footer = footer
    }
}

public enum QuotaCapacityState: Equatable, Sendable {
    case healthy
    case low
    case critical
}

public struct QuotaBarPresentation: Equatable, Sendable {
    public let name: String
    public let remainingFraction: Double
    public let leftText: String
    public let resetText: String
    public let capacityState: QuotaCapacityState

    public init(window: QuotaWindow, now: Date) {
        name = window.name
        remainingFraction = window.remainingPercent / 100
        leftText = "\(DisplayFormatting.percent(window.remainingPercent)) left"
        resetText = DisplayFormatting.reset(window.resetsAt, now: now)
        switch window.remainingPercent {
        case ...10:
            capacityState = .critical
        case ...20:
            capacityState = .low
        default:
            capacityState = .healthy
        }
    }
}

public struct ProviderCardPresentation: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let brand: ProviderBrand?
    public let statusText: String
    public let statusCondition: ServiceCondition
    public let ageText: String
    public let quotaBars: [QuotaBarPresentation]
    public let tokensText: String?
    public let issueText: String?
    public let isStale: Bool
}

public struct MenuPresentationRow: Equatable, Sendable {
    public let title: String
    public let indentationLevel: Int

    public init(title: String, indentationLevel: Int = 0) {
        self.title = title
        self.indentationLevel = indentationLevel
    }
}

public enum MenuPresentationBuilder {
    public static func build(
        snapshot: ModelBarSnapshot,
        now: Date = Date(),
        preferences: ModelBarPreferences = ModelBarPreferences()
    ) -> MenuPresentation {
        let visibleProviders = snapshot.providers.filter {
            preferences.isProviderEnabled($0.id)
        }
        let visibleAgents = snapshot.agents.filter {
            preferences.isAgentVisible($0.id)
        }
        let highest = visibleProviders.compactMap(\.highestUsedPercent).max()
        let statusTitle = highest.map(DisplayFormatting.percent) ?? "?"
        let hasIssues = visibleProviders.contains { $0.issue != nil } ||
            visibleAgents.contains { $0.issue != nil }
        let stale = now.timeIntervalSince(snapshot.refreshedAt) > 1_800 ||
            visibleProviders.contains { $0.isStale } ||
            visibleAgents.contains { $0.isStale }
        let state: String
        if hasIssues {
            state = "with unavailable data"
        } else if stale {
            state = "stale"
        } else {
            state = "current"
        }

        let footerPrefix: String
        if hasIssues {
            footerPrefix = "Partial data"
        } else if stale {
            footerPrefix = "Stale data"
        } else {
            footerPrefix = "Updated"
        }

        return MenuPresentation(
            statusTitle: statusTitle,
            accessibilityLabel: "Highest model quota usage \(statusTitle), \(state)",
            providerRows: visibleProviders.flatMap {
                providerRows(provider: $0, stale: stale, now: now)
            },
            providerCards: visibleProviders.map {
                providerCard(provider: $0, snapshotIsStale: stale, now: now)
            },
            agentRows: visibleAgents.isEmpty
                ? [MenuPresentationRow(title: "No Hermes profiles found")]
                : visibleAgents.map { agentRow(agent: $0, stale: stale) },
            footer: "\(footerPrefix) \(DisplayFormatting.age(since: snapshot.refreshedAt, now: now))"
        )
    }

    private static func providerCard(
        provider: ProviderSnapshot,
        snapshotIsStale: Bool,
        now: Date
    ) -> ProviderCardPresentation {
        let statusText: String
        let statusCondition: ServiceCondition
        if let serviceStatus = provider.serviceStatus {
            statusText = statusLabel(serviceStatus)
            statusCondition = serviceStatus.condition
        } else {
            statusText = "Service status unknown"
            statusCondition = .unknown
        }

        let tokensText: String?
        if let tokens = provider.tokens {
            let recent = DisplayFormatting.tokens(tokens.recentTokens)
            let sevenDays = DisplayFormatting.tokens(tokens.sevenDayTokens)
            let qualifier = tokens.qualifier.map { " · \($0)" } ?? ""
            tokensText = "Tokens: \(tokens.recentLabel) \(recent) · 7d \(sevenDays)\(qualifier)"
        } else {
            tokensText = nil
        }

        let stale = provider.isStale || snapshotIsStale
        let agePrefix = stale ? "Stale" : "Updated"
        return ProviderCardPresentation(
            id: provider.id,
            displayName: provider.displayName,
            brand: provider.brand,
            statusText: statusText,
            statusCondition: statusCondition,
            ageText: "\(agePrefix) \(DisplayFormatting.age(since: provider.fetchedAt, now: now))",
            quotaBars: provider.quotaWindows.map {
                QuotaBarPresentation(window: $0, now: now)
            },
            tokensText: tokensText,
            issueText: provider.issue?.message,
            isStale: stale
        )
    }

    private static func providerRows(
        provider: ProviderSnapshot,
        stale: Bool,
        now: Date
    ) -> [MenuPresentationRow] {
        var title = provider.displayName
        if let percent = provider.highestUsedPercent.map(DisplayFormatting.percent) {
            title += "  \(percent) used"
        }
        if provider.isStale || stale {
            title += "  stale"
        }
        var rows = [MenuPresentationRow(title: title)]

        for window in provider.quotaWindows {
            let used = DisplayFormatting.percent(window.usedPercent)
            let remaining = DisplayFormatting.percent(window.remainingPercent)
            let reset = DisplayFormatting.reset(window.resetsAt, now: now)
            rows.append(MenuPresentationRow(
                title: "\(window.name): \(used) used · \(remaining) left · \(reset)",
                indentationLevel: 1
            ))
        }

        if let tokens = provider.tokens {
            let recent = DisplayFormatting.tokens(tokens.recentTokens)
            let sevenDays = DisplayFormatting.tokens(tokens.sevenDayTokens)
            let qualifier = tokens.qualifier.map { " · \($0)" } ?? ""
            rows.append(MenuPresentationRow(
                title: "Tokens: \(tokens.recentLabel) \(recent) · 7d \(sevenDays)\(qualifier)",
                indentationLevel: 1
            ))
        }

        if let status = provider.serviceStatus {
            rows.append(MenuPresentationRow(
                title: "Status: \(statusLabel(status))",
                indentationLevel: 1
            ))
        } else {
            rows.append(MenuPresentationRow(
                title: "Status: Service status unknown",
                indentationLevel: 1
            ))
        }

        if let issue = provider.issue {
            rows.append(MenuPresentationRow(
                title: "⚠ \(issue.message)",
                indentationLevel: 1
            ))
        }
        return rows
    }

    private static func agentRow(
        agent: AgentTokenSnapshot,
        stale: Bool
    ) -> MenuPresentationRow {
        var title = agent.displayName
        if let tokens = agent.tokens {
            title += "  24h \(DisplayFormatting.tokens(tokens.recentTokens))"
            title += " · 7d \(DisplayFormatting.tokens(tokens.sevenDayTokens))"
        } else {
            title += "  unavailable"
        }
        if agent.isStale || stale {
            title += "  stale"
        }
        if let issue = agent.issue {
            title += "  ⚠ \(issue.message)"
        }
        return MenuPresentationRow(title: title)
    }

    private static func statusLabel(_ status: ServiceStatus) -> String {
        switch status.condition {
        case .operational:
            return "Operational"
        case .degraded:
            return "Degraded · \(status.description)"
        case .outage:
            return "Outage · \(status.description)"
        case .unknown:
            return "Unknown · \(status.description)"
        }
    }
}
