import Foundation
@testable import ModelBarCore

struct UnusedRunner: CommandRunning {
    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandOutput {
        throw CommandRunnerError.launchFailed
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ModelBarTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
