//
//  PerformanceTestViewModel.swift
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
import UniformTypeIdentifiers
import os.log

@MainActor
final class PerformanceTestViewModel: ObservableObject {
    private let logger = Logger(
        subsystem: "com.duckduckgo.macos.browser.performancetest",
        category: "PerformanceTestViewModel"
    )
    @Published var currentURL: URL?
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var currentIteration = 0
    @Published var totalIterations = PerformanceTestConstants.TestConfig.defaultIterations
    @Published var comparisonResults: BrowserComparisonResults?
    @Published var currentBrowser: String = "" // "DuckDuckGo" or "Safari"
    @Published var browserProgress: String = "" // "1/2" or "2/2"
    @Published var isCancelled = false
    @Published var selectedStatView = PerformanceTestConstants.StatViews.median
    @Published var maxIterations = 30
    @Published var errorMessage: String?

    private let minIterations = 10

    private weak var webView: WKWebView?
    private var duckDuckGoTester: SitePerformanceTester?
    private var safariRunner: SafariTestExecuting?
    private let safariRunnerFactory: @MainActor (URL, Int, Int) -> SafariTestExecuting
    private let createNewTab: (() async -> WKWebView?)?
    private let closeTab: (() async -> Void)?
    private weak var browserWindow: NSWindow?
    private var overlayView: NSView?

    init(
        webView: WKWebView,
        safariRunnerFactory: (@MainActor (URL, Int, Int) -> SafariTestExecuting)? = nil,
        createNewTab: (() async -> WKWebView?)? = nil,
        closeTab: (() async -> Void)? = nil
    ) {
        self.webView = webView
        self.currentURL = webView.url
        self.browserWindow = webView.window
        self.createNewTab = createNewTab
        self.closeTab = closeTab
        self.duckDuckGoTester = SitePerformanceTester(
            webView: webView,
            createNewTab: createNewTab,
            closeTab: closeTab
        )
        self.safariRunnerFactory = safariRunnerFactory ?? { url, iterations, maxIterations in SafariTestRunner(url: url, iterations: iterations, maxIterations: maxIterations) }
        setupDuckDuckGoTester()
    }

    private func setupDuckDuckGoTester() {
        duckDuckGoTester?.progressHandler = { [weak self] iteration, total, status in
            Task { @MainActor [weak self] in
                // Account for warm-up iteration: hide first iteration from user
                if iteration == 1 {
                    // During warm-up iteration
                    self?.currentIteration = 0
                    self?.totalIterations = total - 1  // User-requested iterations only
                    self?.statusText = PerformanceTestConstants.Strings.warmingUp
                    self?.progress = 0.0
                } else {
                    // During actual test iterations (2, 3, 4, ..., total)
                    let userIteration = iteration - 1  // Convert to user's 1-based counting
                    let userTotal = total - 1  // User-requested total

                    self?.currentIteration = userIteration
                    self?.totalIterations = userTotal
                    self?.statusText = status
                    // Progress should reach 1.0 only after the last iteration completes
                    // Use (userIteration - 1) so that iteration N shows progress for N-1 completed
                    self?.progress = Double(userIteration - 1) / Double(userTotal)
               }
            }
        }

        duckDuckGoTester?.isCancelled = { [weak self] in
            self?.isCancelled ?? false
        }
    }

    private func setupSafariRunner() {
        safariRunner?.progressHandler = { [weak self] iteration, _, status in
            Task { @MainActor [weak self] in
                self?.currentIteration = iteration
                self?.statusText = status
            }
        }

        safariRunner?.isCancelled = { [weak self] in
            self?.isCancelled ?? false
        }
    }

    func runTest() async {
        guard let url = currentURL else { return }

        prepareTestEnvironment()
        showTestOverlay()

        let duckDuckGoResults = await runDuckDuckGoTest(url: url)
        let safariResults = await runSafariTest(url: url)

        hideTestOverlay()
        await cleanupAfterTests()
        createComparisonResults(url: url, ddgResults: duckDuckGoResults, safariResults: safariResults)

        finalizeTestRun()
    }

    private func prepareTestEnvironment() {
        recreateTesterIfNeeded()
        isRunning = true
        isCancelled = false
        progress = 0
        comparisonResults = nil
        errorMessage = nil
        currentBrowser = ""
        browserProgress = ""
        currentIteration = 0
        statusText = ""
    }

    private func recreateTesterIfNeeded() {
        guard duckDuckGoTester == nil, let wv = webView else { return }

        duckDuckGoTester = SitePerformanceTester(
            webView: wv,
            createNewTab: createNewTab,
            closeTab: closeTab
        )
        setupDuckDuckGoTester()
    }

    private func runDuckDuckGoTest(url: URL) async -> PerformanceTestResults? {
        guard !isCancelled else { return nil }

        currentBrowser = "DuckDuckGo"
        browserProgress = "1/2"
        statusText = "Testing DuckDuckGo..."

        guard let tester = duckDuckGoTester else { return nil }

        let results = await tester.runPerformanceTest(
            url: url,
            iterations: minIterations,
            maxIterations: maxIterations,
            timeout: PerformanceTestConstants.TestConfig.testTimeout
        )
        duckDuckGoTester = nil
        return results
    }

    private func runSafariTest(url: URL) async -> PerformanceTestResults? {
        guard !isCancelled else { return nil }

        currentBrowser = "Safari"
        browserProgress = "2/2"
        statusText = "Testing Safari..."
        progress = 0
        currentIteration = 0

        let runner = safariRunnerFactory(url, minIterations, maxIterations)
        self.safariRunner = runner
        setupSafariRunner()

        do {
            let resultsPath = try await runner.runTest()
            let parser = SafariResultsParser()
            let results = try parser.parse(filePath: resultsPath)
            runner.cleanup()
            self.safariRunner = nil
            return results
        } catch {
            await handleSafariError(error, runner: runner)
            self.safariRunner = nil
            return nil
        }
    }

    private func handleSafariError(_ error: Error, runner: SafariTestExecuting) async {
        let errorMsg = "Safari test failed: \(error.localizedDescription)"
        logger.error("\(errorMsg)")
        statusText = errorMsg
        errorMessage = errorMsg
        runner.cleanup()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    private func cleanupAfterTests() async {
        guard let createNewTab = createNewTab, let closeTab = closeTab else {
            cleanupWithoutTabManagement()
            return
        }

        logger.debug("Closing old test tab before opening fresh tab to clean up test state")
        await closeTab()
        guard let newWebView = await createNewTab() else { return }
        webView = newWebView
        logger.debug("Created fresh tab after closing old test tab")
    }

    private func cleanupWithoutTabManagement() {
        logger.debug("No tab management available, clearing delegate to prevent retain cycles")
        webView?.navigationDelegate = nil
    }

    private func createComparisonResults(url: URL, ddgResults: PerformanceTestResults?, safariResults: PerformanceTestResults?) {
        guard let ddgResults = ddgResults, let safResults = safariResults else { return }

        logDataVerification(ddgResults: ddgResults, safariResults: safResults)

        self.comparisonResults = BrowserComparisonResults(
            url: url,
            duckDuckGoResults: ddgResults,
            safariResults: safResults,
            iterations: minIterations
        )
    }

    private func logDataVerification(ddgResults: PerformanceTestResults, safariResults: PerformanceTestResults) {
        logger.debug("=== Data Verification ===")
        logger.debug("DuckDuckGo loadComplete values: \(ddgResults.detailedMetrics.loadComplete.prefix(3))")
        logger.debug("Safari loadComplete values: \(safariResults.detailedMetrics.loadComplete.prefix(3))")
        logger.debug("DuckDuckGo fcp values: \(ddgResults.detailedMetrics.fcp.prefix(3))")
        logger.debug("Safari fcp values: \(safariResults.detailedMetrics.fcp.prefix(3))")
        logger.debug("DuckDuckGo ttfb values: \(ddgResults.detailedMetrics.ttfb.prefix(3))")
        logger.debug("Safari ttfb values: \(safariResults.detailedMetrics.ttfb.prefix(3))")
        logger.debug("=========================")
    }

    private func finalizeTestRun() {
        isRunning = false
        browserProgress = ""
        currentBrowser = ""
    }

    func cancelTest() {
        isCancelled = true
        hideTestOverlay()
    }

    func exportResults() {
        guard let results = comparisonResults else { return }
        guard let jsonData = results.exportToJSON() else {
            logger.error("Failed to generate JSON export data")
            return
        }

        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "performance-test-\(Date().timeIntervalSince1970).json"
        savePanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        savePanel.message = "Export performance test results to JSON"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            do {
                try jsonData.write(to: url)
                self.logger.info("Successfully exported results to \(url.path)")

                // Show in Finder
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.logger.error("Failed to write JSON file: \(error.localizedDescription)")
            }
        }
    }

    private func showTestOverlay() {
        guard let browserWindow = browserWindow,
              let contentView = browserWindow.contentView else { return }

        // Create overlay view
        let overlay = NSView(frame: contentView.bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(PerformanceTestConstants.Layout.overlayAlpha).cgColor
        overlay.autoresizingMask = [.width, .height]

        // Create message container
        let messageContainer = NSView()
        messageContainer.wantsLayer = true
        messageContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        messageContainer.layer?.cornerRadius = PerformanceTestConstants.Layout.cornerRadius
        messageContainer.layer?.masksToBounds = true

        // Create title label
        let titleLabel = NSTextField(labelWithString: PerformanceTestConstants.Strings.performanceTestInProgress)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.alignment = .center

        // Create message label
        let messageLabel = NSTextField(labelWithString: PerformanceTestConstants.Strings.pleaseWait)
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

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: PerformanceTestConstants.Layout.cornerRadius),
            messageLabel.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: messageContainer.trailingAnchor, constant: -20),
            messageLabel.bottomAnchor.constraint(equalTo: messageContainer.bottomAnchor, constant: -20),

            messageContainer.widthAnchor.constraint(equalToConstant: PerformanceTestConstants.Layout.overlayMessageWidth)
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
        self.overlayView = overlay
    }

    private func hideTestOverlay() {
        overlayView?.removeFromSuperview()
        overlayView = nil
    }
}
