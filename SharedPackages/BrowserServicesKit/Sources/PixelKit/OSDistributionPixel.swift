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

/// Monthly pixels for deciding when to end support for an operating system version.
///
/// Tech design: https://app.asana.com/1/137249556945/project/1208546505108826/task/1214950124367783?focus=true
public struct OSDistributionPixel: PixelKitEvent {

    public enum Metric: String {
        case client
        case searches
        case activeSubscriptions = "active_subscriptions"
    }

    public enum Platform: String {
        case iOS = "ios"
        case macOS = "macos"
    }

    public enum FormFactor: String {
        case phone
        case tablet
        case desktop
    }

    private let metric: Metric
    private let osMajorVersion: Int
    private let platform: Platform
    private let formFactor: FormFactor

    public init(metric: Metric,
                osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                platform: Platform,
                formFactor: FormFactor) {
        self.metric = metric
        self.osMajorVersion = osMajorVersion
        self.platform = platform
        self.formFactor = formFactor
    }

    public var name: String {
        "os_distribution_\(metric.rawValue)_major_version_\(osMajorVersion)_\(platform.rawValue)_\(formFactor.rawValue)"
    }

    public var parameters: [String: String]? { nil }

    // No standard parameters: these pixels must not carry `pixelSource`.
    public var standardParameters: [PixelKitStandardParameter]? { [] }
}

public extension PixelKit {

    /// Fires an OS-distribution pixel with the fixed configuration these pixels require:
    /// `.monthly` frequency, no `appVersion`, no `pixelSource`, and no platform-prefix enforcement.
    /// (On macOS, `channel` is still added like every other macOS pixel; iOS does not send it.)
    func fireOSDistributionPixel(_ event: OSDistributionPixel) {
        fire(event,
             frequency: .monthly,
             includeAppVersionParameter: false,
             doNotEnforcePrefix: true)
    }

    /// Fires an OS-distribution pixel for the given metric, deriving `platform` and `formFactor`
    /// from the `source` configured at `setUp` (set per-context — app or extension — without UIKit).
    /// No-ops if the source is unknown/unset, so it is safe to call from any context.
    func fireOSDistributionPixel(metric: OSDistributionPixel.Metric) {
        let platform: OSDistributionPixel.Platform
        let formFactor: OSDistributionPixel.FormFactor
        switch source {
        case Source.iOS.rawValue:
            (platform, formFactor) = (.iOS, .phone)
        case Source.iPadOS.rawValue:
            (platform, formFactor) = (.iOS, .tablet)
        case Source.macStore.rawValue, Source.macDMG.rawValue:
            (platform, formFactor) = (.macOS, .desktop)
        default:
            return
        }
        fireOSDistributionPixel(OSDistributionPixel(metric: metric, platform: platform, formFactor: formFactor))
    }

    static func fireOSDistributionPixel(_ event: OSDistributionPixel) {
        shared?.fireOSDistributionPixel(event)
    }

    static func fireOSDistributionPixel(metric: OSDistributionPixel.Metric) {
        shared?.fireOSDistributionPixel(metric: metric)
    }
}
