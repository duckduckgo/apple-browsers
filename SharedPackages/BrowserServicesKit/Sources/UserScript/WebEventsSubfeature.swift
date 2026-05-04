//
//  WebEventsSubfeature.swift
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
import WebKit

/// User's YouTube login state at the time a detection event was emitted.
/// `unknown` is the catch-all for missing or unrecognised values from
/// content-scope-scripts so the pixel always reports a schema-valid value.
public enum LoginState: String {
    case loggedIn = "logged-in"
    case loggedOut = "logged-out"
    case premium
    case unknown
}

/// C-S-S subfeature that receives web interference detection events
/// (currently YouTube ad-blocking related) and forwards each gated event
/// to the platform-supplied pixel-firing closure.
///
/// JS side: content-scope-scripts `webInterferenceDetection` feature with
/// `featureName: "webEvents"`, method `"webEvent"`.
/// Params shape: `{ "type": String, "data": { "loginState": String? } }`.
public final class WebEventsSubfeature: NSObject, Subfeature {

    public typealias EventHandler = (_ type: String, _ loginState: LoginState) -> Void

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = "webEvents"
    public weak var broker: UserScriptMessageBroker?

    private let isUserOptedIn: () -> Bool
    private let onEvent: EventHandler

    /// Per-event-type kill switches live in the privacy config and are evaluated
    /// JS-side in content-scope-scripts before the message is sent, so the native
    /// side does not duplicate that check.
    /// - Parameters:
    ///   - isUserOptedIn: Composite gate covering YouTube Ad Blocking enabled
    ///     and analytics opt-in.
    ///   - onEvent: Platform pixel-firing closure invoked once the user-opt-in
    ///     gate passes.
    public init(
        isUserOptedIn: @escaping () -> Bool,
        onEvent: @escaping EventHandler
    ) {
        self.isUserOptedIn = isUserOptedIn
        self.onEvent = onEvent
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "webEvent" else { return nil }
        return { [weak self] params, _ in
            self?.handleWebEvent(params: params)
            return nil
        }
    }

    private func handleWebEvent(params: Any) {
        guard let payload = params as? [String: Any],
              let type = payload["type"] as? String else { return }

        guard isUserOptedIn() else { return }
        let raw = (payload["data"] as? [String: Any])?["loginState"] as? String
        let loginState = raw.flatMap(LoginState.init(rawValue:)) ?? .unknown
        onEvent(type, loginState)
    }
}
