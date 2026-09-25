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
    private var stderrTail: [String] = []

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
            cancelCurrent()
            currentJobID = nil
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
        cancelCurrent()
        setStatus(jobID, .failed("Cancelled"))
        currentJobID = nil
        startNextIfNeeded()
    }

    private func cancelCurrent() {
        runningProcess?.terminate()
        runningProcess = nil
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
        stderrTail = []

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else {
                handle.readabilityHandler = nil
                return
            }
            let lines = text.split(separator: "\n").map(String.init)
            Task { @MainActor in
                self?.stderrTail.append(contentsOf: lines)
                if self?.stderrTail.count ?? 0 > 20 {
                    self?.stderrTail.removeFirst((self?.stderrTail.count ?? 20) - 20)
                }
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                handle.readabilityHandler = nil
                return
            }
            let events: [CLIEvent] = text.split(separator: "\n").compactMap { chunk in
                chunk.data(using: .utf8)
                    .flatMap { try? JSONDecoder().decode(CLIEvent.self, from: $0) }
            }
            Task { @MainActor in
                self?.handle(events, for: jobID)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.currentJobID == jobID else { return }
                self.runningProcess = nil
                if case .done = self.status(of: jobID) {
                    // already finished normally
                } else if process.terminationStatus != 0 {
                    var message = "Exited with code \(process.terminationStatus)"
                    if process.terminationReason == .uncaughtSignal {
                        message = "Terminated"
                    }
                    let tail = self.stderrTail.joined(separator: "\n")
                    self.setStatus(jobID, .failed(tail.isEmpty ? message : "\(message)\n\(tail)"))
                } else {
                    self.setStatus(jobID, .failed("Finished without reporting output"))
                }
                self.currentJobID = nil
                self.startNextIfNeeded()
            }
        }

        do {
            setStatus(jobID, .running(stage: "starting", percent: 0))
            runningProcess = process
            try process.run()
        } catch {
            setStatus(
                jobID,
                .failed("Could not start CLI at \(CLI.shared.url.path): \(error.localizedDescription)")
            )
            currentJobID = nil
            startNextIfNeeded()
        }
    }

    private func status(of jobID: UUID) -> JobStatus? {
        jobs.first { $0.id == jobID }?.status
    }

    private func handle(_ events: [CLIEvent], for jobID: UUID) {
        for event in events {
            switch event.type {
            case .progress:
                setStatus(jobID, .running(stage: event.stage ?? "", percent: event.percent ?? 0))
            case .done:
                setStatus(jobID, .done(output: event.outputPath ?? ""))
            case .error:
                setStatus(jobID, .failed(event.detail ?? "Unknown error"))
            }
        }
    }
}
