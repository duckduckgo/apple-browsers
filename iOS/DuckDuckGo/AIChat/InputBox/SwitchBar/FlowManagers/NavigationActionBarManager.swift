//
//  NavigationActionBarManager.swift
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

import Foundation
import UIKit

/// Protocol for handling navigation action bar events
protocol NavigationActionBarManagerDelegate: AnyObject {
    func navigationActionBarManagerDidTapMicrophone(_ manager: NavigationActionBarManager)
    func navigationActionBarManagerDidTapNewLine(_ manager: NavigationActionBarManager)
    func navigationActionBarManagerDidTapSearch(_ manager: NavigationActionBarManager)
}

/// Manages the navigation action bar displayed at the bottom of the screen
final class NavigationActionBarManager {
    
    // MARK: - Properties
    
    weak var delegate: NavigationActionBarManagerDelegate?
    
    private let switchBarHandler: SwitchBarHandling
    private var navigationActionBarViewController: NavigationActionBarViewController?
    private var navigationActionBarViewModel: NavigationActionBarViewModel?
    private var bottomConstraint: NSLayoutConstraint?
    private var isAnimating = false
    private var lastKeyboardHeight: CGFloat = 0
    
    // MARK: - Initialization
    
    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        setupKeyboardObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Installs the navigation action bar in the provided parent view controller
    @MainActor
    func installInViewController(_ viewController: UIViewController, safeAreaGuide: UILayoutGuide) {
        let viewModel = NavigationActionBarViewModel(
            switchBarHandler: switchBarHandler,
            onMicrophoneTapped: { [weak self] in
                guard let self = self else { return }
                self.delegate?.navigationActionBarManagerDidTapMicrophone(self)
            },
            onNewLineTapped: { [weak self] in
                guard let self = self else { return }
                self.delegate?.navigationActionBarManagerDidTapNewLine(self)
            },
            onSearchTapped: { [weak self] in
                guard let self = self else { return }
                self.delegate?.navigationActionBarManagerDidTapSearch(self)
            }
        )
        navigationActionBarViewModel = viewModel
        
        let actionBarViewController = NavigationActionBarViewController(viewModel: viewModel)
        navigationActionBarViewController = actionBarViewController
        
        viewController.addChild(actionBarViewController)
        viewController.view.addSubview(actionBarViewController.view)
        actionBarViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Store the bottom constraint for keyboard adjustments
        let bottomConstraint = actionBarViewController.view.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor)
        self.bottomConstraint = bottomConstraint
        
        NSLayoutConstraint.activate([
            actionBarViewController.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            actionBarViewController.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            bottomConstraint
        ])
        
        actionBarViewController.didMove(toParent: viewController)
    }
    
    /// Removes the navigation action bar from its parent
    func removeFromParent() {
        navigationActionBarViewController?.willMove(toParent: nil)
        navigationActionBarViewController?.view.removeFromSuperview()
        navigationActionBarViewController?.removeFromParent()
        navigationActionBarViewController = nil
        navigationActionBarViewModel = nil
        bottomConstraint = nil
        isAnimating = false
        lastKeyboardHeight = 0
    }
    
    // MARK: - Private Methods
    
    private func setupKeyboardObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        
        // Also observe frame changes to handle keyboard accessories
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        updateKeyboardPosition(from: notification)
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        updateKeyboardPosition(from: notification)
    }
    
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        updateKeyboardPosition(from: notification)
    }
    
    private func updateKeyboardPosition(from notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let bottomConstraint = bottomConstraint,
              let parentView = navigationActionBarViewController?.view.superview else { return }
        
        // Check if keyboard is visible (not off-screen)
        let screenHeight = UIScreen.main.bounds.height
        let isKeyboardVisible = keyboardFrame.origin.y < screenHeight
        
        let targetKeyboardHeight: CGFloat
        if isKeyboardVisible {
            // Calculate keyboard height relative to the parent view
            let keyboardTopInParentView = parentView.convert(CGPoint(x: 0, y: keyboardFrame.origin.y), from: nil).y
            let parentViewHeight = parentView.bounds.height
            let calculatedHeight = parentViewHeight - keyboardTopInParentView
            targetKeyboardHeight = max(0, calculatedHeight)
        } else {
            targetKeyboardHeight = 0
        }
        
        // Avoid unnecessary updates
        let heightDifference = abs(targetKeyboardHeight - lastKeyboardHeight)
        guard heightDifference > 1.0 || !isAnimating else { return }
        
        lastKeyboardHeight = targetKeyboardHeight
        isAnimating = true
        
        bottomConstraint.constant = -targetKeyboardHeight
        
        UIView.animate(withDuration: animationDuration, animations: {
            parentView.layoutIfNeeded()
        }) { _ in
            self.isAnimating = false
        }
    }
}
