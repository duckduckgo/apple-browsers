//
//  AIChatTabExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import DDGNavigation
import Foundation
import Combine
import FeatureFlags_macOS
import os.log
import Persistence
import PixelKit
import PrivacyConfig
import UserScript
import WebKit
import AIChat
import BrowserServicesKit

protocol AIChatUserScriptProvider {
    var aiChatUserScript: AIChatUserScript? { get }
    var duckAiNativeStorageUserScript: DuckAiNativeStorageUserScript? { get }
}
extension UserScripts: AIChatUserScriptProvider {}

final class AIChatTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private var userScriptCancellables = Set<AnyCancellable>()
    private let isLoadedInSidebar: Bool
    private let isTabBurner: Bool
    private let burnerMode: BurnerMode
    private weak var webView: WKWebView?
    private let featureDiscovery: FeatureDiscovery
    private let featureFlagger: FeatureFlagger
    private let bootstrapRefresher: DuckAiNativeStorageBootstrapScriptRefresher?
    private let fireModeStorageProvider: () -> DuckAiFireModeStorage
    private let attachmentPrivacyDisclosureProvider: () -> AttachmentPrivacyDisclosure
    private let preferencesStorage: AIChatPreferencesStorage
    private let pixelFiring: PixelFiring?

    /// Source of the tab's latest content, for telling how a navigation to Duck.ai started.
    private var latestContentSource: TabContent.URLSource?
    /// The URL of an address-bar suggestion the user just picked, so its navigation isn't counted as typed.
    private var addressBarSuggestionURL: URL?
    /// How a direct navigation started when it landed on another page first, such as a link wrapper
    /// like google.com/url, so that page's client redirect to Duck.ai still counts.
    private var viaForClientRedirect: AIChatDirectNavigationVia?
    /// Set when a page opened this tab for a user's link click (⌘-click, `target=_blank`): WebKit's
    /// first load in a new tab carries neither the click nor the page it came from.
    private var linkOpener: LinkOpener?
    private struct LinkOpener {
        let sourceURL: URL?
    }
    /// Set when the browser re-creates this tab from an earlier one (restore, reopen, duplicate):
    /// its first load looks the same as a lazy load, a suspension wake or a native open.
    private var pendingRecreationSource: AIChatConversationSource?

    private(set) weak var aiChatUserScript: AIChatUserScript? {
        didSet {
            subscribeToUserScript()
        }
    }

    init(scriptsPublisher: some Publisher<some AIChatUserScriptProvider, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>,
         contentPublisher: some Publisher<TabContent, Never>,
         isLoadedInSidebar: Bool,
         isTabBurner: Bool,
         burnerMode: BurnerMode = .regular,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = NSApp.delegateTyped.duckAiNativeStorageHandler,
         burnerDuckAiStorageRegistry: BurnerDuckAiStorageRegistry? = NSApp.delegateTyped.burnerDuckAiStorageRegistry,
         aiChatDebugURLSettings: (any KeyedStoring<AIChatDebugURLSettings>)? = nil,
         preferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.isLoadedInSidebar = isLoadedInSidebar
        self.preferencesStorage = preferencesStorage
        self.pixelFiring = pixelFiring
        self.isTabBurner = isTabBurner
        self.burnerMode = burnerMode
        self.featureDiscovery = featureDiscovery
        self.featureFlagger = featureFlagger
        let debugSettings: any KeyedStoring<AIChatDebugURLSettings> = if let aiChatDebugURLSettings { aiChatDebugURLSettings } else { UserDefaults.standard.keyedStoring() }
        self.fireModeStorageProvider = { [burnerMode, weak burnerDuckAiStorageRegistry] in
            .resolve(isFireMode: burnerMode.isBurner,
                     handler: burnerDuckAiStorageRegistry?.handler(for: burnerMode))
        }
        self.attachmentPrivacyDisclosureProvider = {
            AttachmentPrivacyDisclosure(
                store: NSApp.delegateTyped.attachmentPrivacyDisclosureStore,
                webKeySource: duckAiNativeStorageHandler,
                featureFlagger: featureFlagger
            )
        }
        self.bootstrapRefresher = Self.makeBootstrapRefresher(
            featureFlagger: featureFlagger,
            handler: duckAiNativeStorageHandler,
            fireModeStorageProvider: self.fireModeStorageProvider,
            aiChatDebugURLSettings: debugSettings
        )
        pageContextRequestedPublisher = pageContextRequestedSubject.eraseToAnyPublisher()
        pageContextConsumedPublisher = pageContextConsumedSubject.eraseToAnyPublisher()
        pageContextRemovedPublisher = pageContextRemovedSubject.eraseToAnyPublisher()
        chatRestorationDataPublisher = chatRestorationDataSubject.eraseToAnyPublisher()

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
            self?.aiChatUserScript?.webView = webView
        }.store(in: &cancellables)

        contentPublisher.sink { [weak self] content in
            self?.latestContentSource = Self.navigationSource(of: content)
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.aiChatUserScript = scripts.aiChatUserScript
                self?.aiChatUserScript?.webView = self?.webView
                if let isTabBurner = self?.isTabBurner {
                    self?.aiChatUserScript?.handler.isFireWindowProvider = { isTabBurner }
                }
                self?.aiChatUserScript?.handler.isSidebarProvider = { isLoadedInSidebar }
                if let disclosureProvider = self?.attachmentPrivacyDisclosureProvider {
                    self?.aiChatUserScript?.handler.attachmentPrivacyDisclosureProvider = disclosureProvider
                }
                if let provider = self?.fireModeStorageProvider {
                    scripts.duckAiNativeStorageUserScript?.fireModeStorageProvider = provider
                }

                // Pass the handoff payload in case it was provided before the user script was loaded
                if let payload = self?.temporaryAIChatNativeHandoffData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
                    self?.temporaryAIChatNativeHandoffData = nil
                }

                if let data = self?.temporaryAIChatRestorationData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
                    self?.temporaryAIChatRestorationData = nil
                }

                self?.applyBufferedDirectNavigationFallback()

                if let prompt = self?.temporaryAIChatNativePrompt {
                    self?.aiChatUserScript?.handler.submitAIChatNativePrompt(prompt)
                    self?.temporaryAIChatNativePrompt = nil
                }

                if let pageContext = self?.temporaryPageContext {
                    /// See the comment in `self.submitAIChatPageContext` for the explanation of why we're calling user script twice.
                    self?.aiChatUserScript?.handler.messageHandling.setData(pageContext, forMessageType: .pageContext)
                    self?.aiChatUserScript?.handler.submitAIChatPageContext(pageContext)
                    self?.temporaryPageContext = nil
                }

                if let selections = self?.temporarySelectionContexts, !selections.isEmpty {
                    selections.forEach {
                        self?.aiChatUserScript?.handler.messageHandling.appendSelectionContext($0)
                        self?.aiChatUserScript?.handler.submitAIChatSelectionContext($0)
                    }
                    self?.temporarySelectionContexts = []
                }

                if self?.temporaryOpenSettingsRequest == true {
                    self?.aiChatUserScript?.requestOpenSettingsAction()
                    self?.temporaryOpenSettingsRequest = false
                }
            }
        }.store(in: &cancellables)
    }

    private func subscribeToUserScript() {
        userScriptCancellables.removeAll()
        guard let aiChatUserScript else {
            return
        }

        aiChatUserScript.handler.pageContextRequestedPublisher
            .sink { [weak self] _ in
                self?.pageContextRequestedSubject.send()
            }
            .store(in: &userScriptCancellables)

        aiChatUserScript.handler.pageContextConsumedPublisher
            .sink { [weak self] _ in
                self?.pageContextConsumedSubject.send()
            }
            .store(in: &userScriptCancellables)

        aiChatUserScript.handler.pageContextRemovedPublisher
            .sink { [weak self] _ in
                self?.pageContextRemovedSubject.send()
            }
            .store(in: &userScriptCancellables)

        aiChatUserScript.handler.chatRestorationDataPublisher
            .sink { [weak self] data in
                self?.chatRestorationDataSubject.send(data)
            }
            .store(in: &userScriptCancellables)
    }

    private let pageContextRequestedSubject = PassthroughSubject<Void, Never>()
    let pageContextRequestedPublisher: AnyPublisher<Void, Never>

    private let pageContextConsumedSubject = PassthroughSubject<Void, Never>()
    let pageContextConsumedPublisher: AnyPublisher<Void, Never>

    private let pageContextRemovedSubject = PassthroughSubject<Void, Never>()
    let pageContextRemovedPublisher: AnyPublisher<Void, Never>

    private let chatRestorationDataSubject = PassthroughSubject<AIChatRestorationData?, Never>()
    let chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never>

    private var temporaryAIChatNativeHandoffData: AIChatPayload?
    func setAIChatNativeHandoffData(payload: AIChatPayload) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatNativeHandoffData = payload
            return
        }

        aiChatUserScript.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
    }

    private var temporaryAIChatRestorationData: AIChatRestorationData?
    func setAIChatRestorationData(_ data: AIChatRestorationData?) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatRestorationData = data
            return
        }

        aiChatUserScript.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
    }

    private var temporaryAIChatNativePrompt: AIChatNativePrompt?
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatNativePrompt = prompt
            return
        }

        aiChatUserScript.handler.submitAIChatNativePrompt(prompt)
    }

    private var temporaryDirectNavigationFallback: AIChatConversationSource?
    private func setDirectNavigationFallback(_ source: AIChatConversationSource) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the fallback and set when ready
            temporaryDirectNavigationFallback = source
            return
        }
        aiChatUserScript.handler.directNavigationFallback = source
    }

    private func applyBufferedDirectNavigationFallback() {
        guard let fallback = temporaryDirectNavigationFallback else { return }
        aiChatUserScript?.handler.directNavigationFallback = fallback
        temporaryDirectNavigationFallback = nil
    }

    func noteAddressBarSuggestionNavigation(to url: URL) {
        addressBarSuggestionURL = url
    }

    func noteOpenedForLink(from sourceURL: URL?) {
        linkOpener = LinkOpener(sourceURL: sourceURL)
    }

    func noteRecreated(as source: AIChatConversationSource) {
        pendingRecreationSource = source
    }

    /// Many surfaces open duck.ai as plain `.url` content, so both carry the navigation's source.
    private static func navigationSource(of content: TabContent) -> TabContent.URLSource? {
        switch content {
        case .url(_, credential: _, source: let source), .aiChat(_, source: let source):
            source
        default:
            nil
        }
    }

    private var temporaryOpenSettingsRequest = false
    func requestOpenSettings() {
        guard let aiChatUserScript else {
            // User script not yet loaded — apply when it becomes available
            temporaryOpenSettingsRequest = true
            return
        }
        aiChatUserScript.requestOpenSettingsAction()
    }

    private var temporaryPageContext: AIChatPageContextData?
    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?) {
        // Page Context functionality is only for the sidebar.
        guard isLoadedInSidebar else {
            return
        }

        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryPageContext = pageContext
            return
        }

        ///
        /// We're both making the data available for `getAIChatPageContext` (by storing it in the page context handler)
        /// and calling `submitAIChatPageContext`, because when sidebar is just presented, it's not ready to receive
        /// `submitAIChatPageContext` and will call `getAIChatPageContext` at a later time (when fully initialized).
        /// After that it will exclusively use `submitAIChatPageContext`.
        ///
        /// This can be optimized later to only call one function, depending on whether `getAIChatPageContext`
        /// was received by this user script.
        ///
        aiChatUserScript.handler.messageHandling.setData(pageContext, forMessageType: .pageContext)
        aiChatUserScript.handler.submitAIChatPageContext(pageContext)
    }

    private var temporarySelectionContexts: [AIChatSelectionContextData] = []
    func submitAIChatSelectionContext(_ selection: AIChatSelectionContextData) {
        // Selection context, like page context, is only for the sidebar.
        guard isLoadedInSidebar else {
            return
        }

        guard let aiChatUserScript else {
            // User script not yet loaded — buffer and flush in order once it is.
            temporarySelectionContexts.append(selection)
            return
        }

        // Store for the `getAIChatSelectionContext` pull (covers the FE-not-ready-for-push race),
        // then push for the already-live case. Mirrors `submitAIChatPageContext`.
        aiChatUserScript.handler.messageHandling.appendSelectionContext(selection)
        aiChatUserScript.handler.submitAIChatSelectionContext(selection)
    }
}

extension AIChatTabExtension: NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        refreshNativeStorageBootstrapIfNeeded(for: navigationAction)

        // Only handle sidebar, user-initiated, cross-document navigations; otherwise let them proceed normally
        guard isLoadedInSidebar,
              !navigationAction.navigationType.isSameDocumentNavigation,
              navigationAction.isUserInitiated
        else {
            return .next
        }

        // Downloads must stay in the sidebar webview: a redirect drops the download intent and blob: URLs are unresolvable elsewhere.
        if navigationAction.shouldDownload {
            return .next
        }

        // Allow-list: also let certain hosts navigate inside the sidebar (e.g., duck.ai)
        if navigationAction.url.isStandaloneDuckAIURL {
            return .next
        }

        // Allow internal iframe navigations (e.g. about:srcdoc created by duck.ai JS)
        if featureFlagger.isFeatureOn(.aiChatSidebarAboutSchemeNavigationFix),
           navigationAction.url.scheme == "about" {
            return .next
        }

        // For all other hosts, open in a new tab and cancel sidebar navigation
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else {
            return .next
        }

        let tabCollectionViewModel = parentWindowController.mainViewController.tabCollectionViewModel
        tabCollectionViewModel.insertOrAppendNewTab(.url(navigationAction.url, source: .link))
        return .cancel
    }

    func navigationDidFinish(_ navigation: Navigation) {
        if navigation.url.isDuckAIURL {
            featureDiscovery.setWasUsedBefore(.aiChat)
        }
    }

    func willStart(_ navigation: Navigation) {
        guard !isLoadedInSidebar,
              navigation.navigationAction.isForMainFrame,
              !navigation.navigationAction.navigationType.isSameDocumentNavigation else { return }

        let suggestionURL = addressBarSuggestionURL
        addressBarSuggestionURL = nil
        let inheritedVia = viaForClientRedirect
        viaForClientRedirect = nil
        let linkOpener = self.linkOpener
        self.linkOpener = nil

        if case .redirect(.client) = navigation.navigationAction.navigationType {
            navigation.duckAIDirectNavigationVia = inheritedVia
        } else if let linkOpener {
            navigation.duckAIDirectNavigationVia = Self.isDuckDuckGo(linkOpener.sourceURL) ? nil : .link
        } else {
            navigation.duckAIDirectNavigationVia = directNavigationVia(for: navigation.navigationAction, suggestionURL: suggestionURL)
        }
    }

    func didCommit(_ navigation: Navigation) {
        aiChatUserScript?.handler.resetConversationSourceForNewDocument()

        // Only the first commit may use it, so a later chat in this tab isn't labelled as re-created.
        let recreationSource = pendingRecreationSource
        pendingRecreationSource = nil

        guard navigation.isCurrent else { return }
        guard let via = navigation.duckAIDirectNavigationVia else {
            if let recreationSource, navigation.url.isDuckAIURL, !navigation.url.isDuckAIOpenedFromHomepage {
                setDirectNavigationFallback(recreationSource)
            }
            return
        }
        guard navigation.url.isDuckAIURL else {
            viaForClientRedirect = via
            return
        }
        guard !navigation.url.isDuckAIOpenedFromHomepage else { return }

        let isDuckAIEnabled = preferencesStorage.isAIFeaturesEnabled
        pixelFiring?.fire(AIChatPixel.aiChatDuckAIDirectNavigation(via: via,
                                                                   duckAIEnabled: isDuckAIEnabled,
                                                                   toggleEnabled: isDuckAIEnabled && preferencesStorage.showSearchAndDuckAIToggle),
                          frequency: .dailyAndCount)
        setDirectNavigationFallback(via.conversationSource)
    }

    /// Only navigations the user started toward a URL count; loads the browser starts itself (its own
    /// Duck.ai buttons, restoration, reloads) don't. A client redirect only carries on the navigation
    /// that led to its page.
    private func directNavigationVia(for action: NavigationAction, suggestionURL: URL?) -> AIChatDirectNavigationVia? {
        switch action.navigationType {
        case .custom(.userEnteredUrl):
            guard case .userEntered = latestContentSource else { return nil }
            return action.url == suggestionURL ? .suggestion : .typed
        case .custom(.bookmark):
            guard case .bookmark(isFavorite: true) = latestContentSource else { return .bookmark }
            return .favorite
        case .custom(.historyEntry):
            return .history
        case .custom(.appOpenUrl):
            return .external
        case .custom(.link), .linkActivated:
            return Self.isDuckDuckGo(action.sourceFrame.url) ? nil : .link
        case .other where action.isUserInitiated:
            return Self.isDuckDuckGo(action.sourceFrame.url) ? nil : .link
        default:
            return nil
        }
    }

    /// Duck.ai and duckduckgo.com link to Duck.ai themselves, which isn't a direct navigation.
    private static func isDuckDuckGo(_ sourceURL: URL?) -> Bool {
        guard let sourceURL else { return false }
        return sourceURL.isDuckAIURL || sourceURL.isDuckDuckGo
    }
}

private extension Navigation {
    private static var duckAIDirectNavigationViaKey: UInt8 = 0

    /// How the navigation started, classified when it starts and read when it commits.
    var duckAIDirectNavigationVia: AIChatDirectNavigationVia? {
        get {
            (objc_getAssociatedObject(self, UnsafeRawPointer(&Self.duckAIDirectNavigationViaKey)) as? String)
                .flatMap(AIChatDirectNavigationVia.init(rawValue:))
        }
        set {
            objc_setAssociatedObject(self, UnsafeRawPointer(&Self.duckAIDirectNavigationViaKey), newValue?.rawValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

// MARK: - Native Storage Bootstrap Refresh

extension AIChatTabExtension {

    @MainActor
    fileprivate func refreshNativeStorageBootstrapIfNeeded(for navigationAction: NavigationAction) {
        guard let bootstrapRefresher else {
            Logger.aiChat.debug("[NativeStorage] Skipping bootstrap refresh: refresher unavailable (flag off or handler nil)")
            return
        }
        guard !navigationAction.navigationType.isSameDocumentNavigation else { return }
        guard bootstrapRefresher.isInScope(url: navigationAction.url) else {
            Logger.aiChat.debug("[NativeStorage] Skipping bootstrap refresh: \(navigationAction.url.host ?? "<nil>") out of scope")
            return
        }
        guard let webView else {
            Logger.aiChat.debug("[NativeStorage] Skipping bootstrap refresh: webView not yet available")
            return
        }
        guard let userContentController = webView.configuration.userContentController as? UserContentController else {
            Logger.aiChat.debug("[NativeStorage] Skipping bootstrap refresh: user content controller cast failed")
            return
        }
        let staticScripts = userContentController.contentBlockingAssets?.wkUserScripts ?? []
        bootstrapRefresher.refresh(on: userContentController, staticScripts: staticScripts)
    }

    fileprivate static func makeBootstrapRefresher(
        featureFlagger: FeatureFlagger,
        handler: DuckAiNativeStorageHandling?,
        fireModeStorageProvider: @escaping () -> DuckAiFireModeStorage,
        aiChatDebugURLSettings: any KeyedStoring<AIChatDebugURLSettings>
    ) -> DuckAiNativeStorageBootstrapScriptRefresher? {
        guard featureFlagger.isFeatureOn(.aiChatNativeStorage), let handler else { return nil }
        var originRules: [HostnameMatchingRule] = [.exactOrSubdomain(hostname: "duck.ai")]
        if let customHostname = aiChatDebugURLSettings.customURLHostname {
            originRules.append(.exact(hostname: customHostname))
        }
        let refresher = DuckAiNativeStorageBootstrapScriptRefresher(handler: handler, originRules: originRules)
        refresher.fireModeStorageProvider = fireModeStorageProvider
        return refresher
    }
}

protocol AIChatProtocol: AnyObject, NavigationResponder {
    var aiChatUserScript: AIChatUserScript? { get }
    func setAIChatNativeHandoffData(payload: AIChatPayload)
    func setAIChatRestorationData(_ data: AIChatRestorationData?)
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt)
    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?)
    func submitAIChatSelectionContext(_ selection: AIChatSelectionContextData)
    func requestOpenSettings()
    func noteAddressBarSuggestionNavigation(to url: URL)
    func noteOpenedForLink(from sourceURL: URL?)
    func noteRecreated(as source: AIChatConversationSource)

    var pageContextRequestedPublisher: AnyPublisher<Void, Never> { get }
    var pageContextConsumedPublisher: AnyPublisher<Void, Never> { get }
    var pageContextRemovedPublisher: AnyPublisher<Void, Never> { get }
    var chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never> { get }
}

extension AIChatTabExtension: AIChatProtocol, TabExtension {
    func getPublicProtocol() -> AIChatProtocol { self }
}

extension TabExtensions {
    var aiChat: AIChatProtocol? { resolve(AIChatTabExtension.self) }
}
