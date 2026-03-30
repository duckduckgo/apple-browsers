//
//  AIChatCoordinator.swift
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
import Combine
import FeatureFlags
import PixelKit
import PrivacyConfig

/// Represents an event of hiding or showing an AI Chat tab sidebar.
///
/// - Note: This only refers to the logic of tab having sidebar shown or hidden,
///         not to sidebars getting on and off the screen due to switching browser tabs.
struct AIChatPresenceChange: Equatable {
    let tabID: TabIdentifier
    let isShown: Bool
}

/// Manages the presentation of an AI Chat sidebar in the browser.
///
/// Handles visibility, state management, and feature flag coordination for the AI Chat sidebar.
@MainActor
protocol AIChatCoordinating {

    /// Toggles the AI Chat sidebar visibility on a current tab, using appropriate animation.
    func toggleSidebar()

    /// Collapses the AI Chat sidebar on the current tab with or without animation.
    func collapseSidebar(withAnimation: Bool)

    /// Returns whether the AI Chat sidebar is open on a tab specified by `tabID`.
    func isSidebarOpen(for tabID: TabIdentifier) -> Bool

    /// Returns whether the AI Chat sidebar is currently open for the active tab.
    func isSidebarOpenForCurrentTab() -> Bool

    /// Returns whether AI Chat is currently visible (sidebar or floating) for the active tab.
    func isChatPresentedForCurrentTab() -> Bool

    /// Returns the date when the AI Chat sidebar was last hidden for a tab specified by `tabID`.
    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date?

    /// Returns the date when the AI Chat sidebar was last hidden for the active tab.
    func sidebarHiddenAtForCurrentTab() -> Date?

    /// Emits events whenever sidebar visibility changed for a tab.
    var sidebarPresenceDidChangePublisher: AnyPublisher<AIChatPresenceChange, Never> { get }

    /// Returns whether the AI Chat sidebar is detached into a floating window for a tab specified by `tabID`.
    func isChatFloating(for tabID: TabIdentifier) -> Bool

    /// Emits a `tabID` whenever a chat is floated, re-docked, or its floating window is closed.
    var chatFloatingStateDidChangePublisher: AnyPublisher<TabIdentifier, Never> { get }

    /// Brings the detached floating window for `tabID` to the front and makes it key.
    func focusFloatingWindow(for tabID: TabIdentifier)

    /// Closes a detached floating window for `tabID` if one exists.
    func closeFloatingWindow(for tabID: TabIdentifier)

    /// Closes AI Chat for `tabID` regardless of presentation mode.
    /// - Floating: closes the floating window.
    /// - Sidebar: collapses the sidebar.
    /// - Hidden: no-op.
    func closeChat(for tabID: TabIdentifier, withAnimation: Bool)

    /// Reveals AI Chat for the active tab with `prompt`.
    ///
    /// - Hidden: opens sidebar
    /// - Sidebar: keeps sidebar visible
    /// - Floating: keeps floating presentation and focuses its window
    func revealChat(for prompt: AIChatNativePrompt)
}

final class AIChatCoordinator: AIChatCoordinating {

    let sidebarPresenceDidChangePublisher: AnyPublisher<AIChatPresenceChange, Never>
    let chatFloatingStateDidChangePublisher: AnyPublisher<TabIdentifier, Never>

    private let sidebarHost: AIChatSidebarHosting
    private let sessionStore: AIChatSessionStoring
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatTabOpener: AIChatTabOpening
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: PixelFiring?
    private let featureFlagger: FeatureFlagger
    private var preferencesStorage: AIChatPreferencesStorage
    private let sidebarPresenceDidChangeSubject = PassthroughSubject<AIChatPresenceChange, Never>()
    private let chatFloatingStateDidChangeSubject = PassthroughSubject<TabIdentifier, Never>()

    private var isAnimatingSidebarTransition: Bool = false
    private var isResizeDragging: Bool = false
    private var resizePixelDebounceWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private enum Constants {
        static let defaultSidebarWidth: CGFloat = 400
        static let minSidebarWidth: CGFloat = 320
        static let maxSidebarWidth: CGFloat = 900
        static let fallbackFloatingFrame = NSRect(x: 200, y: 200, width: 400, height: 600)
    }

    /// Per-window default width, snapshotted from the global preference at init.
    /// Updated only by resizes happening in this window.
    private var windowDefaultWidth: CGFloat

    private var isSidebarResizable: Bool {
        featureFlagger.isFeatureOn(.aiChatSidebarResizable)
    }

    private var isChatFloatingEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatSidebarFloating)
    }

    init(
        sidebarHost: AIChatSidebarHosting,
        sessionStore: AIChatSessionStoring,
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
        aiChatTabOpener: AIChatTabOpening,
        windowControllersManager: WindowControllersManagerProtocol,
        pixelFiring: PixelFiring?,
        featureFlagger: FeatureFlagger,
        preferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage()
    ) {
        self.sidebarHost = sidebarHost
        self.sessionStore = sessionStore
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger
        self.preferencesStorage = preferencesStorage

        if let stored = preferencesStorage.lastUsedSidebarWidth, stored > 0 {
            self.windowDefaultWidth = Swift.min(Constants.maxSidebarWidth, Swift.max(Constants.minSidebarWidth, CGFloat(stored)))
        } else {
            self.windowDefaultWidth = Constants.defaultSidebarWidth
        }

        sidebarPresenceDidChangePublisher = sidebarPresenceDidChangeSubject.eraseToAnyPublisher()
        chatFloatingStateDidChangePublisher = chatFloatingStateDidChangeSubject.eraseToAnyPublisher()
        self.sidebarHost.aiChatSidebarHostingDelegate = self
        self.sidebarHost.aiChatSidebarResizeDelegate = self

        NotificationCenter.default.publisher(for: .aiChatNativeHandoffData)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard sidebarHost.isInKeyWindow,
                      let payload = notification.object as? AIChatPayload
                else { return }

                self?.handleAIChatHandoff(with: payload)
            }
            .store(in: &cancellables)

        featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshFloatingFeatureAvailability()
            }
            .store(in: &cancellables)

        windowControllersManager.stateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshFloatingTitleStateForAllSessions()
            }
            .store(in: &cancellables)

        // Normalize restored sessions against current flag state on startup.
        // Without this, a restored `.floating` session can stay stuck when the
        // floating feature is currently disabled.
        refreshFloatingFeatureAvailability()
    }

    // MARK: - Public API

    func toggleSidebar() {
        guard !isAnimatingSidebarTransition,
              let currentTabID = sidebarHost.currentTabID,
              !isChatFloating(for: currentTabID) else {
            return
        }

        if isSidebarOpen(for: currentTabID) {
            hideSidebar(for: currentTabID, animated: true)
        } else {
            showSidebar(for: currentTabID, animated: true)
        }
    }

    func collapseSidebar(withAnimation: Bool) {
        guard let currentTabID = sidebarHost.currentTabID,
              !isChatFloating(for: currentTabID) else {
            return
        }
        hideSidebar(for: currentTabID, animated: withAnimation)
    }

    func isSidebarOpen(for tabID: TabIdentifier) -> Bool {
        sessionStore.sessions[tabID]?.state.presentationMode == .sidebar
    }

    func isSidebarOpenForCurrentTab() -> Bool {
        guard let currentTabID = sidebarHost.currentTabID else { return false }
        return isSidebarOpen(for: currentTabID)
    }

    func isChatPresentedForCurrentTab() -> Bool {
        guard let currentTabID = sidebarHost.currentTabID else { return false }
        return isChatPresented(for: currentTabID)
    }

    func isChatFloating(for tabID: TabIdentifier) -> Bool {
        sessionStore.sessions[tabID]?.state.presentationMode == .floating
    }

    func focusFloatingWindow(for tabID: TabIdentifier) {
        sessionStore.sessions[tabID]?.floatingWindowController?.show()
    }

    func closeFloatingWindow(for tabID: TabIdentifier) {
        sessionStore.sessions[tabID]?.floatingWindowController?.close(reason: .system)
    }

    func closeChat(for tabID: TabIdentifier, withAnimation: Bool) {
        if isChatFloating(for: tabID) {
            closeFloatingWindow(for: tabID)
        } else if isSidebarOpen(for: tabID) {
            hideSidebar(for: tabID, animated: withAnimation)
        }
    }

    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date? {
        sessionStore.sessions[tabID]?.state.hiddenAt
    }

    func sidebarHiddenAtForCurrentTab() -> Date? {
        guard let currentTabID = sidebarHost.currentTabID else { return nil }
        return sidebarHiddenAt(for: currentTabID)
    }

    private func presentSidebar(for prompt: AIChatNativePrompt) {
        guard let currentTabID = sidebarHost.currentTabID,
              !isChatFloating(for: currentTabID) else { return }

        if let chatViewController = sessionStore.sessions[currentTabID]?.chatViewController {
            chatViewController.setAIChatPrompt(prompt)
        } else {
            AIChatPromptHandler.shared.setData(prompt)
            showSidebar(for: currentTabID, animated: true)
        }
    }

    func revealChat(for prompt: AIChatNativePrompt) {
        guard let currentTabID = sidebarHost.currentTabID else { return }
        if isChatFloating(for: currentTabID) {
            sessionStore.sessions[currentTabID]?.chatViewController?.setAIChatPrompt(prompt)
            focusFloatingWindow(for: currentTabID)
            return
        }

        presentSidebar(for: prompt)
    }

    // MARK: - Show / Hide / Collapse

    /// Prepares the session, embeds the VC, updates state, and animates the sidebar open.
    private func showSidebar(for tabID: TabIdentifier, animated: Bool) {
        sessionStore.expireSessionIfNeeded(for: tabID)

        let session = sessionStore.getOrCreateSession(for: tabID, burnerMode: sidebarHost.burnerMode)
        let chatViewController = session.chatViewController ?? session.makeChatViewController(tabID: tabID)

        chatViewController.isChatFloatingEnabled = isChatFloatingEnabled
        chatViewController.delegate = self
        sidebarHost.embedChatViewController(chatViewController, for: nil)
        session.state.setSidebar()

        sidebarPresenceDidChangeSubject.send(.init(tabID: tabID, isShown: true))
        transitionSidebar(for: tabID, isShowing: true, animated: animated)
    }

    /// Updates state, animates the sidebar closed, then tears down UI and ends the session.
    private func hideSidebar(for tabID: TabIdentifier, animated: Bool) {
        sessionStore.sessions[tabID]?.state.setHidden()
        sidebarPresenceDidChangeSubject.send(.init(tabID: tabID, isShown: false))

        transitionSidebar(for: tabID, isShowing: false, animated: animated) { [weak self] in
            guard let self else { return }
            self.tearDownUI(for: tabID)
            self.sessionStore.endSession(for: tabID)
        }
    }

    /// Instantly hides the sidebar container without touching any session state.
    private func collapseSidebar() {
        sidebarHost.sidebarContainerLeadingConstraint?.constant = 0
        sidebarHost.setResizeHandleVisible(false)
    }

    // MARK: - Sidebar Transition (pure visual)

    /// Animates (or immediately sets) the sidebar constraints.
    private func transitionSidebar(
        for tabID: TabIdentifier,
        isShowing: Bool,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        isAnimatingSidebarTransition = true
        sidebarHost.setResizeHandleVisible(false)
        isResizeDragging = false

        let tabWidth = sidebarWidth(for: tabID)
        let displayWidth = isShowing ? effectiveSidebarWidth(tabWidth: tabWidth, availableWidth: sidebarHost.availableWidth) : tabWidth
        let newConstraintValue = isShowing ? -displayWidth : 0.0

        sidebarHost.sidebarContainerWidthConstraint?.constant = displayWidth

        if animated {
            NSAnimationContext.runAnimationGroup { [weak self] context in
                guard let self else { return }
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidebarHost.sidebarContainerLeadingConstraint?.animator().constant = newConstraintValue
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.isAnimatingSidebarTransition = false
                if isShowing && self.isSidebarResizable {
                    self.sidebarHost.setResizeHandleVisible(true)
                }
                completion?()
            }
        } else {
            sidebarHost.sidebarContainerLeadingConstraint?.constant = newConstraintValue
            if isShowing && isSidebarResizable {
                sidebarHost.setResizeHandleVisible(true)
            }
            isAnimatingSidebarTransition = false
            completion?()
        }
    }

    // MARK: - Handoff

    private func handleAIChatHandoff(with payload: AIChatPayload) {
        guard let currentTabID = sidebarHost.currentTabID else { return }

        if isChatPresented(for: currentTabID) {
            aiChatTabOpener.openAIChatTab(with: .payload(payload), behavior: .newTab(selected: true))
        } else {
            /// https://app.asana.com/1/137249556945/project/276630244458377/task/1211982069731816
            sessionStore.removeSession(for: currentTabID)

            let session = sessionStore.getOrCreateSession(for: currentTabID, burnerMode: sidebarHost.burnerMode)
            let chatViewController = session.makeChatViewController(tabID: currentTabID)
            chatViewController.aiChatPayload = payload
            showSidebar(for: currentTabID, animated: true)
            pixelFiring?.fire(
                AIChatPixel.aiChatSidebarOpened(
                    source: .serp,
                    shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                    minutesSinceSidebarHidden: sidebarHiddenAt(for: currentTabID)?.minutesSinceNow()
                ),
                frequency: .dailyAndStandard
            )
        }
    }

    private func isChatPresented(for tabID: TabIdentifier) -> Bool {
        guard let mode = sessionStore.sessions[tabID]?.state.presentationMode else { return false }
        return mode != .hidden
    }

    private func refreshFloatingFeatureAvailability() {
        for (tabID, session) in sessionStore.sessions {
            session.chatViewController?.isChatFloatingEnabled = isChatFloatingEnabled
            if !isChatFloatingEnabled, session.state.presentationMode == .floating {
                // Session store is shared app-wide, but coordinator/UI lifecycle is per-window.
                // Only the owning coordinator should tear down and emit per-coordinator updates.
                if (owningCoordinator(for: tabID) ?? self) === self {
                    session.state.setHidden()
                    tearDownUI(for: tabID)
                    sessionStore.endSession(for: tabID)
                    chatFloatingStateDidChangeSubject.send(tabID)
                }
            }
        }
    }

    private func refreshFloatingTitleState(for tabID: TabIdentifier) {
        guard let session = sessionStore.sessions[tabID],
              session.state.presentationMode == .floating else {
            return
        }
        session.floatingWindowController?.updateTabViewModel(tabViewModel(for: tabID))
    }

    private func refreshFloatingTitleStateForAllSessions() {
        for tabID in sessionStore.sessions.keys {
            refreshFloatingTitleState(for: tabID)
        }
    }

    // MARK: - UI Teardown

    private func tearDownUI(for tabID: TabIdentifier) {
        guard let session = sessionStore.sessions[tabID] else { return }
        session.floatingWindowController?.close(reason: .teardown)
        session.chatViewController?.removeCompletely()
    }

    private func windowController(for tabID: TabIdentifier) -> MainWindowController? {
        windowControllersManager.mainWindowControllers.first { controller in
            let tabCollectionViewModel = controller.mainViewController.tabCollectionViewModel
            let hasRegularTab = tabCollectionViewModel.tabViewModels.keys.contains { $0.uuid == tabID }
            let hasPinnedTab = tabCollectionViewModel.pinnedTabsManager?.tabViewModels.keys.contains { $0.uuid == tabID } ?? false
            return hasRegularTab || hasPinnedTab
        }
    }

    private func tabViewModel(for tabID: TabIdentifier) -> TabViewModel? {
        for tabCollectionViewModel in windowControllersManager.allTabCollectionViewModels {
            if let regularTabViewModel = tabCollectionViewModel.tabViewModels.first(where: { $0.key.uuid == tabID })?.value {
                return regularTabViewModel
            }
            if let pinnedTabViewModel = tabCollectionViewModel.pinnedTabsManager?.tabViewModels.first(where: { $0.key.uuid == tabID })?.value {
                return pinnedTabViewModel
            }
        }
        return nil
    }

    // MARK: - Detach / Attach

    private func detachSidebar() {
        guard isChatFloatingEnabled,
              let tabID = sidebarHost.currentTabID,
              let session = sessionStore.sessions[tabID],
              let chatViewController = session.chatViewController,
              session.floatingWindowController == nil else {
            return
        }

        // Manual detach should always originate from the current sidebar location/size,
        // clamped to the visible screen area so the window is always reachable.
        let screenFrame = normalizedFloatingFrame(sidebarHost.sidebarContainerScreenFrame ?? Constants.fallbackFloatingFrame)
        session.state.floatingWindowFrame = screenFrame

        collapseSidebarPreservingWebView(chatViewController, for: tabID)

        let tabViewModel = tabViewModel(for: tabID)

        let controller = AIChatFloatingWindowController(
            tabID: tabID,
            chatViewController: chatViewController,
            tabViewModel: tabViewModel,
            contentRect: screenFrame)
        controller.delegate = self
        controller.onFrameChanged = { [weak session] frame in
            session?.state.floatingWindowFrame = frame
        }

        session.floatingWindowController = controller
        session.state.setFloating()
        refreshFloatingTitleState(for: tabID)

        controller.show()
        fireAIChatSidebarPixel(.aiChatSidebarDetached)
        chatFloatingStateDidChangeSubject.send(tabID)
    }

    private func restoreFloatingWindowIfNeeded(for tabID: TabIdentifier) {
        guard isChatFloatingEnabled,
              let session = sessionStore.sessions[tabID] else {
            return
        }

        guard session.state.presentationMode == .floating else {
            return
        }

        if session.floatingWindowController != nil {
            return
        }

        let chatViewController = session.chatViewController ?? session.makeChatViewController(tabID: tabID)
        chatViewController.isChatFloatingEnabled = isChatFloatingEnabled
        chatViewController.delegate = self
        chatViewController.removeCompletely()

        let tabViewModel = tabViewModel(for: tabID)
        let frame = normalizedFloatingFrame(session.state.floatingWindowFrame ?? sidebarHost.sidebarContainerScreenFrame ?? Constants.fallbackFloatingFrame)

        let controller = AIChatFloatingWindowController(
            tabID: tabID,
            chatViewController: chatViewController,
            tabViewModel: tabViewModel,
            contentRect: frame)
        controller.delegate = self
        controller.onFrameChanged = { [weak session] frame in
            session?.state.floatingWindowFrame = frame
        }
        session.floatingWindowController = controller
        session.state.floatingWindowFrame = frame
        refreshFloatingTitleState(for: tabID)
        // Show only when re-creating a missing floating window (e.g. restoration path).
        controller.show()
        chatFloatingStateDidChangeSubject.send(tabID)
    }

    private func attachSidebar(for tabID: TabIdentifier) {
        guard let session = sessionStore.sessions[tabID],
              let controller = session.floatingWindowController else {
            return
        }

        let floatingFrame = controller.frame
        controller.onFrameChanged = nil

        guard let chatViewController = controller.detachChatViewController() else {
            controller.close(reason: .attach)
            session.floatingWindowController = nil
            session.state.setHidden()
            chatFloatingStateDidChangeSubject.send(tabID)
            return
        }

        session.state.floatingWindowFrame = floatingFrame
        // Set sidebar mode before any tab/window focus changes to avoid
        // a transient "floating without controller" state.
        session.state.setSidebar()

        windowController(for: tabID)?.window?.makeKeyAndOrderFront(nil)

        chatViewController.delegate = self
        let isSelectingDifferentTab = sidebarHost.currentTabID != tabID
        sidebarHost.embedChatViewController(chatViewController, for: tabID)

        // If embedding selects a different tab, sidebarHostDidSelectTab will drive
        // the sidebar show flow. Only run it here when tab selection does not change.
        if !isSelectingDifferentTab {
            sidebarPresenceDidChangeSubject.send(.init(tabID: tabID, isShown: true))
            transitionSidebar(for: tabID, isShowing: true, animated: false)
        }

        controller.close(reason: .attach)
        session.floatingWindowController = nil

        fireAIChatSidebarPixel(.aiChatSidebarAttached)
        chatFloatingStateDidChangeSubject.send(tabID)
    }
}

// MARK: - AIChatSidebarHostingDelegate

extension AIChatCoordinator: AIChatSidebarHostingDelegate {

    func sidebarHostDidSelectTab(with tabID: TabIdentifier) {
        let mode = sessionStore.sessions[tabID]?.state.presentationMode ?? .hidden
        switch mode {
        case .sidebar:
            showSidebar(for: tabID, animated: false)
        case .floating, .hidden:
            collapseSidebar()
            if mode == .floating {
                restoreFloatingWindowIfNeeded(for: tabID)
            }
        }
        refreshFloatingTitleStateForAllSessions()
    }

    func sidebarHostDidUpdateTabs() {
        performOrphanCleanup()
    }
}

// MARK: - AIChatViewControllerDelegate

extension AIChatCoordinator: AIChatViewControllerDelegate {

    func didClickOpenInNewTabButton() {
        guard let currentTabID = sidebarHost.currentTabID,
              let session = sessionStore.sessions[currentTabID] else { return }

        pixelFiring?.fire(AIChatPixel.aiChatSidebarExpanded, frequency: .dailyAndStandard)

        let restorationData = session.state.restorationData
        let currentAIChatURL = session.currentAIChatURL.removingAIChatPlacementParameter()
        let isCurrentTabNewTab = tabViewModel(for: currentTabID)?.tab.content == .newtab

        toggleSidebar()

        Task { @MainActor in
            let behavior: LinkOpenBehavior = isCurrentTabNewTab ? .currentTab : .newTab(selected: true)
            if let data = restorationData {
                aiChatTabOpener.openAIChatTab(with: .restoration(data), behavior: behavior)
            } else {
                aiChatTabOpener.openAIChatTab(with: .url(currentAIChatURL), behavior: behavior)
            }
        }
    }

    func didClickCloseButton() {
        pixelFiring?.fire(AIChatPixel.aiChatSidebarClosed(source: .sidebarCloseButton), frequency: .dailyAndStandard)

        if let tabID = sidebarHost.currentTabID {
            windowController(for: tabID)?.window?.makeFirstResponder(nil)
        }
        toggleSidebar()
    }

    func didClickDetachButton() {
        detachSidebar()
    }

    func didClickAttachButton(for tabID: TabIdentifier) {
        (owningCoordinator(for: tabID) ?? self).attachSidebar(for: tabID)
    }

    func didClickTitleButton(for tabID: TabIdentifier) {
        fireAIChatSidebarPixel(.aiChatSidebarFloatingTabActivated)
        (owningCoordinator(for: tabID) ?? self).activateTabFromFloatingTitle(for: tabID)
    }
}

// MARK: - AIChatSidebarResizeDelegate

extension AIChatCoordinator: AIChatSidebarResizeDelegate {

    @discardableResult
    func sidebarHostDidResize(to width: CGFloat) -> CGFloat {
        guard !isAnimatingSidebarTransition else { return width }
        isResizeDragging = true
        let clampedWidth = clampSidebarWidth(width)
        sidebarHost.applySidebarWidth(clampedWidth)
        return clampedWidth
    }

    func sidebarHostDidFinishResize(to width: CGFloat) {
        guard !isAnimatingSidebarTransition,
              let currentTabID = sidebarHost.currentTabID else { return }
        isResizeDragging = false
        let clampedWidth = clampSidebarWidth(width)
        sidebarHost.applySidebarWidth(clampedWidth)
        windowDefaultWidth = clampedWidth
        sessionStore.sessions[currentTabID]?.state.sidebarWidth = clampedWidth
        preferencesStorage.lastUsedSidebarWidth = Double(clampedWidth)
        fireResizedPixelDebounced(width: clampedWidth)
    }

    func sidebarHostDidChangeAvailableWidth(_ availableWidth: CGFloat) {
        guard !isAnimatingSidebarTransition,
              !isResizeDragging,
              let currentTabID = sidebarHost.currentTabID,
              isSidebarOpen(for: currentTabID) else { return }
        let tabWidth = sidebarWidth(for: currentTabID)
        let effectiveWidth = effectiveSidebarWidth(tabWidth: tabWidth, availableWidth: availableWidth)
        sidebarHost.applySidebarWidth(effectiveWidth)
    }

    // MARK: - Private Helpers

    /// Hides the docked sidebar container visually without running the full close flow.
    private func collapseSidebarPreservingWebView(_ chatViewController: NSViewController, for tabID: TabIdentifier) {
        chatViewController.removeCompletely()
        sidebarHost.sidebarContainerLeadingConstraint?.constant = 0
        sidebarHost.setResizeHandleVisible(false)
        sidebarPresenceDidChangeSubject.send(.init(tabID: tabID, isShown: false))
    }

    private func fireResizedPixelDebounced(width: CGFloat) {
        resizePixelDebounceWorkItem?.cancel()
        let widthInt = Int(width)
        let workItem = DispatchWorkItem { [weak self] in
            self?.pixelFiring?.fire(AIChatPixel.aiChatSidebarResized(width: widthInt), frequency: .dailyAndStandard)
        }
        resizePixelDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func sidebarWidth(for tabID: TabIdentifier) -> CGFloat {
        sessionStore.sessions[tabID]?.state.sidebarWidth ?? windowDefaultWidth
    }

    private func clampSidebarWidth(_ width: CGFloat) -> CGFloat {
        let maxWidth = max(Constants.minSidebarWidth, min(Constants.maxSidebarWidth, sidebarHost.availableWidth / 2))
        return min(maxWidth, max(Constants.minSidebarWidth, width))
    }

    private func effectiveSidebarWidth(tabWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        if availableWidth >= 2 * tabWidth {
            return tabWidth
        }

        let halfWidth = availableWidth / 2
        return max(Constants.minSidebarWidth, halfWidth)
    }

    private func normalizedFloatingFrame(_ frame: NSRect) -> NSRect {
        guard let screen = targetScreen() else {
            return frame
        }

        let visibleFrame = screen.visibleFrame
        let width = max(1, min(frame.width, visibleFrame.width))
        let height = max(1, min(frame.height, visibleFrame.height))
        let clampedX = max(visibleFrame.minX, min(frame.origin.x, visibleFrame.maxX - width))
        let clampedY = max(visibleFrame.minY, min(frame.origin.y, visibleFrame.maxY - height))

        let normalized = NSRect(x: clampedX, y: clampedY, width: width, height: height)
        return normalized
    }

    private func targetScreen() -> NSScreen? {
        let anchorFrame = sidebarHost.sidebarContainerScreenFrame ?? Constants.fallbackFloatingFrame
        if let screenContainingAnchor = NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchorFrame) }) {
            return screenContainingAnchor
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func performOrphanCleanup() {
        let currentTabIDsFromCollections = Set(
            windowControllersManager.allTabCollectionViewModels.flatMap { tabCollectionViewModel in
                let unpinnedTabIDs = tabCollectionViewModel.tabCollection.tabs.map(\.uuid)
                let pinnedTabIDs = tabCollectionViewModel.pinnedTabsCollection?.tabs.map(\.uuid) ?? []
                return unpinnedTabIDs + pinnedTabIDs
            }
        )
        let currentTabIDsFromViewModels = Set(
            windowControllersManager.allTabCollectionViewModels.flatMap { tabCollectionViewModel in
                let unpinnedTabIDs = tabCollectionViewModel.tabViewModels.keys.map(\.uuid)
                let pinnedTabIDs = tabCollectionViewModel.pinnedTabsManager?.tabViewModels.keys.map(\.uuid) ?? []
                return unpinnedTabIDs + pinnedTabIDs
            }
        )
        let currentTabIDs = currentTabIDsFromCollections

        let initiallyRemovedTabIDs = Set(sessionStore.sessions.keys).subtracting(currentTabIDs)
        let protectedFloatingTabIDs = Set(initiallyRemovedTabIDs.filter { tabID in
            guard let session = sessionStore.sessions[tabID] else { return false }
            let isFloatingAndVisible = session.state.presentationMode == .floating && session.floatingWindowController?.isShowing == true
            // Protect only transient tab-list churn (S11): if tab is still represented by live view models.
            return isFloatingAndVisible && currentTabIDsFromViewModels.contains(tabID)
        })
        let effectiveCurrentTabIDs = currentTabIDs.union(protectedFloatingTabIDs)
        let removedTabIDs = Set(sessionStore.sessions.keys).subtracting(effectiveCurrentTabIDs)
        for tabID in removedTabIDs {
            tearDownUI(for: tabID)
        }

        sessionStore.removeOrphanedSessions(currentTabIDs: Array(effectiveCurrentTabIDs))
    }
}

// MARK: - AIChatFloatingWindowControllerDelegate

extension AIChatCoordinator: AIChatFloatingWindowControllerDelegate {

    func floatingWindowDidClose(_ controller: AIChatFloatingWindowController, initiatedByUser: Bool) {
        let tabID = controller.tabID
        if let session = sessionStore.sessions[tabID] {
            session.state.floatingWindowFrame = controller.frame
            session.floatingWindowController = nil
        }
        tearDownUI(for: tabID)
        sessionStore.endSession(for: tabID)

        if initiatedByUser {
            fireAIChatSidebarPixel(.aiChatSidebarFloatingClosed)
        }

        chatFloatingStateDidChangeSubject.send(tabID)
    }

}

private extension AIChatCoordinator {

    func activateTabFromFloatingTitle(for tabID: TabIdentifier) {
        windowController(for: tabID)?.window?.makeKeyAndOrderFront(nil)
        sidebarHost.selectTab(with: tabID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.sessionStore.sessions[tabID]?.floatingWindowController?.show()
        }
        refreshFloatingTitleState(for: tabID)
    }

    func owningCoordinator(for tabID: TabIdentifier) -> AIChatCoordinator? {
        windowController(for: tabID)?.mainViewController.aiChatCoordinator as? AIChatCoordinator
    }

    func fireAIChatSidebarPixel(_ pixel: AIChatPixel) {
        pixelFiring?.fire(pixel, frequency: .dailyAndStandard)
    }
}
