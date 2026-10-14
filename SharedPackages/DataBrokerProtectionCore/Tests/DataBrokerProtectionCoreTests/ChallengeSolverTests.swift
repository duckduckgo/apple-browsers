//
//  ChallengeSolverTests.swift
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

#if os(macOS)
import Common
import DataBrokerProtectionCoreTestsUtils
import PixelKit
import XCTest
@testable import DataBrokerProtectionCore

final class ChallengeSolverTests: XCTestCase {

    private static let brokerURL = URL(string: "https://www.example.com/search")!
    private static let label = ChallengeLabel(frame: CGRect(x: 100, y: 200, width: 150, height: 20))
    fileprivate static let attemptId = UUID()

    @MainActor
    func testWhenChallengeClearsDuringAutoPassWait_thenSolvesUnassistedWithoutClicking() async {
        let env = Environment()
        env.page.locate = { Self.label }
        env.clock.onSleep = { _ in _ = env.solver.handleMainFrameResponse(Self.brokerResponse()) }

        XCTAssertTrue(env.solver.handleMainFrameResponse(Self.challengeResponse()))
        await env.solver.solveTask?.value

        XCTAssertTrue(env.page.clickedPoints.isEmpty)
        XCTAssertFalse(env.solver.isAwaitingSolve)
        XCTAssertTrue(env.failures.isEmpty)
        XCTAssertEqual(env.solvedResolutions, [.unassisted])
    }

    @MainActor
    func testWhenLabelIsStable_thenClicksOnceLeftOfLabelAndSolvesAssisted() async {
        let env = Environment()
        env.page.locate = { Self.label }
        env.page.onClick = { _ = env.solver.handleMainFrameResponse(Self.brokerResponse()) }

        _ = env.solver.handleMainFrameResponse(Self.challengeResponse())
        await env.solver.solveTask?.value

        XCTAssertEqual(env.page.clickedPoints, [CGPoint(x: 80, y: 210)])
        XCTAssertTrue(env.failures.isEmpty)
        XCTAssertEqual(env.solvedResolutions, [.assisted])
    }

    @MainActor
    func testWhenLabelMovesBetweenSnapshots_thenDoesNotClickAndFailsAtDeadline() async {
        let env = Environment()
        var locateCount = 0
        env.page.locate = {
            locateCount += 1
            return ChallengeLabel(frame: Self.label.frame.offsetBy(dx: CGFloat(locateCount) * 30, dy: 0))
        }

        _ = env.solver.handleMainFrameResponse(Self.challengeResponse())
        await env.solver.solveTask?.value

        XCTAssertTrue(env.page.clickedPoints.isEmpty)
        XCTAssertFalse(env.solver.isAwaitingSolve)
        XCTAssertEqual(env.failures, [.challengeNotSolved])
        XCTAssertTrue(env.solvedResolutions.isEmpty)
        XCTAssertEqual(env.failedStages, [.noClick])
    }

    @MainActor
    func testWhenClickDoesNotClearChallenge_thenFailsAfterClickAtDeadline() async {
        let env = Environment()
        env.page.locate = { Self.label }

        _ = env.solver.handleMainFrameResponse(Self.challengeResponse())
        await env.solver.solveTask?.value

        XCTAssertEqual(env.page.clickedPoints.count, 1)
        XCTAssertEqual(env.failures, [.challengeNotSolved])
        XCTAssertEqual(env.failedStages, [.afterClick])
    }

    @MainActor
    func testWhenBrokerPageArrivesWhileConfirmingLabel_thenDoesNotClick() async {
        let env = Environment()
        var locateCount = 0
        env.page.locate = {
            locateCount += 1
            if locateCount == 2 {
                _ = env.solver.handleMainFrameResponse(Self.brokerResponse())
            }
            return Self.label
        }

        _ = env.solver.handleMainFrameResponse(Self.challengeResponse())
        await env.solver.solveTask?.value

        XCTAssertTrue(env.page.clickedPoints.isEmpty)
        XCTAssertEqual(env.solvedResolutions, [.unassisted])
    }

    @MainActor
    func testWhenNonChallengeResponseComesFromAnotherHost_thenKeepsAwaitingSolve() async {
        let env = Environment()
        env.page.locate = { nil }
        env.clock.onSleep = { _ in
            _ = env.solver.handleMainFrameResponse(Self.brokerResponse(url: URL(string: "https://other.org")!))
        }

        _ = env.solver.handleMainFrameResponse(Self.challengeResponse())
        await env.solver.solveTask?.value

        XCTAssertEqual(env.failures, [.challengeNotSolved])
        XCTAssertTrue(env.solvedResolutions.isEmpty)
        XCTAssertEqual(env.failedStages, [.noClick])
    }

    @MainActor
    func testWhenSolverIsDisabled_thenDoesNotAwaitSolveButFiresDetectionPixel() {
        let env = Environment(isEnabled: false)

        XCTAssertFalse(env.solver.handleMainFrameResponse(Self.challengeResponse()))

        XCTAssertFalse(env.solver.isAwaitingSolve)
        XCTAssertNil(env.solver.solveTask)
        XCTAssertEqual(env.mockPixelHandler?.firedEvents.count, 1)
        guard case .mainFrameChallengeDetected(_, _, _, let isSolverEnabled) = env.mockPixelHandler?.firedEvents.first else {
            return XCTFail("Expected the detection pixel")
        }
        XCTAssertFalse(isSolverEnabled)
    }

    @MainActor
    func testWhenClearanceCookieExistedBeforeChallenge_thenClearancePixelFiresOnceAfterItChanges() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)"))
        var firedPixelNames: [String] = []
        var firedPixelParameters: [[String: String]] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: [:],
                                defaults: defaults) { pixelName, _, parameters, _, _, _ in
            firedPixelNames.append(pixelName)
            firedPixelParameters.append(parameters)
        }
        let env = Environment(isEnabled: false,
                              pixelHandler: DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS))
        let staleCookie = try Self.clearanceCookie(value: "stale")
        let freshCookie = try Self.clearanceCookie(value: "fresh")

        _ = env.solver.handleMainFrameResponse(Self.challengeResponse())
        env.solver.handleCookies([staleCookie])
        env.solver.handleCookies([staleCookie])
        env.solver.handleCookies([freshCookie])
        env.solver.handleCookies([try Self.clearanceCookie(value: "fresher")])

        XCTAssertEqual(firedPixelNames, [
            "dbp_challenge_main-frame_detected_macos_daily",
            "dbp_challenge_main-frame_detected_macos_count",
            "dbp_challenge_clearance_observed_macos_daily",
            "dbp_challenge_clearance_observed_macos_count"
        ])
        for parameters in firedPixelParameters {
            XCTAssertEqual(parameters["data_broker"], "example.com")
            XCTAssertEqual(parameters["broker_version"], "1.2.3")
            XCTAssertEqual(parameters["attempt_id"], Self.attemptId.uuidString)
            XCTAssertEqual(parameters["is_solver_enabled"], "false")
        }
        XCTAssertEqual(firedPixelParameters.last?["resolution"], "unassisted")
    }

    private static func challengeResponse() -> HTTPURLResponse {
        HTTPURLResponse(url: brokerURL, statusCode: 403, httpVersion: nil, headerFields: ["cf-mitigated": "challenge"])!
    }

    private static func brokerResponse(url: URL = brokerURL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    private static func clearanceCookie(value: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .name: "cf_clearance",
            .value: value,
            .domain: "example.com",
            .path: "/"
        ]))
    }
}

@MainActor
private final class Environment {
    let clock = FakeClock()
    let page = FakeChallengePage()
    let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    var mockPixelHandler: MockDataBrokerProtectionPixelsHandler? { pixelHandler as? MockDataBrokerProtectionPixelsHandler }
    private(set) var failures: [DataBrokerProtectionError] = []
    private(set) var solver: ChallengeSolver!

    var solvedResolutions: [DataBrokerProtectionSharedPixels.ChallengeResolution] {
        mockPixelHandler?.firedEvents.compactMap { event in
            guard case .challengeSolved(_, _, _, let resolution) = event else { return nil }
            return resolution
        } ?? []
    }

    var failedStages: [DataBrokerProtectionSharedPixels.ChallengeFailureStage] {
        mockPixelHandler?.firedEvents.compactMap { event in
            guard case .challengeFailed(_, _, _, let stage) = event else { return nil }
            return stage
        } ?? []
    }

    init(isEnabled: Bool = true,
         pixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = MockDataBrokerProtectionPixelsHandler()) {
        self.pixelHandler = pixelHandler
        let fakeClock = clock
        solver = ChallengeSolver(
            isEnabled: isEnabled,
            settings: ChallengeSolverSettings(),
            pixelContext: .init(dataBroker: "example.com", brokerVersion: "1.2.3", attemptId: ChallengeSolverTests.attemptId),
            pixelHandler: pixelHandler,
            reportEvent: { _, _ in },
            sleep: { try await fakeClock.sleep($0) },
            now: { fakeClock.now })
        solver.page = page
        solver.onFailure = { [weak self] in self?.failures.append($0) }
        solver.beginLoad(of: URL(string: "https://www.example.com/search")!)
    }
}

@MainActor
private final class FakeClock {
    private(set) var now = Date(timeIntervalSince1970: 0)
    var onSleep: ((TimeInterval) -> Void)?

    func sleep(_ interval: TimeInterval) async throws {
        now += interval
        onSleep?(interval)
        try Task.checkCancellation()
        await Task.yield()
    }
}

@MainActor
private final class FakeChallengePage: ChallengePage {
    var locate: () -> ChallengeLabel? = { nil }
    var onClick: (() -> Void)?
    private(set) var clickedPoints: [CGPoint] = []

    func locateLabel(matching text: String) async -> ChallengeLabel? {
        locate()
    }

    func click(at point: CGPoint, onMouseDown: () -> Void) async throws {
        try Task.checkCancellation()
        clickedPoints.append(point)
        onMouseDown()
        onClick?()
    }
}
#endif
