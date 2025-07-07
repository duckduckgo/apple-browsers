//
//  OmniBarViewController.swift
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
import Core

class OmniBarViewController: UIViewController, OmniBar {

    // MARK: - OmniBar conformance

    // swiftlint:disable:next force_cast
    var barView: any OmniBarView { view as! OmniBarView }

    var isBackButtonEnabled: Bool {
        get { barView.backButton.isEnabled }
        set { barView.backButton.isEnabled = newValue }
    }

    var isForwardButtonEnabled: Bool {
        get { barView.forwardButton.isEnabled }
        set { barView.forwardButton.isEnabled = newValue }
    }
    
    var text: String? {
        get { textField.text }
        set { textField.text = newValue }
    }
    var isTextFieldEditing: Bool {
        textField.isEditing
    }

    // -

    let dependencies: OmnibarDependencyProvider
    weak var omniDelegate: OmniBarDelegate?

    // MARK: - State
    private(set) lazy var state: OmniBarState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)

    private var textFieldTapped = true

    // MARK: - Animation

    var dismissButtonAnimator: UIViewPropertyAnimator?
    private var privacyIconAndTrackersAnimator = PrivacyIconAndTrackersAnimator()
    private var notificationAnimator = OmniBarNotificationAnimator()
    private let privacyIconContextualOnboardingAnimator = PrivacyIconContextualOnboardingAnimator()

    // MARK: - Constraints

    private var trailingConstraintValueForSmallWidth: CGFloat {
        if state.showAccessoryButton || state.showSettings {
            return 14
        } else {
            return 4
        }
    }

    // MARK: - Helpers

    private var textField: TextFieldWithInsets {
        barView.textField
    }

    init(dependencies: OmnibarDependencyProvider) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureTextField()
        registerNotifications()
        assignActions()
        configureEditingMenu()

        enableInteractionsWithPointer()

        barView.privacyInfoContainer.isHidden = true

        decorate()

        refreshState(state)
    }

    private func enableInteractionsWithPointer() {
        barView.backButton.isPointerInteractionEnabled = true
        barView.forwardButton.isPointerInteractionEnabled = true
        barView.settingsButton.isPointerInteractionEnabled = true
        barView.cancelButton.isPointerInteractionEnabled = true
        barView.bookmarksButton.isPointerInteractionEnabled = true
        barView.accessoryButton.isPointerInteractionEnabled = true
        barView.menuButton.isPointerInteractionEnabled = true
        barView.refreshButton.isPointerInteractionEnabled = true
        barView.shareButton.isPointerInteractionEnabled = true
        barView.clearButton.isPointerInteractionEnabled = true
    }

    private func configureTextField() {
        let theme = ThemeManager.shared.currentTheme

        textField.delegate = self
        textField.attributedPlaceholder = NSAttributedString(string: UserText.searchDuckDuckGo,
                                                             attributes: [.foregroundColor: theme.searchBarTextPlaceholderColor])

        textField.textDragInteraction?.isEnabled = false

        textField.onCopyAction = { field in
            guard let range = field.selectedTextRange else { return }
            UIPasteboard.general.string = field.text(in: range)
        }
    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidChange),
                                               name: UITextField.textDidChangeNotification,
                                               object: textField)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadSpeechRecognizerAvailability),
                                               name: .speechRecognizerDidChangeAvailability,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }

    private func assignActions() {
        barView.onTextEntered = { [weak self] in
            self?.onTextEntered()
        }
        barView.onVoiceSearchButtonPressed = { [weak self] in
            self?.onVoiceSearchButtonPressed()
        }
        barView.onAbortButtonPressed = { [weak self] in
            self?.onAbortButtonPressed()
        }
        barView.onClearButtonPressed = { [weak self] in
            self?.onClearButtonPressed()
        }
        barView.onPrivacyIconPressed = { [weak self] in
            self?.onPrivacyIconPressed()
        }
        barView.onMenuButtonPressed = { [weak self] in
            self?.onMenuButtonPressed()
        }
        barView.onTrackersViewPressed = { [weak self] in
            self?.onTrackersViewPressed()
        }
        barView.onSettingsButtonPressed = { [weak self] in
            self?.onSettingsButtonPressed()
        }
        barView.onCancelPressed = { [weak self] in
            self?.onCancelPressed()
        }
        barView.onRefreshPressed = { [weak self] in
            self?.onRefreshPressed()
        }
        barView.onRefreshPressed = { [weak self] in
            self?.onRefreshPressed()
        }
        barView.onSharePressed = { [weak self] in
            self?.onSharePressed()
        }
        barView.onBackPressed = { [weak self] in
            self?.onBackPressed()
        }
        barView.onForwardPressed = { [weak self] in
            self?.onForwardPressed()
        }
        barView.onBookmarksPressed = { [weak self] in
            self?.onBookmarksPressed()
        }
        barView.onAccessoryPressed = { [weak self] in
            self?.onAccessoryPressed()
        }
        barView.onDismissPressed = { [weak self] in
            self?.onDismissPressed()
        }
        barView.onSettingsLongPress = { [weak self] in
            self?.onSettingsLongPress()
        }
        barView.onAccessoryLongPress = { [weak self] in
            self?.onAccessoryLongPress()
        }
    }

    private func configureEditingMenu() {
        let title = UserText.actionPasteAndGo
        UIMenuController.shared.menuItems = [UIMenuItem(title: title, action: #selector(self.pasteURLAndGo))]
    }

    // MARK: - OmniBar conformance

    func showSeparator() {
        barView.showSeparator()
    }

    func hideSeparator() {
        barView.hideSeparator()
    }

    func moveSeparatorToTop() {
        barView.moveSeparatorToTop()
    }

    func moveSeparatorToBottom() {
        barView.moveSeparatorToBottom()
    }

    func useSmallTopSpacing() {
        // no-op - implemented in subclass
    }

    func useRegularTopSpacing() {
        // no-op - implemented in subclass
    }

    func preventShadowsOnTop() {
        // no-op - implemented in subclass
    }

    func preventShadowsOnBottom() {
        // no-op - implemented in subclass
    }

    func startBrowsing() {
        refreshState(state.onBrowsingStartedState)
    }

    func stopBrowsing() {
        refreshState(state.onBrowsingStoppedState)
    }

    func startLoading() {
        refreshState(state.withLoading())
    }

    func stopLoading() {
        refreshState(state.withoutLoading())
    }

    func cancel() {
        refreshState(state.onEditingStoppedState)
    }

    func updateQuery(_ query: String?) {
        text = query
        textDidChange()
    }

    func beginEditing() {
        textFieldTapped = false
        defer {
            textFieldTapped = true
        }
        textField.becomeFirstResponder()
    }

    func endEditing() {
        textField.resignFirstResponder()
    }

    func refreshText(forUrl url: URL?, forceFullURL: Bool) {
        guard !textField.isEditing else { return }
        guard let url = url else {
            textField.text = nil
            return
        }

        if let query = url.searchQuery {
            textField.text = query
        } else {
            textField.attributedText = AddressDisplayHelper.addressForDisplay(url: url, showsFullURL: textField.isEditing || forceFullURL)
        }
    }

    func enterPhoneState() {
        refreshState(state.onEnterPhoneState)
    }

    func enterPadState() {
        refreshState(state.onEnterPadState)
    }

    func removeTextSelection() {
        textField.selectedTextRange = nil
    }

    func selectTextToEnd(_ offset: Int) {
        guard let fromPosition = textField.position(from: textField.beginningOfDocument, offset: offset) else { return }
        textField.selectedTextRange = textField.textRange(from: fromPosition, to: textField.endOfDocument)
    }

    func updateAccessoryType(_ type: OmniBarAccessoryType) {
        DispatchQueue.main.async {
            self.barView.accessoryType = type
        }
    }

    func showOrScheduleCookiesManagedNotification(isCosmetic: Bool) {
        let type: OmniBarNotificationType = isCosmetic ? .cookiePopupHidden : .cookiePopupManaged

        enqueueAnimationIfNeeded { [weak self] in
            guard let self else { return }
            self.notificationAnimator.showNotification(type, in: barView, viewController: self)
        }
    }

    func showOrScheduleOnboardingPrivacyIconAnimation() {
        enqueueAnimationIfNeeded { [weak self] in
            guard let self else { return }
            self.privacyIconContextualOnboardingAnimator.showPrivacyIconAnimation(in: barView)
        }
    }

    func dismissOnboardingPrivacyIconAnimation() {
        privacyIconContextualOnboardingAnimator.dismissPrivacyIconAnimation(barView.privacyInfoContainer.privacyIcon)
    }

    func startTrackersAnimation(_ privacyInfo: PrivacyInfo, forDaxDialog: Bool) {
        guard state.allowsTrackersAnimation, !barView.privacyInfoContainer.isAnimationPlaying else { return }

        privacyIconAndTrackersAnimator.configure(barView.privacyInfoContainer, with: privacyInfo)

        if TrackerAnimationLogic.shouldAnimateTrackers(for: privacyInfo.trackerInfo) {
            if forDaxDialog {
                privacyIconAndTrackersAnimator.startAnimationForDaxDialog(in: barView, with: privacyInfo)
            } else {
                privacyIconAndTrackersAnimator.startAnimating(in: barView, with: privacyInfo)
            }
        } else {
            privacyIconAndTrackersAnimator.completeForNoAnimation()
        }
    }

    func updatePrivacyIcon(for privacyInfo: PrivacyInfo?) {
        guard let privacyInfo = privacyInfo,
              !barView.privacyInfoContainer.isAnimationPlaying,
              !privacyIconAndTrackersAnimator.isAnimatingForDaxDialog
        else { return }

        if privacyInfo.url.isDuckPlayer {
            showCustomIcon(icon: .duckPlayer)
            return
        }

        if privacyInfo.isSpecialErrorPageVisible {
            showCustomIcon(icon: .specialError)
            return
        }

        let icon = PrivacyIconLogic.privacyIcon(for: privacyInfo)
        barView.privacyInfoContainer.privacyIcon.updateIcon(icon)
        barView.privacyInfoContainer.privacyIcon.isHidden = false
        barView.customIconView.isHidden = true
    }

    func hidePrivacyIcon() {
        barView.privacyInfoContainer.privacyIcon.isHidden = true
    }

    func resetPrivacyIcon(for url: URL?) {
        cancelAllAnimations()
        barView.privacyInfoContainer.privacyIcon.isHidden = false

        let icon = PrivacyIconLogic.privacyIcon(for: url)
        barView.privacyInfoContainer.privacyIcon.updateIcon(icon)
        barView.customIconView.isHidden = true
    }

    func cancelAllAnimations() {
        privacyIconAndTrackersAnimator.cancelAnimations(in: barView)
        notificationAnimator.cancelAnimations(in: barView)
        privacyIconContextualOnboardingAnimator.dismissPrivacyIconAnimation(barView.privacyInfoContainer.privacyIcon)
    }

    func completeAnimationForDaxDialog() {
        privacyIconAndTrackersAnimator.completeAnimationForDaxDialog(in: barView)
    }

    // MARK: - Private/animation

    private func enqueueAnimationIfNeeded(_ block: @escaping () -> Void) {
        if privacyIconAndTrackersAnimator.state == .completed {
            block()
        } else {
            privacyIconAndTrackersAnimator.onAnimationCompletion(block)
        }
    }

    // MARK: - Private

    // Support static custom icons, for things like internal pages, for example
    func showCustomIcon(icon: OmniBarIcon) {
        barView.privacyInfoContainer.privacyIcon.isHidden = true
        barView.customIconView.image = icon.image
        barView.privacyInfoContainer.addSubview(barView.customIconView)
        barView.customIconView.isHidden = false
    }

    @objc private func didEnterBackground() {
        cancelAllAnimations()
    }

    private func refreshState(_ newState: any OmniBarState) {
        let oldState: OmniBarState = self.state
        if state.requiresUpdate(transitioningInto: newState) {
            Logger.general.debug("OmniBar entering \(newState.description) from \(self.state.description)")

            if state.isDifferentState(than: newState) {
                if newState.clearTextOnStart {
                    clear()
                }
                cancelAllAnimations()
            }
            state = newState
        }

        updateInterface(from: oldState, to: state)

        UIView.animate(withDuration: 0.0) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }

    func updateInterface(from oldState: any OmniBarState, to state: any OmniBarState) {
        updateLeftIconContainerState(oldState: oldState, newState: state)

        barView.isPrivacyInfoContainerHidden = !state.showPrivacyIcon
        barView.isClearButtonHidden = !state.showClear
        barView.isMenuButtonHidden = !state.showMenu
        barView.isSettingsButtonHidden = !state.showSettings
        barView.isCancelButtonHidden = !state.showCancel
        barView.isRefreshButtonHidden = !state.showRefresh
        barView.isShareButtonHidden = !state.showShare
        barView.isVoiceSearchButtonHidden = !state.showVoiceSearch
        barView.isAbortButtonHidden = !state.showAbort
        barView.isBackButtonHidden = !state.showBackButton
        barView.isForwardButtonHidden = !state.showForwardButton
        barView.isBookmarksButtonHidden = !state.showBookmarksButton
        barView.isAccessoryButtonHidden = !state.showAccessoryButton

    }

    func onQuerySubmitted() {
        if let suggestion = omniDelegate?.selectedSuggestion() {
            omniDelegate?.onOmniSuggestionSelected(suggestion)
        } else {
            guard let query = textField.text?.trimmingWhitespace(), !query.isEmpty else {
                return
            }
            resignFirstResponder()

            if let url = URL(trimmedAddressBarString: query), url.isValid {
                omniDelegate?.onOmniQuerySubmitted(url.absoluteString)
            } else {
                omniDelegate?.onOmniQuerySubmitted(query)
            }
        }
    }

    @objc private func textDidChange() {
        let newQuery = textField.text ?? ""
        omniDelegate?.onOmniQueryUpdated(newQuery)
        if newQuery.isEmpty {
            refreshState(state.onTextClearedState)
        } else {
            refreshState(state.onTextEnteredState)
        }
    }

    @objc private func reloadSpeechRecognizerAvailability() {
        assert(Thread.isMainThread)
        state = state.onReloadState
        refreshState(state)
    }

    @objc private func pasteURLAndGo(sender: UIMenuItem) {
        guard let pastedText = UIPasteboard.general.string else { return }
        textField.text = pastedText
        onQuerySubmitted()
    }

    private func clear() {
        textField.text = nil
        omniDelegate?.onOmniQueryUpdated("")
    }

    private func updateLeftIconContainerState(oldState: any OmniBarState, newState: any OmniBarState) {
        if oldState.showSearchLoupe && newState.showDismiss {
            animateDismissButtonTransition(from: barView.searchLoupe, to: barView.dismissButton)
        } else if oldState.showDismiss && newState.showSearchLoupe {
            animateDismissButtonTransition(from: barView.dismissButton, to: barView.searchLoupe)
        } else if dismissButtonAnimator == nil || dismissButtonAnimator?.isRunning == false {
            updateLeftContainerVisibility(state: newState)
        }

        if !state.showDismiss && !newState.showSearchLoupe {
            barView.leftIconContainerView.isHidden = true
        } else {
            barView.leftIconContainerView.isHidden = false
        }
    }

    func animateDismissButtonTransition(from oldView: UIView, to newView: UIView) {
        dismissButtonAnimator?.stopAnimation(true)
        let animationOffset: CGFloat = 20
        let animationDuration: CGFloat = 0.7
        let animationDampingRatio: CGFloat = 0.6

        newView.alpha = 0
        newView.transform = CGAffineTransform(translationX: -animationOffset, y: 0)
        newView.isHidden = false
        oldView.isHidden = false

        dismissButtonAnimator = UIViewPropertyAnimator(duration: animationDuration, dampingRatio: animationDampingRatio) {
            oldView.alpha = 0
            oldView.transform = CGAffineTransform(translationX: -animationOffset, y: 0)
            newView.alpha = 1.0
            newView.transform = .identity
        }

        dismissButtonAnimator?.isInterruptible = true

        dismissButtonAnimator?.addCompletion { position in
            if position == .end {
                oldView.isHidden = true
                oldView.transform = .identity
            }
        }

        dismissButtonAnimator?.startAnimation()
    }

    private func updateLeftContainerVisibility(state: any OmniBarState) {
        barView.isSearchLoupeHidden = !state.showSearchLoupe
        barView.isDismissButtonHidden = !state.showDismiss
        barView.dismissButton.alpha = state.showDismiss ? 1 : 0
        barView.searchLoupe.alpha = state.showSearchLoupe ? 1 : 0
    }

    // MARK: - Control actions

    private func onTextEntered() {
        onQuerySubmitted()
    }

    private func onVoiceSearchButtonPressed() {
        omniDelegate?.onVoiceSearchPressed()
    }

    private func onAbortButtonPressed() {
        omniDelegate?.onAbortPressed()
    }

    private func onClearButtonPressed() {
        omniDelegate?.onClearPressed()
        refreshState(state.onTextClearedState)
    }

    private func onPrivacyIconPressed() {
        let isPrivacyIconHighlighted = privacyIconContextualOnboardingAnimator.isPrivacyIconHighlighted(barView.privacyInfoContainer.privacyIcon)
        omniDelegate?.onPrivacyIconPressed(isHighlighted: isPrivacyIconHighlighted)
    }

    private func onMenuButtonPressed() {
        omniDelegate?.onMenuPressed()
    }

    private func onTrackersViewPressed() {
        cancelAllAnimations()
        textField.becomeFirstResponder()
    }

    private func onSettingsButtonPressed() {
        Pixel.fire(pixel: .addressBarSettings)
        omniDelegate?.onSettingsPressed()
    }

    private func onCancelPressed() {
        omniDelegate?.onCancelPressed()
        refreshState(state.onEditingStoppedState)
    }

    private func onRefreshPressed() {
        Pixel.fire(pixel: .refreshPressed)
        cancelAllAnimations()
        omniDelegate?.onRefreshPressed()
    }

    private func onSharePressed() {
        omniDelegate?.onSharePressed()
    }

    private func onBackPressed() {
        omniDelegate?.onBackPressed()
    }

    private func onForwardPressed() {
        omniDelegate?.onForwardPressed()
    }

    private func onBookmarksPressed() {
        Pixel.fire(pixel: .bookmarksButtonPressed,
                   withAdditionalParameters: [PixelParameters.originatedFromMenu: "0"])
        omniDelegate?.onBookmarksPressed()
    }

    private func onAccessoryPressed() {
        omniDelegate?.onAccessoryPressed(accessoryType: barView.accessoryType)
    }

    private func onDismissPressed() {
        omniDelegate?.onCancelPressed()
        refreshState(state.onEditingStoppedState)
    }

    private func onSettingsLongPress() {
        omniDelegate?.onSettingsLongPressed()
    }

    private func onAccessoryLongPress() {
        omniDelegate?.onAccessoryLongPressed(accessoryType: barView.accessoryType)
    }
}

// MARK: - TextFieldDelegate

extension OmniBarViewController: UITextFieldDelegate {
    @objc func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        self.refreshState(self.state.onEditingStartedState)
        return true
    }

    @objc func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        omniDelegate?.onTextFieldWillBeginEditing(barView, tapped: textFieldTapped)
        return true
    }

    @objc func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.async {
            let highlightText = self.omniDelegate?.onTextFieldDidBeginEditing(self.barView) ?? true
            self.refreshState(self.state.onEditingStartedState)

            if highlightText {
                self.textField.selectAll(nil)
            }
            self.omniDelegate?.onDidBeginEditing()
        }
    }

    @objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        omniDelegate?.onEnterPressed()
        return true
    }

    @objc func textFieldDidEndEditing(_ textField: UITextField) {
        switch omniDelegate?.onEditingEnd() {
        case .dismissed, .none:
            refreshState(state.onEditingStoppedState)
        case .suspended:
            refreshState(state.onEditingSuspendedState)
        }
        self.omniDelegate?.onDidEndEditing()
    }
}

// MARK: - Theming

extension OmniBarViewController {

    private func decorate() {
        privacyIconAndTrackersAnimator.resetImageProvider()

        if let url = textField.text.flatMap({ URL(trimmedAddressBarString: $0.trimmingWhitespace()) }) {
            textField.attributedText = AddressDisplayHelper.addressForDisplay(url: url, showsFullURL: textField.isEditing)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            privacyIconAndTrackersAnimator.resetImageProvider()
        }
    }
}
