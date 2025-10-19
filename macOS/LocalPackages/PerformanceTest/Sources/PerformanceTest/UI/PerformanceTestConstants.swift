//
//  PerformanceTestConstants.swift
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

enum PerformanceTestConstants {

    // MARK: - Window Configuration
    static let windowWidth: CGFloat = 680
    static let windowHeight: CGFloat = 650
    static let windowTitle = "Site Performance Test"
    static let windowAutosaveName = "PerformanceTest"

    // MARK: - UI Strings
    enum Strings {
        static let testSitePerformance = "Test Site Performance"
        static let testing = "Testing:"
        static let noActivePageToTest = "No active page to test"
        static let testConfiguration = "Test Configuration"
        static let startTest = "Start Test"
        static let stopTest = "Stop Test"
        static let testAgain = "Test Again"
        static let testingInProgress = "Testing Site Performance"
        static let testDetails = "Test Details"
        static let statisticalView = "Statistical View:"
        static let performanceTestInProgress = "Performance Test in Progress"
        static let pleaseWait = "Please wait..."
        static let warmingUp = "Warming up..."

        // Metric titles
        static let loadComplete = "Load Complete"
        static let domComplete = "DOM Complete"
        static let domContentLoaded = "DOM Content Loaded"
        static let domInteractive = "DOM Interactive"
        static let fcp = "FCP"
        static let ttfb = "TTFB"
        static let responseTime = "Response Time"
        static let serverTime = "Server Time"
        static let transferSize = "Transfer Size"
        static let decodedBodySize = "Decoded Body Size"
        static let encodedBodySize = "Encoded Body Size"
        static let resourceCount = "Resource Count"

        // Test result labels
        static let totalTests = "Total Tests:"
        static let consistency = "Consistency:"
        static let p95ToP50Ratio = "P95/P50 Ratio:"
        static let analysis = "Analysis:"
        static let failed = "Failed:"

        // Picker options
        static let medianRecommended = "Median (Recommended)"
        static let p95Percentile = "P95 (95th Percentile)"
        static let meanAverage = "Mean (Average)"
        static let minBestCase = "Min (Best Case)"
        static let maxWorstCase = "Max (Worst Case)"
    }

    // MARK: - SF Symbols
    enum Icons {
        static let speedometer = "speedometer"
        static let play = "play.fill"
        static let clockwise = "arrow.clockwise"
        static let checkmarkCircle = "checkmark.circle"
        static let docText = "doc.text"
        static let docRichtext = "doc.richtext"
        static let handTap = "hand.tap"
        static let paintbrush = "paintbrush"
        static let network = "network"
        static let arrowLeftArrowRight = "arrow.left.arrow.right"
        static let serverRack = "server.rack"
        static let arrowDownDoc = "arrow.down.doc"
        static let docPlaintext = "doc.plaintext"
        static let docZipper = "doc.zipper"
        static let folder = "folder"
        static let exclamationTriangle = "exclamationmark.triangle.fill"
    }

    // MARK: - Layout Constants
    enum Layout {
        static let mainSpacing: CGFloat = 24
        static let sectionSpacing: CGFloat = 16
        static let itemSpacing: CGFloat = 12
        static let smallSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 12
        static let smallCornerRadius: CGFloat = 8
        static let progressBarHeight: CGFloat = 8
        static let logoSize: CGFloat = 24
        static let overlayAlpha: CGFloat = 0.7

        // Padding
        static let standardPadding: CGFloat = 16
        static let largePadding: CGFloat = 40
        static let horizontalPadding: CGFloat = 100

        // Widths
        static let buttonWidth: CGFloat = 200
        static let progressWidth: CGFloat = 300
        static let pickerWidth: CGFloat = 200
        static let metricValueWidth: CGFloat = 120
        static let overlayMessageWidth: CGFloat = 400
    }

    // MARK: - Test Configuration
    enum TestConfig {
        static let availableIterations = [1, 5, 10, 15, 20, 30, 50]
        static let defaultIterations = 10
        static let testTimeout: TimeInterval = 120.0  // 2 minutes for very large pages (specs, documentation)
        static let checkInterval: TimeInterval = 0.5
        static let warmupDelay: UInt64 = 500_000_000 // 500ms in nanoseconds
    }

    // MARK: - Statistical Views
    enum StatViews {
        static let median = "median"
        static let p95 = "p95"
        static let mean = "mean"
        static let min = "min"
        static let max = "max"
        static let stdDev = "stdDev"  // Deprecated - use iqr instead
        static let iqr = "iqr"  // Interquartile Range - robust measure of spread
        static let cv = "cv"
    }

    // MARK: - Quality Thresholds
    enum Thresholds {
        // Core Web Vitals (seconds)
        static let goodLCP: TimeInterval = 2.5
        static let poorLCP: TimeInterval = 4.0

        // CV (Coefficient of Variation) percentages
        static let excellentCV: Double = 10
        static let goodCV: Double = 20
        static let fairCV: Double = 40

        // Normalization ranges
        static let maxTimeForProgress: Double = 5000 // ms
        static let maxSizeForProgress: Double = 10000 // KB
        static let maxCountForProgress: Double = 200
    }
}
