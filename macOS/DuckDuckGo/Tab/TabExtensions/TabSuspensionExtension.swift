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
import Navigation
import WebKit

protocol TabSuspensionUserScriptProvider {
    var formFocusUserScript: FormFocusUserScript { get }
    var webRTCUserScript: WebRTCUserScript { get }
}
extension UserScripts: TabSuspensionUserScriptProvider {}

final class TabSuspensionExtension {

    private var cancellables = Set<AnyCancellable>()
    private weak var formFocusScript: FormFocusUserScript?
    private weak var webRTCScript: WebRTCUserScript?

    @Published private var audioState: WKWebView.AudioState = .unmuted(isPlayingAudio: false)
    @Published private var hasActiveFormInput: Bool = false
    @Published private var hasActiveWebRTCConnection: Bool = false

    @Published private(set) var canBeSuspended: Bool = true

    init(
        scriptsPublisher: some Publisher<some TabSuspensionUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>
    ) {
        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.formFocusScript = scripts.formFocusUserScript
                self?.formFocusScript?.delegate = self
                self?.webRTCScript = scripts.webRTCUserScript
                self?.webRTCScript?.delegate = self
            }
        }.store(in: &cancellables)

        webViewPublisher.sink { [weak self] webView in
            guard let self else { return }
            webView.audioStatePublisher
                .sink { [weak self] state in
                    self?.audioState = state
                }
                .store(in: &self.cancellables)
        }.store(in: &cancellables)

        $audioState.map(\.isPlayingAudio)
            .combineLatest($hasActiveFormInput, $hasActiveWebRTCConnection)
            .map { isPlayingAudio, hasFormInput, hasWebRTC in
                !isPlayingAudio && !hasFormInput && !hasWebRTC
            }
            .assign(to: &$canBeSuspended)
    }
}

extension TabSuspensionExtension: FormFocusUserScriptDelegate {
    @MainActor
    func formFocusUserScript(_ script: FormFocusUserScript, didChangeFocus focused: Bool) {
        hasActiveFormInput = focused
    }
}

extension TabSuspensionExtension: WebRTCUserScriptDelegate {
    @MainActor
    func webRTCUserScript(_ script: WebRTCUserScript, didChangeConnectionActive active: Bool) {
        hasActiveWebRTCConnection = active
    }
}

extension TabSuspensionExtension: NavigationResponder {
    @MainActor
    func didCommit(_ navigation: Navigation) {
        hasActiveFormInput = false
        hasActiveWebRTCConnection = false
    }
}

protocol TabSuspensionExtensionProtocol: AnyObject, NavigationResponder {
    var canBeSuspended: Bool { get }
    var canBeSuspendedPublisher: AnyPublisher<Bool, Never> { get }
}

extension TabSuspensionExtension: TabSuspensionExtensionProtocol, TabExtension {
    func getPublicProtocol() -> TabSuspensionExtensionProtocol { self }

    var canBeSuspendedPublisher: AnyPublisher<Bool, Never> {
        $canBeSuspended.eraseToAnyPublisher()
    }
}

extension TabExtensions {
    var tabSuspension: TabSuspensionExtensionProtocol? {
        resolve(TabSuspensionExtension.self)
    }
}
