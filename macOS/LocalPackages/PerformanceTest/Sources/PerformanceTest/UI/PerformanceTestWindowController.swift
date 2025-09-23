//
//  PerformanceTestWindowController.swift
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

import AppKit
import SwiftUI
import WebKit

/// Window controller for performance testing - handles everything internally
public class PerformanceTestWindowController: NSWindowController {

    private var viewModel: PerformanceTestViewModel?
    private var hostingController: NSHostingController<PerformanceTestWindowView>?

    public convenience init(webView: WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Site Performance Test"
        window.center()

        self.init(window: window)

        // Create view model with the webView
        let viewModel = PerformanceTestViewModel(webView: webView)
        self.viewModel = viewModel

        // Create the SwiftUI view
        let contentView = PerformanceTestWindowView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        window.contentViewController = hostingController
        window.setFrameAutosaveName("PerformanceTest")
    }
}

// MARK: - SwiftUI View

struct PerformanceTestWindowView: View {
    @ObservedObject var viewModel: PerformanceTestViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let results = viewModel.testResults {
                resultsView(results)
            } else if viewModel.isRunning {
                progressView
            } else {
                startView
            }
        }
        .frame(width: 680, height: 650)
    }

    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "speedometer")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Test Site Performance")
                .font(.largeTitle)
                .fontWeight(.semibold)

            if let url = viewModel.currentURL {
                VStack(spacing: 8) {
                    Text("Testing:")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(url.host ?? url.absoluteString)
                        .font(.system(.title2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                }
                .multilineTextAlignment(.center)
            } else {
                Text("No active page to test")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Test configuration
            VStack(spacing: 16) {
                // Iterations selector
                VStack(spacing: 8) {
                    Text("Test Configuration")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Picker("Iterations", selection: $viewModel.selectedIterations) {
                        ForEach([10, 15, 20, 30, 50], id: \.self) { count in
                            Text("\(count) iterations").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }
            .padding(.top)

            Button(action: {
                Task {
                    await viewModel.runTest()
                }
            }) {
                Label("Start Test", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.currentURL == nil)

            Spacer()
        }
        .padding()
        .padding(.horizontal, 100)
    }

    private var progressView: some View {
        VStack(spacing: 24) {
            Text("Testing Site Performance")
                .font(.title)
                .fontWeight(.semibold)

            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 300)

            Text(viewModel.statusText)
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Iteration \(viewModel.currentIteration) of \(viewModel.totalIterations) (\(Int(viewModel.progress * 100))% Complete)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Stop Test") {
                viewModel.cancelTest()
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func resultsView(_ results: PerformanceTestResults) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with site URL and statistical view selector
                VStack(spacing: 12) {
                    if let url = viewModel.currentURL {
                        Text(url.host ?? url.absoluteString)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Text("Statistical View:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $viewModel.selectedStatView) {
                            Text("Median (Recommended)").tag("median")
                            Text("P95 (95th Percentile)").tag("p95")
                            Text("Mean (Average)").tag("mean")
                            Text("Min (Best Case)").tag("min")
                            Text("Max (Worst Case)").tag("max")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }

                    Text(statViewDescription(viewModel.selectedStatView))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Metrics Grid - All performance metrics with selected statistical view
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // Load Complete
                    if let value = getMetricStatValue(results.detailedMetrics.loadComplete, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.loadComplete, "stdDev") {
                        MetricBox(
                            title: "Load Complete",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "checkmark.circle"
                        )
                    }

                    // DOM Complete
                    if let value = getMetricStatValue(results.detailedMetrics.domComplete, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.domComplete, "stdDev") {
                        MetricBox(
                            title: "DOM Complete",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "doc.text"
                        )
                    }

                    // DOM Content Loaded
                    if let value = getMetricStatValue(results.detailedMetrics.domContentLoaded, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.domContentLoaded, "stdDev") {
                        MetricBox(
                            title: "DOM Content Loaded",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "doc.richtext"
                        )
                    }

                    // DOM Interactive
                    if let value = getMetricStatValue(results.detailedMetrics.domInteractive, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.domInteractive, "stdDev") {
                        MetricBox(
                            title: "DOM Interactive",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "hand.tap"
                        )
                    }

                    // FCP (First Contentful Paint)
                    if let value = getMetricStatValue(results.detailedMetrics.fcp, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.fcp, "stdDev") {
                        MetricBox(
                            title: "FCP",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "paintbrush"
                        )
                    }

                    // TTFB (Time to First Byte)
                    if let value = getMetricStatValue(results.detailedMetrics.ttfb, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.ttfb, "stdDev") {
                        MetricBox(
                            title: "TTFB",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "network"
                        )
                    }

                    // Response Time
                    if let value = getMetricStatValue(results.detailedMetrics.responseTime, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.responseTime, "stdDev") {
                        MetricBox(
                            title: "Response Time",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "arrow.left.arrow.right"
                        )
                    }

                    // Server Time
                    if let value = getMetricStatValue(results.detailedMetrics.serverTime, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.serverTime, "stdDev") {
                        MetricBox(
                            title: "Server Time",
                            value: formatMetricValue(value, isTime: true),
                            stdDev: formatMetricValue(stdDev, isTime: true),
                            icon: "server.rack"
                        )
                    }

                    // Transfer Size
                    if let value = getMetricStatValue(results.detailedMetrics.transferSize, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.transferSize, "stdDev") {
                        MetricBox(
                            title: "Transfer Size",
                            value: formatMetricValue(value, isTime: false),
                            stdDev: formatMetricValue(stdDev, isTime: false),
                            icon: "arrow.down.doc"
                        )
                    }

                    // Decoded Body Size
                    if let value = getMetricStatValue(results.detailedMetrics.decodedBodySize, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.decodedBodySize, "stdDev") {
                        MetricBox(
                            title: "Decoded Body Size",
                            value: formatMetricValue(value, isTime: false),
                            stdDev: formatMetricValue(stdDev, isTime: false),
                            icon: "doc.plaintext"
                        )
                    }

                    // Encoded Body Size
                    if let value = getMetricStatValue(results.detailedMetrics.encodedBodySize, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(results.detailedMetrics.encodedBodySize, "stdDev") {
                        MetricBox(
                            title: "Encoded Body Size",
                            value: formatMetricValue(value, isTime: false),
                            stdDev: formatMetricValue(stdDev, isTime: false),
                            icon: "doc.zipper"
                        )
                    }

                    // Resource Count
                    let resourceCountDoubles = results.detailedMetrics.resourceCount.map { Double($0) }
                    if let value = getMetricStatValue(resourceCountDoubles, viewModel.selectedStatView),
                       let stdDev = getMetricStatValue(resourceCountDoubles, "stdDev") {
                        MetricBox(
                            title: "Resource Count",
                            value: "\(Int(value))",
                            stdDev: "\(Int(stdDev))",
                            icon: "folder"
                        )
                    }
                }

                // Test details
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Test Details")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Text("Total Tests:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(results.iterations - 1)")
                                .font(.system(.body, design: .monospaced))
                        }

                        HStack {
                            Text("Consistency:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(results.reliabilityScore)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(reliabilityColor(results.reliabilityScore))
                        }

                        if let ratio = results.p95ToP50Ratio {
                            HStack {
                                Text("P95/P50 Ratio:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(String(format: "%.1fx", ratio))
                                        .font(.system(.body, design: .monospaced))
                                    if ratio > 2.5 {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.footnote)
                                    }
                                }
                            }
                        }

                        HStack {
                            Text("Analysis:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(results.reliabilityType)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if results.failedAttempts > 0 {
                            HStack {
                                Text("Failed:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(results.failedAttempts)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)

                // Action buttons
                HStack {
                    Spacer()

                    Button(action: {
                        Task {
                            await viewModel.runTest()
                        }
                    }) {
                        Label("Test Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top)
            }
            .padding()
        }
    }

    private func statViewDescription(_ statView: String) -> String {
        switch statView {
        case "median":
            return "Showing median values (50th percentile) ± standard deviation"
        case "p95":
            return "Showing 95th percentile values (worst 5% of loads) ± standard deviation"
        case "mean":
            return "Showing average values ± standard deviation"
        case "min":
            return "Showing best case performance ± standard deviation"
        case "max":
            return "Showing worst case performance ± standard deviation"
        default:
            return "Showing \(statView) values ± standard deviation"
        }
    }

    private func gradeEmoji(_ grade: String) -> String {
        switch grade {
        case "A": return "🟢" // Green circle for Excellent
        case "B": return "🟡" // Yellow circle for Good
        case "C": return "🟠" // Orange circle for Fair
        case "D": return "🔴" // Red circle for Poor
        default: return "🔴" // Red circle for Very Poor
        }
    }

    private func timeQuality(_ time: TimeInterval) -> String {
        // Based on Google Core Web Vitals LCP thresholds
        if time < 2.5 { return "Good" } else if time < 4.0 { return "Needs Improvement" } else { return "Poor" }
    }

    private func consistencyQuality(_ stdDev: TimeInterval, averageTime: TimeInterval) -> String {
        guard averageTime > 0 else { return "Poor" }
        let cv = (stdDev / averageTime) * 100
        return cvQuality(cv)
    }

    private func cvQuality(_ cv: Double) -> String {
        if cv < 10 { return "Excellent" } else if cv < 20 { return "Good" } else if cv < 40 { return "Fair" } else { return "Poor" }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        // Always show in milliseconds as integers to match spec
        String(format: "%.0f", time * 1000)
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

        // Exclude first value (warm-up) if we have more than one
        let relevantValues = values.count > 1 ? Array(values.dropFirst()) : values
        guard !relevantValues.isEmpty else { return nil }

        switch statView {
        case "mean":
            return relevantValues.reduce(0, +) / Double(relevantValues.count)
        case "median":
            let sorted = relevantValues.sorted()
            let count = sorted.count
            if count % 2 == 0 {
                return (sorted[count/2 - 1] + sorted[count/2]) / 2.0
            } else {
                return sorted[count/2]
            }
        case "min":
            return relevantValues.min()
        case "max":
            return relevantValues.max()
        case "p95":
            let sorted = relevantValues.sorted()
            let index = Int(Double(sorted.count - 1) * 0.95)
            return sorted[index]
        case "stdDev":
            let mean = relevantValues.reduce(0, +) / Double(relevantValues.count)
            let variance = relevantValues.reduce(0) { sum, value in
                sum + pow(value - mean, 2)
            } / Double(relevantValues.count)
            return sqrt(variance)
        case "cv":
            let mean = relevantValues.reduce(0, +) / Double(relevantValues.count)
            guard mean > 0 else { return nil }
            let stdDev = getMetricStatValue(relevantValues, "stdDev") ?? 0
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

// Metric box showing value with progress bar
struct MetricBox: View {
    let title: String
    let value: String
    let stdDev: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.caption)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // DuckDuckGo Browser
            HStack(spacing: 12) {
                Image("Logo", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * normalizedProgress(value), height: 8)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 4) {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)

                    if let stdDev = stdDev {
                        Text("± \(stdDev)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 120, alignment: .trailing)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    // Calculate progress bar width based on value (normalized 0-1)
    private func normalizedProgress(_ value: String) -> Double {
        // Extract numeric value from string (remove "ms", "KB", etc)
        let numericString = value.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let numericValue = Double(numericString) else { return 0.5 }

        // Normalize based on whether it's time (ms) or size (KB/MB)
        if value.contains("ms") {
            // For time: 0ms = 1.0, 5000ms = 0.0
            return max(0, min(1, 1.0 - (numericValue / 5000.0)))
        } else if value.contains("KB") || value.contains("MB") {
            // For size: smaller is better
            let sizeInKB = value.contains("MB") ? numericValue * 1000 : numericValue
            return max(0, min(1, 1.0 - (sizeInKB / 10000.0)))
        } else {
            // For counts: normalize to 0-200 range
            return max(0, min(1, numericValue / 200.0))
        }
    }
}

struct PerformanceMetricCard: View {
    let title: String
    let value: String
    let actualValue: Double
    let metricType: MetricType
    let icon: String
    let quality: String
    let averageTime: Double?

    enum MetricType {
        case loadTime
        case consistency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private var normalizedValue: Double {
        switch metricType {
        case .loadTime:
            // 0-10 second range, inverted (lower is better)
            return max(0, min(1, 1.0 - (actualValue / 10.0)))
        case .consistency:
            // Use CV-based calculation if averageTime is available
            if let avgTime = averageTime, avgTime > 0 {
                let cv = (actualValue / avgTime) * 100
                // 0-100% CV range, inverted (lower is better)
                return max(0, min(1, 1.0 - (cv / 100.0)))
            } else {
                // Fallback to absolute std dev, 0-2 second range, inverted
                return max(0, min(1, 1.0 - (actualValue / 2.0)))
            }
        }
    }

    private var qualityColor: Color {
        switch quality {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        case "Poor": return .red
        default: return .gray
        }
    }
}

// MARK: - Enhanced View Model

@MainActor
final class PerformanceTestViewModel: ObservableObject {
    @Published var currentURL: URL?
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var currentIteration = 0
    @Published var totalIterations = 10
    @Published var testResults: PerformanceTestResults?
    @Published var isCancelled = false
    @Published var selectedIterations = 10
    @Published var selectedStatView = "median" // Default to median - more robust to outliers

    private var webView: WKWebView?
    private var tester: SitePerformanceTester?
    private weak var browserWindow: NSWindow?
    private var overlayView: NSView?

    init(webView: WKWebView) {
        self.webView = webView
        self.currentURL = webView.url
        self.browserWindow = webView.window
        self.tester = SitePerformanceTester(webView: webView)
        setupTester()
    }

    private func setupTester() {
        tester?.progressHandler = { [weak self] iteration, total, status in
            Task { @MainActor in
                // Account for warm-up iteration: hide first iteration from user
                if iteration == 1 {
                    // During warm-up iteration
                    self?.currentIteration = 0
                    self?.totalIterations = total - 1  // User-requested iterations only
                    self?.statusText = "Warming up..."
                    self?.progress = 0.0
                } else {
                    // During actual test iterations (2, 3, 4, ..., total)
                    let userIteration = iteration - 1  // Convert to user's 1-based counting
                    let userTotal = total - 1  // User-requested total

                    self?.currentIteration = userIteration
                    self?.totalIterations = userTotal
                    self?.statusText = status
                    self?.progress = Double(userIteration) / Double(userTotal)
                }
            }
        }

        tester?.isCancelled = { [weak self] in
            self?.isCancelled ?? false
        }
    }

    func runTest() async {
        guard let url = currentURL, let tester = tester else { return }

        isRunning = true
        isCancelled = false
        progress = 0
        testResults = nil

        // Show overlay on browser window
        showTestOverlay()

        // Run the site performance test
        let results = await tester.runPerformanceTest(
            url: url,
            iterations: selectedIterations + 1, // +1 for warm-up run
            timeout: 30.0
        )

        // Hide overlay
        hideTestOverlay()

        self.testResults = results
        isRunning = false
    }

    func cancelTest() {
        isCancelled = true
        hideTestOverlay()
    }

    private func showTestOverlay() {
        guard let browserWindow = browserWindow,
              let contentView = browserWindow.contentView else { return }

        DispatchQueue.main.async { [weak self] in
            // Create overlay view
            let overlay = NSView(frame: contentView.bounds)
            overlay.wantsLayer = true
            overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
            overlay.autoresizingMask = [.width, .height]

            // Create message container
            let messageContainer = NSView()
            messageContainer.wantsLayer = true
            messageContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            messageContainer.layer?.cornerRadius = 12
            messageContainer.layer?.masksToBounds = true

            // Create title label
            let titleLabel = NSTextField(labelWithString: "Performance Test in Progress")
            titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
            titleLabel.textColor = NSColor.labelColor
            titleLabel.alignment = .center

            // Create message label
            let messageLabel = NSTextField(labelWithString: "Please wait...")
            messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
            messageLabel.textColor = NSColor.secondaryLabelColor
            messageLabel.alignment = .center
            messageLabel.maximumNumberOfLines = 0
            messageLabel.lineBreakMode = .byWordWrapping

            // Layout message container
            messageContainer.addSubview(titleLabel)
            messageContainer.addSubview(messageLabel)

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: messageContainer.topAnchor, constant: 20),
                titleLabel.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor, constant: 20),
                titleLabel.trailingAnchor.constraint(equalTo: messageContainer.trailingAnchor, constant: -20),

                messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
                messageLabel.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor, constant: 20),
                messageLabel.trailingAnchor.constraint(equalTo: messageContainer.trailingAnchor, constant: -20),
                messageLabel.bottomAnchor.constraint(equalTo: messageContainer.bottomAnchor, constant: -20),

                messageContainer.widthAnchor.constraint(equalToConstant: 400)
            ])

            // Add message container to overlay
            overlay.addSubview(messageContainer)
            messageContainer.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                messageContainer.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                messageContainer.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
            ])

            // Add overlay to window
            contentView.addSubview(overlay)
            self?.overlayView = overlay
        }
    }

    private func hideTestOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayView?.removeFromSuperview()
            self?.overlayView = nil
        }
    }
}
