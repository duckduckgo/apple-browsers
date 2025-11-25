//
//  PerformanceTestWindowView.swift
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

import SwiftUI

struct PerformanceTestWindowView: View {
    @ObservedObject var viewModel: PerformanceTestViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let comparison = viewModel.comparisonResults {
                comparisonResultsView(comparison)
            } else if viewModel.isRunning {
                progressView
            } else {
                startView
            }
        }
        .frame(width: PerformanceTestConstants.windowWidth, height: PerformanceTestConstants.windowHeight)
    }

    // MARK: - Start View

    private var startView: some View {
        VStack(spacing: PerformanceTestConstants.Layout.mainSpacing) {
            Spacer()

            startViewHeader
            currentURLSection

            if let errorMessage = viewModel.errorMessage {
                errorMessageView(errorMessage)
            }

            maxIterationsPicker
            startTestButton

            Spacer()
        }
        .padding()
        .padding(.horizontal, PerformanceTestConstants.Layout.horizontalPadding)
    }

    private var startViewHeader: some View {
        VStack(spacing: PerformanceTestConstants.Layout.itemSpacing) {
            Image(systemName: PerformanceTestConstants.Icons.speedometer)
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text(PerformanceTestConstants.Strings.testSitePerformance)
                .font(.largeTitle)
                .fontWeight(.semibold)
        }
    }

    private var currentURLSection: some View {
        Group {
            if let url = viewModel.currentURL {
                VStack(spacing: PerformanceTestConstants.Layout.smallSpacing) {
                    Text(PerformanceTestConstants.Strings.testing)
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(url.absoluteString)
                        .font(.system(.title2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                }
                .multilineTextAlignment(.center)
            } else {
                Text(PerformanceTestConstants.Strings.noActivePageToTest)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var maxIterationsPicker: some View {
        HStack {
            Text("Max Iterations:")
                .font(.body)
                .foregroundColor(.secondary)
            Picker("", selection: $viewModel.maxIterations) {
                Text("10").tag(10)
                Text("15").tag(15)
                Text("20").tag(20)
                Text("25").tag(25)
                Text("30").tag(30)
                Text("35").tag(35)
                Text("40").tag(40)
                Text("45").tag(45)
                Text("50").tag(50)
            }
            .pickerStyle(.menu)
            .frame(width: 100)
        }
    }

    private var startTestButton: some View {
        Button(action: {
            Task {
                await viewModel.runTest()
            }
        }) {
            Label(PerformanceTestConstants.Strings.startTest, systemImage: PerformanceTestConstants.Icons.play)
                .frame(width: PerformanceTestConstants.Layout.buttonWidth)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.currentURL == nil)
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: PerformanceTestConstants.Layout.mainSpacing) {
            progressViewHeader
            browserProgressIndicator

            if let errorMessage = viewModel.errorMessage {
                errorMessageView(errorMessage)
            }

            progressStatusText
            progressIterationText
            stopTestButton
        }
        .padding(PerformanceTestConstants.Layout.largePadding)
    }

    private var progressViewHeader: some View {
        Text(PerformanceTestConstants.Strings.testingInProgress)
            .font(.title)
            .fontWeight(.semibold)
    }

    private var browserProgressIndicator: some View {
        Group {
            if !viewModel.currentBrowser.isEmpty {
                HStack(spacing: 8) {
                    Text("Testing \(viewModel.currentBrowser)")
                        .font(.headline)

                    if !viewModel.browserProgress.isEmpty {
                        Text("(\(viewModel.browserProgress))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
        }
    }

    private var progressBar: some View {
        ProgressView(value: viewModel.progress)
            .progressViewStyle(LinearProgressViewStyle())
            .frame(width: PerformanceTestConstants.Layout.progressWidth)
    }

    private var progressStatusText: some View {
        Text(viewModel.statusText)
            .font(.headline)
            .foregroundColor(.secondary)
    }

    private var progressIterationText: some View {
        Text("Iteration \(viewModel.currentIteration)")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var stopTestButton: some View {
        Button(PerformanceTestConstants.Strings.stopTest) {
            viewModel.cancelTest()
        }
        .buttonStyle(.bordered)
    }

    private func errorMessageView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)

            Text(message)
                .font(.callout)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Comparison Results View

    private func comparisonResultsView(_ comparison: BrowserComparisonResults) -> some View {
        ScrollView {
            VStack(spacing: PerformanceTestConstants.Layout.mainSpacing) {
                comparisonHeader(comparison)
                comparisonMetricsGrid(comparison)
                comparisonDetailsSection(comparison)
                actionButtonsSection
            }
            .padding()
        }
    }

    private func comparisonHeader(_ comparison: BrowserComparisonResults) -> some View {
        VStack(spacing: PerformanceTestConstants.Layout.itemSpacing) {
            Text(comparison.url.absoluteString)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Browser Comparison")
                .font(.caption)
                .foregroundColor(.secondary)

            statisticalViewPicker
            statisticalViewDescription
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(PerformanceTestConstants.Layout.cornerRadius)
    }

    private func comparisonMetricsGrid(_ comparison: BrowserComparisonResults) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PerformanceTestConstants.Layout.sectionSpacing) {
            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.loadComplete,
                icon: PerformanceTestConstants.Icons.checkmarkCircle,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.loadComplete,
                safariValues: comparison.safariResults.detailedMetrics.loadComplete,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.domComplete,
                icon: PerformanceTestConstants.Icons.docText,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.domComplete,
                safariValues: comparison.safariResults.detailedMetrics.domComplete,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.domContentLoaded,
                icon: PerformanceTestConstants.Icons.docRichtext,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.domContentLoaded,
                safariValues: comparison.safariResults.detailedMetrics.domContentLoaded,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.domInteractive,
                icon: PerformanceTestConstants.Icons.handTap,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.domInteractive,
                safariValues: comparison.safariResults.detailedMetrics.domInteractive,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.fcp,
                icon: PerformanceTestConstants.Icons.paintbrush,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.fcp,
                safariValues: comparison.safariResults.detailedMetrics.fcp,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.ttfb,
                icon: PerformanceTestConstants.Icons.network,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.ttfb,
                safariValues: comparison.safariResults.detailedMetrics.ttfb,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.responseTime,
                icon: PerformanceTestConstants.Icons.arrowLeftArrowRight,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.responseTime,
                safariValues: comparison.safariResults.detailedMetrics.responseTime,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.serverTime,
                icon: PerformanceTestConstants.Icons.serverRack,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.serverTime,
                safariValues: comparison.safariResults.detailedMetrics.serverTime,
                comparison: comparison,
                isTime: true
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.transferSize,
                icon: PerformanceTestConstants.Icons.arrowDownDoc,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.transferSize,
                safariValues: comparison.safariResults.detailedMetrics.transferSize,
                comparison: comparison,
                isTime: false
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.decodedBodySize,
                icon: PerformanceTestConstants.Icons.docPlaintext,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.decodedBodySize,
                safariValues: comparison.safariResults.detailedMetrics.decodedBodySize,
                comparison: comparison,
                isTime: false
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.encodedBodySize,
                icon: PerformanceTestConstants.Icons.docZipper,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.encodedBodySize,
                safariValues: comparison.safariResults.detailedMetrics.encodedBodySize,
                comparison: comparison,
                isTime: false
            )

            comparisonMetricBox(
                title: PerformanceTestConstants.Strings.resourceCount,
                icon: PerformanceTestConstants.Icons.folder,
                ddgValues: comparison.duckDuckGoResults.detailedMetrics.resourceCount.map { Double($0) },
                safariValues: comparison.safariResults.detailedMetrics.resourceCount.map { Double($0) },
                comparison: comparison,
                isTime: false
            )
        }
    }

    private func comparisonMetricBox(
        title: String,
        icon: String,
        ddgValues: [Double],
        safariValues: [Double],
        comparison: BrowserComparisonResults,
        isTime: Bool
    ) -> some View {
        Group {
            if let ddgValue = getMetricStatValue(ddgValues, viewModel.selectedStatView),
               let ddgIQR = getMetricStatValue(ddgValues, PerformanceTestConstants.StatViews.iqr),
               let safariValue = getMetricStatValue(safariValues, viewModel.selectedStatView),
               let safariIQR = getMetricStatValue(safariValues, PerformanceTestConstants.StatViews.iqr) {

                let percentDiff = comparison.percentageDifference(ddgValue, safariValue)
                let winner = isTime ? comparison.timeBasedWinner(ddgValue, safariValue, ddgStdDev: ddgIQR, safariStdDev: safariIQR) : comparison.sizeBasedWinner(ddgValue, safariValue, ddgStdDev: ddgIQR, safariStdDev: safariIQR)

                ComparisonMetricBox(
                    title: title,
                    icon: icon,
                    duckduckgoValue: formatMetricValue(ddgValue, isTime: isTime),
                    duckduckgoStdDev: formatMetricValue(ddgIQR / 2.0, isTime: isTime),  // Display IQR/2 as spread around median
                    safariValue: formatMetricValue(safariValue, isTime: isTime),
                    safariStdDev: formatMetricValue(safariIQR / 2.0, isTime: isTime),  // Display IQR/2 as spread around median
                    percentageDiff: percentDiff,
                    winner: winner
                )
            }
        }
    }

    private func comparisonDetailsSection(_ comparison: BrowserComparisonResults) -> some View {
        VStack(alignment: .leading, spacing: PerformanceTestConstants.Layout.sectionSpacing) {
            // Test Statistics
            HStack(spacing: PerformanceTestConstants.Layout.sectionSpacing) {
                // DuckDuckGo stats
                VStack(alignment: .leading, spacing: PerformanceTestConstants.Layout.itemSpacing) {
                    Text("DuckDuckGo Statistics")
                        .font(.headline)

                    VStack(spacing: PerformanceTestConstants.Layout.smallSpacing) {
                        statRow("Total Tests", "\(comparison.duckDuckGoResults.iterations)")
                        statRow("Consistency", comparison.duckDuckGoResults.reliabilityScore,
                               color: reliabilityColor(comparison.duckDuckGoResults.reliabilityScore))
                        if let ratio = comparison.duckDuckGoResults.p95ToP50Ratio {
                            statRow("P95/P50 Ratio", String(format: "%.1fx", ratio))
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(PerformanceTestConstants.Layout.smallCornerRadius)
                .frame(maxWidth: .infinity)

                // Safari stats
                VStack(alignment: .leading, spacing: PerformanceTestConstants.Layout.itemSpacing) {
                    Text("Safari Statistics")
                        .font(.headline)

                    VStack(spacing: PerformanceTestConstants.Layout.smallSpacing) {
                        statRow("Total Tests", "\(comparison.safariResults.iterations)")
                        statRow("Consistency", comparison.safariResults.reliabilityScore,
                               color: reliabilityColor(comparison.safariResults.reliabilityScore))
                        if let ratio = comparison.safariResults.p95ToP50Ratio {
                            statRow("P95/P50 Ratio", String(format: "%.1fx", ratio))
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(PerformanceTestConstants.Layout.smallCornerRadius)
                .frame(maxWidth: .infinity)
            }

            // Statistical Significance Note
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Statistical Significance")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Text("Tests use adaptive iterations (minimum 10, maximum 30) to ensure statistical reliability. Testing stops early when results are consistent (IQR/median < 20%), or continues to improve accuracy if variance is high. The first warm-up iteration is excluded, and outliers are filtered using the IQR method (values outside Q1 - 1.5×IQR to Q3 + 1.5×IQR are removed) to eliminate network hiccups and focus on typical site performance. Metrics use the median (50th percentile) from the filtered data as the primary measure. The uncertainty shown (±) is the Interquartile Range (IQR/2), representing the middle 50% spread—lower values indicate more consistent performance. Statistical significance is determined by comparing whether the performance difference exceeds the combined IQR values. When the difference is smaller than this threshold, results are marked as \"Not statistically significant,\" indicating the browsers performed essentially the same.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(PerformanceTestConstants.Layout.smallCornerRadius)
        }
    }

    private func statRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // MARK: - Results View

    private func resultsView(_ results: PerformanceTestResults) -> some View {
        ScrollView {
            VStack(spacing: PerformanceTestConstants.Layout.mainSpacing) {
                resultsHeader
                metricsGrid(results)
                testDetailsSection(results)
                actionButtonsSection
            }
            .padding()
        }
    }

    private var resultsHeader: some View {
        VStack(spacing: PerformanceTestConstants.Layout.itemSpacing) {
            if let url = viewModel.currentURL {
                Text(url.absoluteString)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            statisticalViewPicker
            statisticalViewDescription
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(PerformanceTestConstants.Layout.cornerRadius)
    }

    private var statisticalViewPicker: some View {
        HStack {
            Text(PerformanceTestConstants.Strings.statisticalView)
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $viewModel.selectedStatView) {
                Text(PerformanceTestConstants.Strings.medianRecommended).tag(PerformanceTestConstants.StatViews.median)
                Text(PerformanceTestConstants.Strings.p95Percentile).tag(PerformanceTestConstants.StatViews.p95)
                Text(PerformanceTestConstants.Strings.meanAverage).tag(PerformanceTestConstants.StatViews.mean)
                Text(PerformanceTestConstants.Strings.minBestCase).tag(PerformanceTestConstants.StatViews.min)
                Text(PerformanceTestConstants.Strings.maxWorstCase).tag(PerformanceTestConstants.StatViews.max)
            }
            .pickerStyle(.menu)
            .frame(width: PerformanceTestConstants.Layout.pickerWidth)
        }
    }

    private var statisticalViewDescription: some View {
        Text(statViewDescription(viewModel.selectedStatView))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func metricsGrid(_ results: PerformanceTestResults) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PerformanceTestConstants.Layout.sectionSpacing) {
            loadCompleteMetric(results)
            domCompleteMetric(results)
            domContentLoadedMetric(results)
            domInteractiveMetric(results)
            fcpMetric(results)
            ttfbMetric(results)
            responseTimeMetric(results)
            serverTimeMetric(results)
            transferSizeMetric(results)
            decodedBodySizeMetric(results)
            encodedBodySizeMetric(results)
            resourceCountMetric(results)
        }
    }
}

// MARK: - Individual Metric Components

extension PerformanceTestWindowView {

    private func loadCompleteMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.loadComplete, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.loadComplete, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.loadComplete,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.checkmarkCircle
                )
            }
        }
    }

    private func domCompleteMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.domComplete, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.domComplete, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.domComplete,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.docText
                )
            }
        }
    }

    private func domContentLoadedMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.domContentLoaded, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.domContentLoaded, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.domContentLoaded,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.docRichtext
                )
            }
        }
    }

    private func domInteractiveMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.domInteractive, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.domInteractive, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.domInteractive,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.handTap
                )
            }
        }
    }

    private func fcpMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.fcp, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.fcp, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.fcp,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.paintbrush
                )
            }
        }
    }

    private func ttfbMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.ttfb, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.ttfb, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.ttfb,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.network
                )
            }
        }
    }

    private func responseTimeMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.responseTime, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.responseTime, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.responseTime,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.arrowLeftArrowRight
                )
            }
        }
    }

    private func serverTimeMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.serverTime, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.serverTime, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.serverTime,
                    value: formatMetricValue(value, isTime: true),
                    stdDev: formatMetricValue(stdDev, isTime: true),
                    icon: PerformanceTestConstants.Icons.serverRack
                )
            }
        }
    }

    private func transferSizeMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.transferSize, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.transferSize, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.transferSize,
                    value: formatMetricValue(value, isTime: false),
                    stdDev: formatMetricValue(stdDev, isTime: false),
                    icon: PerformanceTestConstants.Icons.arrowDownDoc
                )
            }
        }
    }

    private func decodedBodySizeMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.decodedBodySize, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.decodedBodySize, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.decodedBodySize,
                    value: formatMetricValue(value, isTime: false),
                    stdDev: formatMetricValue(stdDev, isTime: false),
                    icon: PerformanceTestConstants.Icons.docPlaintext
                )
            }
        }
    }

    private func encodedBodySizeMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            if let value = getMetricStatValue(results.detailedMetrics.encodedBodySize, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(results.detailedMetrics.encodedBodySize, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.encodedBodySize,
                    value: formatMetricValue(value, isTime: false),
                    stdDev: formatMetricValue(stdDev, isTime: false),
                    icon: PerformanceTestConstants.Icons.docZipper
                )
            }
        }
    }

    private func resourceCountMetric(_ results: PerformanceTestResults) -> some View {
        Group {
            let resourceCountDoubles = results.detailedMetrics.resourceCount.map { Double($0) }
            if let value = getMetricStatValue(resourceCountDoubles, viewModel.selectedStatView),
               let stdDev = getMetricStatValue(resourceCountDoubles, PerformanceTestConstants.StatViews.stdDev) {
                MetricBox(
                    title: PerformanceTestConstants.Strings.resourceCount,
                    value: "\(Int(value))",
                    stdDev: "\(Int(stdDev))",
                    icon: PerformanceTestConstants.Icons.folder
                )
            }
        }
    }
}

// MARK: - Test Details Section

extension PerformanceTestWindowView {

    private func testDetailsSection(_ results: PerformanceTestResults) -> some View {
        VStack(alignment: .leading, spacing: PerformanceTestConstants.Layout.itemSpacing) {
            testDetailsHeader
            testDetailsContent(results)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(PerformanceTestConstants.Layout.smallCornerRadius)
    }

    private var testDetailsHeader: some View {
        HStack {
            Text(PerformanceTestConstants.Strings.testDetails)
                .font(.headline)
            Spacer()
        }
    }

    private func testDetailsContent(_ results: PerformanceTestResults) -> some View {
        VStack(spacing: PerformanceTestConstants.Layout.smallSpacing) {
            totalTestsRow(results)
            consistencyRow(results)
            p95ToP50RatioRow(results)
            analysisRow(results)
            failedTestsRow(results)
        }
    }

    private func totalTestsRow(_ results: PerformanceTestResults) -> some View {
        HStack {
            Text(PerformanceTestConstants.Strings.totalTests)
                .foregroundColor(.secondary)
            Spacer()

            Text("\(results.iterations)")
               .font(.system(.body, design: .monospaced))
        }
    }

    private func consistencyRow(_ results: PerformanceTestResults) -> some View {
        HStack {
            Text(PerformanceTestConstants.Strings.consistency)
                .foregroundColor(.secondary)
            Spacer()
            Text(results.reliabilityScore)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(reliabilityColor(results.reliabilityScore))
        }
    }

    private func p95ToP50RatioRow(_ results: PerformanceTestResults) -> some View {
        Group {
            if let ratio = results.p95ToP50Ratio {
                HStack {
                    Text(PerformanceTestConstants.Strings.p95ToP50Ratio)
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(String(format: "%.1fx", ratio))
                            .font(.system(.body, design: .monospaced))
                        if ratio > 2.5 {
                            Image(systemName: PerformanceTestConstants.Icons.exclamationTriangle)
                                .foregroundColor(.orange)
                                .font(.footnote)
                        }
                    }
                }
            }
        }
    }

    private func analysisRow(_ results: PerformanceTestResults) -> some View {
        HStack {
            Text(PerformanceTestConstants.Strings.analysis)
                .foregroundColor(.secondary)
            Spacer()
            Text(results.reliabilityType)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failedTestsRow(_ results: PerformanceTestResults) -> some View {
        Group {
            if results.failedAttempts > 0 {
                HStack {
                    Text(PerformanceTestConstants.Strings.failed)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(results.failedAttempts)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Action Buttons Section

extension PerformanceTestWindowView {

    private var actionButtonsSection: some View {
        HStack {
            Button(action: {
                viewModel.exportResults()
            }) {
                Label("Export to JSON", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: {
                Task {
                    await viewModel.runTest()
                }
            }) {
                Label(PerformanceTestConstants.Strings.testAgain, systemImage: PerformanceTestConstants.Icons.clockwise)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top)
    }
}

// MARK: - Helper Functions

extension PerformanceTestWindowView {

    private func statViewDescription(_ statView: String) -> String {
        switch statView {
        case PerformanceTestConstants.StatViews.median:
            return "Showing median values (50th percentile) ± interquartile range (IQR/2)"
        case PerformanceTestConstants.StatViews.p95:
            return "Showing 95th percentile values (worst 5% of loads) ± interquartile range (IQR/2)"
        case PerformanceTestConstants.StatViews.mean:
            return "Showing average values ± interquartile range (IQR/2)"
        case PerformanceTestConstants.StatViews.min:
            return "Showing best case performance ± interquartile range (IQR/2)"
        case PerformanceTestConstants.StatViews.max:
            return "Showing worst case performance ± interquartile range (IQR/2)"
        default:
            return "Showing \(statView) values ± interquartile range (IQR/2)"
        }
    }

    private func formatMetricValue(_ value: Double, isTime: Bool) -> String {
        if isTime {
            // Convert seconds to milliseconds and add "ms" suffix
            return String(format: "%.0fms", value * 1000)
        } else {
            // For size metrics, format appropriately
            if value > 1_000_000 {
                return String(format: "%.1fMB", value / 1_000_000)
            } else if value > 1000 {
                return String(format: "%.1fKB", value / 1000)
            } else {
                return String(format: "%.0fB", value)
            }
        }
    }

    private func getMetricStatValue<T: BinaryInteger>(_ values: [T], _ statView: String) -> Double? {
        let doubleValues = values.map { Double($0) }
        return getMetricStatValue(doubleValues, statView)
    }

    private func getMetricStatValue(_ values: [Double], _ statView: String) -> Double? {
        guard !values.isEmpty else { return nil }

        switch statView {
        case PerformanceTestConstants.StatViews.mean:
            return values.reduce(0, +) / Double(values.count)
        case PerformanceTestConstants.StatViews.median:
            let sorted = values.sorted()
            let count = sorted.count
            if count % 2 == 0 {
                return (sorted[count/2 - 1] + sorted[count/2]) / 2.0
            } else {
                return sorted[count/2]
            }
        case PerformanceTestConstants.StatViews.min:
            return values.min()
        case PerformanceTestConstants.StatViews.max:
            return values.max()
        case PerformanceTestConstants.StatViews.p95:
            let sorted = values.sorted()
            let count = Double(sorted.count)

            guard count > 0 else { return nil }

            let index = 0.95 * (count - 1)
            let lowerIndex = Int(floor(index))
            let upperIndex = Int(ceil(index))

            if lowerIndex == upperIndex {
                return sorted[lowerIndex]
            }

            let weight = index - Double(lowerIndex)
            let lowerValue = sorted[lowerIndex]
            let upperValue = sorted[upperIndex]

            return lowerValue + weight * (upperValue - lowerValue)
        case PerformanceTestConstants.StatViews.stdDev:
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { sum, value in
                sum + pow(value - mean, 2)
            } / Double(values.count)
            return sqrt(variance)
        case PerformanceTestConstants.StatViews.iqr:
            return PerformanceTestResults.calculateIQR(values)
        case PerformanceTestConstants.StatViews.cv:
            let mean = values.reduce(0, +) / Double(values.count)
            guard mean > 0 else { return nil }

            let variance = values.reduce(0) { sum, value in
                sum + pow(value - mean, 2)
            } / Double(values.count)
            let stdDev = sqrt(variance)
            return (stdDev / mean) * 100
        default:
            return nil
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 70..<90: return .yellow
        case 50..<70: return .orange
        default: return .red
        }
    }

    private func reliabilityColor(_ reliability: String) -> Color {
        switch reliability {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        case "Poor": return .red
        case "Variable": return .orange  // Could be site issue, not necessarily bad
        default: return .gray
        }
    }
}
