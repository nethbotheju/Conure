import Foundation
import SwiftUI
import AppKit

enum JobStatus: Equatable {
    case queued
    case running(stage: String, percent: Double)
    case done(output: String)
    case failed(String)

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Transcribing"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
}

struct JobConfiguration {
    var model: String?
    var language: String?
    var speakers: [String]
    var format: String
    var timed: Bool
    var outputDirectory: URL?
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

    private var runningProcess: Process?
    private var currentJobID: UUID?
    private var currentRunID: UUID?
    private var cancelling = false
    private var completion = JobCompletion()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runningProcess?.terminate()
            }
        }
    }

    var isRunning: Bool { currentJobID != nil }

    func add(inputs: [URL], configuration: JobConfiguration) {
        for input in inputs {
            jobs.append(Job(input: input, configuration: configuration))
        }
        startNextIfNeeded()
    }

    func remove(_ jobID: UUID) {
        if jobID == currentJobID {
            cancelling = true
            cancelCurrent()
        }
        jobs.removeAll { $0.id == jobID }
        startNextIfNeeded()
    }

    func retry(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              case .failed = jobs[index].status else { return }
        jobs[index].status = .queued
        startNextIfNeeded()
    }

    func cancel(_ jobID: UUID) {
        guard jobID == currentJobID else {
            jobs.removeAll { $0.id == jobID }
            return
        }
        cancelling = true
        cancelCurrent()
        setStatus(jobID, .failed("Cancelled"))
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
        currentJobID = next.id
        run(next)
    }

    private func run(_ job: Job) {
        let jobID = job.id
        let runID = UUID()
        currentRunID = runID
        cancelling = false
        let process = Process()
        process.executableURL = CLI.shared.url
        process.arguments = CLI.shared.makeArguments(
            input: job.input,
            model: job.configuration.model,
            language: job.configuration.language,
            speakers: job.configuration.speakers.isEmpty ? nil : job.configuration.speakers,
            format: job.configuration.format,
            timed: job.configuration.timed,
            output: job.configuration.outputDirectory
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
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            runningProcess = nil
            setStatus(
                jobID,
                .failed("Could not start CLI at \(CLI.shared.url.path): \(error.localizedDescription)")
            )
            currentJobID = nil
            currentRunID = nil
            startNextIfNeeded()
        }
    }

    private func finishIfNeeded(for jobID: UUID) {
        guard currentJobID == jobID, let result = completion.result else { return }
        runningProcess = nil
        if !cancelling { setStatus(jobID, result) }
        currentJobID = nil
        currentRunID = nil
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
}
