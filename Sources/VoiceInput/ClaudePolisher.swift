import Foundation

enum ClaudePolisherError: Error, LocalizedError {
    case nonZeroExit(Int32, String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let stderr):
            return "claude exited \(code): \(stderr)"
        case .emptyOutput:
            return "claude returned empty output"
        }
    }
}

final class ClaudePolisher {
    /// Pipe `text` through `claude -p <systemPrompt>` and return the polished response.
    /// We run via a login shell so it picks up the same PATH the user sees in Terminal.
    func polish(_ text: String, systemPrompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.runClaude(prompt: systemPrompt, input: text)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func runClaude(prompt: String, input: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login shell so PATH includes user's claude binary location.
        // We pass the system prompt as the positional `-p` arg, and feed the user
        // text on stdin so we don't have to worry about shell-escaping it.
        let escaped = prompt.replacingOccurrences(of: "'", with: "'\\''")
        process.arguments = ["-lc", "claude -p '\(escaped)'"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let data = input.data(using: .utf8) {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try stdinPipe.fileHandleForWriting.close()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ClaudePolisherError.nonZeroExit(process.terminationStatus, err)
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ClaudePolisherError.emptyOutput }
        return trimmed
    }
}
