import Foundation

struct JobCompletion {
    private(set) var stdoutFinished = false
    private(set) var stderrFinished = false
    private(set) var exitStatus: (code: Int32, reason: Process.TerminationReason)?
    private(set) var terminalEvent: CLIEvent?
    private var stderrTail = Data()
    private let tailLimit = 4096

    mutating func receive(_ event: CLIEvent) {
        if event.type != .progress, terminalEvent == nil {
            terminalEvent = event
        }
    }

    mutating func appendStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > tailLimit {
            stderrTail.removeFirst(stderrTail.count - tailLimit)
        }
    }

    mutating func finishStdout() { stdoutFinished = true }
    mutating func finishStderr() { stderrFinished = true }
    mutating func exited(code: Int32, reason: Process.TerminationReason) {
        exitStatus = (code, reason)
    }

    var result: JobStatus? {
        guard stdoutFinished, stderrFinished, let exitStatus else { return nil }
        if exitStatus.code == 0, exitStatus.reason == .exit {
            switch terminalEvent?.type {
            case .done:
                if let output = terminalEvent?.outputPath, !output.isEmpty {
                    return .done(output: output)
                }
                return .failed("Invalid done event: missing output path")
            case .error:
                return .failed(terminalEvent?.detail ?? "Unknown error")
            default:
                return .failed("Finished without reporting output")
            }
        }
        if terminalEvent?.type == .error {
            return .failed(terminalEvent?.detail ?? "Unknown error")
        }
        let message = exitStatus.reason == .uncaughtSignal
            ? "Terminated" : "Exited with code \(exitStatus.code)"
        let tail = String(decoding: stderrTail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(tail.isEmpty ? message : "\(message)\n\(tail)")
    }
}
