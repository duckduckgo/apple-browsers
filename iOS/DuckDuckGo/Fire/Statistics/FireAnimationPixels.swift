//
//  FireAnimationPixels.swift
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

enum FireAnimationPixels: PixelKit.Event {
    case animationCompleted(scope: String, source: String, animation: String, burnInProgress: Bool)
    case burnOutlastedAnimation(scope: String, source: String, animation: String)
    case burnCompletedAfterAnimation(scope: String, source: String, animation: String, elapsed: DataClearingPixels.ElapsedBucket)

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var name: String {
        switch self {
        case .animationCompleted:
            return "fire_animation-completed"
        case .burnOutlastedAnimation:
            return "fire_burn-outlasted-animation"
        case .burnCompletedAfterAnimation:
            return "fire_post-animation-burn-completed"
        }
    }

    var parameters: [String: String]? {
        let scope: String
        let source: String
        let animation: String
        var parameters: [String: String] = [:]
        switch self {
        case .animationCompleted(let eventScope, let eventSource, let eventAnimation, let burnInProgress):
            (scope, source, animation) = (eventScope, eventSource, eventAnimation)
            parameters["burn_in_progress"] = String(burnInProgress)
        case .burnOutlastedAnimation(let eventScope, let eventSource, let eventAnimation):
            (scope, source, animation) = (eventScope, eventSource, eventAnimation)
        case .burnCompletedAfterAnimation(let eventScope, let eventSource, let eventAnimation, let elapsed):
            (scope, source, animation) = (eventScope, eventSource, eventAnimation)
            parameters["elapsed"] = elapsed.rawValue
        }
        parameters["scope"] = scope
        parameters["source"] = source
        parameters["animation"] = animation
        return parameters
    }
}
