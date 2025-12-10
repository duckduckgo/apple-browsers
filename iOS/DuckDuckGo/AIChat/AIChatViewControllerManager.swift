//
//  AIChatViewControllerManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UserScript
import AIChat
import Foundation
import BrowserServicesKit
import WebKit
import Core
import SwiftUI
import Combine

protocol AIChatViewControllerManagerDelegate: AnyObject {
    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestToLoad url: URL)
    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestOpenDownloadWithFileName fileName: String)
    func aiChatViewControllerManagerDidReceiveOpenSettingsRequest(_ manager: AIChatViewControllerManager)
    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didSubmitQuery query: String)
}

final class AIChatViewControllerManager {

    // MARK: - Public Properties

    weak var delegate: AIChatViewControllerManagerDelegate?

    // MARK: - Private Properties

    private(set) var chatViewController: AIChatViewController?
    private weak var userContentController: UserContentController?

    private var aiChatUserScript: AIChatUserScript?
    private var payloadHandler = AIChatPayloadHandler()
    private let subscriptionAIChatStateHandler: SubscriptionAIChatStateHandling

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private let downloadsDirectoryHandler: DownloadsDirectoryHandling
    private let userAgentManager: AIChatUserAgentProviding
    private let featureFlagger: FeatureFlagger
    private let featureDiscovery: FeatureDiscovery
    private let experimentalAIChatManager: ExperimentalAIChatManager
    private let aiChatSettings: AIChatSettingsProvider
    private var cancellables = Set<AnyCancellable>()
    private var sessionTimer: AIChatSessionTimer?
    private var pixelMetricHandler: (any AIChatPixelMetricHandling)?
    private var productSurfaceTelemetry: ProductSurfaceTelemetry

    // MARK: - Initialization

    init(privacyConfigurationManager: PrivacyConfigurationManaging,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         downloadsDirectoryHandler: DownloadsDirectoryHandling = DownloadsDirectoryHandler(),
         userAgentManager: UserAgentManaging = DefaultUserAgentManager.shared,
         experimentalAIChatManager: ExperimentalAIChatManager,
         featureFlagger: FeatureFlagger,
         featureDiscovery: FeatureDiscovery,
         aiChatSettings: AIChatSettingsProvider,
         subscriptionAIChatStateHandler: SubscriptionAIChatStateHandling = SubscriptionAIChatStateHandler(),
         productSurfaceTelemetry: ProductSurfaceTelemetry) {

        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.downloadsDirectoryHandler = downloadsDirectoryHandler
        self.userAgentManager = AIChatUserAgentHandler(userAgentManager: userAgentManager)
        self.experimentalAIChatManager = experimentalAIChatManager
        self.featureFlagger = featureFlagger
        self.featureDiscovery = featureDiscovery
        self.aiChatSettings = aiChatSettings
        self.subscriptionAIChatStateHandler = subscriptionAIChatStateHandler
        self.productSurfaceTelemetry = productSurfaceTelemetry
    }

    // MARK: - Public Methods

    /// Opens AI Chat in a modal presentation (sheet).
    ///
    /// - Parameters:
    ///   - query: Optional initial query to send to AI Chat
    ///   - payload: Optional payload data for AI Chat
    ///   - autoSend: Whether to automatically send the query
    ///   - tools: Optional RAG tools available in AI Chat
    ///   - viewController: View controller to present the modal on
    @MainActor
    func killSessionAndResetTimer() async {
        stopSessionTimer()
        await cleanUpSession()
    }

    @MainActor
    func openAIChat(_ query: String? = nil,
                    payload: Any? = nil,
                    autoSend: Bool = false,
                    tools: [AIChatRAGTool]? = nil,
                    on viewController: UIViewController) {
        open(query, payload: payload, autoSend: autoSend, tools: tools,
             presentationMode: .modal, viewController: viewController)
    }

    /// Opens AI Chat in a container view (no modal sheet).
    ///
    /// - Parameters:
    ///   - query: Optional initial query to send to AI Chat
    ///   - payload: Optional payload data for AI Chat
    ///   - autoSend: Whether to automatically send the query
    ///   - tools: Optional RAG tools available in AI Chat
    ///   - containerView: View to embed AI Chat into
    ///   - parentViewController: Parent view controller for managing the child
    ///   - completion: Optional callback when setup is complete
    @MainActor
    func openAIChatInContainer(_ query: String? = nil,
                               payload: Any? = nil,
                               autoSend: Bool = false,
                               tools: [AIChatRAGTool]? = nil,
                               in containerView: UIView,
                               parentViewController: UIViewController,
                               completion: (() -> Void)? = nil) {
        open(query, payload: payload, autoSend: autoSend, tools: tools,
             presentationMode: .container, containerView: containerView,
             viewController: parentViewController, completion: completion)
    }

    // MARK: - Private Setup Methods

    /// Unified internal method handling both modal and container presentations.
    ///
    /// - Parameters:
    ///   - query: Optional initial query
    ///   - payload: Optional payload data
    ///   - autoSend: Whether to auto-send query
    ///   - tools: Optional RAG tools
    ///   - presentationMode: `.modal` (fires pixels) or `.container` (no pixels)
    ///   - containerView: Required for `.container` mode
    ///   - viewController: Required for both modes
    ///   - completion: Optional callback (used in container mode)
    @MainActor
    private func open(_ query: String? = nil,
                      payload: Any? = nil,
                      autoSend: Bool = false,
                      tools: [AIChatRAGTool]? = nil,
                      presentationMode: AIChatPresentationMode,
                      containerView: UIView? = nil,
                      viewController: UIViewController? = nil,
                      completion: (() -> Void)? = nil) {

        productSurfaceTelemetry.duckAIUsed()

        // Reset the session timer if the subscription state has changed
        if subscriptionAIChatStateHandler.shouldForceAIChatRefresh {
            stopSessionTimer()
        }

        // Only fire this pixel for modal presentations (new pixels for full mode coming soon)
        if presentationMode == .modal {
            pixelMetricHandler = AIChatPixelMetricHandler(timeElapsedInMinutes: sessionTimer?.timeElapsedInMinutes())
            pixelMetricHandler?.fireOpenAIChat()
            featureDiscovery.setWasUsedBefore(.aiChat)
        }

        // If we have a query or payload, clean the previous session and start fresh
        if query != nil || payload != nil || subscriptionAIChatStateHandler.shouldForceAIChatRefresh {
            subscriptionAIChatStateHandler.reset()
            Task {
                await cleanUpSession()
                self.performSetup(query, payload: payload, autoSend: autoSend, tools: tools,
                                  presentationMode: presentationMode, containerView: containerView,
                                  viewController: viewController, completion: completion)
            }
        } else {
            performSetup(query, payload: payload, autoSend: autoSend, tools: tools,
                         presentationMode: presentationMode, containerView: containerView,
                         viewController: viewController, completion: completion)
        }
    }

    /// Routes to appropriate setup method based on presentation mode.
    @MainActor
    private func performSetup(_ query: String?,
                              payload: Any?,
                              autoSend: Bool,
                              tools: [AIChatRAGTool]?,
                              presentationMode: AIChatPresentationMode,
                              containerView: UIView?,
                              viewController: UIViewController?,
                              completion: (() -> Void)?) {
        switch presentationMode {
        case .modal:
            guard let viewController = viewController else { return }
            setupAndPresentAIChat(query, payload: payload, autoSend: autoSend,
                                  tools: tools, on: viewController)
        case .container:
            guard let containerView = containerView, let viewController = viewController else { return }
            setupAndAddToContainer(query, payload: payload, autoSend: autoSend,
                                   tools: tools, in: containerView,
                                   parentViewController: viewController, completion: completion)
        }
    }

    /// Creates and presents AI Chat in a modal sheet.
    ///
    /// Sets up the view controller with initial query/payload and presents
    /// it wrapped in a `RoundedPageSheetContainerViewController`.
    @MainActor
    private func setupAndPresentAIChat(_ query: String?,
                                       payload: Any?,
                                       autoSend: Bool,
                                       tools: [AIChatRAGTool]?,
                                       on viewController: UIViewController) {
        let aiChatViewController = createAIChatViewController(presentationMode: .modal)
        setupChatViewController(aiChatViewController, query: query,
                                payload: payload,
                                autoSend: autoSend,
                                tools: tools)

        let roundedPageSheet = RoundedPageSheetContainerViewController(
            contentViewController: aiChatViewController,
            allowedOrientation: .portrait
        )
        roundedPageSheet.delegate = self

        viewController.present(roundedPageSheet, animated: true)
        chatViewController = aiChatViewController
        stopSessionTimer()
    }

    /// Embeds AI Chat as a child view controller in a container.
    @MainActor
    private func setupAndAddToContainer(_ query: String?,
                                        payload: Any?,
                                        autoSend: Bool,
                                        tools: [AIChatRAGTool]?,
                                        in containerView: UIView,
                                        parentViewController: UIViewController,
                                        completion: (() -> Void)? = nil) {
        let aiChatViewController = createAIChatViewController(presentationMode: .container)
        setupChatViewController(aiChatViewController, query: query,
                                payload: payload,
                                autoSend: autoSend,
                                tools: tools)

        parentViewController.addChild(aiChatViewController)
        containerView.addSubview(aiChatViewController.view)

        aiChatViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            aiChatViewController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            aiChatViewController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            aiChatViewController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            aiChatViewController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        aiChatViewController.didMove(toParent: parentViewController)

        chatViewController = aiChatViewController
        stopSessionTimer()

        completion?()
    }

    // MARK: - Private Helper Methods

    private func startSessionTimer() {
        guard isKeepSessionEnabled else { return }

        let sessionTime = TimeInterval(aiChatSettings.sessionTimerInMinutes * 60)
        sessionTimer = AIChatSessionTimer(durationInSeconds: sessionTime, completion: { [weak self] in
            Task {
                await self?.cleanUpSession()
            }
        })
        sessionTimer?.start()
    }

    @MainActor
    private func cleanUpSession() async {
        await self.cleanUpUserContent()
        self.chatViewController = nil
    }

    private func stopSessionTimer() {
        sessionTimer?.cancel()
        sessionTimer = nil
    }

    private var isKeepSessionEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatKeepSession)
    }

    @MainActor
    private func createAIChatViewController(presentationMode: AIChatPresentationMode = .modal) -> AIChatViewController {
        if let chatViewController = chatViewController {
            return chatViewController
        }
        let webViewConfiguration = createWebViewConfiguration()
        let inspectableWebView = isInspectableWebViewEnabled()

        let aiChatViewController = AIChatViewController(
            settings: aiChatSettings,
            webViewConfiguration: webViewConfiguration,
            requestAuthHandler: AIChatRequestAuthorizationHandler(debugSettings: AIChatDebugSettings()),
            inspectableWebView: inspectableWebView,
            downloadsPath: downloadsDirectoryHandler.downloadsDirectory,
            userAgentManager: userAgentManager,
            presentationMode: presentationMode
        )

        aiChatViewController.delegate = self
        return aiChatViewController
    }

    @MainActor
    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration.persistent()
        let userContentController = UserContentController(assetsPublisher: contentBlockingAssetsPublisher,
                                                          privacyConfigurationManager: privacyConfigurationManager)
        userContentController.delegate = self
        configuration.userContentController = userContentController
        self.userContentController = userContentController
        return configuration
    }

    private func setupChatViewController(_ aiChatViewController: AIChatViewController,
                                         query: String?,
                                         payload: Any?,
                                         autoSend: Bool,
                                         tools: [AIChatRAGTool]?) {
        if let query = query {
            aiChatViewController.loadQuery(query,
                                           autoSend: autoSend,
                                           tools: tools)
        }

        if let payload = payload as? AIChatPayload {
            payloadHandler.setData(payload)
            aiChatViewController.reload()
        }
    }

    private func isInspectableWebViewEnabled() -> Bool {
#if DEBUG
        return true
#else
        return AppUserDefaults().inspectableWebViewEnabled
#endif
    }

    private func cleanUpUserContent() async {
        await userContentController?.removeAllContentRuleLists()
        await userContentController?.cleanUpBeforeClosing()
    }

    private func loadQuery(_ query: String) {
        chatViewController?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.delegate?.aiChatViewControllerManager(self, didSubmitQuery: query)
        }
    }
}

// MARK: - UserContentControllerDelegate

extension AIChatViewControllerManager: UserContentControllerDelegate {
    @MainActor
    func userContentController(_ userContentController: UserContentController,
                               didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                               userScripts: UserScriptsProvider,
                               updateEvent: ContentBlockerRulesManager.UpdateEvent) {

        guard let userScripts = userScripts as? UserScripts else {
            fatalError("Unexpected UserScripts")
        }

        aiChatUserScript = userScripts.aiChatUserScript
        aiChatUserScript?.delegate = self
        aiChatUserScript?.setPayloadHandler(payloadHandler)
        aiChatUserScript?.webView = chatViewController?.webView
    }
}

// MARK: - AIChatViewControllerDelegate

extension AIChatViewControllerManager: AIChatViewControllerDelegate {
    func aiChatViewController(_ viewController: AIChatViewController, didRequestToLoad url: URL) {
        viewController.dismiss(animated: true) {
            self.delegate?.aiChatViewControllerManager(self, didRequestToLoad: url)
        }
    }

    func aiChatViewControllerDidFinish(_ viewController: AIChatViewController) {
        startSessionTimer()
        viewController.dismiss(animated: true)
    }

    func aiChatViewController(_ viewController: AIChatViewController, didRequestOpenDownloadWithFileName fileName: String) {
        viewController.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.delegate?.aiChatViewControllerManager(self, didRequestOpenDownloadWithFileName: fileName)
        }
    }
    
    func aiChatViewControllerWillStartDownload() {
        downloadsDirectoryHandler.createDownloadsDirectoryIfNeeded()
    }
}

// MARK: - RoundedPageSheetContainerViewControllerDelegate

extension AIChatViewControllerManager: RoundedPageSheetContainerViewControllerDelegate {
    func roundedPageSheetContainerViewControllerDidDisappear(_ controller: RoundedPageSheetContainerViewController) {
        guard isKeepSessionEnabled == false else { return }

        Task {
            await cleanUpSession()
        }
    }
}

// MARK: - AIChatUserScriptDelegate

extension AIChatViewControllerManager: AIChatUserScriptDelegate {
    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMessage message: AIChatUserScriptMessages) {
        switch message {
        case .openAIChatSettings:
            chatViewController?.dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                self.delegate?.aiChatViewControllerManagerDidReceiveOpenSettingsRequest(self)
            }
        case .closeAIChat:
            chatViewController?.dismiss(animated: true)
        default:
            break
        }
    }

    func aiChatUserScript(_ userScript: AIChatUserScript, didReceiveMetric metric: AIChatMetric) {

        if metric.metricName == .userDidSubmitPrompt
            || metric.metricName == .userDidSubmitFirstPrompt {
            NotificationCenter.default.post(name: .aiChatUserDidSubmitPrompt, object: nil)
        }

        pixelMetricHandler?.firePixelWithMetric(metric)
    }
}

// MARK: - AIChatUserAgentHandler

private struct AIChatUserAgentHandler: AIChatUserAgentProviding {
    let userAgentManager: UserAgentManaging

    func userAgent(url: URL?) -> String {
        userAgentManager.userAgent(isDesktop: false, url: url)
    }
}
