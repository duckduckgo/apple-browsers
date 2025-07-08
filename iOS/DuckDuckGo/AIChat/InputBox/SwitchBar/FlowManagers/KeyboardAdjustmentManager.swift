//
//  KeyboardAdjustmentManager.swift
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

/// Manages keyboard appearance and UI adjustments in response to keyboard notifications
final class KeyboardAdjustmentManager {
    
    // MARK: - Types
    
    struct Configuration {
        let logoOffset: CGFloat
        let logoOffsetForVisibleKeyboard: CGFloat
        let actionBarMargin: CGFloat
        
        static let `default` = Configuration(
            logoOffset: 18,
            logoOffsetForVisibleKeyboard: 50,
            actionBarMargin: 16
        )
    }
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private let parentView: UIView
    private weak var logoCenterYConstraint: NSLayoutConstraint?
    private weak var actionBarBottomConstraint: NSLayoutConstraint?
    
    // MARK: - Initialization
    
    init(parentView: UIView,
         logoCenterYConstraint: NSLayoutConstraint?,
         actionBarBottomConstraint: NSLayoutConstraint?,
         configuration: Configuration = .default) {
        self.parentView = parentView
        self.logoCenterYConstraint = logoCenterYConstraint
        self.actionBarBottomConstraint = actionBarBottomConstraint
        self.configuration = configuration
        
        setupKeyboardNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Private Methods
    
    private func setupKeyboardNotifications() {
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
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let animationCurveRawNSN = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height - configuration.logoOffsetForVisibleKeyboard
        let safeAreaInsets = parentView.safeAreaInsets
        let adjustedKeyboardHeight = keyboardHeight - safeAreaInsets.bottom
        let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRawNSN.uintValue)
        
        let keyboardAdjustment = adjustedKeyboardHeight / 2
        logoCenterYConstraint?.constant = configuration.logoOffset - keyboardAdjustment
        actionBarBottomConstraint?.constant = -(keyboardHeight - safeAreaInsets.bottom + configuration.actionBarMargin)
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: animationCurve,
            animations: {
                self.parentView.layoutIfNeeded()
            }
        )
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let animationCurveRawNSN = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else {
            return
        }
        
        let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRawNSN.uintValue)
        logoCenterYConstraint?.constant = configuration.logoOffset
        actionBarBottomConstraint?.constant = -configuration.actionBarMargin
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: animationCurve,
            animations: {
                self.parentView.layoutIfNeeded()
            }
        )
    }
}
