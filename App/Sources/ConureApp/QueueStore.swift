import Foundation
import SwiftUI
import AppKit
import Combine

enum JobStatus: Equatable {
    case queued
    case running(stage: String, percent: Double)
    case done(output: String)
    case failed(String)
    case cancelled

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Transcribing"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

enum CollisionPolicy: String {
    case replace
    case unique
}

struct JobConfiguration {
    var model: String?
    var language: String?
    var speakers: [String]
    var format: String
    var timed: Bool
    var outputDirectory: URL?
    var collision: CollisionPolicy?

    var resolvedModelID: String {
        if let model, !model.isEmpty { return model }
        return CLI.defaultModelID
    }

    var requiredModelIDs: [String] {
        speakers.isEmpty ? ["silero"] : ["sortformer"]
    }

    var modelIDsInPlay: [String] {
        [resolvedModelID] + requiredModelIDs
    }

    func desiredOutputPath(for input: URL) -> String {
        let directory = outputDirectory ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(base).\(format)").path
    }
}

struct Job: Identifiable {
    let id = UUID()
    let input: URL
    let configuration: JobConfiguration
    var status: JobStatus = .queued
}

@MainActor
final class QueueStore: ObservableObject {
    @Published var jobs: [Job] = []

    private let executableURL: URL
    private let coordinator: ModelCoordinator?
    private var runningProcess: Process?
    private var currentJobID: UUID?
    private var currentRunID: UUID?
    private var cancelling = false
    private var completion = JobCompletion()
    private var operationsCancellable: AnyCancellable?

    init(executableURL: URL? = nil, coordinator: ModelCoordinator? = nil) {
        self.executableURL = executableURL ?? CLI.shared.url
        self.coordinator = coordinator
        if let coordinator {
            operationsCancellable = coordinator.$operations
                .dropFirst()
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.startNextIfNeeded()
                    }
                }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if let process = self?.runningProcess, process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
            }
        }
    }

    var isRunning: Bool { currentJobID != nil }

    func add(inputs: [URL], configuration: JobConfiguration) {
        for input in inputs {
            jobs.append(Job(input: input, configuration: configuration))
        }
        syncModelUsage()
        startNextIfNeeded()
    }

    func outputConflicts(inputs: [URL], configuration: JobConfiguration) -> [String] {
        let queued = jobs.filter {
            if case .queued = $0.status { return true }
            if case .running = $0.status { return true }
            return false
        }
        let claimed = Set(queued.map { $0.configuration.desiredOutputPath(for: $0.input) })
        var counts: [String: Int] = [:]
        for input in inputs {
            let path = configuration.desiredOutputPath(for: input)
            counts[path, default: 0] += 1
        }
        return counts.keys
            .filter { path in
                counts[path]! > 1
                    || claimed.contains(path)
                    || FileManager.default.fileExists(atPath: path)
            }
            .map { ($0 as NSString).lastPathComponent }
            .sorted()
    }

    func remove(_ jobID: UUID) {
        if jobID == currentJobID {
            cancelling = true
            cancelCurrent()
        }
        jobs.removeAll { $0.id == jobID }
        syncModelUsage()
        startNextIfNeeded()
    }

    func retry(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        switch jobs[index].status {
        case .failed, .cancelled: break
        default: return
        }
        jobs[index].status = .queued
        syncModelUsage()
        startNextIfNeeded()
    }

    func cancel(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        if jobID == currentJobID {
            cancelling = true
            setStatus(jobID, .cancelled)
            syncModelUsage()
            cancelCurrent()
        } else if jobs[index].status == .queued {
            setStatus(jobID, .cancelled)
            syncModelUsage()
        }
    }

    private func cancelCurrent() {
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    private func setStatus(_ jobID: UUID, _ status: JobStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = status
    }

    private func startNextIfNeeded() {
        guard currentJobID == nil,
              let next = jobs.first(where: { $0.status == .queued }) else { return }
        if coordinator?.isMutatingAny(of: next.configuration.modelIDsInPlay) == true { return }
        currentJobID = next.id
        syncModelUsage()
        run(next)
    }

    private func run(_ job: Job) {
        let jobID = job.id
        let runID = UUID()
        currentRunID = runID
        cancelling = false
        let process = Process()
        process.executableURL = executableURL
        process.arguments = CLI.shared.makeArguments(
            input: job.input,
            model: job.configuration.model,
            language: job.configuration.language,
            speakers: job.configuration.speakers.isEmpty ? nil : job.configuration.speakers,
            format: job.configuration.format,
            timed: job.configuration.timed,
            output: job.configuration.outputDirectory,
            collision: job.configuration.collision
        )
        CLI.shared.configure(process)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        completion = JobCompletion()

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentJobID == jobID, self.currentRunID == runID else { return }
                if data.isEmpty {
                    self.completion.finishStderr()
                    self.finishIfNeeded(for: jobID)
                } else {
                    self.completion.appendStderr(data)
                }
            }
        }

        let decoder = JSONLinesDecoder()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let records = data.isEmpty ? decoder.finish() : decoder.append(data)
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentJobID == jobID, self.currentRunID == runID else { return }
                for record in records {
                    switch record {
                    case .event(let event): self.handle(event, for: jobID)
                    case .malformed(let message): NSLog("%@", message)
                    }
                }
                if data.isEmpty {
                    self.completion.finishStdout()
                    self.finishIfNeeded(for: jobID)
                }
            }
        }

        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            let reason = process.terminationReason
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentJobID == jobID, self.currentRunID == runID else { return }
                self.completion.exited(code: code, reason: reason)
                self.finishIfNeeded(for: jobID)
            }
        }

        do {
            setStatus(jobID, .running(stage: "starting", percent: 0))
            runningProcess = process
            syncModelUsage()
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            runningProcess = nil
            if !cancelling {
                setStatus(
                    jobID,
                    .failed("Could not start CLI at \(executableURL.path): \(error.localizedDescription)")
                )
            }
            currentJobID = nil
            currentRunID = nil
            syncModelUsage()
            startNextIfNeeded()
        }
    }

    private func finishIfNeeded(for jobID: UUID) {
        guard currentJobID == jobID, let result = completion.result else { return }
        runningProcess = nil
        if !cancelling { setStatus(jobID, result) }
        currentJobID = nil
        currentRunID = nil
        syncModelUsage()
        startNextIfNeeded()
    }

    private func handle(_ event: CLIEvent, for jobID: UUID) {
        switch event.type {
        case .progress:
            if !cancelling && completion.terminalEvent == nil {
                setStatus(jobID, .running(stage: event.stage ?? "", percent: event.percent ?? 0))
            }
        case .done, .error:
            completion.receive(event)
        }
    }

    private func syncModelUsage() {
        guard let coordinator else { return }
        var usage: [String: ModelCoordinator.Usage] = [:]
        for job in jobs {
            switch job.status {
            case .running:
                usage[job.configuration.resolvedModelID, default: ModelCoordinator.Usage()].activeJobs += 1
            case .queued:
                usage[job.configuration.resolvedModelID, default: ModelCoordinator.Usage()].queuedJobs += 1
            default:
                break
            }
        }
        coordinator.setInUse(usage)
    }
}
