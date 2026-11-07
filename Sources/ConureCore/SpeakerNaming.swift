import Foundation

public enum SpeakerNameError: LocalizedError, Equatable {
    case empty
    case controlCharacters
    case tooLong(Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Speaker names cannot be blank. Use --clear <id> to remove a name."
        case .controlCharacters:
            return "Speaker names cannot contain newlines or control characters."
        case .tooLong(let limit):
            return "Speaker names must be \(limit) characters or fewer."
        }
    }
}

public enum SpeakerName {
    public static let maximumLength = 60

    public static func normalized(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpeakerNameError.empty }
        let hasControl = trimmed.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F
        }
        guard !hasControl else { throw SpeakerNameError.controlCharacters }
        guard trimmed.count <= maximumLength else { throw SpeakerNameError.tooLong(maximumLength) }
        return trimmed
    }

    public static func parseAssignment(_ argument: String) throws -> (id: Int, name: String) {
        let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let id = Int(parts[0]), id > 0 else {
            throw SpeakerInputError.invalidAssignment(argument)
        }
        return (id, try normalized(String(parts[1])))
    }
}

public enum SpeakerInputError: LocalizedError, Equatable {
    case invalidAssignment(String)
    case invalidSpeakerCount(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidAssignment(let argument):
            return "Invalid speaker assignment \"\(argument)\"; expected <id>=<name>, e.g. 1=Ada."
        case .invalidSpeakerCount(let count):
            return "Speaker count must be between 1 and \(SpeakerLimits.maximum); got \(count)."
        }
    }
}

public enum SpeakerLimits {
    public static let maximum = 4

    public static func validate(count: Int) throws {
        guard (1...maximum).contains(count) else {
            throw SpeakerInputError.invalidSpeakerCount(count)
        }
    }
}
