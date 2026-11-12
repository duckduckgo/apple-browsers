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
        pixelFiring?.fire(DataBrokerProtectionMacOSPixels.assistedOptOutStarted, frequency: .standard)
    }

    func reachedUserTurn(after duration: TimeInterval) {
        pixelFiring?.fire(DataBrokerProtectionMacOSPixels.assistedOptOutUserTurn(durationBucket: bucket(duration)), frequency: .standard)
    }

    func ended(outcome: AssistedOptOutOutcome, totalDuration: TimeInterval, userTurnDuration: TimeInterval) {
        pixelFiring?.fire(DataBrokerProtectionMacOSPixels.assistedOptOutEnded(
            outcome: outcome, totalDurationBucket: bucket(totalDuration), userTurnDurationBucket: bucket(userTurnDuration)), frequency: .standard)
    }

    private func bucket(_ duration: TimeInterval) -> String {
        switch duration {
        case ..<1: return "under_1s"
        case ..<5: return "1_5s"
        case ..<15: return "5_15s"
        case ..<30: return "15_30s"
        case ..<60: return "30_60s"
        case ..<120: return "1_2m"
        case ..<300: return "2_5m"
        case ..<600: return "5_10m"
        default: return "10m_or_more"
        }
    }
}
