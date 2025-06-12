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
    private weak var editingStateViewController: OmniBarEditingStateViewController?

    override func loadView() {
        view = omniBarView
    }

    // MARK: - Initialization

    override func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if experimentalManager.isExperimentalTransitionEnabled {
            presentExperimentalEditingState(for: textField)
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

    // MARK: - Private Helper Methods

    private func presentExperimentalEditingState(for textField: UITextField) {
        let switchBarHandler = createSwitchBarHandler(for: textField)
        let shouldAutoSelectText = shouldAutoSelectTextForUrl(textField)

        let editingStateViewController = OmniBarEditingStateViewController(switchBarHandler: switchBarHandler)
        editingStateViewController.delegate = self
        editingStateViewController.expectedStartFrame = barView.searchContainer.convert(barView.searchContainer.bounds, to: nil)
        editingStateViewController.modalPresentationStyle = .overFullScreen

        present(editingStateViewController, animated: false)
        self.editingStateViewController = editingStateViewController

        if shouldAutoSelectText {
            DispatchQueue.main.async {
                editingStateViewController.selectAllText()
            }
        }
    }

    private func createSwitchBarHandler(for textField: UITextField) -> SwitchBarHandler {
        let switchBarHandler = SwitchBarHandler()

        guard let currentText = omniBarView.text else {
            return switchBarHandler
        }

        if let textFieldText = textField.text,
           let url = URL(trimmedAddressBarString: textFieldText.trimmingWhitespace()) {
            let urlText = AddressDisplayHelper.addressForDisplay(url: url, showsFullURL: true)
            switchBarHandler.updateCurrentText(urlText.string)
        } else {
            switchBarHandler.updateCurrentText(currentText)
        }

        return switchBarHandler
    }

    private func shouldAutoSelectTextForUrl(_ textField: UITextField) -> Bool {
        guard let textFieldText = textField.text else { return false }
        return URL(trimmedAddressBarString: textFieldText.trimmingWhitespace()) != nil
    }
}

extension UpdatedOmniBarViewController: OmniBarEditingStateViewControllerDelegate {
    func onQueryUpdated(_ query: String) {
    }

    func onQuerySubmitted(_ query: String) {
        editingStateViewController?.dismissAnimated()
        omniDelegate?.onOmniQuerySubmitted(query)
    }

    func onPromptSubmitted(_ query: String) {
        editingStateViewController?.dismissAnimated {
            self.omniDelegate?.onOmniPromptSubmitted(query)
        }
    }
}
