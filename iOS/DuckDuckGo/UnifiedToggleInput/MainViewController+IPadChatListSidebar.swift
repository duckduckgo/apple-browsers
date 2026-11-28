//
//  MainViewController+IPadChatListSidebar.swift
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
import Common
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// iPad's full-tab Duck.ai chat shows the iPhone Chats list as a column beside the chat, in place of
/// the web page's own sidebar. One list follows whichever Duck.ai tab is on screen.
extension MainViewController {

    /// The list reads chats from native storage, so it needs that on as well as the native input.
    var isIPadChatListSidebarAvailable: Bool {
        isIPadFullTabChatInput && featureFlagger.isFeatureOn(.aiChatNativeStorage)
    }

    /// The "Chats" entry points (address bar menu, app menu, contextual "View all") load `sidebar=open`. The page would
    /// open its own chats drawer under this list too, so the page loads without it; the caller opens this list instead.
    func nativeChatListRequest(for url: URL) -> (url: URL, requestsChatList: Bool) {
        // The host check also takes a debug Duck.ai URL, which `isDuckAIURL` doesn't know.
        guard isIPadChatListSidebarAvailable,
              url.isDuckAIURL || url.host == aiChatSettings.aiChatURL.host,
              Self.requestsChatList(url) else { return (url, false) }
        return (url.removingParameters(named: [AIChatURLParameters.sidebarName]), true)
    }

    /// The list opens when the next Duck.ai tab installs it, so a tab still being built shows it from the start.
    func openIPadChatListSidebarOnNextInstall() {
        if !iPadChatListSidebarState.isOpen {
            // The tab may not exist yet; it spans the window, as this view does.
            iPadChatListSidebarState.instrumentation.sidebarOpened(source: .chatsEntryPoint,
                                                                  layout: iPadChatListSidebarLayout(tabWidth: view.bounds.width))
        }
        iPadChatListSidebarState.isOpen = true
    }

    private static func requestsChatList(_ url: URL?) -> Bool {
        url?.getParameter(named: AIChatURLParameters.sidebarName) == AIChatURLParameters.sidebarOpenValue
    }

    func installIPadChatListSidebar(in tab: TabViewController) {
        guard isIPadChatListSidebarAvailable else { return }
        openIPadChatListSidebarIfRequested(by: tab)
        let sidebar = iPadChatListSidebar(isFireMode: tab.tabModel.fireTab)
        tab.installChatListSidebar(sidebar.navigationController,
                                   isOpen: iPadChatListSidebarState.isOpen,
                                   onToggle: { [weak self] in self?.toggleIPadChatListSidebar(from: .chatsButton) },
                                   onNewChat: { [weak self] in
                                       self?.iPadChatListSidebarState.instrumentation.floatingNewChatTapped()
                                       self?.startNewChatFromIPadChatListSidebar()
                                   },
                                   onTabWidthChange: { [weak self] in self?.updateIPadChatListButtonPlacement() })
        sidebar.followCurrentChat(of: tab)
        // Identified actions replace each other, so installing on every Duck.ai tab adds just one.
        unifiedToggleInputCoordinator?.viewController.aiTabChatsButton.addAction(UIAction(identifier: .iPadChatListInputButton) { [weak self] _ in
            self?.toggleIPadChatListSidebar(from: .inputChatsButton)
        }, for: .touchUpInside)
        updateIPadChatListButtonPlacement()
    }

    /// The floating Chats button covers the page's text in narrow windows, so there the input carries it instead.
    func updateIPadChatListButtonPlacement() {
        let tab = iPadChatListSidebarState.sidebar?.navigationController.parent as? TabViewController
        let container = tab?.chatListSidebarContainer
        // Voice and Duck.ai's `hideChatInput` hide the input, and its button with it.
        let isInputShown = tab?.fullTabChatInputContainer?.isHidden == false
        let isBesideInput = container?.floatingButtonCoversPage == true && isInputShown
        container?.setFloatingButtonsHidden(isBesideInput)
        guard let coordinator = unifiedToggleInputCoordinator else { return }
        coordinator.viewController.setFlankingAccessoriesVisible(isBesideInput && coordinator.isAITabCollapsed ? .chats : [])
    }

    /// Loads that skip `addTab`/`loadUrl` (background tabs, links, history) still carry `sidebar=open`.
    private func openIPadChatListSidebarIfRequested(by tab: TabViewController) {
        let requestsChatList = Self.requestsChatList(tab.url ?? tab.link?.url)
        defer { tab.hasOpenedChatListSidebarFromURL = requestsChatList }
        guard requestsChatList, !tab.hasOpenedChatListSidebarFromURL else { return }
        openIPadChatListSidebarOnNextInstall()
    }

    func detachIPadChatListSidebar() {
        guard let sidebar = iPadChatListSidebarState.sidebar else { return }
        (sidebar.navigationController.parent as? TabViewController)?.removeChatListSidebar()
        sidebar.stopFollowingCurrentChat()
    }

    private func toggleIPadChatListSidebar(from button: AIChatHistorySidebarPixel.ChatsButton) {
        let isOpening = !iPadChatListSidebarState.isOpen
        if let tab = iPadChatListSidebarTab {
            let layout = iPadChatListSidebarLayout(tabWidth: tab.view.bounds.width)
            if isOpening {
                iPadChatListSidebarState.instrumentation.sidebarOpened(source: button.openSource, layout: layout)
            } else {
                iPadChatListSidebarState.instrumentation.sidebarClosed(source: button.closeSource, layout: layout)
            }
        }
        setIPadChatListSidebarOpen(isOpening)
    }

    /// Closes that follow a new chat or a picked chat go through `setIPadChatListSidebarOpen` and aren't reported.
    fileprivate func closeIPadChatListSidebarFromCloseButton() {
        if iPadChatListSidebarState.isOpen, let tab = iPadChatListSidebarTab {
            iPadChatListSidebarState.instrumentation.sidebarClosed(source: .closeButton,
                                                                  layout: iPadChatListSidebarLayout(tabWidth: tab.view.bounds.width))
        }
        setIPadChatListSidebarOpen(false)
    }

    private var iPadChatListSidebarTab: TabViewController? {
        iPadChatListSidebarState.sidebar?.navigationController.parent as? TabViewController
    }

    private func iPadChatListSidebarLayout(tabWidth: CGFloat) -> AIChatHistorySidebarPixel.Layout {
        IPadChatListSidebarContainerView.isOverlay(forTabWidth: tabWidth) ? .overlay : .column
    }

    func setIPadChatListSidebarOpen(_ isOpen: Bool, endsEditing: Bool = true) {
        iPadChatListSidebarState.isOpen = isOpen
        guard let tab = iPadChatListSidebarState.sidebar?.navigationController.parent as? TabViewController else { return }
        // Opening the list means switching or starting a chat, so the keyboard goes down either way.
        if endsEditing {
            tab.view.endEditing(true)
        }
        tab.setChatListSidebarOpen(isOpen, animated: true)
    }

    /// Typing into the chat input means the user is back on the chat, so the list gets out of its way.
    func closeIPadChatListSidebarForFocusedInput() {
        guard iPadChatListSidebarState.isOpen else { return }
        setIPadChatListSidebarOpen(false, endsEditing: false)
    }

    private func iPadChatListSidebar(isFireMode: Bool) -> IPadChatListSidebar {
        if let sidebar = iPadChatListSidebarState.sidebar, sidebar.isFireMode == isFireMode {
            return sidebar
        }
        // Fire tabs read their own storage, so switching between fire and regular tabs needs another list.
        detachIPadChatListSidebar()
        let viewModel = makeAIChatHistoryViewModel(source: .browserMenu, isFireMode: isFireMode)
        let sidebar = IPadChatListSidebar(viewModel: viewModel,
                                          fireButtonAnimator: fireButtonAnimator,
                                          isFireMode: isFireMode,
                                          host: self)
        iPadChatListSidebarState.sidebar = sidebar
        return sidebar
    }

    // MARK: - Sidebar actions

    fileprivate func startNewChatFromIPadChatListSidebar() {
        guard let tab = currentTab, tab.isAITab else { return }
        duckAIInputFocus.forget()
        // A new chat starts the conversation on screen, so the list gets out of the way before the input takes focus.
        if iPadChatListSidebarState.isOpen {
            setIPadChatListSidebarOpen(false)
        }
        beginNewChatFromHistory(in: tab)
        unifiedToggleInputCoordinator?.showExpanded(inputMode: .aiChat)
    }

    /// Deleting the open chat from the list leaves the tab on a fresh chat rather than on a chat that's gone.
    fileprivate func leaveDeletedChatFromIPadChatListSidebar() {
        guard let tab = currentTab, tab.isAITab else { return }
        iPadChatListSidebarState.instrumentation.openChatDeleted()
        unifiedToggleInputCoordinator?.startNewChat()
        tab.submitStartChatAction()
    }

    /// Duck.ai opens the chat in place; the URL load is the fallback when the page can't.
    fileprivate func openChatFromIPadChatListSidebar(chatId: String) {
        // The list lies over the chat, so it gets out of the way of what the user just picked.
        if iPadChatListSidebarState.isOpen {
            setIPadChatListSidebarOpen(false)
        }
        guard let tab = currentTab, tab.openChatID(in: tab.url) != chatId else { return }
        duckAIInputFocus.forget()
        iPadChatListSidebarState.pendingChatOpen?.cancel()
        let url = aiChatSettings.aiChatURL.withChatID(chatId)
        guard tab.isAITab else {
            onChatHistorySelected(url: url)
            return
        }
        recordChatHistorySelection()
        // Marked now rather than when the page reports it; a fallback load lands on the same chat.
        iPadChatListSidebarState.sidebar?.historyViewController.currentChatId = chatId
        iPadChatListSidebarState.pendingChatOpen = Task { @MainActor [weak self, weak tab] in
            let outcome = await tab?.openChatInPage(chatId: chatId)
            guard !Task.isCancelled, let self, let tab, tab === self.currentTab else { return }
            guard outcome == .opened else {
                self.iPadChatListSidebarState.instrumentation.chatOpenFellBack(outcome: outcome)
                self.loadChatFromHistory(url)
                return
            }
            // No page load follows to take the stamp.
            tab.tabModel.duckAIEntrySource = .chatHistoryOpenChat
            tab.tabModel.discardDuckAIEntrySourceAwaitingPageLoad()
        }
    }
}

private extension UIAction.Identifier {
    static let iPadChatListInputButton = UIAction.Identifier("com.duckduckgo.ipad.chatList.inputButton")
}

private extension TabViewController {
    /// Unlike `URL.duckAIChatID`, also reads the debug Duck.ai URL, which the tab already counts as Duck.ai.
    func openChatID(in url: URL?) -> String? {
        guard isAITab, let chatId = url?.getParameter(named: "chatID"), !chatId.isEmpty else { return nil }
        return chatId
    }
}

/// Where the list lives between Duck.ai tabs, and whether it was last left open.
final class IPadChatListSidebarState {
    let instrumentation: AIChatHistorySidebarInstrumentation
    fileprivate(set) var sidebar: IPadChatListSidebar?
    fileprivate(set) var isOpen = false
    fileprivate var pendingChatOpen: Task<Void, Never>?

    init(instrumentation: AIChatHistorySidebarInstrumentation = DefaultAIChatHistorySidebarInstrumentation()) {
        self.instrumentation = instrumentation
    }
}

/// Owns the list and answers its requests on behalf of `MainViewController`.
@MainActor
final class IPadChatListSidebar {

    let navigationController: UINavigationController
    let historyViewController: AIChatHistoryViewController
    let isFireMode: Bool

    private let viewModel: AIChatHistoryViewModel
    private weak var host: MainViewController?
    private var currentChatCancellable: AnyCancellable?
    private var storedChatsCancellable: AnyCancellable?
    private var storedChatIds: Set<String> = []

    fileprivate init(viewModel: AIChatHistoryViewModel, fireButtonAnimator: FireButtonAnimator, isFireMode: Bool, host: MainViewController) {
        self.viewModel = viewModel
        self.isFireMode = isFireMode
        self.host = host
        historyViewController = AIChatHistoryViewController(viewModel: viewModel,
                                                            fireButtonAnimator: fireButtonAnimator,
                                                            presentation: .sidebar)
        navigationController = IPadChatListNavigationController(rootViewController: historyViewController)
        viewModel.delegate = self
        historyViewController.sidebarDelegate = self
        // Every stored chat, not the rows a search leaves; a failed read is skipped, since it says nothing was deleted.
        storedChatsCancellable = viewModel.$storedChatIds
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] chatIds in
                self?.storedChatsDidChange(chatIds)
            }
    }

    private func storedChatsDidChange(_ chatIds: Set<String>) {
        defer { storedChatIds = chatIds }
        guard let currentChatId = historyViewController.currentChatId,
              storedChatIds.contains(currentChatId),
              !chatIds.contains(currentChatId) else { return }
        host?.leaveDeletedChatFromIPadChatListSidebar()
    }

    /// The page reports the open chat in its URL, including chats started from the input.
    fileprivate func followCurrentChat(of tab: TabViewController) {
        currentChatCancellable = tab.webView?.publisher(for: \.url)
            .map { [weak tab] url in tab?.openChatID(in: url) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chatId in
                self?.historyViewController.currentChatId = chatId
            }
    }

    fileprivate func stopFollowingCurrentChat() {
        currentChatCancellable = nil
    }
}

extension IPadChatListSidebar: AIChatHistoryViewModelDelegate {

    func viewModelDidRequestOpenNewChat() {
        host?.startNewChatFromIPadChatListSidebar()
    }

    func viewModelDidRequestOpenChat(chatId: String) {
        host?.openChatFromIPadChatListSidebar(chatId: chatId)
    }

    func viewModelDidRequestChatProtection() {
        host?.currentTab?.submitOpenChatProtectionAction()
    }

    func viewModelDidRequestDataClearingSettings() {
        host?.setIPadChatListSidebarOpen(false)
        host?.segueToSettingsDataClearing()
    }

    func viewModelDidExportChat(filename: String) {
        host?.viewModelDidExportChat(filename: filename)
    }

    func viewModelDidExportChats(count: Int) {
        host?.viewModelDidExportChats(count: count)
    }

    func viewModelDidFailExport() {
        host?.viewModelDidFailExport()
    }

    /// The sidebar never closes as a screen; it stays in the tab.
    func viewModelWillClose() {}
}

extension IPadChatListSidebar: AIChatHistorySidebarDelegate {

    var chatHistorySidebarIsSyncEnabled: Bool {
        host?.syncService.authState != .inactive
    }

    func chatHistorySidebarDidRequestClose() {
        host?.closeIPadChatListSidebarFromCloseButton()
    }

    func chatHistorySidebarDidRequestSyncSettings() {
        host?.iPadChatListSidebarState.instrumentation.menuActionSelected(.syncSettings)
        host?.segueToSettingsSync()
    }

    func chatHistorySidebarDidRequestDuckAISettings() {
        host?.iPadChatListSidebarState.instrumentation.menuActionSelected(.duckAISettings)
        host?.currentTab?.submitOpenSettingsAction()
    }
}

// MARK: - Tab hosting

/// The list over the chat's leading edge, plus the two buttons that stand in for it while it's closed. It never resizes
/// the chat, which would reflow the page; in a narrow window it covers the whole tab, like the iPhone Chats screen.
final class IPadChatListSidebarContainerView: UIView {

    static let width: CGFloat = 320

    private enum Constants {
        static let buttonSize: CGFloat = 44
        static let buttonInset: CGFloat = 16
        static let animationDuration: TimeInterval = 0.35
        /// Below this the chat beside the column gets too narrow to read.
        static let minimumChatWidth: CGFloat = 450
        /// Duck.ai centers a ~663 pt column; below this its left edge passes under the floating Chats button.
        static let minimumChatWidthForFloatingButton: CGFloat = 800
    }

    fileprivate let showChatsButton = IPadChatListSidebarContainerView.makeFloatingButton(
        image: DesignSystemImages.Glyphs.Size24.chats.withRenderingMode(.alwaysTemplate),
        accessibilityLabel: UserText.aiChatHistorySidebarShowAccessibilityLabel)
    fileprivate let newChatButton = IPadChatListSidebarContainerView.makeFloatingButton(
        image: DesignSystemImages.Glyphs.Size24.compose,
        accessibilityLabel: UserText.actionNewAIChat)
    fileprivate let widthProbe = WidthProbeView()

    fileprivate var leadingConstraint: NSLayoutConstraint?
    fileprivate var columnWidthConstraint: NSLayoutConstraint?
    fileprivate var overlayWidthConstraint: NSLayoutConstraint?
    fileprivate var onToggle: (() -> Void)?
    fileprivate var onNewChat: (() -> Void)?
    fileprivate var onTabWidthChange: (() -> Void)?
    fileprivate(set) var isOpen = false
    fileprivate(set) var isOverlay = false
    private var tabWidth: CGFloat = 0
    private var areFloatingButtonsHidden = false

    /// Measured on the tab, which the chat fills whenever the floating button shows.
    var floatingButtonCoversPage: Bool {
        tabWidth > 0 && tabWidth < Constants.minimumChatWidthForFloatingButton
    }

    /// The input carries Chats in narrow windows, in the slot New Chat would take.
    func setFloatingButtonsHidden(_ isHidden: Bool) {
        guard isHidden != areFloatingButtonsHidden else { return }
        areFloatingButtonsHidden = isHidden
        applyOpenState(isOpen)
    }

    private let separator: UIView = {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(designSystemColor: .lines)
        return separator
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(designSystemColor: .surface)
        clipsToBounds = true
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        showChatsButton.addTarget(self, action: #selector(showChatsTapped), for: .touchUpInside)
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        widthProbe.onWidthChange = { [weak self] width in
            self?.applyLayoutMode(forTabWidth: width)
            self?.onTabWidthChange?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Asks the host to open or close the list, so its remembered state stays in step.
    func requestToggle() {
        onToggle?()
    }

    fileprivate func applyOpenState(_ isOpen: Bool) {
        self.isOpen = isOpen
        let closedOffset = isOverlay ? -(superview?.bounds.width ?? Self.width) : -Self.width
        leadingConstraint?.constant = isOpen ? 0 : closedOffset
        showChatsButton.alpha = isOpen ? 0 : 1
        newChatButton.alpha = isOpen ? 0 : 1
        accessibilityElementsHidden = !isOpen
        showChatsButton.isHidden = areFloatingButtonsHidden
        showChatsButton.isAccessibilityElement = !isOpen && !areFloatingButtonsHidden
        // A narrow window's input spans the tab under the button.
        let hidesNewChatButton = isOverlay || areFloatingButtonsHidden
        newChatButton.isHidden = hidesNewChatButton
        newChatButton.isAccessibilityElement = !isOpen && !hidesNewChatButton
    }

    static func isOverlay(forTabWidth tabWidth: CGFloat) -> Bool {
        tabWidth < width + Constants.minimumChatWidth
    }

    /// Follows live window resizes: a narrow tab trades the column for a list over the whole tab.
    private func applyLayoutMode(forTabWidth tabWidth: CGFloat) {
        self.tabWidth = tabWidth
        let isOverlay = Self.isOverlay(forTabWidth: tabWidth)
        if isOverlay != self.isOverlay {
            self.isOverlay = isOverlay
            separator.isHidden = isOverlay
            // Deactivate before activating so the two widths never conflict.
            (isOverlay ? columnWidthConstraint : overlayWidthConstraint)?.isActive = false
            (isOverlay ? overlayWidthConstraint : columnWidthConstraint)?.isActive = true
        }
        // The closed overlay waits a full tab width off screen, which moves with the window.
        applyOpenState(isOpen)
    }

    @objc private func showChatsTapped() {
        onToggle?()
    }

    @objc private func newChatTapped() {
        onNewChat?()
    }

    fileprivate static func animate(_ changes: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
        UIView.animate(withDuration: Constants.animationDuration,
                       delay: 0,
                       usingSpringWithDamping: 1,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: changes,
                       completion: completion)
    }

    fileprivate func floatingButtonConstraints(in tabView: UIView, below top: NSLayoutYAxisAnchor) -> [NSLayoutConstraint] {
        [
            showChatsButton.leadingAnchor.constraint(equalTo: tabView.safeAreaLayoutGuide.leadingAnchor, constant: Constants.buttonInset),
            showChatsButton.topAnchor.constraint(equalTo: top, constant: Constants.buttonInset),
            showChatsButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            showChatsButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            newChatButton.leadingAnchor.constraint(equalTo: tabView.safeAreaLayoutGuide.leadingAnchor, constant: Constants.buttonInset),
            newChatButton.centerYAnchor.constraint(equalTo: tabView.safeAreaLayoutGuide.bottomAnchor,
                                                   constant: -IPadChatListNavigationController.inputPillCenterHeight),
            newChatButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            newChatButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
        ]
    }

    private static func makeFloatingButton(image: UIImage, accessibilityLabel: String) -> UIButton {
        let button: UIButton
        if #available(iOS 26, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = image
            configuration.cornerStyle = .capsule
            button = UIButton(configuration: configuration)
        } else {
            button = UIButton(type: .system)
            button.setImage(image, for: .normal)
            button.backgroundColor = UIColor(designSystemColor: .surface)
            button.layer.cornerRadius = Constants.buttonSize / 2
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.12
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        button.accessibilityLabel = accessibilityLabel
        return button
    }
}

/// Lifts the list's toolbar so its buttons line up with the collapsed chat input's pill beside it.
private final class IPadChatListNavigationController: UINavigationController {

    /// The collapsed pill's center, measured up from the bottom safe area where the input sits.
    static let inputPillCenterHeight = UnifiedToggleInputView.aiTabCollapsedFooterHeight / 2

    private var calibratedLayout: (size: CGSize, safeAreaBottom: CGFloat)?
    private var isCalibrationScheduled = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safeAreaBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
        guard calibratedLayout.map({ $0.size != view.bounds.size || $0.safeAreaBottom != safeAreaBottom }) ?? true,
              !isCalibrationScheduled else { return }
        // The toolbar places its items a pass after the inset changes, so measuring here would chase its own tail.
        isCalibrationScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.alignToolbarWithInputPill()
        }
    }

    private func alignToolbarWithInputPill() {
        isCalibrationScheduled = false
        // The glass toolbar spans the whole view and doesn't center its items, so measure the New Chat button.
        guard view.window != nil, !isToolbarHidden,
              let item = topViewController?.toolbarItems?.lazy.compactMap(\.customView).first else { return }
        additionalSafeAreaInsets.bottom = 0
        view.layoutIfNeeded()
        toolbar.layoutIfNeeded()
        guard item.window != nil, item.bounds.height > 0 else { return }
        let itemCenterHeight = view.bounds.maxY - item.convert(item.bounds, to: view).midY
        let safeAreaBottom = view.safeAreaInsets.bottom
        additionalSafeAreaInsets.bottom = max(0, safeAreaBottom + Self.inputPillCenterHeight - itemCenterHeight)
        calibratedLayout = (view.bounds.size, safeAreaBottom)
    }
}

/// Spans the tab invisibly and reports its width, so the list can switch layouts as the window resizes.
final class WidthProbeView: UIView {

    var onWidthChange: ((CGFloat) -> Void)?
    private var lastWidth: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.width != lastWidth else { return }
        lastWidth = bounds.width
        onWidthChange?(bounds.width)
    }
}

extension TabViewController {

    func installChatListSidebar(_ listViewController: UIViewController,
                                isOpen: Bool,
                                onToggle: @escaping () -> Void,
                                onNewChat: @escaping () -> Void,
                                onTabWidthChange: @escaping () -> Void) {
        if let chatListSidebarContainer, listViewController.parent === self {
            chatListSidebarContainer.onToggle = onToggle
            chatListSidebarContainer.onNewChat = onNewChat
            chatListSidebarContainer.onTabWidthChange = onTabWidthChange
            bringChatListSidebarControlsToFront()
            if chatListSidebarContainer.isOpen != isOpen {
                setChatListSidebarOpen(isOpen, animated: false)
            }
            return
        }
        (listViewController.parent as? TabViewController)?.removeChatListSidebar()
        removeChatListSidebar()

        let container = IPadChatListSidebarContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.onToggle = onToggle
        container.onNewChat = onNewChat
        container.onTabWidthChange = onTabWidthChange
        view.insertSubview(container.widthProbe, at: 0)
        view.addSubview(container)
        view.addSubview(container.showChatsButton)
        view.addSubview(container.newChatButton)

        addChild(listViewController)
        let listView: UIView = listViewController.view
        listView.translatesAutoresizingMaskIntoConstraints = false
        container.insertSubview(listView, at: 0)

        let leading = container.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let columnWidth = container.widthAnchor.constraint(equalToConstant: IPadChatListSidebarContainerView.width)
        container.leadingConstraint = leading
        container.columnWidthConstraint = columnWidth
        container.overlayWidthConstraint = container.widthAnchor.constraint(equalTo: view.widthAnchor)
        NSLayoutConstraint.activate([
            leading,
            columnWidth,
            container.topAnchor.constraint(equalTo: containerStackView.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            listView.topAnchor.constraint(equalTo: container.topAnchor),
            listView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            listView.widthAnchor.constraint(equalTo: container.widthAnchor),
            container.widthProbe.topAnchor.constraint(equalTo: view.topAnchor),
            container.widthProbe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.widthProbe.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.widthProbe.heightAnchor.constraint(equalToConstant: 1),
        ] + container.floatingButtonConstraints(in: view, below: containerStackView.topAnchor))
        listViewController.didMove(toParent: self)
        chatListSidebarContainer = container
        container.applyOpenState(isOpen)
        container.isHidden = !isOpen

        // A tab set up off screen lays out once it joins a window; forcing it here makes the list's table warn.
        guard view.window != nil else { return }
        UIView.performWithoutAnimation { view.layoutIfNeeded() }
    }

    func removeChatListSidebar() {
        guard let container = chatListSidebarContainer else { return }
        children.filter { $0.view.isDescendant(of: container) }.forEach { child in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        container.showChatsButton.removeFromSuperview()
        container.newChatButton.removeFromSuperview()
        container.widthProbe.removeFromSuperview()
        container.removeFromSuperview()
        chatListSidebarContainer = nil
    }

    func setChatListSidebarOpen(_ isOpen: Bool, animated: Bool) {
        guard let container = chatListSidebarContainer else { return }
        guard animated else {
            container.applyOpenState(isOpen)
            container.isHidden = !isOpen
            if view.window != nil { view.layoutIfNeeded() }
            return
        }
        // Start from the closed pose for the current layout, which a resize while closed may have changed.
        if !container.isOpen {
            container.applyOpenState(false)
        }
        view.layoutIfNeeded()
        container.isHidden = false
        IPadChatListSidebarContainerView.animate({ [weak self] in
            container.applyOpenState(isOpen)
            self?.view.layoutIfNeeded()
        }, completion: { _ in
            // Bar buttons reach past the column's edge, so a closed list must not take touches.
            container.isHidden = !container.isOpen
        })
    }

    /// The input and other tab overlays are added later, so keep the buttons above them.
    func bringChatListSidebarControlsToFront() {
        guard let container = chatListSidebarContainer else { return }
        view.bringSubviewToFront(container)
        view.bringSubviewToFront(container.showChatsButton)
        view.bringSubviewToFront(container.newChatButton)
    }
}
