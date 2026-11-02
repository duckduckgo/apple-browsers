//
//  TabViewControllerAIChatExtension.swift
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

import AIChat
import Foundation
import UIKit
import WebKit

/// Protocol for tab controllers that support full mode AIChat content loading.
protocol AITabController {
    /// Loads AIChat with optional query, auto-submit, payload, and RAG tools.
    func load(_ query: String?, autoSend: Bool, payload: Any?, flowType: AIChatOnboardingFlowType, tools: [AIChatRAGTool]?, modelId: String?, reasoningEffort: AIChatReasoningEffort?, attachments: AIChatPromptAttachments, termsAccepted: Bool)

    /// Loads AIChat in voice mode.
    func loadVoiceMode()

    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction()

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction()

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction()

    /// Opens a new AI chat in a new tab.
    func openNewChatInNewTab(source: AIChatEntryPointSource?, inputRequest: DuckAINewChatInputRequest?)
}

// MARK: - AITabController
extension TabViewController: AITabController {

    /// Loads AIChat with optional query, auto-submit, payload, and RAG tools.
    func load(_ query: String? = nil,
              autoSend: Bool = false,
              payload: Any? = nil,
              flowType: AIChatOnboardingFlowType = .default,
              tools: [AIChatRAGTool]? = nil,
              modelId: String? = nil,
              reasoningEffort: AIChatReasoningEffort? = nil,
              attachments: AIChatPromptAttachments = .none,
              termsAccepted: Bool = false) {
        let openingQuery = AIChatOpeningRequest.Query(query: query, autoSend: autoSend, flowType: flowType, tools: tools,
                                                     modelId: modelId, reasoningEffort: reasoningEffort,
                                                     attachments: attachments, termsAccepted: termsAccepted)
        configureAIChatOpening(payload: payload)
        if let prompt = openingQuery.sharedPrompt { AIChatPromptHandler.shared.setData(prompt) }
        let queryURL = openingQuery.url(using: aiChatContentHandler)

        load(url: queryURL)
    }

    func configureAIChatOpening(payload: Any?) {
        isVoiceModeRequested = false
        aiChatContentHandler.setPayload(payload: payload)
    }
    
    /// Loads AIChat in voice mode.
    func loadVoiceMode() {
        isVoiceModeRequested = true
        let url = aiChatContentHandler.buildVoiceModeURL()
        load(url: url)
    }

    /// Submits a start chat action to initiate a new AI Chat conversation.
    func submitStartChatAction() {
        cancelPendingAIChatTabAttachmentPrompt()
        Task { @MainActor in
            await aiChatContentHandler.submitStartChatAction()
        }
    }

    /// Submits an open settings action to open the AI Chat settings.
    func submitOpenSettingsAction() {
        aiChatContentHandler.submitOpenSettingsAction()
    }

    /// Submits a toggle sidebar action to open/close the sidebar.
    func submitToggleSidebarAction() {
        aiChatContentHandler.submitToggleSidebarAction()
    }
    
    /// Opens a new AI chat in a new tab.
    func openNewChatInNewTab(source: AIChatEntryPointSource?, inputRequest: DuckAINewChatInputRequest? = nil) {
        let newChatURL = aiChatContentHandler.buildQueryURL(
            query: nil,
            autoSend: false,
            flowType: .default,
            tools: nil
        )
        delegate?.tab(self, didRequestNewDuckAITabForUrl: newChatURL, entrySource: source, newChatInputRequest: inputRequest)
    }

    /// Opens the Duck.ai chats sidebar in a new tab. Mirrors the contextual sheet's "View all chats"
    /// (`sidebarOpenURL`), so it works from any tab — unlike the in-page sidebar toggle.
    func openChatListInNewTab() {
        let url = AIChatURLParameters.sidebarOpenURL(from: aiChatSettings.aiChatURL)
        delegate?.tab(self, didRequestNewTabForUrl: url, openedByPage: false, inheritingAttribution: nil)
    }

    func openSettingsInNewTab() {
        let url = AIChatURLParameters.settingsOpenURL(from: aiChatSettings.aiChatURL)
        delegate?.tab(self, didRequestNewTabForUrl: url, openedByPage: false, inheritingAttribution: nil)
    }

    func submitOpenChatProtectionAction() {
        aiChatContentHandler.submitOpenChatProtectionAction()
    }

    /// Reloads the full mode AI Chat tab if this is an AI tab.
    func reloadFullModeAIChatIfNeeded() {
        if isAITab {
            webView.reload()
        }
    }
}

extension TabViewController {

    enum AIChatNewWindowDecision: Equatable {
        case ignore
        case loadInTab(URL)
        case openInNewTab(URL)
    }

    static func aiChatNewWindowDecision(currentURL: URL?,
                                        navigationAction: WKNavigationAction) -> AIChatNewWindowDecision {
        guard navigationAction.navigationType == .linkActivated,
              navigationAction.targetFrame == nil,
              currentURL?.isDuckAIURL == true,
              let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .ignore
        }

        if url.isDuckAIURL {
            return .loadInTab(url)
        }

        return .openInNewTab(url)
    }

    /// Page-started main-frame navigations into Duck.ai that native attributes. The tab's own loads
    /// report their entry where they start, so the one still pending is skipped.
    static func inPageDuckAIEntrySource(currentURL: URL?,
                                        navigationAction: WKNavigationAction,
                                        pendingNativeLoadURL: URL?) -> AIChatEntryPointSource? {
        guard navigationAction.isTargetingMainFrame,
              navigationAction.navigationType != .backForward,
              navigationAction.navigationType != .reload,
              let targetURL = navigationAction.request.url,
              targetURL != pendingNativeLoadURL else {
            return nil
        }
        return AIChatEntryPointSource.forInPageNavigation(from: currentURL, to: targetURL,
                                                          isLinkActivation: navigationAction.navigationType == .linkActivated)
    }
}

// MARK: - Pull up past the bottom to start a new chat (PoC)

extension TabViewController {

    func installDuckAIOverscrollNewChatIfNeeded() {
        guard isAITab, duckAIOverscrollNewChat == nil else { return }
        duckAIOverscrollNewChat = DuckAIOverscrollNewChatHandler(webView: webView) { [weak self] in
            self?.openNewChatInNewTab(source: .duckAINewChat)
        }
    }
}

/// Duck.ai scrolls an inner container, not the web view's scroll view, so the native scroll view never
/// reports overscroll. Instead a simultaneous pan asks the page whether the container under the finger is
/// at its bottom, then measures how far the finger keeps pulling up from there.
final class DuckAIOverscrollNewChatHandler: NSObject, UIGestureRecognizerDelegate {

    private enum Constants {
        static let triggerDistance: CGFloat = 110
        static let pillBottomOffset: CGFloat = 16
    }

    private weak var webView: WKWebView?
    private let onTrigger: () -> Void
    private let pan = UIPanGestureRecognizer()
    private let pill = UILabel()
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private var isAtBottom = false
    private var isCheckInFlight = false
    private var baselineTranslation: CGFloat?
    private var isArmed = false

    init(webView: WKWebView, onTrigger: @escaping () -> Void) {
        self.webView = webView
        self.onTrigger = onTrigger
        super.init()
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        webView.addGestureRecognizer(pan)
        installPill(in: webView)
    }

    private func installPill(in webView: WKWebView) {
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.font = .systemFont(ofSize: 15, weight: .semibold)
        pill.textAlignment = .center
        pill.textColor = .label
        pill.backgroundColor = .secondarySystemBackground
        pill.layer.cornerRadius = 18
        pill.layer.masksToBounds = true
        pill.alpha = 0
        pill.isUserInteractionEnabled = false
        webView.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: webView.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.pillBottomOffset),
            pill.heightAnchor.constraint(equalToConstant: 36),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let webView else { return }
        let translation = gesture.translation(in: webView).y
        switch gesture.state {
        case .began:
            reset()
            haptic.prepare()
            checkAtBottom(at: gesture.location(in: webView))
        case .changed:
            if !isAtBottom {
                checkAtBottom(at: gesture.location(in: webView))
            }
            guard let baselineTranslation else { return }
            updatePill(pull: baselineTranslation - translation)
        case .ended:
            if isArmed { onTrigger() }
            hidePill()
            reset()
        default:
            hidePill()
            reset()
        }
    }

    private func updatePill(pull: CGFloat) {
        let progress = max(0, min(1, pull / Constants.triggerDistance))
        let armed = progress >= 1
        if armed != isArmed {
            isArmed = armed
            if armed { haptic.impactOccurred() }
        }
        pill.text = armed ? "Release for new chat" : "↑ Pull up for new chat"
        pill.alpha = progress
        pill.transform = CGAffineTransform(translationX: 0, y: (1 - progress) * 20)
    }

    private func hidePill() {
        UIView.animate(withDuration: 0.2) {
            self.pill.alpha = 0
            self.pill.transform = .identity
        }
    }

    private func reset() {
        isAtBottom = false
        baselineTranslation = nil
        isArmed = false
    }

    /// Only a chat with messages counts; the empty new-chat screen has nothing to scroll past.
    private func checkAtBottom(at point: CGPoint) {
        guard let webView, !isCheckInFlight, webView.url?.duckAIChatID != nil else { return }
        isCheckInFlight = true
        let script = """
        (function(x, y) {
          let el = document.elementFromPoint(x, y);
          while (el && el !== document.documentElement) {
            const style = getComputedStyle(el);
            if (/(auto|scroll)/.test(style.overflowY) && el.scrollHeight > el.clientHeight + 1) {
              return el.scrollTop + el.clientHeight >= el.scrollHeight - 4;
            }
            el = el.parentElement;
          }
          // Nothing overflows: the whole chat fits on screen, so it is already at its bottom.
          const root = document.scrollingElement;
          return !root || root.scrollTop + innerHeight >= root.scrollHeight - 4;
        })(\(point.x), \(point.y))
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            self.isCheckInFlight = false
            guard self.pan.state == .began || self.pan.state == .changed, result as? Bool == true, !self.isAtBottom else { return }
            self.isAtBottom = true
            // Measure the pull from where the finger was once the bottom was reached.
            self.baselineTranslation = self.pan.translation(in: webView).y
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
