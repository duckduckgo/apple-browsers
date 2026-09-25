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
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// A New Tab Page built as a vertical stack of independent blocks.
final class RedesignedNewTabPageViewController: UIViewController, NewTabPage {

    private enum Metrics {
        static let customizeButtonTopMargin: CGFloat = 10
        static let customizeButtonTrailingMargin: CGFloat = 20
        static let customizeButtonSize: CGFloat = 44
        static let portraitContentTopInset: CGFloat = 96
        static let entranceTranslation: CGFloat = 12
        static let entranceDuration: TimeInterval = 0.25
    }

    weak var delegate: NewTabPageControllerDelegate?
    weak var chromeDelegate: BrowserChromeDelegate?

    var isDragging: Bool { scrollView.isDragging }

    var hasInlineSearchInput: Bool { true }

    private let blocks: [any NewTabPageBlock]
    private let favoritesModel: FavoritesViewModel?
    private let pageModel: NewTabPageViewModel?
    private let messagesModel: NewTabPageMessagesModel?
    private var areFavoritesHidden = false
    private var isEntranceAnimationPending = false
    private var entranceAnimator: UIViewPropertyAnimator?

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

    private let blocksStackView: UIStackView = {
        let stackView = UIStackView()
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
                         background: UIColor(designSystemColor: .controlsFillPrimary),
                         pressedForeground: UIColor(designSystemColor: .iconsSecondary),
                         pressedBackground: UIColor(designSystemColor: .controlsFillTertiary))
        button.accessibilityLabel = UserText.newTabPageCustomizationTitle
        button.addTarget(self, action: #selector(customizeButtonTapped), for: .touchUpInside)
        return button
    }()

    init(blocks: [any NewTabPageBlock],
         favoritesModel: FavoritesViewModel? = nil,
         pageModel: NewTabPageViewModel? = nil,
         messagesModel: NewTabPageMessagesModel? = nil) {
        self.blocks = blocks
        self.favoritesModel = favoritesModel
        self.pageModel = pageModel
        self.messagesModel = messagesModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(designSystemColor: .background)
        addSubviews()
        installBlocks()
        // Load once per page, after the caller has supplied the initial escape-hatch context.
        messagesModel?.load()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        let isLandscape = view.bounds.width > view.bounds.height
        contentTopConstraint.constant = isLandscape ? Metrics.customizeButtonTopMargin : Metrics.portraitContentTopInset
    }

    @objc private func customizeButtonTapped() {
        let model = NewTabPageCustomizationModel()
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

        // The page is attached with alpha 0 ahead of a contextual dialog so content cannot flash
        // for a frame first, and is expected to restore it itself.
        view.alpha = 1
        guard isEntranceAnimationPending else { return }
        isEntranceAnimationPending = false
        let animator = UIViewPropertyAnimator(duration: Metrics.entranceDuration, curve: .easeOut) { [weak self] in
            self?.restoreEntrancePose()
        }
        entranceAnimator = animator
        animator.startAnimation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        finishEntranceAnimation()
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

    func finishEntranceAnimation() {
        guard isEntranceAnimationPending || entranceAnimator != nil else { return }
        isEntranceAnimationPending = false
        entranceAnimator?.stopAnimation(true)
        entranceAnimator = nil
        restoreEntrancePose()
    }

    private func addSubviews() {
        view.addSubview(contentContainerView)
        contentContainerView.addSubview(scrollView)
        scrollView.addSubview(blocksStackView)
        contentContainerView.addSubview(customizeButton)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        blocksStackView.translatesAutoresizingMaskIntoConstraints = false
        customizeButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
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

            customizeButton.topAnchor.constraint(equalTo: contentContainerView.safeAreaLayoutGuide.topAnchor,
                                                 constant: Metrics.customizeButtonTopMargin),
            customizeButton.trailingAnchor.constraint(equalTo: contentContainerView.safeAreaLayoutGuide.trailingAnchor,
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
    }

    func beginSearch(textEntryMode: TextEntryMode) {
        delegate?.newTabPageDidRequestSearch(self, textEntryMode: textEntryMode)
    }

    func beginVoiceSearch(textEntryMode: TextEntryMode) {
        delegate?.newTabPageDidRequestVoiceSearch(self, textEntryMode: textEntryMode)
    }

    func dismiss() {
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

/// The logo is not hosted on this page; favorites participate in the existing content handoff.
extension RedesignedNewTabPageViewController: NewTabPageContentHandoff {

    var isShowingLogo: Bool { false }

    var isShowingFavorites: Bool { restingContentIsFavorites && !areFavoritesHidden }

    var restingContentIsLogo: Bool { false }

    var restingContentIsFavorites: Bool { favoritesModel?.isEmpty == false }

    func setLogoHidden(_ hidden: Bool) {}

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

/// Contextual dialogs are not hosted on this page yet.
extension RedesignedNewTabPageViewController: NewTabPageOnboardingPresenting {

    func showNextDaxDialog() {
        assertionFailure("Contextual onboarding is not implemented on the redesigned New Tab Page")
    }

    func onboardingCompleted() {
        assertionFailure("Contextual onboarding is not implemented on the redesigned New Tab Page")
    }

    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String, textEntryMode: TextEntryMode?) {
        assertionFailure("Contextual onboarding is not implemented on the redesigned New Tab Page")
    }

    func refreshContextualOnboardingDialogLayout() {}

    func dismissDuckAICompletionDialogIfNeededOnEditingEnd() {}
}

extension RedesignedNewTabPageViewController: NewTabPageInputTransitionSource {

    var searchInputView: UIView? {
        blocks.first { $0.id == .searchInput }?.viewController.view
    }

    func setSearchInputEditing(_ isEditing: Bool) {
        if isEditing {
            finishEntranceAnimation()
        }
        searchInputView?.alpha = isEditing ? 0 : 1
        view.accessibilityElementsHidden = isEditing
        searchInputView?.isUserInteractionEnabled = !isEditing
        scrollView.isScrollEnabled = !isEditing
        customizeButton.alpha = isEditing ? 0 : 1
        customizeButton.isUserInteractionEnabled = !isEditing
    }
}
