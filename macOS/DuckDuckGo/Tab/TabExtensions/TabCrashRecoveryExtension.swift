//
//  TabCrashRecoveryExtension.swift
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

import BrowserServicesKit
import Combine
import Foundation
import Navigation
import WebKit
import PixelKit

/// This enum describes the type of crash that can be reported by the extension,
/// judging by the time since the last occurrence.
enum TabCrashType: Equatable {
    /// A single, standalone crash, occurring at least `TabCrashRecoveryExtension.Const.crashLoopInterval`
    /// since the last crash.
    case single

    /// A crash occurring within `TabCrashRecoveryExtension.Const.crashLoopInterval` since the last crash,
    /// indicating a possible crash loop.
    case crashLoop
}

/// This protocol defines API for detecting tab crash loops.
protocol TabCrashLoopDetecting {
    /// Returns the current date - useful for unit testing.
    func currentDate() -> Date

    /// Returns `true` if a crash occurring at `crashTimestamp`
    /// happened early enough since the optional `lastCrashTimestamp`,
    /// indicating a possible crash loop.
    func isCrashLoop(for crashTimestamp: Date, lastCrashTimestamp: Date?) -> Bool
}

struct TabCrashLoopDetector: TabCrashLoopDetecting {
    func currentDate() -> Date { Date() }

    func isCrashLoop(for crashTimestamp: Date, lastCrashTimestamp: Date?) -> Bool {
        guard let lastCrashTimestamp else {
            return false
        }
        return crashTimestamp.timeIntervalSince(lastCrashTimestamp) < Const.crashLoopInterval
    }

    enum Const {
        static let crashLoopInterval: TimeInterval = 5
    }
}

/// This struct describes a tab crash data to be displayed in a tab's error page.
struct TabCrashErrorPayload {
    /// WebKit error related to the crash – used by Tab instance to decide the error page type to be displayed.
    let error: WKError
    /// URL that the crash occured for.
    let url: URL
}

/// This Tab Extension is responsible for recovering from tab crashes.
final class TabCrashRecoveryExtension {
    private weak var webView: WKWebView?
    private var content: Tab.TabContent?
    private var lastCrashedAt: Date?
    private var webViewError: WKError?
    private let tabDidCrashSubject = PassthroughSubject<TabCrashType, Never>()
    private let tabCrashErrorPayloadSubject = PassthroughSubject<TabCrashErrorPayload, Never>()

    private let featureFlagger: FeatureFlagger
    private let crashLoopDetector: TabCrashLoopDetecting
    private let firePixel: (PixelKitEvent, [String: String]) -> Void

    private var cancellables = Set<AnyCancellable>()

    init(
        featureFlagger: FeatureFlagger,
        contentPublisher: some Publisher<Tab.TabContent, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>,
        webViewErrorPublisher: some Publisher<WKError?, Never>,
        crashLoopDetector: TabCrashLoopDetecting = TabCrashLoopDetector(),
        firePixel: @escaping (PixelKitEvent, [String: String]) -> Void = { event, parameters in
            PixelKit.fire(event, frequency: .dailyAndStandard, withAdditionalParameters: parameters)
        }
    ) {
        self.featureFlagger = featureFlagger
        self.crashLoopDetector = crashLoopDetector
        self.firePixel = firePixel

        contentPublisher.sink { [weak self] content in
            self?.content = content
        }
        .store(in: &cancellables)

        webViewErrorPublisher.sink { [weak self] webViewError in
            self?.webViewError = webViewError
        }
        .store(in: &cancellables)

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }
        .store(in: &cancellables)
    }
}

extension TabCrashRecoveryExtension: NavigationResponder {

    func webContentProcessDidTerminate(with reason: WKProcessTerminationReason?) {
        guard let webView, (webViewError?.code.rawValue ?? WKError.Code.unknown.rawValue) != WKError.Code.webContentProcessTerminated.rawValue else {
            return
        }

        let terminationReason = reason?.rawValue ?? -1

        let error = WKError(.webContentProcessTerminated, userInfo: [
            WKProcessTerminationReason.userInfoKey: terminationReason,
            NSLocalizedDescriptionKey: UserText.webProcessCrashPageMessage,
            NSUnderlyingErrorKey: NSError(domain: WKErrorDomain, code: terminationReason)
        ])

        attemptTabCrashRecovery(for: error, in: webView)

        Task.detached(priority: .utility) {
#if APPSTORE
            let additionalParameters = [String: String]()
#else
            let additionalParameters = await SystemInfo.pixelParameters()
#endif
            self.firePixel(DebugEvent(GeneralPixel.webKitDidTerminate, error: error), additionalParameters)
        }
    }

    private func attemptTabCrashRecovery(for error: WKError, in webView: WKWebView) {
        let shouldAutoReload: Bool

        if featureFlagger.isFeatureOn(.tabCrashRecovery) {
            let crashTimestamp = crashLoopDetector.currentDate()
            let isCrashLoop = crashLoopDetector.isCrashLoop(for: crashTimestamp, lastCrashTimestamp: lastCrashedAt)
            tabDidCrashSubject.send(isCrashLoop ? .crashLoop : .single)
            lastCrashedAt = crashTimestamp

            if isCrashLoop {
                Task.detached(priority: .utility) {
                    self.firePixel(GeneralPixel.webKitTerminationLoop, [:])
                }
            }

            shouldAutoReload = !isCrashLoop
        } else {
            shouldAutoReload = featureFlagger.internalUserDecider.isInternalUser
        }

        handleTabCrash(error, in: webView, shouldAutoReload: shouldAutoReload)
    }

    private func handleTabCrash(_ error: WKError, in webView: WKWebView, shouldAutoReload: Bool) {
        if shouldAutoReload {
            webView.reload()
        } else if case .url(let url, _, _) = content {
            tabCrashErrorPayloadSubject.send(.init(error: error, url: url))
        }
    }
}

protocol TabCrashRecoveryExtensionProtocol: AnyObject, NavigationResponder {
    /// Publishes an event every time a tab crash occurs, in order for the tab item view
    /// to display the crash notification icon if needed.
    /// - Note: This is only valid for the tab crash recovery scenario.
    ///     Events won't be published if `tabCrashRecovery` feature flag is not set.
    var tabDidCrashPublisher: AnyPublisher<TabCrashType, Never> { get }

    /// Publishes events with tab crash data to be displayed in the tab.
    /// This publisher does not depend on `tabCrashRecovery` feature flag.
    var tabCrashErrorPayloadPublisher: AnyPublisher<TabCrashErrorPayload, Never> { get }
}

extension TabCrashRecoveryExtension: TabCrashRecoveryExtensionProtocol, TabExtension {
    func getPublicProtocol() -> TabCrashRecoveryExtensionProtocol { self }

    var tabDidCrashPublisher: AnyPublisher<TabCrashType, Never> {
        tabDidCrashSubject.eraseToAnyPublisher()
    }

    var tabCrashErrorPayloadPublisher: AnyPublisher<TabCrashErrorPayload, Never> {
        tabCrashErrorPayloadSubject.eraseToAnyPublisher()
    }
}

extension TabExtensions {
    var tabCrashRecovery: TabCrashRecoveryExtensionProtocol? {
        resolve(TabCrashRecoveryExtension.self)
    }
}
