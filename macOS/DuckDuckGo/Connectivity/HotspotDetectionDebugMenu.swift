//
//  HotspotDetectionDebugMenu.swift
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

#if DEBUG && !APPSTORE
import AppKit
import Foundation
import Combine
import OSLog

final class HotspotDetectionDebugMenu: NSMenu {

    private let connectivityURLMenuItem = NSMenuItem(title: "")
    private let testsServerMenuItem = NSMenuItem(title: "Run Tests Server", action: #selector(toggleTestsServer))
    private let firefoxEndpointMenuItem = NSMenuItem(title: "Use Firefox Endpoint", action: #selector(useFirefoxEndpoint))
    private let testsServerSuccessMenuItem = NSMenuItem(title: "Local Tests Server (Success)", action: #selector(useTestsServerSuccess))
    private let testsServerHotspotMenuItem = NSMenuItem(title: "Local Tests Server (Hotspot)", action: #selector(useTestsServerHotspot))
    private let testsServerRedirectMenuItem = NSMenuItem(title: "Local Tests Server (Redirect to Hotspot)", action: #selector(useTestsServerRedirect))
    private let testsServerFailureMenuItem = NSMenuItem(title: "Local Tests Server (Failure)", action: #selector(useTestsServerFailure))
    private let customURLMenuItem = NSMenuItem(title: "Set Custom URL…", action: #selector(setCustomConnectivityURL))
    private let resetURLMenuItem = NSMenuItem(title: "Reset to Default", action: #selector(resetToDefaultURL))
    private var testsServerProcess: Process?
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(title: "")

        connectivityURLMenuItem.isEnabled = false

        buildItems {
            connectivityURLMenuItem
            NSMenuItem.separator()
            firefoxEndpointMenuItem.targetting(self)
            NSMenuItem.separator()
            testsServerSuccessMenuItem.targetting(self)
            testsServerHotspotMenuItem.targetting(self)
            testsServerRedirectMenuItem.targetting(self)
            testsServerFailureMenuItem.targetting(self)
            NSMenuItem.separator()
            customURLMenuItem.targetting(self)
            resetURLMenuItem.targetting(self)
            NSMenuItem.separator()
            testsServerMenuItem.targetting(self)
        }

        updateMenuItemsState()

        // Monitor tests server process
        NotificationCenter.default.publisher(for: Process.didTerminateNotification)
            .filter { [weak self] notification in
                notification.object as? Process === self?.testsServerProcess
            }
            .sink { [weak self] _ in
                self?.testsServerProcess = nil
                self?.updateMenuItemsState()
            }
            .store(in: &cancellables)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateMenuItemsState()
    }

    private func updateMenuItemsState() {
        let currentURL = HotspotDetectionDebugSettings.shared.connectivityCheckURL
        connectivityURLMenuItem.title = "Current: \(currentURL.absoluteString)"

        // Clear all checkmarks first
        firefoxEndpointMenuItem.state = .off
        testsServerSuccessMenuItem.state = .off
        testsServerHotspotMenuItem.state = .off
        testsServerRedirectMenuItem.state = .off
        testsServerFailureMenuItem.state = .off
        customURLMenuItem.state = .off

        // Set checkmark based on current URL
        if currentURL == HotspotDetectionDebugSettings.firefoxDetectPortalURL {
            firefoxEndpointMenuItem.state = .on
        } else if currentURL == HotspotDetectionDebugSettings.testsServerSuccessURL {
            testsServerSuccessMenuItem.state = .on
        } else if currentURL == HotspotDetectionDebugSettings.testsServerHotspotURL {
            testsServerHotspotMenuItem.state = .on
        } else if currentURL == HotspotDetectionDebugSettings.testsServerRedirectURL {
            testsServerRedirectMenuItem.state = .on
        } else if currentURL == HotspotDetectionDebugSettings.testsServerFailureURL {
            testsServerFailureMenuItem.state = .on
        } else {
            // Custom URL is selected
            customURLMenuItem.state = .on
        }

        if testsServerProcess?.isRunning == true {
            testsServerMenuItem.title = "Stop Tests Server [Running]"
        } else {
            testsServerMenuItem.title = "Run Tests Server"
        }
    }

    // MARK: - Connectivity URL Actions

    @objc private func useFirefoxEndpoint() {
        HotspotDetectionDebugSettings.shared.connectivityCheckURL = HotspotDetectionDebugSettings.firefoxDetectPortalURL
        updateMenuItemsState()
    }

    @objc private func useTestsServerSuccess() {
        ensureTestsServerRunning()
        HotspotDetectionDebugSettings.shared.connectivityCheckURL = HotspotDetectionDebugSettings.testsServerSuccessURL
        updateMenuItemsState()
    }

    @objc private func useTestsServerHotspot() {
        ensureTestsServerRunning()
        HotspotDetectionDebugSettings.shared.connectivityCheckURL = HotspotDetectionDebugSettings.testsServerHotspotURL
        updateMenuItemsState()
    }

    @objc private func useTestsServerRedirect() {
        ensureTestsServerRunning()
        HotspotDetectionDebugSettings.shared.connectivityCheckURL = HotspotDetectionDebugSettings.testsServerRedirectURL
        updateMenuItemsState()
    }

    @objc private func useTestsServerFailure() {
        ensureTestsServerRunning()
        HotspotDetectionDebugSettings.shared.connectivityCheckURL = HotspotDetectionDebugSettings.testsServerFailureURL
        updateMenuItemsState()
    }

    @objc private func setCustomConnectivityURL() {
        showCustomURLAlert { [weak self] value in
            guard let value = value, let url = URL(string: value), url.isValid else { return false }

            HotspotDetectionDebugSettings.shared.connectivityCheckURL = url
            self?.updateMenuItemsState()
            return true
        }
    }

    @objc private func resetToDefaultURL() {
        HotspotDetectionDebugSettings.shared.reset()
        updateMenuItemsState()
    }

    // MARK: - Tests Server Actions

    private func ensureTestsServerRunning() {
        if testsServerProcess?.isRunning != true {
            startTestsServer()
        }
    }

    @objc private func toggleTestsServer() {
        if testsServerProcess?.isRunning == true {
            stopTestsServer()
        } else {
            startTestsServer()
        }
    }

    private func startTestsServer() {
        guard testsServerProcess?.isRunning != true else { return }

        let process = Process()

        // Find tests-server binary in the main bundle
        guard let testsServerPath = Bundle.main.path(forResource: "tests-server", ofType: nil) else {
            Logger.general.error("tests-server binary not found in main bundle")
            showAlert(title: "Error", message: "tests-server binary not found in application bundle")
            return
        }

        process.executableURL = URL(fileURLWithPath: testsServerPath)
        process.arguments = []

        // Set working directory to Integration Tests Resources for file lookup
        if let integrationTestsResourcesPath = Bundle.main.path(forResource: "IntegrationTestsResources", ofType: nil) {
            process.currentDirectoryURL = URL(fileURLWithPath: integrationTestsResourcesPath)
        }

        do {
            try process.run()
            testsServerProcess = process
            updateMenuItemsState()
            Logger.general.info("tests-server started on localhost:8085")
        } catch {
            Logger.general.error("Failed to start tests-server: \(error)")
            showAlert(title: "Error", message: "Failed to start tests-server: \(error.localizedDescription)")
        }
    }

    private func stopTestsServer() {
        testsServerProcess?.terminate()
        testsServerProcess = nil
        updateMenuItemsState()
        Logger.general.info("tests-server stopped")
    }

    // MARK: - Helper Methods

    private func showCustomURLAlert(completion: @escaping (String?) -> Bool) {
        let alert = NSAlert()
        alert.messageText = "Set Custom Connectivity Check URL"
        alert.informativeText = "Enter the URL to use for connectivity checks:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = HotspotDetectionDebugSettings.shared.connectivityCheckURL.absoluteString
        alert.accessoryView = textField

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !completion(value) {
                showAlert(title: "Invalid URL", message: "Please enter a valid URL")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Debug Settings

final class HotspotDetectionDebugSettings: ObservableObject {
    static let shared = HotspotDetectionDebugSettings()

    static let firefoxDetectPortalURL = URL(string: "http://detectportal.firefox.com/success.txt")!
    static let testsServerSuccessURL = URL(string: "http://localhost:8085/?data=success")!
    static let testsServerHotspotURL = URL(string: "http://localhost:8085/?data=%3Chtml%3ESet%20endpoint%20to%20%3Cb%3ELocal%20Tests%20Server%20%28Success%29%3C/b%3E%20to%20simulate%20hotspot%20authorization%20completion%3C/html%3E")!
    static let testsServerRedirectURL = URL(string: "http://localhost:8085/?status=302&headers=Location%3Dhttp%253A//localhost%253A8085/%253Fdata%253D%25253Chtml%25253ESet%252520endpoint%252520to%252520%25253Cb%25253ELocal%252520Tests%252520Server%252520%252528Success%252529%25253C/b%25253E%252520to%252520simulate%252520hotspot%252520authorization%252520completion%25253C/html%25253E")!
    static let testsServerFailureURL = URL(string: "http://localhost:8085/?status=500")!

    @Published var connectivityCheckURL: URL = firefoxDetectPortalURL

    private init() {
        // Always start with Firefox endpoint, no persistence
        self.connectivityCheckURL = Self.firefoxDetectPortalURL
    }

    func reset() {
        connectivityCheckURL = Self.firefoxDetectPortalURL
    }
}
#endif
