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

import Common
import ConcurrencyExtensions
import Foundation
import os.log
import PrivacyConfig

#if os(macOS)
struct ChallengeSolverSettings: Decodable {
    var enabledBrokers: [String] = []
    var autoPassWait: TimeInterval = 5
    var checkboxOffset: CGFloat = 20
    var labelText = "Verify you are human"

    private enum CodingKeys: String, CodingKey {
        case enabledBrokers
        case autoPassWait = "autoPassWaitSeconds"
        case checkboxOffset = "checkboxOffsetPoints"
        case labelText
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ChallengeSolverSettings()
        enabledBrokers = try container.decodeIfPresent([String].self, forKey: .enabledBrokers) ?? defaults.enabledBrokers
        autoPassWait = try container.decodeIfPresent(TimeInterval.self, forKey: .autoPassWait) ?? defaults.autoPassWait
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
struct ChallengeLabel: Sendable {
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
    private enum ClearanceObservation {
        case notDetected
        case waitingForFirstCookieRead
        case waitingForClearanceCookieChange(initialValue: String?)
        case clearanceReported
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
    private let dataBroker: DataBroker?
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let reportEvent: (String, Bool) -> Void
    private let sleeper: Sleeper
    private let dateProvider: CurrentDateProviding

    private var didSendChallengeClick = false
    private var clearanceObservation: ClearanceObservation = .notDetected

    init(isEnabled: Bool,
         settings: ChallengeSolverSettings,
         dataBroker: DataBroker?,
         pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?,
         reportEvent: @escaping (String, Bool) -> Void,
         sleeper: Sleeper = .default,
         dateProvider: CurrentDateProviding = DefaultCurrentDateProvider()) {
        self.isEnabled = isEnabled && (dataBroker.map { settings.enabledBrokers.contains($0.url) } ?? false)
        self.settings = settings
        self.dataBroker = dataBroker
        self.pixelHandler = pixelHandler
        self.reportEvent = reportEvent
        self.sleeper = sleeper
        self.dateProvider = dateProvider
    }

    func beginLoad() {
        cancel()
        clearanceObservation = .notDetected
    }

    /// Returns `true` while the solver is awaiting a solve for this response, so the caller must not fail the load on its status code.
    func handleMainFrameResponse(_ response: HTTPURLResponse) -> Bool {
        let isChallenge = response.value(forHTTPHeaderField: Constants.mitigatedHeaderField)?.caseInsensitiveCompare(Constants.challengeMitigation) == .orderedSame
        if isChallenge {
            if case .notDetected = clearanceObservation {
                clearanceObservation = .waitingForFirstCookieRead
            }
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
        if let dataBroker {
            pixelHandler?.fire(.challengeSolved(dataBroker: dataBroker.url,
                                                brokerVersion: dataBroker.version,
                                                resolution: resolution))
        }
        return false
    }

    /// Reports challenge clearance once per load when `cf_clearance` changes from its first observed value after detection.
    /// Ignores unchanged cookies from earlier challenges and further cookie changes after reporting clearance.
    /// Compared locally to determine outcome; never included in the pixel payload.
    func handleCookies(_ cookies: [HTTPCookie]) {
        let clearance = cookies.first { $0.name.caseInsensitiveCompare("cf_clearance") == .orderedSame }?.value

        switch clearanceObservation {
        case .notDetected, .clearanceReported:
            return
        case .waitingForFirstCookieRead:
            clearanceObservation = .waitingForClearanceCookieChange(initialValue: clearance)
            return
        case .waitingForClearanceCookieChange(let initialValue):
            guard let clearance, clearance != initialValue else { return }
        }

        clearanceObservation = .clearanceReported
        let resolution = currentResolution
        reportEvent("Supporting evidence: cf_clearance changed; resolution=\(resolution.rawValue)", false)
        guard let dataBroker else { return }
        pixelHandler?.fire(.challengeClearanceObserved(dataBroker: dataBroker.url,
                                                       brokerVersion: dataBroker.version,
                                                       resolution: resolution,
                                                       isSolverEnabled: isEnabled))
    }

    func cancel() {
        solveTask?.cancel()
        solveTask = nil
        isAwaitingSolve = false
        didSendChallengeClick = false
    }

    private var currentResolution: DataBrokerProtectionSharedPixels.ChallengeResolution {
        if didSendChallengeClick { return .assisted }
        return isAwaitingSolve ? .unknown : .unassisted
    }

    private func fireDetectionPixel() {
        guard let dataBroker else { return }
        Logger.action.log("Challenge: pixel detected fired for \(dataBroker.url, privacy: .public)")
        pixelHandler?.fire(.mainFrameChallengeDetected(dataBroker: dataBroker.url,
                                                       brokerVersion: dataBroker.version,
                                                       isSolverEnabled: isEnabled))
    }

    private func startSolving() {
        solveTask?.cancel()
        didSendChallengeClick = false
        solveTask = Task { [weak self] in
            await self?.solve()
        }
    }

    private func solve() async {
        let deadline = dateProvider.currentDate.addingTimeInterval(BrokerJobExecutionConfig.Constants.defaultCssActionTimeout)
        do {
            try await sleep(for: settings.autoPassWait)
            while isAwaitingSolve, dateProvider.currentDate < deadline {
                if !didSendChallengeClick, let page, let point = try await stableCheckboxPoint(on: page) {
                    try await click(at: point, on: page)
                }
                try await sleep(for: min(Constants.retryInterval, deadline.timeIntervalSince(dateProvider.currentDate)))
            }
        } catch {
            return
        }

        guard isAwaitingSolve else { return }
        let failureStage: DataBrokerProtectionSharedPixels.ChallengeFailureStage = didSendChallengeClick ? .afterClick : .noClick
        let failureDescription = didSendChallengeClick ? "after click" : "with no click delivered"
        cancel()
        reportEvent("Failed challenge \(failureDescription); broker destination did not arrive before the deadline", true)
        if let dataBroker {
            pixelHandler?.fire(.challengeFailed(dataBroker: dataBroker.url,
                                                brokerVersion: dataBroker.version,
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
        guard isAwaitingSolve, let secondLabel = await page.locateLabel(matching: settings.labelText) else {
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
        guard isAwaitingSolve else { return }
        try await page.click(at: point) {
            didSendChallengeClick = true
        }
        guard didSendChallengeClick else {
            Logger.action.error("Challenge: checkbox click was not delivered")
            return
        }
        reportEvent("Sent checkbox click at \(Int(point.x)),\(Int(point.y))", false)
    }
}
#endif
