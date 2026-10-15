//
//  PasskeyRequestOutcomeReporter.swift
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

import AuthenticationServices
import Foundation
import os.log
import PixelKit

/// How a WebKit passkey request ended, as reported in pixels.
struct PasskeyRequestOutcome: Equatable {

    enum Style: String {
        case modal
        case autofill
        case unknown
    }

    enum RequestType: String {
        case get
        case create
        case other
    }

    enum Result: Equatable {
        case success
        /// The user closed the passkey sheet.
        case canceled
        case failure(Failure)
    }

    enum Failure: Equatable {
        /// The agent refused the request because the app already has one open, which is what passkeys being stuck looks like.
        case requestInProgress
        case failed
        case other(code: Int)

        var parameterValue: String {
            switch self {
            case .requestInProgress: return "requestInProgress"
            case .failed: return "failed"
            case .other(let code): return "other_\(code)"
            }
        }
    }

    enum Duration: String {
        case under100ms
        case under1s
        case under10s
        case under1m
        case over1m

        init(_ interval: TimeInterval) {
            switch interval {
            case ..<0.1: self = .under100ms
            case ..<1: self = .under1s
            case ..<10: self = .under10s
            case ..<60: self = .under1m
            default: self = .over1m
            }
        }
    }

    let style: Style
    let type: RequestType
    let result: Result
    let duration: Duration
}

extension PasskeyRequestOutcome {

    /// Whether this request makes the user an active passkey user.
    var isActiveUse: Bool {
        switch (result, style) {
        case (.success, _):
            // The user used a passkey.
            return true
        case (.failure(.requestInProgress), _):
            // The system refused the request because another one is still open, so no sheet was shown.
            return false
        case (_, .modal):
            // The user saw the passkey sheet, however it ended.
            return true
        case (_, .autofill), (_, .unknown):
            // AutoFill requests start on page load for every visitor, so only a passkey the user picked counts.
            return false
        }
    }
}

extension PasskeyRequestOutcome.Result {

    /// The reason the agent gives when it refuses a request because the app already has one open.
    private static let requestInProgressReason = "Request already in progress for specified application identifier."

    /// The result of a request that ended with `error`, or succeeded if there's none.
    init(error: NSError?) {
        guard let error else {
            self = .success
            return
        }
        guard error.domain == ASAuthorizationError.errorDomain else {
            self = .failure(.other(code: error.code))
            return
        }
        switch ASAuthorizationError.Code(rawValue: error.code) {
        case .canceled:
            self = .canceled
        case .failed where error.userInfo[NSLocalizedFailureReasonErrorKey] as? String == Self.requestInProgressReason:
            self = .failure(.requestInProgress)
        case .failed:
            self = .failure(.failed)
        default:
            self = .failure(.other(code: error.code))
        }
    }
}

/// Fires a pixel for how each WebKit passkey request ends, so we can see whether passkeys work for users, and a daily
/// pixel for users who used a passkey or saw the passkey sheet.
///
/// Successes and cancellations fire right away. A failure waits for ``failureDelay`` and fires only if no other outcome
/// arrives first: a newer failure replaces it, and a success or cancellation drops it. Pages often retry a failed
/// request, so this reports one failure per burst of retries, and none when the user ends up seeing the passkey sheet.
final class PasskeyRequestOutcomeReporter {

    private let pixelFiring: PixelFiring?
    private let failureDelay: TimeInterval
    private var pendingFailure: DispatchWorkItem?

    init(pixelFiring: PixelFiring? = PixelKit.shared, failureDelay: TimeInterval = 3) {
        self.pixelFiring = pixelFiring
        self.failureDelay = failureDelay
    }

    func report(_ outcome: PasskeyRequestOutcome) {
        pendingFailure?.cancel()
        pendingFailure = nil

        if outcome.isActiveUse {
            pixelFiring?.fire(PasskeyActiveUserPixel(), frequency: .daily)
        }

        let pixel = PasskeyRequestOutcomePixel(outcome)
        Logger.general.log("WebKit passkey request outcome: \(pixel.name, privacy: .public) \(pixel.parameters ?? [:], privacy: .public)")

        guard case .failure = outcome.result else {
            pixelFiring?.fire(pixel, frequency: .dailyAndCount)
            return
        }
        let fire = DispatchWorkItem { [weak self] in
            self?.pendingFailure = nil
            self?.pixelFiring?.fire(pixel, frequency: .dailyAndCount)
        }
        pendingFailure = fire
        DispatchQueue.main.asyncAfter(deadline: .now() + failureDelay, execute: fire)
    }
}

/// Pixels for how WebKit passkey requests end.
struct PasskeyRequestOutcomePixel: PixelKit.Event {

    let outcome: PasskeyRequestOutcome

    init(_ outcome: PasskeyRequestOutcome) {
        self.outcome = outcome
    }

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch outcome.result {
        case .success: return "passkey_request_success_macos"
        case .canceled: return "passkey_request_cancel_macos"
        case .failure: return "passkey_request_failure_macos"
        }
    }

    var parameters: [String: String]? {
        var parameters = [
            "style": outcome.style.rawValue,
            "type": outcome.type.rawValue,
            "duration": outcome.duration.rawValue
        ]
        if case .failure(let failure) = outcome.result {
            parameters["error"] = failure.parameterValue
        }
        return parameters
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// A user used a passkey or saw the passkey sheet today.
struct PasskeyActiveUserPixel: PixelKit.Event {
    var name: String { "passkey_active_user_macos" }
    var namePrefix: PixelKitNamePrefix { .none }
    var parameters: [String: String]? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}
