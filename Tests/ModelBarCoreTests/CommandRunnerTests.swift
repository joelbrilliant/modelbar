import Foundation
import XCTest
@testable import ModelBarCore

final class CommandRunnerTests: XCTestCase {
    func testCapturesOutputWithoutLeavingTheProcessRunning() async throws {
        let runner = ProcessCommandRunner()
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["provider-json"],
            timeout: 2
        )

        XCTAssertEqual(String(data: output.stdout, encoding: .utf8), "provider-json")
        XCTAssertEqual(output.exitCode, 0)
    }

    func testTerminatesACommandAtItsDeadline() async {
        let runner = ProcessCommandRunner()
        let startedAt = Date()

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch CommandRunnerError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
