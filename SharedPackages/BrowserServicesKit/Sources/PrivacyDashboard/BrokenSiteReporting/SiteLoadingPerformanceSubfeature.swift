//
//  SiteLoadingPerformanceSubfeature.swift
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
import UserScript
import WebKit

/// Listens for the `expandedPerformanceMetricsResult` push from the content-scope-scripts
/// `performanceMetrics` JS feature (sent on every page load) and fires the sampled
/// `site_loading_performance` pixel.
///
/// `featureName` is `"performanceMetrics"` to match the CSS JS feature so the messaging
/// broker routes pushes to this delegate. This subfeature is intentionally narrow: it only
/// handles the push that fires the sampled pixel. The broken-site-report path goes through
/// `BreakageReportingSubfeature` instead.
public final class SiteLoadingPerformanceSubfeature: Subfeature {

    public var messageOriginPolicy: MessageOriginPolicy = .all
    public var featureName: String = "performanceMetrics"
    public weak var broker: UserScriptMessageBroker?

    private let samplePercentage: Int
    private let pixelFire: (PixelKitEvent, PixelKit.Frequency) -> Void

    public init(samplePercentage: Int = 2,
                pixelFire: @escaping (PixelKitEvent, PixelKit.Frequency) -> Void = { event, frequency in
                    PixelKit.fire(event, frequency: frequency)
                }) {
        self.samplePercentage = samplePercentage
        self.pixelFire = pixelFire
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "expandedPerformanceMetricsResult" else { return nil }
        return expandedPerformanceMetricsResult
    }

    public func expandedPerformanceMetricsResult(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload = params as? [String: Any],
              let metrics = payload["metrics"] as? [String: Any] else {
            return nil
        }

        let rawMetrics = PerformanceMetrics(from: metrics)
        let privacyAwareMetrics = rawMetrics.privacyAwareMetrics()
        let pixel = SiteLoadingPerformancePixel.performanceMetricsReceived(metrics: privacyAwareMetrics)
        pixelFire(pixel, .sample(percentage: samplePercentage))
        return nil
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }
}
