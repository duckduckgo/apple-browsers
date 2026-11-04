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

import UIKit

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
        if let currentTab {
            refreshUnifiedToggleInput(for: currentTab)
        }
    }

    func refreshIPadFullTabChatInput(for tab: TabViewController, coordinator: UnifiedToggleInputCoordinator) {
        let isRefreshingCurrentTab = coordinator.currentTabUID == tab.tabModel.uid
        activateUnifiedToggleInput(for: tab.tabModel)

        switch refreshAction(for: tab, coordinator: coordinator, isRefreshingCurrentTab: isRefreshingCurrentTab) {
        case .refreshAITab(let behavior):
            prepareAITabInput(tab: tab, coordinator: coordinator)
            tab.installFullTabChatInput(coordinator.viewController)
            reconcileAIChatInputChromeForCurrentTab()
            applyAITabRefreshBehavior(behavior, coordinator: coordinator)
            applyIPadFullTabChatInputPose(coordinator: coordinator, animationStyle: .snap)
        case .unbindInactiveNonAITab, .refreshNonAITab, .preserveOmnibarSession:
            if coordinator.isActive {
                coordinator.hide()
                coordinator.unbind()
            }
            detachIPadFullTabChatInput(coordinator)
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
            self?.currentTab?.view.layoutIfNeeded()
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

/// Spans the tab's width under the chat, painted and separated like the iPhone Duck.ai tab footer.
final class FullTabChatInputContainerView: UIView {

    /// Matches the Duck.ai web chat column so the input lines up with the transcript above it.
    static let maximumInputWidth: CGFloat = 768

    /// Pins the web view container's bottom to this container's top while the input is visible.
    var webViewContainerBottomConstraint: NSLayoutConstraint?

    /// Matches the hairline iPhone draws above its collapsed footer.
    let topSeparator: UIView = {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(designSystemColor: .lines)
        separator.isUserInteractionEnabled = false
        return separator
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(designSystemColor: .surfaceCanvas)
        addSubview(topSeparator)
        NSLayoutConstraint.activate([
            topSeparator.topAnchor.constraint(equalTo: topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
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
        container.insertSubview(inputView, belowSubview: container.topSeparator)

        let preferredWidth = inputView.widthAnchor.constraint(equalToConstant: FullTabChatInputContainerView.maximumInputWidth)
        preferredWidth.priority = .defaultHigh
        var constraints = [
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            inputView.topAnchor.constraint(equalTo: container.topAnchor),
            inputView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            inputView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor),
            inputView.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor),
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

        UIView.performWithoutAnimation { view.layoutIfNeeded() }
    }

    func removeFullTabChatInput() {
        guard let container = fullTabChatInputContainer else { return }
        children.filter { $0.view.isDescendant(of: container) }.forEach { child in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        container.removeFromSuperview()
        fullTabChatInputContainer = nil
        webViewContainerBottomConstraint?.isActive = true
    }

    func setFullTabChatInputSeparatorVisible(_ visible: Bool) {
        fullTabChatInputContainer?.topSeparator.isHidden = !visible
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
