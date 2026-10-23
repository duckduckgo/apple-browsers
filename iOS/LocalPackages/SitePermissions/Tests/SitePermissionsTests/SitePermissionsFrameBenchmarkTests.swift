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
import SitePermissions
import UserScript
import WebKit
import XCTest

/// Measures what the site-permission scripts cost on a page that creates many blank iframes.
///
/// Opt-in, so CI skips it. xcodebuild passes `TEST_RUNNER_`-prefixed variables to the test process:
///
///     TEST_RUNNER_SITE_PERMISSIONS_BENCHMARK=1 xcodebuild test -scheme SitePermissions \
///         -only-testing:SitePermissionsTests/SitePermissionsFrameBenchmarkTests ...
///
/// `SITE_PERMISSIONS_BENCHMARK_FRAMES` (default 200) and `SITE_PERMISSIONS_BENCHMARK_RUNS` (default 3)
/// change the frame count and the runs per configuration. The report holds medians and asserts nothing.
/// This file uses only the scripts' public API, so it also runs unchanged on older revisions.
@MainActor
final class SitePermissionsFrameBenchmarkTests: XCTestCase {

    private enum Configuration: String, CaseIterable {
        case noScripts = "No site-permission scripts"
        case geolocation = "Geolocation only"
        case mediaCapture = "Media capture only"
        case allScripts = "All scripts"
        /// Tab web views already run other scripts in both content worlds of every frame. This control
        /// measures what those worlds cost, so the difference from it is the site-permission scripts' own cost.
        case emptyScripts = "Control: empty page and isolated scripts"
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
        // Interleave configurations so that drift during the run affects each one equally.
        for run in 1...runs {
            for configuration in Configuration.allCases {
                let sample = try await measure(configuration, frameCount: frameCount)
                samples[configuration, default: []].append(sample)
                print("Run \(run), \(configuration.rawValue): \(sample)")
            }
        }

        var lines = [
            "\(frameCount) blank iframes, median of \(runs) runs",
            "",
            "| Configuration | Create frames (ms) | Footprint growth (MB) | Per frame (KB) | Native messages | Window messages |",
            "|---|---:|---:|---:|---|---:|"
        ]
        for configuration in Configuration.allCases {
            let configurationSamples = samples[configuration] ?? []
            let growth = median(configurationSamples.compactMap(\.footprintGrowthBytes))
            let messages = configurationSamples.first?.nativeMessages ?? [:]
            let messageSummary = messages.isEmpty ? "0" : messages.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }
                .joined(separator: ", ")
            let cells = [
                configuration.rawValue,
                format(median(configurationSamples.map(\.creationMilliseconds))),
                format(growth.map { $0 / 1_048_576 }),
                format(growth.map { $0 / 1_024 / Double(frameCount) }),
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
        let geolocation = GeolocationUserScript(installImmediately: true)
        // Tab web views activate every frame with a trustworthy host; blank frames inherit the page's.
        geolocation.activationHandler = { !$0.securityOrigin.host.isEmpty }
        let scripts: [UserScript]
        switch configuration {
        case .noScripts:
            scripts = []
        case .geolocation:
            scripts = [geolocation.policyScript, geolocation]
        case .mediaCapture:
            scripts = [MediaCaptureUserScript()]
        case .allScripts:
            // The order that tab web views use.
            scripts = [MediaCaptureUserScript(), geolocation.policyScript, geolocation]
        case .emptyScripts:
            scripts = []
            for world in [WKContentWorld.page, .defaultClient] {
                webViewConfiguration.userContentController.addUserScript(
                    WKUserScript(source: "void 0;", injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)
                )
            }
        }
        for script in scripts {
            counter.install(script, in: webViewConfiguration.userContentController)
        }

        let page = BenchmarkPage(configuration: webViewConfiguration)
        defer { webViewConfiguration.userContentController.removeAllScriptMessageHandlers() }
        try await page.load(Self.html, baseURL: XCTUnwrap(URL(string: "http://localhost/")))
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

    /// Waits until neither native nor window message counts change for 300 ms, up to 10 seconds.
    private func waitForMessagesToSettle(in webView: WKWebView, counter: NativeMessageCounter) async throws -> Int {
        var last = (native: -1, window: -1)
        var stablePolls = 0
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let window = try await webView.callAsyncJavaScript("return windowMessages;",
                                                                arguments: [:],
                                                                in: nil,
                                                                contentWorld: .page) as? Int ?? 0
            let current = (native: counter.counts.values.reduce(0, +), window: window)
            stablePolls = current == last ? stablePolls + 1 : 0
            last = current
            if stablePolls == 3 {
                break
            }
        }
        return last.window
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

/// Counts each message before forwarding it to its user script, as the app's message broker does.
@MainActor
private final class NativeMessageCounter: NSObject, WKScriptMessageHandlerWithReply {

    private(set) var counts = [String: Int]()
    private var handlers = [String: WKScriptMessageHandlerWithReply]()

    func install(_ script: UserScript, in controller: WKUserContentController) {
        controller.addUserScript(script.makeWKUserScriptSync())
        for name in script.messageNames {
            handlers[name] = script as? WKScriptMessageHandlerWithReply
            controller.addScriptMessageHandler(self, contentWorld: script.getContentWorld(), name: name)
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let key = (message.body as? [String: Any])?["kind"] as? String ?? message.name
        counts[key, default: 0] += 1
        guard let handler = handlers[message.name] else {
            replyHandler(nil, "Unknown message handler")
            return
        }
        handler.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
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
