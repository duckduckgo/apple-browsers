//
//  NewTabPageWebViewModel.swift
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

import Combine
import NewTabPage
import PixelKit
import PrivacyConfig
import UniformTypeIdentifiers
import WebKit

/**
 * This class manages a dedicated web view for displaying New Tab Page.
 *
 * It initializes NTP user script, the NTP-specific web view configuration
 * and then sets up a new web view with that configuration. It also serves
 * as a navigation delegate for the web view, blocking all navigations other than
 * to the New Tab Page.
 *
 * This class is inspired by `DBPUIViewModel`.
 */
@MainActor
final class NewTabPageWebViewModel: NSObject {
    let newTabPageUserScript: NewTabPageUserScript
    let webView: WebView
    private let activeRemoteMessageModel: ActiveRemoteMessageModel
    private let newTabPageLoadMetrics: NewTabPageLoadMetrics
    private var cancellables: Set<AnyCancellable> = []
    private var selectedTabID: String?
    private var remoteMessageImpression: RemoteMessageImpression?
    private var isRemoteMessageVisibilityCheckScheduled = false

    private struct RemoteMessageImpression: Equatable {
        let tabID: String
        let messageID: String
    }

    init(featureFlagger: FeatureFlagger, actionsManager: NewTabPageActionsManager, activeRemoteMessageModel: ActiveRemoteMessageModel, newTabPageLoadMetrics: NewTabPageLoadMetrics) {
        newTabPageUserScript = NewTabPageUserScript()
        actionsManager.registerUserScript(newTabPageUserScript)
        self.activeRemoteMessageModel = activeRemoteMessageModel

        let configuration = WKWebViewConfiguration()
        configuration.applyNewTabPageWebViewConfiguration(with: featureFlagger, newTabPageUserScript: newTabPageUserScript)
        webView = WebView(frame: .zero, configuration: configuration, featureFlagger: featureFlagger)

        self.newTabPageLoadMetrics = newTabPageLoadMetrics

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: URL.newtab))
        newTabPageUserScript.webView = webView

        webView.publisher(for: \.window)
            .map { $0 != nil }
            .sink { [weak self] isOnScreen in
                if isOnScreen && OnboardingActionsManager.isOnboardingFinished && AppDelegate.isNewUser {
                    PixelKit.fire(GeneralPixel.newTabInitial, frequency: .legacyInitial)
                }
                if isOnScreen {
                    NotificationCenter.default.post(name: .newTabPageWebViewDidAppear, object: nil)
                } else {
                    self?.remoteMessageImpression = nil
                }
                self?.scheduleRemoteMessageVisibilityCheck()
            }
            .store(in: &cancellables)

        activeRemoteMessageModel.$newTabPageRemoteMessage
            .sink { [weak self] _ in self?.scheduleRemoteMessageVisibilityCheck() }
            .store(in: &cancellables)

        let visibilityNotifications = [NSWindow.didChangeOcclusionStateNotification,
                                       NSWindow.didMiniaturizeNotification,
                                       NSWindow.didDeminiaturizeNotification,
                                       NSWindow.didBeginSheetNotification,
                                       NSWindow.didEndSheetNotification,
                                       NSApplication.didBecomeActiveNotification,
                                       NSApplication.didResignActiveNotification]
        for name in visibilityNotifications {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] notification in
                    guard let self else { return }
                    if let window = notification.object as? NSWindow, window !== webView.window { return }
                    if name == NSApplication.didResignActiveNotification {
                        remoteMessageImpression = nil
                    }
                    scheduleRemoteMessageVisibilityCheck()
                }
                .store(in: &cancellables)
        }

        NotificationCenter.default.publisher(for: .newTabPageSectionsAvailabilityDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.webView.reload()
            }
            .store(in: &cancellables)
    }

    func removeUserScripts() {
        if let controller = webView.configuration.userContentController as? NewTabPageUserContentController {
            controller.removeUserScripts()
        }
    }

    func updateRemoteMessageVisibility(selectedTabID: String?) {
        self.selectedTabID = selectedTabID
        if selectedTabID == nil {
            remoteMessageImpression = nil
        }
        scheduleRemoteMessageVisibilityCheck()
    }

    private func scheduleRemoteMessageVisibilityCheck() {
        guard !isRemoteMessageVisibilityCheckScheduled else { return }
        isRemoteMessageVisibilityCheckScheduled = true
        // Publishers can fire before their new value or the view hierarchy has settled.
        Task { @MainActor [weak self] in
            guard let self else { return }
            isRemoteMessageVisibilityCheckScheduled = false
            await reportRemoteMessageIfVisible()
        }
    }

    private func reportRemoteMessageIfVisible() async {
        guard let selectedTabID,
              NSApp.isActive,
              let window = webView.window,
              window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible),
              window.attachedSheet == nil,
              !webView.isHiddenOrHasHiddenAncestor, !webView.visibleRect.isEmpty,
              !webView.isLoading,
              let message = activeRemoteMessageModel.newTabPageRemoteMessage,
              activeRemoteMessageModel.isMessageSupported(message) else {
            remoteMessageImpression = nil
            return
        }
        let impression = RemoteMessageImpression(tabID: selectedTabID, messageID: message.id)
        guard remoteMessageImpression != impression else { return }
        remoteMessageImpression = impression
        await activeRemoteMessageModel.markRemoteMessageAsShown(for: .newTabPage)
    }
}

extension NewTabPageWebViewModel: WKUIDelegate {
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard let window = webView.window else {
            completionHandler(nil)
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = [.jpeg, .png, .webP, .pdf]
        openPanel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? openPanel.urls : nil)
        }
    }
}

extension NewTabPageWebViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url == .newtab ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        newTabPageLoadMetrics.onNTPDidPresent()
        scheduleRemoteMessageVisibilityCheck()
    }
}

extension Notification.Name {
    static var newTabPageWebViewDidAppear = Notification.Name("newTabPageWebViewDidAppear")
}

extension WKWebViewConfiguration {

    @MainActor
    func applyNewTabPageWebViewConfiguration(with featureFlagger: FeatureFlagger, newTabPageUserScript: NewTabPageUserScript) {
        if urlSchemeHandler(forURLScheme: URL.NavigationalScheme.duck.rawValue) == nil {
            setURLSchemeHandler(
                DuckURLSchemeHandler(featureFlagger: featureFlagger, isNTPSpecialPageSupported: true),
                forURLScheme: URL.NavigationalScheme.duck.rawValue
            )
        }
        preferences[.developerExtrasEnabled] = true
        self.userContentController = NewTabPageUserContentController(newTabPageUserScript: newTabPageUserScript)
     }
}
