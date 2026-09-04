//
//  EndpointPortFallbackTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import XCTest
@testable import VPN

@MainActor
final class EndpointPortFallbackTests: XCTestCase {

    private struct TestError: Error, Equatable {
        let id: Int
    }

    /// Pops a scripted result per call, repeating the last one once the queue runs dry -
    /// mirrors how a real handshake reporter keeps returning its latest known value.
    private final class FakeHandshakeReporter: HandshakeReporting {
        private var queue: [Result<TimeInterval, Error>]
        private var lastResult: Result<TimeInterval, Error>
        private(set) var callCount = 0

        init(_ results: [Result<TimeInterval, Error>]) {
            precondition(!results.isEmpty, "provide at least one scripted result")
            self.queue = results
            self.lastResult = results[0]
        }

        func getMostRecentHandshake() async throws -> TimeInterval {
            callCount += 1
            if !queue.isEmpty {
                lastResult = queue.removeFirst()
            }
            switch lastResult {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            }
        }
    }

    /// Records probe/applyPort/sleep calls (in order, via `events`) and can be configured
    /// to fail an `applyPort` call for a given port or to cancel on a given sleep call.
    private final class RecordingHarness {
        enum Event: Equatable {
            case probe
            case applyPort(UInt16)
            case sleep
        }

        private(set) var events: [Event] = []
        private(set) var probeCount = 0
        private(set) var appliedPorts: [UInt16] = []
        private(set) var sleepDurations: [TimeInterval] = []

        var failApplyPort: (port: UInt16, error: Error)?
        var cancelOnSleepCall: Int?
        /// Fires after every recorded sleep, e.g. so a test can cancel the enclosing
        /// Task without making `sleep` itself throw.
        var onSleep: (() -> Void)?
        private var sleepCallCount = 0

        func probe() async {
            probeCount += 1
            events.append(.probe)
        }

        func applyPort(_ port: UInt16) async throws {
            events.append(.applyPort(port))
            if let failApplyPort, failApplyPort.port == port {
                throw failApplyPort.error
            }
            appliedPorts.append(port)
        }

        func sleep(_ interval: TimeInterval) async throws {
            sleepCallCount += 1
            sleepDurations.append(interval)
            events.append(.sleep)
            onSleep?()
            if cancelOnSleepCall == sleepCallCount {
                throw CancellationError()
            }
        }
    }

    /// Short configuration so expected read counts stay small: 4 reads (1 immediate + 3
    /// after sleeps) and 3 sleeps per port that times out.
    private let configuration = EndpointPortFallback.Configuration(handshakeTimeout: 3, pollInterval: 1)

    private func makeController(reporter: FakeHandshakeReporter,
                                 harness: RecordingHarness,
                                 configuration: EndpointPortFallback.Configuration? = nil) -> EndpointPortFallback {
        EndpointPortFallback(handshakeReporter: reporter,
                              probe: { await harness.probe() },
                              applyPort: { try await harness.applyPort($0) },
                              sleep: { try await harness.sleep($0) },
                              configuration: configuration ?? self.configuration)
    }

    // MARK: - 1. Handshake on the current port before timeout

    func testHandshakeOnCurrentPort_ReturnsHandshakeWithoutApplyingAnyPort() async {
        let reporter = FakeHandshakeReporter([.success(0), .success(5)])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        XCTAssertEqual(outcome, .handshake(port: 443))
        XCTAssertTrue(harness.appliedPorts.isEmpty)
        XCTAssertEqual(harness.probeCount, 1)
        XCTAssertEqual(harness.sleepDurations.count, 0)
    }

    // MARK: - 2. No handshake on the first port, handshake on the second

    func testNoHandshakeOnFirstPort_HandshakeOnSecond() async {
        let reporter = FakeHandshakeReporter([
            .success(0),                                 // baseline
            .success(0), .success(0), .success(0), .success(0), // 4 reads on port 443, all stale
            .success(10)                                  // first read on 51820: handshake
        ])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443, 51820], currentPort: 443)

        XCTAssertEqual(outcome, .handshake(port: 51820))
        XCTAssertEqual(harness.appliedPorts, [51820])
        XCTAssertEqual(harness.probeCount, 2)
        XCTAssertEqual(harness.sleepDurations.count, 3)
    }

    // MARK: - 3. No handshake on any port

    func testNoHandshakeOnAnyPort_ReturnsExhausted() async {
        let candidates: [UInt16] = [443, 51820, 973]
        let reporter = FakeHandshakeReporter([.success(0)]) // stays at 0 forever
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: candidates, currentPort: 443)

        XCTAssertEqual(outcome, .exhausted(triedPorts: candidates))
        XCTAssertEqual(harness.appliedPorts, [51820, 973])
        XCTAssertEqual(harness.probeCount, 3)
    }

    // MARK: - 4. First candidate differs from current port: applyPort happens before the first probe

    func testFirstCandidateDiffersFromCurrentPort_AppliesBeforeProbing() async {
        let reporter = FakeHandshakeReporter([.success(0), .success(5)])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [51820], currentPort: 443)

        XCTAssertEqual(outcome, .handshake(port: 51820))
        XCTAssertEqual(harness.events, [.applyPort(51820), .probe])
    }

    // MARK: - 5. First candidate matches current port: no applyPort before the first probe

    func testFirstCandidateMatchesCurrentPort_DoesNotApplyBeforeProbing() async {
        let reporter = FakeHandshakeReporter([.success(0), .success(5)])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        XCTAssertEqual(outcome, .handshake(port: 443))
        XCTAssertEqual(harness.events, [.probe])
    }

    // MARK: - 6. Stale baseline is not mistaken for a new handshake

    func testStaleBaseline_IsNotTreatedAsHandshake_UntilTimestampAdvances() async {
        let staleTimestamp: TimeInterval = 1_000
        let reporter = FakeHandshakeReporter([
            .success(staleTimestamp), // baseline
            .success(staleTimestamp), // 1st read: same as baseline, not a handshake
            .success(staleTimestamp), // 2nd read (after 1 sleep): still stale
            .success(staleTimestamp + 1) // 3rd read (after 2 sleeps): new handshake
        ])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        XCTAssertEqual(outcome, .handshake(port: 443))
        XCTAssertEqual(harness.sleepDurations.count, 2)
    }

    // MARK: - 7. Reporter errors are treated as no handshake yet

    func testReporterErrors_AreTreatedAsNoHandshakeYet() async {
        let reporter = FakeHandshakeReporter([
            .success(0),                       // baseline
            .failure(TestError(id: 1)),        // 1st read: error, not a handshake
            .failure(TestError(id: 2)),        // 2nd read (after 1 sleep): error again
            .success(1)                        // 3rd read (after 2 sleeps): handshake
        ])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        XCTAssertEqual(outcome, .handshake(port: 443))
        XCTAssertEqual(harness.sleepDurations.count, 2)
    }

    // MARK: - 8. Cancellation mid-wait stops the run immediately

    func testSleepCancellation_ReturnsCancelled_AndStopsFurtherApplyPortCalls() async {
        let reporter = FakeHandshakeReporter([.success(0)]) // stays at 0 forever
        let harness = RecordingHarness()
        harness.cancelOnSleepCall = 1
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443, 51820], currentPort: 443)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(harness.appliedPorts.isEmpty)
        XCTAssertFalse(harness.events.contains(.applyPort(51820)))
    }

    // MARK: - 9. applyPort failure is skipped without probing, next candidate still tried

    func testApplyPortFailure_SkipsProbing_AndMovesToNextCandidate() async {
        let candidates: [UInt16] = [443, 51820, 973]
        let reporter = FakeHandshakeReporter([
            .success(0),                                          // baseline
            .success(0), .success(0), .success(0), .success(0),   // 4 reads on port 443, timeout
            .success(10)                                          // first read on 973: handshake
        ])
        let harness = RecordingHarness()
        harness.failApplyPort = (port: 51820, error: TestError(id: 3))
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: candidates, currentPort: 443)

        XCTAssertEqual(outcome, .handshake(port: 973))
        XCTAssertEqual(harness.probeCount, 2) // none for the failed 51820 attempt
        XCTAssertEqual(harness.appliedPorts, [973])
        XCTAssertEqual(harness.events, [
            .probe, .sleep, .sleep, .sleep, // port 443 (== currentPort) is probed, then times out
            .applyPort(51820),               // fails, so no probe for it
            .applyPort(973), .probe          // succeeds, then handshakes on the first read
        ])
    }

    // MARK: - 10. Empty candidates

    func testEmptyCandidates_ReturnsExhaustedWithoutTouchingAnythingElse() async {
        let reporter = FakeHandshakeReporter([.success(0)])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [], currentPort: 443)

        XCTAssertEqual(outcome, .exhausted(triedPorts: []))
        XCTAssertEqual(harness.probeCount, 0)
        XCTAssertTrue(harness.appliedPorts.isEmpty)
        XCTAssertEqual(harness.sleepDurations.count, 0)
        XCTAssertEqual(reporter.callCount, 0) // empty candidates short-circuits before the baseline read
    }

    // MARK: - 11. Read/sleep counts match the configuration exactly

    func testReadAndSleepCounts_MatchConfiguration_ForEachTimedOutPort() async {
        let candidates: [UInt16] = [443, 51820]
        let reporter = FakeHandshakeReporter([.success(0)]) // never handshakes
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: candidates, currentPort: 443)

        XCTAssertEqual(outcome, .exhausted(triedPorts: candidates))
        // 1 baseline read + (4 reads * 2 ports)
        XCTAssertEqual(reporter.callCount, 1 + 4 * 2)
        // 3 sleeps per timed-out port, all at the configured 1s poll interval
        XCTAssertEqual(harness.sleepDurations, [1, 1, 1, 1, 1, 1])
    }

    // MARK: - 12. Task cancellation is caught via Task.isCancelled, not a throwing sleep

    func testTaskCancellation_IsCaughtBetweenCandidates_WithoutApplyingTheNextPort() async {
        let reporter = FakeHandshakeReporter([.success(0)]) // never handshakes
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        var fallbackTask: Task<EndpointPortFallback.Outcome, Never>?
        harness.onSleep = {
            // Cancel the enclosing task on the very first sleep, without making
            // `sleep` itself throw - this must be caught by the `Task.isCancelled`
            // check, not by a thrown CancellationError.
            if harness.sleepDurations.count == 1 {
                fallbackTask?.cancel()
            }
        }

        fallbackTask = Task { @MainActor in
            await controller.run(candidates: [443, 51820], currentPort: 443)
        }
        let outcome = await fallbackTask!.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(harness.appliedPorts.isEmpty)
        XCTAssertFalse(harness.events.contains(.applyPort(51820)))
    }

    // MARK: - 13. A failing apply is still tried; the following candidate is not skipped

    func testExhaustedWithFailingApply_StillTriesRemainingCandidates() async {
        let candidates: [UInt16] = [443, 51820, 973]
        let reporter = FakeHandshakeReporter([.success(0)]) // never handshakes
        let harness = RecordingHarness()
        harness.failApplyPort = (port: 51820, error: TestError(id: 4))
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: candidates, currentPort: 443)

        XCTAssertEqual(outcome, .exhausted(triedPorts: candidates))
        XCTAssertEqual(harness.probeCount, 2) // none for the failed 51820 attempt
        let applyPortCalls: [UInt16] = harness.events.compactMap {
            if case .applyPort(let port) = $0 { return port }
            return nil
        }
        XCTAssertEqual(applyPortCalls, [51820, 973])
    }

    // MARK: - 14. A baseline read that throws once is retried, and the retried value is used

    func testBaselineRetryAfterThrow_UsesRetriedValueAsBaseline() async {
        let staleTimestamp: TimeInterval = 500
        let reporter = FakeHandshakeReporter([
            .failure(TestError(id: 5)),      // baseline attempt 1: throws
            .success(staleTimestamp),        // baseline attempt 2: succeeds, becomes baseline
            .success(staleTimestamp),        // 1st poll read: same as baseline, not a handshake
            .success(staleTimestamp + 1)     // 2nd poll read (after 1 sleep): new handshake
        ])
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        // If the throw had been treated as a baseline of 0, the very first poll read
        // (staleTimestamp) would already look like a handshake, one read sooner.
        XCTAssertEqual(outcome, .handshake(port: 443))
        XCTAssertEqual(reporter.callCount, 4)
        XCTAssertEqual(harness.sleepDurations.count, 2) // 1 baseline retry + 1 poll wait
    }

    // MARK: - 15. A baseline that never succeeds reports unavailable without touching any port

    func testBaselineAlwaysThrows_ReturnsHandshakeStatusUnavailable() async {
        let reporter = FakeHandshakeReporter([.failure(TestError(id: 6))]) // always throws
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        XCTAssertEqual(outcome, .handshakeStatusUnavailable)
        XCTAssertEqual(harness.probeCount, 0)
        XCTAssertTrue(harness.appliedPorts.isEmpty)
        XCTAssertEqual(harness.sleepDurations.count, 3) // pollsPerPort retries before giving up
        XCTAssertEqual(reporter.callCount, 4) // pollsPerPort + 1
    }

    // MARK: - 16. pollsPerPort is derived from the configuration, not hardcoded to the test default

    func testPollsPerPort_IsDerivedFromFractionalPollInterval() async {
        // 0.7 / 0.1 is 6.999… in floating point: truncation would give 6 polls, rounding gives 7.
        // So pollsPerPort is 7: 8 reads (7 + 1) and 7 sleeps for the one candidate, which never handshakes.
        let customConfiguration = EndpointPortFallback.Configuration(handshakeTimeout: 0.7, pollInterval: 0.1)
        let reporter = FakeHandshakeReporter([.success(0)]) // never handshakes
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness, configuration: customConfiguration)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        XCTAssertEqual(outcome, .exhausted(triedPorts: [443]))
        XCTAssertEqual(reporter.callCount, 1 + 8) // 1 baseline read + 8 poll reads
        XCTAssertEqual(harness.sleepDurations, Array(repeating: 0.1, count: 7))
    }

    func testPollsPerPort_FloorsToAtLeastOne() async {
        // handshakeTimeout / pollInterval = 0 / 1 = 0, so the max(1, ...) floor still
        // gives one poll: 2 reads (1 + 1) and 1 sleep for the one candidate.
        let customConfiguration = EndpointPortFallback.Configuration(handshakeTimeout: 0, pollInterval: 1)
        let reporter = FakeHandshakeReporter([.success(0)]) // never handshakes
        let harness = RecordingHarness()
        let controller = makeController(reporter: reporter, harness: harness, configuration: customConfiguration)

        let outcome = await controller.run(candidates: [443], currentPort: 443)

        XCTAssertEqual(outcome, .exhausted(triedPorts: [443]))
        XCTAssertEqual(reporter.callCount, 1 + 2) // 1 baseline read + 2 poll reads
        XCTAssertEqual(harness.sleepDurations, [1])
    }

}
