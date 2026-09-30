import FluidAudio

typealias FluidAudioDownloadError = DownloadError

enum FluidAudioDownloadErrorClassifier {
    static func category(of error: Error) -> InstallFailureCategory? {
        guard let error = error as? FluidAudioDownloadError else { return nil }
        switch error {
        case .stalled, .networkDisabled, .rateLimited: return .network
        case .modelNotFound, .modelMissing, .invalidArtifact, .htmlErrorResponse: return .validation
        default: return .other
        }
    }
}
