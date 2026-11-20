//
//  MainViewController+IPadFullTabChatInput.swift
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

import AIChat
import Combine
import UIKit
import UserScript
import WebKit

/// iPad runs the iPhone Duck.ai tab input (same coordinator, view and FE bridge) but keeps its own address bar and
/// tabs bar, so only the layout differs: the input sits at the bottom of the Duck.ai tab instead of replacing the omnibar.
extension MainViewController {

    /// True on iPad when the full-tab Duck.ai chat uses the native input. iPhone's input also takes over the omnibar.
    var isIPadFullTabChatInput: Bool {
        unifiedToggleInputFeature.isFullTabChatInputAvailable && !unifiedToggleInputFeature.isAvailable
    }

    func finishIPadFullTabChatInputSetUp(_ coordinator: UnifiedToggleInputCoordinator) {
        coordinator.attachmentPresentingViewController = self
        subscribeToIntentPublisher(coordinator)
        subscribeToModeChanges(coordinator)
        subscribeToSystemEvents()
        subscribeToToggleSettings()
        // With a hardware keyboard nothing hides when the input loses focus, so the bar follows the focus instead.
        NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)
            .filter { [weak coordinator] notification in
                guard let coordinator, let textView = notification.object as? UIView else { return false }
                return textView.isDescendant(of: coordinator.viewController.view)
            }
            .sink { [weak self] _ in self?.collapseUnfocusedIPadFullTabChatInput() }
            .store(in: &unifiedToggleInputCancellables)
        if let currentTab {
            refreshUnifiedToggleInput(for: currentTab)
        }
    }

    private func collapseUnfocusedIPadFullTabChatInput() {
        // Focus can move straight back, e.g. while the input re-renders, so judge it once that settles.
        DispatchQueue.main.async { [weak self] in
            guard let self, let coordinator = self.unifiedToggleInputCoordinator,
                  coordinator.isAITabExpanded,
                  !coordinator.isEditing,
                  !coordinator.viewController.isInputFirstResponder,
                  // Pickers the input opens take focus while it waits for their result.
                  self.presentedViewController == nil else { return }
            coordinator.showCollapsed()
        }
    }

    func refreshIPadFullTabChatInput(for tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) {
        let isRefreshingCurrentTab = coordinator.currentTabUID == tab.tabModel.uid
        activateUnifiedToggleInput(for: tab.tabModel)

        switch refreshAction(for: tab, coordinator: coordinator, isRefreshingCurrentTab: isRefreshingCurrentTab) {
        case .refreshAITab(let behavior):
            prepareAITabInput(tab: tab, coordinator: coordinator)
            tab.installFullTabChatInput(coordinator.viewController)
            // The input sits flush under the chat; narrow windows would otherwise draw the toolbar's hairline between them.
            tab.borderView.isBottomVisible = false
            installIPadChatListSidebar(in: tab)
            reconcileAIChatInputChromeForCurrentTab()
            applyAITabRefreshBehavior(behavior, coordinator: coordinator)
            applyIPadFullTabChatInputPose(coordinator: coordinator, animationStyle: .snap)
        case .unbindInactiveNonAITab, .refreshNonAITab, .preserveOmnibarSession:
            if coordinator.isActive {
                coordinator.hide()
                coordinator.unbind()
            }
            detachIPadFullTabChatInput(coordinator)
            detachIPadChatListSidebar()
            tab.borderView.isBottomVisible = true
        }
    }

    func handleIPadFullTabChatInputIntent(_ intent: UnifiedToggleInputIntent) {
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        switch intent {
        case .showCollapsed, .showExpanded:
            let layoutTarget = currentTab?.view ?? view!
            applyIPadFullTabChatInputPose(coordinator: coordinator,
                                          animationStyle: intent.animationStyle(layoutTarget: layoutTarget))
        case .hide:
            detachIPadFullTabChatInput(coordinator)
            coordinator.clearText()
        case .showOmnibarEditing, .showOmnibarInactive, .showOmnibarActive, .hideOmnibarEditing:
            // iPad never hands the omnibar to this input.
            break
        }
    }

    private func applyIPadFullTabChatInputPose(coordinator: UnifiedToggleInputCoordinator, animationStyle: UTIAnimationStyle) {
        guard coordinator.isAITabState else { return }
        animationStyle.perform { [weak self, weak coordinator] in
            guard let coordinator else { return }
            if coordinator.isInputEditing {
                self?.updateIPadFullTabChatInputHeightCap(coordinator: coordinator)
            }
            coordinator.viewController.apply(coordinator.computeRenderState().viewConfig, animated: false)
            self?.updateUnifiedInputContentVisibility(for: coordinator)
            // A tab refreshed before it joins a window lays out then; forcing it here makes the chats list's table warn.
            if let tabView = self?.currentTab?.view, tabView.window != nil {
                tabView.layoutIfNeeded()
            }
        }
    }

    /// Keeps a long prompt scrolling inside the card instead of growing past the top of the tab.
    func updateIPadFullTabChatInputHeightCap(coordinator: UnifiedToggleInputCoordinator) {
        guard let tabView = (coordinator.viewController.parent as? TabViewController)?.viewIfLoaded else { return }
        let keyboardTop: CGFloat
        if #available(iOS 16.0, *) {
            keyboardTop = tabView.keyboardLayoutGuide.layoutFrame.minY
        } else {
            keyboardTop = tabView.bounds.maxY - tabView.safeAreaInsets.bottom
        }
        let available = keyboardTop - tabView.safeAreaInsets.top - Constants.iPadFullTabChatInputTopClearance
        coordinator.viewController.setAvailableExpandedHeight(max(0, available))
    }

    private func detachIPadFullTabChatInput(_ coordinator: UnifiedToggleInputCoordinator) {
        (coordinator.viewController.parent as? TabViewController)?.removeFullTabChatInput()
    }
}

// MARK: - Tab hosting

/// Spans the chat column under the chat, painted like the page so the two read as one surface.
final class FullTabChatInputContainerView: UIView {

    /// Matches the Duck.ai web chat column so the input lines up with the transcript above it.
    static let maximumInputWidth: CGFloat = 768

    /// Pins the web view container's bottom to this container's top while the input is visible.
    var webViewContainerBottomConstraint: NSLayoutConstraint?

    /// The web view's colors before the chat repainted them, restored when the input leaves the tab.
    var webViewColorsBeforeInput: (background: UIColor?, scrollView: UIColor?, underPage: UIColor?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(singleUseColor: .duckAIWebViewBackground)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension TabViewController {

    func installFullTabChatInput(_ inputViewController: UIViewController) {
        guard inputViewController.parent !== self else { return }
        (inputViewController.parent as? TabViewController)?.removeFullTabChatInput()

        let container = FullTabChatInputContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        addChild(inputViewController)
        let inputView: UIView = inputViewController.view
        inputView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inputView)

        let preferredWidth = inputView.widthAnchor.constraint(equalToConstant: FullTabChatInputContainerView.maximumInputWidth)
        preferredWidth.priority = .defaultHigh
        // Follows the chat column, which the chats sidebar narrows.
        var constraints = [
            container.leadingAnchor.constraint(equalTo: containerStackView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: containerStackView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            inputView.topAnchor.constraint(equalTo: container.topAnchor),
            inputView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            inputView.leadingAnchor.constraint(greaterThanOrEqualTo: container.safeAreaLayoutGuide.leadingAnchor),
            inputView.trailingAnchor.constraint(lessThanOrEqualTo: container.safeAreaLayoutGuide.trailingAnchor),
            preferredWidth,
        ]
        let webViewAboveInput = webViewContainer.bottomAnchor.constraint(equalTo: container.topAnchor)
        container.webViewContainerBottomConstraint = webViewAboveInput
        constraints.append(webViewAboveInput)
        if #available(iOS 16.0, *) {
            constraints.append(inputView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor))
        } else {
            constraints.append(inputView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor))
        }
        webViewContainerBottomConstraint?.isActive = false
        NSLayoutConstraint.activate(constraints)
        inputViewController.didMove(toParent: self)
        fullTabChatInputContainer = container
        paintWebViewForChatInput(container)

        UIView.performWithoutAnimation { view.layoutIfNeeded() }
    }

    /// The chat's color for every surface the web view shows before and around Duck.ai's page, while the input is in this tab.
    var fullTabChatInputPageColor: UIColor? {
        fullTabChatInputContainer == nil ? nil : UIColor(singleUseColor: .duckAIWebViewBackground)
    }

    /// Until Duck.ai paints, the web view shows its anti-flash and theme colors, a second surface above the input.
    private func paintWebViewForChatInput(_ container: FullTabChatInputContainerView) {
        container.webViewColorsBeforeInput = (webView.backgroundColor, webView.scrollView.backgroundColor,
                                              webView.underPageBackgroundColor)
        let color = UIColor(singleUseColor: .duckAIWebViewBackground)
        webView.backgroundColor = color
        webView.scrollView.backgroundColor = color
        webView.underPageBackgroundColor = color
    }

    func removeFullTabChatInput() {
        guard let container = fullTabChatInputContainer else { return }
        children.filter { $0.view.isDescendant(of: container) }.forEach { child in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        if let colors = container.webViewColorsBeforeInput {
            webView.backgroundColor = colors.background
            webView.scrollView.backgroundColor = colors.scrollView
            webView.underPageBackgroundColor = colors.underPage
        }
        container.removeFromSuperview()
        fullTabChatInputContainer = nil
        webViewContainerBottomConstraint?.isActive = true
    }

    /// Voice mode and the FE's `hideChatInput` give the chat the whole tab.
    func setFullTabChatInputHidden(_ hidden: Bool) {
        guard let container = fullTabChatInputContainer, container.isHidden != hidden else { return }
        container.isHidden = hidden
        if hidden {
            container.webViewContainerBottomConstraint?.isActive = false
            webViewContainerBottomConstraint?.isActive = true
        } else {
            webViewContainerBottomConstraint?.isActive = false
            container.webViewContainerBottomConstraint?.isActive = true
        }
    }
}

// MARK: - Duck.ai loading skeleton

/// iPad's native input owns the bottom of the tab, so Duck.ai's own loading skeleton only flashes before the chat draws.
/// The page has no setting for it; the Duck.ai front end suggested this rule until it has one.
/// https://app.asana.com/1/137249556945/task/1220705777593462?focus=true
final class DuckAILoadingSkeletonUserScript: NSObject, UserScript {

    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let messageNames: [String] = []

    /// Nil unless iPad's full-tab chat uses the native input; `debugSettings` adds a debug Duck.ai host, if set.
    init?(unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding, debugSettings: AIChatDebugSettingsHandling) {
        guard unifiedToggleInputFeature.isFullTabChatInputAvailable, !unifiedToggleInputFeature.isAvailable else { return nil }
        let debugHosts = [debugSettings.messagePolicyHostname, debugSettings.customURL.flatMap { URL(string: $0)?.host }]
        let hosts = Set((["duck.ai"] + debugHosts).compactMap { $0 })
        guard let hostsJSON = try? JSONSerialization.data(withJSONObject: hosts.sorted()),
              let hostsList = String(data: hostsJSON, encoding: .utf8) else { return nil }
        source = """
        (() => {
            if (!\(hostsList).includes(location.hostname)) { return; }
            const style = document.createElement('style');
            style.textContent = '#app-loader { display: none !important; }';
            document.documentElement.appendChild(style);
        })();
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}
