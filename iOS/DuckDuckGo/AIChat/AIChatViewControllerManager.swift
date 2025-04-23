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

protocol AIChatViewControllerManagerDelegate: AnyObject {
    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestToLoad url: URL)
    func aiChatViewControllerManager(_ manager: AIChatViewControllerManager, didRequestOpenDownloadWithFileName fileName: String)
    func aiChatViewControllerManagerDidReceiveOpenSettingsRequest(_ manager: AIChatViewControllerManager)
}

final class AIChatViewControllerManager {
    weak var delegate: AIChatViewControllerManagerDelegate?
    private var aiChatUserScript: AIChatUserScript?
    private var payloadHandler = AIChatPayloadHandler()
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private weak var userContentController: UserContentController?
    private let downloadsDirectoryHandler: DownloadsDirectoryHandling
    private weak var chatViewController: AIChatViewController?
    private let userAgentManager: AIChatUserAgentProviding

    init(privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         downloadsDirectoryHandler: DownloadsDirectoryHandling = DownloadsDirectoryHandler(),
         userAgentManager: UserAgentManager = DefaultUserAgentManager.shared) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.downloadsDirectoryHandler = downloadsDirectoryHandler
        self.userAgentManager = AIChatUserAgentHandler(userAgentManager: userAgentManager)
    }

    @MainActor
    func openAIChat(_ query: String? = nil, payload: Any? = nil, autoSend: Bool = false, on viewController: UIViewController) {
        let settings = AIChatSettings(privacyConfigurationManager: privacyConfigurationManager)

        let inspectableWebView: Bool
#if DEBUG
        inspectableWebView = true
#else
        inspectableWebView = AppUserDefaults().inspectableWebViewEnabled
#endif

        let webviewConfiguration = WKWebViewConfiguration.persistent()
        let userContentController = UserContentController()
        userContentController.delegate = self

        downloadsDirectoryHandler.createDownloadsDirectoryIfNeeded()

        webviewConfiguration.userContentController = userContentController
        self.userContentController = userContentController

        let aiChatViewController = AIChatViewController(settings: settings,
                                                        webViewConfiguration: webviewConfiguration,
                                                        requestAuthHandler: AIChatRequestAuthorizationHandler(debugSettings: AIChatDebugSettings()),
                                                        inspectableWebView: inspectableWebView,
                                                        downloadsPath: downloadsDirectoryHandler.downloadsDirectory,
                                                        userAgentManager: userAgentManager)
        aiChatViewController.delegate = self

        let roundedPageSheet = RoundedPageSheetContainerViewController(
            contentViewController: aiChatViewController,
            allowedOrientation: .portrait)

        roundedPageSheet.delegate = self

        if let query = query {
            aiChatViewController.loadQuery(query, autoSend: autoSend)
        }

        // Force a reload to trigger the user script getUserValues
        if let payload = payload as? AIChatPayload {
            payloadHandler.setData(payload)
            aiChatViewController.reload()
        }
        viewController.present(roundedPageSheet, animated: true, completion: nil)
        chatViewController = aiChatViewController
    }

    private func cleanUpUserContent() {
        Task {
            await userContentController?.removeAllContentRuleLists()
            await userContentController?.cleanUpBeforeClosing()
        }
    }
}

extension AIChatViewControllerManager: UserContentControllerDelegate {
    @MainActor
    func userContentController(_ userContentController: UserContentController,
                               didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                               userScripts: UserScriptsProvider,
                               updateEvent: ContentBlockerRulesManager.UpdateEvent) {

        guard let userScripts = userScripts as? UserScripts else { fatalError("Unexpected UserScripts") }
        self.aiChatUserScript = userScripts.aiChatUserScript
        self.aiChatUserScript?.delegate = self
        self.aiChatUserScript?.setPayloadHandler(self.payloadHandler)
    }
}

// MARK: - AIChatViewControllerDelegate
extension AIChatViewControllerManager: AIChatViewControllerDelegate {
    func aiChatViewController(_ viewController: AIChatViewController, didRequestToLoad url: URL) {
        delegate?.aiChatViewControllerManager(self, didRequestToLoad: url)
        viewController.dismiss(animated: true)
    }

    func aiChatViewControllerDidFinish(_ viewController: AIChatViewController) {
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
        cleanUpUserContent()
    }
}

// MARK: AIChatUserScriptDelegate

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
