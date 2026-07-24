//
//  SubscriptionOnboardingDuckAIWebChatLauncher.swift
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

import SwiftUI
import UIKit
import WebKit
import Combine
import Core
import BrowserServicesKit
import UserScript
import DesignResourcesKit
import DesignResourcesKitIcons

/// Alternative Duck.ai launch mechanism for post-subscription onboarding that opens `duck.ai` directly in a
/// `WKWebView` wired to the app's content-blocking pipeline, instead of the production contextual chat sheet
/// used by `SubscriptionOnboardingDuckAIChatLauncher`. The preferred model is applied by seeding the site's
/// `preferredDuckaiModel` localStorage key before the initial navigation.
@MainActor
final class SubscriptionOnboardingDuckAIWebChatLauncher: NSObject {

    private static let duckAIURL = URL(string: "https://duck.ai")!

    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private weak var hostingController: UIViewController?
    private var onFinished: (() -> Void)?
    private var didFinish = false

    init(contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>) {
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        super.init()
    }

    /// Presents the Duck.ai web surface as a page-sheet modal from `presentingViewController` — matching how the
    /// production contextual sheet is presented — seeding `modelSettingID` (the model's setting identifier, not
    /// its display id) into localStorage when provided. `onFinished` fires exactly once, whether the sheet is
    /// closed via its button or dismissed interactively (swipe-down).
    func present(from presentingViewController: UIViewController, modelSettingID: String?, onFinished: (() -> Void)? = nil) {
        self.onFinished = onFinished
        let webSheet = SubscriptionOnboardingDuckAIWebSheet(
            urlString: Self.duckAIURL.absoluteString,
            preferredModelSettingId: modelSettingID,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            onClose: { [weak self] in
                self?.hostingController?.dismiss(animated: true) { self?.finish() }
            })
        let hosting = UIHostingController(rootView: webSheet)
        hosting.modalPresentationStyle = .pageSheet
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        hosting.presentationController?.delegate = self
        hostingController = hosting
        presentingViewController.present(hosting, animated: true)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished?()
    }
}

extension SubscriptionOnboardingDuckAIWebChatLauncher: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }
}

private struct SubscriptionOnboardingDuckAIWebSheet: View {

    let urlString: String
    var preferredModelSettingId: String?
    var contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color(designSystemColor: .surface)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    // Matches the circular close button used by the onboarding info sheets
                    // (`SubscriptionOnboardingBaseView` `.close`).
                    Button(action: onClose) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(Color(designSystemColor: .iconsSecondary))
                            .frame(width: 44, height: 44)
                            .background(Color(designSystemColor: .controlsFillPrimary))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(UserText.subscriptionOnboardingCloseButtonAccessibilityLabel)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                DuckAIWebView(urlString: urlString,
                              preferredModelSettingId: preferredModelSettingId,
                              contentBlockingAssetsPublisher: contentBlockingAssetsPublisher)
            }
        }
    }
}

private struct DuckAIWebContent: UserContentControllerNewContent {

    let base: ContentBlockingUpdating.NewContent

    var rulesUpdate: ContentBlockerRulesManager.UpdateEvent { base.rulesUpdate }
    var sourceProvider: ScriptSourceProviding { base.sourceProvider }

    var makeUserScripts: @MainActor (ScriptSourceProviding) -> UserScripts {
        { [base] sourceProvider in
            UserScripts(with: sourceProvider,
                        keyValueStore: base.keyValueStore,
                        duckAiNativeStorageHandler: base.duckAiNativeStorageHandler,
                        includeAIChatUserScript: false,
                        adBlockingAvailability: base.adBlockingAvailability)
        }
    }
}

struct DuckAIWebView: UIViewRepresentable {

    let urlString: String
    var preferredModelSettingId: String?
    var contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>?

    func makeCoordinator() -> Coordinator {
        Coordinator(urlString: urlString, preferredModelSettingId: preferredModelSettingId)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration.persistent(fireMode: false)
        if let contentBlockingAssetsPublisher {
            let content = contentBlockingAssetsPublisher
                .map { DuckAIWebContent(base: $0) }
                .eraseToAnyPublisher()
            let controller = UserContentController(assetsPublisher: content,
                                                   privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)
            controller.delegate = context.coordinator
            configuration.userContentController = controller
            context.coordinator.pipelineUserContentController = controller
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
        context.coordinator.webView = webView

        if context.coordinator.pipelineUserContentController == nil {
            context.coordinator.injectModelOverride()
            context.coordinator.loadInitialURLIfNeeded()
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: UserContentControllerDelegate {

        private let urlString: String
        private let preferredModelSettingId: String?
        weak var webView: WKWebView?
        var pipelineUserContentController: UserContentController?
        private var didLoadInitialURL = false

        init(urlString: String, preferredModelSettingId: String?) {
            self.urlString = urlString
            self.preferredModelSettingId = preferredModelSettingId
        }

        func injectModelOverride() {
            guard let preferredModelSettingId else { return }
            let source = "localStorage.setItem('preferredDuckaiModel', JSON.stringify('\(preferredModelSettingId)'));"
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            let controller = pipelineUserContentController ?? webView?.configuration.userContentController
            controller?.addUserScript(script)
        }

        func loadInitialURLIfNeeded() {
            guard !didLoadInitialURL, let url = URL(string: urlString) else { return }
            didLoadInitialURL = true
            webView?.load(URLRequest(url: url))
        }

        func userContentController(_ userContentController: UserContentController,
                                   didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                                   userScripts: UserScriptsProvider,
                                   updateEvent: ContentBlockerRulesManager.UpdateEvent) {
            injectModelOverride()
            loadInitialURLIfNeeded()
        }
    }
}
