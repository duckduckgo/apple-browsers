//
//  SubscriptionTokenRefreshPixel.swift
//  DuckDuckGo
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
import Subscription

/// Reports a run of the background token refresh: what started it and how it ended.
enum SubscriptionTokenRefreshPixel: PixelKit.Event {

    /// How a run ended.
    enum Result: String {
        case refreshed
        case notDue = "not_due"
        case noToken = "no_token"
        case failed
        /// iOS expired the background task before the run finished.
        case expired
    }

    /// A finished run.
    /// - Parameters:
    ///   - trigger: What started the run.
    ///   - result: How it ended.
    case run(trigger: SubscriptionTokenRefreshRun.Trigger, result: Result)

    /// The pixel for a finished run, or nil when the run isn't reported.
    /// Every background task run and every refresh attempt is reported. A disabled run, and a foreground, sign-in or debug run that
    /// found nothing to refresh, are not.
    /// - Parameters:
    ///   - trigger: What started the run.
    ///   - outcome: The keep-alive outcome.
    static func run(trigger: SubscriptionTokenRefreshRun.Trigger, outcome: SubscriptionTokenKeepAlive.Outcome) -> Self? {
        let result: Result
        switch outcome {
        case .disabled: return nil
        case .refreshed: result = .refreshed
        case .failed: result = .failed
        case .notDue: result = .notDue
        case .noToken: result = .noToken
        }
        guard trigger == .backgroundTask || result == .refreshed || result == .failed else { return nil }
        return .run(trigger: trigger, result: result)
    }

    private static let triggerKey = "trigger"
    private static let resultKey = "result"

    var name: String {
        switch self {
        case .run: return "subscription_auth-background-refresh_run"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .run(let trigger, let result):
            return [Self.triggerKey: trigger.pixelValue, Self.resultKey: result.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }
}

private extension SubscriptionTokenRefreshRun.Trigger {

    var pixelValue: String {
        switch self {
        case .foreground: return "foreground"
        case .signIn: return "sign_in"
        case .backgroundTask: return "background_task"
        case .debugMenu: return "debug_menu"
        }
    }
}
