import Foundation

public protocol ProviderAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var brand: ProviderBrand? { get }

    func fetch(using runner: any CommandRunning, now: Date) async -> ProviderReading
}

public extension ProviderAdapter {
    var brand: ProviderBrand? { nil }
}

public protocol ProviderTokenReading: Sendable {
    func read(using runner: any CommandRunning, now: Date) async throws -> TokenUsage
}

public struct CodexBarProviderConfiguration: Sendable {
    public let id: String
    public let displayName: String
    public let brand: ProviderBrand?
    public let cliProviderName: String
    public let primaryWindowName: String
    public let secondaryWindowName: String

    public init(
        id: String,
        displayName: String,
        brand: ProviderBrand? = nil,
        cliProviderName: String,
        primaryWindowName: String,
        secondaryWindowName: String
    ) {
        self.id = id
        self.displayName = displayName
        self.brand = brand
        self.cliProviderName = cliProviderName
        self.primaryWindowName = primaryWindowName
        self.secondaryWindowName = secondaryWindowName
    }
}

public struct CodexBarProviderAdapter: ProviderAdapter {
    public let configuration: CodexBarProviderConfiguration
    public let executable: URL
    public let tokenReader: (any ProviderTokenReading)?

    public var id: String { configuration.id }
    public var displayName: String { configuration.displayName }
    public var brand: ProviderBrand? { configuration.brand }

    public init(
        configuration: CodexBarProviderConfiguration,
        executable: URL,
        tokenReader: (any ProviderTokenReading)?
    ) {
        self.configuration = configuration
        self.executable = executable
        self.tokenReader = tokenReader
    }

    public func fetch(
        using runner: any CommandRunning,
        now: Date
    ) async -> ProviderReading {
        let quotaResult = await fetchQuota(using: runner)
        let tokenResult = await fetchTokens(using: runner, now: now)

        var windows: [QuotaWindow] = []
        var serviceStatus: ServiceStatus?
        var tokens: TokenUsage?
        var issue: SourceIssue?

        switch quotaResult {
        case let .success(parsed):
            windows = parsed.windows
            serviceStatus = parsed.status
        case let .failure(error):
            issue = Self.issue(for: error, area: "Quota")
        }

        switch tokenResult {
        case let .success(value):
            tokens = value
        case let .failure(error):
            if issue == nil {
                issue = Self.issue(for: error, area: "Token history")
            }
        }

        return ProviderReading(
            quotaWindows: windows,
            tokens: tokens,
            serviceStatus: serviceStatus,
            issue: issue
        )
    }

    private func fetchQuota(
        using runner: any CommandRunning
    ) async -> Result<ParsedQuota, Error> {
        do {
            let output = try await runner.run(
                executable: executable,
                arguments: [
                    "--provider", configuration.cliProviderName,
                    "--format", "json",
                    "--status",
                ],
                timeout: 20
            )
            return .success(
                try CodexBarJSONParser.parseQuota(
                    output.stdout,
                    primaryName: configuration.primaryWindowName,
                    secondaryName: configuration.secondaryWindowName
                )
            )
        } catch {
            return .failure(error)
        }
    }

    private func fetchTokens(
        using runner: any CommandRunning,
        now: Date
    ) async -> Result<TokenUsage?, Error> {
        guard let tokenReader else {
            return .success(nil)
        }
        do {
            return .success(try await tokenReader.read(using: runner, now: now))
        } catch {
            return .failure(error)
        }
    }

    private static func issue(for error: Error, area: String) -> SourceIssue {
        if case CommandRunnerError.timedOut = error {
            return SourceIssue(kind: .timeout, message: "\(area) refresh timed out")
        }
        if case let CommandRunnerError.nonZeroExit(_, stderr) = error {
            let lowercased = stderr.lowercased()
            if lowercased.contains("auth") || lowercased.contains("login") ||
                lowercased.contains("credential") {
                return SourceIssue(
                    kind: .authentication,
                    message: "\(area) authentication required"
                )
            }
            if lowercased.contains("network") || lowercased.contains("connection") ||
                lowercased.contains("offline") || lowercased.contains("dns") ||
                lowercased.contains("resolve host") {
                return SourceIssue(kind: .network, message: "\(area) network error")
            }
            return SourceIssue(kind: .provider, message: "\(area) provider error")
        }
        if error is CodexBarParseError {
            return SourceIssue(kind: .invalidData, message: "\(area) returned invalid data")
        }
        return SourceIssue(kind: .unavailable, message: "\(area) unavailable")
    }
}

public struct CodexBarCostTokenReader: ProviderTokenReading {
    public let executable: URL
    public let providerName: String

    public init(executable: URL, providerName: String) {
        self.executable = executable
        self.providerName = providerName
    }

    public func read(
        using runner: any CommandRunning,
        now: Date
    ) async throws -> TokenUsage {
        let output = try await runner.run(
            executable: executable,
            arguments: [
                "cost",
                "--provider", providerName,
                "--format", "json",
                "--days", "7",
            ],
            timeout: 20
        )
        return try CodexBarJSONParser.parseTokens(output.stdout)
    }
}
