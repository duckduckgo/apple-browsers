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
import WebKit

final class TabSuspensionExtension {

    private var cancellables = Set<AnyCancellable>()

    private var audioState: WKWebView.AudioState = .unmuted(isPlayingAudio: false)
    private var hasActiveFormInput: Bool = false // TODO: to be implemented
    private var hasActiveWebRTCConnection: Bool = false // TODO: to be implemented
    private var tabContent: Tab.TabContent = .none

    var canBeSuspended: Bool {
        guard case .url = tabContent else { return false }
        return !audioState.isPlayingAudio && !hasActiveFormInput && !hasActiveWebRTCConnection
    }

    init(
        webViewPublisher: some Publisher<WKWebView, Never>,
        contentPublisher: some Publisher<Tab.TabContent, Never>
    ) {
        contentPublisher.sink { [weak self] content in
            self?.tabContent = content
        }.store(in: &cancellables)

        webViewPublisher.sink { [weak self] webView in
            guard let self else { return }
            webView.audioStatePublisher
                .sink { [weak self] state in
                    self?.audioState = state
                }
                .store(in: &self.cancellables)
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
