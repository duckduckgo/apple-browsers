//
//  WritingAssistanceUserScript.swift
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

import AIChat
import AppKit
import UserScript
import WebKit

/// PROTOTYPE (writing assistance), throwaway: injects the inline selection toolbar (`writing-assistance-toolbar.js`) into
/// every page's top frame and turns its clicks into Duck.ai sidebar requests.
///
/// The script runs in the isolated world, so the page can't post to this handler. It only posts for trusted clicks.
final class WritingAssistanceUserScript: NSObject, UserScript, WKScriptMessageHandlerWithReply {

    enum SettingsKey {
        static let enabled = "writingAssistancePrototype.enabled"
        static let expanded = "writingAssistancePrototype.expanded"
    }

    var source: String {
        (try? Self.loadJS("writing-assistance-toolbar", from: .main)) ?? ""
    }

    let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
    let forMainFrameOnly: Bool = true
    let messageNames: [String] = ["writingAssistance"]

    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let userDefaults: UserDefaults

    init(aiChatMenuConfig: AIChatMenuVisibilityConfigurable = Application.appDelegate.aiChatMenuConfiguration,
         userDefaults: UserDefaults = .standard) {
        self.aiChatMenuConfig = aiChatMenuConfig
        self.userDefaults = userDefaults
    }

    private var isEnabled: Bool {
        aiChatMenuConfig.shouldDisplayAnyAIChatFeature && userDefaults.object(forKey: SettingsKey.enabled) as? Bool ?? true
    }

    private var isExpanded: Bool {
        userDefaults.object(forKey: SettingsKey.expanded) as? Bool ?? true
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else {
            replyHandler(nil, nil)
            return
        }

        switch body["name"] as? String {
        case "getSettings":
            replyHandler(["enabled": isEnabled, "expanded": isExpanded], nil)
        case "run":
            run(body["data"] as? [String: Any] ?? [:], in: message.webView)
            replyHandler(nil, nil)
        default:
            replyHandler(nil, nil)
        }
    }

    // The toolbar hides itself when the tools are off, but a page still showing one from before the setting changed must
    // not be able to use it.
    private func run(_ data: [String: Any], in webView: WKWebView?) {
        guard isEnabled,
              let text = data["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let mainViewController = (webView?.window?.windowController as? MainWindowController)?.mainViewController
        else { return }

        switch data["action"] as? String {
        case "ask":
            mainViewController.aiChatSelectionContextAttacher.attach(text: text, url: webView?.url)
        case "skill":
            guard let prompt = data["prompt"] as? String, !prompt.isEmpty else { return }
            let selection = AIChatSelectionContextAttacher.selectionContext(text: text, url: webView?.url)
            // The selection is what the user asked about — don't also auto-attach the whole page.
            mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab.pageContext?.suppressAutoPageContextForSelectionAction()
            mainViewController.aiChatCoordinator.revealChat(for: .queryPrompt(prompt, autoSubmit: true, selections: [selection]))
        default:
            break
        }
    }
}
