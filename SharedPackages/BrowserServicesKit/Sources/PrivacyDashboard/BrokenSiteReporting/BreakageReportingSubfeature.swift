//
//  BreakageReportingSubfeature.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import UserScript
import WebKit

public class BreakageReportingSubfeature: Subfeature {

    public var messageOriginPolicy: MessageOriginPolicy = .all
    public var featureName: String = "breakageReporting"
    public weak var broker: UserScriptMessageBroker?

    private weak var targetWebview: WKWebView?
    private var timer: Timer?
    private var completionHandler: ((PerformanceMetrics?) -> Void)?
    private var currentPerformanceMetrics: PerformanceMetrics?

    public init(targetWebview: WKWebView) {
        self.targetWebview = targetWebview
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "breakageReportResult" else { return nil }

        return vitalsResult
    }

    public func vitalsResult(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        timer?.invalidate()
        guard let payload = params as? [String: Any],
              let expandedMetrics = payload["expandedPerformanceMetrics"] as? [String: Any] else {
            completionHandler?(nil)
            return nil
        }

        // Parse expanded performance metrics from payload
        let performanceMetrics = PerformanceMetrics(from: expandedMetrics)
        self.currentPerformanceMetrics = performanceMetrics
        completionHandler?(performanceMetrics)
        return nil
    }

    public func notifyHandler(completion: @escaping (PerformanceMetrics?) -> Void) {
        guard let broker, let targetWebview else { completion(nil); return }

        completionHandler = completion
        broker.push(method: "getBreakageReportValues", params: nil, for: self, into: targetWebview)

        // On the chance C-S-S doesn't respond to our message, set a timer
        // to continue the process since the breakage report blocks on this.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    private func handleTimeout() {
        if let completionHandler {
            self.completionHandler = nil
            completionHandler(nil)
        }
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func getExpandedPerformanceMetrics() -> PerformanceMetrics? {
        return currentPerformanceMetrics
    }

    public func getExpandedPerformanceMetricsDictionary() -> [String: Any]? {
        guard let metrics = currentPerformanceMetrics else { return nil }

        // Convert PerformanceMetrics back to dictionary
        var expandedMetrics: [String: Any] = [:]

        if let fcp = metrics.firstContentfulPaint {
            expandedMetrics["firstContentfulPaint"] = fcp
        }
        if let lcp = metrics.largestContentfulPaint {
            expandedMetrics["largestContentfulPaint"] = lcp
        }
        if let ttfb = metrics.timeToFirstByte {
            expandedMetrics["timeToFirstByte"] = ttfb
        }
        if let loadComplete = metrics.loadComplete {
            expandedMetrics["loadComplete"] = loadComplete
        }
        if let transferSize = metrics.transferSize {
            expandedMetrics["transferSize"] = transferSize
        }
        if let decodedBodySize = metrics.decodedBodySize {
            expandedMetrics["decodedBodySize"] = decodedBodySize
        }
        if let encodedBodySize = metrics.encodedBodySize {
            expandedMetrics["encodedBodySize"] = encodedBodySize
        }
        if let resourceCount = metrics.resourceCount {
            expandedMetrics["resourceCount"] = resourceCount
        }
        if let totalResourcesSize = metrics.totalResourcesSize {
            expandedMetrics["totalResourcesSize"] = totalResourcesSize
        }
        if let networkProtocol = metrics.networkProtocol {
            expandedMetrics["protocol"] = networkProtocol
        }
        if let serverTime = metrics.serverTime {
            expandedMetrics["serverTime"] = serverTime
        }
        if let responseTime = metrics.responseTime {
            expandedMetrics["responseTime"] = responseTime
        }
        if let domInteractive = metrics.domInteractive {
            expandedMetrics["domInteractive"] = domInteractive
        }
        if let domComplete = metrics.domComplete {
            expandedMetrics["domComplete"] = domComplete
        }
        if let domContentLoaded = metrics.domContentLoaded {
            expandedMetrics["domContentLoaded"] = domContentLoaded
        }
        if let navigationType = metrics.navigationType {
            expandedMetrics["navigationType"] = navigationType
        }
        if let redirectCount = metrics.redirectCount {
            expandedMetrics["redirectCount"] = redirectCount
        }

        return expandedMetrics
    }
}
