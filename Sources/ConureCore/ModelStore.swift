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

public enum ModelStoreError: LocalizedError {
    case cannotRemoveRequired(ModelDescriptor)

    public var errorDescription: String? {
        switch self {
        case .cannotRemoveRequired(let d):
            return "\(d.displayName) is required by Conure and cannot be removed"
        }
    }
}

public enum ModelStore {
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

    public static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["CONURE_MODELS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Conure/models", isDirectory: true)
    }

    public static var fluidCacheBase: URL {
        baseURL.appendingPathComponent("FluidAudio", isDirectory: true)
    }

    public static func directory(for descriptor: ModelDescriptor) -> URL {
        if descriptor.engine == .fluidAudio {
            let repo: Repo = descriptor.id == unified.id ? .parakeetUnified : .parakeetV3
            return fluidCacheBase.appendingPathComponent(repo.folderName, isDirectory: true)
        }
        return baseURL.appendingPathComponent(descriptor.id, isDirectory: true)
    }

    public static func descriptor(for id: String) -> ModelDescriptor? {
        registry.first { $0.id == id || $0.hfRepo == id }
    }

    public static func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        if descriptor.engine == .fluidAudio {
            let dir = directory(for: descriptor)
            if descriptor.id == unified.id {
                let required = [
                    "parakeet_unified_encoder_int8.mlmodelc", "parakeet_unified_decoder.mlmodelc",
                    "parakeet_unified_joint_decision_single_step.mlmodelc", "vocab.json",
                ]
                return required.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
            }
            return AsrModels.modelsExist(at: dir, version: .v3)
        }
        return HuggingFaceDownloader.weightsExist(in: directory(for: descriptor))
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

    public static func download(
        _ descriptor: ModelDescriptor,
        progress: ProgressSink? = nil
    ) async throws {
        if descriptor.engine == .fluidAudio {
            if isDownloaded(descriptor) {
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
                try await AsrModels.download(
                    to: directory(for: descriptor), version: .v3, progressHandler: report
                )
            }
            progress?(.download(100, descriptor.displayName))
            return
        }
        let dir = directory(for: descriptor)
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

    public static func remove(_ descriptor: ModelDescriptor) throws {
        if descriptor.isRequired {
            throw ModelStoreError.cannotRemoveRequired(descriptor)
        }
        let dir = directory(for: descriptor)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }
}
