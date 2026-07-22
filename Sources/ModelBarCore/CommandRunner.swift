import Darwin
import Foundation

public struct CommandOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum CommandRunnerError: Error, Sendable {
    case launchFailed
    case timedOut
    case nonZeroExit(Int32, String)
}

public protocol CommandRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandOutput
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandOutput {
        try await Task.detached(priority: .utility) {
            try Self.runBlocking(
                executable: executable,
                arguments: arguments,
                timeout: timeout
            )
        }.value
    }

    private static func runBlocking(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> CommandOutput {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeCollector(pipe: outputPipe)
        let errorCollector = PipeCollector(pipe: errorPipe)

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            _ = outputCollector.finish()
            _ = errorCollector.finish()
            throw CommandRunnerError.launchFailed
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw CommandRunnerError.timedOut
        }

        process.waitUntilExit()
        let stdout = outputCollector.finish()
        let stderr = errorCollector.finish()
        let output = CommandOutput(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus
        )

        guard output.exitCode == 0 else {
            let stderrText = String(data: stderr, encoding: .utf8) ?? ""
            throw CommandRunnerError.nonZeroExit(output.exitCode, stderrText)
        }
        return output
    }
}

private final class PipeCollector: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()

    init(pipe: Pipe) {
        group.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }
            let captured = pipe.fileHandleForReading.readDataToEndOfFile()
            self.lock.lock()
            self.data = captured
            self.lock.unlock()
            self.group.leave()
        }
    }

    func finish() -> Data {
        group.wait()
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
