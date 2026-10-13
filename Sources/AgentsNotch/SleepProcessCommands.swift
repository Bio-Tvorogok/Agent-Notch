import Foundation

struct SleepCommandResult {
    let status: Int32
    let output: String
}

@MainActor
protocol SleepCommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> SleepCommandResult
}

struct SleepProcessCommands: SleepCommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> SleepCommandResult {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<SleepCommandResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = errors
                process.standardError = errors
                do {
                    try process.run()
                    let output = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    done.resume(returning: SleepCommandResult(status: process.terminationStatus,
                        output: String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
                } catch { done.resume(throwing: error) }
            }
        }
    }
}
