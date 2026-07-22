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
        XCTAssertEqual(presentation.providerCards[0].statusText, "Service status unknown")
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
