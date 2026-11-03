//
//  SitePermissionsFrameBenchmarkTests.swift
//  DuckDuckGo
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

import Darwin
import WebKit
import XCTest
@testable import SitePermissions

/// Measures what the site-permission content-scope features cost on a page that creates many blank iframes.
///
/// Opt-in, so CI skips it. xcodebuild passes `TEST_RUNNER_`-prefixed variables to the test process:
///
///     TEST_RUNNER_SITE_PERMISSIONS_BENCHMARK=1 xcodebuild test -scheme SitePermissions \
///         -only-testing:SitePermissionsTests/SitePermissionsFrameBenchmarkTests ...
///
/// `SITE_PERMISSIONS_BENCHMARK_FRAMES` (default 200) and `SITE_PERMISSIONS_BENCHMARK_RUNS` (default 3)
/// change the frame count and the runs per configuration. The report holds medians and asserts nothing.
@MainActor
final class SitePermissionsFrameBenchmarkTests: XCTestCase {

    private enum Configuration: String, CaseIterable {
        case noScripts = "No scripts"
        /// Tab web views run the content-scope scripts in both content worlds of every frame. Every configuration
        /// below runs them too, so its difference from the control is the site-permission features' own cost.
        case control = "Control: content-scope scripts without site permissions"
        case geolocation = "Control + geolocation"
        case mediaCapture = "Control + media capture"
        case allFeatures = "Control + all site permissions"
    }

    private struct Sample {
        let creationMilliseconds: Double
        let footprintGrowthBytes: Double?
        let nativeMessages: [String: Int]
        let windowMessages: Int
    }

    func testBlankIframeFlood() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["SITE_PERMISSIONS_BENCHMARK"] == "1",
                          "Set TEST_RUNNER_SITE_PERMISSIONS_BENCHMARK=1 to run this benchmark")
        let frameCount = environment["SITE_PERMISSIONS_BENCHMARK_FRAMES"].flatMap(Int.init) ?? 200
        let runs = environment["SITE_PERMISSIONS_BENCHMARK_RUNS"].flatMap(Int.init) ?? 3

        var samples = [Configuration: [Sample]]()
        let configurations = Configuration.allCases
        // Interleave configurations and rotate their order each run, so that drift during the run and
        // whatever the previous web view leaves in the web content process affect each one equally.
        for run in 0..<runs {
            for offset in configurations.indices {
                let configuration = configurations[(run + offset) % configurations.count]
                let sample = try await measure(configuration, frameCount: frameCount)
                samples[configuration, default: []].append(sample)
                print("Run \(run + 1), \(configuration.rawValue): \(sample)")
            }
        }

        let controlGrowth = median((samples[.control] ?? []).compactMap(\.footprintGrowthBytes))
        var lines = [
            "\(frameCount) blank iframes, median of \(runs) runs",
            "",
            "| Configuration | Create frames (ms) | Footprint growth (MB) | Over control (MB) | Per frame over control (KB) "
                + "| Native messages | Window messages |",
            "|---|---:|---:|---:|---:|---|---:|"
        ]
        for configuration in configurations {
            let configurationSamples = samples[configuration] ?? []
            let growth = median(configurationSamples.compactMap(\.footprintGrowthBytes))
            let overControl = configuration == .noScripts ? nil : growth.flatMap { growth in
                controlGrowth.map { growth - $0 }
            }
            let messages = configurationSamples.first?.nativeMessages ?? [:]
            let messageSummary = messages.isEmpty ? "0" : messages.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }
                .joined(separator: ", ")
            let cells = [
                configuration.rawValue,
                format(median(configurationSamples.map(\.creationMilliseconds))),
                format(growth.map { $0 / 1_048_576 }),
                format(overControl.map { $0 / 1_048_576 }),
                format(overControl.map { $0 / 1_024 / Double(frameCount) }),
                messageSummary,
                String(configurationSamples.first?.windowMessages ?? 0)
            ]
            lines.append("| \(cells.joined(separator: " | ")) |")
        }
        if samples.values.joined().allSatisfy({ $0.footprintGrowthBytes == nil }) {
            lines.append("\nThe web content process footprint was unavailable, so memory was not measured.")
        }

        let report = lines.joined(separator: "\n")
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "Site permissions frame benchmark"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func measure(_ configuration: Configuration, frameCount: Int) async throws -> Sample {
        let counter = NativeMessageCounter()
        let webViewConfiguration = WKWebViewConfiguration()
        let geolocation = GeolocationUserScript()
        // Tab web views activate every frame with a trustworthy host; blank frames inherit the page's.
        geolocation.activationHandler = { !$0.securityOrigin.host.isEmpty }
        let contentScope: SitePermissionsContentScope?
        switch configuration {
        case .noScripts:
            contentScope = nil
        case .control:
            contentScope = try SitePermissionsContentScope()
        case .geolocation:
            contentScope = try SitePermissionsContentScope(geolocation: geolocation)
        case .mediaCapture:
            contentScope = try SitePermissionsContentScope(mediaCapture: MediaCaptureUserScript())
        case .allFeatures:
            contentScope = try SitePermissionsContentScope(geolocation: geolocation, mediaCapture: MediaCaptureUserScript())
        }
        if let contentScope {
            counter.forward(to: contentScope.pageScript)
            contentScope.install(in: webViewConfiguration.userContentController, pageMessageHandler: counter)
        }

        let page = BenchmarkPage(configuration: webViewConfiguration)
        defer {
            geolocation.cancelAllWatches()
            webViewConfiguration.userContentController.removeAllScriptMessageHandlers()
        }
        try await page.load(Self.html, baseURL: XCTUnwrap(URL(string: "http://localhost/")))
        _ = try await waitForMessagesToSettle(in: page.webView, counter: counter)
        let footprintBefore = physicalFootprint(of: page.webView)

        let elapsed = try await page.webView.callAsyncJavaScript("return await createFrames(count, 20);",
                                                                 arguments: ["count": frameCount],
                                                                 in: nil,
                                                                 contentWorld: .page)
        let windowMessages = try await waitForMessagesToSettle(in: page.webView, counter: counter)
        let footprintAfter = physicalFootprint(of: page.webView)

        return Sample(creationMilliseconds: try XCTUnwrap(elapsed as? Double),
                      footprintGrowthBytes: footprintBefore.flatMap { before in
                          footprintAfter.map { Double($0) - Double(before) }
                      },
                      nativeMessages: counter.counts,
                      windowMessages: windowMessages)
    }

    private func waitForMessagesToSettle(in webView: WKWebView, counter: NativeMessageCounter) async throws -> Int {
        var last = (native: -1, replies: -1, window: -1)
        var stablePolls = 0
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let window = try await webView.callAsyncJavaScript("return windowMessages;",
                                                                arguments: [:],
                                                                in: nil,
                                                                contentWorld: .page) as? Int ?? 0
            let current = (native: counter.counts.values.reduce(0, +), replies: counter.replies, window: window)
            stablePolls = current == last && current.replies == current.native ? stablePolls + 1 : 0
            last = current
            if stablePolls == 3 {
                return current.window
            }
        }
        throw NSError(domain: "SitePermissionsFrameBenchmark", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Messages did not settle within 10 seconds: "
                + "\(last.native) received, \(last.replies) replies, \(last.window) window messages"
        ])
    }

    /// Returns the web content process's physical footprint, or nil when the platform hides it.
    private func physicalFootprint(of webView: WKWebView) -> UInt64? {
        // Test-only private API: WebKit does not publish its web content process identifier.
        // proc_pid_rusage is not in the iOS SDK headers, so it is looked up at runtime.
        guard let processID = webView.value(forKey: "_webProcessIdentifier") as? pid_t,
              processID > 0,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "proc_pid_rusage") else {
            return nil
        }
        typealias ProcessResourceUsage = @convention(c) (pid_t, Int32, UnsafeMutablePointer<rusage_info_t?>) -> Int32
        let processResourceUsage = unsafeBitCast(symbol, to: ProcessResourceUsage.self)
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                processResourceUsage(processID, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    private func median(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }

    private func format(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "n/a"
    }

    private static let html = """
    <html><head><script>
        window.windowMessages = 0;
        window.addEventListener("message", () => { window.windowMessages += 1; });
        // A message channel yields to the event loop without timer clamping in a hidden web view.
        const yieldToEventLoop = () => new Promise((resolve) => {
            const channel = new MessageChannel();
            channel.port1.onmessage = resolve;
            channel.port2.postMessage(null);
        });
        window.createFrames = async (count, batchSize) => {
            const start = performance.now();
            for (let created = 0; created < count; created += batchSize) {
                for (let index = created; index < Math.min(count, created + batchSize); index++) {
                    document.body.appendChild(document.createElement("iframe"));
                }
                await yieldToEventLoop();
            }
            return performance.now() - start;
        };
    </script></head><body></body></html>
    """
}

/// Counts each page-world content-scope message before forwarding it to the content-scope script.
@MainActor
private final class NativeMessageCounter: NSObject, WKScriptMessageHandlerWithReply {

    private(set) var counts = [String: Int]()
    private(set) var replies = 0
    private var handler: WKScriptMessageHandlerWithReply?

    func forward(to handler: WKScriptMessageHandlerWithReply) {
        self.handler = handler
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let body = message.body as? [String: Any]
        let key = [body?["featureName"] as? String, body?["method"] as? String].compactMap { $0 }.joined(separator: ".")
        counts[key.isEmpty ? message.name : key, default: 0] += 1
        guard let handler else {
            replies += 1
            replyHandler(nil, "Unknown message handler")
            return
        }
        handler.userContentController(userContentController, didReceive: message) { [weak self] reply, error in
            self?.replies += 1
            replyHandler(reply, error)
        }
    }
}

@MainActor
private final class BenchmarkPage: NSObject, WKNavigationDelegate {

    let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ html: String, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
