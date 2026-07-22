import Foundation

public struct ExampleProviderAdapter: ProviderAdapter {
    public let id = "example"
    public let displayName = "Example"
    public let brand: ProviderBrand? = ProviderBrand(
        lightModeAccent: ProviderBrandColour(red: 70, green: 90, blue: 220),
        darkModeAccent: ProviderBrandColour(red: 130, green: 150, blue: 255)
    )

    private let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public func fetch(
        using runner: any CommandRunning,
        now: Date
    ) async -> ProviderReading {
        do {
            let output = try await runner.run(
                executable: executable,
                arguments: ["usage", "json"],
                timeout: 20
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Payload.self, from: output.stdout)
            return ProviderReading(
                quotaWindows: payload.windows.map {
                    QuotaWindow(
                        name: $0.name,
                        usedPercent: $0.usedPercent,
                        resetsAt: $0.resetsAt
                    )
                },
                tokens: payload.tokens.map {
                    TokenUsage(
                        recentTokens: $0.recent,
                        sevenDayTokens: $0.sevenDays,
                        recentLabel: $0.recentLabel,
                        qualifier: "provider reported"
                    )
                },
                serviceStatus: nil,
                issue: nil
            )
        } catch CommandRunnerError.timedOut {
            return failure(
                SourceIssue(kind: .timeout, message: "Example refresh timed out")
            )
        } catch let CommandRunnerError.nonZeroExit(_, stderr) {
            let lowercased = stderr.lowercased()
            let kind: SourceIssueKind
            if lowercased.contains("login") || lowercased.contains("auth") {
                kind = .authentication
            } else if lowercased.contains("network") ||
                        lowercased.contains("connection") ||
                        lowercased.contains("offline") ||
                        lowercased.contains("dns") {
                kind = .network
            } else {
                kind = .provider
            }
            return failure(
                SourceIssue(kind: kind, message: "Example provider unavailable")
            )
        } catch CommandRunnerError.launchFailed {
            return failure(
                SourceIssue(kind: .unavailable, message: "Example command unavailable")
            )
        } catch is DecodingError {
            return failure(
                SourceIssue(kind: .invalidData, message: "Example returned invalid data")
            )
        } catch {
            return failure(
                SourceIssue(kind: .unavailable, message: "Example provider unavailable")
            )
        }
    }

    private func failure(_ issue: SourceIssue) -> ProviderReading {
        ProviderReading(
            quotaWindows: [],
            tokens: nil,
            serviceStatus: nil,
            issue: issue
        )
    }
}

private struct Payload: Decodable {
    let windows: [Window]
    let tokens: Tokens?

    struct Window: Decodable {
        let name: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    struct Tokens: Decodable {
        let recent: Int64
        let sevenDays: Int64
        let recentLabel: String
    }
}
