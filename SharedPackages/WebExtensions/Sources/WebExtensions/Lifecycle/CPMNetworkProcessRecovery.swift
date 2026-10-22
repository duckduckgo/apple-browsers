//
//  CPMNetworkProcessRecovery.swift
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

import Combine
import Foundation
import os.log
import WebKit

/// WebKit can retain a loaded background view after replacing the Network process that hosted
/// its service worker. Restart only that background, preserving the context and its content scripts.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMNetworkProcessRecovery {
    private enum Selector {
        static let networkProcessIdentifier = NSSelectorFromString("_networkProcessIdentifier")
        static let killWebContentProcessAndResetState = NSSelectorFromString("_killWebContentProcessAndResetState")
    }

    typealias ProcessIdentifier = @MainActor (WKWebsiteDataStore) -> Int32?
    typealias Restart = @MainActor (WKWebView) -> Bool

    private final class Watch {
        weak var background: WKWebView?
        let dataStore: WKWebsiteDataStore
        var originalProcess: Int32?
        let isCurrent: @MainActor () -> Bool

        init(background: WKWebView, dataStore: WKWebsiteDataStore, originalProcess: Int32?, isCurrent: @escaping @MainActor () -> Bool) {
            self.background = background
            self.dataStore = dataStore
            self.originalProcess = originalProcess
            self.isCurrent = isCurrent
        }
    }

    private let isEnabled: @MainActor () -> Bool
    private let processIdentifier: ProcessIdentifier
    private let restart: Restart
    private let checkInterval: TimeInterval
    private let pixelFiring: WebExtensionPixelFiring
    // Old and new extension contexts can coexist while an embedded extension is upgraded.
    private var watches: [String: Watch] = [:]
    private var periodicCheck: Task<Void, Never>?
    private var featureFlagSubscription: AnyCancellable?

    init(isEnabled: @escaping @MainActor () -> Bool,
         featureFlagUpdates: AnyPublisher<Void, Never>? = nil,
         pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
         checkInterval: TimeInterval = 5,
         processIdentifier: @escaping ProcessIdentifier = CPMNetworkProcessRecovery.networkProcessIdentifier,
         restart: @escaping Restart = CPMNetworkProcessRecovery.restartBackground) {
        self.isEnabled = isEnabled
        self.checkInterval = checkInterval
        self.pixelFiring = pixelFiring
        self.processIdentifier = processIdentifier
        self.restart = restart
        featureFlagSubscription = featureFlagUpdates?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated {
                    self?.recoverIfNeeded()
                }
            }
    }

    deinit { periodicCheck?.cancel() }

    func watch(_ webView: WKWebView, identifier: String, isCurrent: @escaping @MainActor () -> Bool) {
        let dataStore = webView.configuration.websiteDataStore
        watches[identifier] = Watch(background: webView, dataStore: dataStore, originalProcess: processIdentifier(dataStore), isCurrent: isCurrent)
        startPeriodicCheckIfNeeded()
    }

    private func startPeriodicCheckIfNeeded() {
        guard periodicCheck == nil, !watches.isEmpty, isEnabled() else { return }
        let interval = checkInterval
        periodicCheck = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.recoverIfNeeded()
            }
        }
    }

    /// Also checked at main-frame HTTP(S) response policy, independently of the startup gate and diagnostics.
    @discardableResult
    func recoverIfNeeded() -> Bool {
        guard isEnabled() else {
            // Keep the baseline for re-enabling recovery on an already loaded background.
            stopPeriodicCheck()
            return false
        }
        startPeriodicCheckIfNeeded()
        var recovered = false
        // Restarting a background can synchronously replace a watch or unload another context.
        for (identifier, watch) in watches {
            guard watches[identifier] === watch else { continue }
            guard let background = watch.background, watch.isCurrent() else {
                removeWatch(identifier: identifier, matching: watch)
                continue
            }
            guard let current = processIdentifier(watch.dataStore), current > 0 else { continue }
            guard let originalProcess = watch.originalProcess, originalProcess > 0 else {
                watch.originalProcess = current
                continue
            }
            guard current != originalProcess else { continue }
            guard isEnabled() else {
                stopPeriodicCheck()
                return recovered
            }
            guard restart(background) else { continue }
            Logger.webExtensions.info("[CPM Recovery] Restarted embedded background after Network process replacement")
            removeWatch(identifier: identifier, matching: watch)
            recovered = true
            pixelFiring.fire(.cpmNetworkProcessRecoveryApplied)
        }
        return recovered
    }

    func stopWatching(identifier: String) {
        watches.removeValue(forKey: identifier)
        if watches.isEmpty { stopPeriodicCheck() }
    }

    private func removeWatch(identifier: String, matching watch: Watch) {
        guard watches[identifier] === watch else { return }
        stopWatching(identifier: identifier)
    }

    private func stopPeriodicCheck() {
        periodicCheck?.cancel()
        periodicCheck = nil
    }

    private static func networkProcessIdentifier(_ store: WKWebsiteDataStore) -> Int32? {
        guard store.responds(to: Selector.networkProcessIdentifier) else { return nil }
        return (store.value(forKey: NSStringFromSelector(Selector.networkProcessIdentifier)) as? NSNumber)?.int32Value
    }

    private static func restartBackground(_ webView: WKWebView) -> Bool {
        guard webView.responds(to: Selector.killWebContentProcessAndResetState) else { return false }
        webView.perform(Selector.killWebContentProcessAndResetState)
        return true
    }
}
