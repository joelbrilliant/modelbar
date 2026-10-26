import Foundation

public struct MenuPresentation: Equatable, Sendable {
    /// Plain-text fallback for the status item: segment values joined by
    /// single spaces, or "?" when no enabled provider has data yet.
    public let statusTitle: String
    public let statusSegments: [StatusSegmentPresentation]
    public let statusToolTip: String
    public let accessibilityLabel: String
    public let providerRows: [MenuPresentationRow]
    public let providerCards: [ProviderCardPresentation]
    public let agentRows: [MenuPresentationRow]
    public let footer: String

    public init(
        statusTitle: String,
        statusSegments: [StatusSegmentPresentation],
        statusToolTip: String,
        accessibilityLabel: String,
        providerRows: [MenuPresentationRow],
        providerCards: [ProviderCardPresentation],
        agentRows: [MenuPresentationRow],
        footer: String
    ) {
        self.statusTitle = statusTitle
        self.statusSegments = statusSegments
        self.statusToolTip = statusToolTip
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

    public init(remainingPercent: Double) {
        switch remainingPercent {
        case ...10:
            self = .critical
        case ...20:
            self = .low
        default:
            self = .healthy
        }
    }
}

/// One provider's segment in the closed status item: its tightest quota
/// window expressed as percentage left.
public struct StatusSegmentPresentation: Equatable, Sendable {
    public static let unavailableText = "\u{2013}"

    public let id: String
    public let displayName: String
    public let brand: ProviderBrand?
    public let windowName: String?
    public let remainingFraction: Double?
    public let valueText: String
    public let capacityState: QuotaCapacityState?
    public let isStale: Bool

    public init(
        id: String,
        displayName: String,
        brand: ProviderBrand?,
        windowName: String?,
        remainingFraction: Double?,
        valueText: String,
        capacityState: QuotaCapacityState?,
        isStale: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.brand = brand
        self.windowName = windowName
        self.remainingFraction = remainingFraction
        self.valueText = valueText
        self.capacityState = capacityState
        self.isStale = isStale
    }
}

public struct QuotaBarPresentation: Equatable, Sendable {
    public let name: String
    public let remainingFraction: Double
    public let leftText: String
    public let countdownText: String
    public let accessibilityText: String
    public let capacityState: QuotaCapacityState

    public init(window: QuotaWindow, now: Date) {
        name = window.name
        remainingFraction = window.remainingPercent / 100
        leftText = "\(DisplayFormatting.percent(window.remainingPercent)) left"
        countdownText = DisplayFormatting.countdown(window.resetsAt, now: now)
        capacityState = QuotaCapacityState(remainingPercent: window.remainingPercent)

        let resetPhrase: String
        if window.resetsAt == nil {
            resetPhrase = "reset time unknown"
        } else if countdownText == "due" {
            resetPhrase = "reset due"
        } else {
            resetPhrase = "resets in \(countdownText)"
        }
        accessibilityText = "\(window.name), \(leftText), \(resetPhrase)"
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
    /// Shown when no enabled provider is in the snapshot yet. Settings and
    /// launch keep at least one provider enabled, so an empty list means
    /// newly enabled providers have not been fetched, not that none are on.
    public static let waitingForProviderDataText = "Waiting for provider data"

    public static func build(
        snapshot: ModelBarSnapshot,
        now: Date = Date(),
        preferences: ModelBarPreferences = ModelBarPreferences(),
        calendar: Calendar = .current
    ) -> MenuPresentation {
        let visibleProviders = snapshot.providers.filter {
            preferences.isProviderEnabled($0.id)
        }
        let visibleAgents = snapshot.agents.filter {
            preferences.isAgentVisible($0.id)
        }
        let hasIssues = visibleProviders.contains { $0.issue != nil } ||
            visibleAgents.contains { $0.issue != nil }
        let ageStale = now.timeIntervalSince(snapshot.refreshedAt) > 1_800
        let stale = ageStale ||
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

        let footer = "\(footerPrefix) \(DisplayFormatting.age(since: snapshot.refreshedAt, now: now))"
        // Segments are stale only through their own provider or snapshot
        // age, never because another provider or a Hermes agent is stale,
        // so dimming shows which provider is out of date.
        let segments = visibleProviders.map {
            statusSegment(provider: $0, snapshotAgeIsStale: ageStale)
        }
        let statusTitle = segments.isEmpty
            ? "?"
            : segments.map(\.valueText).joined(separator: " ")

        return MenuPresentation(
            statusTitle: statusTitle,
            statusSegments: segments,
            statusToolTip: statusToolTip(
                providers: visibleProviders,
                segments: segments,
                footer: "\(toolTipFooterPrefix(hasIssues: hasIssues, stale: stale)) " +
                    DisplayFormatting.clockTime(snapshot.refreshedAt, now: now, calendar: calendar),
                now: now,
                calendar: calendar
            ),
            accessibilityLabel: statusAccessibilityLabel(segments: segments, state: state),
            providerRows: visibleProviders.flatMap {
                providerRows(provider: $0, stale: $0.isStale || ageStale, now: now)
            },
            providerCards: visibleProviders.map {
                providerCard(provider: $0, snapshotAgeIsStale: ageStale, now: now)
            },
            agentRows: visibleAgents.isEmpty
                ? [MenuPresentationRow(title: "No Hermes profiles found")]
                : visibleAgents.map { agentRow(agent: $0, stale: stale) },
            footer: footer
        )
    }

    private static func statusSegment(
        provider: ProviderSnapshot,
        snapshotAgeIsStale: Bool
    ) -> StatusSegmentPresentation {
        let window = provider.tightestQuotaWindow
        return StatusSegmentPresentation(
            id: provider.id,
            displayName: provider.displayName,
            brand: provider.brand,
            windowName: window?.name,
            remainingFraction: window.map { $0.remainingPercent / 100 },
            valueText: window.map { DisplayFormatting.percentNumber($0.remainingPercent) }
                ?? StatusSegmentPresentation.unavailableText,
            capacityState: window.map {
                QuotaCapacityState(remainingPercent: $0.remainingPercent)
            },
            isStale: provider.isStale || snapshotAgeIsStale
        )
    }

    /// The tooltip is a stored string that AppKit shows until the next
    /// render, so it uses absolute times rather than "just now" or
    /// "resets in 20m", which would go stale while the menu stays closed.
    private static func toolTipFooterPrefix(hasIssues: Bool, stale: Bool) -> String {
        if hasIssues {
            return "Partial data from"
        }
        if stale {
            return "Stale data from"
        }
        return "Updated"
    }

    private static func statusToolTip(
        providers: [ProviderSnapshot],
        segments: [StatusSegmentPresentation],
        footer: String,
        now: Date,
        calendar: Calendar
    ) -> String {
        var lines = zip(providers, segments).map { provider, segment in
            var parts = [segment.displayName]
            if let window = provider.tightestQuotaWindow {
                parts.append(window.name)
                parts.append("\(DisplayFormatting.percent(window.remainingPercent)) left")
                if window.resetsAt != nil {
                    parts.append(DisplayFormatting.resetClock(
                        window.resetsAt,
                        now: now,
                        calendar: calendar
                    ))
                }
            } else {
                parts.append("Quota unavailable")
            }
            if segment.isStale {
                parts.append("stale")
            }
            return parts.joined(separator: " · ")
        }
        if lines.isEmpty {
            lines.append(waitingForProviderDataText)
        }
        lines.append(footer)
        return lines.joined(separator: "\n")
    }

    private static func statusAccessibilityLabel(
        segments: [StatusSegmentPresentation],
        state: String
    ) -> String {
        var sentences = ["Model quota left, \(state)."]
        if segments.isEmpty {
            sentences.append("\(waitingForProviderDataText).")
        }
        for segment in segments {
            let staleSuffix = segment.isStale ? ", stale" : ""
            guard let windowName = segment.windowName else {
                sentences.append("\(segment.displayName), quota unavailable\(staleSuffix).")
                continue
            }
            var sentence = "\(segment.displayName), \(windowName), \(segment.valueText)% left"
            switch segment.capacityState {
            case .critical:
                sentence += ", critical"
            case .low:
                sentence += ", low"
            case .healthy, nil:
                break
            }
            sentences.append(sentence + staleSuffix + ".")
        }
        return sentences.joined(separator: " ")
    }

    private static func providerCard(
        provider: ProviderSnapshot,
        snapshotAgeIsStale: Bool,
        now: Date
    ) -> ProviderCardPresentation {
        let statusText: String
        let statusCondition: ServiceCondition
        if let serviceStatus = provider.serviceStatus {
            statusText = statusLabel(serviceStatus)
            statusCondition = serviceStatus.condition
        } else {
            statusText = "Status unknown"
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

        // Per provider, like the status item: another provider or a Hermes
        // agent going stale must not mark this card stale.
        let stale = provider.isStale || snapshotAgeIsStale
        let agePrefix = stale ? "Stale" : "Updated"
        return ProviderCardPresentation(
            id: provider.id,
            displayName: provider.displayName,
            brand: provider.brand,
            statusText: statusText,
            statusCondition: statusCondition,
            ageText: "\(agePrefix) \(DisplayFormatting.age(since: provider.fetchedAt, now: now))",
            quotaBars: provider.displayedQuotaWindows.map {
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
        if stale {
            title += "  stale"
        }
        var rows = [MenuPresentationRow(title: title)]

        for window in provider.displayedQuotaWindows {
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
