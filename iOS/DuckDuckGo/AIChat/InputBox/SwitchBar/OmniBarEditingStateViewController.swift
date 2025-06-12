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

protocol OmniBarEditingStateViewControllerDelegate: AnyObject {
    func onQueryUpdated(_ query: String)
    func onQuerySubmitted(_ query: String)
    func onPromptSubmitted(_ query: String)
}

/// Later: Inject auto suggestions here.
final class OmniBarEditingStateViewController: UIViewController {
    var textAreaView: UIView {
        switchBarVC.textEntryViewController.textEntryView
    }
    private var cancellables = Set<AnyCancellable>()
    private let switchBarHandler: SwitchBarHandling
    private lazy var switchBarVC = SwitchBarViewController(switchBarHandler: switchBarHandler)
    weak var delegate: OmniBarEditingStateViewControllerDelegate?

    var expectedStartFrame: CGRect?

    lazy var isTopBarPosition = AppDependencyProvider.shared.appSettings.currentAddressBarPosition == .top
    private var topSwitchBarConstraint: NSLayoutConstraint?

    internal init(switchBarHandler: any SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        installSwitchBarVC()
        self.view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        animateAppearance()
    }

    private func animateAppearance() {

        guard let expectedStartFrame else {
            self.switchBarVC.setExpanded(true)
            return
        }

        // Prepare initial state
        let heightConstraint = switchBarVC.view.heightAnchor.constraint(equalToConstant: expectedStartFrame.height)
        if isTopBarPosition {
            heightConstraint.isActive = true
            topPositionAppearance(expectedStartFrame: expectedStartFrame, heightConstraint: heightConstraint)
        } else {
            bottomPositionAppearance()
        }

    }

    private func topPositionAppearance(expectedStartFrame: CGRect, heightConstraint: NSLayoutConstraint) {
        topSwitchBarConstraint = switchBarVC.view.topAnchor.constraint(equalTo: view.topAnchor, constant: expectedStartFrame.minY)
        topSwitchBarConstraint?.isActive = true
        self.switchBarVC.setExpanded(false)
        self.switchBarVC.view.alpha = 0.0

        self.view.layoutIfNeeded()

        // Create animators
        let backgroundFadeAnimator = UIViewPropertyAnimator(duration: 0.15, curve: .easeIn) {
            self.view.backgroundColor = UIColor(designSystemColor: .background)
        }

        let fadeInAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .easeIn) {
            self.switchBarVC.view.alpha = 1.0
        }

        let expandAnimator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.7) {
            self.switchBarVC.setExpanded(true)
            heightConstraint.isActive = false

            self.switchBarVC.view.layoutIfNeeded()
        }

        // Schedule animations
        backgroundFadeAnimator.addCompletion { _ in
            expandAnimator.startAnimation()
            self.switchBarVC.focusTextField()
        }

        // Start animations
        backgroundFadeAnimator.startAnimation()
        fadeInAnimator.startAnimation()
    }

    private func bottomPositionAppearance() {

        topSwitchBarConstraint = switchBarVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80)
        topSwitchBarConstraint?.isActive = true
        self.switchBarVC.setExpanded(true)
        self.switchBarVC.view.alpha = 0.0

        self.view.layoutIfNeeded()

        // Create animators
        let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.75) {
            self.view.backgroundColor = UIColor(designSystemColor: .background)
            self.switchBarVC.view.alpha = 1.0
            self.topSwitchBarConstraint?.constant = 20

            self.view.layoutIfNeeded()
        }

        // Schedule animations
        animator.addCompletion { _ in
            self.switchBarVC.focusTextField()
        }

        // Start animations
        animator.startAnimation()
    }

    @objc private func dismissButtonTapped(_ sender: UIButton) {
        switchBarVC.unfocusTextField()
        dismissAnimated()
    }

    @objc func dismissAnimated(_ completion: (() -> Void)? = nil) {
        animateDismissal {
            DispatchQueue.main.async {
                if self.presentingViewController != nil {
                    self.dismiss(animated: false)
                }
                completion?()
            }
        }
    }

    private func animateDismissal(_ completion: (() -> Void)? = nil) {

        self.view.layoutIfNeeded()

        if isTopBarPosition {
            topPositionDismissal(completion)
        } else {
            bottomPositionDismissal(completion)
        }

    }

    private func topPositionDismissal(_ completion: (() -> Void)?) {
        // Create animators
        let collapseAnimator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.7) {
            self.switchBarVC.setExpanded(false)
            if let expectedStartFrame = self.expectedStartFrame {
                let heightConstraint = self.switchBarVC.view.heightAnchor.constraint(equalToConstant: expectedStartFrame.height)
                heightConstraint.isActive = true
            }

            self.view.layoutIfNeeded()
        }

        let backgroundFadeAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
            self.view.backgroundColor = .clear
        }

        let fadeOutAnimator = UIViewPropertyAnimator(duration: 0.15, curve: .easeIn) {
            self.switchBarVC.view.alpha = 0.0
        }

        fadeOutAnimator.addCompletion { _ in
            completion?()
        }

        // Start animations
        collapseAnimator.startAnimation()
        backgroundFadeAnimator.startAnimation()
        fadeOutAnimator.startAnimation(afterDelay: 0.15)
    }

    private func bottomPositionDismissal(_ completion: (() -> Void)?) {
        let animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
            self.view.backgroundColor = .clear
            self.switchBarVC.view.alpha = 0.0
            self.topSwitchBarConstraint?.constant = 80

            self.view.layoutIfNeeded()
        }

        animator.addCompletion { _ in
            completion?()
        }

        animator.startAnimation()
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
        setupSubscriptions()

    }

    private func setupSubscriptions() {
        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in
                self?.delegate?.onQueryUpdated(currentText)
            }
            .store(in: &cancellables)

        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { newState in
                switch newState {
                case .search:
                    print("search mode")
                case .aiChat:
                    print("AI chat mode")
                }
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

    }
    
    func selectAllText() {
        switchBarVC.textEntryViewController.selectAllText()
    }
}
