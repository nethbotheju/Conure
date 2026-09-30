import Foundation
import AudioCommon
import FluidAudio

public struct ModelDescriptor: Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case asr
        case diarization
        case vad
    }

    public enum Engine: String, Sendable, Codable {
        case speechSwift
        case fluidAudio
    }

    public let engine: Engine
    public let id: String
    public let displayName: String
    public let hfRepo: String
    public let kind: Kind
    public let files: [String]
    public let approxSizeMB: Int
    public let notes: String

    public init(
        id: String,
        displayName: String,
        hfRepo: String,
        kind: Kind,
        files: [String],
        approxSizeMB: Int,
        notes: String,
        engine: Engine = .speechSwift
    ) {
        self.engine = engine
        self.id = id
        self.displayName = displayName
        self.hfRepo = hfRepo
        self.kind = kind
        self.files = files
        self.approxSizeMB = approxSizeMB
        self.notes = notes
    }

    public var isRequired: Bool { kind != .asr }
    public var isDefault: Bool { id == ModelStore.defaultModelID }
}

public enum InstallFailureCategory: String, Sendable {
    case network
    case diskSpace
    case permission
    case validation
    case other

    var label: String {
        switch self {
        case .network: "network error"
        case .diskSpace: "disk space error"
        case .permission: "permission error"
        case .validation: "validation error"
        case .other: "download failed"
        }
    }
}

public enum ModelStoreError: LocalizedError {
    case cannotRemoveRequired(ModelDescriptor)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case installFailed(model: String, category: InstallFailureCategory, reason: String)

    public var errorDescription: String? {
        switch self {
        case .cannotRemoveRequired(let d):
            return "\(d.displayName) is required by Conure and cannot be removed"
        case .insufficientDiskSpace(let required, let available):
            return String(
                format: "Not enough disk space: %.0f MB needed, %.0f MB available — free up space and try again",
                Double(required) / 1_048_576,
                Double(available) / 1_048_576
            )
        case .installFailed(let model, let category, let reason):
            return "\(model): \(category.label) — \(reason)"
        }
    }

    /// NSFileWriteVolumeFullError, which the SDK does not expose to Swift as a
    /// `CocoaError.Code` case.
    static let fileWriteVolumeFullCode = 660

    public static func categorize(_ error: Error) -> InstallFailureCategory {
        if let downloadError = error as? AudioCommon.DownloadError {
            switch downloadError {
            case .networkUnavailable, .stalled: return .network
            case .checksumMismatch, .invalidRemoteFileName: return .validation
            case .failedToDownload: return .other
            }
        }
        if let category = FluidAudioDownloadErrorClassifier.category(of: error) {
            return category
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                return .network
            default:
                return .other
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: nsError.code) {
            case .fileWriteNoPermission, .fileReadNoPermission: return .permission
            default: break
            }
            if nsError.code == Self.fileWriteVolumeFullCode { return .diskSpace }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case ENOSPC: return .diskSpace
            case EACCES, EPERM, EROFS: return .permission
            default: break
            }
        }
        return .other
    }
}

public enum ModelStore {
    public enum InstallState: String, Sendable, Codable {
        case missing
        case incomplete
        case ready
    }

    public static let defaultModelID = "parakeet"

    public static let parakeet = ModelDescriptor(
        id: "parakeet",
        displayName: "Parakeet TDT 0.6B (CoreML INT8)",
        hfRepo: "aufklarer/Parakeet-TDT-v3-CoreML-INT8-30s",
        kind: .asr,
        files: [
            "encoder.mlmodelc/**", "decoder.mlmodelc/**", "joint.mlmodelc/**",
            "vocab.json", "config.json",
        ],
        approxSizeMB: 611,
        notes: "Fast and accurate (English) — recommended default"
    )

    public static let unified = ModelDescriptor(
        id: "parakeet-unified-en",
        displayName: "Parakeet Unified EN (punctuated)",
        hfRepo: "FluidInference/parakeet-unified-en-0.6b-coreml",
        kind: .asr,
        files: [],
        approxSizeMB: 590,
        notes: "English with built-in punctuation and capitalization (FluidAudio)",
        engine: .fluidAudio
    )

    public static let multilingual = ModelDescriptor(
        id: "parakeet-v3-multilingual",
        displayName: "Parakeet TDT v3 (multilingual)",
        hfRepo: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        kind: .asr,
        files: [],
        approxSizeMB: 465,
        notes: "Multilingual, auto-detect; optional language hint (FluidAudio)",
        engine: .fluidAudio
    )

    public static let sortformer = ModelDescriptor(
        id: "sortformer",
        displayName: "Sortformer Diarization (CoreML)",
        hfRepo: "aufklarer/Sortformer-Diarization-CoreML",
        kind: .diarization,
        files: ["Sortformer.mlmodelc/**", "config.json"],
        approxSizeMB: 60,
        notes: "Speaker diarization, up to 4 speakers, auto-downloaded with --speakers"
    )

    public static let silero = ModelDescriptor(
        id: "silero",
        displayName: "Silero VAD v6.2.1 (CoreML)",
        hfRepo: "aufklarer/Silero-VAD-v6.2.1-CoreML",
        kind: .vad,
        files: ["silero_vad.mlmodelc/**", "config.json"],
        approxSizeMB: 3,
        notes: "Voice activity detection, auto-downloaded when no speakers are given"
    )

    public static let registry: [ModelDescriptor] = [parakeet, unified, multilingual, sortformer, silero]

    static let stagingDirectoryName = ".incomplete"

    public static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["CONURE_MODELS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Conure/models", isDirectory: true)
    }

    public static var fluidCacheBase: URL {
        fluidCacheBase(under: baseURL)
    }

    static func fluidCacheBase(under base: URL) -> URL {
        base.appendingPathComponent("FluidAudio", isDirectory: true)
    }

    public static func directory(for descriptor: ModelDescriptor) -> URL {
        directory(for: descriptor, base: baseURL)
    }

    public static func directory(for descriptor: ModelDescriptor, base: URL) -> URL {
        if descriptor.engine == .fluidAudio {
            let repo: Repo = descriptor.id == unified.id ? .parakeetUnified : .parakeetV3
            return fluidCacheBase(under: base).appendingPathComponent(repo.folderName, isDirectory: true)
        }
        return base.appendingPathComponent(descriptor.id, isDirectory: true)
    }

    public static func descriptor(for id: String) -> ModelDescriptor? {
        registry.first { $0.id == id || $0.hfRepo == id }
    }

    // MARK: - Installation state

    public static func installState(of descriptor: ModelDescriptor, base: URL = baseURL) -> InstallState {
        installState(of: descriptor, in: directory(for: descriptor, base: base))
    }

    static func installState(of descriptor: ModelDescriptor, in dir: URL) -> InstallState {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              !entries.isEmpty
        else { return .missing }
        let fm = FileManager.default
        let (bundles, files) = requiredContents(of: descriptor)
        let ready = bundles.allSatisfy { isCompleteBundle(dir.appendingPathComponent($0, isDirectory: true)) }
            && files.allSatisfy { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
        return ready ? .ready : .incomplete
    }

    public static func isDownloaded(_ descriptor: ModelDescriptor, base: URL = baseURL) -> Bool {
        installState(of: descriptor, base: base) == .ready
    }

    static func requiredContents(of descriptor: ModelDescriptor) -> (bundles: [String], files: [String]) {
        var bundles: [String] = []
        var files: [String] = []
        func partition(_ names: some Sequence<String>) {
            for name in names {
                if name.hasSuffix(".mlmodelc") || name.hasSuffix(".mlpackage") {
                    bundles.append(name)
                } else {
                    files.append(name)
                }
            }
        }
        if descriptor.engine == .fluidAudio {
            if descriptor.id == unified.id {
                partition(ModelNames.ParakeetUnified.requiredModels(variant: "offline"))
            } else {
                partition(
                    ModelNames.ASR.requiredModelsV3(precision: .int8)
                        .union([ModelNames.ASR.vocabularyFile]))
            }
            return (bundles, files)
        }
        for pattern in descriptor.files {
            if pattern.hasSuffix("/**") {
                bundles.append(String(pattern.dropLast(3)))
            } else {
                partition([pattern])
            }
        }
        return (bundles, files)
    }

    /// A compiled CoreML bundle counts as present only when it is a directory
    /// holding `coremldata.bin` — the same signature FluidAudio's cache
    /// validation uses — and no interrupted `.partial` transfer remains
    /// inside it.
    static func isCompleteBundle(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: url.appendingPathComponent("coremldata.bin").path)
        else { return false }
        return !containsPartialDownload(at: url)
    }

    static func containsPartialDownload(at url: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return false }
        for case let entry as String in enumerator
        where (entry as NSString).pathExtension == "partial" {
            return true
        }
        return false
    }

    public static func diskSize(of descriptor: ModelDescriptor) -> Int64 {
        let fm = FileManager.default
        let dir = directory(for: descriptor)
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Disk space preflight

    public static func diskSpaceFailure(requiredBytes: Int64, availableBytes: Int64) -> ModelStoreError? {
        guard requiredBytes > 0, availableBytes >= 0, availableBytes < requiredBytes else { return nil }
        return .insufficientDiskSpace(requiredBytes: requiredBytes, availableBytes: availableBytes)
    }

    static func availableDiskCapacity(at url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        var candidate = url
        while true {
            if let values = try? candidate.resourceValues(forKeys: keys) {
                if let important = values.volumeAvailableCapacityForImportantUsage {
                    return important
                }
                if let fallback = values.volumeAvailableCapacity {
                    return Int64(fallback)
                }
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { return nil }
            candidate = parent
        }
    }

    // MARK: - Download

    public static func download(
        _ descriptor: ModelDescriptor,
        progress: ProgressSink? = nil
    ) async throws {
        let dir = directory(for: descriptor)
        let state = installState(of: descriptor, in: dir)
        if state != .ready {
            let requiredBytes = Int64(descriptor.approxSizeMB) * 1_048_576
            if let capacity = availableDiskCapacity(at: dir),
               let failure = diskSpaceFailure(requiredBytes: requiredBytes, availableBytes: capacity) {
                throw failure
            }
        }
        do {
            try await performDownload(descriptor, state: state, dir: dir, progress: progress)
            pruneStaging(in: dir, whenReady: installState(of: descriptor, in: dir))
        } catch {
            if error is CancellationError || error is ModelStoreError { throw error }
            throw ModelStoreError.installFailed(
                model: descriptor.id,
                category: ModelStoreError.categorize(error),
                reason: error.localizedDescription
            )
        }
    }

    private static func performDownload(
        _ descriptor: ModelDescriptor,
        state: InstallState,
        dir: URL,
        progress: ProgressSink?
    ) async throws {
        if descriptor.engine == .fluidAudio {
            if state == .ready {
                progress?(.download(100, descriptor.displayName))
                return
            }
            let report: ProgressHandler = { update in
                progress?(.download(update.fractionCompleted * 100, descriptor.displayName))
            }
            if descriptor.id == unified.id {
                try await ModelHub.download(
                    .parakeetUnified, to: fluidCacheBase, variant: "offline", progressHandler: report
                )
            } else {
                try await ModelHub.download(
                    .parakeetV3,
                    to: fluidCacheBase,
                    variant: ParakeetEncoderPrecision.int8.rawValue,
                    progressHandler: report
                )
            }
            progress?(.download(100, descriptor.displayName))
            return
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await HuggingFaceDownloader.downloadWeights(
            modelId: descriptor.hfRepo,
            to: dir,
            additionalFiles: descriptor.files,
            progressHandler: { fraction in
                progress?(.download(fraction * 100, descriptor.displayName))
            }
        )
    }

    /// Once an installation validates as ready, leftover staging data can no
    /// longer be a resume point: every required file is complete at its final
    /// path. Drop the speech-swift `.incomplete` directory and FluidAudio
    /// `.partial` files whose final file already exists; keep `.partial`
    /// files whose target is still missing (those remain resumable).
    static func pruneStaging(in dir: URL, whenReady state: InstallState) {
        guard state == .ready else { return }
        let fm = FileManager.default
        let staging = dir.appendingPathComponent(stagingDirectoryName, isDirectory: true)
        if fm.fileExists(atPath: staging.path) {
            try? fm.removeItem(at: staging)
        }
        guard let enumerator = fm.enumerator(atPath: dir.path) else { return }
        let partialSuffix = ".partial"
        for case let entry as String in enumerator where entry.hasSuffix(partialSuffix) {
            let target = dir.appendingPathComponent(String(entry.dropLast(partialSuffix.count)))
            if fm.fileExists(atPath: target.path) {
                try? fm.removeItem(at: dir.appendingPathComponent(entry))
            }
        }
    }

    public static func remove(_ descriptor: ModelDescriptor) throws {
        if descriptor.isRequired {
            throw ModelStoreError.cannotRemoveRequired(descriptor)
        }
        let dir = directory(for: descriptor)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }
}
