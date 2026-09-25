import Foundation
import ParakeetASR
import FluidAudio

public protocol Transcribing: Sendable {
    var modelId: String { get }
    func warmUp() async throws
    func transcribe(_ samples: ArraySlice<Float>, sampleRate: Int, language: String?) async throws -> String
}

public enum TranscriberFactory {
    public static func load(modelId: String?, progress: ProgressSink?) async throws -> any Transcribing {
        if let descriptor = ModelStore.descriptor(for: modelId ?? ModelStore.defaultModelID),
           descriptor.engine == .fluidAudio {
            return try await FluidTranscriber.load(descriptor: descriptor, progress: progress)
        }
        return try await Transcriber.load(modelId: modelId, progress: progress)
    }
}

public actor FluidTranscriber: Transcribing {
    public nonisolated let modelId: String
    private let unified: UnifiedAsrManager?
    private let multilingual: AsrManager?

    private init(modelId: String, unified: UnifiedAsrManager?, multilingual: AsrManager?) {
        self.modelId = modelId
        self.unified = unified
        self.multilingual = multilingual
    }

    public static func load(descriptor: ModelDescriptor, progress: ProgressSink?) async throws -> FluidTranscriber {
        if descriptor.id == ModelStore.unified.id {
            let manager = UnifiedAsrManager()
            try await manager.loadModels(to: ModelStore.fluidCacheBase) { update in
                progress?(.download(update.fractionCompleted * 100, descriptor.displayName))
            }
            return FluidTranscriber(modelId: descriptor.hfRepo, unified: manager, multilingual: nil)
        }
        if !ModelStore.isDownloaded(descriptor) {
            try await ModelStore.download(descriptor, progress: progress)
        }
        let models = try await AsrModels.load(from: ModelStore.directory(for: descriptor), version: .v3)
        let manager = AsrManager(models: models)
        return FluidTranscriber(modelId: descriptor.hfRepo, unified: nil, multilingual: manager)
    }

    public func warmUp() async throws {}

    public func transcribe(_ samples: ArraySlice<Float>, sampleRate: Int, language: String?) async throws -> String {
        guard !samples.isEmpty else { return "" }
        precondition(sampleRate == 16_000)
        let text: String
        if let unified {
            text = try await unified.transcribe(Array(samples))
        } else if let multilingual {
            let hint: Language?
            if let language, !language.isEmpty {
                guard let supported = Language(rawValue: language) else {
                    throw FluidTranscriberError.unsupportedLanguage(language)
                }
                hint = supported
            } else {
                hint = nil
            }
            var state = TdtDecoderState.make()
            let result = try await multilingual.transcribe(Array(samples), decoderState: &state, language: hint)
            text = result.text
        } else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum FluidTranscriberError: LocalizedError {
    case unsupportedLanguage(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let code):
            return "FluidAudio does not support the language hint \(code). Omit --language to auto-detect."
        }
    }
}

public final class Transcriber: Transcribing, @unchecked Sendable {
    public static let defaultModelId = ModelStore.defaultModelID

    public let modelId: String
    private let model: ParakeetASRModel

    private init(model: ParakeetASRModel, modelId: String) {
        self.model = model
        self.modelId = modelId
    }

    public static func load(
        modelId: String? = nil,
        offlineMode: Bool = false,
        progress: ProgressSink? = nil
    ) async throws -> Transcriber {
        let requested = modelId ?? defaultModelId
        let repoId: String
        let cacheDir: URL?
        let offline: Bool
        if let descriptor = ModelStore.descriptor(for: requested) {
            repoId = descriptor.hfRepo
            let dir = ModelStore.directory(for: descriptor)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let downloaded = ModelStore.isDownloaded(descriptor)
            if !downloaded && !offlineMode {
                try await ModelStore.download(descriptor, progress: progress)
            }
            cacheDir = dir
            offline = offlineMode || downloaded
        } else {
            repoId = requested
            cacheDir = nil
            offline = offlineMode
        }
        let model = try await ParakeetASRModel.fromPretrained(
            modelId: repoId,
            cacheDir: cacheDir,
            offlineMode: offline,
            progressHandler: { fraction, detail in
                progress?(.download(fraction * 100, detail))
            }
        )
        return Transcriber(model: model, modelId: repoId)
    }

    public func warmUp() async throws {
        try model.warmUp()
    }

    public func transcribe(_ samples: ArraySlice<Float>, sampleRate: Int, language: String?) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let result = try autoreleasepool {
            try model.transcribeAudio(Array(samples), sampleRate: sampleRate, language: language)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
