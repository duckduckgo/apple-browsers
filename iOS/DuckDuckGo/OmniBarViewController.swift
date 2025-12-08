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
import Kingfisher
import DesignResourcesKitIcons

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

    internal var textFieldTapped = true
    internal var textEntryMode: TextEntryMode = .search

    // MARK: - Animation

    var isUsingUnifiedPredictor: Bool {
        dependencies.featureFlagger.isFeatureOn(.unifiedURLPredictor)
    }
    var dismissButtonAnimator: UIViewPropertyAnimator?
    private var notificationAnimator = OmniBarNotificationAnimator()
    private let privacyIconContextualOnboardingAnimator = PrivacyIconContextualOnboardingAnimator()

    // Animation timing constants
    private enum AnimationTiming {
        static let pageLoadNotificationDelay: TimeInterval = 0    // Delay after page load before processing notifications
        static let highPriorityDelay: TimeInterval = 0.0          // Delay for high-priority notifications (trackers)
        static let lowPriorityDelay: TimeInterval = 1.2           // Delay for low-priority notifications (cookies)
        static let betweenAnimationsDelay: TimeInterval = 0.5     // Delay between consecutive animations
    }

    // Animation queue state
    private enum AnimationState {
        case idle, animating
    }

    private enum AnimationPriority: Int {
        case high = 0  // Higher priority (sorted first)
        case low = 1   // Lower priority (sorted last)

        var delay: TimeInterval {
            switch self {
            case .high: return AnimationTiming.highPriorityDelay
            case .low: return AnimationTiming.lowPriorityDelay
            }
        }
    }

    private struct QueuedAnimation {
        let priority: AnimationPriority
        let block: () -> Void
    }

    // Thread-safe animation state (all access must be on main actor)
    @MainActor
    private var animationState: AnimationState = .idle
    @MainActor
    private var animationQueue: [QueuedAnimation] = []
    @MainActor
    private var isPageLoading: Bool = false
    @MainActor
    private var pendingNotifications: [(priority: AnimationPriority, block: () -> Void)] = []

    // Work item for cancellable delayed notification processing
    private var pendingNotificationWorkItem: DispatchWorkItem?

    // MARK: - Constraints

    private var trailingConstraintValueForSmallWidth: CGFloat {
        if state.showAIChatButton || state.showSettings {
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
        barView.aiChatButton.isPointerInteractionEnabled = true
        barView.menuButton.isPointerInteractionEnabled = true
        barView.refreshButton.isPointerInteractionEnabled = true
        barView.customizableButton.isPointerInteractionEnabled = true
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
        barView.onCustomizableButtonPressed = { [weak self] in
            self?.onCustomizableButtonPressed()
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
        barView.onAIChatPressed = { [weak self] in
            self?.onAIChatPressed()
        }
        barView.onDismissPressed = { [weak self] in
            self?.onDismissPressed()
        }
        barView.onAIChatLeftButtonPressed = { [weak self] in
            self?.onAIChatLeftButtonPressed()
        }
        barView.onAIChatBrandingPressed = { [weak self] in
            self?.onAIChatBrandingPressed()
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

    func startBrowsing() {
        refreshState(state.onBrowsingStartedState)
    }

    func stopBrowsing() {
        refreshState(state.onBrowsingStoppedState)
    }

    func startLoading() {
        // Cancel any pending animations when page starts loading
        cancelAllAnimations()

        // Cancel any pending notification processing work item to prevent timer leak
        // This is critical when navigating rapidly between pages
        pendingNotificationWorkItem?.cancel()
        pendingNotificationWorkItem = nil

        isPageLoading = true
        pendingNotifications.removeAll()
        refreshState(state.withLoading())
    }

    func stopLoading() {
        refreshState(state.withoutLoading())

        // Cancel any existing pending work before scheduling new one
        pendingNotificationWorkItem?.cancel()

        // Wait briefly after page load completes before processing notifications
        // This allows tracker and cookie notifications to arrive before animation starts
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isPageLoading = false
            self.processPendingNotifications()
        }

        pendingNotificationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationTiming.pageLoadNotificationDelay, execute: workItem)
    }

    func cancel() {
        refreshState(state.onEditingStoppedState)
    }

    func updateQuery(_ query: String?) {
        text = query
        textDidChange()
    }
    
    func beginEditing(animated: Bool, forTextEntryMode textEntryMode: TextEntryMode) {
        textFieldTapped = false
        self.textEntryMode = textEntryMode
        defer {
            textFieldTapped = true
            self.textEntryMode = .search
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

    func showOrScheduleCookiesManagedNotification(isCosmetic: Bool) {
        let type: OmniBarNotificationType = isCosmetic ? .cookiePopupHidden : .cookiePopupManaged

        enqueueAnimationIfNeeded(priority: .low) { [weak self] in
            guard let self else { return }
            self.notificationAnimator.showNotification(type, in: barView, viewController: self) { [weak self] in
                self?.completeCurrentAnimation()
            }
        }
    }

    func showOrScheduleOnboardingPrivacyIconAnimation() {
        enqueueAnimationIfNeeded { [weak self] in
            guard let self else { return }
            self.privacyIconContextualOnboardingAnimator.showPrivacyIconAnimation(in: barView)
            // Onboarding animation completes immediately
            self.completeCurrentAnimation()
        }
    }

    func dismissOnboardingPrivacyIconAnimation() {
        privacyIconContextualOnboardingAnimator.dismissPrivacyIconAnimation(barView.privacyInfoContainer.privacyIcon)
    }

    func startTrackersAnimation(_ privacyInfo: PrivacyInfo, forDaxDialog: Bool) {
        guard state.allowsTrackersAnimation else { return }

        let trackerCount = privacyInfo.trackerInfo.trackersBlocked.count
        let privacyIcon = PrivacyIconLogic.privacyIcon(for: privacyInfo)

        // Don't show notification on SERP pages (DuckDuckGo search)
        guard !privacyInfo.url.isDuckDuckGoSearch else {
            barView.privacyInfoContainer.privacyIcon.updateIcon(privacyIcon)
            return
        }

        // Show tracker count notification and animation if any trackers were blocked
        if trackerCount > 0 {
            enqueueAnimationIfNeeded(priority: .high) { [weak self] in
                guard let self else { return }

                // Show notification, then play privacy icon animation
                self.notificationAnimator.showNotification(.trackersBlocked(count: trackerCount), in: barView, viewController: self) { [weak self] in
                    guard let self else { return }

                    // After notification completes, animate the privacy icon
                    self.barView.privacyInfoContainer.privacyIcon.prepareForAnimation(for: privacyIcon)
                    let shieldAnimation = self.barView.privacyInfoContainer.privacyIcon.shieldAnimationView(for: privacyIcon)

                    // Play from start to just before the end to avoid any end-frame blink
                    if let animation = shieldAnimation?.animation {
                        let endFrame = animation.endFrame - 2  // Stop 2 frames before the end
                        shieldAnimation?.play(fromFrame: animation.startFrame, toFrame: endFrame, loopMode: .playOnce) { [weak self] completed in
                            guard let self, completed else { return }

                            // Update to final icon state after animation completes
                            self.barView.privacyInfoContainer.privacyIcon.updateIcon(privacyIcon)

                            // Animation complete, process next in queue
                            self.completeCurrentAnimation()
                        }
                    } else {
                        // Fallback if animation not loaded
                        self.barView.privacyInfoContainer.privacyIcon.updateIcon(privacyIcon)
                        self.completeCurrentAnimation()
                    }
                }
            }
        } else {
            // No trackers blocked, just update icon without animation
            barView.privacyInfoContainer.privacyIcon.updateIcon(privacyIcon)
        }
    }

    func updatePrivacyIcon(for privacyInfo: PrivacyInfo?) {
        guard let privacyInfo = privacyInfo,
              !barView.privacyInfoContainer.isAnimationPlaying
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
    
    func setDaxEasterEggLogoURL(_ logoURL: String?) {
        let url = logoURL.flatMap { URL(string: $0) }
        
        barView.privacyInfoContainer.privacyIcon.setDaxEasterEggLogoURL(url) {
            DailyPixel.fireDailyAndCount(pixel: .daxEasterEggLogoDisplayed)
        }
        
        // Set up delegate if not already done
        if barView.privacyInfoContainer.delegate == nil {
            barView.privacyInfoContainer.delegate = self
        }
    }

    func completeAnimationForDaxDialog() {
        // When Dax Dialog appears, cancel any running animations and clear the queue
        cancelAllAnimations()
    }

    func refreshCustomizableButton() {
        applyCustomization()
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
        // Cancel pending notification work item to prevent delayed processing
        pendingNotificationWorkItem?.cancel()
        pendingNotificationWorkItem = nil

        // Clear pending notifications
        pendingNotifications.removeAll()

        // Cancel running animations
        notificationAnimator.cancelAnimations(in: barView)
        privacyIconContextualOnboardingAnimator.dismissPrivacyIconAnimation(barView.privacyInfoContainer.privacyIcon)

        // Clear animation queue
        animationState = .idle
        animationQueue.removeAll()
    }

    // MARK: - Private/animation

    private func enqueueAnimationIfNeeded(priority: AnimationPriority = .high, _ block: @escaping () -> Void) {
        // If page is still loading, store notification to be processed after page completes
        if isPageLoading {
            pendingNotifications.append((priority: priority, block: block))
            return
        }

        // Apply delay BEFORE enqueueing based on priority
        // This ensures high-priority items (0.3s) enter queue before low-priority items (1.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + priority.delay) { [weak self] in
            guard let self else { return }

            // CRITICAL: Check animation state after delay to prevent race condition
            // Multiple delayed blocks can fire simultaneously, but only the first should
            // trigger processNextAnimation() if we're idle
            let shouldProcessImmediately = self.animationState == .idle && self.animationQueue.isEmpty

            let queuedAnimation = QueuedAnimation(priority: priority, block: block)
            self.animationQueue.append(queuedAnimation)

            // Sort queue by priority (high priority first)
            self.animationQueue.sort { $0.priority.rawValue < $1.priority.rawValue }

            // Only process if we were idle before adding this item
            if shouldProcessImmediately {
                self.processNextAnimation()
            }
        }
    }

    private func processPendingNotifications() {
        guard !pendingNotifications.isEmpty else { return }

        // Sort by priority (high priority first)
        let sortedNotifications = pendingNotifications.sorted { $0.priority.rawValue < $1.priority.rawValue }
        pendingNotifications.removeAll()

        // Add all notifications directly to queue without priority delays
        // since we've already sorted them by priority
        for notification in sortedNotifications {
            let queuedAnimation = QueuedAnimation(priority: notification.priority, block: notification.block)
            animationQueue.append(queuedAnimation)
        }

        // Re-sort entire queue to maintain priority guarantee
        // This ensures newly added notifications are properly ordered with existing items
        animationQueue.sort { $0.priority.rawValue < $1.priority.rawValue }

        // Start processing if we're idle
        if animationState == .idle {
            processNextAnimation()
        }
    }

    private func processNextAnimation() {
        guard animationState == .idle, !animationQueue.isEmpty else { return }

        animationState = .animating
        let nextQueuedAnimation = animationQueue.removeFirst()

        // Execute immediately - delay was already applied before adding to queue
        nextQueuedAnimation.block()
    }

    private func completeCurrentAnimation() {
        animationState = .idle

        // Wait before processing next animation to ensure smooth transitions
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationTiming.betweenAnimationsDelay) { [weak self] in
            self?.processNextAnimation()
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
        barView.isCustomizableButtonHidden = !state.showCustomizableButton
        barView.isVoiceSearchButtonHidden = !state.showVoiceSearch
        barView.isAbortButtonHidden = !state.showAbort
        barView.isBackButtonHidden = !state.showBackButton
        barView.isForwardButtonHidden = !state.showForwardButton
        barView.isBookmarksButtonHidden = !state.showBookmarksButton
        barView.isAIChatButtonHidden = !state.showAIChatButton

        applyCustomization()

        let shouldShowAIChat = state.showAIChatFullModeBranding
        barView.isFullAIChatHidden = !shouldShowAIChat
    }

    private func applyCustomization() {
        // Some states (e.g. `AIChatModeState`) do not support customization, i.e we should not show the customizable button
        guard state.allowCustomization else { return }
        
        let state = dependencies.mobileCustomization.state
        guard state.isEnabled else {
            barView.customizableButton.setImage(DesignSystemImages.Glyphs.Size24.shareApple, for: .normal)
            barView.isCustomizableButtonHidden = !self.state.showCustomizableButton
            return
        }

        let largeIcon = dependencies.mobileCustomization.largeIconForButton(state.currentAddressBarButton)
        barView.customizableButton.setImage(largeIcon, for: .normal)

        if self.state.showCustomizableButton {
            barView.isCustomizableButtonHidden = largeIcon == nil
        } else {
            barView.isCustomizableButtonHidden = true
        }
    }

    func onQuerySubmitted() {
        if let suggestion = omniDelegate?.selectedSuggestion() {
            omniDelegate?.onOmniSuggestionSelected(suggestion)
        } else {
            guard let query = textField.text?.trimmingWhitespace(), !query.isEmpty else {
                return
            }
            resignFirstResponder()

            DailyPixel.fireDailyAndCount(pixel: .aiChatLegacyOmnibarQuerySubmitted)
            
            if let url = URL(trimmedAddressBarString: query, useUnifiedLogic: isUsingUnifiedPredictor), url.isValid(usingUnifiedLogic: isUsingUnifiedPredictor) {
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
        omniDelegate?.onClearTextPressed()
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

    private func onCustomizableButtonPressed() {
        omniDelegate?.onCustomizableButtonPressed()
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

    private func onAIChatPressed() {
        omniDelegate?.onAIChatPressed()
    }

    private func onDismissPressed() {
        Pixel.fire(pixel: .aiChatLegacyOmnibarBackButtonPressed)
        omniDelegate?.onCancelPressed()
        refreshState(state.onEditingStoppedState)
    }

    private func onAIChatLeftButtonPressed() {
        omniDelegate?.onAIChatLeftButtonPressed()
    }

    private func onAIChatBrandingPressed() {
        omniDelegate?.onAIChatBrandingPressed()
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
        DailyPixel.fireDailyAndCount(pixel: .aiChatLegacyOmnibarShown)
        
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
    
    /// Get the current frame of the logo, accounting for device rotation and scale transforms
    func getCurrentLogoFrame() -> CGRect? {
        // Dax logo easter eggs no longer supported
        return nil
    }
}

extension OmniBarViewController {

    /// Enters AI Chat full mode, showing AI Chat-specific UI in the omnibar
    func enterAIChatMode() {
        refreshState(state.onEnterAIChatState)
    }
}

// MARK: - Theming

extension OmniBarViewController {

    private func decorate() {
        if let url = textField.text.flatMap({ URL(trimmedAddressBarString: $0.trimmingWhitespace(), useUnifiedLogic: isUsingUnifiedPredictor) }) {
            textField.attributedText = AddressDisplayHelper.addressForDisplay(url: url, showsFullURL: textField.isEditing)
        }
    }
}

// MARK: - PrivacyInfoContainerViewDelegate

extension OmniBarViewController: PrivacyInfoContainerViewDelegate {
    func privacyInfoContainerViewDidTapDaxLogo(_ view: PrivacyInfoContainerView, logoURL: URL?, currentImage: UIImage?, sourceFrame: CGRect) {
        DailyPixel.fireDailyAndCount(pixel: .daxEasterEggLogoTapped)
        
        dependencies.daxEasterEggPresenter.presentFullScreen(
            from: self,
            logoURL: logoURL,
            currentImage: currentImage,
            sourceFrame: sourceFrame,
            sourceViewController: self
        )
    }
}
