//
//  AssistedOptOutPixelInstrumentation.swift
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

import DataBrokerProtectionCore
import Foundation
import PixelKit

@MainActor
final class AssistedOptOutPixelInstrumentation: AssistedOptOutInstrumentation {
    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func started() {
        pixelFiring?.fire(AssistedOptOutPixel.started, frequency: .standard)
    }

    func reachedUserTurn(after duration: TimeInterval) {
        pixelFiring?.fire(AssistedOptOutPixel.userTurn(durationBucket: bucket(duration)), frequency: .standard)
    }

    func ended(outcome: AssistedOptOutOutcome, totalDuration: TimeInterval, userTurnDuration: TimeInterval) {
        pixelFiring?.fire(AssistedOptOutPixel.ended(
            outcome: outcome, totalDurationBucket: bucket(totalDuration), userTurnDurationBucket: bucket(userTurnDuration)), frequency: .standard)
    }

    private func bucket(_ duration: TimeInterval) -> String {
        switch duration {
        case ..<30: return "0"
        case ..<60: return "30"
        case ..<120: return "60"
        case ..<240: return "120"
        case ..<480: return "240"
        default: return "480"
        }
    }
}

enum AssistedOptOutPixel: PixelKit.Event {
    case started
    case userTurn(durationBucket: String)
    case ended(outcome: AssistedOptOutOutcome, totalDurationBucket: String, userTurnDurationBucket: String)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .started: return "pir_assisted_opt_out_started_macos"
        case .userTurn: return "pir_assisted_opt_out_user_turn_macos"
        case .ended: return "pir_assisted_opt_out_ended_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .started:
            return [:]
        case .userTurn(let durationBucket):
            return ["duration_seconds_bucket": durationBucket]
        case .ended(let outcome, let totalDurationBucket, let userTurnDurationBucket):
            return ["outcome": outcome.rawValue, "total_duration_seconds_bucket": totalDurationBucket,
                    "user_turn_duration_seconds_bucket": userTurnDurationBucket]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { [] }
}
