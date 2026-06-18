//
//  OSDistributionPixel.swift
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

/// Pixels for deciding when to end support for an operating system version.
///
/// `.client` and `.activeSubscriptions` fire at most once per calendar month (monthly-active
/// users / subscribers); `.searches` fires on every search or AI query, since the EOL policy's
/// "low monthly search traffic" metric counts total search + AI-query *traffic*, not active users.
///
/// Tech design: https://app.asana.com/1/137249556945/project/1208546505108826/task/1214950124367783?focus=true
public struct OSDistributionPixel: PixelKitEvent {

    public enum Metric: String {
        case client
        case searches
        case activeSubscriptions = "active_subscriptions"
    }

    private let metric: Metric
    private let osMajorVersion: Int
    private let platform: DevicePlatform
    private let formFactor: String

    public init(metric: Metric,
                osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                platform: DevicePlatform,
                formFactor: String) {
        self.metric = metric
        self.osMajorVersion = osMajorVersion
        self.platform = platform
        self.formFactor = formFactor
    }

    public var name: String {
        "os_distribution_\(metric.rawValue)_major_version_\(osMajorVersion)_\(platform.rawValue.lowercased())_\(formFactor)"
    }

    /// Per-metric firing frequency. `.searches` measures total search + AI-query traffic so it fires
    /// on every event; `.client` and `.activeSubscriptions` measure monthly-active users / subscribers.
    var frequency: PixelKit.Frequency {
        switch metric {
        case .searches: return .standard
        case .client, .activeSubscriptions: return .monthly
        }
    }

    // Self-tags the pixel to route through the PETAL (timestamp-randomization) pipeline.
    public var parameters: [String: String]? { ["petal": "randomize"] }

    // No standard parameters
    public var standardParameters: [PixelKitStandardParameter]? { [] }
}

public extension PixelKit {

    /// Fires an OS-distribution pixel with the fixed configuration these pixels require:
    /// the metric's `frequency` (see `OSDistributionPixel.frequency`), no `appVersion`,
    /// no `pixelSource`, and no platform-prefix enforcement.
    func fireOSDistributionPixel(_ event: OSDistributionPixel) {
        fire(event,
             frequency: event.frequency,
             includeAppVersionParameter: false,
             doNotEnforcePrefix: true)
    }

    func fireOSDistributionPixel(metric: OSDistributionPixel.Metric,
                                 platform: DevicePlatform = .currentPlatform,
                                 formFactor: String = DevicePlatform.formFactor) {
        fireOSDistributionPixel(OSDistributionPixel(metric: metric,
                                                    platform: platform,
                                                    formFactor: formFactor))
    }

    static func fireOSDistributionPixel(metric: OSDistributionPixel.Metric) {
        shared?.fireOSDistributionPixel(metric: metric)
    }
}
