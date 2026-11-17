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

    func installIPadChatListSidebar(in tab: TabViewController) {
        guard isIPadChatListSidebarAvailable else { return }
        let sidebar = iPadChatListSidebar(isFireMode: tab.tabModel.fireTab)
        tab.installChatListSidebar(sidebar.navigationController,
                                   isOpen: iPadChatListSidebarState.isOpen,
                                   onToggle: { [weak self] in self?.toggleIPadChatListSidebar() },
                                   onFire: { [weak sidebar] source in sidebar?.historyViewController.presentDeleteAllChatsConfirmation(from: source) })
        tab.setChatListFireButtonAvailable(sidebar.hasChats)
        sidebar.followCurrentChat(of: tab)
    }

    func detachIPadChatListSidebar() {
        guard let sidebar = iPadChatListSidebarState.sidebar else { return }
        (sidebar.navigationController.parent as? TabViewController)?.removeChatListSidebar()
        sidebar.stopFollowingCurrentChat()
    }

    func toggleIPadChatListSidebar() {
        setIPadChatListSidebarOpen(!iPadChatListSidebarState.isOpen)
    }

    func setIPadChatListSidebarOpen(_ isOpen: Bool) {
        iPadChatListSidebarState.isOpen = isOpen
        guard let tab = iPadChatListSidebarState.sidebar?.navigationController.parent as? TabViewController else { return }
        // A list over the whole tab hides the input, so it takes the keyboard down too.
        if !isOpen || tab.chatListSidebarContainer?.isOverlay == true {
            tab.view.endEditing(true)
        }
        tab.setChatListSidebarOpen(isOpen, animated: true)
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
        beginNewChatFromHistory(in: tab)
        unifiedToggleInputCoordinator?.showExpanded(inputMode: .aiChat)
    }

    /// Deleting the open chat from the list leaves the tab on a fresh chat rather than on a chat that's gone.
    fileprivate func leaveDeletedChatFromIPadChatListSidebar() {
        guard let tab = currentTab, tab.isAITab else { return }
        unifiedToggleInputCoordinator?.startNewChat()
        tab.submitStartChatAction()
    }

    fileprivate func iPadChatListSidebarHasChatsDidChange(_ hasChats: Bool) {
        (iPadChatListSidebarState.sidebar?.navigationController.parent as? TabViewController)?
            .setChatListFireButtonAvailable(hasChats)
    }

    /// Duck.ai opens the chat in place; the URL load is the fallback when the page can't.
    fileprivate func openChatFromIPadChatListSidebar(chatId: String) {
        guard let tab = currentTab, tab.url?.duckAIChatID != chatId else { return }
        duckAIInputFocus.forget()
        iPadChatListSidebarState.pendingChatOpen?.cancel()
        let url = aiChatSettings.aiChatURL.withChatID(chatId)
        guard tab.isAITab else {
            onChatHistorySelected(url: url)
            return
        }
        recordChatHistorySelection()
        iPadChatListSidebarState.pendingChatOpen = Task { @MainActor [weak self, weak tab] in
            let outcome = await tab?.openChatInPage(chatId: chatId)
            guard !Task.isCancelled, let self, let tab, tab === self.currentTab else { return }
            guard outcome == .opened else {
                self.loadChatFromHistory(url)
                return
            }
            // No page load follows to take the stamp.
            tab.tabModel.duckAIEntrySource = .chatHistoryOpenChat
            tab.tabModel.discardDuckAIEntrySourceAwaitingPageLoad()
        }
    }
}

/// Where the list lives between Duck.ai tabs, and whether it was last left open.
final class IPadChatListSidebarState {
    fileprivate(set) var sidebar: IPadChatListSidebar?
    fileprivate(set) var isOpen = false
    fileprivate var pendingChatOpen: Task<Void, Never>?
}

/// Owns the list and answers its requests on behalf of `MainViewController`.
@MainActor
final class IPadChatListSidebar {

    let navigationController: UINavigationController
    let historyViewController: AIChatHistoryViewController
    let isFireMode: Bool
    /// Fire has nothing to delete without chats, so the closed sidebar's fire button hides.
    private(set) var hasChats = false

    private let viewModel: AIChatHistoryViewModel
    private weak var host: MainViewController?
    private var currentChatCancellable: AnyCancellable?
    private var listedChatsCancellable: AnyCancellable?
    private var listedChatIds: Set<String> = []

    fileprivate init(viewModel: AIChatHistoryViewModel, fireButtonAnimator: FireButtonAnimator, isFireMode: Bool, host: MainViewController) {
        self.viewModel = viewModel
        self.isFireMode = isFireMode
        self.host = host
        historyViewController = AIChatHistoryViewController(viewModel: viewModel,
                                                            fireButtonAnimator: fireButtonAnimator,
                                                            presentation: .sidebar)
        navigationController = UINavigationController(rootViewController: historyViewController)
        viewModel.delegate = self
        historyViewController.sidebarDelegate = self
        // Debounced so a pin toggle, which updates both sections one after the other, reads as one change.
        listedChatsCancellable = Publishers.CombineLatest(viewModel.$pinned, viewModel.$recent)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] pinned, recent in
                self?.listedChatsDidChange(Set((pinned + recent).map(\.chatId)))
            }
    }

    private func listedChatsDidChange(_ chatIds: Set<String>) {
        defer { listedChatIds = chatIds }
        let hasChats = viewModel.totalChatCount > 0
        if hasChats != self.hasChats {
            self.hasChats = hasChats
            host?.iPadChatListSidebarHasChatsDidChange(hasChats)
        }
        // A search narrows the list without deleting anything.
        guard viewModel.query.isEmpty,
              let currentChatId = historyViewController.currentChatId,
              listedChatIds.contains(currentChatId),
              !chatIds.contains(currentChatId) else { return }
        host?.leaveDeletedChatFromIPadChatListSidebar()
    }

    /// The page reports the open chat in its URL, including chats started from the input.
    fileprivate func followCurrentChat(of tab: TabViewController) {
        currentChatCancellable = tab.webView?.publisher(for: \.url)
            .map { $0?.duckAIChatID }
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
        host?.setIPadChatListSidebarOpen(false)
    }

    func chatHistorySidebarDidRequestFeedback() {
        host?.segueToFeedback()
    }

    func chatHistorySidebarDidRequestSyncSettings() {
        host?.segueToSettingsSync()
    }

    func chatHistorySidebarDidRequestDuckAISettings() {
        host?.currentTab?.submitOpenSettingsAction()
    }
}

// MARK: - Tab hosting

/// The list beside the chat, plus the two buttons that stand in for it while it's closed. In a narrow window the
/// chat can't spare the column's width, so the list covers the whole tab instead, like the iPhone Chats screen.
final class IPadChatListSidebarContainerView: UIView {

    static let width: CGFloat = 320

    private enum Constants {
        static let buttonSize: CGFloat = 44
        static let buttonInset: CGFloat = 16
        static let animationDuration: TimeInterval = 0.35
        /// Below this the chat beside the column gets too narrow to read.
        static let minimumChatWidth: CGFloat = 450
    }

    fileprivate let showChatsButton = IPadChatListSidebarContainerView.makeFloatingButton(
        image: DesignSystemImages.Glyphs.Size24.chats.withRenderingMode(.alwaysTemplate),
        accessibilityLabel: UserText.aiChatHistorySidebarShowAccessibilityLabel)
    fileprivate let fireButton = IPadChatListSidebarContainerView.makeFloatingButton(
        image: DesignSystemImages.Glyphs.Size24.fireSolid,
        accessibilityLabel: UserText.aiChatHistoryFireAllAccessibilityLabel)
    fileprivate let widthProbe = WidthProbeView()

    fileprivate var leadingConstraint: NSLayoutConstraint?
    fileprivate var columnWidthConstraint: NSLayoutConstraint?
    fileprivate var overlayWidthConstraint: NSLayoutConstraint?
    fileprivate var contentLeadingConstraint: NSLayoutConstraint?
    fileprivate weak var standaloneContentLeadingConstraint: NSLayoutConstraint?
    fileprivate var onToggle: (() -> Void)?
    fileprivate var onFire: ((AnyObject) -> Void)?
    fileprivate(set) var isOpen = false
    fileprivate(set) var isOverlay = false
    /// An image of the chat held over the page while the column slides; see `coverPageForSlide`.
    fileprivate weak var pageCover: UIView?
    fileprivate var isFireAvailable = true

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
        fireButton.addTarget(self, action: #selector(fireTapped(_:)), for: .touchUpInside)
        widthProbe.onWidthChange = { [weak self] width in
            self?.applyLayoutMode(forTabWidth: width)
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
        fireButton.alpha = isOpen ? 0 : 1
        accessibilityElementsHidden = !isOpen
        showChatsButton.isAccessibilityElement = !isOpen
        updateFireButtonVisibility()
    }

    fileprivate func setFireAvailable(_ isAvailable: Bool) {
        isFireAvailable = isAvailable
        updateFireButtonVisibility()
    }

    /// A narrow window's input spans the tab under the button, and its toolbar already carries fire.
    private func updateFireButtonVisibility() {
        let isShown = isFireAvailable && !isOverlay
        fireButton.isHidden = !isShown
        fireButton.isAccessibilityElement = !isOpen && isShown
    }

    /// Follows live window resizes: a narrow tab trades the column for a list over the whole tab.
    private func applyLayoutMode(forTabWidth tabWidth: CGFloat) {
        let isOverlay = tabWidth < Self.width + Constants.minimumChatWidth
        if isOverlay != self.isOverlay {
            self.isOverlay = isOverlay
            separator.isHidden = isOverlay
            // Deactivate before activating so the two widths never conflict.
            (isOverlay ? columnWidthConstraint : overlayWidthConstraint)?.isActive = false
            (isOverlay ? overlayWidthConstraint : columnWidthConstraint)?.isActive = true
            // A column pushes the chat over; an overlay leaves it where it is, underneath.
            (isOverlay ? contentLeadingConstraint : standaloneContentLeadingConstraint)?.isActive = false
            (isOverlay ? standaloneContentLeadingConstraint : contentLeadingConstraint)?.isActive = true
        }
        // The closed overlay waits a full tab width off screen, which moves with the window.
        applyOpenState(isOpen)
    }

    @objc private func showChatsTapped() {
        onToggle?()
    }

    @objc private func fireTapped(_ sender: UIButton) {
        onFire?(sender)
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
            fireButton.leadingAnchor.constraint(equalTo: tabView.safeAreaLayoutGuide.leadingAnchor, constant: Constants.buttonInset),
            fireButton.bottomAnchor.constraint(equalTo: tabView.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.buttonInset),
            fireButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            fireButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
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
                                onFire: @escaping (AnyObject) -> Void) {
        if let chatListSidebarContainer, listViewController.parent === self {
            chatListSidebarContainer.onToggle = onToggle
            chatListSidebarContainer.onFire = onFire
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
        container.onFire = onFire
        view.insertSubview(container.widthProbe, at: 0)
        view.addSubview(container)
        view.addSubview(container.showChatsButton)
        view.addSubview(container.fireButton)

        addChild(listViewController)
        let listView: UIView = listViewController.view
        listView.translatesAutoresizingMaskIntoConstraints = false
        container.insertSubview(listView, at: 0)

        let leading = container.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let contentLeading = containerStackView.leadingAnchor.constraint(equalTo: container.trailingAnchor)
        let columnWidth = container.widthAnchor.constraint(equalToConstant: IPadChatListSidebarContainerView.width)
        container.leadingConstraint = leading
        container.contentLeadingConstraint = contentLeading
        container.columnWidthConstraint = columnWidth
        container.overlayWidthConstraint = container.widthAnchor.constraint(equalTo: view.widthAnchor)
        container.standaloneContentLeadingConstraint = containerStackViewLeadingConstraint
        containerStackViewLeadingConstraint?.isActive = false
        NSLayoutConstraint.activate([
            leading,
            contentLeading,
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
        container.fireButton.removeFromSuperview()
        container.widthProbe.removeFromSuperview()
        container.contentLeadingConstraint?.isActive = false
        container.removeFromSuperview()
        chatListSidebarContainer = nil
        containerStackViewLeadingConstraint?.isActive = true
    }

    func setChatListSidebarOpen(_ isOpen: Bool, animated: Bool) {
        guard let container = chatListSidebarContainer else { return }
        guard animated else {
            container.applyOpenState(isOpen)
            container.isHidden = !isOpen
            view.layoutIfNeeded()
            return
        }
        // Start from the closed pose for the current layout, which a resize while closed may have changed.
        if !container.isOpen {
            container.applyOpenState(false)
        }
        view.layoutIfNeeded()
        container.isHidden = false
        // An overlay leaves the page where it is; a column resizes it.
        let cover = container.isOverlay ? nil : coverPageForSlide(in: container)
        IPadChatListSidebarContainerView.animate({ [weak self] in
            container.applyOpenState(isOpen)
            self?.view.layoutIfNeeded()
        }, completion: { _ in
            // Bar buttons reach past the column's edge, so a closed list must not take touches.
            container.isHidden = !container.isOpen
            cover.map(Self.revealPage(under:))
        })
    }

    /// WebKit lays the page out for its final width as soon as the frame starts to change, so the chat jumps ahead
    /// of the column and leaves a bare strip behind. An image of the chat stands in while it slides: the Duck.ai
    /// transcript is centered, so the image kept centered sits where the reflowed page will end up.
    private func coverPageForSlide(in container: IPadChatListSidebarContainerView) -> UIView? {
        container.pageCover?.removeFromSuperview()
        guard webViewContainer.window != nil,
              let snapshot = webViewContainer.snapshotView(afterScreenUpdates: false) else { return nil }
        let cover = UIView(frame: webViewContainer.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = UIColor(singleUseColor: .duckAIWebViewBackground)
        cover.isUserInteractionEnabled = false
        cover.clipsToBounds = true
        snapshot.frame = cover.bounds
        snapshot.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        cover.addSubview(snapshot)
        webViewContainer.addSubview(cover)
        container.pageCover = cover
        return cover
    }

    /// Waits a frame for WebKit to draw at the new width, then lets the real page show through.
    private static func revealPage(under cover: UIView) {
        UIView.animate(withDuration: 0.15, delay: 0.05, options: [.curveEaseOut, .allowUserInteraction], animations: {
            cover.alpha = 0
        }, completion: { _ in
            cover.removeFromSuperview()
        })
    }

    func setChatListFireButtonAvailable(_ isAvailable: Bool) {
        chatListSidebarContainer?.setFireAvailable(isAvailable)
    }

    /// The input and other tab overlays are added later, so keep the buttons above them.
    func bringChatListSidebarControlsToFront() {
        guard let container = chatListSidebarContainer else { return }
        view.bringSubviewToFront(container)
        view.bringSubviewToFront(container.showChatsButton)
        view.bringSubviewToFront(container.fireButton)
    }
}
