import Foundation
import XCTest
@testable import ModelBarCore

final class RefreshServiceTests: XCTestCase {
    func testRegistryPreservesOrderWithAFourthProvider() async {
        let names = ["OpenAI", "Claude", "Grok", "Future"]
        let providers: [any ProviderAdapter] = names.enumerated().map { index, name in
            FakeProvider(id: String(index), displayName: name, delay: UInt64(4 - index))
        }
        let service = RefreshService(
            registry: ProviderRegistry(providers: providers),
            runner: UnusedRunner(),
            agentSource: EmptyAgentSource()
        )

        let snapshot = await service.refresh(now: Date(timeIntervalSince1970: 123))

        XCTAssertEqual(snapshot.providers.map(\.displayName), names)
    }

    func testAdapterIdentityAndBrandFlowThroughRegistryWithoutRendererChanges() async {
        let brand = ProviderBrand(
            lightModeAccent: ProviderBrandColour(red: 12, green: 34, blue: 56),
            darkModeAccent: ProviderBrandColour(red: 78, green: 90, blue: 123)
        )
        let provider = FakeProvider(
            id: "future",
            displayName: "Future",
            delay: 0,
            brand: brand
        )
        let service = RefreshService(
            registry: ProviderRegistry(providers: [provider]),
            runner: UnusedRunner(),
            agentSource: EmptyAgentSource()
        )

        let snapshot = await service.refresh(now: Date(timeIntervalSince1970: 123))
        let presentation = MenuPresentationBuilder.build(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 123)
        )

        XCTAssertEqual(snapshot.providers[0].id, "future")
        XCTAssertEqual(snapshot.providers[0].displayName, "Future")
        XCTAssertEqual(snapshot.providers[0].brand, brand)
        XCTAssertEqual(presentation.providerCards[0].brand, brand)
        XCTAssertEqual(presentation.providerCards[0].statusText, "Status unknown")
    }

    func testRegistryRestoresBrandToLegacyCachedSnapshot() {
        let brand = ProviderBrand(
            lightModeAccent: ProviderBrandColour(red: 12, green: 34, blue: 56),
            darkModeAccent: ProviderBrandColour(red: 78, green: 90, blue: 123)
        )
        let registry = ProviderRegistry(
            providers: [
                FakeProvider(
                    id: "future",
                    displayName: "Future",
                    delay: 0,
                    brand: brand
                ),
            ]
        )
        let cached = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "future",
                    displayName: "Future",
                    quotaWindows: [],
                    tokens: nil,
                    serviceStatus: nil,
                    issue: nil,
                    fetchedAt: Date(timeIntervalSince1970: 100)
                ),
                ProviderSnapshot(
                    id: "retired",
                    displayName: "Retired",
                    quotaWindows: [],
                    tokens: nil,
                    serviceStatus: nil,
                    issue: nil,
                    fetchedAt: Date(timeIntervalSince1970: 100)
                ),
            ],
            agents: [],
            refreshedAt: Date(timeIntervalSince1970: 100)
        )

        let restored = registry.applyingRegisteredMetadata(to: cached)

        XCTAssertEqual(restored.providers.map(\.id), ["future"])
        XCTAssertEqual(restored.providers[0].brand, brand)
    }

    func testDisabledProvidersAreNotFetched() async {
        let enabledCounter = FetchCounter()
        let disabledCounter = FetchCounter()
        let service = RefreshService(
            registry: ProviderRegistry(
                providers: [
                    CountingProvider(id: "codex", counter: enabledCounter),
                    CountingProvider(id: "claude", counter: disabledCounter),
                ]
            ),
            runner: UnusedRunner(),
            agentSource: EmptyAgentSource()
        )

        let snapshot = await service.refresh(enabledProviderIDs: ["codex"])
        let enabledFetches = await enabledCounter.value
        let disabledFetches = await disabledCounter.value

        XCTAssertEqual(snapshot.providers.map(\.id), ["codex"])
        XCTAssertEqual(enabledFetches, 1)
        XCTAssertEqual(disabledFetches, 0)
    }

    func testFailedRefreshKeepsLastSuccessfulValuesAndMarksThemStale() {
        let now = Date()
        let previousProvider = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            quotaWindows: [QuotaWindow(name: "Weekly", usedPercent: 50, resetsAt: nil)],
            tokens: TokenUsage(recentTokens: 10, sevenDayTokens: 20, recentLabel: "today"),
            serviceStatus: ServiceStatus(
                condition: .operational,
                description: "Operational",
                url: nil
            ),
            issue: nil,
            fetchedAt: now
        )
        let failedProvider = ProviderSnapshot(
            id: "codex",
            displayName: "OpenAI",
            quotaWindows: [],
            tokens: nil,
            serviceStatus: nil,
            issue: SourceIssue(kind: .timeout, message: "Quota refresh timed out"),
            fetchedAt: now.addingTimeInterval(60)
        )
        let previous = ModelBarSnapshot(
            providers: [previousProvider],
            agents: [],
            refreshedAt: now
        )
        let fresh = ModelBarSnapshot(
            providers: [failedProvider],
            agents: [],
            refreshedAt: now.addingTimeInterval(60)
        )

        let merged = SnapshotMerger.merge(fresh: fresh, previous: previous)

        XCTAssertEqual(merged.providers[0].quotaWindows, previousProvider.quotaWindows)
        XCTAssertEqual(merged.providers[0].tokens, previousProvider.tokens)
        XCTAssertEqual(merged.providers[0].serviceStatus, previousProvider.serviceStatus)
        XCTAssertTrue(merged.providers[0].isStale)
    }

    func testRepeatedFailuresKeepTheCachedQuotaAge() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = [QuotaWindow(name: "Weekly", usedPercent: 50, resetsAt: nil)]
        func failed(at date: Date) -> ModelBarSnapshot {
            ModelBarSnapshot(
                providers: [
                    ProviderSnapshot(
                        id: "codex",
                        displayName: "OpenAI",
                        quotaWindows: [],
                        tokens: nil,
                        serviceStatus: nil,
                        issue: SourceIssue(kind: .timeout, message: "Quota refresh timed out"),
                        fetchedAt: date
                    ),
                ],
                agents: [],
                refreshedAt: date
            )
        }
        let good = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "codex",
                    displayName: "OpenAI",
                    quotaWindows: quota,
                    tokens: nil,
                    serviceStatus: nil,
                    issue: nil,
                    fetchedAt: start
                ),
            ],
            agents: [],
            refreshedAt: start
        )

        let firstFailure = SnapshotMerger.merge(
            fresh: failed(at: start.addingTimeInterval(3_600)),
            previous: good
        )
        let now = start.addingTimeInterval(7_200)
        let secondFailure = SnapshotMerger.merge(fresh: failed(at: now), previous: firstFailure)

        XCTAssertEqual(secondFailure.providers[0].fetchedAt, start)
        XCTAssertTrue(secondFailure.providers[0].isStale)
        let card = MenuPresentationBuilder.build(snapshot: secondFailure, now: now).providerCards[0]
        XCTAssertEqual(card.ageText, "Stale 2h ago")
    }

    func testTokenOnlyIssueWithFreshQuotaIsNotStaleAndBackfillsTokens() {
        let now = Date()
        let cachedTokens = TokenUsage(recentTokens: 10, sevenDayTokens: 20, recentLabel: "today")
        let cachedStatus = ServiceStatus(condition: .operational, description: "Operational", url: nil)
        let previous = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "claude",
                    displayName: "Claude",
                    quotaWindows: [QuotaWindow(name: "5-hour", usedPercent: 10, resetsAt: nil)],
                    tokens: cachedTokens,
                    serviceStatus: cachedStatus,
                    issue: nil,
                    fetchedAt: now
                ),
            ],
            agents: [],
            refreshedAt: now
        )
        let freshWindows = [QuotaWindow(name: "5-hour", usedPercent: 66, resetsAt: nil)]
        let fresh = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "claude",
                    displayName: "Claude",
                    quotaWindows: freshWindows,
                    tokens: nil,
                    serviceStatus: nil,
                    issue: SourceIssue(kind: .timeout, message: "Token history refresh timed out"),
                    fetchedAt: now.addingTimeInterval(60)
                ),
            ],
            agents: [],
            refreshedAt: now.addingTimeInterval(60)
        )

        let merged = SnapshotMerger.merge(fresh: fresh, previous: previous).providers[0]

        XCTAssertEqual(merged.quotaWindows, freshWindows)
        XCTAssertEqual(merged.tokens, cachedTokens)
        XCTAssertEqual(merged.serviceStatus, cachedStatus)
        XCTAssertEqual(merged.issue?.message, "Token history refresh timed out")
        XCTAssertFalse(merged.isStale)
    }

    func testIssueWithoutCachedQuotaIsNotStale() {
        let now = Date()
        let previous = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "grok",
                    displayName: "Grok",
                    quotaWindows: [],
                    tokens: TokenUsage(recentTokens: 1, sevenDayTokens: 2, recentLabel: "today"),
                    serviceStatus: nil,
                    issue: nil,
                    fetchedAt: now
                ),
            ],
            agents: [],
            refreshedAt: now
        )
        let fresh = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "grok",
                    displayName: "Grok",
                    quotaWindows: [],
                    tokens: nil,
                    serviceStatus: nil,
                    issue: SourceIssue(kind: .network, message: "Quota network error"),
                    fetchedAt: now.addingTimeInterval(60)
                ),
            ],
            agents: [],
            refreshedAt: now.addingTimeInterval(60)
        )

        let merged = SnapshotMerger.merge(fresh: fresh, previous: previous).providers[0]

        XCTAssertTrue(merged.quotaWindows.isEmpty)
        XCTAssertFalse(merged.isStale)
    }

    func testIssueWithNoPreviousSnapshotIsNotStale() {
        let now = Date()
        let fresh = ModelBarSnapshot(
            providers: [
                ProviderSnapshot(
                    id: "codex",
                    displayName: "OpenAI",
                    quotaWindows: [],
                    tokens: nil,
                    serviceStatus: nil,
                    issue: SourceIssue(kind: .timeout, message: "Quota refresh timed out"),
                    fetchedAt: now
                ),
            ],
            agents: [],
            refreshedAt: now
        )

        XCTAssertFalse(SnapshotMerger.merge(fresh: fresh, previous: nil).providers[0].isStale)
        XCTAssertFalse(
            SnapshotMerger.merge(
                fresh: fresh,
                previous: ModelBarSnapshot(providers: [], agents: [], refreshedAt: now)
            ).providers[0].isStale
        )
    }

    func testAgentWithIssueAndCachedTokensStaysStale() {
        let now = Date()
        let cachedTokens = TokenUsage(recentTokens: 5, sevenDayTokens: 50, recentLabel: "24h")
        func agent(tokens: TokenUsage?, issue: SourceIssue?, at date: Date) -> AgentTokenSnapshot {
            AgentTokenSnapshot(
                id: "rocky",
                displayName: "Rocky",
                tokens: tokens,
                issue: issue,
                usesLegacySchema: false,
                fetchedAt: date
            )
        }
        let previous = ModelBarSnapshot(
            providers: [],
            agents: [agent(tokens: cachedTokens, issue: nil, at: now)],
            refreshedAt: now
        )
        let fresh = ModelBarSnapshot(
            providers: [],
            agents: [
                agent(
                    tokens: nil,
                    issue: SourceIssue(kind: .unavailable, message: "Database busy"),
                    at: now.addingTimeInterval(60)
                ),
            ],
            refreshedAt: now.addingTimeInterval(60)
        )

        let merged = SnapshotMerger.merge(fresh: fresh, previous: previous).agents[0]

        XCTAssertEqual(merged.tokens, cachedTokens)
        XCTAssertTrue(merged.isStale)
    }

    func testConcurrentRefreshTriggersShareOneProviderBatch() async {
        let counter = FetchCounter()
        let service = RefreshService(
            registry: ProviderRegistry(
                providers: [CountingProvider(counter: counter)]
            ),
            runner: UnusedRunner(),
            agentSource: EmptyAgentSource()
        )
        let coordinator = RefreshCoordinator(service: service)

        async let first = coordinator.refresh()
        async let second = coordinator.refresh()
        _ = await (first, second)
        let fetchCount = await counter.value

        XCTAssertEqual(fetchCount, 1)
    }

    func testDifferentProviderSelectionsRunInSeparateOrderedBatches() async {
        let codexCounter = FetchCounter()
        let claudeCounter = FetchCounter()
        let coordinator = RefreshCoordinator(
            service: RefreshService(
                registry: ProviderRegistry(
                    providers: [
                        CountingProvider(id: "codex", counter: codexCounter),
                        CountingProvider(id: "claude", counter: claudeCounter),
                    ]
                ),
                runner: UnusedRunner(),
                agentSource: EmptyAgentSource()
            )
        )

        let firstTask = Task {
            await coordinator.refresh(enabledProviderIDs: ["codex"])
        }
        try? await Task.sleep(for: .milliseconds(5))
        let secondTask = Task {
            await coordinator.refresh(enabledProviderIDs: ["claude"])
        }
        let first = await firstTask.value
        let second = await secondTask.value
        let codexFetches = await codexCounter.value
        let claudeFetches = await claudeCounter.value

        XCTAssertEqual(first.providers.map(\.id), ["codex"])
        XCTAssertEqual(second.providers.map(\.id), ["claude"])
        XCTAssertEqual(codexFetches, 1)
        XCTAssertEqual(claudeFetches, 1)
    }

    func testAgeOverThirtyMinutesIsStaleWithoutARefreshFailure() {
        let snapshot = ModelBarSnapshot(
            providers: [],
            agents: [],
            refreshedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 1_899)))
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 1_901)))
    }
}

private struct FakeProvider: ProviderAdapter {
    let id: String
    let displayName: String
    let delay: UInt64
    var brand: ProviderBrand? = nil

    func fetch(using runner: any CommandRunning, now: Date) async -> ProviderReading {
        try? await Task.sleep(nanoseconds: delay * 1_000_000)
        return ProviderReading(
            quotaWindows: [],
            tokens: nil,
            serviceStatus: nil,
            issue: nil
        )
    }
}

private struct EmptyAgentSource: AgentTokenSource {
    func fetch(now: Date) async -> [AgentTokenSnapshot] { [] }
}

private actor FetchCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct CountingProvider: ProviderAdapter {
    let id: String
    var displayName: String { id.capitalized }
    let counter: FetchCounter

    init(id: String = "counting", counter: FetchCounter) {
        self.id = id
        self.counter = counter
    }

    func fetch(using runner: any CommandRunning, now: Date) async -> ProviderReading {
        await counter.increment()
        try? await Task.sleep(for: .milliseconds(50))
        return ProviderReading(
            quotaWindows: [],
            tokens: nil,
            serviceStatus: nil,
            issue: nil
        )
    }
}
