//
//  PasskeyUsagePixel.swift
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
import PixelKit
import UserScript

/// Pixels for passkey sign-ins and passkey creations on web pages.
enum PasskeyUsagePixel: PixelKit.Event {
    var namePrefix: PixelKitNamePrefix { .none }

    case useSuccess
    case useFailure(error: String)
    case createSuccess
    case createFailure(error: String)
    /// A passkey detection message the reporter didn't recognise.
    case unknownEvent

    var name: String {
        switch self {
        case .useSuccess: return "autofill_passkey_use_success_macos"
        case .useFailure: return "autofill_passkey_use_failure_macos"
        case .createSuccess: return "autofill_passkey_create_success_macos"
        case .createFailure: return "autofill_passkey_create_failure_macos"
        case .unknownEvent: return "autofill_passkey_unknown_event_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .useFailure(let error), .createFailure(let error):
            return ["error": error]
        case .useSuccess, .createSuccess, .unknownEvent:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// Reports passkey sign-in and creation outcomes from web pages as pixels, so we can see how often they succeed or fail.
/// The outcomes come from content-scope-scripts' `passkeyDetection`, which only runs when remote config enables it.
struct PasskeyUsagePixelReporter {

    /// The messages passkey detection sends.
    enum MessageName: String {
        case passkeyUsed
        case passkeyFailed
    }

    /// The error names a failure pixel may carry. Anything else is reported as `Other`, so a page can't put arbitrary
    /// text into a pixel.
    private static let knownErrors: Set<String> = [
        "NotAllowedError", "SecurityError", "NotSupportedError", "InvalidStateError", "ConstraintError", "AbortError",
        "UnknownError", "EncodingError", "NotReadableError", "TypeError", "Other"
    ]

    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    /// A handler for passkey detection's messages, or `nil` for any other `webCompat` message. Lets whichever object
    /// receives a tab's `webCompat` messages pass these on.
    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = MessageName(rawValue: methodName) else { return nil }
        return { params, _ in
            report(message, params: params)
            return nil
        }
    }

    /// Fires the pixel for one reported outcome. Messages that don't match a sign-in or a creation fire the unknown-event
    /// pixel instead, so changes to what the page script sends show up in the data.
    func report(_ message: MessageName, params: Any) {
        let params = params as? [String: Any]
        let type = params?["type"] as? String
        let pixel: PasskeyUsagePixel
        switch (message, type) {
        case (.passkeyUsed, "get"):
            pixel = .useSuccess
        case (.passkeyUsed, "create"):
            pixel = .createSuccess
        case (.passkeyFailed, "get"):
            pixel = .useFailure(error: Self.sanitizedError(params?["error"]))
        case (.passkeyFailed, "create"):
            pixel = .createFailure(error: Self.sanitizedError(params?["error"]))
        default:
            pixel = .unknownEvent
        }
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }

    private static func sanitizedError(_ value: Any?) -> String {
        guard let error = value as? String, knownErrors.contains(error) else { return "Other" }
        return error
    }
}
