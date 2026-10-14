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
import Foundation
import os.log
import PrivacyConfig

struct ChallengeSolverSettings: Decodable, Equatable {
    var autoPassWait: TimeInterval = 5
    var deadline: TimeInterval = 45
    var retryInterval: TimeInterval = 2
    var stabilityCheckDelay: TimeInterval = 0.4
    var stabilityTolerance: CGFloat = 8
    var checkboxOffset: CGFloat = 20
    var labelText = "Verify you are human"

    private enum CodingKeys: String, CodingKey {
        case autoPassWait = "autoPassWaitSeconds"
        case deadline = "deadlineSeconds"
        case retryInterval = "retryIntervalSeconds"
        case stabilityCheckDelay = "stabilityCheckDelaySeconds"
        case stabilityTolerance = "stabilityTolerancePoints"
        case checkboxOffset = "checkboxOffsetPoints"
        case labelText
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ChallengeSolverSettings()
        autoPassWait = try container.decodeIfPresent(TimeInterval.self, forKey: .autoPassWait) ?? defaults.autoPassWait
        deadline = try container.decodeIfPresent(TimeInterval.self, forKey: .deadline) ?? defaults.deadline
        retryInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .retryInterval) ?? defaults.retryInterval
        stabilityCheckDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .stabilityCheckDelay) ?? defaults.stabilityCheckDelay
        stabilityTolerance = try container.decodeIfPresent(CGFloat.self, forKey: .stabilityTolerance) ?? defaults.stabilityTolerance
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
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

    struct PixelContext {
        let dataBroker: String
        let brokerVersion: String
        let attemptId: UUID
    }

    var page: ChallengePage?
    var onFailure: ((DataBrokerProtectionError) -> Void)?

    private(set) var isHoldingLoad = false
    private(set) var solveTask: Task<Void, Never>?

    private let isEnabled: Bool
    private let settings: ChallengeSolverSettings
    private let pixelContext: PixelContext?
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let reportEvent: (String, Bool) -> Void
    private let sleep: Sleep
    private let now: () -> Date

    private var expectedHost: String?
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
         sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.settings = settings
        self.pixelContext = pixelContext
        self.pixelHandler = pixelHandler
        self.reportEvent = reportEvent
        self.sleep = sleep
        self.now = now
    }

    func beginLoad(of url: URL) {
        cancel()
        expectedHost = Self.normalizedHost(url.host)
        didDetectChallenge = false
        didCaptureClearanceBaseline = false
        clearanceBaseline = nil
        didReportClearance = false
    }

    /// Returns `true` when the solver holds the load for this response, so the caller must not fail it on its status code.
    func handleMainFrameResponse(_ response: HTTPURLResponse) -> Bool {
        let isChallenge = response.value(forHTTPHeaderField: "cf-mitigated")?.caseInsensitiveCompare("challenge") == .orderedSame
        isChallengeResponse = isChallenge

        if isChallenge {
            didDetectChallenge = true
            fireDetectionPixel()
            guard isEnabled else { return false }
            if !isHoldingLoad {
                isHoldingLoad = true
                reportEvent("Detected: main response has cf-mitigated=challenge; HTTP \(response.statusCode)", false)
                startSolving()
            }
            return true
        }

        guard isHoldingLoad else { return false }
        guard isExpectedBrokerDestination(response.url) else {
            Logger.action.log("Challenge: non-challenge response did not reach the expected broker host")
            return false
        }

        isHoldingLoad = false
        solveTask?.cancel()
        solveTask = nil
        let resolution = currentResolution
        reportEvent("Solved challenge \(resolution.rawValue); expected broker destination reached", false)
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
        isHoldingLoad = false
        didClick = false
    }

    private var currentResolution: DataBrokerProtectionSharedPixels.ChallengeResolution {
        if didClick { return .assisted }
        return isHoldingLoad ? .unknown : .unassisted
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
        let deadline = now().addingTimeInterval(settings.deadline)
        do {
            try await sleep(settings.autoPassWait)
            while isHoldingLoad, now() < deadline {
                if isChallengeResponse, !didClick, let page, let point = try await stableCheckboxPoint(on: page) {
                    try await click(at: point, on: page)
                }
                try await sleep(min(settings.retryInterval, max(0, deadline.timeIntervalSince(now()))))
            }
        } catch {
            return
        }

        guard isHoldingLoad else { return }
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

    private func stableCheckboxPoint(on page: ChallengePage) async throws -> CGPoint? {
        guard let firstLabel = await page.locateLabel(matching: settings.labelText) else {
            Logger.action.log("Challenge: first snapshot did not contain the verification label")
            return nil
        }
        try Task.checkCancellation()

        try await sleep(settings.stabilityCheckDelay)
        guard isChallengeResponse, let secondLabel = await page.locateLabel(matching: settings.labelText) else {
            Logger.action.log("Challenge: second snapshot did not contain the verification label")
            return nil
        }
        try Task.checkCancellation()

        guard firstLabel.isStable(comparedTo: secondLabel, tolerance: settings.stabilityTolerance) else {
            Logger.action.log("Challenge: snapshot rejected because the verification label was not stable")
            return nil
        }
        return secondLabel.checkboxPoint(offset: settings.checkboxOffset)
    }

    private func click(at point: CGPoint, on page: ChallengePage) async throws {
        guard isHoldingLoad, isChallengeResponse else { return }
        try await page.click(at: point) {
            didClick = true
        }
        guard didClick else {
            Logger.action.error("Challenge: checkbox click was not delivered")
            return
        }
        reportEvent("Sent checkbox click at \(Int(point.x)),\(Int(point.y))", false)
    }

    private func isExpectedBrokerDestination(_ url: URL?) -> Bool {
        guard let expectedHost, let responseHost = Self.normalizedHost(url?.host) else { return false }
        return responseHost == expectedHost || responseHost.hasSuffix(".\(expectedHost)") || expectedHost.hasSuffix(".\(responseHost)")
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard let host = host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
#endif
