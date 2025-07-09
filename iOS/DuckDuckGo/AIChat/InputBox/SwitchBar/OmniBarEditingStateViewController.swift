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

protocol OmniBarEditingStateViewControllerDelegate: AnyObject {
    func onQueryUpdated(_ query: String)
    func onQuerySubmitted(_ query: String)
    func onPromptSubmitted(_ query: String)
    func onSelectFavorite(_ favorite: BookmarkEntity)
    func onSelectSuggestion(_ suggestion: Suggestion)
    func onVoiceSearchRequested(from mode: TextEntryMode)
}

/// Main coordinator for the OmniBar editing state, managing multiple specialized components
final class OmniBarEditingStateViewController: UIViewController, OmniBarEditingStateTransitionDelegate {

    // MARK: - Properties
    
    var textAreaView: UIView {
        switchBarVC.textEntryViewController.textEntryView
    }

    var rootView: UIView { view }
    var logoView: UIView? { daxLogoManager.logoView }

    weak var delegate: OmniBarEditingStateViewControllerDelegate?
    var expectedStartFrame: CGRect?
    var suggestionTrayDependencies: SuggestionTrayDependencies?
    
    // MARK: - Core Components
    
    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()
    private let transitionAnimator = OmniBarEditingStateAnimator()
    
    lazy var isTopBarPosition = AppDependencyProvider.shared.appSettings.currentAddressBarPosition == .top
    lazy var switchBarVC = SwitchBarViewController(switchBarHandler: switchBarHandler)
    
    // MARK: - Manager Components
    
    private var swipeContainerManager: SwipeContainerManager?
    private var keyboardAdjustmentManager: KeyboardAdjustmentManager?
    private var navigationActionBarManager: NavigationActionBarManager?
    private var suggestionTrayManager: SuggestionTrayManager?
    private let daxLogoManager = DaxLogoManager()

    // MARK: - Initialization
    
    internal init(switchBarHandler: any SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        installComponents()
        setupSubscriptions()
        setupTransitionAnimator()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        transitionAnimator.animateAppearance()
        switchBarVC.focusTextField()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DailyPixel.fireDailyAndCount(pixel: .aiChatInternalSwitchBarDisplayed)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        swipeContainerManager?.updateLayout(viewBounds: view.bounds)
    }

    // MARK: - Public Methods
    
    @objc func dismissAnimated(_ completion: (() -> Void)? = nil) {
        transitionAnimator.animateDismissal {
            DispatchQueue.main.async {
                if self.presentingViewController != nil {
                    self.dismiss(animated: false)
                }
                completion?()
            }
        }
    }
    
    func setUpForInitialSelectedState() {
        switchBarVC.textEntryViewController.selectAllText()
        suggestionTrayManager?.showInitialSuggestions()
        swipeContainerManager?.updateLayout(viewBounds: view.bounds)
    }

    // MARK: - Private Methods
    
    private func setupView() {
        view.backgroundColor = UIColor(designSystemColor: .background)
    }
    
    private func installComponents() {
        installSwitchBarVC()
        installSwipeContainer()
        installSuggestionsTray()
        installDaxLogoView()
        installNavigationActionBar()
        installKeyboardManager()
    }
    
    private func setupTransitionAnimator() {
        transitionAnimator.transitionDelegate = self
    }
    
    private func installSwitchBarVC() {
        addChild(switchBarVC)
        view.addSubview(switchBarVC.view)
        switchBarVC.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            switchBarVC.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            switchBarVC.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        switchBarVC.didMove(toParent: self)
        switchBarVC.backButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
    }

    private func installSwipeContainer() {
        let manager = SwipeContainerManager(switchBarHandler: switchBarHandler)
        manager.delegate = self
        manager.installInView(view, belowView: switchBarVC.view, safeAreaGuide: view.safeAreaLayoutGuide)
        swipeContainerManager = manager
    }

    private func installSuggestionsTray() {
        guard let dependencies = suggestionTrayDependencies,
              let searchContainer = swipeContainerManager?.searchPageContainer else { return }
        
        let manager = SuggestionTrayManager(switchBarHandler: switchBarHandler, dependencies: dependencies)
        manager.delegate = self
        manager.installInContainerView(searchContainer, parentViewController: self)
        suggestionTrayManager = manager
    }

    private func installDaxLogoView() {
        daxLogoManager.installInViewController(self)
    }
    
    private func installNavigationActionBar() {
        let manager = NavigationActionBarManager(switchBarHandler: switchBarHandler)
        manager.delegate = self
        manager.installInViewController(self, safeAreaGuide: view.safeAreaLayoutGuide)
        navigationActionBarManager = manager
    }
    
    private func installKeyboardManager() {
        let manager = KeyboardAdjustmentManager(
            parentView: view,
            logoCenterYConstraint: daxLogoManager.logoCenterYConstraint,
            actionBarBottomConstraint: navigationActionBarManager?.actionBarBottomConstraint
        )
        keyboardAdjustmentManager = manager
    }

    private func setupSubscriptions() {
        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in
                self?.delegate?.onQueryUpdated(currentText)
                self?.suggestionTrayManager?.handleQueryUpdate(currentText)
            }
            .store(in: &cancellables)

        switchBarHandler.textSubmissionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] submission in
                switch submission.mode {
                case .search:
                    self?.delegate?.onQuerySubmitted(submission.text)
                case .aiChat:
                    self?.delegate?.onPromptSubmitted(submission.text)
                }

                self?.switchBarHandler.clearText()
            }
            .store(in: &cancellables)

        switchBarHandler.microphoneButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleMicrophoneButtonTapped()
            }
            .store(in: &cancellables)
    }

    // MARK: - Action Handlers

    @objc private func dismissButtonTapped(_ sender: UIButton) {
        switchBarVC.unfocusTextField()
        dismissAnimated()
    }

    private func handleMicrophoneButtonTapped() {
        delegate?.onVoiceSearchRequested(from: switchBarHandler.currentToggleState)
    }
}

// MARK: - SwipeContainerManagerDelegate

extension OmniBarEditingStateViewController: SwipeContainerManagerDelegate {
    
    func swipeContainerManager(_ manager: SwipeContainerManager, didSwipeToMode mode: TextEntryMode) {
        switchBarHandler.setToggleState(mode)
    }
    
    func swipeContainerManager(_ manager: SwipeContainerManager, didUpdateScrollProgress progress: CGFloat) {
        // Forward the scroll progress to the switch bar to animate the toggle
        switchBarVC.updateScrollProgress(progress)
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
}

// MARK: - NavigationActionBarManagerDelegate

extension OmniBarEditingStateViewController: NavigationActionBarManagerDelegate {
    
    func navigationActionBarManagerDidTapMicrophone(_ manager: NavigationActionBarManager) {
        handleMicrophoneButtonTapped()
    }
    
    func navigationActionBarManagerDidTapNewLine(_ manager: NavigationActionBarManager) {
        let currentText = switchBarHandler.currentText
        let newText = currentText + "\n"
        switchBarHandler.updateCurrentText(newText)
    }
    
    func navigationActionBarManagerDidTapSearch(_ manager: NavigationActionBarManager) {
        let currentText = switchBarHandler.currentText
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switchBarHandler.submitText(currentText)
        }
    }
}
