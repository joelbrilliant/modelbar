import Foundation

public struct ProviderRegistry: Sendable {
    public let providers: [any ProviderAdapter]

    public init(providers: [any ProviderAdapter]) {
        self.providers = providers
    }

    private func applyingRegisteredMetadata(
        to snapshot: ProviderSnapshot
    ) -> ProviderSnapshot {
        guard let provider = providers.first(where: { $0.id == snapshot.id }) else {
            return snapshot
        }
        var result = snapshot
        result.brand = provider.brand
        return result
    }

    public func applyingRegisteredMetadata(
        to snapshot: ModelBarSnapshot
    ) -> ModelBarSnapshot {
        var result = snapshot
        let registeredIDs = Set(providers.map(\.id))
        result.providers = snapshot.providers
            .filter { registeredIDs.contains($0.id) }
            .map { applyingRegisteredMetadata(to: $0) }
        return result
    }

    public static func standard(
        codexBarExecutable: URL,
        homeDirectory: URL
    ) -> ProviderRegistry {
        let codex = CodexBarProviderAdapter(
            configuration: CodexBarProviderConfiguration(
                id: "codex",
                displayName: "OpenAI",
                brand: .openAI,
                cliProviderName: "codex",
                primaryWindowName: "Primary",
                secondaryWindowName: "Weekly"
            ),
            executable: codexBarExecutable,
            tokenReader: CodexBarCostTokenReader(
                executable: codexBarExecutable,
                providerName: "codex"
            )
        )
        let claude = CodexBarProviderAdapter(
            configuration: CodexBarProviderConfiguration(
                id: "claude",
                displayName: "Claude",
                brand: .claude,
                cliProviderName: "claude",
                primaryWindowName: "5-hour",
                secondaryWindowName: "Weekly"
            ),
            executable: codexBarExecutable,
            tokenReader: CodexBarCostTokenReader(
                executable: codexBarExecutable,
                providerName: "claude"
            )
        )
        let grok = CodexBarProviderAdapter(
            configuration: CodexBarProviderConfiguration(
                id: "grok",
                displayName: "Grok",
                brand: .grok,
                cliProviderName: "grok",
                primaryWindowName: "Quota",
                secondaryWindowName: "Secondary"
            ),
            executable: codexBarExecutable,
            tokenReader: GrokLocalTokenReader(
                sessionsDirectory: homeDirectory
                    .appendingPathComponent(".grok")
                    .appendingPathComponent("sessions")
            )
        )
        return ProviderRegistry(providers: [codex, claude, grok])
    }
}

public struct RefreshService: Sendable {
    public let registry: ProviderRegistry
    public let runner: any CommandRunning
    public let agentSource: any AgentTokenSource

    public init(
        registry: ProviderRegistry,
        runner: any CommandRunning,
        agentSource: any AgentTokenSource
    ) {
        self.registry = registry
        self.runner = runner
        self.agentSource = agentSource
    }

    public func refresh(
        now: Date = Date(),
        enabledProviderIDs: Set<String>? = nil
    ) async -> ModelBarSnapshot {
        async let providers = fetchProviders(
            now: now,
            enabledProviderIDs: enabledProviderIDs
        )
        async let agents = agentSource.fetch(now: now)
        return await ModelBarSnapshot(
            providers: providers,
            agents: agents,
            refreshedAt: now
        )
    }

    private func fetchProviders(
        now: Date,
        enabledProviderIDs: Set<String>?
    ) async -> [ProviderSnapshot] {
        var results: [ProviderSnapshot] = []
        let providers = registry.providers.filter { provider in
            enabledProviderIDs?.contains(provider.id) ?? true
        }
        for provider in providers {
            let reading = await provider.fetch(using: runner, now: now)
            results.append(
                ProviderSnapshot(
                    id: provider.id,
                    displayName: provider.displayName,
                    brand: provider.brand,
                    quotaWindows: reading.quotaWindows,
                    tokens: reading.tokens,
                    serviceStatus: reading.serviceStatus,
                    issue: reading.issue,
                    fetchedAt: now
                )
            )
        }
        return results
    }
}

public actor RefreshCoordinator {
    private let service: RefreshService
    private var inFlight: (
        generation: Int,
        enabledProviderIDs: Set<String>?,
        task: Task<ModelBarSnapshot, Never>
    )?
    private var nextGeneration = 0

    public init(service: RefreshService) {
        self.service = service
    }

    public func refresh(
        now: Date = Date(),
        enabledProviderIDs: Set<String>? = nil
    ) async -> ModelBarSnapshot {
        if let inFlight,
           inFlight.enabledProviderIDs == enabledProviderIDs {
            return await inFlight.task.value
        }
        if let inFlight {
            _ = await inFlight.task.value
            if self.inFlight?.generation == inFlight.generation {
                self.inFlight = nil
            }
            return await refresh(
                now: now,
                enabledProviderIDs: enabledProviderIDs
            )
        }

        nextGeneration += 1
        let generation = nextGeneration
        let task = Task {
            await service.refresh(
                now: now,
                enabledProviderIDs: enabledProviderIDs
            )
        }
        inFlight = (generation, enabledProviderIDs, task)
        let snapshot = await task.value
        if inFlight?.generation == generation {
            inFlight = nil
        }
        return snapshot
    }
}
