//
//  BreakageReportData.swift
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

/// Data collected from breakage reporting subfeature including performance metrics and detector data
public struct BreakageReportData {
    public let performanceMetrics: PerformanceMetrics?
    public let detectorData: DetectorData?

    public init(performanceMetrics: PerformanceMetrics?, detectorData: DetectorData?) {
        self.performanceMetrics = performanceMetrics
        self.detectorData = detectorData
    }

    /// Convenience computed property for privacy-aware metrics conversion
    public var privacyAwarePerformanceMetrics: PrivacyAwarePerformanceMetrics? {
        return performanceMetrics?.privacyAwareMetrics()
    }
}
