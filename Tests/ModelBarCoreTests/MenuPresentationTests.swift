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

        XCTAssertEqual(presentation.statusTitle, "50 68")
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

        XCTAssertEqual(presentation.statusTitle, "60")
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

        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Model quota left, current. OpenAI, Weekly, 60% left."
        )
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

    func testStatusSegmentsFollowSnapshotOrderAndOnlyEnabledProviders() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = ModelBarSnapshot(
            providers: [
                provider(id: "codex", name: "OpenAI", brand: .openAI, used: [4], now: now),
                provider(id: "claude", name: "Claude", brand: .claude, used: [66], now: now),
                provider(id: "grok", name: "Grok", brand: .grok, used: [1], now: now),
            ],
            agents: [],
            refreshedAt: now
        )

        let all = MenuPresentationBuilder.build(snapshot: snapshot, now: now)
        XCTAssertEqual(all.statusSegments.map(\.id), ["codex", "claude", "grok"])
        XCTAssertEqual(all.statusSegments.map(\.displayName), ["OpenAI", "Claude", "Grok"])
        XCTAssertEqual(all.statusSegments.map(\.brand), [.openAI, .claude, .grok])
        XCTAssertEqual(all.statusSegments.map(\.valueText), ["96", "34", "99"])
        XCTAssertEqual(all.statusTitle, "96 34 99")

        let filtered = MenuPresentationBuilder.build(
            snapshot: snapshot,
            now: now,
            preferences: ModelBarPreferences(disabledProviderIDs: ["claude"])
        )
        XCTAssertEqual(filtered.statusSegments.map(\.id), ["codex", "grok"])
        XCTAssertEqual(filtered.statusTitle, "96 99")
    }

    func testStatusSegmentUsesTightestQuotaWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let claude = ProviderSnapshot(
            id: "claude",
            displayName: "Claude",
            brand: .claude,
            quotaWindows: [
                QuotaWindow(name: "5-hour", usedPercent: 66, resetsAt: nil),
                QuotaWindow(name: "Weekly", usedPercent: 29, resetsAt: nil),
                QuotaWindow(name: "Daily Routines", usedPercent: 0, resetsAt: nil),
                QuotaWindow(name: "Fable only", usedPercent: 0, resetsAt: nil),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )

        XCTAssertEqual(claude.tightestQuotaWindow?.name, "5-hour")

        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [claude], agents: [], refreshedAt: now),
            now: now
        )
        let segment = presentation.statusSegments[0]
        XCTAssertEqual(segment.valueText, "34")
        XCTAssertEqual(segment.windowName, "5-hour")
        XCTAssertEqual(segment.remainingFraction ?? -1, 0.34, accuracy: 0.000_001)
        XCTAssertEqual(segment.capacityState, .healthy)
        XCTAssertFalse(segment.isStale)
    }

    func testTightestQuotaWindowTieKeepsFirstWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let provider = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            quotaWindows: [
                QuotaWindow(name: "Primary", usedPercent: 10, resetsAt: nil),
                QuotaWindow(name: "Weekly", usedPercent: 70, resetsAt: nil),
                QuotaWindow(name: "Monthly", usedPercent: 70, resetsAt: nil),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )

        XCTAssertEqual(provider.tightestQuotaWindow?.name, "Weekly")
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [provider], agents: [], refreshedAt: now),
            now: now
        )
        XCTAssertEqual(presentation.statusSegments[0].windowName, "Weekly")
    }

    func testStatusSegmentRoundingMatchesCardLeftText() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cases: [(used: Double, expected: String)] = [
            (66.5, "34"),
            (33.5, "66"),
            (99.6, "0"),
            (0.4, "100"),
        ]
        for testCase in cases {
            let provider = provider(
                id: "codex",
                name: "OpenAI",
                brand: .openAI,
                used: [testCase.used],
                now: now
            )
            let presentation = MenuPresentationBuilder.build(
                snapshot: ModelBarSnapshot(providers: [provider], agents: [], refreshedAt: now),
                now: now
            )
            let segment = presentation.statusSegments[0]
            let card = presentation.providerCards[0].quotaBars[0]
            XCTAssertEqual(
                "\(segment.valueText)% left",
                card.leftText,
                "used \(testCase.used)"
            )
            XCTAssertEqual(segment.valueText, testCase.expected, "used \(testCase.used)")
        }
    }

    func testStatusSegmentMatchesCardBarForTightestWindowWhenItIsNotFirst() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let provider = ProviderSnapshot(
            id: "claude",
            displayName: "Claude",
            brand: .claude,
            quotaWindows: [
                QuotaWindow(name: "5-hour", usedPercent: 12.4, resetsAt: nil),
                QuotaWindow(name: "Weekly", usedPercent: 81.5, resetsAt: nil),
                QuotaWindow(name: "Opus", usedPercent: 40, resetsAt: nil),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [provider], agents: [], refreshedAt: now),
            now: now
        )

        let segment = presentation.statusSegments[0]
        XCTAssertEqual(segment.windowName, "Weekly")
        let card = presentation.providerCards[0].quotaBars.first { $0.name == segment.windowName }
        XCTAssertNotNil(card)
        XCTAssertEqual("\(segment.valueText)% left", card?.leftText)
        XCTAssertEqual(segment.valueText, "18")
        XCTAssertEqual(segment.capacityState, card?.capacityState)
        XCTAssertEqual(segment.capacityState, .low)
    }

    func testStatusSegmentWithoutQuotaWindowsShowsPlaceholderNotZero() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [
                    provider(id: "codex", name: "OpenAI", brand: .openAI, used: [50], now: now),
                    provider(id: "grok", name: "Grok", brand: .grok, used: [], now: now),
                ],
                agents: [],
                refreshedAt: now
            ),
            now: now
        )

        let segment = presentation.statusSegments[1]
        XCTAssertEqual(segment.valueText, "\u{2013}")
        XCTAssertNil(segment.windowName)
        XCTAssertNil(segment.remainingFraction)
        XCTAssertNil(segment.capacityState)
        XCTAssertEqual(presentation.statusTitle, "50 \u{2013}")
    }

    func testStatusSegmentsMarkProviderAndSnapshotAgeStaleness() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var staleClaude = provider(id: "claude", name: "Claude", brand: .claude, used: [20], now: now)
        staleClaude.isStale = true

        let providerStale = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [staleClaude], agents: [], refreshedAt: now),
            now: now
        )
        XCTAssertTrue(providerStale.statusSegments[0].isStale)

        let fresh = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [provider(id: "codex", name: "OpenAI", brand: .openAI, used: [20], now: now)],
                agents: [],
                refreshedAt: now
            ),
            now: now
        )
        XCTAssertFalse(fresh.statusSegments[0].isStale)

        let old = now.addingTimeInterval(-1_801)
        let ageStale = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [provider(id: "codex", name: "OpenAI", brand: .openAI, used: [20], now: old)],
                agents: [],
                refreshedAt: old
            ),
            now: now
        )
        XCTAssertTrue(ageStale.statusSegments[0].isStale)
        XCTAssertEqual(ageStale.statusSegments[0].valueText, "80")
    }

    func testMergedFailingProviderIsTheOnlyStaleSegment() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let previous = ModelBarSnapshot(
            providers: [
                provider(id: "codex", name: "OpenAI", brand: .openAI, used: [10], now: now),
                provider(id: "claude", name: "Claude", brand: .claude, used: [77], now: now),
                provider(id: "grok", name: "Grok", brand: .grok, used: [2], now: now),
            ],
            agents: [],
            refreshedAt: now
        )
        let later = now.addingTimeInterval(900)
        var failedClaude = provider(id: "claude", name: "Claude", brand: .claude, used: [], now: later)
        failedClaude.issue = SourceIssue(kind: .network, message: "Quota network error")
        let fresh = ModelBarSnapshot(
            providers: [
                provider(id: "codex", name: "OpenAI", brand: .openAI, used: [6], now: later),
                failedClaude,
                provider(id: "grok", name: "Grok", brand: .grok, used: [1], now: later),
            ],
            agents: [],
            refreshedAt: later
        )
        let merged = SnapshotMerger.merge(fresh: fresh, previous: previous)

        let presentation = MenuPresentationBuilder.build(snapshot: merged, now: later)

        XCTAssertEqual(presentation.statusSegments.map(\.id), ["codex", "claude", "grok"])
        XCTAssertEqual(presentation.statusSegments.map(\.isStale), [false, true, false])
        XCTAssertEqual(presentation.statusSegments.map(\.valueText), ["94", "23", "99"])
        XCTAssertEqual(presentation.statusTitle, "94 23 99")
        let toolTipLines = presentation.statusToolTip.components(separatedBy: "\n")
        XCTAssertEqual(toolTipLines[0], "OpenAI · Primary · 94% left")
        XCTAssertEqual(toolTipLines[1], "Claude · Primary · 23% left · stale")
        XCTAssertEqual(toolTipLines[2], "Grok · Primary · 99% left")
        XCTAssertTrue(presentation.accessibilityLabel.contains("OpenAI, Primary, 94% left."))
        XCTAssertTrue(presentation.accessibilityLabel.contains("Claude, Primary, 23% left, stale."))
        XCTAssertTrue(presentation.accessibilityLabel.contains("Grok, Primary, 99% left."))
    }

    func testStaleAgentDoesNotDimProviderSegments() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var staleAgent = agent(id: "rocky", name: "Rocky", now: now)
        staleAgent.isStale = true
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [
                    provider(id: "codex", name: "OpenAI", brand: .openAI, used: [20], now: now),
                    provider(id: "claude", name: "Claude", brand: .claude, used: [30], now: now),
                ],
                agents: [staleAgent],
                refreshedAt: now
            ),
            now: now
        )

        XCTAssertEqual(presentation.statusSegments.map(\.isStale), [false, false])
        XCTAssertFalse(presentation.statusToolTip.contains("stale"))
    }

    func testOldSnapshotMarksEverySegmentStale() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = now.addingTimeInterval(-1_801)
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [
                    provider(id: "codex", name: "OpenAI", brand: .openAI, used: [20], now: old),
                    provider(id: "claude", name: "Claude", brand: .claude, used: [30], now: old),
                    provider(id: "grok", name: "Grok", brand: .grok, used: [], now: old),
                ],
                agents: [],
                refreshedAt: old
            ),
            now: now
        )

        XCTAssertEqual(presentation.statusSegments.map(\.isStale), [true, true, true])
    }

    func testCapacityThresholdsAreSharedByCardsAndStatusSegments() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cases: [(remaining: Double, state: QuotaCapacityState)] = [
            (21, .healthy),
            (20, .low),
            (11, .low),
            (10, .critical),
        ]
        for testCase in cases {
            XCTAssertEqual(
                QuotaCapacityState(remainingPercent: testCase.remaining),
                testCase.state
            )
            let presentation = MenuPresentationBuilder.build(
                snapshot: ModelBarSnapshot(
                    providers: [
                        provider(
                            id: "codex",
                            name: "OpenAI",
                            brand: .openAI,
                            used: [100 - testCase.remaining],
                            now: now
                        ),
                    ],
                    agents: [],
                    refreshedAt: now
                ),
                now: now
            )
            XCTAssertEqual(presentation.statusSegments[0].capacityState, testCase.state)
            XCTAssertEqual(presentation.providerCards[0].quotaBars[0].capacityState, testCase.state)
        }
    }

    func testStatusTitleFallsBackToQuestionMarkWhenEnabledProvidersAreNotYetFetched() {
        // Only Grok was enabled at the last refresh; Settings then enabled
        // Claude and disabled Grok, and the old snapshot renders first.
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [
                    provider(id: "grok", name: "Grok", brand: .grok, used: [50], now: now),
                ],
                agents: [],
                refreshedAt: now
            ),
            now: now,
            preferences: ModelBarPreferences(disabledProviderIDs: ["codex", "grok"]),
            calendar: fixedCalendar
        )

        XCTAssertTrue(presentation.statusSegments.isEmpty)
        XCTAssertEqual(presentation.statusTitle, "?")
        XCTAssertEqual(presentation.statusToolTip, "Waiting for provider data\nUpdated 03:33")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Model quota left, current. Waiting for provider data."
        )
    }

    func testStatusToolTipListsEveryProviderAndFooter() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let codex = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            brand: .openAI,
            quotaWindows: [
                QuotaWindow(name: "Weekly", usedPercent: 50, resetsAt: now.addingTimeInterval(86_400)),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )
        let claude = provider(id: "claude", name: "Claude", brand: .claude, used: [66], now: now)
        let grok = provider(id: "grok", name: "Grok", brand: .grok, used: [], now: now)

        let fresh = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [codex, claude, grok], agents: [], refreshedAt: now),
            now: now,
            calendar: fixedCalendar
        )
        XCTAssertEqual(
            fresh.statusToolTip,
            [
                "OpenAI · Weekly · 50% left · resets Thu 03:33",
                "Claude · Primary · 34% left",
                "Grok · Quota unavailable",
                "Updated 03:33",
            ].joined(separator: "\n")
        )

        let old = now.addingTimeInterval(-3_600)
        var staleCodex = codex
        staleCodex.fetchedAt = old
        var staleGrok = grok
        staleGrok.fetchedAt = old
        let stale = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [staleCodex, staleGrok], agents: [], refreshedAt: old),
            now: now,
            calendar: fixedCalendar
        )
        XCTAssertEqual(
            stale.statusToolTip,
            [
                "OpenAI · Weekly · 50% left · resets Thu 03:33 · stale",
                "Grok · Quota unavailable · stale",
                "Stale data from 02:33",
            ].joined(separator: "\n")
        )
    }

    func testToolTipTimesAreAbsoluteSoTheyStayTrueAfterRender() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertEqual(
            DisplayFormatting.resetClock(now.addingTimeInterval(1_200), now: now, calendar: fixedCalendar),
            "resets 03:53"
        )
        XCTAssertEqual(
            DisplayFormatting.resetClock(now.addingTimeInterval(8 * 86_400), now: now, calendar: fixedCalendar),
            "resets 26 May at 03:33"
        )
        XCTAssertEqual(
            DisplayFormatting.resetClock(now.addingTimeInterval(-60), now: now, calendar: fixedCalendar),
            "reset due"
        )
        XCTAssertEqual(DisplayFormatting.resetClock(nil, now: now, calendar: fixedCalendar), "reset unknown")
    }

    func testAccessibilityLabelNamesEveryProviderWindowPercentAndState() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = ModelBarSnapshot(
            providers: [
                provider(id: "codex", name: "OpenAI", brand: .openAI, used: [94], now: now),
                provider(id: "claude", name: "Claude", brand: .claude, used: [82], now: now),
                provider(id: "grok", name: "Grok", brand: .grok, used: [], now: now),
                provider(id: "future", name: "Future", brand: nil, used: [30], now: now),
            ],
            agents: [],
            refreshedAt: now
        )

        let current = MenuPresentationBuilder.build(snapshot: snapshot, now: now)
        XCTAssertEqual(
            current.accessibilityLabel,
            "Model quota left, current. OpenAI, Primary, 6% left, critical. " +
                "Claude, Primary, 18% left, low. Grok, quota unavailable. " +
                "Future, Primary, 70% left."
        )

        let old = now.addingTimeInterval(-3_600)
        var staleSnapshot = snapshot
        staleSnapshot.refreshedAt = old
        let stale = MenuPresentationBuilder.build(snapshot: staleSnapshot, now: now)
        XCTAssertEqual(
            stale.accessibilityLabel,
            "Model quota left, stale. OpenAI, Primary, 6% left, critical, stale. " +
                "Claude, Primary, 18% left, low, stale. Grok, quota unavailable, stale. " +
                "Future, Primary, 70% left, stale."
        )

        var partialSnapshot = snapshot
        partialSnapshot.providers[2].issue = SourceIssue(kind: .network, message: "Quota network error")
        let partial = MenuPresentationBuilder.build(snapshot: partialSnapshot, now: now)
        XCTAssertTrue(
            partial.accessibilityLabel.hasPrefix("Model quota left, with unavailable data. OpenAI")
        )

        let none = MenuPresentationBuilder.build(
            snapshot: snapshot,
            now: now,
            preferences: ModelBarPreferences(
                disabledProviderIDs: ["codex", "claude", "grok", "future"]
            )
        )
        XCTAssertEqual(none.accessibilityLabel, "Model quota left, current. Waiting for provider data.")
    }

    // MARK: - One-line quota rows (V1.3)

    func testCountdownFormatsBoundaries() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let dash = "\u{2013}"
        let hour: TimeInterval = 3_600
        let day: TimeInterval = 86_400
        let cases: [(seconds: TimeInterval?, expected: String)] = [
            (nil, dash),
            (-60, "due"),
            (0, "due"),
            (59, "1m"),
            (60, "1m"),
            (3_540, "59m"),
            (3_599, "59m"),
            (hour, "1h 0m"),
            (3 * hour + 2_640, "3h 44m"),
            (day - 1, "23h 59m"),
            (day, "1d 0h"),
            (3 * day + 13 * hour + 3_240, "3d 13h"),
        ]
        for testCase in cases {
            let date = testCase.seconds.map { now.addingTimeInterval($0) }
            XCTAssertEqual(
                DisplayFormatting.countdown(date, now: now),
                testCase.expected,
                "seconds \(String(describing: testCase.seconds))"
            )
        }
    }

    func testQuotaBarCarriesCountdownAndAccessibilityText() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let known = QuotaBarPresentation(
            window: QuotaWindow(
                name: "5-hour",
                usedPercent: 18,
                resetsAt: now.addingTimeInterval(3 * 3_600 + 44 * 60)
            ),
            now: now
        )
        XCTAssertEqual(known.countdownText, "3h 44m")
        XCTAssertEqual(known.leftText, "82% left")
        XCTAssertEqual(known.accessibilityText, "5-hour, 82% left, resets in 3h 44m")

        let unknown = QuotaBarPresentation(
            window: QuotaWindow(name: "Weekly", usedPercent: 18, resetsAt: nil),
            now: now
        )
        XCTAssertEqual(unknown.countdownText, "\u{2013}")
        XCTAssertEqual(unknown.accessibilityText, "Weekly, 82% left, reset time unknown")

        let due = QuotaBarPresentation(
            window: QuotaWindow(
                name: "Weekly",
                usedPercent: 18,
                resetsAt: now.addingTimeInterval(-5)
            ),
            now: now
        )
        XCTAssertEqual(due.countdownText, "due")
        XCTAssertEqual(due.accessibilityText, "Weekly, 82% left, reset due")
    }

    func testUnusedWindowsAreHiddenFromCardsAndLegacyRows() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let claude = ProviderSnapshot(
            id: "claude",
            displayName: "Claude",
            brand: .claude,
            quotaWindows: [
                QuotaWindow(name: "5-hour", usedPercent: 66, resetsAt: nil),
                QuotaWindow(name: "Daily Routines", usedPercent: 0, resetsAt: nil),
                QuotaWindow(
                    name: "Weekly",
                    usedPercent: 0,
                    resetsAt: now.addingTimeInterval(86_400)
                ),
                QuotaWindow(name: "Fable only", usedPercent: 0, resetsAt: nil),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )
        XCTAssertTrue(claude.quotaWindows[1].isUnused)
        XCTAssertFalse(claude.quotaWindows[0].isUnused)
        XCTAssertFalse(claude.quotaWindows[2].isUnused)

        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [claude], agents: [], refreshedAt: now),
            now: now
        )

        XCTAssertEqual(presentation.providerCards[0].quotaBars.map(\.name), ["5-hour", "Weekly"])
        let rowTitles = presentation.providerRows.map(\.title)
        XCTAssertTrue(rowTitles.contains { $0.hasPrefix("5-hour:") })
        XCTAssertTrue(rowTitles.contains { $0.hasPrefix("Weekly:") })
        XCTAssertFalse(rowTitles.contains { $0.hasPrefix("Daily Routines:") })
        XCTAssertFalse(rowTitles.contains { $0.hasPrefix("Fable only:") })
    }

    func testEveryWindowUnusedKeepsAllWindowsInsteadOfAnEmptyCard() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let grok = ProviderSnapshot(
            id: "grok",
            displayName: "Grok",
            brand: .grok,
            quotaWindows: [
                QuotaWindow(name: "Daily", usedPercent: 0, resetsAt: nil),
                QuotaWindow(name: "Monthly", usedPercent: 0, resetsAt: nil),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )

        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [grok], agents: [], refreshedAt: now),
            now: now
        )

        XCTAssertEqual(presentation.providerCards[0].quotaBars.map(\.name), ["Daily", "Monthly"])
        XCTAssertEqual(presentation.providerCards[0].quotaBars.map(\.leftText), ["100% left", "100% left"])
        let rowTitles = presentation.providerRows.map(\.title)
        XCTAssertTrue(rowTitles.contains { $0.hasPrefix("Daily:") })
        XCTAssertTrue(rowTitles.contains { $0.hasPrefix("Monthly:") })
    }

    func testProviderWithNoWindowsStillHasAnEmptyBarList() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [provider(id: "grok", name: "Grok", brand: .grok, used: [], now: now)],
                agents: [],
                refreshedAt: now
            ),
            now: now
        )
        XCTAssertTrue(presentation.providerCards[0].quotaBars.isEmpty)
    }

    func testStatusSegmentIgnoresUnusedWindows() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let claude = ProviderSnapshot(
            id: "claude",
            displayName: "Claude",
            brand: .claude,
            quotaWindows: [
                QuotaWindow(name: "Daily Routines", usedPercent: 0, resetsAt: nil),
                QuotaWindow(name: "5-hour", usedPercent: 40, resetsAt: nil),
                QuotaWindow(name: "Fable only", usedPercent: 0, resetsAt: nil),
            ],
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )

        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(providers: [claude], agents: [], refreshedAt: now),
            now: now
        )

        XCTAssertEqual(claude.tightestQuotaWindow?.name, "5-hour")
        XCTAssertEqual(presentation.statusSegments[0].windowName, "5-hour")
        XCTAssertEqual(presentation.statusSegments[0].valueText, "60")
        XCTAssertEqual(presentation.providerCards[0].quotaBars.map(\.name), ["5-hour"])
    }

    func testCardStalenessIsPerProviderNotGlobal() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var staleClaude = provider(id: "claude", name: "Claude", brand: .claude, used: [20], now: now)
        staleClaude.isStale = true
        var staleAgent = agent(id: "rocky", name: "Rocky", now: now)
        staleAgent.isStale = true
        let snapshot = ModelBarSnapshot(
            providers: [
                provider(id: "codex", name: "OpenAI", brand: .openAI, used: [10], now: now),
                staleClaude,
            ],
            agents: [staleAgent],
            refreshedAt: now
        )

        let presentation = MenuPresentationBuilder.build(snapshot: snapshot, now: now)

        XCTAssertEqual(presentation.providerCards.map(\.isStale), [false, true])
        XCTAssertTrue(presentation.providerCards[0].ageText.hasPrefix("Updated"))
        XCTAssertTrue(presentation.providerCards[1].ageText.hasPrefix("Stale"))
        XCTAssertFalse(presentation.providerRows.map(\.title).first { $0.hasPrefix("OpenAI") }!.hasSuffix("stale"))
        XCTAssertTrue(presentation.providerRows.map(\.title).first { $0.hasPrefix("Claude") }!.hasSuffix("stale"))
        // The footer and overall state keep the global rule.
        XCTAssertTrue(presentation.footer.hasPrefix("Stale data"))
        XCTAssertTrue(presentation.accessibilityLabel.hasPrefix("Model quota left, stale."))
    }

    func testStaleHermesAgentAloneDoesNotMarkAnyProviderCardStale() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var staleAgent = agent(id: "rocky", name: "Rocky", now: now)
        staleAgent.isStale = true
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [
                    provider(id: "codex", name: "OpenAI", brand: .openAI, used: [10], now: now),
                ],
                agents: [staleAgent],
                refreshedAt: now
            ),
            now: now
        )

        XCTAssertEqual(presentation.providerCards.map(\.isStale), [false])
        XCTAssertTrue(presentation.providerCards[0].ageText.hasPrefix("Updated"))
    }

    func testOldSnapshotMarksEveryCardStale() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = now.addingTimeInterval(-7_200)
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [
                    provider(id: "codex", name: "OpenAI", brand: .openAI, used: [10], now: old),
                    provider(id: "claude", name: "Claude", brand: .claude, used: [30], now: old),
                ],
                agents: [],
                refreshedAt: old
            ),
            now: now
        )

        XCTAssertEqual(presentation.providerCards.map(\.isStale), [true, true])
        XCTAssertEqual(presentation.providerCards[0].ageText, "Stale 2h ago")
        XCTAssertTrue(presentation.providerRows.map(\.title).allSatisfy {
            !$0.hasPrefix("OpenAI") || $0.hasSuffix("stale")
        })
    }

    func testMissingServiceStatusReadsStatusUnknownOnTheCard() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let presentation = MenuPresentationBuilder.build(
            snapshot: ModelBarSnapshot(
                providers: [provider(id: "grok", name: "Grok", brand: .grok, used: [5], now: now)],
                agents: [],
                refreshedAt: now
            ),
            now: now
        )

        XCTAssertEqual(presentation.providerCards[0].statusText, "Status unknown")
        XCTAssertEqual(presentation.providerCards[0].statusCondition, .unknown)
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func provider(
        id: String,
        name: String,
        brand: ProviderBrand?,
        used: [Double],
        now: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            displayName: name,
            brand: brand,
            quotaWindows: used.map {
                QuotaWindow(name: "Primary", usedPercent: $0, resetsAt: nil)
            },
            tokens: nil,
            serviceStatus: nil,
            issue: nil,
            fetchedAt: now
        )
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
