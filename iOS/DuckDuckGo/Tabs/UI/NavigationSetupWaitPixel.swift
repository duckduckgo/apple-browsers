//
//  NavigationSetupWaitPixel.swift
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

import Core
import Foundation
import PixelKit

/// How long the first foreground navigation waited for setup, and how much each setup stage added.
enum NavigationSetupWaitPixel: PixelKit.Event {

    case finished(outcome: RulesCompilationMonitor.Outcome,
                  waitTime: Pixel.Event.BucketAggregation,
                  webExtensionsWait: Pixel.Event.BucketAggregation,
                  contentBlockingWait: Pixel.Event.BucketAggregation,
                  isOnboarding: Bool)

    var name: String {
        "navigation_setup_wait"
    }

    var parameters: [String: String]? {
        switch self {
        case .finished(let outcome, let waitTime, let webExtensionsWait, let contentBlockingWait, let isOnboarding):
            return [
                "outcome": outcome.rawValue,
                "state": isOnboarding ? "onboarding" : "regular",
                "wait_time": waitTime.rawValue,
                "web_extensions_wait_time": webExtensionsWait.rawValue,
                "content_blocking_wait_time": contentBlockingWait.rawValue,
            ]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
