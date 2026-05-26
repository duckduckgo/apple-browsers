//
//  TabViewControllerLongPressMenuExtension.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

import UIKit
import Core
import SafariServices
import WebKit
import History
import Common
import Combine
import DesignResourcesKitIcons

extension TabViewController {

    func buildLinkPreviewMenu(for url: URL, withProvided providedElements: [UIMenuElement]) -> UIMenu {
        let isFireTab = tabModel.fireTab
        let browsingModeParam = [PixelParameters.browsingMode: tabModel.pixelParamValue]
        Pixel.fire(pixel: .linkLongPressMenuShown, withAdditionalParameters: browsingModeParam)

        var sections = [UIMenuElement]()
        var tabActions = [UIMenuElement]()

        let newTabTitle = isFireTab ? UserText.actionNewFireTabForUrl : UserText.actionNewTabForUrl
        tabActions.append(UIAction(title: newTabTitle,
                                   image: DesignSystemImages.Glyphs.Size16.add) { [weak self] _ in
            self?.onNewTabAction(url: url)
        })

        tabActions.append(UIAction(title: UserText.actionNewBackgroundTabForUrl,
                                   image: DesignSystemImages.Glyphs.Size16.openIn) { [weak self] _ in
            self?.onBackgroundTabAction(url: url)
        })

        sections.append(UIMenu(title: "", options: .displayInline, children: tabActions))

        let fireModeCapability = FireModeCapability.create()
        if !isFireTab && fireModeCapability.isFireModeEnabled {
            let fireTabAction = UIAction(title: UserText.actionNewFireTabForUrl,
                                         image: DesignSystemImages.Glyphs.Size16.fireWindow) { [weak self] _ in
                self?.onFireTabAction(url: url)
            }
            sections.append(UIMenu(title: "", options: .displayInline, children: [fireTabAction]))
        }

        let utilityActions = [
            UIAction(title: UserText.actionCopy,
                     image: DesignSystemImages.Glyphs.Size16.copy) { [weak self] _ in
                self?.onCopyAction(forUrl: url)
            },
            UIAction(title: UserText.actionShare,
                     image: DesignSystemImages.Glyphs.Size16.shareApple) { [weak self] _ in
                guard let webView = self?.webView else { return }
                let shareSheetOrigin = Point(x: Int(webView.bounds.midX), y: Int(0))
                self?.onShareAction(forUrl: url, atPoint: shareSheetOrigin)
            }
        ]
        sections.append(UIMenu(title: "", options: .displayInline, children: utilityActions))

        return UIMenu(title: url.host?.droppingWwwPrefix() ?? "", children: sections + providedElements)
    }

    private func onNewTabAction(url: URL) {
        Pixel.fire(pixel: .linkLongPressNewTab, withAdditionalParameters: [
            PixelParameters.browsingMode: tabModel.pixelParamValue
        ])
        delegate?.tab(self,
                      didRequestNewTabForUrl: url,
                      openedByPage: false,
                      inheritingAttribution: adClickAttributionLogic.state)
    }

    private func onFireTabAction(url: URL) {
        Pixel.fire(pixel: .linkLongPressFireTab)
        delegate?.tab(self,
                      didRequestNewFireTabForUrl: url,
                      inheritingAttribution: adClickAttributionLogic.state)
    }

    private func onBackgroundTabAction(url: URL) {
        Pixel.fire(pixel: .linkLongPressBackgroundTab, withAdditionalParameters: [
            PixelParameters.browsingMode: tabModel.pixelParamValue
        ])
        delegate?.tab(self, didRequestNewBackgroundTabForUrl: url, inheritingAttribution: adClickAttributionLogic.state)
    }
    
    private func onOpenAction(forUrl url: URL) {
        if let webView = webView {
            webView.load(URLRequest.userInitiated(url))
        }
    }
    
    private func onShareAction(forUrl url: URL, atPoint point: Point?) {
        guard let webView = webView else { return }
        presentShareSheet(withItems: [url], fromView: webView, atPoint: point)
    }
}

extension TabViewController {

    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {

        guard let url = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }

        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: {
            return AppUserDefaults().longPressPreviews ? self.buildOpenLinkPreview(for: url) : nil
        }, actionProvider: { _ in
            // We don't use provided elements as they are not built with correct URL in case of AMP links
            return self.buildLinkPreviewMenu(for: url, withProvided: [])
        })

        completionHandler(config)
    }

    func webView(_ webView: WKWebView, contextMenuForElement elementInfo: WKContextMenuElementInfo,
                 willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating) {
        guard let url = elementInfo.linkURL else { return }
        load(url: url)
    }

    fileprivate func buildOpenLinkPreview(for url: URL) -> UIViewController? {
        let tab = Tab(link: Link(title: nil, url: url), fireTab: self.tabModel.fireTab)
        let tabController = TabViewController.loadFromStoryboard(
            model: tab,
            privacyConfigurationManager: privacyConfigurationManager,
            bookmarksDatabase: bookmarksDatabase,
            historyManager: historyManager,
            syncService: syncService,
            userScriptsDependencies: userScriptsDependencies,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            subscriptionDataReporter: subscriptionDataReporter,
            contextualOnboardingPresenter: contextualOnboardingPresenter,
            contextualOnboardingLogic: contextualOnboardingLogic,
            onboardingPixelReporter: onboardingPixelReporter,
            featureFlagger: featureFlagger,
            contentScopeExperimentManager: contentScopeExperimentsManager,
            textZoomCoordinator: textZoomCoordinator,
            autoconsentManagement: autoconsentManagement,
            websiteDataManager: websiteDataManager,
            fireproofing: fireproofing,
            favicons: favicons,
            tabInteractionStateSource: tabInteractionStateSource,
            specialErrorPageNavigationHandler: specialErrorPageNavigationHandler,
            featureDiscovery: featureDiscovery,
            keyValueStore: keyValueStore,
            daxDialogsManager: daxDialogsManager,
            aiChatSettings: aiChatSettings,
            productSurfaceTelemetry: productSurfaceTelemetry,
            privacyStats: privacyStats,
            voiceSearchHelper: voiceSearchHelper,
            darkReaderFeatureSettings: darkReaderFeatureSettings,
            autoplaySettings: autoplaySettings,
            adBlockingAvailability: adBlockingAvailability)

        tabController.isLinkPreview = true
        let configuration = WKWebViewConfiguration.nonPersistent()
        tabController.attachWebView(configuration: configuration, andLoadRequest: URLRequest.userInitiated(url), consumeCookies: false)
        tabController.loadViewIfNeeded()
        return tabController
    }

}
