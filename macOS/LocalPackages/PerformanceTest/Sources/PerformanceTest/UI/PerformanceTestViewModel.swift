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

@MainActor
final class PerformanceTestViewModel: ObservableObject {
    @Published var currentURL: URL?
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var currentIteration = 0
    @Published var totalIterations = PerformanceTestConstants.TestConfig.defaultIterations
    @Published var testResults: PerformanceTestResults?
    @Published var isCancelled = false
    @Published var selectedIterations = PerformanceTestConstants.TestConfig.defaultIterations
    @Published var selectedStatView = PerformanceTestConstants.StatViews.median

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
            timeout: PerformanceTestConstants.TestConfig.testTimeout
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
