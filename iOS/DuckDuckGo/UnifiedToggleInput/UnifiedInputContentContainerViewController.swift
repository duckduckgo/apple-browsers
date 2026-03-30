//
//  UnifiedInputContentContainerViewController.swift
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
import DesignResourcesKit
import Combine
import PrivacyConfig
import Bookmarks
import Persistence
import History
import Core
import Suggestions
import AIChat
import RemoteMessaging

protocol UnifiedInputContentContainerViewControllerDelegate: AnyObject {
    func unifiedInputEditingStateDidSubmitQuery(_ query: String)
    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?)
    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity)
    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity)
    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion)
    func unifiedInputEditingStateDidSelectChatHistory(url: URL)
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab)
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode)
}

final class UnifiedInputContentContainerViewController: UIViewController {

    enum HeaderDisplayMode: Equatable {
        case hidden
        case active
        case inactive
    }

    // MARK: - Properties

    var suggestionTrayDependencies: SuggestionTrayDependencies?
    weak var delegate: UnifiedInputContentContainerViewControllerDelegate?
    var onDismissRequested: (() -> Void)?
    var onSwipeDownRequested: (() -> Void)?

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    private lazy var contentContainerView = UIView()
    private lazy var inlineHeaderView: UnifiedInputTopHeaderView = {
        let view = UnifiedInputTopHeaderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.onDismissTapped = { [weak self] in
            self?.onDismissRequested?()
        }
        return view
    }()

    private var isLandscapeOrientation: Bool = false {
        didSet {
            isUsingTopBarPosition = !forceBottomBarLayout && (appSettings.currentAddressBarPosition == .top || isLandscapeOrientation)
        }
    }
    var forceBottomBarLayout: Bool = false {
        didSet {
            isUsingTopBarPosition = !forceBottomBarLayout && (appSettings.currentAddressBarPosition == .top || isLandscapeOrientation)
        }
    }
    private var isUsingTopBarPosition: Bool
    private var isAdjustedForTopBar: Bool
    private(set) var currentSectionTitle: String?
    private var headerDisplayMode: HeaderDisplayMode = .hidden

    private weak var contentContainerViewLeadingConstraint: NSLayoutConstraint?
    private weak var contentContainerViewTrailingConstraint: NSLayoutConstraint?
    private weak var contentContainerViewTopConstraint: NSLayoutConstraint?

    let appSettings: AppSettings
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let aiChatSettings: AIChatSettingsProvider

    // MARK: - Manager Components

    private var swipeContainerManager: SwipeContainerManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private var aiChatHistoryManager: AIChatHistoryManager?
    private let daxLogoManager: DaxLogoManager
    private var notificationCancellable: AnyCancellable?

    private weak var contentAnimator: UIViewPropertyAnimator?

    // MARK: - Initialization

    init(switchBarHandler: SwitchBarHandling,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings()) {
        self.switchBarHandler = switchBarHandler
        self.daxLogoManager = DaxLogoManager()
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.aiChatSettings = aiChatSettings
        self.isUsingTopBarPosition = appSettings.currentAddressBarPosition == .top
        self.isAdjustedForTopBar = self.isUsingTopBarPosition

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        installComponents()
        setupSubscriptions()
        observeRemoteMessagesChanges()

        suggestionTrayManager?.showInitialSuggestions()
        updateDaxVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if aiChatHistoryManager == nil && featureFlagger.isFeatureOn(.aiChatSuggestions) && aiChatSettings.isChatSuggestionsEnabled {
            installChatHistoryList()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        aiChatHistoryManager?.tearDown()
        aiChatHistoryManager = nil
    }

    // MARK: - Public Methods

    @objc func dismissAnimated(_ completion: (() -> Void)? = nil) {
        if self.presentingViewController != nil {
            self.dismiss(animated: true, completion: completion)
        }
    }

    func setLogoYOffset(_ offset: CGFloat) {
        daxLogoManager.containerYCenterConstraint?.constant = offset
    }

    func setLogoHidden(_ hidden: Bool) {
        daxLogoManager.setForcedHidden(hidden)
    }

    var isSwipeEnabled: Bool = true {
        didSet { swipeContainerManager?.isSwipeEnabled = isSwipeEnabled }
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        if !animated {
            swipeContainerManager?.animateProgrammaticModeChanges = false
        }
        if switchBarHandler.currentToggleState != mode {
            switchBarHandler.setToggleState(mode)
        }
        swipeContainerManager?.syncVisibleMode(animated: animated)
        swipeContainerManager?.animateProgrammaticModeChanges = true
        updateSectionTitle()
    }

    func setHeaderDisplayMode(_ mode: HeaderDisplayMode) {
        guard headerDisplayMode != mode else { return }
        headerDisplayMode = mode
        renderHeader()
    }

    func setText(_ text: String) {
        switchBarHandler.updateCurrentText(text)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        adjustLayoutForViewSize(view.bounds.size)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { _ in
            self.adjustLayoutForViewSize(size)
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Private Methods

    private func requiresHorizontallyCompactLayout(for size: CGSize) -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }

        if let orientation = view.window?.windowScene?.interfaceOrientation {
            return orientation.isLandscape
        }

        if let sceneOrientation = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.interfaceOrientation })
            .first {
            return sceneOrientation.isLandscape
        }

        return false
    }

    private func adjustLayoutForViewSize(_ size: CGSize) {
        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: size)
        self.isLandscapeOrientation = isHorizontallyCompactLayoutEnabled

        let horizontalMargin: CGFloat = isHorizontallyCompactLayoutEnabled ? Metrics.horizontalMarginForCompactLayout : 0
        self.contentContainerViewLeadingConstraint?.constant = horizontalMargin
        self.contentContainerViewTrailingConstraint?.constant = -horizontalMargin
        self.updateDaxVisibility()
        self.updateLayoutForCurrentOrientation()
    }

    private func setupView() {
        view.backgroundColor = Metrics.backgroundColor
        setUpContentContainer()
        setUpInlineHeaderView()
        setUpSwipeDownGesture()
    }

    private func setUpContentContainer() {
        view.addSubview(contentContainerView)
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false

        contentContainerViewLeadingConstraint = contentContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        contentContainerViewLeadingConstraint?.isActive = true
        contentContainerViewTrailingConstraint = contentContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        contentContainerViewTrailingConstraint?.isActive = true
        contentContainerViewTopConstraint = contentContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        contentContainerViewTopConstraint?.isActive = true

        NSLayoutConstraint.activate([
            contentContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setUpInlineHeaderView() {
        view.addSubview(inlineHeaderView)
        NSLayoutConstraint.activate([
            inlineHeaderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            inlineHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inlineHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inlineHeaderView.heightAnchor.constraint(equalToConstant: Metrics.inlineHeaderHeight)
        ])
    }

    private func setUpSwipeDownGesture() {
        let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDownGesture.direction = .down
        swipeDownGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(swipeDownGesture)
    }

    private func installComponents() {
        installSwipeContainer()
        installSuggestionsTray()
        installDaxLogoView()
    }

    private func updateSectionTitle() {
        let text = computedSectionTitleText()
        currentSectionTitle = text.isEmpty ? nil : text
        swipeContainerManager?.containerViewController.additionalSafeAreaInsets.top = Metrics.contentTopInset
        renderHeader()
    }

    private func computedSectionTitleText() -> String {
        let mode = switchBarHandler.currentToggleState
        let hasFavorites = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let hasAutocomplete = suggestionTrayManager?.shouldDisplaySuggestionTray == true && !hasFavorites
        let hasChatHistory = aiChatHistoryManager?.hasSuggestions == true
        switch mode {
        case .search:
            if hasFavorites { return UserText.sectionTitleFavorites }
            if hasAutocomplete { return UserText.sectionTitleSuggestions }
            return ""
        case .aiChat:
            if hasChatHistory {
                return switchBarHandler.currentText.isEmpty ? UserText.aiChatRecentChatsTitle : UserText.aiChatSuggestedChatsTitle
            }
            return ""
        }
    }

    private func installSwipeContainer() {
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler)
        let containerVC = manager.containerViewController
        addChild(containerVC)
        contentContainerView.addSubview(containerVC.view)
        containerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerVC.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            containerVC.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            containerVC.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            containerVC.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])
        containerVC.didMove(toParent: self)
        manager.delegate = self
        manager.fadeOutDelegate = self
        manager.isSwipeEnabled = isSwipeEnabled
        swipeContainerManager = manager
    }

    private func installSuggestionsTray() {
        guard let dependencies = suggestionTrayDependencies,
              let containerViewController = swipeContainerManager?.containerViewController,
              let searchContainer = swipeContainerManager?.searchPageContainer else { return }

        let manager = SuggestionTrayManager(switchBarHandler: switchBarHandler, dependencies: dependencies)
        manager.delegate = self
        manager.installInContainerView(searchContainer, parentViewController: containerViewController, escapeHatch: nil)
        suggestionTrayManager = manager
    }

    private func installChatHistoryList() {
        guard let swipeContainerManager else { return }

        let reader = SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfigurationManager)
        let historySettings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
        let suggestionsReader = AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)

        let manager = AIChatHistoryManager(suggestionsReader: suggestionsReader,
                                           aiChatSettings: aiChatSettings,
                                           viewModel: AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount))
        manager.delegate = self
        swipeContainerManager.installChatHistory(using: manager)
        manager.subscribeToTextChanges(switchBarHandler.currentTextPublisher)
        aiChatHistoryManager = manager
        manager.hasSuggestionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateSectionTitle()
                self.scheduleAnimation {
                    self.updateDaxVisibility()
                    self.view.layoutIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func installDaxLogoView() {
        daxLogoManager.installInViewController(self, asSubviewOf: contentContainerView, anchorView: contentContainerView, isTopBarPosition: false)
    }

    private func setupSubscriptions() {
        setupSwitchBarSubscriptions()
    }

    private func setupSwitchBarSubscriptions() {
        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in
                guard let self else { return }

                scheduleAnimation {
                    self.updateDaxVisibility()
                    self.view.layoutIfNeeded()
                }

                self.suggestionTrayManager?.handleQueryUpdate(currentText, animated: true)
                self.updateSectionTitle()
            }
            .store(in: &cancellables)

    }

    private func updateLayoutForCurrentOrientation() {
        guard isUsingTopBarPosition != isAdjustedForTopBar else { return }
        isAdjustedForTopBar = isUsingTopBarPosition
        updateSectionTitle()
    }

    private func renderHeader() {
        if isUsingTopBarPosition {
            if let currentSectionTitle, !currentSectionTitle.isEmpty {
                inlineHeaderView.isHidden = false
                inlineHeaderView.setTitleLayoutPosition(.topBarSection)
                inlineHeaderView.configure(title: currentSectionTitle)
                inlineHeaderView.setDismissButtonHidden(true)
                contentContainerViewTopConstraint?.constant = Metrics.topBarSectionHeaderHeight
            } else {
                inlineHeaderView.isHidden = true
                contentContainerViewTopConstraint?.constant = 0
            }
            return
        }

        switch headerDisplayMode {
        case .hidden:
            inlineHeaderView.isHidden = true
            inlineHeaderView.setTitleLayoutPosition(.bottomBarHeader)
            inlineHeaderView.setDismissButtonHidden(false)
            contentContainerViewTopConstraint?.constant = 0
        case .active:
            inlineHeaderView.isHidden = false
            inlineHeaderView.setTitleLayoutPosition(.bottomBarHeader)
            inlineHeaderView.configure(title: currentSectionTitle)
            inlineHeaderView.setDismissButtonHidden(false)
            contentContainerViewTopConstraint?.constant = Metrics.inlineHeaderHeight
        case .inactive:
            inlineHeaderView.isHidden = false
            inlineHeaderView.setTitleLayoutPosition(.bottomBarHeader)
            inlineHeaderView.configure(title: currentSectionTitle)
            inlineHeaderView.setDismissButtonHidden(true)
            contentContainerViewTopConstraint?.constant = Metrics.inlineHeaderHeight
        }
    }

    private func observeRemoteMessagesChanges() {
        notificationCancellable = NotificationCenter.default.publisher(for: RemoteMessagingStore.Notifications.remoteMessagesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.suggestionTrayManager?.showInitialSuggestions()
                self.updateDaxVisibility()
            }
    }

    private func scheduleAnimation(_ animation: @escaping () -> Void, completion: ((UIViewAnimatingPosition) -> Void)? = nil) {
        if contentAnimator?.state == .stopped {
            contentAnimator = nil
        }

        let animator = self.contentAnimator ?? UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.73)
        contentAnimator = animator

        animator.addAnimations(animation)
        if let completion {
            animator.addCompletion(completion)
        }

        animator.startAnimation()
    }

    // MARK: - Action Handlers

    private func handleMicrophoneButtonTapped() {
        guard isViewLoaded, view.window != nil, !view.isHidden, !(view.superview?.isHidden ?? true) else { return }
        SpeechRecognizer.requestMicAccess { [weak self] permission in
            guard let self,
                  self.view.window != nil,
                  self.view.superview?.isHidden != true else { return }
            if permission {
                let preferredTarget: VoiceSearchTarget? = (self.switchBarHandler.currentToggleState == .aiChat) ? .AIChat : .SERP
                self.showVoiceSearch(preferredTarget: preferredTarget)
            } else {
                self.showNoMicrophonePermissionAlert()
            }
        }
    }

    @objc private func handleSwipeDown() {
        onSwipeDownRequested?()
    }

    private func showVoiceSearch(preferredTarget: VoiceSearchTarget? = nil) {
        let voiceSearchController = VoiceSearchViewController(preferredTarget: preferredTarget)
        voiceSearchController.delegate = self
        voiceSearchController.modalTransitionStyle = .crossDissolve
        voiceSearchController.modalPresentationStyle = .overFullScreen
        present(voiceSearchController, animated: true)
    }

    private func showNoMicrophonePermissionAlert() {
        let alertController = NoMicPermissionAlert.buildAlert()
        present(alertController, animated: true)
    }

    private func updateDaxVisibility() {
        let shouldDisplaySuggestionTray = suggestionTrayManager?.shouldDisplaySuggestionTray == true
        let shouldDisplayFavoritesOverlay = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: view.bounds.size)
        let isShowingChatHistory = aiChatHistoryManager?.hasSuggestions == true

        let isHomeDaxVisible = !shouldDisplaySuggestionTray && !shouldDisplayFavoritesOverlay && !isHorizontallyCompactLayoutEnabled
        let isAIDaxVisible: Bool
        if switchBarHandler.isUsingFadeOutAnimation {
            isAIDaxVisible = !isHorizontallyCompactLayoutEnabled && !isShowingChatHistory
        } else {
            isAIDaxVisible = !shouldDisplaySuggestionTray && !isHorizontallyCompactLayoutEnabled && !isShowingChatHistory
        }

        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
        updateSectionTitle()
    }

    private enum Metrics {
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .panel)
        static let inlineHeaderHeight: CGFloat = 60
        static let topBarSectionHeaderHeight: CGFloat = 68
        static let contentTopInset: CGFloat = 10
    }
}

// MARK: - SwipeContainerViewControllerDelegate

extension UnifiedInputContentContainerViewController: SwipeContainerViewControllerDelegate {

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didSwipeToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
        delegate?.unifiedInputEditingStateDidChangeMode(mode)
        scheduleAnimation {
            self.updateDaxVisibility()
        }
    }

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didUpdateScrollProgress progress: CGFloat) {
        daxLogoManager.updateSwipeProgress(progress)
    }
}

// MARK: - FadeOutContainerViewControllerDelegate

extension UnifiedInputContentContainerViewController: FadeOutContainerViewControllerDelegate {

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didTransitionToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
        delegate?.unifiedInputEditingStateDidChangeMode(mode)
    }

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didUpdateTransitionProgress progress: CGFloat) {
        daxLogoManager.updateSwipeProgress(progress)
    }

    func fadeOutContainerViewControllerIsShowingSuggestions(_ controller: FadeOutContainerViewController) -> Bool {
        return suggestionTrayManager?.shouldDisplaySuggestionTray ?? false
    }
}

// MARK: - SuggestionTrayManagerDelegate

extension UnifiedInputContentContainerViewController: SuggestionTrayManagerDelegate {

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectSuggestion suggestion: Suggestion) {
        delegate?.unifiedInputEditingStateDidSelectSuggestion(suggestion)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectFavorite favorite: BookmarkEntity) {
        delegate?.unifiedInputEditingStateDidSelectFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, shouldUpdateTextTo text: String) {
        switchBarHandler.updateCurrentText(text)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsEditFavorite favorite: BookmarkEntity) {
        delegate?.unifiedInputEditingStateDidEditFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsSwitchToTab tab: Tab) {
        delegate?.unifiedInputEditingStateDidRequestSwitchTab(tab)
    }
}

// MARK: - VoiceSearchViewControllerDelegate

extension UnifiedInputContentContainerViewController: VoiceSearchViewControllerDelegate {

    func voiceSearchViewController(_ controller: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self, let query else { return }
            let mode: TextEntryMode = (target == .AIChat) ? .aiChat : .search
            self.switchBarHandler.setToggleState(mode)
            self.switchBarHandler.submitText(query)
        }
    }
}

// MARK: - AIChatHistoryManagerDelegate

extension UnifiedInputContentContainerViewController: AIChatHistoryManagerDelegate {

    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChatURL url: URL) {
        delegate?.unifiedInputEditingStateDidSelectChatHistory(url: url)
    }
}
