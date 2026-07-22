import Foundation
import XCTest
@testable import ModelBarCore

final class ProviderParserTests: XCTestCase {
    func testCodexQuotaIncludesEveryReturnedWindow() throws {
        let parsed = try CodexBarJSONParser.parseQuota(
            try fixture("codex-quota"),
            primaryName: "Primary",
            secondaryName: "Weekly"
        )

        XCTAssertEqual(parsed.windows.map(\.name), ["Weekly", "Codex Spark Weekly"])
        XCTAssertEqual(parsed.windows[0].usedPercent, 50)
        XCTAssertEqual(parsed.windows[0].remainingPercent, 50)
        XCTAssertEqual(parsed.status?.condition, .operational)
    }

    func testClaudeStatusMapsDegradedWithoutRelyingOnColour() throws {
        let parsed = try CodexBarJSONParser.parseQuota(
            try fixture("claude-quota"),
            primaryName: "5-hour",
            secondaryName: "Weekly"
        )

        XCTAssertEqual(parsed.windows.map(\.name), ["5-hour", "Weekly"])
        XCTAssertEqual(parsed.status?.condition, .degraded)
        XCTAssertEqual(parsed.status?.description, "Partially Degraded Service")
    }

    func testGrokStatusRemainsUnknownWhenNoStatusObjectExists() throws {
        let parsed = try CodexBarJSONParser.parseQuota(
            try fixture("grok-quota"),
            primaryName: "Quota",
            secondaryName: "Secondary"
        )

        XCTAssertEqual(parsed.windows.count, 1)
        XCTAssertNil(parsed.status)
    }

    func testMajorStatusMapsToOutage() throws {
        let source = try XCTUnwrap(String(
            data: try fixture("claude-quota"),
            encoding: .utf8
        ))
        let outageData = Data(source.replacingOccurrences(
            of: "\"minor\"",
            with: "\"major\""
        ).utf8)

        let parsed = try CodexBarJSONParser.parseQuota(
            outageData,
            primaryName: "5-hour",
            secondaryName: "Weekly"
        )

        XCTAssertEqual(parsed.status?.condition, .outage)
    }

    func testMissingQuotaWindowsAreUnavailableRatherThanFalseZeroes() async {
        let adapter = testAdapter()
        let data = Data("[{\"usage\":{}}]".utf8)
        let snapshot = await adapter.fetch(
            using: FixedRunner(result: .success(data)),
            now: Date()
        )

        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertEqual(snapshot.issue?.kind, .invalidData)
    }

    func testTokenTotalsMapFromProductionShapedOutput() throws {
        let tokens = try CodexBarJSONParser.parseTokens(try fixture("provider-tokens"))

        XCTAssertEqual(tokens.recentTokens, 156_313_475)
        XCTAssertEqual(tokens.sevenDayTokens, 410_245_065)
        XCTAssertEqual(tokens.recentLabel, "today")
    }

    func testMalformedJSONUsesTheInvalidDataCategory() async {
        let adapter = testAdapter()
        let snapshot = await adapter.fetch(
            using: FixedRunner(result: .success(Data("{".utf8))),
            now: Date()
        )

        XCTAssertEqual(snapshot.issue?.kind, .invalidData)
    }

    func testAuthenticationAndNetworkFailuresRemainDistinct() async {
        let adapter = testAdapter()
        let authentication = await adapter.fetch(
            using: FixedRunner(result: .failure(.nonZeroExit(1, "login required"))),
            now: Date()
        )
        let network = await adapter.fetch(
            using: FixedRunner(result: .failure(.nonZeroExit(1, "network offline"))),
            now: Date()
        )

        XCTAssertEqual(authentication.issue?.kind, .authentication)
        XCTAssertEqual(network.issue?.kind, .network)
    }

    func testQuotaPercentagesClampAndSumToOneHundred() {
        let over = QuotaWindow(name: "Over", usedPercent: 140, resetsAt: nil)
        let under = QuotaWindow(name: "Under", usedPercent: -2, resetsAt: nil)

        XCTAssertEqual(over.usedPercent, 100)
        XCTAssertEqual(over.remainingPercent, 0)
        XCTAssertEqual(under.usedPercent, 0)
        XCTAssertEqual(under.remainingPercent, 100)
    }

    func testDisplayFormattingKeepsLargeTokenCountsScannable() {
        XCTAssertEqual(DisplayFormatting.tokens(999), "999")
        XCTAssertEqual(DisplayFormatting.tokens(1_200), "1.2K")
        XCTAssertEqual(DisplayFormatting.tokens(156_313_475), "156M")
        XCTAssertEqual(DisplayFormatting.tokens(1_791_831_092), "1.8B")
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: url)
    }

    private func testAdapter() -> CodexBarProviderAdapter {
        CodexBarProviderAdapter(
            configuration: CodexBarProviderConfiguration(
                id: "test",
                displayName: "Test",
                cliProviderName: "test",
                primaryWindowName: "Primary",
                secondaryWindowName: "Secondary"
            ),
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            tokenReader: nil
        )
    }
}

private struct FixedRunner: CommandRunning {
    enum ResultValue: Sendable {
        case success(Data)
        case failure(CommandRunnerError)
    }

    let result: ResultValue

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandOutput {
        switch result {
        case let .success(data):
            return CommandOutput(stdout: data, stderr: Data(), exitCode: 0)
        case let .failure(error):
            throw error
        }
    }
}
