//
//  DefaultOmniBarViewController.swift
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
import Suggestions
import Bookmarks
import AIChat

final class DefaultOmniBarViewController: OmniBarViewController {

    var isSuggestionTrayVisible: Bool {
        omniDelegate?.isSuggestionTrayVisible() == true
    }

    private lazy var omniBarView = DefaultOmniBarView.create()
    private let aiChatSettings = AIChatSettings()
    private weak var editingStateViewController: OmniBarEditingStateViewController?

//    let editModeTransitioningDelegate = OmniBarEditingStateTransitioningDelegate()

    override func loadView() {
        view = omniBarView
    }

    // MARK: - Initialization

    override func viewDidLoad() {
        super.viewDidLoad()

        // Handle address bar position changes to set the shadow correctly
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(addressBarPositionChanged),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateShadowAppearanceByApplyingLayerMask()
    }

    override func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if aiChatSettings.isAIChatSearchInputUserSettingsEnabled {
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

        updateShadowAppearanceByApplyingLayerMask()
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

    override func endEditing() {
        super.endEditing()
        editingStateViewController?.dismissAnimated()
    }

    var shouldClipShadows: Bool {
        state.isBrowsing
            && !isSuggestionTrayVisible
    }

    // MARK: Notifications

    @objc private func addressBarPositionChanged() {
        updateShadowAppearanceByApplyingLayerMask()
    }

    // MARK: - Private Helper Methods

    private func updateShadowAppearanceByApplyingLayerMask() {
        omniBarView.updateMaskLayer(maskTop: dependencies.appSettings.currentAddressBarPosition.isBottom,
                                    clip: shouldClipShadows)
    }

    private func presentExperimentalEditingState(for textField: UITextField) {
        guard editingStateViewController == nil else { return }
        guard let suggestionsDependencies = dependencies.suggestionTrayDependencies else { return }

        let switchBarHandler = createSwitchBarHandler(for: textField)
        let shouldAutoSelectText = shouldAutoSelectTextForUrl(textField)

        let editingStateViewController = OmniBarEditingStateViewController(switchBarHandler: switchBarHandler)
        editingStateViewController.delegate = self

        editingStateViewController.modalPresentationStyle = .custom
        editingStateViewController.transitioningDelegate = self

        editingStateViewController.suggestionTrayDependencies = suggestionsDependencies
        editingStateViewController.automaticallySelectsTextOnAppear = shouldAutoSelectText
        
        self.editingStateViewController = editingStateViewController

        present(editingStateViewController, animated: true)
    }

    private func createSwitchBarHandler(for textField: UITextField) -> SwitchBarHandler {
        let switchBarHandler = SwitchBarHandler(voiceSearchHelper: dependencies.voiceSearchHelper,
                                                storage: UserDefaults.standard)

        guard let currentText = omniBarView.text?.trimmingWhitespace(), !currentText.isEmpty else {
            return switchBarHandler
        }

        /// Determine whether the current text in the omnibar is a search query or a URL.
        /// - If the text is a URL, retrieve the full URL from the delegate and update the text with the full URL for display.
        /// - If the text is a search query, simply update the text with the query itself.
        if URL(trimmedAddressBarString: currentText) != nil,
           let url = omniDelegate?.didRequestCurrentURL() {
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

extension DefaultOmniBarViewController: OmniBarEditingStateViewControllerDelegate {
    func onQueryUpdated(_ query: String) {
    }

    func onQuerySubmitted(_ query: String) {
        editingStateViewController?.dismissAnimated()
        omniDelegate?.onOmniQuerySubmitted(query)
    }

    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?) {
        editingStateViewController?.dismissAnimated { [weak self] in
            guard let self else { return }
            self.omniDelegate?.onPromptSubmitted(query, tools: tools)
        }
    }

    func onSelectFavorite(_ favorite: BookmarkEntity) {
        editingStateViewController?.dismissAnimated()
        omniDelegate?.onSelectFavorite(favorite)
    }

    func onSelectSuggestion(_ suggestion: Suggestion) {
        omniDelegate?.onOmniSuggestionSelected(suggestion)
        editingStateViewController?.dismissAnimated()
    }

    func onVoiceSearchRequested(from mode: TextEntryMode) {
        editingStateViewController?.dismissAnimated { [weak self] in
            guard let self else { return }

            let voiceSearchTarget: VoiceSearchTarget = (mode == .aiChat) ? .AIChat : .SERP
            self.omniDelegate?.onVoiceSearchPressed(preferredTarget: voiceSearchTarget)
        }
    }
}

extension DefaultOmniBarViewController: UIViewControllerTransitioningDelegate {

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return OmniBarEditingStateTransition(isPresenting: true,
                                             addressBarPosition: dependencies.appSettings.currentAddressBarPosition)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return OmniBarEditingStateTransition(isPresenting: false,
                                             addressBarPosition: dependencies.appSettings.currentAddressBarPosition)
    }
}
