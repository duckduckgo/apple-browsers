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
    private let newTabPageLoadMetrics: NewTabPageLoadMetrics
    private var cancellables: Set<AnyCancellable> = []

    /// `userInfo` key on `.newTabPageWebViewDidAppear` carrying whether the appearing NTP belongs to
    /// a Fire Window, so pixel senders can tag Fire Window impressions/submissions distinctly.
    static let isFireWindowUserInfoKey = "isFireWindow"

    init(featureFlagger: FeatureFlagger, actionsManager: NewTabPageActionsManager, activeRemoteMessageModel: ActiveRemoteMessageModel, newTabPageLoadMetrics: NewTabPageLoadMetrics, burnerMode: BurnerMode = .regular) {
        newTabPageUserScript = NewTabPageUserScript()
        actionsManager.registerUserScript(newTabPageUserScript)

        let configuration = WKWebViewConfiguration()
        configuration.applyNewTabPageWebViewConfiguration(with: featureFlagger, newTabPageUserScript: newTabPageUserScript, burnerMode: burnerMode)
        webView = WebView(frame: .zero, configuration: configuration, featureFlagger: featureFlagger)

        self.newTabPageLoadMetrics = newTabPageLoadMetrics

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: URL.newtab))
        newTabPageUserScript.webView = webView

        webView.publisher(for: \.window)
            .map { $0 != nil }
            .sink { [weak activeRemoteMessageModel] isOnScreen in
                // Not meaningful for Fire Windows: this tracks the very first NTP a new user sees.
                if isOnScreen && !burnerMode.isBurner && OnboardingActionsManager.isOnboardingFinished && AppDelegate.isNewUser {
                    PixelKit.fire(GeneralPixel.newTabInitial, frequency: .legacyInitial)
                }
                activeRemoteMessageModel?.isViewOnScreen = isOnScreen
                if isOnScreen {
                    NotificationCenter.default.post(
                        name: .newTabPageWebViewDidAppear,
                        object: nil,
                        userInfo: [Self.isFireWindowUserInfoKey: burnerMode.isBurner]
                    )
                }
            }
            .store(in: &cancellables)

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
    }
}

extension Notification.Name {
    static var newTabPageWebViewDidAppear = Notification.Name("newTabPageWebViewDidAppear")
}

extension WKWebViewConfiguration {

    @MainActor
    func applyNewTabPageWebViewConfiguration(with featureFlagger: FeatureFlagger, newTabPageUserScript: NewTabPageUserScript, burnerMode: BurnerMode = .regular) {
        if urlSchemeHandler(forURLScheme: URL.NavigationalScheme.duck.rawValue) == nil {
            setURLSchemeHandler(
                DuckURLSchemeHandler(featureFlagger: featureFlagger, isNTPSpecialPageSupported: true),
                forURLScheme: URL.NavigationalScheme.duck.rawValue
            )
        }
        // Fire Window NTP: use the Fire Window's isolated, non-persistent data store so the omnibar's
        // search/Duck.ai session never touches regular browsing data. The store already carries its
        // `fireWindowSession` tag (set by WindowsManager at window creation), which NewTabPageConfigurationClient
        // uses to detect burner webViews without depending on `webView.window` being attached yet.
        if case .burner(let websiteDataStore) = burnerMode {
            self.websiteDataStore = websiteDataStore
        }
        preferences[.developerExtrasEnabled] = true
        self.userContentController = NewTabPageUserContentController(newTabPageUserScript: newTabPageUserScript)
     }
}
