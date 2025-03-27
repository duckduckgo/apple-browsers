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
import Core

final class DefaultOmniBarViewController: UIViewController, OmniBar {
    private(set) lazy var omniBarView: DefaultOmniBarView = {
        DefaultOmniBarView.loadFromXib(dependencies: dependencies)
    }()

    private let dependencies: OmnibarDependencyProvider
    weak var omniDelegate: OmniBarDelegate?

    // MARK: - State
    private lazy var state: OmniBarState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)

    private var textFieldTapped = true

    // MARK: - Animation

    private var dismissButtonAnimator: UIViewPropertyAnimator?
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
        omniBarView.textField
    }

    // MARK: - OmniBar conformance

    var barView: OmniBarView {
        omniBarView
    }


    var isTextFieldEditing: Bool { textField.isFirstResponder }

    var isBackButtonEnabled: Bool {
        get { omniBarView.backButton.isEnabled }
        set { omniBarView.backButton.isEnabled = newValue }
    }

    var isForwardButtonEnabled: Bool {
        get { omniBarView.forwardButton.isEnabled }
        set { omniBarView.forwardButton.isEnabled = newValue }
    }

    var text: String? {
        get { textField.text }
        set { textField.text = newValue }
    }

    // MARK: -

    init(dependencies: OmnibarDependencyProvider) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = omniBarView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureTextField()
        registerNotifications()
        assignActions()
        configureEditingMenu()

        decorate()
    }

    private func configureTextField() {
        let theme = ThemeManager.shared.currentTheme

        textField.delegate = self
        textField.attributedPlaceholder = NSAttributedString(string: UserText.searchDuckDuckGo,
                                                             attributes: [.foregroundColor: theme.searchBarTextPlaceholderColor])

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadSpeechRecognizerAvailability),
                                               name: .speechRecognizerDidChangeAvailability,
                                               object: nil)

    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidChange),
                                               name: UITextField.textDidChangeNotification,
                                               object: textField)
    }

    private func assignActions() {
        omniBarView.onTextEntered = { [weak self] in
            self?.onTextEntered()
        }
        omniBarView.onVoiceSearchButtonPressed = { [weak self] in
            self?.onVoiceSearchButtonPressed()
        }
        omniBarView.onAbortButtonPressed = { [weak self] in
            self?.onAbortButtonPressed()
        }
        omniBarView.onClearButtonPressed = { [weak self] in
            self?.onClearButtonPressed()
        }
        omniBarView.onPrivacyIconPressed = { [weak self] in
            self?.onPrivacyIconPressed()
        }
        omniBarView.onMenuButtonPressed = { [weak self] in
            self?.onMenuButtonPressed()
        }
        omniBarView.onTrackersViewPressed = { [weak self] in
            self?.onTrackersViewPressed()
        }
        omniBarView.onSettingsButtonPressed = { [weak self] in
            self?.onSettingsButtonPressed()
        }
        omniBarView.onCancelPressed = { [weak self] in
            self?.onCancelPressed()
        }
        omniBarView.onRefreshPressed = { [weak self] in
            self?.onRefreshPressed()
        }
        omniBarView.onBackPressed = { [weak self] in
            self?.onBackPressed()
        }
        omniBarView.onForwardPressed = { [weak self] in
            self?.onForwardPressed()
        }
        omniBarView.onBookmarksPressed = { [weak self] in
            self?.onBookmarksPressed()
        }
        omniBarView.onAccessoryPressed = { [weak self] in
            self?.onAccessoryPressed()
        }
        omniBarView.onDismissPressed = { [weak self] in
            self?.onDismissPressed()
        }
        omniBarView.onSettingsLongPress = { [weak self] in
            self?.onSettingsLongPress()
        }
        omniBarView.onAccessoryLongPress = { [weak self] in
            self?.onAccessoryLongPress()
        }
    }

    private func configureEditingMenu() {
        let title = UserText.actionPasteAndGo
        UIMenuController.shared.menuItems = [UIMenuItem(title: title, action: #selector(self.pasteURLAndGo))]
    }

    // MARK: - OmniBar conformance

    func showSeparator() {
        omniBarView.showSeparator()
    }

    func hideSeparator() {
        omniBarView.hideSeparator()
    }

    func moveSeparatorToTop() {
        omniBarView.moveSeparatorToTop()
    }

    func moveSeparatorToBottom() {
        omniBarView.moveSeparatorToBottom()
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
        omniBarView.removeTextSelection()
    }

    func selectTextToEnd(_ offset: Int) {
        guard let fromPosition = textField.position(from: textField.beginningOfDocument, offset: offset) else { return }
        textField.selectedTextRange = textField.textRange(from: fromPosition, to: textField.endOfDocument)
    }

    func updateAccessoryType(_ type: OmniBarAccessoryType) {
        DispatchQueue.main.async {
            self.omniBarView.accessoryType = type
            self.updatePadding()
        }
    }

    func showOrScheduleCookiesManagedNotification(isCosmetic: Bool) {
        let type: OmniBarNotificationType = isCosmetic ? .cookiePopupHidden : .cookiePopupManaged

        enqueueAnimationIfNeeded { [weak self] in
            guard let self else { return }
            self.notificationAnimator.showNotification(type, in: omniBarView, viewController: self)
        }
    }

    func showOrScheduleOnboardingPrivacyIconAnimation() {
        enqueueAnimationIfNeeded { [weak self] in
            guard let self else { return }
            self.privacyIconContextualOnboardingAnimator.showPrivacyIconAnimation(in: omniBarView)
        }
    }

    func dismissOnboardingPrivacyIconAnimation() {
        privacyIconContextualOnboardingAnimator.dismissPrivacyIconAnimation(omniBarView.privacyInfoContainer.privacyIcon)
    }

    func startTrackersAnimation(_ privacyInfo: PrivacyInfo, forDaxDialog: Bool) {
        guard state.allowsTrackersAnimation, !omniBarView.privacyInfoContainer.isAnimationPlaying else { return }

        privacyIconAndTrackersAnimator.configure(omniBarView.privacyInfoContainer, with: privacyInfo)

        if TrackerAnimationLogic.shouldAnimateTrackers(for: privacyInfo.trackerInfo) {
            if forDaxDialog {
                privacyIconAndTrackersAnimator.startAnimationForDaxDialog(in: omniBarView, with: privacyInfo)
            } else {
                privacyIconAndTrackersAnimator.startAnimating(in: omniBarView, with: privacyInfo)
            }
        } else {
            privacyIconAndTrackersAnimator.completeForNoAnimation()
        }
    }

    func updatePrivacyIcon(for privacyInfo: PrivacyInfo?) {
        guard let privacyInfo = privacyInfo,
              !omniBarView.privacyInfoContainer.isAnimationPlaying,
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
        omniBarView.privacyInfoContainer.privacyIcon.updateIcon(icon)
        omniBarView.privacyInfoContainer.privacyIcon.isHidden = false
        omniBarView.customIconView.isHidden = true
    }

    func hidePrivacyIcon() {
        omniBarView.privacyInfoContainer.privacyIcon.isHidden = true
    }

    func resetPrivacyIcon(for url: URL?) {
        cancelAllAnimations()
        omniBarView.privacyInfoContainer.privacyIcon.isHidden = false

        let icon = PrivacyIconLogic.privacyIcon(for: url)
        omniBarView.privacyInfoContainer.privacyIcon.updateIcon(icon)
        omniBarView.customIconView.isHidden = true
    }

    func cancelAllAnimations() {
        privacyIconAndTrackersAnimator.cancelAnimations(in: omniBarView)
        notificationAnimator.cancelAnimations(in: omniBarView)
        privacyIconContextualOnboardingAnimator.dismissPrivacyIconAnimation(omniBarView.privacyInfoContainer.privacyIcon)
    }

    func completeAnimationForDaxDialog() {
        privacyIconAndTrackersAnimator.completeAnimationForDaxDialog(in: omniBarView)
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

    /// When a setting that affects the accessory button is modified, `refreshState` is called.
    /// This requires updating the padding to ensure consistent layout.
    private func updatePadding() {
        omniBarView.omniBarLeadingConstraint.constant = (state.hasLargeWidth ? 24 : 8)
        omniBarView.omniBarTrailingConstraint.constant = (state.hasLargeWidth ? 24 : trailingConstraintValueForSmallWidth)
    }

    // Support static custom icons, for things like internal pages, for example
    private func showCustomIcon(icon: OmniBarIcon) {
        omniBarView.privacyInfoContainer.privacyIcon.isHidden = true
        omniBarView.customIconView.image = UIImage(named: icon.rawValue)
        omniBarView.privacyInfoContainer.addSubview(omniBarView.customIconView)
        omniBarView.customIconView.isHidden = false
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

        omniBarView.searchFieldContainer.adjustTextFieldOffset(for: state)

        updateLeftIconContainerState(oldState: oldState, newState: state)

        setVisibility(omniBarView.privacyInfoContainer, hidden: !state.showPrivacyIcon)
        setVisibility(omniBarView.clearButton, hidden: !state.showClear)
        setVisibility(omniBarView.menuButton, hidden: !state.showMenu)
        setVisibility(omniBarView.settingsButton, hidden: !state.showSettings)
        setVisibility(omniBarView.cancelButton, hidden: !state.showCancel)
        setVisibility(omniBarView.refreshButton, hidden: !state.showRefresh)
        setVisibility(omniBarView.voiceSearchButton, hidden: !state.showVoiceSearch)
        setVisibility(omniBarView.abortButton, hidden: !state.showAbort)

        setVisibility(omniBarView.backButton, hidden: !state.showBackButton)
        setVisibility(omniBarView.forwardButton, hidden: !state.showForwardButton)
        setVisibility(omniBarView.bookmarksButton, hidden: !state.showBookmarksButton)
        setVisibility(omniBarView.accessoryButton, hidden: !state.showAccessoryButton)

        omniBarView.searchContainerCenterConstraint.isActive = state.hasLargeWidth
        omniBarView.searchContainerMaxWidthConstraint.isActive = state.hasLargeWidth
        omniBarView.leftButtonsSpacingConstraint.constant = state.hasLargeWidth ? 24 : 0
        omniBarView.rightButtonsSpacingConstraint.constant = state.hasLargeWidth ? 24 : trailingConstraintValueForSmallWidth

        if state.showVoiceSearch && state.showClear {
            omniBarView.searchStackContainer.setCustomSpacing(13, after: omniBarView.voiceSearchButton)
        }

        if oldState.showAccessoryButton != state.showAccessoryButton ||
            oldState.hasLargeWidth != state.hasLargeWidth {
            updatePadding()
        }

        UIView.animate(withDuration: 0.0) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }

    /*
     Superfluous check to overcome apple bug in stack view where setting value more than
     once causes issues, related to http://www.openradar.me/22819594
     Kill this method when radar is fixed - burn it with fire ;-)
     */
    private func setVisibility(_ view: UIView, hidden: Bool) {
        if view.isHidden != hidden {
            view.isHidden = hidden
        }
    }

    private func onQuerySubmitted() {
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
            animateTransition(from: omniBarView.searchLoupe, to: omniBarView.dismissButton)
        } else if oldState.showDismiss && newState.showSearchLoupe {
            animateTransition(from: omniBarView.dismissButton, to: omniBarView.searchLoupe)
        } else if dismissButtonAnimator == nil || dismissButtonAnimator?.isRunning == false {
            updateLeftContainerVisibility(state: newState)
        }

        if !state.showDismiss && !newState.showSearchLoupe {
            omniBarView.leftIconContainerView.isHidden = true
        } else {
            omniBarView.leftIconContainerView.isHidden = false
        }
    }

    private func animateTransition(from oldView: UIView, to newView: UIView) {
        dismissButtonAnimator?.stopAnimation(true)
        let animationOffset: CGFloat = 20
        let animationDuration: CGFloat = 0.7
        let animationDampingRatio: CGFloat = 0.6

        newView.alpha = 0
        newView.transform = CGAffineTransform(translationX: -animationOffset, y: 0)
        newView.isHidden = false
        oldView.isHidden = false

        let targetAlpha: CGFloat = (newView == omniBarView.searchLoupe) ? 0.5 : 1.0

        dismissButtonAnimator = UIViewPropertyAnimator(duration: animationDuration, dampingRatio: animationDampingRatio) {
            oldView.alpha = 0
            oldView.transform = CGAffineTransform(translationX: -animationOffset, y: 0)
            newView.alpha = targetAlpha
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
        setVisibility(omniBarView.searchLoupe, hidden: !state.showSearchLoupe)
        setVisibility(omniBarView.dismissButton, hidden: !state.showDismiss)
        omniBarView.dismissButton.alpha = state.showDismiss ? 1 : 0
        omniBarView.searchLoupe.alpha = state.showSearchLoupe ? 0.5 : 0
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
        let isPrivacyIconHighlighted = privacyIconContextualOnboardingAnimator.isPrivacyIconHighlighted(omniBarView.privacyInfoContainer.privacyIcon)
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
        omniDelegate?.onAccessoryPressed(accessoryType: omniBarView.accessoryType)
    }

    private func onDismissPressed() {
        omniDelegate?.onCancelPressed()
        refreshState(state.onEditingStoppedState)
    }

    private func onSettingsLongPress() {
        omniDelegate?.onSettingsLongPressed()
    }

    private func onAccessoryLongPress() {
        omniDelegate?.onAccessoryLongPressed(accessoryType: omniBarView.accessoryType)
    }
}

extension DefaultOmniBarViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        self.refreshState(self.state.onEditingStartedState)
        return true
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        omniDelegate?.onTextFieldWillBeginEditing(omniBarView, tapped: textFieldTapped)
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.async {
            let highlightText = self.omniDelegate?.onTextFieldDidBeginEditing(self.omniBarView) ?? true
            self.refreshState(self.state.onEditingStartedState)

            if highlightText {
                self.textField.selectAll(nil)
            }
            self.omniDelegate?.onDidBeginEditing()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        omniDelegate?.onEnterPressed()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        switch omniDelegate?.onEditingEnd() {
        case .dismissed, .none:
            refreshState(state.onEditingStoppedState)
        case .suspended:
            refreshState(state.onEditingSuspendedState)
        }
        self.omniDelegate?.onDidEndEditing()
    }
}

extension DefaultOmniBarViewController {
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
