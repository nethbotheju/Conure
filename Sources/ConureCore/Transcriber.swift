import Foundation
import ParakeetASR

public final class Transcriber {
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

    public func warmUp() throws {
        try model.warmUp()
    }

    public func transcribe(_ samples: ArraySlice<Float>, sampleRate: Int, language: String?) throws -> String {
        guard !samples.isEmpty else { return "" }
        let result = try autoreleasepool {
            try model.transcribeAudio(Array(samples), sampleRate: sampleRate, language: language)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
