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

    private var chatViewController: AIChatViewController?
    private weak var userContentController: UserContentController?

    private var aiChatUserScript: AIChatUserScript?
    private var payloadHandler = AIChatPayloadHandler()
    private var inputBoxHandler: AIChatInputBoxHandling?
    private var inputBoxViewModel: AIChatInputBoxViewModel?

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let downloadsDirectoryHandler: DownloadsDirectoryHandling
    private let userAgentManager: AIChatUserAgentProviding
    private let experimentalAIChatManager: ExperimentalAIChatManager
    private var cancellables = Set<AnyCancellable>()
    private var sessionTimer: AIChatSessionTimer?

    // MARK: - Initialization

    init(privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         downloadsDirectoryHandler: DownloadsDirectoryHandling = DownloadsDirectoryHandler(),
         userAgentManager: UserAgentManager = DefaultUserAgentManager.shared,
         experimentalAIChatManager: ExperimentalAIChatManager) {

        self.privacyConfigurationManager = privacyConfigurationManager
        self.downloadsDirectoryHandler = downloadsDirectoryHandler
        self.userAgentManager = AIChatUserAgentHandler(userAgentManager: userAgentManager)
        self.experimentalAIChatManager = experimentalAIChatManager
    }

    // MARK: - Public Methods

    @MainActor
    func openAIChat(_ query: String? = nil,
                    payload: Any? = nil,
                    autoSend: Bool = false,
                    on viewController: UIViewController) {
        downloadsDirectoryHandler.createDownloadsDirectoryIfNeeded()

        /// If we have a query or payload, let's clean the previous session and start fresh
        if query != nil || payload != nil {
            Task { @MainActor in
                await cleanUpSession()
                setupAndPresentAIChat(query, payload: payload, autoSend: autoSend, on: viewController)
            }
        } else {
            setupAndPresentAIChat(query, payload: payload, autoSend: autoSend, on: viewController)
        }
    }

    @MainActor
    private func setupAndPresentAIChat(_ query: String?,
                                       payload: Any?,
                                       autoSend: Bool,
                                       on viewController: UIViewController) {
        let aiChatViewController = createAIChatViewController()
        setupChatViewController(aiChatViewController, query: query, payload: payload, autoSend: autoSend)

        let roundedPageSheet = RoundedPageSheetContainerViewController(
            contentViewController: aiChatViewController,
            allowedOrientation: .portrait
        )
        roundedPageSheet.delegate = self

        viewController.present(roundedPageSheet, animated: true)
        chatViewController = aiChatViewController
        stopSessionTimer()
    }

    // MARK: - Private Helper Methods

    private func startSessionTimer() {
        sessionTimer = AIChatSessionTimer()
        sessionTimer?.start {  [weak self] in
            Task { @MainActor in
                await self?.cleanUpSession()
            }
        }
    }

    private func cleanUpSession() async {
        await self.cleanUpUserContent()
        self.chatViewController = nil
    }

    private func stopSessionTimer() {
        sessionTimer?.cancel()
    }

    @MainActor
    private func createAIChatViewController() -> AIChatViewController {
        if let chatViewController = chatViewController {
            return chatViewController
        }
        let settings = AIChatSettings(privacyConfigurationManager: privacyConfigurationManager)
        let webViewConfiguration = createWebViewConfiguration()
        let inspectableWebView = isInspectableWebViewEnabled()
        let chatInputBox = setupChatInputBoxIfNeeded()

        let aiChatViewController = AIChatViewController(
            settings: settings,
            webViewConfiguration: webViewConfiguration,
            requestAuthHandler: AIChatRequestAuthorizationHandler(debugSettings: AIChatDebugSettings()),
            inspectableWebView: inspectableWebView,
            downloadsPath: downloadsDirectoryHandler.downloadsDirectory,
            userAgentManager: userAgentManager,
            chatInputBoxViewController: chatInputBox,
            chatInputBoxHandler: inputBoxHandler
        )

        aiChatViewController.delegate = self
        return aiChatViewController
    }

    @MainActor
    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration.persistent()
        let userContentController = UserContentController()
        userContentController.delegate = self
        configuration.userContentController = userContentController
        self.userContentController = userContentController
        return configuration
    }

    private func setupChatViewController(_ aiChatViewController: AIChatViewController,
                                         query: String?,
                                         payload: Any?, autoSend: Bool) {
        if let query = query {
            aiChatViewController.loadQuery(query, autoSend: autoSend)
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

    private func setupChatInputBoxIfNeeded() -> UIViewController? {
        guard experimentalAIChatManager.isExperimentalAIChatSettingsEnabled else { return nil }
        let viewModel = AIChatInputBoxViewModel()
        let handler = AIChatInputBoxHandler(inputBoxViewModel: viewModel)

        inputBoxViewModel = viewModel
        inputBoxHandler = handler
        setupAIChatSubscriptions()
        return ChatInputBoxViewController(viewModel: viewModel)
    }

    private func setupAIChatSubscriptions() {
        guard let inputBoxHandler = inputBoxHandler else { return }

        inputBoxHandler.didSubmitQuery
            .sink { [weak self] submittedText in
                guard let self = self else { return }
                self.loadQuery(submittedText)
            }
            .store(in: &cancellables)
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
        aiChatUserScript?.inputBoxHandler = inputBoxHandler
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
}

// MARK: - RoundedPageSheetContainerViewControllerDelegate

extension AIChatViewControllerManager: RoundedPageSheetContainerViewControllerDelegate {
    func roundedPageSheetContainerViewControllerDidDisappear(_ controller: RoundedPageSheetContainerViewController) {

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
}

// MARK: - AIChatUserAgentHandler

private struct AIChatUserAgentHandler: AIChatUserAgentProviding {
    let userAgentManager: UserAgentManager

    func userAgent(url: URL?) -> String {
        userAgentManager.userAgent(isDesktop: false, url: url)
    }
}

// MARK: - AIChatReloadTimer

private final class AIChatSessionTimer {
    private enum Constants {
        static let sessionTimerDuration: TimeInterval = 60 * 60
    }

    private var timer: Timer?

    func start(completion: @escaping () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.sessionTimerDuration, repeats: false) { _ in
            completion()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        cancel()
    }
}
