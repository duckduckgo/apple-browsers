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

/**
 * This Tab Extension is responsible for recovering from tab crashes.
 */
final class TabCrashRecoveryExtension {
    private weak var webView: WKWebView?
    private var content: Tab.TabContent?
    private var lastCrashedAt: Date?
    private let featureFlagger: FeatureFlagger
    private var webViewError: WKError?
    private let tabCrashErrorSubject = PassthroughSubject<TabCrashErrorPayload, Never>()
    private let firePixel: (PixelKitEvent, [String: String]) -> Void

    private var cancellables = Set<AnyCancellable>()

    enum Const {
        static let crashLoopInterval: TimeInterval = 5
    }

    init(
        featureFlagger: FeatureFlagger,
        contentPublisher: some Publisher<Tab.TabContent, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>,
        webViewErrorPublisher: some Publisher<WKError?, Never>,
        firePixel: @escaping (PixelKitEvent, [String: String]) -> Void = { event, parameters in
            PixelKit.fire(event, frequency: .dailyAndStandard, withAdditionalParameters: parameters)
        }
    ) {
        self.featureFlagger = featureFlagger
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
        }.store(in: &cancellables)
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

        Task {
#if APPSTORE
            let additionalParameters = [String: String]()
#else
            let additionalParameters = await SystemInfo.pixelParameters()
#endif
            firePixel(DebugEvent(GeneralPixel.webKitDidTerminate, error: error), additionalParameters)
        }

        if featureFlagger.isFeatureOn(.tabCrashRecovery) {
            guard let lastCrashedAt else {
                lastCrashedAt = Date()
                webView.reload()
                return
            }
            if Date().timeIntervalSince(lastCrashedAt) > Const.crashLoopInterval {
                self.lastCrashedAt = Date()
                webView.reload()
            } else {
                if case .url(let url, _, _) = content {
                    tabCrashErrorSubject.send(.init(error: error, url: url))
                }
            }
        } else {
            let isInternalUser = featureFlagger.internalUserDecider.isInternalUser == true

            if isInternalUser {
                webView.reload()
            } else {
                if case .url(let url, _, _) = content {
                    tabCrashErrorSubject.send(.init(error: error, url: url))
                }
            }
        }
    }
}

struct TabCrashErrorPayload {
    let error: WKError
    let url: URL
}

protocol TabCrashRecoveryExtensionProtocol: AnyObject, NavigationResponder {
    var tabCrashErrorPublisher: AnyPublisher<TabCrashErrorPayload, Never> { get }
}

extension TabCrashRecoveryExtension: TabCrashRecoveryExtensionProtocol, TabExtension {
    func getPublicProtocol() -> TabCrashRecoveryExtensionProtocol { self }

    var tabCrashErrorPublisher: AnyPublisher<TabCrashErrorPayload, Never> {
        tabCrashErrorSubject.eraseToAnyPublisher()
    }
}

extension TabExtensions {
    var tabCrashRecovery: TabCrashRecoveryExtensionProtocol? {
        resolve(TabCrashRecoveryExtension.self)
    }
}
