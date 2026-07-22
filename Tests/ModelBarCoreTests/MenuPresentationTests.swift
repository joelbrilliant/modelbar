import Foundation
import XCTest
@testable import ModelBarCore

final class MenuPresentationTests: XCTestCase {
    func testPresentationIncludesProviderQuotaTokensStatusAndEveryAgent() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "codex",
                    displayName: "OpenAI",
                    brand: .openAI,
                    quotaWindows: [
                        QuotaWindow(
                            name: "Weekly",
                            usedPercent: 50,
                            resetsAt: now.addingTimeInterval(86_400)
                        ),
                    ],
                    tokens: TokenUsage(
                        recentTokens: 1_200,
                        sevenDayTokens: 2_000_000,
                        recentLabel: "today",
                        qualifier: "local"
                    ),
                    serviceStatus: ServiceStatus(
                        condition: .operational,
                        description: "All Systems Operational",
                        url: nil
                    ),
                    issue: nil,
                    fetchedAt: now
                ),
                ProviderSnapshot(
                    id: "grok",
                    displayName: "Grok",
                    brand: .grok,
                    quotaWindows: [
                        QuotaWindow(name: "Quota", usedPercent: 32, resetsAt: nil),
                    ],
                    tokens: nil,
                    serviceStatus: nil,
                    issue: nil,
                    fetchedAt: now
                ),
            ],
            agents: [
                agent(id: "default", name: "Rocky", now: now),
                agent(id: "frank", name: "Frank", now: now),
                agent(id: "chad", name: "Chad", now: now),
                agent(id: "oscar", name: "Oscar", now: now),
            ],
            refreshedAt: now
        )

        let presentation = MenuPresentationBuilder.build(snapshot: snapshot, now: now)
        let providerTitles = presentation.providerRows.map(\.title)
        let agentTitles = presentation.agentRows.map(\.title)

        XCTAssertEqual(presentation.statusTitle, "50%")
        XCTAssertEqual(presentation.providerCards.count, 2)
        XCTAssertEqual(presentation.providerCards[0].brand, .openAI)
        XCTAssertEqual(presentation.providerCards[1].brand, .grok)
        XCTAssertEqual(presentation.providerCards[0].statusText, "Operational")
        XCTAssertEqual(presentation.providerCards[0].quotaBars[0].remainingFraction, 0.5)
        XCTAssertEqual(presentation.providerCards[0].quotaBars[0].leftText, "50% left")
        XCTAssertEqual(presentation.providerCards[0].quotaBars[0].capacityState, .healthy)
        XCTAssertTrue(providerTitles.contains("Weekly: 50% used · 50% left · resets in 1d"))
        XCTAssertTrue(providerTitles.contains("Tokens: today 1.2K · 7d 2M · local"))
        XCTAssertTrue(providerTitles.contains("Status: Operational"))
        XCTAssertTrue(providerTitles.contains("Status: Service status unknown"))
        XCTAssertEqual(agentTitles.count, 4)
        XCTAssertTrue(agentTitles[0].hasPrefix("Rocky  24h"))
        XCTAssertTrue(agentTitles[3].hasPrefix("Oscar  24h"))
        XCTAssertEqual(presentation.footer, "Updated just now")
    }

    func testCardMarksLowAndCriticalCapacityInTextAndState() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let provider = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            quotaWindows: [
                QuotaWindow(name: "Primary", usedPercent: 82, resetsAt: nil),
                QuotaWindow(name: "Weekly", usedPercent: 94, resetsAt: nil),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )

        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [provider],
                agents: [],
                refreshedAt: now
            ),
            now: now
        )

        XCTAssertEqual(presentation.providerCards[0].quotaBars[0].leftText, "18% left")
        XCTAssertEqual(presentation.providerCards[0].quotaBars[0].capacityState, .low)
        XCTAssertEqual(presentation.providerCards[0].quotaBars[1].leftText, "6% left")
        XCTAssertEqual(presentation.providerCards[0].quotaBars[1].capacityState, .critical)
    }

    func testCardsUseSnapshotBrandAndDefaultUnbrandedProvidersToNeutral() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let providers: [(String, String, ProviderBrand?)] = [
            ("codex", "OpenAI", .openAI),
            ("claude", "Claude", .claude),
            ("grok", "Grok", .grok),
            ("future", "Future", nil),
        ]
        let snapshots = providers.map { id, name, brand in
            ProviderSnapshot(
                id: id,
                displayName: name,
                brand: brand,
                quotaWindows: [],
                tokens: nil,
                serviceStatus: nil,
                issue: nil,
                fetchedAt: now
            )
        }

        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: snapshots,
                agents: [],
                refreshedAt: now
            ),
            now: now
        )

        XCTAssertEqual(
            presentation.providerCards.map(\.brand),
            [.openAI, .claude, .grok, nil]
        )
    }

    func testPreferencesFilterProvidersAgentsAndStatusTitle() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let codex = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            quotaWindows: [QuotaWindow(name: "Weekly", usedPercent: 90, resetsAt: nil)],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )
        let claude = ProviderSnapshot(
            id: "claude",
            displayName: "Claude",
            quotaWindows: [QuotaWindow(name: "Weekly", usedPercent: 40, resetsAt: nil)],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )
        let snapshot = ModelBarSnapshot(
            providers: [codex, claude],
            agents: [
                agent(id: "default", name: "Rocky", now: now),
                agent(id: "frank", name: "Frank", now: now),
            ],
            refreshedAt: now
        )

        let presentation = MenuPresentationBuilder.build(
            snapshot: snapshot,
            now: now,
            preferences: ModelBarPreferences(
                disabledProviderIDs: ["codex"],
                hiddenAgentIDs: ["frank"]
            )
        )

        XCTAssertEqual(presentation.statusTitle, "40%")
        XCTAssertEqual(presentation.providerCards.map(\.id), ["claude"])
        XCTAssertEqual(presentation.agentRows.count, 1)
        XCTAssertTrue(presentation.agentRows[0].title.hasPrefix("Rocky"))
    }

    func testHiddenAgentFailureDoesNotMarkVisibleMenuPartialOrStale() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let provider = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            quotaWindows: [QuotaWindow(name: "Weekly", usedPercent: 40, resetsAt: nil)],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )
        let hiddenAgent = AgentTokenSnapshot(
            id: "frank",
            displayName: "Frank",
            tokens: nil,
            issue: SourceIssue(kind: .network, message: "Unavailable"),
            usesLegacySchema: false,
            fetchedAt: now,
            isStale: true
        )

        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [provider],
                agents: [hiddenAgent],
                refreshedAt: now
            ),
            now: now,
            preferences: ModelBarPreferences(hiddenAgentIDs: ["frank"])
        )

        XCTAssertEqual(presentation.accessibilityLabel, "Highest model quota usage 40%, current")
        XCTAssertEqual(presentation.footer, "Updated just now")
    }

    func testStaleAndPartialStatesAreVisibleInText() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let provider = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            quotaWindows: [],
            tokens: nil,
            serviceStatus: nil,
            issue: SourceIssue(kind: .network, message: "Quota network error"),
            fetchedAt: now.addingTimeInterval(-3_600),
            isStale: true
        )
        let snapshot = ModelBarSnapshot(
            providers: [provider],
            agents: [],
            refreshedAt: now.addingTimeInterval(-3_600)
        )

        let presentation = MenuPresentationBuilder.build(snapshot: snapshot, now: now)

        XCTAssertTrue(presentation.accessibilityLabel.contains("unavailable data"))
        XCTAssertTrue(presentation.providerRows.map(\.title).contains("⚠ Quota network error"))
        XCTAssertEqual(presentation.footer, "Partial data 1h ago")
    }

    private func agent(id: String, name: String, now: Date) -> AgentTokenSnapshot {
        AgentTokenSnapshot(
            id: id,
            displayName: name,
            tokens: TokenUsage(
                recentTokens: 100,
                sevenDayTokens: 700,
                recentLabel: "24h"
            ),
            issue: nil,
            usesLegacySchema: false,
            fetchedAt: now
        )
    }
}
