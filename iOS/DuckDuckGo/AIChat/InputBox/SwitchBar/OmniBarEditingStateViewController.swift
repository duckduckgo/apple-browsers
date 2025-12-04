//
//  OmniBarEditingStateViewController.swift
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

import UIKit
import DesignResourcesKit
import Combine
import BrowserServicesKit
import Bookmarks
import Persistence
import History
import Core
import Suggestions
import SwiftUI
import AIChat
import RemoteMessaging

protocol OmniBarEditingStateViewControllerDelegate: AnyObject {
    func onQueryUpdated(_ query: String)
    func onQuerySubmitted(_ query: String)
    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?)
    func onSelectFavorite(_ favorite: BookmarkEntity)
    func onEditFavorite(_ favorite: BookmarkEntity)
    func onSelectSuggestion(_ suggestion: Suggestion)
    func onVoiceSearchRequested(from mode: TextEntryMode)
    func onDismissRequested()
}

/// Main coordinator for the OmniBar editing state, managing multiple specialized components
final class OmniBarEditingStateViewController: UIViewController, OmniBarEditingStateTransitioning {

    // MARK: - Properties

    var actionBarView: UIView? { navigationActionBarManager?.view }

    var suggestionTrayDependencies: SuggestionTrayDependencies?

    weak var delegate: OmniBarEditingStateViewControllerDelegate?
    var automaticallySelectsTextOnAppear = false

    // MARK: - Core Components
    private lazy var contentContainerView = UIView()

    private lazy var bottomLocationSwitchBarBackgroundMaskView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.backgroundColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    private var isUsingTopBarPosition: Bool
    private var isLandscapeOrientation: Bool = false {
        didSet {
            isUsingTopBarPosition = appSettings.currentAddressBarPosition == .top || isLandscapeOrientation
            switchBarHandler.updateBarPosition(isTop: isUsingTopBarPosition)
        }
    }
    private var isAdjustedForTopBar: Bool

    lazy var switchBarVC = SwitchBarViewController(switchBarHandler: switchBarHandler,
                                                   showsSeparator: !isUsingTopBarPosition,
                                                   reduceTopPaddings: !isUsingTopBarPosition)

    private weak var contentContainerViewLeadingConstraint: NSLayoutConstraint?
    private weak var contentContainerViewTrailingConstraint: NSLayoutConstraint?

    let appSettings: AppSettings
    private let featureFlagger: FeatureFlagger

    // MARK: - Manager Components

    private var swipeContainerManager: SwipeContainerManager?
    private var navigationActionBarManager: NavigationActionBarManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private let daxLogoManager: DaxLogoManager
    private var notificationCancellable: AnyCancellable?
    private let switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding

    private weak var contentAnimator: UIViewPropertyAnimator?

    // MARK: - Initialization

    internal init(switchBarHandler: any SwitchBarHandling,
                  switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding = SwitchBarSubmissionMetrics(),
                  appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
                  featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.switchBarHandler = switchBarHandler
        self.switchBarSubmissionMetrics = switchBarSubmissionMetrics
        self.daxLogoManager = DaxLogoManager()
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
        self.isUsingTopBarPosition = appSettings.currentAddressBarPosition == .top || isLandscapeOrientation
        self.isAdjustedForTopBar = self.isUsingTopBarPosition

        super.init(nibName: nil, bundle: nil)
    }

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
        updateSwipeContainerSafeArea()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        switchBarVC.focusTextField()
        if automaticallySelectsTextOnAppear {
            DispatchQueue.main.async {
                self.switchBarVC.textEntryViewController.selectAllText()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DailyPixel.fireDailyAndCount(pixel: .aiChatInternalSwitchBarDisplayed)
        DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarShown)
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

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        adjustLayoutForViewSize(view.bounds.size)
    }

    private func requiresHorizontallyCompactLayout(for size: CGSize) -> Bool {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        return isPhone && size.width > size.height
    }

    private func adjustLayoutForViewSize(_ size: CGSize) {

        let isHorizontallyCompactLayoutEnabled = requiresHorizontallyCompactLayout(for: size)
        self.isLandscapeOrientation = isHorizontallyCompactLayoutEnabled

        let horizontalMargin: CGFloat = isHorizontallyCompactLayoutEnabled ? Constants.horizontalMarginForCompactLayout : 0
        self.contentContainerViewLeadingConstraint?.constant = horizontalMargin
        self.contentContainerViewTrailingConstraint?.constant = -horizontalMargin
        self.updateDaxVisibility()
        self.updateLayoutForCurrentOrientation()

        self.navigationActionBarManager?.navigationActionBarViewController?.isShowingGradient = !isHorizontallyCompactLayoutEnabled && isUsingTopBarPosition
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            self.adjustLayoutForViewSize(size)
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Private Methods

    private func setupView() {
        setUpContentContainer()

        view.backgroundColor = Constants.backgroundColor
    }

    private func setUpContentContainer() {
        view.addSubview(contentContainerView)
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false

        contentContainerViewLeadingConstraint = contentContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        contentContainerViewLeadingConstraint?.isActive = true
        contentContainerViewTrailingConstraint = contentContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        contentContainerViewTrailingConstraint?.isActive = true

        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func installComponents() {
        installSwitchBarVC()
        installSwipeContainer()
        installSuggestionsTray()
        installDaxLogoView()
        installNavigationActionBar()

        contentContainerView.bringSubviewToFront(switchBarVC.view)
    }

    private func installSwitchBarVC() {
        addChild(switchBarVC)
        let container = contentContainerView
        container.addSubview(switchBarVC.view)
        switchBarVC.view.translatesAutoresizingMaskIntoConstraints = false
        switchBarVC.view.setContentHuggingPriority(.defaultHigh, for: .vertical)

        // Prevent showing scrollable content under the switcher
        switchBarVC.view.backgroundColor = Constants.backgroundColor

        NSLayoutConstraint.activate([
            switchBarVC.view.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
            switchBarVC.view.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor)
        ])

        if isUsingTopBarPosition {
            switchBarVC.view.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8).isActive = true
        } else {

            switchBarVC.view.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor, constant: -8).isActive = true

            // Add content mask
            // Prevents content overflow from being visible under text input.
            container.addSubview(bottomLocationSwitchBarBackgroundMaskView)
            NSLayoutConstraint.activate([
                bottomLocationSwitchBarBackgroundMaskView.topAnchor.constraint(equalTo: switchBarVC.view.bottomAnchor),
                bottomLocationSwitchBarBackgroundMaskView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bottomLocationSwitchBarBackgroundMaskView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bottomLocationSwitchBarBackgroundMaskView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }

        switchBarVC.textEntryViewController.isUsingIncreasedButtonPadding = !isUsingTopBarPosition
        switchBarVC.didMove(toParent: self)
        switchBarVC.backButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
    }

    private func installSwipeContainer() {
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler)
        manager.installInViewController(self, asSubviewOf: contentContainerView, barView: switchBarVC.view, isTopBarPosition: isUsingTopBarPosition)
        manager.delegate = self
        manager.fadeOutDelegate = self
        swipeContainerManager = manager
    }

    private func installSuggestionsTray() {
        guard let dependencies = suggestionTrayDependencies,
              let containerViewController = swipeContainerManager?.containerViewController,
              let searchContainer = swipeContainerManager?.searchPageContainer else { return }

        let manager = SuggestionTrayManager(switchBarHandler: switchBarHandler, dependencies: dependencies)
        manager.delegate = self
        manager.installInContainerView(searchContainer, parentViewController: containerViewController)
        suggestionTrayManager = manager
    }

    private func installDaxLogoView() {
        if let view = switchBarVC.segmentedPickerView {
            daxLogoManager.installInViewController(self, asSubviewOf: contentContainerView, barView: view, isTopBarPosition: isUsingTopBarPosition)
        }
    }

    private func installNavigationActionBar() {
        let manager = NavigationActionBarManager(switchBarHandler: switchBarHandler)
        if isUsingTopBarPosition {
            // Note this is not installed in contentContainerView - this is floating over content.
            manager.installInViewController(self)
        } else {
            manager.installInViewController(switchBarVC.textEntryViewController, inView: switchBarVC.textEntryViewController.buttonsContainerView)
        }
        manager.delegate = self
        manager.animationDelegate = self
        navigationActionBarManager = manager
    }

    private func setupSubscriptions() {
        switchBarVC.textEntryViewController.textHeightChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in

                self?.scheduleAnimation({
                    self?.updateSwipeContainerSafeArea()
                    self?.view.layoutIfNeeded()
                }, completion: nil)

            }
            .store(in: &cancellables)

        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in

                guard let self else { return }

                self.delegate?.onQueryUpdated(currentText)

                scheduleAnimation {
                    self.updateDaxVisibility()
                    self.updateSwipeContainerSafeArea()
                    self.view.layoutIfNeeded()
                }

                self.suggestionTrayManager?.handleQueryUpdate(currentText, animated: true)
            }
            .store(in: &cancellables)

        switchBarHandler.textSubmissionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] submission in
                guard let self = self else { return }

                let text = submission.text

                if self.switchBarHandler.isCurrentTextValidURL {
                    self.delegate?.onQuerySubmitted(text)
                    return
                }

                switch submission.mode {
                case .search:
                    switchBarSubmissionMetrics.process(text, for: .search)
                    self.delegate?.onQuerySubmitted(text)

                case .aiChat:
                    switchBarSubmissionMetrics.process(text, for: .aiChat)
                    // If we (re)add the web rag button, then we need to add it to the array of tools Duck.ai should use
                    //  for this submission.
                    self.delegate?.onPromptSubmitted(text, tools: nil)
                }
            }
            .store(in: &cancellables)

        switchBarHandler.microphoneButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleMicrophoneButtonTapped()
            }
            .store(in: &cancellables)
    }

    private func updateSwipeContainerSafeArea() {
        if isUsingTopBarPosition {
            swipeContainerManager?.containerViewController.additionalSafeAreaInsets.bottom = 0
        } else {
            switchBarVC.view.layoutIfNeeded()
            let barHeigthAboveSafeArea = switchBarVC.view.bounds.height - switchBarVC.view.safeAreaInsets.bottom
            swipeContainerManager?.containerViewController.additionalSafeAreaInsets.bottom = barHeigthAboveSafeArea
        }
    }

    private func updateLayoutForCurrentOrientation() {

        guard isUsingTopBarPosition != isAdjustedForTopBar else { return }

        var currentSelection: UITextRange?
        if switchBarVC.textEntryViewController.isFocused {
            currentSelection = switchBarVC.textEntryViewController.currentTextSelection
        }

        contentContainerView.subviews.forEach { $0.removeFromSuperview() }
        navigationActionBarManager?.navigationActionBarViewController?.willMove(toParent: nil)
        navigationActionBarManager?.navigationActionBarViewController?.view.removeFromSuperview()
        navigationActionBarManager?.navigationActionBarViewController?.removeFromParent()

        switchBarVC.showsSeparator = !isUsingTopBarPosition

        installComponents()

        if let currentSelection {
            switchBarVC.textEntryViewController.focusTextField()
            switchBarVC.textEntryViewController.currentTextSelection = currentSelection
        }

        isAdjustedForTopBar = isUsingTopBarPosition
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

        // Starts the animation. No effect if it's already running.
        animator.startAnimation()
    }

    // MARK: - Action Handlers

    @objc private func dismissButtonTapped(_ sender: UIButton) {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarBackButtonPressed, withAdditionalParameters: switchBarHandler.modeParameters)
        switchBarVC.unfocusTextField()
        delegate?.onDismissRequested()
        dismissAnimated()
    }

    private func handleMicrophoneButtonTapped() {
        // Do not dismiss the OmniBar. Just dismiss the keyboard and present Voice Search above.
        switchBarVC.unfocusTextField()
        SpeechRecognizer.requestMicAccess { [weak self] permission in
            guard let self = self else { return }
            if permission {
                let preferredTarget: VoiceSearchTarget? = (self.switchBarHandler.currentToggleState == .aiChat) ? .AIChat : .SERP
                self.showVoiceSearch(preferredTarget: preferredTarget)
            } else {
                self.showNoMicrophonePermissionAlert()
            }
        }
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

        let isHomeDaxVisible = !shouldDisplaySuggestionTray && !shouldDisplayFavoritesOverlay && !isHorizontallyCompactLayoutEnabled

        let isAIDaxVisible: Bool
        if switchBarHandler.isUsingFadeOutAnimation {
            isAIDaxVisible = !isHorizontallyCompactLayoutEnabled
        } else {
            isAIDaxVisible = !shouldDisplaySuggestionTray && !isHorizontallyCompactLayoutEnabled
        }

        daxLogoManager.updateVisibility(isHomeDaxVisible: isHomeDaxVisible, isAIDaxVisible: isAIDaxVisible)
    }
}

// MARK: - NavigationActionBarViewAnimationDelegate

extension OmniBarEditingStateViewController: NavigationActionBarViewAnimationDelegate {
    func animateActionBarView(_ view: NavigationActionBarView,
                              animations: @escaping () -> Void,
                              completion: ((UIViewAnimatingPosition) -> Void)?) {
        scheduleAnimation({
            animations()
            self.view.layoutIfNeeded()
        }, completion: completion)
    }
}

// MARK: - SwipeContainerManagerDelegate

extension OmniBarEditingStateViewController: SwipeContainerViewControllerDelegate {

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didSwipeToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
    }

    func swipeContainerViewController(_ controller: SwipeContainerViewController, didUpdateScrollProgress progress: CGFloat) {
        // Forward the scroll progress to the switch bar to animate the toggle
        switchBarVC.updateScrollProgress(progress)

        daxLogoManager.updateSwipeProgress(progress)
    }
}

// MARK: - FadeOutContainerViewControllerDelegate

extension OmniBarEditingStateViewController: FadeOutContainerViewControllerDelegate {

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didTransitionToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
    }

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didUpdateTransitionProgress progress: CGFloat) {
        // Forward the transition progress to the switch bar to animate the toggle
        switchBarVC.updateScrollProgress(progress)

        daxLogoManager.updateSwipeProgress(progress)
    }

    func fadeOutContainerViewControllerIsShowingSuggestions(_ controller: FadeOutContainerViewController) -> Bool {
        return suggestionTrayManager?.shouldDisplaySuggestionTray ?? false
    }
}

// MARK: - SuggestionTrayManagerDelegate

extension OmniBarEditingStateViewController: SuggestionTrayManagerDelegate {

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectSuggestion suggestion: Suggestion) {
        delegate?.onSelectSuggestion(suggestion)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectFavorite favorite: BookmarkEntity) {
        delegate?.onSelectFavorite(favorite)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, shouldUpdateTextTo text: String) {
        switchBarHandler.updateCurrentText(text)
    }

    func suggestionTrayManager(_ manager: SuggestionTrayManager, requestsEditFavorite favorite: BookmarkEntity) {
        delegate?.onEditFavorite(favorite)
    }

}

// MARK: - NavigationActionBarManagerDelegate

extension OmniBarEditingStateViewController: NavigationActionBarManagerDelegate {

    func navigationActionBarManagerDidTapMicrophone(_ manager: NavigationActionBarManager) {
        handleMicrophoneButtonTapped()
    }

    func navigationActionBarManagerDidTapNewLine(_ manager: NavigationActionBarManager) {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarFloatingReturnPressed)
        let currentText = switchBarHandler.currentText
        let newText = currentText + "\n"
        switchBarHandler.updateCurrentText(newText)
    }

    func navigationActionBarManagerDidTapSearch(_ manager: NavigationActionBarManager) {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarFloatingSubmitPressed, withAdditionalParameters: switchBarHandler.modeParameters)
        let currentText = switchBarHandler.currentText
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switchBarHandler.submitText(currentText)
        }
    }
}

// MARK: - VoiceSearchViewControllerDelegate

extension OmniBarEditingStateViewController: VoiceSearchViewControllerDelegate {

    func voiceSearchViewController(_ controller: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        if let text = query {
            switchBarHandler.updateCurrentText(text)
        }

        controller.dismiss(animated: true) { [weak self] in
            guard let self = self, let query = query else { return }
            self.handleVoiceSearchCompletion(with: query, for: target)
        }
    }

    private func handleVoiceSearchCompletion(with query: String, for target: VoiceSearchTarget) {
        switch target {
        case .SERP:
            delegate?.onQuerySubmitted(query)

        case .AIChat:
            delegate?.onPromptSubmitted(query, tools: nil)
        }
    }
}

private extension OmniBarEditingStateViewController {
    struct Constants {
        // Adjusts for two buttons in the action bar
        static let horizontalMarginForCompactLayout: CGFloat = 108
        static let backgroundColor = UIColor(designSystemColor: .background)
        static let animationDuration: TimeInterval = 0.15
    }
}
