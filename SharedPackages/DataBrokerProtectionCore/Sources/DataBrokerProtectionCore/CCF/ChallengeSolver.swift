//
//  ChallengeSolver.swift
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
import ConcurrencyExtensions
import Foundation
import os.log
import PrivacyConfig

struct ChallengeSolverSettings: Decodable {
    var autoPassWait: TimeInterval = 5
    var deadline: TimeInterval = 45
    var checkboxOffset: CGFloat = 20
    var labelText = "Verify you are human"

    private enum CodingKeys: String, CodingKey {
        case autoPassWait = "autoPassWaitSeconds"
        case deadline = "deadlineSeconds"
        case checkboxOffset = "checkboxOffsetPoints"
        case labelText
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ChallengeSolverSettings()
        autoPassWait = try container.decodeIfPresent(TimeInterval.self, forKey: .autoPassWait) ?? defaults.autoPassWait
        deadline = try container.decodeIfPresent(TimeInterval.self, forKey: .deadline) ?? defaults.deadline
        checkboxOffset = try container.decodeIfPresent(CGFloat.self, forKey: .checkboxOffset) ?? defaults.checkboxOffset
        labelText = try container.decodeIfPresent(String.self, forKey: .labelText) ?? defaults.labelText
    }

    init(privacyConfig: PrivacyConfiguration) {
        guard let settingsString = privacyConfig.settings(for: DBPSubfeature.challengeSolver),
              let settingsData = settingsString.data(using: .utf8),
              let settings = try? JSONDecoder().decode(ChallengeSolverSettings.self, from: settingsData) else {
            self.init()
            return
        }
        self = settings
    }
}

/// The challenge label's frame in the web view's top-left-origin coordinates.
struct ChallengeLabel: Equatable, Sendable {
    let frame: CGRect

    func checkboxPoint(offset: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX - offset, y: frame.midY)
    }

    func isStable(comparedTo other: ChallengeLabel, tolerance: CGFloat) -> Bool {
        abs(frame.minX - other.frame.minX) < tolerance
            && abs(frame.minY - other.frame.minY) < tolerance
            && abs(frame.width - other.frame.width) < tolerance
            && abs(frame.height - other.frame.height) < tolerance
    }
}

@MainActor
protocol ChallengePage: AnyObject {
    func locateLabel(matching text: String) async -> ChallengeLabel?
    /// Calls `onMouseDown` once the click reaches the page. Throws `CancellationError` without clicking when the task is cancelled first.
    func click(at point: CGPoint, onMouseDown: () -> Void) async throws
}

@MainActor
final class ChallengeSolver {
    struct PixelContext {
        let dataBroker: String
        let brokerVersion: String
        let attemptId: UUID
    }

    private enum Constants {
        static let retryInterval: TimeInterval = 2
        static let stabilityCheckDelay: TimeInterval = 0.4
        static let stabilityTolerance: CGFloat = 8
        static let mitigatedHeaderField = "cf-mitigated"
        static let challengeMitigation = "challenge"
    }

    var page: ChallengePage?
    var onFailure: ((DataBrokerProtectionError) -> Void)?

    private(set) var isAwaitingSolve = false
    private(set) var solveTask: Task<Void, Never>?

    private let isEnabled: Bool
    private let settings: ChallengeSolverSettings
    private let pixelContext: PixelContext?
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let reportEvent: (String, Bool) -> Void
    private let sleeper: Sleeper
    private let dateProvider: CurrentDateProviding

    private var isChallengeResponse = false
    private var didClick = false
    private var didDetectChallenge = false
    private var didCaptureClearanceBaseline = false
    private var clearanceBaseline: String?
    private var didReportClearance = false

    init(isEnabled: Bool,
         settings: ChallengeSolverSettings,
         pixelContext: PixelContext?,
         pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?,
         reportEvent: @escaping (String, Bool) -> Void,
         sleeper: Sleeper = .default,
         dateProvider: CurrentDateProviding = DefaultCurrentDateProvider()) {
        self.isEnabled = isEnabled
        self.settings = settings
        self.pixelContext = pixelContext
        self.pixelHandler = pixelHandler
        self.reportEvent = reportEvent
        self.sleeper = sleeper
        self.dateProvider = dateProvider
    }

    func beginLoad() {
        cancel()
        didDetectChallenge = false
        didCaptureClearanceBaseline = false
        clearanceBaseline = nil
        didReportClearance = false
    }

    /// Returns `true` while the solver is awaiting a solve for this response, so the caller must not fail the load on its status code.
    func handleMainFrameResponse(_ response: HTTPURLResponse) -> Bool {
        let isChallenge = response.value(forHTTPHeaderField: Constants.mitigatedHeaderField)?.caseInsensitiveCompare(Constants.challengeMitigation) == .orderedSame
        isChallengeResponse = isChallenge

        if isChallenge {
            didDetectChallenge = true
            fireDetectionPixel()
            guard isEnabled else { return false }
            if !isAwaitingSolve {
                isAwaitingSolve = true
                reportEvent("Detected: main response has cf-mitigated=challenge; HTTP \(response.statusCode)", false)
                startSolving()
            }
            return true
        }

        guard isAwaitingSolve else { return false }

        isAwaitingSolve = false
        solveTask?.cancel()
        solveTask = nil
        let resolution = currentResolution
        reportEvent("Solved challenge \(resolution.rawValue); a non-challenge main-frame response arrived", false)
        if let pixelContext {
            pixelHandler?.fire(.challengeSolved(dataBroker: pixelContext.dataBroker,
                                                brokerVersion: pixelContext.brokerVersion,
                                                attemptId: pixelContext.attemptId,
                                                resolution: resolution))
        }
        return false
    }

    /// Fires the clearance pixel when `cf_clearance` changes after a challenge. The first cookies seen after detection are the baseline,
    /// so a clearance left over from an earlier challenge in the same job does not count.
    func handleCookies(_ cookies: [HTTPCookie]) {
        guard didDetectChallenge, !didReportClearance else { return }
        let clearance = cookies.first { $0.name.caseInsensitiveCompare("cf_clearance") == .orderedSame }?.value

        guard didCaptureClearanceBaseline else {
            didCaptureClearanceBaseline = true
            clearanceBaseline = clearance
            return
        }
        guard let clearance, clearance != clearanceBaseline else { return }

        didReportClearance = true
        let resolution = currentResolution
        reportEvent("Supporting evidence: cf_clearance changed; resolution=\(resolution.rawValue)", false)
        guard let pixelContext else { return }
        pixelHandler?.fire(.challengeClearanceObserved(dataBroker: pixelContext.dataBroker,
                                                       brokerVersion: pixelContext.brokerVersion,
                                                       attemptId: pixelContext.attemptId,
                                                       resolution: resolution,
                                                       isSolverEnabled: isEnabled))
    }

    func cancel() {
        solveTask?.cancel()
        solveTask = nil
        isChallengeResponse = false
        isAwaitingSolve = false
        didClick = false
    }

    private var currentResolution: DataBrokerProtectionSharedPixels.ChallengeResolution {
        if didClick { return .assisted }
        return isAwaitingSolve ? .unknown : .unassisted
    }

    private func fireDetectionPixel() {
        guard let pixelContext else { return }
        Logger.action.log("Challenge: pixel detected fired for \(pixelContext.dataBroker, privacy: .public)")
        pixelHandler?.fire(.mainFrameChallengeDetected(dataBroker: pixelContext.dataBroker,
                                                       brokerVersion: pixelContext.brokerVersion,
                                                       attemptId: pixelContext.attemptId,
                                                       isSolverEnabled: isEnabled))
    }

    private func startSolving() {
        solveTask?.cancel()
        didClick = false
        solveTask = Task { [weak self] in
            await self?.solve()
        }
    }

    private func solve() async {
        let deadline = dateProvider.currentDate.addingTimeInterval(settings.deadline)
        do {
            try await sleep(for: settings.autoPassWait)
            while isAwaitingSolve, dateProvider.currentDate < deadline {
                if isChallengeResponse, !didClick, let page, let point = try await stableCheckboxPoint(on: page) {
                    try await click(at: point, on: page)
                }
                try await sleep(for: min(Constants.retryInterval, deadline.timeIntervalSince(dateProvider.currentDate)))
            }
        } catch {
            return
        }

        guard isAwaitingSolve else { return }
        let failureStage: DataBrokerProtectionSharedPixels.ChallengeFailureStage = didClick ? .afterClick : .noClick
        let failureDescription = didClick ? "after click" : "with no click delivered"
        cancel()
        reportEvent("Failed challenge \(failureDescription); broker destination did not arrive before the deadline", true)
        if let pixelContext {
            pixelHandler?.fire(.challengeFailed(dataBroker: pixelContext.dataBroker,
                                                brokerVersion: pixelContext.brokerVersion,
                                                attemptId: pixelContext.attemptId,
                                                stage: failureStage))
        }
        onFailure?(.challengeNotSolved)
    }

    /// `Sleeper.default` asserts on a non-positive interval, which the remote auto-pass wait or the time left before the deadline can be.
    private func sleep(for interval: TimeInterval) async throws {
        guard interval > 0 else {
            try Task.checkCancellation()
            return
        }
        try await sleeper.sleep(for: interval)
    }

    private func stableCheckboxPoint(on page: ChallengePage) async throws -> CGPoint? {
        guard let firstLabel = await page.locateLabel(matching: settings.labelText) else {
            Logger.action.log("Challenge: first snapshot did not contain the verification label")
            return nil
        }
        try Task.checkCancellation()

        try await sleep(for: Constants.stabilityCheckDelay)
        guard isChallengeResponse, let secondLabel = await page.locateLabel(matching: settings.labelText) else {
            Logger.action.log("Challenge: second snapshot did not contain the verification label")
            return nil
        }
        try Task.checkCancellation()

        guard firstLabel.isStable(comparedTo: secondLabel, tolerance: Constants.stabilityTolerance) else {
            Logger.action.log("Challenge: snapshot rejected because the verification label was not stable")
            return nil
        }
        return secondLabel.checkboxPoint(offset: settings.checkboxOffset)
    }

    private func click(at point: CGPoint, on page: ChallengePage) async throws {
        guard isAwaitingSolve, isChallengeResponse else { return }
        try await page.click(at: point) {
            didClick = true
        }
        guard didClick else {
            Logger.action.error("Challenge: checkbox click was not delivered")
            return
        }
        reportEvent("Sent checkbox click at \(Int(point.x)),\(Int(point.y))", false)
    }
}
#endif
