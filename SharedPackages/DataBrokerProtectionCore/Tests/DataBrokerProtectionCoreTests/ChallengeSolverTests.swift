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
import BrowserServicesKitTestsUtils
import Common
import ConcurrencyExtensions
import DataBrokerProtectionCoreTestsUtils
@_spi(Testing) import PixelKit
import XCTest
@testable import DataBrokerProtectionCore

final class ChallengeSolverTests: XCTestCase {

    private static let brokerURL = URL(string: "https://www.example.com/search")!
    private static let label = ChallengeLabel(frame: CGRect(x: 100, y: 200, width: 150, height: 20))

    func testWhenChallengePixelsFire_thenExcludeAttemptID() {
        let events: [DataBrokerProtectionSharedPixels] = [
            .mainFrameChallengeDetected(dataBroker: "example.com", brokerVersion: "1.2.3", isSolverEnabled: true),
            .challengeClearanceObserved(dataBroker: "example.com", brokerVersion: "1.2.3",
                                        resolution: .assisted, isSolverEnabled: true),
            .challengeSolved(dataBroker: "example.com", brokerVersion: "1.2.3", resolution: .assisted),
            .challengeFailed(dataBroker: "example.com", brokerVersion: "1.2.3", stage: .afterClick)
        ]
        let pixelKit = PixelKitMock()
        for event in events {
            pixelKit.fire(event, frequency: .dailyAndCount)
        }

        XCTAssertEqual(pixelKit.actualFireCalls.count, 4)
        for call in pixelKit.actualFireCalls {
            XCTAssertNil(call.pixel.parameters?["attempt_id"], call.pixel.name)
            XCTAssertEqual(call.pixel.parameters?["data_broker"], "example.com")
            XCTAssertEqual(call.pixel.parameters?["broker_version"], "1.2.3")
        }
    }

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
    func testWhenNonChallengeResponseComesFromAnotherHost_thenSolves() async {
        let env = Environment()
        env.page.locate = { nil }
        env.clock.onSleep = { _ in
            _ = env.solver.handleMainFrameResponse(Self.brokerResponse(url: URL(string: "https://other.org")!))
        }

        _ = env.solver.handleMainFrameResponse(Self.challengeResponse())
        await env.solver.solveTask?.value

        XCTAssertFalse(env.solver.isAwaitingSolve)
        XCTAssertTrue(env.failures.isEmpty)
        XCTAssertEqual(env.solvedResolutions, [.unassisted])
    }

    @MainActor
    func testWhenJobIsIneligible_thenDoesNotStartSolving() async throws {
        let cases = [
            ("{}", true, true),
            (#"{"enabledBrokers":[]}"#, true, true),
            (#"{"enabledBrokers":["other.org","www.example.com","EXAMPLE.COM"]}"#, true, true),
            (#"{"enabledBrokers":["example.*"]}"#, true, true),
            (#"{"enabledBrokers":["example.com"]}"#, false, true),
            (#"{"enabledBrokers":["example.com"]}"#, true, false),
            (#"{"enabledBrokers":["*"]}"#, false, true),
            (#"{"enabledBrokers":["*"]}"#, true, false)
        ]
        for (json, isEnabled, hasDataBroker) in cases {
            let settings = try JSONDecoder().decode(ChallengeSolverSettings.self, from: Data(json.utf8))
            let dataBroker = hasDataBroker
                ? DataBroker.mockWithDefaults(url: "example.com", version: "1.2.3")
                : nil
            let env = Environment(isEnabled: isEnabled, settings: settings, dataBroker: dataBroker)

            XCTAssertFalse(env.solver.handleMainFrameResponse(Self.challengeResponse()), json)
            XCTAssertFalse(env.solver.isAwaitingSolve, json)
            XCTAssertNil(env.solver.solveTask, json)
            await env.solver.solveTask?.value

            XCTAssertEqual(env.clock.dateProvider.currentDate, Date(timeIntervalSince1970: 0), json)
            XCTAssertEqual(env.page.locateCount, 0, json)
            XCTAssertTrue(env.page.clickedPoints.isEmpty, json)
            XCTAssertTrue(env.failures.isEmpty, json)
            XCTAssertTrue(env.solvedResolutions.isEmpty, json)
            XCTAssertEqual(env.mockPixelHandler?.firedEvents.count, hasDataBroker ? 1 : 0, json)
            if hasDataBroker {
                guard case .mainFrameChallengeDetected(_, _, let isSolverEnabled) = env.mockPixelHandler?.firedEvents.first else {
                    return XCTFail("Expected the detection pixel")
                }
                XCTAssertFalse(isSolverEnabled, json)
            }
        }
    }

    @MainActor
    func testWhenJobBrokerIsTargetedAndChallengeHostDiffers_thenStartsSolving() async throws {
        let cases = [
            #"{"enabledBrokers":["example.com"]}"#,
            #"{"enabledBrokers":["*"]}"#,
            #"{"enabledBrokers":["other.org","*"]}"#
        ]
        for json in cases {
            let settings = try JSONDecoder().decode(ChallengeSolverSettings.self, from: Data(json.utf8))
            let env = Environment(settings: settings)
            env.page.locate = { Self.label }
            env.page.onClick = { _ = env.solver.handleMainFrameResponse(Self.brokerResponse()) }

            XCTAssertTrue(env.solver.handleMainFrameResponse(Self.challengeResponse(url: URL(string: "https://other.org")!)), json)
            await env.solver.solveTask?.value

            XCTAssertEqual(env.page.clickedPoints, [CGPoint(x: 80, y: 210)], json)
            XCTAssertTrue(env.failures.isEmpty, json)
            XCTAssertEqual(env.solvedResolutions, [.assisted], json)
        }
    }

    @MainActor
    func testWhenClearanceCookieExistedBeforeChallenge_thenClearancePixelFiresOnceAfterItChanges() throws {
        let cases = [
            ("{}", true, false),
            (#"{"enabledBrokers":[]}"#, true, false),
            (#"{"enabledBrokers":["other.org"]}"#, true, false),
            (#"{"enabledBrokers":["example.com"]}"#, false, false),
            (#"{"enabledBrokers":["example.com"]}"#, true, true),
            (#"{"enabledBrokers":["*"]}"#, false, false),
            (#"{"enabledBrokers":["*"]}"#, true, true)
        ]
        for (json, isEnabled, isSolverEnabled) in cases {
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
            let settings = try JSONDecoder().decode(ChallengeSolverSettings.self, from: Data(json.utf8))
            let env = Environment(isEnabled: isEnabled,
                                  settings: settings,
                                  pixelHandler: DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS))
            defer { env.solver.cancel() }
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
                XCTAssertNil(parameters["attempt_id"])
                XCTAssertEqual(parameters["is_solver_enabled"], String(isSolverEnabled))
            }
            XCTAssertEqual(firedPixelParameters.last?["resolution"], isSolverEnabled ? "unknown" : "unassisted")
        }
    }

    private static func challengeResponse(url: URL = brokerURL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: ["cf-mitigated": "challenge"])!
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
            guard case .challengeSolved(_, _, let resolution) = event else { return nil }
            return resolution
        } ?? []
    }

    var failedStages: [DataBrokerProtectionSharedPixels.ChallengeFailureStage] {
        mockPixelHandler?.firedEvents.compactMap { event in
            guard case .challengeFailed(_, _, let stage) = event else { return nil }
            return stage
        } ?? []
    }

    init(isEnabled: Bool = true,
         settings: ChallengeSolverSettings? = nil,
         dataBroker: DataBroker? = .mockWithDefaults(url: "example.com", version: "1.2.3"),
         pixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = MockDataBrokerProtectionPixelsHandler()) {
        self.pixelHandler = pixelHandler
        let fakeClock = clock
        var defaultSettings = ChallengeSolverSettings()
        defaultSettings.enabledBrokers = ["example.com"]
        solver = ChallengeSolver(
            isEnabled: isEnabled,
            settings: settings ?? defaultSettings,
            dataBroker: dataBroker,
            pixelHandler: pixelHandler,
            reportEvent: { _, _ in },
            sleeper: Sleeper { try await fakeClock.sleep($0) },
            dateProvider: fakeClock.dateProvider)
        solver.page = page
        solver.onFailure = { [weak self] in self?.failures.append($0) }
        solver.beginLoad()
    }
}

@MainActor
private final class FakeClock {
    let dateProvider = MockCurrentDateProvider(currentDate: Date(timeIntervalSince1970: 0))
    var onSleep: ((TimeInterval) -> Void)?

    func sleep(_ interval: TimeInterval) async throws {
        dateProvider.currentDate += interval
        onSleep?(interval)
        try Task.checkCancellation()
        await Task.yield()
    }
}

@MainActor
private final class FakeChallengePage: ChallengePage {
    var locate: () -> ChallengeLabel? = { nil }
    var onClick: (() -> Void)?
    private(set) var locateCount = 0
    private(set) var clickedPoints: [CGPoint] = []

    func locateLabel(matching text: String) async -> ChallengeLabel? {
        locateCount += 1
        return locate()
    }

    func click(at point: CGPoint, onMouseDown: () -> Void) async throws {
        try Task.checkCancellation()
        clickedPoints.append(point)
        onMouseDown()
        onClick?()
    }
}
#endif
