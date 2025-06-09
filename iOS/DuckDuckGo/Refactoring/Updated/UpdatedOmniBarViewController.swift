//
//  UpdatedOmniBarViewController.swift
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
import PrivacyDashboard

final class UpdatedOmniBarViewController: OmniBarViewController {

    private lazy var omniBarView = UpdatedOmniBarView.create()
    private let experimentalManager = ExperimentalAIChatManager()

    override func loadView() {
        view = omniBarView
    }

    // MARK: - Initialization

    override func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if experimentalManager.isExperimentalTransitionEnabled {
            let switchBarVC = SwitchBarPlaygroundViewController()
            switchBarVC.modalPresentationStyle = .overFullScreen

            // Get the layout guide from the omni bar view
            let proxy: OmniBarTransitionProxy = omniBarView
            let searchAreaContainerGuide = proxy.fieldContainerLayoutGuide
//            guard let window = view.window else {
//                present(switchBarVC, animated: true)
//                return false
//            }

            switchBarVC.alpha = 0

            // Present the view controller
            present(switchBarVC, animated: false) {
                searchAreaContainerGuide.topAnchor.constraint(equalTo: switchBarVC.fieldContainerLayoutGuide.topAnchor).isActive = true
                searchAreaContainerGuide.leadingAnchor.constraint(equalTo: switchBarVC.fieldContainerLayoutGuide.leadingAnchor).isActive = true
                searchAreaContainerGuide.trailingAnchor.constraint(equalTo: switchBarVC.fieldContainerLayoutGuide.trailingAnchor).isActive = true

                switchBarVC.mainView.layoutIfNeeded()
                switchBarVC.containerView.

                // Animate to final position using the target layout guide
                UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.2) {
                    switchBarVC.alpha = 1
                }.startAnimation()
            }
            return false
        }
        return super.textFieldShouldBeginEditing(textField)
    }

    override func animateDismissButtonTransition(from oldView: UIView, to newView: UIView) {
        dismissButtonAnimator?.stopAnimation(true)
        let animationDuration: CGFloat = 0.25

        newView.alpha = 0
        newView.isHidden = false
        oldView.isHidden = false

        dismissButtonAnimator = UIViewPropertyAnimator(duration: animationDuration, curve: .easeInOut) {
            oldView.alpha = 0
            newView.alpha = 1.0
        }

        dismissButtonAnimator?.isInterruptible = true

        dismissButtonAnimator?.addCompletion { position in
            if position == .end {
                oldView.isHidden = true
            }
        }

        dismissButtonAnimator?.startAnimation()
    }

    override func showCustomIcon(icon: OmniBarIcon) {
        // This causes constraints to be removed...
        barView.customIconView.removeFromSuperview()

        super.showCustomIcon(icon: icon)

        guard let customIconSuperview = barView.customIconView.superview else { return }

        // ... so we can reapply them here
        barView.customIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            barView.customIconView.centerYAnchor.constraint(equalTo: customIconSuperview.centerYAnchor),
            barView.customIconView.leadingAnchor.constraint(equalTo: customIconSuperview.leadingAnchor),
        ])
    }

    override func updateInterface(from oldState: any OmniBarState, to state: any OmniBarState) {
        super.updateInterface(from: oldState, to: state)

        omniBarView.isUsingCompactLayout = !state.hasLargeWidth

        // Should show separator only when there is another button next to accessory button
        let isShowingSeparator = state.showAccessoryButton && (state.showClear || state.showVoiceSearch || state.showRefresh || state.showAbort || state.showShare)
        omniBarView.isShowingSeparator = isShowingSeparator
    }

    override func textFieldDidBeginEditing(_ textField: UITextField) {
        super.textFieldDidBeginEditing(textField)
        
        omniBarView.layoutIfNeeded()
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0.0, options: [.curveEaseOut]) {
            self.omniBarView.isActiveState = true
            self.omniBarView.layoutIfNeeded()
        }
    }

    override func textFieldDidEndEditing(_ textField: UITextField) {
        super.textFieldDidEndEditing(textField)

        omniBarView.layoutIfNeeded()
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0.0, options: [.curveEaseOut]) {
            self.omniBarView.isActiveState = false
            self.omniBarView.layoutIfNeeded()
        }
    }

    override func useSmallTopSpacing() {
        omniBarView.isUsingSmallTopSpacing = true
    }

    override func useRegularTopSpacing() {
        omniBarView.isUsingSmallTopSpacing = false
    }

    override func preventShadowsOnTop() {
        omniBarView.updateMaskLayer(maskTop: true)
    }

    override func preventShadowsOnBottom() {
        omniBarView.updateMaskLayer(maskTop: false)
    }
}
