import Foundation

public enum OutputCollisionPolicy: String, Sendable {
    case fail
    case replace
    case unique
}

public enum OutputPlanner {
    public static func resolve(
        desired: URL,
        policy: OutputCollisionPolicy,
        claimedPaths: Set<String> = []
    ) throws -> URL {
        switch policy {
        case .replace:
            return desired
        case .fail:
            guard !isTaken(desired, claimedPaths) else {
                throw ConureError.outputExists(desired)
            }
            return desired
        case .unique:
            guard isTaken(desired, claimedPaths) else { return desired }
            let base = desired.deletingPathExtension().lastPathComponent
            let directory = desired.deletingLastPathComponent()
            let ext = desired.pathExtension
            var index = 2
            while true {
                let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
                let candidate = directory.appendingPathComponent(name)
                guard isTaken(candidate, claimedPaths) else { return candidate }
                index += 1
            }
        }
    }

    public static func resolveBatch(
        sources: [URL],
        format: OutputFormat,
        overrideDirectory: URL?,
        policy: OutputCollisionPolicy
    ) throws -> [URL] {
        var claimed: Set<String> = []
        var resolved: [URL] = []
        resolved.reserveCapacity(sources.count)
        for source in sources {
            let desired = TranscriptWriter.outputURL(for: source, format: format, overrideDirectory: overrideDirectory)
            let url = try resolve(desired: desired, policy: policy, claimedPaths: claimed)
            claimed.insert(url.path)
            resolved.append(url)
        }
        return resolved
    }

    private static func isTaken(_ url: URL, _ claimedPaths: Set<String>) -> Bool {
        claimedPaths.contains(url.path) || FileManager.default.fileExists(atPath: url.path)
    }
}
