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
        case failure(NSError)
    }

    let style: Style
    let type: RequestType
    let result: Result
}

extension PasskeyRequestOutcome {

    /// Whether this request makes the user an active passkey user.
    var isActiveUse: Bool {
        switch (result, style) {
        case (.success, _):
            // The user used a passkey.
            return true
        case (.failure(let error), _) where error.isPasskeyRequestInProgress:
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

    /// Whether this request shows passkeys are stuck: the user asked for the passkey sheet and the system refused it
    /// because another request is still open. AutoFill refusals don't count, since they also happen once in a while
    /// without being stuck.
    var isStuck: Bool {
        guard style == .modal, case .failure(let error) = result else { return false }
        return error.isPasskeyRequestInProgress
    }
}

extension PasskeyRequestOutcome.Result {

    /// The result of a request that ended with `error`, or succeeded if there's none.
    init(error: NSError?) {
        switch error {
        case nil:
            self = .success
        case let error? where error.domain == ASAuthorizationError.errorDomain && error.code == ASAuthorizationError.canceled.rawValue:
            self = .canceled
        case let error?:
            self = .failure(error)
        }
    }
}

extension NSError {

    /// The reason the agent gives when it refuses a request because the app already has one open.
    private static let passkeyRequestInProgressReason = "Request already in progress for specified application identifier."

    /// Whether the agent refused the request because the app already has one open, which is what passkeys being stuck
    /// looks like.
    var isPasskeyRequestInProgress: Bool {
        domain == ASAuthorizationError.errorDomain
            && code == ASAuthorizationError.failed.rawValue
            && userInfo[NSLocalizedFailureReasonErrorKey] as? String == Self.passkeyRequestInProgressReason
    }
}

/// Fires a pixel for how each WebKit passkey request ends, so we can see whether passkeys work for users, and a daily
/// pixel for users who used a passkey or saw the passkey sheet.
///
/// Successes and cancellations fire right away. A failure waits for ``failureDelay`` and fires only if no other outcome
/// arrives first: a newer failure replaces it, and a success or cancellation drops it. Pages often retry a failed
/// request, so this reports one failure per burst of retries, and none when the user ends up seeing the passkey sheet.
@MainActor
final class PasskeyRequestOutcomeReporter {

    private let pixelFiring: PixelFiring?
    private let failureDelay: TimeInterval
    private var pendingFailure: DispatchWorkItem?

    init(pixelFiring: PixelFiring? = PixelKit.shared, failureDelay: TimeInterval = 3) {
        self.pixelFiring = pixelFiring
        self.failureDelay = failureDelay
    }

    func report(_ outcome: PasskeyRequestOutcome) {
        if outcome.isActiveUse {
            pixelFiring?.fire(PasskeyActiveUserPixel(), frequency: .daily)
        }
        if outcome.isStuck {
            pixelFiring?.fire(PasskeyStuckPixel(), frequency: .dailyAndCount)
        }

        // The outcome replaces the failure waiting to fire, if there's one.
        pendingFailure?.cancel()
        pendingFailure = nil

        let fireNow = { [weak self] in
            let pixel = PasskeyRequestOutcomePixel(outcome)
            self?.pixelFiring?.fire(pixel, frequency: .dailyAndCount)
        }

        // Successes and cancellations are what the user sees, so they fire right away. Failures are noisy and are often
        // intermediate states the user never sees, such as a request the page retries, so one fires only if no other
        // outcome follows within `failureDelay`.
        switch outcome.result {
        case .success, .canceled:
            fireNow()
        case .failure:
            let fireLater = DispatchWorkItem { [weak self] in
                self?.pendingFailure = nil
                fireNow()
            }
            pendingFailure = fireLater
            DispatchQueue.main.asyncAfter(deadline: .now() + failureDelay, execute: fireLater)
        }
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
        [
            "style": outcome.style.rawValue,
            "type": outcome.type.rawValue,
            // Routes the pixel through the PETAL (timestamp-randomization) pipeline.
            "petal": "randomize"
        ]
    }

    var error: NSError? {
        guard case .failure(let error) = outcome.result else { return nil }
        return error
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

/// The system refused to show the passkey sheet the user asked for, because another request is still open.
struct PasskeyStuckPixel: PixelKit.Event {
    var name: String { "passkey_stuck_macos" }
    var namePrefix: PixelKitNamePrefix { .none }
    var parameters: [String: String]? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}
