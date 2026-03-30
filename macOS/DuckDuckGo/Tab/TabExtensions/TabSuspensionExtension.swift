//
//  TabSuspensionExtension.swift
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
import PrivacyConfig
import WebKit

final class TabSuspensionExtension {

    private var cancellables = Set<AnyCancellable>()

    private weak var webView: WKWebView?
    private var tabContent: Tab.TabContent = .none
    private let isTabPinned: () -> Bool
    private let featureFlagger: FeatureFlagger

    var canBeSuspended: Bool {
        guard featureFlagger.isFeatureOn(.tabSuspension) else { return false }
        guard case let .url(url, _, _) = tabContent, !url.isDuckPlayer else { return false }
        guard !isTabPinned() else { return false }
        guard let webView else {
            return false
        }
        return !webView.audioState.isPlayingAudio
    }

    init(
        webViewPublisher: some Publisher<WKWebView, Never>,
        contentPublisher: some Publisher<Tab.TabContent, Never>,
        featureFlagger: FeatureFlagger,
        isTabPinned: @escaping () -> Bool
    ) {
        self.featureFlagger = featureFlagger
        self.isTabPinned = isTabPinned

        contentPublisher.sink { [weak self] content in
            self?.tabContent = content
        }.store(in: &cancellables)

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)
    }
}

protocol TabSuspensionExtensionProtocol: AnyObject {
    var canBeSuspended: Bool { get }
}

extension TabSuspensionExtension: TabSuspensionExtensionProtocol, TabExtension {
    func getPublicProtocol() -> TabSuspensionExtensionProtocol { self }
}

extension TabExtensions {
    var tabSuspension: TabSuspensionExtensionProtocol? {
        resolve(TabSuspensionExtension.self)
    }
}
