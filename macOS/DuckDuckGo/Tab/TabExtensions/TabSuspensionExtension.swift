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
import Common
import Foundation
import Navigation
import PrivacyConfig
import UserScript
import WebKit

protocol TabSuspensionUserScriptProvider {
    var tabSuspensionScript: TabSuspensionUserScript { get }
}
extension UserScripts: TabSuspensionUserScriptProvider {}

/// This protocol encapsulates checks for tab suspension eligibility performed on a web view instance.
protocol TabSuspensionWebViewChecking: AnyObject {
    var isLoading: Bool { get }
    var isPlayingAudio: Bool { get }
    var isCapturingAudio: Bool { get }
    var isCapturingVideo: Bool { get }
    var isDisplayingPDF: Bool { get async }
}

extension WKWebView: TabSuspensionWebViewChecking {
    var isCapturingAudio: Bool {
        return microphoneState != .none
    }

    var isCapturingVideo: Bool {
        return cameraState != .none
    }

    var isDisplayingPDF: Bool {
        get async {
            return await mimeType == "application/pdf"
        }
    }
}

final class TabSuspensionExtension {

    enum SuspensionState: String {
        case never
        case sameURL
        case samePath
        case sameHostname
        case sameDomain
        case differentDomain
    }

    private var cancellables = Set<AnyCancellable>()

    private weak var webView: TabSuspensionWebViewChecking?
    private weak var tabSuspensionUserScript: TabSuspensionUserScript?
    private var tabContent: Tab.TabContent = .none
    private let tabID: TabIdentifier
    private let isTabPinned: () -> Bool
    private let aiChatSessionStore: AIChatSessionStoring
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let tld: TLD

    var hasVideoInPictureInPicture: Bool = false
    var isDisplayingPDF: Bool = false
    var lastSuspendedURL: URL?
    private(set) var pageReportsUnableToSuspend: Bool = false

    private var hasActiveAIChatSession: Bool {
        aiChatSessionStore.sessions[tabID] != nil
    }

    var lastSuspensionState: SuspensionState {
        switch (lastSuspendedURL, tabContent.urlForWebView) {
        case (nil, _):
            return .never
        case (.some(let a), .some(let b)) where a == b:
            return .sameURL
        case (.some(let a), .some(let b)) where a.trimmingQueryItemsAndFragment() == b.trimmingQueryItemsAndFragment():
            return .samePath
        case (.some(let a), .some(let b)) where a.host == b.host:
            return .sameHostname
        case (.some(let a), .some(let b)) where tld.eTLDplus1(a.host) != nil && tld.eTLDplus1(a.host) == tld.eTLDplus1(b.host):
            return .sameDomain
        default:
            return .differentDomain
        }
    }

    var canBeSuspended: Bool {

        // feature flag on
        guard featureFlagger.isFeatureOn(.tabSuspension) else { return false }

        // only URL tab content
        guard case let .url(url, _, _) = tabContent else { return false }

        // only HTTP/HTTPS (this skips Duck Player which is duck://)
        guard url.navigationalScheme?.isHypertextScheme == true else { return false }

        // skip Duck.ai
        guard !url.isDuckAIURL else { return false }

        // domain not in exceptions list
        guard privacyConfigurationManager.privacyConfig.isFeature(.tabSuspension, enabledForDomain: url.host) else { return false }

        // not pinned
        guard !isTabPinned() else { return false }

        // without active AI chat
        guard !hasActiveAIChatSession else { return false }

        guard let webView else { return false }

        // not currently loading
        guard !webView.isLoading else { return false }

        // not playing audio
        // NOTE: This doesn't take into account muted tabs (`webView.audioState.isMuted`). Tab muted state is not persisted by
        // state restoration, and a tab that was playing audio but was muted, would not be muted after restoration.
        // We're playing safe and not suspending such tabs (they would report `webView.isPlayingAudio` as `true` here).
        guard !webView.isPlayingAudio else { return false }

        // not capturing audio
        guard !webView.isCapturingAudio else { return false }

        // not capturing video
        guard !webView.isCapturingVideo else { return false }

        // not using picture in picture
        guard !hasVideoInPictureInPicture else { return false }

        // not displaying a PDF
        guard !isDisplayingPDF else { return false }

        // page doesn't report conditions preventing suspension
        guard !pageReportsUnableToSuspend else { return false }

        return true
    }

    init(
        tabID: TabIdentifier,
        webViewPublisher: some Publisher<TabSuspensionWebViewChecking, Never>,
        contentPublisher: some Publisher<Tab.TabContent, Never>,
        scriptsPublisher: some Publisher<some TabSuspensionUserScriptProvider, Never>,
        featureFlagger: FeatureFlagger,
        aiChatSessionStore: AIChatSessionStoring,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        tld: TLD,
        isTabPinned: @escaping () -> Bool
    ) {
        self.tabID = tabID
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.isTabPinned = isTabPinned
        self.aiChatSessionStore = aiChatSessionStore
        self.tld = tld

        contentPublisher.sink { [weak self] content in
            self?.tabContent = content
        }.store(in: &cancellables)

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.tabSuspensionUserScript = scripts.tabSuspensionScript
                self?.tabSuspensionUserScript?.delegate = self
            }
        }.store(in: &cancellables)
    }
}

protocol TabSuspensionExtensionProtocol: AnyObject, NavigationResponder {
    var canBeSuspended: Bool { get }
    var hasVideoInPictureInPicture: Bool { get set }
    var lastSuspensionState: TabSuspensionExtension.SuspensionState { get }
    var lastSuspendedURL: URL? { get set }
}

extension TabSuspensionExtension: TabSuspensionExtensionProtocol, TabExtension {
    func getPublicProtocol() -> TabSuspensionExtensionProtocol { self }
}

extension TabSuspensionExtension: NavigationResponder {
    @MainActor
    func didCommit(_ navigation: Navigation) {
        pageReportsUnableToSuspend = false
        isDisplayingPDF = false
    }

    @MainActor
    func navigationDidFinish(_ navigation: Navigation) {
        // This flag already gets reset in didCommit but let's repeat it here in case
        // there are automated 'focusin' events that happen at page load.
        // We're not interested in these as they aren't user-initiated.
        // The didCommit is still needed to handle websites that fail to load or get stuck loading.
        pageReportsUnableToSuspend = false

        guard let webView else { return }
        Task { @MainActor [weak self, weak webView] in
            let isPDF = await webView?.isDisplayingPDF ?? false
            self?.isDisplayingPDF = isPDF
        }
    }
}

extension TabSuspensionExtension: TabSuspensionUserScriptDelegate {
    @MainActor
    func tabSuspensionUserScript(_ script: TabSuspensionUserScript, didReceiveCanBeSuspended canBeSuspended: Bool) {
        pageReportsUnableToSuspend = !canBeSuspended
    }
}

extension TabExtensions {
    var tabSuspension: TabSuspensionExtensionProtocol? {
        resolve(TabSuspensionExtension.self)
    }
}
