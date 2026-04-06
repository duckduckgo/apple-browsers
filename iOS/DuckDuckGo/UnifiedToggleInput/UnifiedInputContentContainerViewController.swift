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
import os.log

private let utiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo", category: "UTI")

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

    // MARK: - Properties

    var suggestionTrayDependencies: SuggestionTrayDependencies?
    weak var delegate: UnifiedInputContentContainerViewControllerDelegate?
    var onDismissRequested: (() -> Void)?
    var onSwipeDownRequested: (() -> Void)?

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    private lazy var contentContainerView = UIView()
    private lazy var floatingDismissButton: UIButton = {
        let button: UIButton
        if #available(iOS 26, *) {
            var config = UIButton.Configuration.glass()
            config.image = UIImage(systemName: "xmark")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button = UIButton(configuration: config)
        } else {
            button = UIButton(type: .system)
            let image = UIImage(systemName: "xmark")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            button.setImage(image, for: .normal)
            button.tintColor = UIColor(designSystemColor: .textPrimary)
            button.backgroundColor = UIColor(designSystemColor: .surface)
            button.layer.cornerRadius = 22
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.1
            button.layer.shadowRadius = 4
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleFloatingDismissTap), for: .primaryActionTriggered)
        return button
    }()

    private var isLandscapeOrientation: Bool = false {
        didSet {
            utiLog.debug("ContentContainer.isLandscapeOrientation.didSet - old: \(oldValue, privacy: .public), new: \(self.isLandscapeOrientation, privacy: .public)")
            isUsingTopBarPosition = !forceBottomBarLayout && (appSettings.currentAddressBarPosition == .top || isLandscapeOrientation)
        }
    }
    var forceBottomBarLayout: Bool = false {
        didSet {
            utiLog.debug("ContentContainer.forceBottomBarLayout.didSet - old: \(oldValue, privacy: .public), new: \(self.forceBottomBarLayout, privacy: .public)")
            isUsingTopBarPosition = !forceBottomBarLayout && (appSettings.currentAddressBarPosition == .top || isLandscapeOrientation)
        }
    }
    private var isUsingTopBarPosition: Bool
    private var isAdjustedForTopBar: Bool
    private(set) var currentSectionTitle: String?

    private weak var contentContainerViewLeadingConstraint: NSLayoutConstraint?
    private weak var contentContainerViewTrailingConstraint: NSLayoutConstraint?

    let appSettings: AppSettings
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let aiChatSettings: AIChatSettingsProvider

    // MARK: - Manager Components

    private var swipeContainerManager: SwipeContainerManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private var aiChatHistoryManager: AIChatHistoryManager?
    private var isShowingURLFallback = false

    private var chatHasSuggestions: Bool {
        let result = aiChatHistoryManager?.hasSuggestions ?? false
        utiLog.debug("ContentContainer.chatHasSuggestions - \(result, privacy: .public)")
        return result
    }

    private let daxLogoManager: DaxLogoManager
    private var notificationCancellable: AnyCancellable?

    private weak var contentAnimator: UIViewPropertyAnimator?

    // MARK: - Initialization

    init(switchBarHandler: SwitchBarHandling,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings()) {
        utiLog.debug("ContentContainer.init")
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
        utiLog.debug("ContentContainer.init(coder:)")
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        utiLog.debug("ContentContainer.viewDidLoad")
        super.viewDidLoad()

        setupView()
        installComponents()
        setupSubscriptions()
        observeRemoteMessagesChanges()

        suggestionTrayManager?.showInitialSuggestions()
        updateDaxVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        utiLog.debug("ContentContainer.viewWillAppear")
        super.viewWillAppear(animated)

        if aiChatHistoryManager == nil && featureFlagger.isFeatureOn(.aiChatSuggestions) && aiChatSettings.isChatSuggestionsEnabled {
            utiLog.debug("ContentContainer.viewWillAppear 🔀 chatHistoryManager=nil, installing chat history list")
            installChatHistoryList()
        } else {
            utiLog.debug("ContentContainer.viewWillAppear 🔀 skipping chat history install: managerExists=\(self.aiChatHistoryManager != nil, privacy: .public), featureOn=\(self.featureFlagger.isFeatureOn(.aiChatSuggestions), privacy: .public), suggestionsEnabled=\(self.aiChatSettings.isChatSuggestionsEnabled, privacy: .public)")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        utiLog.debug("ContentContainer.viewDidDisappear")
        super.viewDidDisappear(animated)
        utiLog.debug("ContentContainer.viewDidDisappear → tearing down aiChatHistoryManager (exists=\(self.aiChatHistoryManager != nil, privacy: .public))")
        aiChatHistoryManager?.tearDown()
        aiChatHistoryManager = nil
    }

    // MARK: - Public Methods

    @objc func dismissAnimated(_ completion: (() -> Void)? = nil) {
        utiLog.debug("ContentContainer.dismissAnimated")
        if self.presentingViewController != nil {
            utiLog.debug("ContentContainer.dismissAnimated 🔀 presentingViewController exists → dismissing")
            self.dismiss(animated: true, completion: completion)
        } else {
            utiLog.debug("ContentContainer.dismissAnimated 🔀 no presentingViewController, skipping dismiss")
        }
    }

    func setLogoYOffset(_ offset: CGFloat) {
        utiLog.debug("ContentContainer.setLogoYOffset - offset: \(offset, privacy: .public)")
        daxLogoManager.containerYCenterConstraint?.constant = offset
    }

    func setLogoHidden(_ hidden: Bool) {
        utiLog.debug("ContentContainer.setLogoHidden - hidden: \(hidden, privacy: .public)")
        daxLogoManager.setForcedHidden(hidden)
    }

    var isSwipeEnabled: Bool = true {
        didSet {
            utiLog.debug("ContentContainer.isSwipeEnabled.didSet - enabled: \(self.isSwipeEnabled, privacy: .public)")
            swipeContainerManager?.isSwipeEnabled = isSwipeEnabled
        }
    }

    func setInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        utiLog.debug("ContentContainer.setInputMode - mode: \(String(describing: mode), privacy: .public), animated: \(animated, privacy: .public), currentMode: \(String(describing: self.switchBarHandler.currentToggleState), privacy: .public)")
        utiLog.debug("ContentContainer.setInputMode → forwarding to applyURLFallbackForModeChange")
        applyURLFallbackForModeChange(mode)
        if !animated {
            utiLog.debug("ContentContainer.setInputMode 🔀 animated=false → disabling programmatic mode change animations")
            swipeContainerManager?.animateProgrammaticModeChanges = false
        }
        if switchBarHandler.currentToggleState != mode {
            utiLog.debug("ContentContainer.setInputMode 🔀 mode changed → forwarding to switchBarHandler.setToggleState(\(String(describing: mode), privacy: .public))")
            switchBarHandler.setToggleState(mode)
        } else {
            utiLog.debug("ContentContainer.setInputMode 🔀 mode already \(String(describing: mode), privacy: .public), skipping toggle")
        }
        updateSectionTitle()
        utiLog.debug("ContentContainer.setInputMode 📐 layoutIfNeeded")
        view.layoutIfNeeded()

        utiLog.debug("ContentContainer.setInputMode → syncVisibleMode(animated: \(animated, privacy: .public))")
        swipeContainerManager?.syncVisibleMode(animated: animated)
        swipeContainerManager?.animateProgrammaticModeChanges = true
    }

    func setDismissButtonVisible(_ visible: Bool) {
        utiLog.debug("ContentContainer.setDismissButtonVisible - visible: \(visible, privacy: .public)")
        utiLog.debug("ContentContainer.setDismissButtonVisible 📐 floatingDismissButton.isHidden=\(!visible, privacy: .public)")
        floatingDismissButton.isHidden = !visible
    }

    func setText(_ text: String) {
        utiLog.debug("ContentContainer.setText - text: \(text, privacy: .public)")
        utiLog.debug("ContentContainer.setText → forwarding to switchBarHandler.updateCurrentText")
        switchBarHandler.updateCurrentText(text)
    }

    override func viewWillLayoutSubviews() {
        utiLog.debug("ContentContainer.viewWillLayoutSubviews")
        super.viewWillLayoutSubviews()
        adjustLayoutForViewSize(view.bounds.size)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        utiLog.debug("ContentContainer.viewWillTransition - size: \(size.debugDescription, privacy: .public)")
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { _ in
            self.adjustLayoutForViewSize(size)
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Private Methods

    private func requiresHorizontallyCompactLayout(for size: CGSize) -> Bool {
        utiLog.debug("ContentContainer.requiresHorizontallyCompactLayout - size: \(size.debugDescription, privacy: .public)")
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            utiLog.debug("ContentContainer.requiresHorizontallyCompactLayout ↩️ guard: not phone idiom")
            return false
        }

        if let orientation = view.window?.windowScene?.interfaceOrientation {
            utiLog.debug("ContentContainer.requiresHorizontallyCompactLayout 🔀 windowScene orientation=\(String(describing: orientation), privacy: .public), isLandscape=\(orientation.isLandscape, privacy: .public)")
            return orientation.isLandscape
        }

        if let sceneOrientation = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.interfaceOrientation })
            .first {
            utiLog.debug("ContentContainer.requiresHorizontallyCompactLayout 🔀 fallback scene orientation=\(String(describing: sceneOrientation), privacy: .public), isLandscape=\(sceneOrientation.isLandscape, privacy: .public)")
            return sceneOrientation.isLandscape
        }

        utiLog.debug("ContentContainer.requiresHorizontallyCompactLayout 🔀 no orientation found, returning false")
        return false
    }

    private func adjustLayoutForViewSize(_ size: CGSize) {
        utiLog.debug("ContentContainer.adjustLayoutForViewSize - size: \(size.debugDescription, privacy: .public)")
        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: size)
        self.isLandscapeOrientation = isHorizontallyCompactLayoutEnabled

        let horizontalMargin: CGFloat = isHorizontallyCompactLayoutEnabled ? Metrics.horizontalMarginForCompactLayout : 0
        utiLog.debug("ContentContainer.adjustLayoutForViewSize 📐 horizontalMargin=\(horizontalMargin, privacy: .public), isCompact=\(isHorizontallyCompactLayoutEnabled, privacy: .public)")
        self.contentContainerViewLeadingConstraint?.constant = horizontalMargin
        self.contentContainerViewTrailingConstraint?.constant = -horizontalMargin
        self.updateDaxVisibility()
        self.updateLayoutForCurrentOrientation()
    }

    private func setupView() {
        utiLog.debug("ContentContainer.setupView")
        view.backgroundColor = Metrics.backgroundColor
        setUpContentContainer()
        setUpFloatingDismissButton()
        setUpSwipeDownGesture()
    }

    private func setUpContentContainer() {
        utiLog.debug("ContentContainer.setUpContentContainer")
        view.addSubview(contentContainerView)
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false

        contentContainerViewLeadingConstraint = contentContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        contentContainerViewLeadingConstraint?.isActive = true
        contentContainerViewTrailingConstraint = contentContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        contentContainerViewTrailingConstraint?.isActive = true
        contentContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true

        NSLayoutConstraint.activate([
            contentContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setUpFloatingDismissButton() {
        utiLog.debug("ContentContainer.setUpFloatingDismissButton")
        view.addSubview(floatingDismissButton)
        NSLayoutConstraint.activate([
            floatingDismissButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            floatingDismissButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            floatingDismissButton.widthAnchor.constraint(equalToConstant: 44),
            floatingDismissButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setUpSwipeDownGesture() {
        utiLog.debug("ContentContainer.setUpSwipeDownGesture")
        let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDownGesture.direction = .down
        swipeDownGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(swipeDownGesture)
    }

    private func installComponents() {
        utiLog.debug("ContentContainer.installComponents")
        utiLog.debug("ContentContainer.installComponents → installing swipeContainer")
        installSwipeContainer()
        utiLog.debug("ContentContainer.installComponents → installing suggestionsTray")
        installSuggestionsTray()
        utiLog.debug("ContentContainer.installComponents → installing daxLogoView")
        installDaxLogoView()
    }

    private func updateSectionTitle() {
        utiLog.debug("ContentContainer.updateSectionTitle")
        let text = computedSectionTitleText()
        currentSectionTitle = text.isEmpty ? nil : text
        utiLog.debug("ContentContainer.updateSectionTitle - resolvedTitle=\(String(describing: self.currentSectionTitle), privacy: .public)")

        let mode = switchBarHandler.currentToggleState
        switch mode {
        case .search:
            let hasFavorites = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
            if hasFavorites {
                utiLog.debug("ContentContainer.updateSectionTitle 🔀 search+hasFavorites → setting favorites title, clearing suggestions title")
                suggestionTrayManager?.setFavoritesSectionTitle(currentSectionTitle)
                suggestionTrayManager?.setSuggestionsSectionTitle(nil)
            } else {
                utiLog.debug("ContentContainer.updateSectionTitle 🔀 search+noFavorites → setting suggestions title, clearing favorites title")
                suggestionTrayManager?.setSuggestionsSectionTitle(currentSectionTitle)
                suggestionTrayManager?.setFavoritesSectionTitle(nil)
            }
            aiChatHistoryManager?.setSectionTitle(nil)
        case .aiChat:
            utiLog.debug("ContentContainer.updateSectionTitle 🔀 aiChat → clearing suggestion titles, setting chat title")
            suggestionTrayManager?.setSuggestionsSectionTitle(nil)
            suggestionTrayManager?.setFavoritesSectionTitle(nil)
            aiChatHistoryManager?.setSectionTitle(currentSectionTitle)
        }
    }

    private func computedSectionTitleText() -> String {
        utiLog.debug("ContentContainer.computedSectionTitleText")
        let mode = switchBarHandler.currentToggleState
        let hasFavorites = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let hasAutocomplete = suggestionTrayManager?.shouldDisplaySuggestionTray == true && !hasFavorites
        let hasChatHistory = aiChatHistoryManager?.hasSuggestions == true
        utiLog.debug("ContentContainer.computedSectionTitleText - mode=\(String(describing: mode), privacy: .public), hasFavorites=\(hasFavorites, privacy: .public), hasAutocomplete=\(hasAutocomplete, privacy: .public), hasChatHistory=\(hasChatHistory, privacy: .public)")
        switch mode {
        case .search:
            if hasFavorites {
                utiLog.debug("ContentContainer.computedSectionTitleText 🔀 search+hasFavorites → sectionTitleFavorites")
                return UserText.sectionTitleFavorites
            }
            if hasAutocomplete {
                utiLog.debug("ContentContainer.computedSectionTitleText 🔀 search+hasAutocomplete → sectionTitleSuggestions")
                return UserText.sectionTitleSuggestions
            }
            utiLog.debug("ContentContainer.computedSectionTitleText 🔀 search+noContent → empty")
            return ""
        case .aiChat:
            if isShowingURLFallback {
                utiLog.debug("ContentContainer.computedSectionTitleText 🔀 aiChat+urlFallback → sectionTitleSuggestions")
                return UserText.sectionTitleSuggestions
            }
            if hasChatHistory {
                let isEmpty = switchBarHandler.currentText.isEmpty
                utiLog.debug("ContentContainer.computedSectionTitleText 🔀 aiChat+chatHistory, textEmpty=\(isEmpty, privacy: .public) → \(isEmpty ? "recentChats" : "suggestedChats", privacy: .public)")
                return isEmpty ? UserText.aiChatRecentChatsTitle : UserText.aiChatSuggestedChatsTitle
            }
            utiLog.debug("ContentContainer.computedSectionTitleText 🔀 aiChat+noContent → empty")
            return ""
        }
    }

    private func installSwipeContainer() {
        utiLog.debug("ContentContainer.installSwipeContainer")
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler)
        let containerVC = manager.containerViewController
        utiLog.debug("ContentContainer.installSwipeContainer 📐 adding containerVC as child, setting constraints")
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
        utiLog.debug("ContentContainer.installSwipeContainer → setting delegate, fadeOutDelegate, isSwipeEnabled=\(self.isSwipeEnabled, privacy: .public)")
        manager.delegate = self
        manager.fadeOutDelegate = self
        manager.isSwipeEnabled = isSwipeEnabled
        swipeContainerManager = manager
    }

    private func installSuggestionsTray() {
        utiLog.debug("ContentContainer.installSuggestionsTray")
        guard let dependencies = suggestionTrayDependencies,
              let containerViewController = swipeContainerManager?.containerViewController,
              let searchContainer = swipeContainerManager?.searchPageContainer else {
            utiLog.debug("ContentContainer.installSuggestionsTray ↩️ guard: dependencies=\(self.suggestionTrayDependencies != nil, privacy: .public), containerVC=\(self.swipeContainerManager?.containerViewController != nil, privacy: .public), searchContainer=\(self.swipeContainerManager?.searchPageContainer != nil, privacy: .public)")
            return
        }

        utiLog.debug("ContentContainer.installSuggestionsTray 📐 creating SuggestionTrayManager and installing in searchContainer")
        let manager = SuggestionTrayManager(switchBarHandler: switchBarHandler, dependencies: dependencies)
        manager.delegate = self
        manager.installInContainerView(searchContainer, parentViewController: containerViewController, escapeHatch: nil)
        suggestionTrayManager = manager
    }

    private func installChatHistoryList() {
        utiLog.debug("ContentContainer.installChatHistoryList")
        guard let swipeContainerManager else {
            utiLog.debug("ContentContainer.installChatHistoryList ↩️ guard: swipeContainerManager is nil")
            return
        }

        utiLog.debug("ContentContainer.installChatHistoryList 📐 creating AIChatHistoryManager and installing via swipeContainerManager")
        let reader = SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfigurationManager)
        let historySettings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
        let suggestionsReader = AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)

        let manager = AIChatHistoryManager(suggestionsReader: suggestionsReader,
                                           aiChatSettings: aiChatSettings,
                                           viewModel: AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount))
        manager.delegate = self
        manager.titleLayoutConfiguration = .unifiedInput
        swipeContainerManager.installChatHistory(using: manager)
        manager.subscribeToTextChanges(switchBarHandler.currentTextPublisher)
        aiChatHistoryManager = manager
        manager.hasSuggestionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasSuggestions in
                guard let self else { return }
                utiLog.debug("ContentContainer.installChatHistoryList.hasSuggestionsPublisher - hasSuggestions=\(hasSuggestions, privacy: .public), mode=\(String(describing: self.switchBarHandler.currentToggleState), privacy: .public)")
                self.updateURLFallbackSuggestions(hasSuggestions: hasSuggestions, mode: self.switchBarHandler.currentToggleState)
                self.updateSectionTitle()
                self.scheduleAnimation {
                    self.updateDaxVisibility()
                    self.view.layoutIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func installDaxLogoView() {
        utiLog.debug("ContentContainer.installDaxLogoView")
        daxLogoManager.installInViewController(self, asSubviewOf: contentContainerView, anchorView: contentContainerView, isTopBarPosition: false)
    }

    private func setupSubscriptions() {
        utiLog.debug("ContentContainer.setupSubscriptions")
        setupSwitchBarSubscriptions()
    }

    private func setupSwitchBarSubscriptions() {
        utiLog.debug("ContentContainer.setupSwitchBarSubscriptions")
        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in
                guard let self else { return }

                utiLog.debug("ContentContainer.setupSwitchBarSubscriptions.textPublisher - currentText=\(currentText, privacy: .public)")
                self.suggestionTrayManager?.handleQueryUpdate(currentText, animated: true)
                self.updateSectionTitle()

                scheduleAnimation {
                    self.updateDaxVisibility()
                    self.view.layoutIfNeeded()
                }

                self.updateURLFallbackForCurrentText()
            }
            .store(in: &cancellables)

    }

    private func updateLayoutForCurrentOrientation() {
        utiLog.debug("ContentContainer.updateLayoutForCurrentOrientation - isUsingTopBar: \(self.isUsingTopBarPosition, privacy: .public), isAdjusted: \(self.isAdjustedForTopBar, privacy: .public)")
        guard isUsingTopBarPosition != isAdjustedForTopBar else {
            utiLog.debug("ContentContainer.updateLayoutForCurrentOrientation ↩️ guard: isUsingTopBarPosition == isAdjustedForTopBar, no change needed")
            return
        }
        utiLog.debug("ContentContainer.updateLayoutForCurrentOrientation 📐 adjusting for topBar=\(self.isUsingTopBarPosition, privacy: .public)")
        isAdjustedForTopBar = isUsingTopBarPosition
        updateSectionTitle()
    }

    private func observeRemoteMessagesChanges() {
        utiLog.debug("ContentContainer.observeRemoteMessagesChanges")
        notificationCancellable = NotificationCenter.default.publisher(for: RemoteMessagingStore.Notifications.remoteMessagesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                utiLog.debug("ContentContainer.observeRemoteMessagesChanges.sink → remoteMessagesDidChange received, refreshing suggestions and dax visibility")
                self.suggestionTrayManager?.showInitialSuggestions()
                self.updateDaxVisibility()
            }
    }

    private func scheduleAnimation(_ animation: @escaping () -> Void, completion: ((UIViewAnimatingPosition) -> Void)? = nil) {
        utiLog.debug("ContentContainer.scheduleAnimation")
        if contentAnimator?.state == .stopped {
            utiLog.debug("ContentContainer.scheduleAnimation 🔀 existing animator stopped, clearing")
            contentAnimator = nil
        }

        let isReusing = self.contentAnimator != nil
        let animator = self.contentAnimator ?? UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.73)
        contentAnimator = animator
        utiLog.debug("ContentContainer.scheduleAnimation → \(isReusing ? "reusing" : "created new", privacy: .public) animator, starting animation")

        animator.addAnimations(animation)
        if let completion {
            animator.addCompletion(completion)
        }

        animator.startAnimation()
    }

    // MARK: - Action Handlers

    private func handleMicrophoneButtonTapped() {
        utiLog.debug("ContentContainer.handleMicrophoneButtonTapped")
        guard isViewLoaded, view.window != nil, !view.isHidden, !(view.superview?.isHidden ?? true) else {
            utiLog.debug("ContentContainer.handleMicrophoneButtonTapped ↩️ guard: view not visible (isViewLoaded=\(self.isViewLoaded, privacy: .public), window=\(self.view.window != nil, privacy: .public), isHidden=\(self.view.isHidden, privacy: .public))")
            return
        }
        utiLog.debug("ContentContainer.handleMicrophoneButtonTapped → requesting mic access")
        SpeechRecognizer.requestMicAccess { [weak self] permission in
            guard let self,
                  self.view.window != nil,
                  self.view.superview?.isHidden != true else {
                utiLog.debug("ContentContainer.handleMicrophoneButtonTapped.micCallback ↩️ guard: self or view unavailable")
                return
            }
            if permission {
                let preferredTarget: VoiceSearchTarget? = (self.switchBarHandler.currentToggleState == .aiChat) ? .AIChat : .SERP
                utiLog.debug("ContentContainer.handleMicrophoneButtonTapped 🔀 permission granted → showVoiceSearch(target: \(String(describing: preferredTarget), privacy: .public))")
                self.showVoiceSearch(preferredTarget: preferredTarget)
            } else {
                utiLog.debug("ContentContainer.handleMicrophoneButtonTapped 🔀 permission denied → showNoMicrophonePermissionAlert")
                self.showNoMicrophonePermissionAlert()
            }
        }
    }

    @objc private func handleSwipeDown() {
        utiLog.debug("ContentContainer.handleSwipeDown")
        utiLog.debug("ContentContainer.handleSwipeDown → invoking onSwipeDownRequested (bound=\(self.onSwipeDownRequested != nil, privacy: .public))")
        onSwipeDownRequested?()
    }

    func setContentInset(top: CGFloat, bottom: CGFloat) {
        utiLog.debug("ContentContainer.setContentInset - top: \(top, privacy: .public), bottom: \(bottom, privacy: .public)")
        var insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        insets.top += Metrics.contentTopInset
        utiLog.debug("ContentContainer.setContentInset 📐 applying additionalSafeAreaInsets(top: \(insets.top, privacy: .public), bottom: \(insets.bottom, privacy: .public))")
        swipeContainerManager?.containerViewController.additionalSafeAreaInsets = insets
    }

    @objc private func handleFloatingDismissTap() {
        utiLog.debug("ContentContainer.handleFloatingDismissTap")
        utiLog.debug("ContentContainer.handleFloatingDismissTap → invoking onDismissRequested (bound=\(self.onDismissRequested != nil, privacy: .public))")
        onDismissRequested?()
    }

    private func showVoiceSearch(preferredTarget: VoiceSearchTarget? = nil) {
        utiLog.debug("ContentContainer.showVoiceSearch - preferredTarget: \(String(describing: preferredTarget), privacy: .public)")
        let voiceSearchController = VoiceSearchViewController(preferredTarget: preferredTarget)
        voiceSearchController.delegate = self
        voiceSearchController.modalTransitionStyle = .crossDissolve
        voiceSearchController.modalPresentationStyle = .overFullScreen
        present(voiceSearchController, animated: true)
    }

    private func showNoMicrophonePermissionAlert() {
        utiLog.debug("ContentContainer.showNoMicrophonePermissionAlert")
        let alertController = NoMicPermissionAlert.buildAlert()
        present(alertController, animated: true)
    }

    private func updateDaxVisibility() {
        utiLog.debug("ContentContainer.updateDaxVisibility")
        let shouldDisplaySuggestionTray = suggestionTrayManager?.shouldDisplaySuggestionTray == true
        let shouldDisplayFavoritesOverlay = suggestionTrayManager?.shouldDisplayFavoritesOverlay == true
        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: view.bounds.size)
        let isShowingChatHistory = aiChatHistoryManager?.hasSuggestions == true
        let isChatHistoryPending = aiChatHistoryManager != nil
            && aiChatHistoryManager?.hasCompletedInitialFetch != true
            && switchBarHandler.currentToggleState == .aiChat
        let isURLFallbackShowingContent = isShowingURLFallback && (suggestionTrayManager?.isShowingSuggestionTray ?? false)

        utiLog.debug("ContentContainer.updateDaxVisibility - suggestionTray=\(shouldDisplaySuggestionTray, privacy: .public), favorites=\(shouldDisplayFavoritesOverlay, privacy: .public), compact=\(isHorizontallyCompactLayoutEnabled, privacy: .public), chatHistory=\(isShowingChatHistory, privacy: .public), chatPending=\(isChatHistoryPending, privacy: .public), urlFallback=\(isURLFallbackShowingContent, privacy: .public)")

        let isHomeDaxVisible = !shouldDisplaySuggestionTray && !shouldDisplayFavoritesOverlay && !isHorizontallyCompactLayoutEnabled
        let isAIDaxVisible: Bool
        if switchBarHandler.isUsingFadeOutAnimation {
            isAIDaxVisible = !isHorizontallyCompactLayoutEnabled && !isShowingChatHistory && !isChatHistoryPending && !isURLFallbackShowingContent
            utiLog.debug("ContentContainer.updateDaxVisibility 🔀 fadeOutAnimation path → isAIDaxVisible=\(isAIDaxVisible, privacy: .public)")
        } else {
            isAIDaxVisible = !shouldDisplaySuggestionTray && !isHorizontallyCompactLayoutEnabled && !isShowingChatHistory && !isChatHistoryPending && !isURLFallbackShowingContent
            utiLog.debug("ContentContainer.updateDaxVisibility 🔀 swipe path → isAIDaxVisible=\(isAIDaxVisible, privacy: .public)")
        }

        utiLog.debug("ContentContainer.updateDaxVisibility → updateVisibility(homeDax=\(isHomeDaxVisible, privacy: .public), aiDax=\(isAIDaxVisible, privacy: .public))")
        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
        updateSectionTitle()
    }

    // MARK: - URL Fallback Suggestions

    private func applyURLFallbackForModeChange(_ mode: TextEntryMode) {
        utiLog.debug("ContentContainer.applyURLFallbackForModeChange - mode: \(String(describing: mode), privacy: .public)")
        utiLog.debug("ContentContainer.applyURLFallbackForModeChange → restoreFullSuggestions")
        restoreFullSuggestions()
        if mode == .aiChat {
            utiLog.debug("ContentContainer.applyURLFallbackForModeChange 🔀 mode=aiChat → updateURLFallbackSuggestions(hasSuggestions: \(self.chatHasSuggestions, privacy: .public))")
            updateURLFallbackSuggestions(hasSuggestions: chatHasSuggestions, mode: mode)
        } else {
            utiLog.debug("ContentContainer.applyURLFallbackForModeChange 🔀 mode=search → skipping URL fallback update")
        }
    }

    private func restoreFullSuggestions() {
        utiLog.debug("ContentContainer.restoreFullSuggestions - isShowingURLFallback: \(self.isShowingURLFallback, privacy: .public)")
        guard isShowingURLFallback else {
            utiLog.debug("ContentContainer.restoreFullSuggestions ↩️ guard: not showing URL fallback, nothing to restore")
            return
        }
        utiLog.debug("ContentContainer.restoreFullSuggestions → resetSuggestionFilter, hiding searchPage")
        suggestionTrayManager?.resetSuggestionFilter()
        swipeContainerManager?.setSearchPageVisible(false, animated: false)
        isShowingURLFallback = false
    }

    private func updateURLFallbackForCurrentText() {
        utiLog.debug("ContentContainer.updateURLFallbackForCurrentText")
        let mode = switchBarHandler.currentToggleState
        guard mode == .aiChat else {
            utiLog.debug("ContentContainer.updateURLFallbackForCurrentText ↩️ guard: mode=\(String(describing: mode), privacy: .public), not aiChat")
            return
        }
        utiLog.debug("ContentContainer.updateURLFallbackForCurrentText → updateURLFallbackSuggestions")
        updateURLFallbackSuggestions(hasSuggestions: chatHasSuggestions, mode: mode)
    }

    private func updateURLFallbackSuggestions(hasSuggestions: Bool, mode: TextEntryMode) {
        utiLog.debug("ContentContainer.updateURLFallbackSuggestions - hasSuggestions: \(hasSuggestions, privacy: .public), mode: \(String(describing: mode), privacy: .public)")
        guard mode == .aiChat else {
            utiLog.debug("ContentContainer.updateURLFallbackSuggestions ↩️ guard: mode=\(String(describing: mode), privacy: .public), not aiChat → restoring full suggestions")
            restoreFullSuggestions()
            return
        }
        let query = switchBarHandler.currentText
        let shouldShow = !hasSuggestions && !query.isBlank
        utiLog.debug("ContentContainer.updateURLFallbackSuggestions - query=\(query, privacy: .public), shouldShow=\(shouldShow, privacy: .public), isShowingURLFallback=\(self.isShowingURLFallback, privacy: .public)")
        if shouldShow {
            utiLog.debug("ContentContainer.updateURLFallbackSuggestions 🔀 shouldShow=true → showURLOnlySuggestions")
            suggestionTrayManager?.showURLOnlySuggestions(for: query, animated: false)
            if !isShowingURLFallback {
                utiLog.debug("ContentContainer.updateURLFallbackSuggestions 📐 first show → making searchPage visible")
                swipeContainerManager?.setSearchPageVisible(true, animated: false)
            }
            isShowingURLFallback = true
        } else if isShowingURLFallback {
            utiLog.debug("ContentContainer.updateURLFallbackSuggestions 🔀 shouldShow=false, wasShowingFallback → hiding URL suggestions, restoring chat")
            suggestionTrayManager?.hideURLOnlySuggestions(animated: true)
            swipeContainerManager?.setSearchPageVisible(false, animated: true)
            swipeContainerManager?.restoreChatPageVisibility()
            isShowingURLFallback = false
        } else {
            utiLog.debug("ContentContainer.updateURLFallbackSuggestions 🔀 shouldShow=false, not showing fallback → no-op")
        }
    }

    private enum Metrics {
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .panel)
        static let contentTopInset: CGFloat = 10
    }
}

// MARK: - SwipeContainerViewControllerDelegate

extension UnifiedInputContentContainerViewController: SwipeContainerViewControllerDelegate {

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didSwipeToMode mode: TextEntryMode) {
        utiLog.debug("ContentContainer.swipeContainerViewController(didSwipeToMode:) - forwarding mode: \(String(describing: mode), privacy: .public)")
        utiLog.debug("ContentContainer.swipeContainerViewController(didSwipeToMode:) → applyURLFallbackForModeChange")
        applyURLFallbackForModeChange(mode)
        utiLog.debug("ContentContainer.swipeContainerViewController(didSwipeToMode:) → switchBarHandler.setToggleState")
        switchBarHandler.setToggleState(mode)
        utiLog.debug("ContentContainer.swipeContainerViewController(didSwipeToMode:) → delegate.unifiedInputEditingStateDidChangeMode")
        delegate?.unifiedInputEditingStateDidChangeMode(mode)
        scheduleAnimation {
            self.updateDaxVisibility()
        }
    }

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didUpdateScrollProgress progress: CGFloat) {
        utiLog.debug("ContentContainer.swipeContainerViewController(didUpdateScrollProgress:) - progress: \(progress, privacy: .public)")
        daxLogoManager.updateSwipeProgress(progress)
    }
}

// MARK: - FadeOutContainerViewControllerDelegate

extension UnifiedInputContentContainerViewController: FadeOutContainerViewControllerDelegate {

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didTransitionToMode mode: TextEntryMode) {
        utiLog.debug("ContentContainer.fadeOutContainerViewController(didTransitionToMode:) - forwarding mode: \(String(describing: mode), privacy: .public)")
        utiLog.debug("ContentContainer.fadeOutContainerViewController(didTransitionToMode:) → applyURLFallbackForModeChange")
        applyURLFallbackForModeChange(mode)
        utiLog.debug("ContentContainer.fadeOutContainerViewController(didTransitionToMode:) → switchBarHandler.setToggleState")
        switchBarHandler.setToggleState(mode)
        utiLog.debug("ContentContainer.fadeOutContainerViewController(didTransitionToMode:) → delegate.unifiedInputEditingStateDidChangeMode")
        delegate?.unifiedInputEditingStateDidChangeMode(mode)
    }

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didUpdateTransitionProgress progress: CGFloat) {
        utiLog.debug("ContentContainer.fadeOutContainerViewController(didUpdateTransitionProgress:) - progress: \(progress, privacy: .public)")
        daxLogoManager.updateSwipeProgress(progress)
    }

    func fadeOutContainerViewControllerIsShowingSuggestions(_ controller: FadeOutContainerViewController) -> Bool {
        let result = suggestionTrayManager?.shouldDisplaySuggestionTray ?? false
        utiLog.debug("ContentContainer.fadeOutContainerViewControllerIsShowingSuggestions → returning \(result, privacy: .public)")
        return result
    }

    func fadeOutContainerViewControllerShouldKeepSearchVisible(_ controller: FadeOutContainerViewController) -> Bool {
        utiLog.debug("ContentContainer.fadeOutContainerViewControllerShouldKeepSearchVisible → returning isShowingURLFallback=\(self.isShowingURLFallback, privacy: .public)")
        return isShowingURLFallback
    }
}

// MARK: - SuggestionTrayManagerDelegate

extension UnifiedInputContentContainerViewController: SuggestionTrayManagerDelegate {

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectSuggestion suggestion: Suggestion) {
        utiLog.debug("ContentContainer.suggestionTrayManager(didSelectSuggestion:) → forwarding to delegate.unifiedInputEditingStateDidSelectSuggestion")
        delegate?.unifiedInputEditingStateDidSelectSuggestion(suggestion)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectFavorite favorite: BookmarkEntity) {
        utiLog.debug("ContentContainer.suggestionTrayManager(didSelectFavorite:) → forwarding to delegate.unifiedInputEditingStateDidSelectFavorite")
        delegate?.unifiedInputEditingStateDidSelectFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, shouldUpdateTextTo text: String) {
        utiLog.debug("ContentContainer.suggestionTrayManager(shouldUpdateTextTo:) → forwarding to switchBarHandler.updateCurrentText(\(text, privacy: .public))")
        switchBarHandler.updateCurrentText(text)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsEditFavorite favorite: BookmarkEntity) {
        utiLog.debug("ContentContainer.suggestionTrayManager(requestsEditFavorite:) → forwarding to delegate.unifiedInputEditingStateDidEditFavorite")
        delegate?.unifiedInputEditingStateDidEditFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsSwitchToTab tab: Tab) {
        utiLog.debug("ContentContainer.suggestionTrayManager(requestsSwitchToTab:) → forwarding to delegate.unifiedInputEditingStateDidRequestSwitchTab")
        delegate?.unifiedInputEditingStateDidRequestSwitchTab(tab)
    }

    func suggestionTrayManagerDidUpdateVisibility(_ manager: SuggestionTrayManager) {
        utiLog.debug("ContentContainer.suggestionTrayManagerDidUpdateVisibility → updateDaxVisibility")
        updateDaxVisibility()
    }
}

// MARK: - VoiceSearchViewControllerDelegate

extension UnifiedInputContentContainerViewController: VoiceSearchViewControllerDelegate {

    func voiceSearchViewController(_ controller: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        utiLog.debug("ContentContainer.voiceSearchViewController(didFinishQuery:) - query: \(String(describing: query), privacy: .public), target: \(String(describing: target), privacy: .public)")
        utiLog.debug("ContentContainer.voiceSearchViewController(didFinishQuery:) → dismissing voice search controller")
        controller.dismiss(animated: true) { [weak self] in
            guard let self, let query else {
                utiLog.debug("ContentContainer.voiceSearchViewController(didFinishQuery:).completion ↩️ guard: self=\(self != nil, privacy: .public), query=\(query != nil, privacy: .public)")
                return
            }
            let mode: TextEntryMode = (target == .AIChat) ? .aiChat : .search
            utiLog.debug("ContentContainer.voiceSearchViewController(didFinishQuery:).completion → setToggleState(\(String(describing: mode), privacy: .public)), submitText(\(query, privacy: .public))")
            self.switchBarHandler.setToggleState(mode)
            self.switchBarHandler.submitText(query)
        }
    }
}

// MARK: - AIChatHistoryManagerDelegate

extension UnifiedInputContentContainerViewController: AIChatHistoryManagerDelegate {

    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChatURL url: URL) {
        utiLog.debug("ContentContainer.aiChatHistoryManager(didSelectChatURL:) → forwarding to delegate.unifiedInputEditingStateDidSelectChatHistory(url: \(url, privacy: .public))")
        delegate?.unifiedInputEditingStateDidSelectChatHistory(url: url)
    }
}
