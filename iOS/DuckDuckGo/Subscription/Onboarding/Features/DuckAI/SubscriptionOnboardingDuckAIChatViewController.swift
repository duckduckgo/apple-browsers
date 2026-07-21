//
//  SubscriptionOnboardingDuckAIChatViewController.swift
//  DuckDuckGo
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

import UIKit
import Combine
import AIChat
import BrowserServicesKit
import Core

/// Post-subscription onboarding Duck.ai chat, presented as a self-contained full-screen modal.
///
/// Reuses the production contextual-chat surface — `AIChatContextualWebViewController` + `AIChatContextualUTIHost`
/// — with page context turned off: a native `UnifiedToggleInput` bar bound to a live Duck.ai web chat, so the
/// user's prompts push into the already-loaded page (no reload). Subscription tier resolves through the standard
/// `UserScripts` bundle (`SubscriptionUserScript`) built from the content-blocking pipeline; the onboarding-selected
/// model is applied on appear.
///
/// The debug host wires this today via `SubscriptionOnboardingSectionDelegate.launchDuckAIChat(modelID:)`; a
/// shipping flow coordinator can host it the same way.
final class SubscriptionOnboardingDuckAIChatViewController: UIViewController {

    /// Onboarding always provides the native input bar, so the UTI feature is forced on (unlike the default
    /// provider, which is iPhone-only). This must agree with the FE's `supportsNativeChatInput`, which is fed
    /// the same feature — otherwise the FE would hide its composer with no native bar behind it.
    private struct OnboardingUnifiedToggleInputFeature: UnifiedToggleInputFeatureProviding {
        let isAvailable = true
        let isToggleHiddenOnDuckAITab = false
    }

    private let modelID: String?
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private var utiHost: AIChatContextualUTIHost?
    private var didActivate = false

    init(modelID: String?,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>) {
        self.modelID = modelID
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Duck.ai"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close,
                                                           primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        let downloadsDirectoryHandler = DownloadsDirectoryHandler()
        downloadsDirectoryHandler.createDownloadsDirectoryIfNeeded()
        let downloadHandler = makeDownloadHandler(downloadsPath: downloadsDirectoryHandler.downloadsDirectory)

        // `utiHostInstaller` runs inside the web VC's `viewDidLoad` (triggered when its view is added below), so it
        // captures `self` to publish the host back for `viewDidAppear`. Page context is off (`getPageContext: nil`,
        // attach closures return false); `startsPreSubmit: true` makes the first prompt start the chat and every
        // subsequent one live-push (see `AIChatContextualUTIHost`).
        let webViewController = AIChatContextualWebViewController(
            aiChatSettings: AIChatSettings(),
            privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: DefaultFeatureDiscovery(),
            featureFlagger: AppDependencyProvider.shared.featureFlagger,
            unifiedToggleInputFeature: OnboardingUnifiedToggleInputFeature(),
            isFireTab: false,
            duckAiFireModeStorageHandler: nil,
            downloadHandler: downloadHandler,
            getPageContext: nil,
            pixelHandler: AIChatContextualModePixelHandler(),
            utiHostInstaller: { [weak self] webVC in
                let host = AIChatContextualUTIHost(
                    originatingURLPublisher: Just<URL?>(nil).eraseToAnyPublisher(),
                    initialAttachedContext: nil,
                    hasActiveChat: { false },
                    isAutoAttachEnabled: { false },
                    isCurrentPageAttachable: { false },
                    isFireTab: false,
                    lastUsedModelProvider: nil,
                    startsPreSubmit: true
                )
                host.setContextualChatViewController(webVC)
                host.installInWebView(webVC)
                self?.utiHost = host
                return host
            }
        )

        addChild(webViewController)
        webViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webViewController.view)
        NSLayoutConstraint.activate([
            webViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            webViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webViewController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // `installInWebView` calls `showExpanded()` during the web VC's `viewDidLoad` (before it's in a window),
        // so re-assert activation once on screen. Preselect the onboarding model on the bound coordinator.
        guard !didActivate, let utiHost else { return }
        didActivate = true
        utiHost.activateInput()
        if let modelID {
            utiHost.preselectModel(modelID)
        }
    }
}
