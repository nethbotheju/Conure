import ArgumentParser
import ConureCore
import Foundation

extension URL: ExpressibleByArgument {
    public init?(argument: String) {
        if argument.hasPrefix("/") {
            self.init(fileURLWithPath: argument)
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            self = cwd.appendingPathComponent(argument)
        }
    }
}

func emitJSONLine(_ event: ConureEvent) {
    if let data = try? JSONEncoder().encode(event), let line = String(data: data, encoding: .utf8) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

extension OutputFormat: ExpressibleByArgument {}

@main
struct ConureCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "conure",
        abstract: "Local audio/video transcription with Parakeet on Apple Silicon",
        version: "0.1.0",
        subcommands: [TranscribeCommand.self, ModelsCommand.self],
        defaultSubcommand: TranscribeCommand.self
    )

    func run() async throws {}
}

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe audio/video files"
    )

    @Argument(help: "Audio or video files to transcribe")
    var files: [URL]

    @Option(help: "Model id (parakeet) or full HuggingFace repo (default: parakeet)")
    var model: String?

    @Option(help: "Attendee names, comma-separated (max 4). Enables speaker diarization")
    var speakers: String?

    @Option(help: "Output format: md or srt")
    var format: OutputFormat = .markdown

    @Flag(inversion: .prefixedNo, help: "Include timestamps in Markdown output")
    var timed: Bool = false

    @Option(help: "Output directory (default: alongside each input file)")
    var output: URL?

    @Flag(help: "Human-readable progress instead of JSON lines")
    var pretty: Bool = false

    @Option(help: "Language hint, e.g. en. Empty for auto-detect")
    var language: String?

    mutating func run() async throws {
        let sink: ProgressSink = pretty ? prettySink : jsonSink

        let speakerList = speakers?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let speakerList, speakerList.count > 4 {
            throw ValidationError("Maximum 4 speakers supported")
        }

        for (index, file) in files.enumerated() {
            if files.count > 1, pretty {
                print("\n[\(index + 1)/\(files.count)] \(file.lastPathComponent)")
            }
            let options = TranscribeOptions(
                modelId: model,
                language: language,
                speakerNames: speakerList,
                format: format,
                timed: timed,
                outputDirectory: output
            )
            do {
                let (_, outputURL) = try await TranscribePipeline.transcribeFile(file, options: options, progress: sink)
                let event = ConureEvent.done(outputURL.path)
                emit(event)
            } catch {
                emit(.error(error.localizedDescription))
                throw error
            }
        }
    }

    private func emit(_ event: ConureEvent) {
        if pretty {
            prettySink(event)
        } else {
            jsonSink(event)
        }
    }

    private var jsonSink: ProgressSink {
        { event in
            if let data = try? JSONEncoder().encode(event), let line = String(data: data, encoding: .utf8) {
                FileHandle.standardOutput.write(Data((line + "\n").utf8))
            }
        }
    }

    private var prettySink: ProgressSink {
        { event in
            switch event.type {
            case .progress:
                let pct = max(0, min(100, Int(event.percent ?? 0)))
                let bar = String(repeating: "#", count: pct / 4) + String(repeating: ".", count: 25 - pct / 4)
                let stage = event.stage?.rawValue ?? ""
                let detail = event.detail.map { " \($0)" } ?? ""
                FileHandle.standardError.write(Data("\r\(stage) [\(bar)] \(pct)%\(detail)".utf8))
            case .done:
                FileHandle.standardError.write(Data("\n".utf8))
                print("Done → \(event.outputPath ?? "")")
            case .error:
                FileHandle.standardError.write(Data("\n".utf8))
                print("Error: \(event.detail ?? "unknown")")
            }
        }
    }
}

struct ModelsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "Manage transcription models",
        subcommands: [List.self, Download.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List models and download status")

        @Flag(help: "Machine-readable JSON output")
        var json: Bool = false

        func run() throws {
            if json {
                struct Row: Codable {
                    let id: String
                    let name: String
                    let repo: String
                    let kind: String
                    let downloaded: Bool
                    let required: Bool
                    let isDefault: Bool
                    let sizeMB: Double
                    let approxSizeMB: Int
                    let notes: String
                }
                let rows = ModelStore.registry.map {
                    Row(
                        id: $0.id,
                        name: $0.displayName,
                        repo: $0.hfRepo,
                        kind: $0.kind.rawValue,
                        downloaded: ModelStore.isDownloaded($0),
                        required: $0.isRequired,
                        isDefault: $0.isDefault,
                        sizeMB: Double(ModelStore.diskSize(of: $0)) / 1_048_576,
                        approxSizeMB: $0.approxSizeMB,
                        notes: $0.notes
                    )
                }
                let data = try JSONEncoder().encode(rows)
                print(String(data: data, encoding: .utf8)!)
            } else {
                print("Models are stored in \(ModelStore.baseURL.path)\n")
                let asrModels = ModelStore.registry.filter { !$0.isRequired }
                let requiredModels = ModelStore.registry.filter { $0.isRequired }
                print("Transcription models (choose per job):")
                for descriptor in asrModels {
                    print(row(for: descriptor))
                }
                print("\nRequired models (used automatically, cannot be removed):")
                for descriptor in requiredModels {
                    print(row(for: descriptor))
                }
            }
        }

        private func row(for descriptor: ModelDescriptor) -> String {
            let status = ModelStore.isDownloaded(descriptor)
                ? "downloaded \(formatMB(ModelStore.diskSize(of: descriptor)))"
                : "not downloaded (~\(descriptor.approxSizeMB) MB)"
            let tags = [
                descriptor.isDefault ? "default" : nil,
                descriptor.isRequired ? "required" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            let tagLine = tags.isEmpty ? "" : " [\(tags)]"
            return "  \(descriptor.id)\(tagLine)\n    \(descriptor.displayName)\n    \(status) — \(descriptor.notes)\n"
        }

        private func formatMB(_ bytes: Int64) -> String {
            String(format: "%.0f MB", Double(bytes) / 1_048_576)
        }
    }

    struct Download: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "download", abstract: "Download a model")

        @Argument(help: "Model id (parakeet, sortformer, silero) or full HuggingFace repo")
        var id: String

        @Flag(help: "Human-readable progress instead of JSON lines")
        var pretty: Bool = false

        func run() async throws {
            guard let descriptor = ModelStore.descriptor(for: id) else {
                throw ValidationError("Unknown model: \(id). Run `conure models list` for ids.")
            }
            try await ModelStore.download(descriptor) { event in
                if pretty {
                    let pct = max(0, min(100, Int(event.percent ?? 0)))
                    FileHandle.standardError.write(Data("\rDownloading \(descriptor.id): \(pct)%".utf8))
                } else {
                    emitJSONLine(event)
                }
            }
            if pretty {
                FileHandle.standardError.write(Data("\nDownloaded \(descriptor.id)\n".utf8))
            } else {
                emitJSONLine(ConureEvent.done(ModelStore.directory(for: descriptor).path))
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "Delete a downloaded model")

        @Argument(help: "Model id (parakeet)")
        var id: String

        func run() throws {
            guard let descriptor = ModelStore.descriptor(for: id) else {
                throw ValidationError("Unknown model: \(id). Run `conure models list` for ids.")
            }
            guard !descriptor.isRequired else {
                throw ValidationError("\(descriptor.displayName) is required and cannot be removed")
            }
            guard ModelStore.isDownloaded(descriptor) else {
                throw ValidationError("\(id) is not downloaded")
            }
            try ModelStore.remove(descriptor)
            print("Removed \(id)")
        }
    }
}
