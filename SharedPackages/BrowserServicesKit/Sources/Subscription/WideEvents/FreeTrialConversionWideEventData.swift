//
//  FreeTrialConversionWideEventData.swift
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
import Common
import PixelKit

public class FreeTrialConversionWideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "free_trial_conversion",
        featureName: "free-trial-conversion",
        mobileMetaType: "ios-free-trial-conversion",
        desktopMetaType: "macos-free-trial-conversion"
    )

    /// 8 days = 7-day trial + 1-day buffer
    public static let trialTimeout: TimeInterval = .days(8)

    // MARK: - Protocol Properties

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    // MARK: - Trial Data

    public var trialStartDate: Date

    // MARK: - Feature Activation (D1 = day 1, D2toD7 = days 2-7)

    public var vpnActivatedD1: Bool = false
    public var vpnActivatedD2ToD7: Bool = false

    public var pirActivatedD1: Bool = false
    public var pirActivatedD2ToD7: Bool = false

    private enum CodingKeys: String, CodingKey {
        case globalData, contextData, appData, errorData
        case trialStartDate
        case vpnActivatedD1, vpnActivatedD2ToD7
        case pirActivatedD1, pirActivatedD2ToD7
    }

    // MARK: - Init

    public init(trialStartDate: Date = Date(),
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.trialStartDate = trialStartDate
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    // MARK: - Completion Decision

    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            // Timeout fallback: if app launches after 8 days and flow wasn't completed, mark as unknown
            if Date() >= trialStartDate.addingTimeInterval(Self.trialTimeout) {
                return .complete(.unknown(reason: "timeout"))
            }
            return .keepPending
        }
    }
}

// MARK: - Update Helpers

extension FreeTrialConversionWideEventData {

    /// Whether the VPN activation pixel should be fired (i.e., VPN hasn't been activated yet)
    public var shouldFireVPNActivationPixel: Bool {
        !vpnActivatedD1 && !vpnActivatedD2ToD7
    }

    /// Whether the PIR activation pixel should be fired (i.e., PIR hasn't been activated yet)
    public var shouldFirePIRActivationPixel: Bool {
        !pirActivatedD1 && !pirActivatedD2ToD7
    }

    public func markVPNActivated() {
        guard shouldFireVPNActivationPixel else { return }
        if isDay1() {
            vpnActivatedD1 = true
        } else {
            vpnActivatedD2ToD7 = true
        }
    }

    public func markPIRActivated() {
        guard shouldFirePIRActivationPixel else { return }
        if isDay1() {
            pirActivatedD1 = true
        } else {
            pirActivatedD2ToD7 = true
        }
    }

    private func isDay1() -> Bool {
        let daysSinceStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        return daysSinceStart < 1
    }

    /// Returns the current activation day for pixel reporting
    public func activationDay() -> FreeTrialActivationDay {
        isDay1() ? .d1 : .d2ToD7
    }
}

// MARK: - Pixel Parameters

extension FreeTrialConversionWideEventData {

    public func pixelParameters() -> [String: String] {
        [
            WideEventParameter.FreeTrialConversionFeature.vpnActivatedD1: String(vpnActivatedD1),
            WideEventParameter.FreeTrialConversionFeature.vpnActivatedD2ToD7: String(vpnActivatedD2ToD7),
            WideEventParameter.FreeTrialConversionFeature.pirActivatedD1: String(pirActivatedD1),
            WideEventParameter.FreeTrialConversionFeature.pirActivatedD2ToD7: String(pirActivatedD2ToD7),
        ]
    }
}

// MARK: - Wide Event Parameters

extension WideEventParameter {

    public enum FreeTrialConversionFeature {
        static let vpnActivatedD1 = "feature.data.ext.step.vpn_activated_d1"
        static let vpnActivatedD2ToD7 = "feature.data.ext.step.vpn_activated_d2_to_d7"
        static let pirActivatedD1 = "feature.data.ext.step.pir_activated_d1"
        static let pirActivatedD2ToD7 = "feature.data.ext.step.pir_activated_d2_to_d7"
    }
}
