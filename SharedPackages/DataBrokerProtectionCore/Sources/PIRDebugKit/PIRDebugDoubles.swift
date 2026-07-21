//
//  PIRDebugDoubles.swift
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
import DataBrokerProtectionCore

/// A no-op `DBPFeatureFlagging` used by PIRDebugKit so runners can be constructed without the
/// app's feature-flag stack. Remote broker delivery is reported off (PIRDebugKit fetches rules
/// itself), and all other flags default off.
public struct PIRDebugFeatureFlagger: DBPFeatureFlagging {
    public let isRemoteBrokerDeliveryFeatureOn: Bool
    public let isForegroundRunningOnAppActiveFeatureOn: Bool
    public let isContinuedProcessingFeatureOn: Bool
    public let isWebViewUserAgentOn: Bool
    public let isOptOutRetryErrorFrequencyExperimentOn: Bool

    public init(isRemoteBrokerDeliveryFeatureOn: Bool = false,
                isForegroundRunningOnAppActiveFeatureOn: Bool = false,
                isContinuedProcessingFeatureOn: Bool = false,
                isWebViewUserAgentOn: Bool = false,
                isOptOutRetryErrorFrequencyExperimentOn: Bool = false) {
        self.isRemoteBrokerDeliveryFeatureOn = isRemoteBrokerDeliveryFeatureOn
        self.isForegroundRunningOnAppActiveFeatureOn = isForegroundRunningOnAppActiveFeatureOn
        self.isContinuedProcessingFeatureOn = isContinuedProcessingFeatureOn
        self.isWebViewUserAgentOn = isWebViewUserAgentOn
        self.isOptOutRetryErrorFrequencyExperimentOn = isOptOutRetryErrorFrequencyExperimentOn
    }
}

public enum PIRDebugPixels {
    /// A pixel handler that logs to stderr instead of firing real pixels (mirrors the debug
    /// window's `fakePixelHandler`). No network, no `PixelKit.shared`.
    public static func stderrLoggingPixelHandler() -> EventMapping<DataBrokerProtectionSharedPixels> {
        EventMapping<DataBrokerProtectionSharedPixels> { event, _, _, _ in
            FileHandle.standardError.write(Data("[pixel] \(String(describing: event))\n".utf8))
        }
    }
}
