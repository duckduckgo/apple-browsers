//
//  BreakageReportingSubfeature.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
    private var completionHandler: ((PerformanceMetrics?, DetectorData?, [Double]?) -> Void)?
    private var currentPerformanceMetrics: PerformanceMetrics?

    public init(targetWebview: WKWebView) {
        self.targetWebview = targetWebview
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "breakageReportResult" else { return nil }

        return breakageReportResult
    }

    public func breakageReportResult(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        timer?.invalidate()
        guard let payload = params as? [String: Any],
              let expandedMetrics = payload["expandedPerformanceMetrics"] as? [String: Any] else {
            completionHandler?(nil, nil, nil)
            return nil
        }

        // Parse expanded performance metrics from payload
        let performanceMetrics = PerformanceMetrics(from: expandedMetrics)
        self.currentPerformanceMetrics = performanceMetrics

        // Parse detector data from payload if present
        let detectorData: DetectorData?
        if let detectorDataDict = payload["detectorData"] as? [String: Any] {
            detectorData = DetectorData(from: detectorDataDict)
        } else {
            detectorData = nil
        }

        let jsPerformanceMetrics: [Double]?
        if let jsPerformance = payload["jsPerformance"] as? [Double] {
            jsPerformanceMetrics = jsPerformance
        } else {
            jsPerformanceMetrics = nil
        }

        completionHandler?(performanceMetrics, detectorData, jsPerformanceMetrics)
        return nil
    }

    public func notifyHandler(completion: @escaping (PerformanceMetrics?, DetectorData?, [Double]?) -> Void) {
        guard let broker, let targetWebview else { completion(nil, nil, nil); return }

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
            completionHandler(nil, nil, nil)
        }
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func getExpandedPerformanceMetrics() -> PerformanceMetrics? {
        return currentPerformanceMetrics
    }

}
