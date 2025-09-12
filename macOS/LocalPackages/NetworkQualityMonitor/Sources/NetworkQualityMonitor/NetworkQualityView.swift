//
//  NetworkQualityView.swift
//  NetworkQualityMonitor
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

public struct NetworkQualityView: View {
    @StateObject private var viewModel = NetworkQualityViewModel()

    public init() {}

    public var body: some View {
        if #available(macOS 12.0, iOS 15.0, *) {
            VStack(spacing: 0) {
                if let results = viewModel.results {
                    resultsView(results)
                } else if viewModel.isRunning {
                    progressView
                } else {
                    startView
                }
            }
            .frame(width: 680, height: 650)
        } else {
            // Fallback for macOS 11.4
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Network Quality Test")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("This feature requires macOS 12.0 or later")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Please upgrade your system to use network quality testing")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(width: 680, height: 650)
        }
    }

    @available(macOS 12.0, iOS 15.0, *)
    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Test Network Quality")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Browser focused network checks for performance testing")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { Task { await viewModel.startTest() } }) {
                Label("Start Test", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .padding(.horizontal, 100)
    }

    @available(macOS 12.0, iOS 15.0, *)
    private var progressView: some View {
        VStack(spacing: 24) {
            Text("Testing Network Quality")
                .font(.title)
                .fontWeight(.semibold)

            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 300)

            Text(viewModel.currentPhase)
                .font(.headline)
                .foregroundColor(.secondary)

            Text("\(Int(viewModel.progress * 100))% Complete")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func resultsView(_ results: NetworkTestResults) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Text(results.quality.emoji)
                        .font(.system(size: 48))

                    VStack(alignment: .leading) {
                        Text("Network Quality")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(results.quality.rawValue)
                            .font(.title)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    // Overall score
                    ZStack {
                        Circle()
                            .stroke(qualityColor(results.quality), lineWidth: 6)
                            .frame(width: 80, height: 80)

                        VStack {
                            Text("\(Int(results.overallScore.overall))")
                                .font(.system(size: 28, weight: .bold))
                            Text("Score")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Metrics Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    MetricCard(
                        title: "HTTP Response",
                        value: "\(Int(results.httpResponse.averageResponseTime))ms",
                        actualValue: results.httpResponse.averageResponseTime,
                        metricType: .httpResponse,
                        icon: "speedometer",
                        infoText: "Calculated by testing websites with HEAD requests.\n\n Takes the best-performing site's median (P50) as baseline, then adjusts based on how much worse other sites perform (P75 multiplier). \n\nThis gives a geography-adjusted score. \n\n This test renders more real-world results compared to basic ICMP based Latency tests."
                    )

                    MetricCard(
                        title: "Download",
                        value: String(format: "%.1f Mbps", results.bandwidth.downloadSpeedMbps),
                        actualValue: results.bandwidth.downloadSpeedMbps,
                        metricType: .bandwidth,
                        icon: "arrow.down.circle",
                        infoText: "Downloads 100MB files from multiple CDN servers (Cloudflare, OVH, Hetzner, Tele2). Tests each server briefly to find the fastest, then performs sustained downloads. Takes the best result to show real-world achievable throughput."
                    )

                    MetricCard(
                        title: "Upload",
                        value: String(format: "%.1f Mbps", results.bandwidth.uploadSpeedMbps),
                        actualValue: results.bandwidth.uploadSpeedMbps,
                        metricType: .bandwidth,
                        icon: "arrow.up.circle",
                        infoText: "Uploads 50MB chunks to multiple test servers (Cloudflare, httpbin, speedtest.net). Measures sustained upload throughput. Asymmetric speeds are normal for most connections."
                    )

                    MetricCard(
                        title: "DNS",
                        value: "\(Int(results.dns.averageResolutionTime))ms",
                        actualValue: results.dns.averageResolutionTime,
                        metricType: .dns,
                        icon: "globe",
                        infoText: "Tests DNS resolution speed for popular domains (DuckDuckGo, Google, Amazon, etc.) using system's DNS resolver. Measures average resolution time. High values indicate slow DNS servers or network issues."
                    )

                    MetricCard(
                        title: "Response Variance",
                        value: String(format: "%.1f ms", results.httpResponse.responseVariance),
                        actualValue: results.httpResponse.responseVariance,
                        metricType: .responseVariance,
                        icon: "waveform",
                        infoText: "Measures response consistency using Coefficient of Variation (CV = StdDev/Mean) for each site. Takes P95 of all site CVs to capture worst-case. \n\nA CV of 10% means responses vary by ±10% from average. Values shown in ms (CV × adjusted response time). \n\nLow values = consistent = reliable performance tests. High values = more variable."
                    )

                    MetricCard(
                        title: "Buffer Bloat",
                        value: results.bufferBloat.grade,
                        actualValue: 0,  // Not used for grade-based metric
                        metricType: .bufferBloat,
                        icon: "waveform.path.ecg",
                        infoText: "Measures latency increase when network is saturated. Runs HEAD requests during a large download to detect queuing delays. Grade based on absolute increase: A (<50ms), B (50-100ms), C (100-200ms), D (200-400ms), F (>400ms). Lower grades mean less buffer bloat impact on real-time apps."
                    )
                }

                // Action buttons
                HStack {
                    Spacer()

                    Button(action: { Task { await viewModel.startTest() } }) {
                        Label("Test Again", systemImage: "arrow.clockwise")
                    }
                }
                .padding(.top)
            }
            .padding()
        }
    }

    private func qualityColor(_ quality: NetworkQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }

}

@available(macOS 12.0, iOS 15.0, *)
struct MetricCard: View {
    let title: String
    let value: String
    let actualValue: Double
    let metricType: MetricType
    let icon: String
    let infoText: String

    @State private var showInfo = false

    enum MetricType {
        case httpResponse      // Lower is better (ms)
        case bandwidth         // Higher is better (Mbps)
        case dns              // Lower is better (ms)
        case responseVariance // Lower is better (ms)
        case bufferBloat // Grade-based
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                    Spacer()
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(qualityLabel)
                        .font(.caption)
                        .foregroundColor(qualityColor)
                }

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)

                ProgressView(value: normalizedValue, total: 1.0)
                    .accentColor(qualityColor)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            if showInfo {
                VStack(spacing: 12) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        Button(action: { showInfo = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView {
                        Text(infoText)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 120)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(radius: 4)
            }
        }
    }

    private var normalizedValue: Double {
        switch metricType {
        case .httpResponse:
            // 0-600ms range for browser navigation, inverted (lower is better)
            // Adjusted to match new scale: Excellent <150, Good <300, Fair <500
            return max(0, min(1, 1.0 - (actualValue / 600.0)))
        case .bandwidth:
            // 0-500Mbps range (higher is better)
            return max(0, min(1, actualValue / 500.0))
        case .dns:
            // 0-150ms range, inverted (lower is better)
            // Adjusted to better show DNS performance (Fair is <100ms)
            return max(0, min(1, 1.0 - (actualValue / 150.0)))
        case .responseVariance:
            // 0-200ms range for CV-based variance, inverted (lower is better)
            // Adjusted to match new scale: Excellent <50, Good <100, Fair <150
            return max(0, min(1, 1.0 - (actualValue / 200.0)))
        case .bufferBloat:
            // Grade-based
            switch value {
            case "A": return 0.9
            case "B": return 0.7
            case "C": return 0.5
            case "D": return 0.3
            default: return 0.1
            }
        }
    }

    private var qualityLabel: String {
        switch metricType {
        case .httpResponse:
            // Relative performance scale (adjusted for user's geographic location)
            if actualValue < 150 { return "Excellent" } else if actualValue < 300 { return "Good" } else if actualValue < 500 { return "Fair" } else { return "Poor" }
        case .bandwidth:
            if actualValue >= 100 { return "Excellent" } else if actualValue >= 50 { return "Good" } else if actualValue >= 25 { return "Fair" } else { return "Poor" }
        case .dns:
            if actualValue < 20 { return "Excellent" } else if actualValue < 50 { return "Good" } else if actualValue < 100 { return "Fair" } else { return "Poor" }
        case .responseVariance:
            // Based on coefficient of variation (CV) for HTTP requests
            // More lenient than network jitter since we're testing different sites
            if actualValue < 50 { return "Excellent" }    // CV < ~25% - very consistent
            else if actualValue < 100 { return "Good" }    // CV < ~50% - normal for HTTP
            else if actualValue < 150 { return "Fair" }    // CV < ~75% - manageable
            else { return "Poor" }                         // CV > ~75% - high variance
        case .bufferBloat:
            switch value {
            case "A": return "Excellent"
            case "B": return "Good"
            case "C": return "Fair"
            case "D": return "Poor"
            default: return "Very Poor"
            }
        }
    }

    private var qualityColor: Color {
        switch qualityLabel {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        case "Poor", "Very Poor": return .red
        default: return .gray
        }
    }
}

@MainActor
final class NetworkQualityViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var results: NetworkTestResults?
    @Published var progress: Double = 0
    @Published var currentPhase = ""
    @Published var error: String?

    private let monitor = NetworkQualityMonitor()

    func startTest() async {
        isRunning = true
        results = nil
        error = nil
        progress = 0

        // Set up real progress callback
        monitor.progressCallback = { [weak self] progress, phase in
            Task { @MainActor in
                self?.progress = progress
                self?.currentPhase = phase
            }
        }

        do {
            let results = try await monitor.runTest()

            await MainActor.run {
                self.results = results
                self.progress = 1.0
                self.isRunning = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isRunning = false
            }
        }
    }
}

// MARK: - macOS Window Controller with SwiftUI

#if os(macOS)
import AppKit

public class NetworkQualitySwiftUIWindowController: NSWindowController {

    public convenience init() {
        let window = NSWindow()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Network Quality Test"
        window.setContentSize(NSSize(width: 680, height: 650))

        let hostingController = NSHostingController(rootView: NetworkQualityView())
        window.contentViewController = hostingController

        self.init(window: window)

        window.center()
        window.setFrameAutosaveName("NetworkQualityTest")
    }
}
#endif
