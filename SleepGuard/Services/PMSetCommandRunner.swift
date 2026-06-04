import Foundation

protocol PMSetRunning {
    func assertions() async throws -> String
    func log() async throws -> String
}

enum PMSetCommandError: LocalizedError {
    case nonZeroExit(command: String, status: Int32, stderr: String)
    case invalidOutputEncoding

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(command, status, stderr):
            return "\(command) 退出码 \(status)：\(stderr)"
        case .invalidOutputEncoding:
            return "无法读取 pmset 输出。"
        }
    }
}

struct PMSetCommandRunner: PMSetRunning {
    func assertions() async throws -> String {
        try await run(executable: "/usr/bin/pmset", arguments: ["-g", "assertions"], timeoutSeconds: 20)
    }

    func log() async throws -> String {
        let command = """
        /usr/bin/pmset -g log | /usr/bin/grep -E "Entering Sleep|Wake from|Wake reason|DarkWake" | /usr/bin/tail -n 200
        """
        return try await run(executable: "/bin/sh", arguments: ["-c", command], timeoutSeconds: 45)
    }

    private func run(executable: String, arguments: [String], timeoutSeconds: TimeInterval) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            let timeout = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
            process.waitUntilExit()
            timeout.cancel()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw PMSetCommandError.nonZeroExit(
                    command: "\(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " "))",
                    status: process.terminationStatus,
                    stderr: stderr
                )
            }

            guard let output = String(data: outputData, encoding: .utf8) else {
                throw PMSetCommandError.invalidOutputEncoding
            }
            return output
        }.value
    }
}
