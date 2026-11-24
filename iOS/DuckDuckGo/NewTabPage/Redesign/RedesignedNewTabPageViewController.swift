//
//  RedesignedNewTabPageViewController.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AIChat
import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// A New Tab Page built as a vertical stack of independent blocks.
final class RedesignedNewTabPageViewController: UIViewController, NewTabPage, RemoteMessagePresenting {

    private enum Metrics {
        static let customizeButtonTopMargin: CGFloat = 10
        static let customizeButtonTrailingMargin: CGFloat = 20
        static let customizeButtonSize: CGFloat = 44
        static let portraitContentTopInset: CGFloat = 96
        static let stickySearchInputTopMargin: CGFloat = 8
        static let entranceTranslation: CGFloat = 12
        static let entranceDuration: TimeInterval = 0.25
        static let focusedModulesHideDuration: TimeInterval = 0.1
        static let focusedWelcomeScale: CGFloat = 0.85
    }

    private static let focusedModuleIDs: [NewTabPageBlockID] = [.favorites, .escapeHatch, .messages]

    weak var delegate: NewTabPageControllerDelegate?
    weak var chromeDelegate: BrowserChromeDelegate?

    var isDragging: Bool { scrollView.isDragging }

    var hasInlineSearchInput: Bool { true }

    var inlineToggleMode: TextEntryMode? {
        guard let searchInputModel, searchInputModel.settings.isModeToggleShown else { return nil }
        return searchInputModel.textEntryMode
    }

    private let onboardingCoordinator: NewTabPageOnboardingCoordinator?
    var isPresentingOnboardingDialog: Bool { onboardingCoordinator?.isPresentingDialog == true }

    private let blocks: [any NewTabPageBlock]
    private let favoritesModel: FavoritesViewModel?
    private let pageModel: NewTabPageViewModel?
    private let messagesModel: NewTabPageMessagesModel?
    private let searchInputModel: NewTabPageSearchInputModel?
    private let isStickyInputEnabled: Bool
    private let returnSettings: NewTabPageReturnSettings
    private let customizationStateReporter = NewTabPageCustomizationStateReporter()
    private var isRemoteMessageSurfacePresented = false
    private var areFavoritesHidden = false
    private var isEntranceAnimationPending = false
    private var entranceAnimator: UIViewPropertyAnimator?
    private var detachedContentOffset: CGPoint?
    private var inputEditingLayout: InputEditingLayout?
    private(set) var focusedPose: NewTabPageFocusedPose?
    private var isFocusedPoseSettled = false
    private var focusedKeyboardObserver: NSObjectProtocol?
    private var areFocusedModulesHidden = false
    private var appliedAccessibilityReach = RedesignedNewTabPageAccessibilityReach.wholePage
    var onFocusedModeSwitchSwipe: ((TextEntryMode) -> Void)?
    private lazy var focusedModeSwitchSwipeController = ModeSwitchSwipeGestureController { [weak self] mode in
        self?.onFocusedModeSwitchSwipe?(mode)
    }
    private var stickySearchInputTranslation: CGFloat = 0
    private var focusedScrollInsetBottom: CGFloat = 0

    private struct InputEditingLayout {
        let contentOffset: CGPoint
        let inputFrameInWindow: CGRect?
        let windowBounds: CGRect?
        let bottomSafeAreaInset: CGFloat
        /// How far the input sat from its place in the page layout when focus began, because the page was scrolled.
        let scrolledInputDistance: CGFloat
        /// The sticky pinning translation applied to the input when focus began.
        let stickySearchInputTranslation: CGFloat
        var isGeometryValid = true
        /// Whether the focused pose has started leaving, after which the page keeps the offset the user scrolled to.
        var isLeavingFocus = false
    }

    private let backgroundImageView = UIImageView()
    private var themeCancellable: AnyCancellable?

    private let contentContainerView: UIView = {
        let view = UIView()
        // Clip scrolling content at the page bounds, rather than at the horizontal safe-area edges.
        view.clipsToBounds = true
        return view
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        // Keep content inside the safe area while allowing its shadows to extend beyond it.
        scrollView.clipsToBounds = false
        return scrollView
    }()

    private let blocksStackView: TransformedBlocksStackView = {
        let stackView = TransformedBlocksStackView()
        stackView.axis = .vertical
        return stackView
    }()

    private lazy var contentTopConstraint = blocksStackView.topAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.topAnchor,
        constant: Metrics.portraitContentTopInset)

    private lazy var customizeButton: CircularButton = {
        let button = CircularButton()
        button.isShadowHidden = true
        button.setImage(DesignSystemImages.Glyphs.Size24.options, for: .normal)
        button.setColors(foreground: UIColor(designSystemColor: .iconsSecondary),
                         background: .clear,
                         pressedForeground: UIColor(designSystemColor: .iconsSecondary),
                         pressedBackground: UIColor(designSystemColor: .controlsFillTertiary))
        button.accessibilityLabel = UserText.newTabPageCustomizationTitle
        button.addTarget(self, action: #selector(customizeButtonTapped), for: .touchUpInside)
        return button
    }()

    init(blocks: [any NewTabPageBlock],
         favoritesModel: FavoritesViewModel? = nil,
         pageModel: NewTabPageViewModel? = nil,
         messagesModel: NewTabPageMessagesModel? = nil,
         searchInputModel: NewTabPageSearchInputModel? = nil,
         isStickyInputEnabled: Bool = false,
         returnSettings: NewTabPageReturnSettings,
         onboardingCoordinator: NewTabPageOnboardingCoordinator? = nil) {
        self.onboardingCoordinator = onboardingCoordinator
        self.blocks = blocks
        self.favoritesModel = favoritesModel
        self.pageModel = pageModel
        self.messagesModel = messagesModel
        self.searchInputModel = searchInputModel
        self.isStickyInputEnabled = isStickyInputEnabled
        self.returnSettings = returnSettings
        super.init(nibName: nil, bundle: nil)
        onboardingCoordinator?.page = self
        messagesModel?.onMessageVisibilityChanged = { [weak self] in
            self?.notifyRemoteMessageSurfaceChanged()
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(designSystemColor: .background)
        view.clipsToBounds = true
        addSubviews()
        installBlocks()
        focusedModeSwitchSwipeController.install(on: view)
        focusedModeSwitchSwipeController.isEnabled = false
        scrollView.delegate = self
        blocksStackView.onLayout = { [weak self] in
            self?.updateStickySearchInput()
        }
        if isStickyInputEnabled {
            // The bottom safe area is applied by hand, so it cannot change under the scroll view while the input is focused.
            scrollView.contentInsetAdjustmentBehavior = .never
            applyScrollInsets()
        }
        observeTheme()
        // Load once per page, after the caller has supplied the initial escape-hatch context.
        messagesModel?.load()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // Keyboard resizing must not be mistaken for rotation. Use the window's orientation,
        // and stop preserving geometry captured before a rotation or window resize.
        let layoutSize = view.window?.bounds.size ?? view.bounds.size
        let isLandscape = layoutSize.width > layoutSize.height
        contentTopConstraint.constant = isLandscape ? Metrics.customizeButtonTopMargin : Metrics.portraitContentTopInset
        if let savedLayout = inputEditingLayout, savedLayout.windowBounds != view.window?.bounds {
            inputEditingLayout?.isGeometryValid = false
        }

        // The square artwork fills the page without stretching, with its pond anchored to the bottom.
        let backgroundSize = max(view.bounds.width, view.bounds.height)
        backgroundImageView.frame = CGRect(x: (view.bounds.width - backgroundSize) / 2,
                                           y: view.bounds.height - backgroundSize,
                                           width: backgroundSize,
                                           height: backgroundSize)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onboardingCoordinator?.refreshContextualOnboardingDialogLayout()
        applyScrollInsets()
        // Reattachment and keyboard transitions temporarily change the viewport and safe area.
        // Keep those layouts from changing the loaded page's resting scroll position.
        if let preservedOffset = pinnedEditingContentOffset ?? detachedContentOffset,
           scrollView.contentOffset != preservedOffset {
            scrollView.setContentOffset(preservedOffset, animated: false)
        }
        updateStickySearchInput()
    }

    @objc private func customizeButtonTapped() {
        let model = NewTabPageCustomizationModel(returnSettings: returnSettings)
        model.reportOpening()
        let customizationViewController = NewTabPageCustomizationViewController(model: model)
        customizationViewController.onAllSettingsSelected = { [weak self] in
            guard let self else { return }
            delegate?.newTabPageDidRequestSettings(self)
        }

        present(customizationViewController, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        customizationStateReporter.fireDailyState()
        finishRestoringScrollPosition()
        if presentedViewController?.isBeingDismissed ?? true {
            onboardingCoordinator?.pageDidAppear()
        }
        isRemoteMessageSurfacePresented = true
        notifyRemoteMessageSurfaceChanged()

        // MainViewController pre-hides the chat-path handoff before its queued completion request.
        // The coordinator restores alpha after hiding the modules and preparing the dialog.
        if onboardingCoordinator?.isAwaitingChatPathCompletion != true {
            view.alpha = 1
        }
        guard isEntranceAnimationPending else { return }
        isEntranceAnimationPending = false
        let animator = UIViewPropertyAnimator(duration: Metrics.entranceDuration, curve: .easeOut) { [weak self] in
            self?.restoreEntrancePose()
        }
        entranceAnimator = animator
        animator.startAnimation()
    }

    private func finishRestoringScrollPosition() {
        guard let savedOffset = detachedContentOffset else { return }
        detachedContentOffset = nil
        restoreScrollPosition(savedOffset)
    }

    private func restoreScrollPosition(_ savedOffset: CGPoint) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        // Favorites or messages may have been removed while the page was detached or the input was focused.
        // Clamp once the resting viewport and content size are available.
        scrollView.setContentOffset(clampedContentOffset(savedOffset), animated: false)
    }

    /// The offset moved into the scrollable range.
    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(minimumY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        return CGPoint(x: offset.x, y: min(max(offset.y, minimumY), maximumY))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isRemoteMessageSurfacePresented = false
        onboardingCoordinator?.pageWillDisappear()
        notifyRemoteMessageSurfaceChanged()
        finishEntranceAnimation()
    }

    func hasVisibleRemoteMessage(withID messageID: String) -> Bool {
        isRemoteMessageSurfacePresented && !isPresentingOnboardingDialog && focusedPose?.showsModules != false
            && messagesModel?.hasAppearedRemoteMessage(withID: messageID) == true
    }

    private func notifyRemoteMessageSurfaceChanged() {
        NotificationCenter.default.post(name: RemoteMessageImpressionReporter.remoteMessageSurfaceDidChange, object: self)
    }

    func prepareForEntranceAnimation(if shouldAnimate: Bool) {
        guard shouldAnimate, !UIAccessibility.isReduceMotionEnabled else { return }
        loadViewIfNeeded()
        isEntranceAnimationPending = true
        contentContainerView.alpha = 0
        contentContainerView.transform = CGAffineTransform(translationX: 0, y: Metrics.entranceTranslation)
    }

    private func restoreEntrancePose() {
        contentContainerView.alpha = 1
        contentContainerView.transform = .identity
    }

    private func finishEntranceAnimation() {
        guard isEntranceAnimationPending || entranceAnimator != nil else { return }
        isEntranceAnimationPending = false
        entranceAnimator?.stopAnimation(true)
        entranceAnimator = nil
        restoreEntrancePose()
    }

    private func observeTheme() {
        let store = NewTabPageCustomizationStore()
        applyBackground(of: store.theme)
        themeCancellable = store.themePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in
                self?.applyBackground(of: theme)
            }
    }

    private func applyBackground(of theme: NewTabPageTheme) {
        backgroundImageView.image = theme.backgroundImage
        backgroundImageView.isHidden = theme.backgroundImage == nil
    }

    private func addSubviews() {
        view.addSubview(backgroundImageView)
        view.addSubview(contentContainerView)
        contentContainerView.addSubview(scrollView)
        scrollView.addSubview(blocksStackView)
        let customizeButtonHost: UIView = isStickyInputEnabled ? scrollView : contentContainerView
        let customizeButtonTopAnchor = isStickyInputEnabled
            ? scrollView.contentLayoutGuide.topAnchor
            : contentContainerView.safeAreaLayoutGuide.topAnchor
        let customizeButtonTrailingAnchor = isStickyInputEnabled
            ? scrollView.frameLayoutGuide.trailingAnchor
            : contentContainerView.safeAreaLayoutGuide.trailingAnchor
        customizeButtonHost.addSubview(customizeButton)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        blocksStackView.translatesAutoresizingMaskIntoConstraints = false
        customizeButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: contentContainerView.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentContainerView.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainerView.safeAreaLayoutGuide.trailingAnchor),

            contentTopConstraint,
            blocksStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            blocksStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            blocksStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),

            // Pinning the content width to the visible width leaves block heights as the only
            // thing that can make the page scroll.
            blocksStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            customizeButton.topAnchor.constraint(equalTo: customizeButtonTopAnchor,
                                                 constant: Metrics.customizeButtonTopMargin),
            customizeButton.trailingAnchor.constraint(equalTo: customizeButtonTrailingAnchor,
                                                      constant: -Metrics.customizeButtonTrailingMargin),
            customizeButton.widthAnchor.constraint(equalToConstant: Metrics.customizeButtonSize),
            customizeButton.heightAnchor.constraint(equalToConstant: Metrics.customizeButtonSize)
        ])
    }

    private func installBlocks() {
        for block in blocks {
            let blockController = block.viewController

            addChild(blockController)
            blocksStackView.addArrangedSubview(blockController.view)
            blockController.didMove(toParent: self)
        }
        if isStickyInputEnabled, let searchInputView {
            blocksStackView.bringSubviewToFront(searchInputView)
        }
    }

    /// Keeps the search input just below the top of the visible page once scrolling would carry it offscreen, including while it is focused.
    private func updateStickySearchInput() {
        guard isStickyInputEnabled, let searchInputView else { return }
        // Center and bounds ignore the pinning transform, so they give the resting position.
        let pinning = StickyInputPinning(restingMinY: searchInputView.center.y - searchInputView.bounds.height / 2,
                                         height: searchInputView.bounds.height,
                                         containerHeight: blocksStackView.bounds.height)
        let visibleTopInStack = blocksStackView.convert(CGPoint(x: 0, y: scrollView.bounds.minY + scrollView.adjustedContentInset.top - scrollView.contentInset.top),
                                                        from: scrollView).y
        stickySearchInputTranslation = pinning.translation(pinnedMinY: visibleTopInStack + Metrics.stickySearchInputTopMargin)
        applySearchInputTransform()
    }

    /// Combines the sticky pinning with the focused pose's offset, which is measured from the pinned position.
    private func applySearchInputTransform() {
        let focusedOffset = focusedPose?.inputOffset ?? 0
        searchInputView?.transform = CGAffineTransform(translationX: 0, y: stickySearchInputTranslation + focusedOffset)
    }

    func refreshSearchInputSettings() {
        searchInputModel?.refreshSettings()
    }

    func beginSearch(textEntryMode: TextEntryMode) {
        delegate?.newTabPageDidRequestSearch(self, textEntryMode: textEntryMode)
    }

    func beginVoiceSearch(textEntryMode: TextEntryMode) {
        delegate?.newTabPageDidRequestVoiceSearch(self, textEntryMode: textEntryMode)
    }

    func duckAIMenu() -> UIMenu? {
        delegate?.newTabPageDuckAIMenu(self)
    }

    func dismiss() {
        unsettleFocusedPose()
        detachedContentOffset = scrollView.contentOffset
        onboardingCoordinator?.detach()
        delegate = nil
        chromeDelegate = nil

        removeFromParent()
        view.removeFromSuperview()
    }

    /// No content on this page is sized from the page width.
    func widthChanged() {}
}

extension RedesignedNewTabPageViewController: HomeScreenTransitionSource {

    var snapshotView: UIView { view }

    var rootContainerView: UIView { view }
}

/// The welcome block and favorites participate in the content handoff.
extension RedesignedNewTabPageViewController: NewTabPageContentHandoff {

    var isShowingLogo: Bool { false }

    var isShowingFavorites: Bool { restingContentIsFavorites && !areFavoritesHidden && !isPresentingOnboardingDialog }

    var restingContentIsLogo: Bool { false }

    var restingContentIsFavorites: Bool {
        NewTabPageCustomizationStore().isFavoritesSectionVisible && favoritesModel?.isEmpty == false
    }

    func setLogoHidden(_ hidden: Bool) {
        blocks.first { $0.id == .welcome }?.viewController.view.alpha = hidden ? 0 : 1
    }

    func setFavoritesHidden(_ hidden: Bool) {
        areFavoritesHidden = hidden
        // Preserve the block's space while focused content covers the resting page.
        blocks.first { $0.id == .favorites }?.viewController.view.alpha = hidden ? 0 : 1
    }
}

extension RedesignedNewTabPageViewController: NewTabPageChromeAdapting {

    /// This page draws no framing border.
    func setChromeLayoutContext(isBorderSuppressed: Bool) {}
}

extension RedesignedNewTabPageViewController: NewTabPageEscapeHatchPresenting {

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        pageModel?.escapeHatch = model
        pageModel?.openedAfterIdle = model != nil
        if isViewLoaded {
            messagesModel?.refresh()
        }
    }
}

extension RedesignedNewTabPageViewController: NewTabPageOnboardingHosting {

    var hidesOnboardingContentBeforeInputActivation: Bool { true }

    func setOnboardingContentHidden(_ hidden: Bool, for dialog: NewTabPageOnboardingDialogKind) {
        // Keep the scroll position and block sizes intact beneath the dialog.
        contentContainerView.isHidden = hidden
        applyAccessibilityReach()
        delegate?.newTabPageDidChangeOnboardingPresentation(self)
        notifyRemoteMessageSurfaceChanged()
    }

    func showNextDaxDialog() {
        onboardingCoordinator?.showNextDaxDialog()
    }

    func onboardingCompleted() {
        onboardingCoordinator?.onboardingCompleted()
    }

    func prepareForLinearOnboardingDismissal() {
        onboardingCoordinator?.prepareForLinearOnboardingDismissal()
    }

    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String, textEntryMode: TextEntryMode?) {
        onboardingCoordinator?.showDuckAIOnboardingCompletionWithActiveAddressBar(message: message, textEntryMode: textEntryMode)
    }

    func refreshContextualOnboardingDialogLayout() {
        onboardingCoordinator?.refreshContextualOnboardingDialogLayout()
    }

    func dismissDuckAICompletionDialogIfNeededOnEditingEnd() {
        onboardingCoordinator?.dismissDuckAICompletionDialogIfNeededOnEditingEnd()
    }
}

extension RedesignedNewTabPageViewController: NewTabPageInputTransitionSource {

    var canAnimateSearchInput: Bool { !isPresentingOnboardingDialog }

    var searchInputView: UIView? {
        blocks.first { $0.id == .searchInput }?.viewController.view
    }

    func searchInputTransitionFrame(in targetView: UIView) -> CGRect? {
        searchInputFrame(in: targetView, scrolledBy: 0)
    }

    func focusedPoseSearchInputFrame(in targetView: UIView) -> CGRect? {
        searchInputFrame(in: targetView,
                         scrolledBy: scrollDistanceSinceEditingBegan,
                         pinnedBy: inputEditingLayout?.stickySearchInputTranslation)
    }

    private func searchInputFrame(in targetView: UIView, scrolledBy scrollDistance: CGFloat, pinnedBy pinnedTranslation: CGFloat? = nil) -> CGRect? {
        guard canAnimateSearchInput else { return nil }
        guard let window = view.window else { return nil }
        if let inputEditingLayout, inputEditingLayout.isGeometryValid, inputEditingLayout.windowBounds == window.bounds {
            return inputEditingLayout.inputFrameInWindow.map { targetView.convert($0, from: window) }
        }
        guard let frame = visibleSearchInputFrameInWindow(scrolledBy: scrollDistance, pinnedBy: pinnedTranslation) else { return nil }
        return targetView.convert(frame, from: window)
    }

    private func visibleSearchInputFrameInWindow(scrolledBy scrollDistance: CGFloat = 0, pinnedBy pinnedTranslation: CGFloat? = nil) -> CGRect? {
        guard let window = view.window, let searchInputView else { return nil }
        let frame = searchInputView.untransformedFrame(of: searchInputView.bounds, in: window)
            .offsetBy(dx: 0, dy: scrollDistance + (pinnedTranslation ?? stickySearchInputTranslation))
        let viewport = scrollView.convert(scrollView.bounds, to: window).intersection(window.bounds)
        // An offscreen resting card should not pull the editor beyond the visible page.
        return frame.intersects(viewport) ? frame : nil
    }

    private var scrollDistanceSinceEditingBegan: CGFloat {
        guard let inputEditingLayout else { return 0 }
        return scrollView.contentOffset.y - inputEditingLayout.contentOffset.y
    }

    func setFocusedPose(_ pose: NewTabPageFocusedPose?) {
        inputEditingLayout?.isLeavingFocus = isStickyInputEnabled && pose == nil
        if pose == nil {
            UIView.performWithoutAnimation { unsettleFocusedPose() }
            restorePinnedEditingContentOffset()
        }
        let showedModules = focusedPose?.showsModules
        focusedPose = pose
        favoritesModel?.isFocussedState = pose != nil
        focusedModeSwitchSwipeController.isEnabled = pose?.showsModules == true
        if isFocusedPoseSettled {
            updateFocusedScrollInset(keyboardTop: view.keyboardLayoutGuide.layoutFrame.minY)
        }
        applyFocusedPose()
        applyAccessibilityReach()
        if pose?.showsModules != showedModules {
            notifyRemoteMessageSurfaceChanged()
        }
    }

    func settleFocusedPose() {
        guard focusedPose != nil, !isFocusedPoseSettled else { return }
        isFocusedPoseSettled = true
        updateFocusedScrollInset(keyboardTop: view.keyboardLayoutGuide.layoutFrame.minY)
        focusedKeyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            self.updateFocusedScrollInset(keyboardTop: self.view.convert(frame, from: nil).minY)
        }
        scrollView.keyboardDismissMode = .onDrag
        scrollView.isScrollEnabled = true
    }

    private func unsettleFocusedPose() {
        guard isFocusedPoseSettled else { return }
        isFocusedPoseSettled = false
        focusedKeyboardObserver.map(NotificationCenter.default.removeObserver)
        focusedKeyboardObserver = nil
        focusedScrollInsetBottom = 0
        applyScrollInsets()
        scrollView.keyboardDismissMode = .none
        scrollView.isScrollEnabled = inputEditingLayout == nil
    }

    /// Scrolls back to the offset the page had before editing, inside the caller's animation so the visible rows travel
    /// back with the pose rather than jumping.
    private func restorePinnedEditingContentOffset() {
        guard let pinnedEditingContentOffset, scrollView.contentOffset != pinnedEditingContentOffset else { return }
        scrollView.contentOffset = pinnedEditingContentOffset
    }

    private var pinnedEditingContentOffset: CGPoint? {
        guard !isFocusedPoseSettled, let inputEditingLayout, inputEditingLayout.isGeometryValid, !inputEditingLayout.isLeavingFocus else { return nil }
        return inputEditingLayout.contentOffset
    }

    private func updateFocusedScrollInset(keyboardTop: CGFloat) {
        let keyboardOverlap = max(0, view.bounds.maxY - keyboardTop)
        focusedScrollInsetBottom = keyboardOverlap + (focusedPose?.modulesOffset ?? 0) + (focusedPose?.bottomInputHeight ?? 0)
        applyScrollInsets()
    }

    /// The bottom safe area, such as the floating toolbar's, kept from shrinking below its pre-focus value while the input is focused.
    private var scrollBottomSafeAreaInset: CGFloat {
        guard isStickyInputEnabled else { return 0 }
        if let inputEditingLayout, inputEditingLayout.isGeometryValid {
            // A shrinking inset clamps the scroll offset and makes the page jump, while a growing one must apply.
            return max(inputEditingLayout.bottomSafeAreaInset, view.safeAreaInsets.bottom)
        }
        return view.safeAreaInsets.bottom
    }

    /// While the input is focused the page cannot scroll back past where the modules sit right under the focused card.
    private var editingTopContentInset: CGFloat {
        guard isStickyInputEnabled, let inputEditingLayout, inputEditingLayout.isGeometryValid else { return 0 }
        return -inputEditingLayout.scrolledInputDistance
    }

    private func applyScrollInsets() {
        let bottomInset = focusedScrollInsetBottom + scrollBottomSafeAreaInset
        if scrollView.contentInset.bottom != bottomInset {
            scrollView.contentInset.bottom = bottomInset
        }
        let topInset = editingTopContentInset
        guard scrollView.contentInset.top != topInset else { return }
        // UIKit shifts the offset with the top inset, which would move the page under the user.
        let preservedOffset = scrollView.contentOffset
        scrollView.contentInset.top = topInset
        if scrollView.contentOffset != preservedOffset {
            scrollView.setContentOffset(preservedOffset, animated: false)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applyScrollInsets()
    }

    private var focusedModuleViews: [UIView] {
        blocks.filter { Self.focusedModuleIDs.contains($0.id) }.compactMap { $0.viewController.view }
    }

    func focusedModulesContain(_ point: CGPoint, in targetView: UIView) -> Bool {
        guard focusedPose?.showsModules == true else { return false }
        return focusedModuleViews.contains { $0.convert($0.bounds, to: targetView).contains(point) }
    }

    private func applyFocusedPose() {
        let isFocused = focusedPose != nil
        applySearchInputTransform()
        let greetingTransform = CGAffineTransform(translationX: 0, y: focusedPose?.greetingOffset ?? 0)
        let welcomeView = blocks.first { $0.id == .welcome }?.viewController.view
        welcomeView?.alpha = isFocused ? 0 : 1
        welcomeView?.transform = isFocused
            ? greetingTransform.scaledBy(x: Metrics.focusedWelcomeScale, y: Metrics.focusedWelcomeScale)
            : .identity
        guard focusedPose?.showsModules != false else {
            hideFocusedModules(animated: true)
            return
        }
        let modulesTransform = CGAffineTransform(translationX: 0, y: focusedPose?.modulesOffset ?? 0)
        let moduleViews = focusedModuleViews
        if areFocusedModulesHidden {
            UIView.performWithoutAnimation { moduleViews.forEach { $0.transform = modulesTransform } }
            areFocusedModulesHidden = false
        }
        for moduleView in moduleViews {
            moduleView.alpha = 1
            moduleView.transform = modulesTransform
        }
    }

    private func hideFocusedModules(animated: Bool) {
        areFocusedModulesHidden = true
        let moduleViews = focusedModuleViews
        guard animated else {
            moduleViews.forEach { $0.alpha = 0 }
            return
        }
        UIView.animateOnOwnTiming(duration: Metrics.focusedModulesHideDuration, options: [.beginFromCurrentState, .curveEaseOut]) {
            moduleViews.forEach { $0.alpha = 0 }
        }
    }

    private func applyAccessibilityReach() {
        let reach = RedesignedNewTabPageAccessibilityReach(isEditing: inputEditingLayout != nil,
                                                           isPresentingOnboardingDialog: isPresentingOnboardingDialog,
                                                           focusedPose: focusedPose)
        view.accessibilityElementsHidden = reach == .nothing
        for block in blocks {
            block.viewController.view.accessibilityElementsHidden = reach == .focusedModulesOnly && !Self.focusedModuleIDs.contains(block.id)
        }
        customizeButton.accessibilityElementsHidden = reach == .focusedModulesOnly
        guard reach != appliedAccessibilityReach else { return }
        appliedAccessibilityReach = reach
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    func setSearchInputEditing(_ isEditing: Bool) {
        if isEditing, inputEditingLayout == nil {
            finishEntranceAnimation()
            view.layoutIfNeeded()
            // Focusing mid-bounce must not leave a rubber band release to move the page after the input frame is captured.
            scrollView.setContentOffset(clampedContentOffset(scrollView.contentOffset), animated: false)
            updateStickySearchInput()
            inputEditingLayout = InputEditingLayout(contentOffset: scrollView.contentOffset,
                                                    inputFrameInWindow: visibleSearchInputFrameInWindow(),
                                                    windowBounds: view.window?.bounds,
                                                    bottomSafeAreaInset: view.safeAreaInsets.bottom,
                                                    scrolledInputDistance: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                                                        - stickySearchInputTranslation,
                                                    stickySearchInputTranslation: stickySearchInputTranslation)
        } else if !isEditing, let savedLayout = inputEditingLayout {
            setFocusedPose(nil)
            inputEditingLayout = nil
            applyScrollInsets()
            restoreScrollPosition(savedLayout.isGeometryValid && !isStickyInputEnabled ? savedLayout.contentOffset : scrollView.contentOffset)
        }
        searchInputView?.alpha = isEditing ? 0 : 1
        applyAccessibilityReach()
        searchInputView?.isUserInteractionEnabled = !isEditing
        scrollView.isScrollEnabled = !isEditing
        customizeButton.alpha = isEditing ? 0 : 1
        customizeButton.isUserInteractionEnabled = !isEditing
        updateStickySearchInput()
    }
}

enum RedesignedNewTabPageAccessibilityReach: Equatable {
    case wholePage
    case focusedModulesOnly
    case nothing

    init(isEditing: Bool, isPresentingOnboardingDialog: Bool, focusedPose: NewTabPageFocusedPose?) {
        if !isEditing || isPresentingOnboardingDialog {
            self = .wholePage
        } else if focusedPose?.showsModules == true {
            self = .focusedModulesOnly
        } else {
            self = .nothing
        }
    }
}

/// A stack view whose blocks stay tappable after a focused pose transform moves them outside its bounds.
private final class TransformedBlocksStackView: UIStackView {

    /// Called after each layout pass, when the stack's height is current.
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || arrangedSubviews.contains { blockView in
            !blockView.isHidden && blockView.alpha > 0 && blockView.bounds.contains(blockView.convert(point, from: self))
        }
    }
}

extension RedesignedNewTabPageViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateStickySearchInput()
    }
}
