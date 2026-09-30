import Foundation
import XCTest
@testable import ConureApp

final class JobCompletionTests: XCTestCase {
    private let done = CLIEvent(type: .done, stage: nil, percent: nil, detail: nil, outputPath: "/tmp/output.md")
    private let error = CLIEvent(type: .error, stage: nil, percent: nil, detail: "Transcription failed", outputPath: nil)

    func testAllSuccessSignalOrders() {
        for order in permutations([0, 1, 2]) {
            var completion = JobCompletion()
            for (index, signal) in order.enumerated() {
                switch signal {
                case 0: completion.exited(code: 0, reason: .exit)
                case 1:
                    completion.receive(done)
                    completion.finishStdout()
                default: completion.finishStderr()
                }
                if index < order.count - 1 {
                    XCTAssertNil(completion.result, "order: \(order), step: \(index)")
                }
            }
            XCTAssertEqual(completion.result, .done(output: "/tmp/output.md"), "order: \(order)")
        }
    }

    func testZeroExitWithoutDoneIsProtocolFailure() {
        var completion = JobCompletion()
        completion.exited(code: 0, reason: .exit)
        completion.finishStdout()
        XCTAssertNil(completion.result)
        completion.finishStderr()
        XCTAssertEqual(completion.result, .failed("Finished without reporting output"))
    }

    func testNonzeroExitWaitsForStderrAndIncludesBoundedTail() {
        var completion = JobCompletion()
        completion.appendStderr(Data(repeating: 0x78, count: 5000))
        completion.appendStderr(Data("\nuseful diagnostic\n".utf8))
        completion.finishStdout()
        completion.exited(code: 2, reason: .exit)
        XCTAssertNil(completion.result)
        completion.finishStderr()
        guard case .failed(let message) = completion.result else { return XCTFail("Expected failure") }
        XCTAssertTrue(message.contains("Exited with code 2"))
        XCTAssertTrue(message.hasSuffix("useful diagnostic"))
        XCTAssertLessThan(message.count, 4200)
    }

    func testProtocolErrorOverridesExitDiagnostics() {
        var completion = JobCompletion()
        completion.receive(error)
        completion.appendStderr(Data("generic stderr".utf8))
        completion.finishStderr()
        completion.finishStdout()
        completion.exited(code: 1, reason: .exit)
        XCTAssertEqual(completion.result, .failed("Transcription failed"))
    }

    func testDoneWithoutOutputPathIsInvalid() {
        var completion = JobCompletion()
        completion.receive(CLIEvent(type: .done, stage: nil, percent: nil, detail: nil, outputPath: nil))
        completion.finishStdout()
        completion.finishStderr()
        completion.exited(code: 0, reason: .exit)
        XCTAssertEqual(completion.result, .failed("Invalid done event: missing output path"))
    }

    func testCancellationExitWinsOverTerminalEventsAndDiagnostics() {
        for event in [done, error] {
            var completion = JobCompletion()
            completion.receive(event)
            completion.appendStderr(Data("ignored diagnostic".utf8))
            completion.exited(code: 130, reason: .exit)
            completion.finishStdout()
            XCTAssertNil(completion.result)
            completion.finishStderr()
            XCTAssertEqual(completion.result, .cancelled)
        }
    }

    func testNonzeroExitDoesNotAcceptDone() {
        var completion = JobCompletion()
        completion.receive(done)
        completion.finishStdout()
        completion.finishStderr()
        completion.exited(code: 1, reason: .exit)
        XCTAssertEqual(completion.result, .failed("Exited with code 1"))
    }

    func testProgressAndLaterTerminalEventsCannotReplaceFirstTerminalEvent() {
        var completion = JobCompletion()
        completion.receive(done)
        completion.receive(CLIEvent(type: .progress, stage: "late", percent: 99, detail: nil, outputPath: nil))
        completion.receive(error)
        completion.finishStdout()
        completion.finishStderr()
        completion.exited(code: 0, reason: .exit)
        XCTAssertEqual(completion.result, .done(output: "/tmp/output.md"))
    }

    private func permutations(_ values: [Int]) -> [[Int]] {
        if values.isEmpty { return [[]] }
        return values.flatMap { value in
            permutations(values.filter { $0 != value }).map { [value] + $0 }
        }
    }
}
