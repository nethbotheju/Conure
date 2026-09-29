import Foundation

enum CLIRecord: Sendable {
    case event(CLIEvent)
    case malformed(String)
}

final class JSONLinesDecoder: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [CLIRecord] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var records: [CLIRecord] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let record = decode(line) { records.append(record) }
        }
        return records
    }

    func finish() -> [CLIRecord] {
        lock.lock()
        defer { lock.unlock() }
        let line = buffer
        buffer = Data()
        return decode(line).map { [$0] } ?? []
    }

    private func decode(_ line: Data) -> CLIRecord? {
        guard !line.isEmpty else { return nil }
        do {
            return .event(try JSONDecoder().decode(CLIEvent.self, from: line))
        } catch {
            let preview = String(decoding: line.prefix(200), as: UTF8.self)
            return .malformed("Invalid CLI JSON line \(String(reflecting: preview)): \(error.localizedDescription)")
        }
    }
}
