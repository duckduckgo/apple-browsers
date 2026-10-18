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
    typealias ProcessIdentifier = @MainActor (WKWebView) -> Int32?
    typealias Restart = @MainActor (WKWebView) -> Bool

    private let isEnabled: @MainActor () -> Bool
    private let processIdentifier: ProcessIdentifier
    private let restart: Restart
    private let checkInterval: TimeInterval
    private weak var background: WKWebView?
    private var identifier: String?
    private var originalProcess: Int32?
    private var isCurrent: @MainActor () -> Bool = { false }
    private var periodicCheck: Task<Void, Never>?
    private var featureFlagSubscription: AnyCancellable?

    init(isEnabled: @escaping @MainActor () -> Bool,
         featureFlagUpdates: AnyPublisher<Void, Never>? = nil,
         checkInterval: TimeInterval = 1,
         processIdentifier: @escaping ProcessIdentifier = CPMNetworkProcessRecovery.networkProcessIdentifier,
         restart: @escaping Restart = CPMNetworkProcessRecovery.restartBackground) {
        self.isEnabled = isEnabled
        self.checkInterval = checkInterval
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
        stop()
        background = webView
        self.identifier = identifier
        originalProcess = processIdentifier(webView)
        self.isCurrent = isCurrent
        startPeriodicCheckIfNeeded()
    }

    private func startPeriodicCheckIfNeeded() {
        guard periodicCheck == nil, background != nil, isEnabled() else { return }
        let interval = checkInterval
        periodicCheck = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.recoverIfNeeded()
            }
        }
    }

    /// Also checked before navigation, without depending on the startup gate or diagnostics flags.
    @discardableResult
    func recoverIfNeeded() -> Bool {
        guard isEnabled() else {
            // Keep the baseline for re-enabling recovery on an already loaded background.
            stopPeriodicCheck()
            return false
        }
        guard let background, isCurrent() else {
            stop()
            return false
        }
        startPeriodicCheckIfNeeded()
        guard let current = processIdentifier(background), current > 0 else { return false }
        guard let originalProcess, originalProcess > 0 else {
            originalProcess = current
            return false
        }
        guard current != originalProcess, restart(background) else { return false }
        Logger.webExtensions.info("[CPM Recovery] Restarted embedded background after Network process replacement")
        if self.background === background { stop() }
        return true
    }

    func stopWatching(identifier: String) {
        guard self.identifier == identifier else { return }
        stop()
    }

    private func stopPeriodicCheck() {
        periodicCheck?.cancel()
        periodicCheck = nil
    }

    private func stop() {
        stopPeriodicCheck()
        background = nil
        identifier = nil
        originalProcess = nil
        isCurrent = { false }
    }

    private static func networkProcessIdentifier(_ webView: WKWebView) -> Int32? {
        let store = webView.configuration.websiteDataStore
        guard store.responds(to: NSSelectorFromString("_networkProcessIdentifier")) else { return nil }
        return (store.value(forKey: "_networkProcessIdentifier") as? NSNumber)?.int32Value
    }

    private static func restartBackground(_ webView: WKWebView) -> Bool {
        let selector = NSSelectorFromString("_killWebContentProcessAndResetState")
        guard webView.responds(to: selector) else { return false }
        webView.perform(selector)
        return true
    }
}
