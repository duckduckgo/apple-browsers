//
//  AutoconsentTabExtension.swift
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

import Navigation
import Foundation
import Combine
import WebKit
import BrowserServicesKit
import AutoconsentStats
import Common
import os.log

protocol AutoconsentUserScriptProvider {
    var autoconsentUserScript: UserScriptWithAutoconsent { get }
}
extension UserScripts: AutoconsentUserScriptProvider {}

final class AutoconsentTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private var userScriptCancellables = Set<AnyCancellable>()
    private let autoconsentStats: AutoconsentStatsCollecting
    private let featureFlagger: FeatureFlagger
    private let popupManagedSubject = PassthroughSubject<AutoconsentUserScript.AutoconsentDoneMessage, Never>()

    // Reload loop detection state
    private var lastHandledURL: String = ""
    private var lastHandledCMPName: String = ""
    private var reloadLoopDetected: Bool = false

    private(set) weak var autoconsentUserScript: UserScriptWithAutoconsent? {
        didSet {
            subscribeToUserScript()
        }
    }

    init(scriptsPublisher: some Publisher<some AutoconsentUserScriptProvider, Never>,
         autoconsentStats: AutoconsentStatsCollecting,
         featureFlagger: FeatureFlagger) {

        self.autoconsentStats = autoconsentStats
        self.featureFlagger = featureFlagger

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.autoconsentUserScript = scripts.autoconsentUserScript
            }
        }.store(in: &cancellables)
    }

    private func subscribeToUserScript() {
        userScriptCancellables.removeAll()
        guard let autoconsentUserScript = autoconsentUserScript as? AutoconsentUserScript else {
            return
        }

        // Set the tab extension reference on the user script
        autoconsentUserScript.tabExtension = self

        autoconsentUserScript.popupManagedPublisher
            .sink { [weak self] event in
                self?.handlePopupManaged(event)
                self?.popupManagedSubject.send(event)
            }
            .store(in: &userScriptCancellables)
    }

    private func handlePopupManaged(_ message: AutoconsentUserScript.AutoconsentDoneMessage) {
        guard featureFlagger.isFeatureOn(.newTabPageAutoconsentStats) else { return }

        Task {
            let durationInSeconds: TimeInterval = message.duration / 1000.0
            await autoconsentStats.recordAutoconsentAction(clicksMade: Int64(message.totalClicks), timeSpent: durationInSeconds)
        }
    }

    // MARK: - Reload Loop Detection

    /// Checks if the given URL matches the last handled URL and returns whether to disable autoAction
    /// - Parameter url: The current page URL
    /// - Returns: True if autoAction should be disabled (reload loop detected), false otherwise
    func shouldDisableAutoActionForReloadLoop(url: String) -> Bool {
        let urlMatches = urlsMatchIgnoringQuery(url, lastHandledURL)
        var result = false
        if !urlMatches {
            // Navigated to a different page, clear state
            clearReloadLoopState()
        } else if reloadLoopDetected {
            // prevent further reloads
            Logger.autoconsent.debug("Reload loop prevention: disabling autoAction for \(url)")
            result = true
        }
        return result
    }

    /// Compares two URL strings ignoring query parameters and fragments
    /// - Parameters:
    ///   - url1: First URL string
    ///   - url2: Second URL string
    /// - Returns: True if protocol, host, and path match, false otherwise
    private func urlsMatchIgnoringQuery(_ url1: String, _ url2: String) -> Bool {
        guard let parsedUrl1 = URL(string: url1),
              let parsedUrl2 = URL(string: url2) else {
            // If we can't parse URLs, fall back to exact string comparison
            return url1 == url2
        }

        return parsedUrl1.scheme == parsedUrl2.scheme &&
               parsedUrl1.host == parsedUrl2.host &&
               parsedUrl1.path == parsedUrl2.path
    }

    /// Records that a popup was found with the given CMP name
    /// - Parameters:
    ///   - cmpName: The name of the CMP that was detected
    ///   - url: The current page URL
    /// - Returns: True if a reload loop was detected (should fire pixel), false otherwise
    func recordPopupFound(cmpName: String, url: String) -> Bool {
        if cmpName == lastHandledCMPName && !reloadLoopDetected {
            // Same CMP detected on same URL after it was already handled - reload loop detected
            Logger.autoconsent.debug("Reload loop detected: CMP \(cmpName) on \(url)")
            reloadLoopDetected = true
            return true
        }
        return false
    }

    /// Stores the URL and CMP name after a popup was successfully handled
    /// - Parameters:
    ///   - url: The URL where the popup was handled
    ///   - cmpName: The name of the CMP that was handled
    ///   - isCosmetic: Whether this was a cosmetic rule (cosmetic rules don't trigger reload loops)
    func recordPopupHandled(url: String, cmpName: String, isCosmetic: Bool) {
        if isCosmetic {
            // Cosmetic rules can trigger on every page load and never cause reload loops
            Logger.autoconsent.debug("Cosmetic rule handled, not storing for reload loop detection")
            return
        }

        Logger.autoconsent.debug("Recording popup handled: CMP \(cmpName) on \(url)")
        lastHandledURL = url
        lastHandledCMPName = cmpName
        // Don't reset reloadLoopDetected here - it stays true if already set
    }

    /// Clears the reload loop detection state
    func clearReloadLoopState() {
        lastHandledURL = ""
        lastHandledCMPName = ""
        reloadLoopDetected = false
    }
}

protocol AutoconsentProtocol: AnyObject {
    var autoconsentUserScript: UserScriptWithAutoconsent? { get }
    var popupManagedPublisher: AnyPublisher<AutoconsentUserScript.AutoconsentDoneMessage, Never> { get }

    // Reload loop detection
    func shouldDisableAutoActionForReloadLoop(url: String) -> Bool
    func recordPopupFound(cmpName: String, url: String) -> Bool
    func recordPopupHandled(url: String, cmpName: String, isCosmetic: Bool)
    func clearReloadLoopState()
}

extension AutoconsentTabExtension: AutoconsentProtocol, TabExtension {
    func getPublicProtocol() -> AutoconsentProtocol { self }

    var popupManagedPublisher: AnyPublisher<AutoconsentUserScript.AutoconsentDoneMessage, Never> {
        popupManagedSubject.eraseToAnyPublisher()
    }
}

extension TabExtensions {
    var autoconsent: AutoconsentProtocol? { resolve(AutoconsentTabExtension.self) }
}
