//
//  AIChatTabChatHeaderView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import FeatureFlags_iOS
import PrivacyConfig
import UIKit

protocol AIChatTabChatHeaderViewDelegate: AnyObject {
    func aiChatTabChatHeaderDidTapChatList()
    func aiChatTabChatHeaderDidTapUpgrade()
    func aiChatTabChatHeaderDidTapClose()
    func aiChatTabChatHeaderDidTapNewChat()
    func aiChatTabChatHeaderDidTapNewVoiceChat()
    func aiChatTabChatHeaderDidTapNewImage()
    func aiChatTabChatHeaderDidTapNewTab()
    func aiChatTabChatHeaderDidTapNewSearch()
    func aiChatTabChatHeaderDidTapNewFireTab()
    func aiChatTabChatHeaderDidTapTabSwitcher()
    func aiChatTabChatHeaderUpgradePlateDidBecomeVisible()
    /// The Plus menu opens over the page, so a keyboard there gets out of its way.
    func aiChatTabChatHeaderPlusMenuWillOpen()
    /// The Plus menu closed without opening a new tab.
    func aiChatTabChatHeaderPlusMenuWillCloseInPlace()
}

final class AIChatTabChatHeaderView: UIView {

    /// Tells the header when a new tab comes in over the page, which shared chrome has to look right for.
    weak var newTabOpening: NewTabOpeningObserving?

    static var preferredHeight: CGFloat { Constants.headerHeight }

    enum Layout {
        /// Close button, and a Plus menu that starts chats in this tab or opens new tabs.
        case standard
        /// No close button; every Plus menu row opens a new tab.
        case newTabActions

        var showsCloseButton: Bool { self == .standard }

        init(featureFlagger: FeatureFlagger) {
            self = featureFlagger.isFeatureOn(.aiChatTabHandoffImprovements) ? .newTabActions : .standard
        }
    }

    private enum Constants {
        static let headerHeight: CGFloat = 60
        static let buttonSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let titleEdgeSpacing: CGFloat = 12
        static let titleHorizontalPadding: CGFloat = 12
        static let titleVerticalPadding: CGFloat = 2
        static let chevronSize: CGFloat = 12
        static let chevronSpacing: CGFloat = 4
        /// Gap between the two icons in the shared right pill: two `buttonSize` targets + this = the 104pt group.
        static let pillInnerIconSpacing: CGFloat = 16
        static let tabBadgeSize: CGFloat = 36
        static let paidIconSize: CGFloat = 16
        static let paidIconTitleSpacing: CGFloat = 6
        static let titleMinimumScaleFactor: CGFloat = 0.7
    }

    weak var delegate: AIChatTabChatHeaderViewDelegate?

    private let isFireModeEnabled: Bool

    private let layout: Layout

    private let shouldShowImageGeneration: Bool

    private struct ViewState: Equatable {
        /// `nil` until the first subscription-state check resolves, so we can render a blank
        /// title slot rather than flashing "Free Plan" before flipping to "Duck.ai".
        var isSubscriptionActive: Bool?
        var allowsSubscriptionUpsell = true
        /// Non-nil while the voice surface is on screen; the value is the colour to paint the header.
        var voiceBackgroundColor: UIColor?
        /// Hides the free/upgrade title during the Duck.ai fire onboarding step.
        var isOnboardingLocked: Bool = false
        /// Visibility of the enclosing Duck.ai tab-header container.
        var isContainerVisible: Bool = false
    }

    private var state = ViewState() {
        didSet {
            guard state != oldValue else { return }
            applyState()
            notifyDelegateIfUpgradePlateBecameVisible()
        }
    }

    private var wasUpgradePlateVisible = false

    /// `nil` subscription state means unresolved, not free — hence the explicit `== false`.
    private var isTitleContainerVisible: Bool {
        !state.isOnboardingLocked && state.isSubscriptionActive == false && state.allowsSubscriptionUpsell
    }

    private var isTitleHolderVisible: Bool {
        state.voiceBackgroundColor == nil
    }

    private var isUpgradePlateVisible: Bool {
        state.isContainerVisible && isTitleHolderVisible && isTitleContainerVisible
    }

    private func notifyDelegateIfUpgradePlateBecameVisible() {
        let isVisible = isUpgradePlateVisible
        guard isVisible != wasUpgradePlateVisible else { return }
        wasUpgradePlateVisible = isVisible
        guard isVisible else { return }
        delegate?.aiChatTabChatHeaderUpgradePlateDidBecomeVisible()
    }

    private lazy var closeButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.close,
        accessibilityLabel: UserText.aiChatHeaderCloseTabAccessibilityLabel,
        action: #selector(closeTapped)
    )

    private lazy var chatListButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.chats,
        accessibilityLabel: UserText.aiChatHeaderRecentChatsAccessibilityLabel,
        action: #selector(chatListTapped)
    )

    lazy var closeButtonPill = AIChatHeaderGlassPill(cornerRadius: Constants.buttonSize / 2, usesFloatingAIChrome: usesFloatingAIChrome)
    lazy var chatListButtonPill = AIChatHeaderGlassPill(cornerRadius: Constants.buttonSize / 2, usesFloatingAIChrome: usesFloatingAIChrome)
    private lazy var rightPairPill = Self.makeRightPairPill(holding: [newChatButton, tabSwitcherButton],
                                                            usesFloatingAIChrome: usesFloatingAIChrome)

    private var glassPills: [AIChatHeaderGlassPill] { [closeButtonPill, chatListButtonPill, rightPairPill] }

    private var titleSpacingConstraints: [NSLayoutConstraint] = []

    /// Reuses the toolbar's tab-switcher renderer so count formatting (incl. the ∞ overflow
    /// threshold), unread-dot, and fire-mode tint stay defined in a single place.
    lazy var tabSwitcherView: TabSwitcherStaticView = {
        let view = TabSwitcherStaticView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var tabSwitcherButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        button.accessibilityLabel = UserText.tabSwitcherAccessibilityLabel
        button.addTarget(self, action: #selector(tabSwitcherTapped), for: .touchUpInside)
        Self.placeTabBadge(tabSwitcherView, in: button)
        // Capsule-clip the button so the adjacent Plus menu dismissal can't flash a rectangle highlight.
        button.layer.cornerRadius = Constants.buttonSize / 2
        button.clipsToBounds = true
        return button
    }()

    /// Pushes the tab-icon state from `refreshTabIcon` into the header's renderer in one call,
    /// keeping the count, unread-dot, and fire-mode tint in lock-step with the toolbar button.
    func setTabIconState(count: Int, hasUnread: Bool, isFireMode: Bool) {
        tabIconState = TabIconState(count: count, hasUnread: hasUnread, isFireMode: isFireMode)
        tabIconState.apply(to: tabSwitcherView)
    }

    private struct TabIconState {
        var count = 0
        var hasUnread = false
        var isFireMode = false

        func apply(to view: TabSwitcherStaticView) {
            view.updateCount(count)
            view.hasUnread = hasUnread
            view.isFireMode = isFireMode
        }
    }

    private var tabIconState = TabIconState()

    private lazy var newChatButton: UIButton = {
        // Selector only satisfies `makeIconButton`'s non-optional `action:` — `showsMenuAsPrimaryAction = true` means the menu opens on tap and the selector never fires.
        let button = FadingMenuButton(type: .system)
        configureIconButton(button,
                            image: Self.plusIcon,
                            accessibilityLabel: UserText.aiChatHeaderPlusMenuAccessibilityLabel,
                            action: #selector(newChatTapped))
        // A new tab opening over the page means the Plus menu fades instead of morphing back.
        button.fadesMenuOnDismissal = { [weak self] in self?.newTabOpening?.isOpeningNewTab == true }
        button.menuWillFadeOut = { [weak self] in self?.coverRightPairWithStandIn() }
        button.menuWillOpen = { [weak self] in self?.delegate?.aiChatTabChatHeaderPlusMenuWillOpen() }
        button.menuWillCloseInPlace = { [weak self] in self?.delegate?.aiChatTabChatHeaderPlusMenuWillCloseInPlace() }
        button.menu = makeNewChatPlusMenu()
        button.showsMenuAsPrimaryAction = true
        // Clip the button itself to the pill shape — without this, UIKit's transient
        // highlight on menu dismiss renders as a rectangle against the surrounding pill.
        button.layer.cornerRadius = Constants.buttonSize / 2
        button.clipsToBounds = true
        return button
    }()

    var plusMenu: UIMenu? { newChatButton.menu }

    private func makeNewChatPlusMenu() -> UIMenu {
        switch layout {
        case .standard: makeStandardPlusMenu()
        case .newTabActions: makeNewTabActionsPlusMenu()
        }
    }

    private func makeNewTabActionsPlusMenu() -> UIMenu {
        var chatActions: [UIAction] = [
            UIAction(title: UserText.aiChatHeaderNewTabChatTitle, image: DesignSystemImages.Glyphs.Size24.compose) { [weak self] _ in
                self?.delegate?.aiChatTabChatHeaderDidTapNewChat()
            },
            UIAction(title: UserText.aiChatHeaderNewTabVoiceChatTitle, image: DesignSystemImages.Glyphs.Size24.voice) { [weak self] _ in
                self?.delegate?.aiChatTabChatHeaderDidTapNewVoiceChat()
            },
        ]
        if shouldShowImageGeneration {
            chatActions.append(UIAction(title: UserText.aiChatHeaderNewTabImageTitle, image: DesignSystemImages.Glyphs.Size24.image) { [weak self] _ in
                self?.delegate?.aiChatTabChatHeaderDidTapNewImage()
            })
        }
        let search = UIAction(title: UserText.aiChatHeaderNewTabSearchTitle, image: DesignSystemImages.Glyphs.Size24.findSearchSmall) { [weak self] _ in
            self?.delegate?.aiChatTabChatHeaderDidTapNewSearch()
        }
        return UIMenu(children: [
            UIMenu(title: UserText.aiChatHeaderNewTabSectionTitle, options: .displayInline, children: chatActions),
            UIMenu(options: .displayInline, children: [search]),
        ])
    }

    private func makeStandardPlusMenu() -> UIMenu {
        let newChat = UIAction(
            title: UserText.actionNewAIChat,
            image: DesignSystemImages.Glyphs.Size24.compose
        ) { [weak self] _ in
            self?.delegate?.aiChatTabChatHeaderDidTapNewChat()
        }
        let newVoiceChat = UIAction(
            title: UserText.aiChatHeaderNewVoiceChatTitle,
            image: DesignSystemImages.Glyphs.Size24.voice
        ) { [weak self] _ in
            self?.delegate?.aiChatTabChatHeaderDidTapNewVoiceChat()
        }
        let newTab = UIAction(
            title: UserText.aiChatHeaderNewTabTitle,
            image: DesignSystemImages.Glyphs.Size24.tabNew
        ) { [weak self] _ in
            self?.delegate?.aiChatTabChatHeaderDidTapNewTab()
        }
        let newSearch = UIAction(
            title: UserText.aiChatHeaderNewSearchTitle,
            image: DesignSystemImages.Glyphs.Size24.findSearchSmall
        ) { [weak self] _ in
            self?.delegate?.aiChatTabChatHeaderDidTapNewSearch()
        }
        var inTabActions: [UIAction] = [newChat, newVoiceChat]
        if shouldShowImageGeneration {
            let newImage = UIAction(
                title: UserText.aiChatHeaderNewImageTitle,
                image: DesignSystemImages.Glyphs.Size24.image
            ) { [weak self] _ in
                self?.delegate?.aiChatTabChatHeaderDidTapNewImage()
            }
            inTabActions.append(newImage)
        }
        let inTabGroup = UIMenu(options: .displayInline, children: inTabActions)
        var newTabActions: [UIAction] = [newTab, newSearch]
        if isFireModeEnabled {
            let newFireTab = UIAction(
                title: UserText.aiChatHeaderNewFireTabTitle,
                image: DesignSystemImages.Glyphs.Size24.fireTabs
            ) { [weak self] _ in
                self?.delegate?.aiChatTabChatHeaderDidTapNewFireTab()
            }
            newTabActions.append(newFireTab)
        }
        let newTabGroup = UIMenu(options: .displayInline, children: newTabActions)
        return UIMenu(children: [inTabGroup, newTabGroup])
    }

    private lazy var titleContainer: HighlightableContainerView = {
        let container = HighlightableContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Constants.titleVerticalPadding,
                                                                     leading: Constants.titleHorizontalPadding,
                                                                     bottom: Constants.titleVerticalPadding,
                                                                     trailing: Constants.titleHorizontalPadding)
        container.addTarget(self, action: #selector(upgradeTapped), for: .touchUpInside)
        return container
    }()

    /// Wraps `titleContainer` (free upgrade plate) and `paidTitleStack` (paid icon + title) so the slot can be hidden via one `isHidden` toggle (voice mode).
    lazy var titleHolder: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var freePlanLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = UserText.aiChatHeaderFreePlan
        label.font = AIChatTabChatHeaderView.makeTitlePrimaryFont()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = Constants.titleMinimumScaleFactor
        return label
    }()

    private lazy var freeChevronView: UIImageView = {
        let imageView = UIImageView(image: DesignSystemImages.Glyphs.Size24.chevronDownSmall)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = UIColor(designSystemColor: .textPrimary)
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var upgradeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = UserText.aiChatHeaderUpgrade
        label.font = .daxCaption1()
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = Constants.titleMinimumScaleFactor
        return label
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = UserText.aiChatHeaderPaidTitle
        label.font = AIChatTabChatHeaderView.makeNavigationTitleFont()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = Constants.titleMinimumScaleFactor
        return label
    }()

    private lazy var paidIconView: UIImageView = {
        let imageView = UIImageView(image: DesignSystemImages.Color.Size16.aiChat)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var paidTitleStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [paidIconView, titleLabel])
        stack.axis = .horizontal
        stack.spacing = Constants.paidIconTitleSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var freePlanRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [freePlanLabel, freeChevronView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.chevronSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var freeTitleStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [freePlanRow, upgradeLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        return stack
    }()

    private static func makeTitlePrimaryFont() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
        return UIFont(descriptor: descriptor, size: descriptor.pointSize)
    }

    private static func makeNavigationTitleFont() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
        return UIFont(descriptor: descriptor, size: descriptor.pointSize)
    }

    private lazy var leftStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Constants.buttonSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var rightStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Constants.buttonSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let usesFloatingAIChrome: Bool
    private let leadingSafeAreaFill = UIView()
    private let trailingSafeAreaFill = UIView()

    init(isFireModeEnabled: Bool, shouldShowImageGeneration: Bool, usesFloatingAIChrome: Bool = false, layout: Layout = .standard) {
        self.isFireModeEnabled = isFireModeEnabled
        self.shouldShowImageGeneration = shouldShowImageGeneration
        self.usesFloatingAIChrome = usesFloatingAIChrome
        self.layout = layout
        super.init(frame: .zero)
        setupUI()
    }

    override init(frame: CGRect) {
        self.isFireModeEnabled = false
        self.shouldShowImageGeneration = false
        self.usesFloatingAIChrome = false
        self.layout = .standard
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            glassPills.forEach { $0.refreshGlassForCurrentTraits() }
            updateButtonShadows()
        }
    }

    func configure(isSubscriptionActive: Bool, allowsSubscriptionUpsell: Bool = true) {
        var updatedState = state
        updatedState.isSubscriptionActive = isSubscriptionActive
        updatedState.allowsSubscriptionUpsell = allowsSubscriptionUpsell
        state = updatedState
    }

    func setAllowsSubscriptionUpsell(_ allowed: Bool) {
        state.allowsSubscriptionUpsell = allowed
    }

    func setContainerVisible(_ visible: Bool) {
        state.isContainerVisible = visible
    }

    /// Paints the header the voice colour and hides the title/pills during voice; `nil` colour → the token.
    func setVoiceSessionActive(_ active: Bool, backgroundColor: UIColor? = nil) {
        state.voiceBackgroundColor = active ? (backgroundColor ?? UIColor(singleUseColor: .duckAIVoiceModeBackground)) : nil
    }

    /// Lock/unlock header controls during onboarding (close included — would otherwise let users escape via the NTP).
    /// Dimming is applied to the enclosing pills so the glass background and tab-count label fade uniformly with the icons.
    func setOnboardingLocked(_ locked: Bool) {
        closeButton.isEnabled = !locked
        newChatButton.isEnabled = !locked
        chatListButton.isEnabled = !locked
        tabSwitcherButton.isEnabled = !locked
        titleContainer.isUserInteractionEnabled = !locked

        let dimmedAlpha: CGFloat = locked ? 0.5 : 1
        closeButtonPill.alpha = dimmedAlpha
        chatListButtonPill.alpha = dimmedAlpha
        rightPairPill.alpha = dimmedAlpha
        titleContainer.alpha = dimmedAlpha
        state.isOnboardingLocked = locked
        updateButtonShadows()
    }

    private func applyState() {
        // During fire onboarding, hide the free/upgrade title to avoid distraction.
        titleContainer.isHidden = !isTitleContainerVisible
        let showsNeutralTitle = state.isSubscriptionActive == false && !state.allowsSubscriptionUpsell && !state.isOnboardingLocked
        paidTitleStack.isHidden = state.isSubscriptionActive != true && !showsNeutralTitle
        titleContainer.accessibilityElementsHidden = !isTitleContainerVisible
        let voiceActive = state.voiceBackgroundColor != nil
        applyVoiceSessionAppearance(state.voiceBackgroundColor)
        titleHolder.isHidden = !isTitleHolderVisible
        // Hide each pill (and its button inside it) together so the surrounding glass pill
        // background also disappears during voice sessions. Voice mode owns its own dismiss UI.
        chatListButtonPill.isHidden = voiceActive
        chatListButton.isHidden = voiceActive
        closeButtonPill.isHidden = voiceActive
        closeButton.isHidden = voiceActive
        titleSpacingConstraints.forEach { $0.isActive = !titleHolder.isHidden }
    }

    /// During voice, repaint with the voice `backgroundColor` (light-on-dark controls, no separator) so the
    /// header reads as one surface with the voice background; restore standard canvas chrome when `nil`.
    private func applyVoiceSessionAppearance(_ backgroundColor: UIColor?) {
        let active = backgroundColor != nil
        if #available(iOS 26, *), usesFloatingAIChrome, !active {
            self.backgroundColor = .clear
        } else {
            self.backgroundColor = backgroundColor ?? UIColor(designSystemColor: .surfaceCanvas)
        }
        let safeAreaColor = backgroundColor ?? UIColor(singleUseColor: .duckAIWebViewBackground)
        leadingSafeAreaFill.backgroundColor = safeAreaColor
        trailingSafeAreaFill.backgroundColor = safeAreaColor
        overrideUserInterfaceStyle = active ? .dark : .unspecified
        if #available(iOS 26, *), usesFloatingAIChrome {
            bottomSeparator.isHidden = true
        } else {
            bottomSeparator.isHidden = active
        }
    }

    private lazy var bottomSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .lines)
        return view
    }()

    private func setupUI() {
        if #available(iOS 26, *), usesFloatingAIChrome {
            for fill in [leadingSafeAreaFill, trailingSafeAreaFill] {
                fill.translatesAutoresizingMaskIntoConstraints = false
                addSubview(fill)
            }
            NSLayoutConstraint.activate([
                leadingSafeAreaFill.leadingAnchor.constraint(equalTo: leadingAnchor),
                leadingSafeAreaFill.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
                leadingSafeAreaFill.topAnchor.constraint(equalTo: topAnchor),
                leadingSafeAreaFill.bottomAnchor.constraint(equalTo: bottomAnchor),
                trailingSafeAreaFill.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
                trailingSafeAreaFill.trailingAnchor.constraint(equalTo: trailingAnchor),
                trailingSafeAreaFill.topAnchor.constraint(equalTo: topAnchor),
                trailingSafeAreaFill.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        addSubview(leftStack)
        addSubview(rightStack)
        addSubview(titleHolder)
        titleHolder.addSubview(paidTitleStack)
        titleHolder.addSubview(titleContainer)
        addSubview(bottomSeparator)

        if layout.showsCloseButton {
            leftStack.addArrangedSubview(closeButtonPill)
        }
        leftStack.addArrangedSubview(chatListButtonPill)
        closeButtonPill.contentView.addSubview(closeButton)
        chatListButtonPill.contentView.addSubview(chatListButton)
        rightStack.addArrangedSubview(rightPairPill)

        // Only the shared right-pair pill can cross-fire between icons, so only those two are guarded.
        for control in [newChatButton, tabSwitcherButton] as [UIControl] {
            control.addGestureRecognizer(SiblingTouchGuard())
        }

        titleContainer.addSubview(freeTitleStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.headerHeight),

            leftStack.leadingAnchor.constraint(equalTo: usesFloatingAIChrome ? safeAreaLayoutGuide.leadingAnchor : leadingAnchor, constant: Constants.horizontalPadding),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: usesFloatingAIChrome ? safeAreaLayoutGuide.trailingAnchor : trailingAnchor, constant: -Constants.horizontalPadding),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleHolder.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleHolder.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleContainer.topAnchor.constraint(equalTo: titleHolder.topAnchor),
            titleContainer.leadingAnchor.constraint(equalTo: titleHolder.leadingAnchor),
            titleContainer.trailingAnchor.constraint(equalTo: titleHolder.trailingAnchor),
            titleContainer.bottomAnchor.constraint(equalTo: titleHolder.bottomAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            chatListButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            chatListButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            closeButtonPill.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            closeButtonPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            closeButton.centerXAnchor.constraint(equalTo: closeButtonPill.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: closeButtonPill.centerYAnchor),

            chatListButtonPill.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            chatListButtonPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            chatListButton.centerXAnchor.constraint(equalTo: chatListButtonPill.centerXAnchor),
            chatListButton.centerYAnchor.constraint(equalTo: chatListButtonPill.centerYAnchor),

            freeTitleStack.topAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.topAnchor),
            freeTitleStack.leadingAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.leadingAnchor),
            freeTitleStack.trailingAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.trailingAnchor),
            freeTitleStack.bottomAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.bottomAnchor),

            paidTitleStack.centerXAnchor.constraint(equalTo: titleHolder.centerXAnchor),
            paidTitleStack.centerYAnchor.constraint(equalTo: titleHolder.centerYAnchor),
            paidTitleStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleHolder.leadingAnchor),
            paidTitleStack.trailingAnchor.constraint(lessThanOrEqualTo: titleHolder.trailingAnchor),

            paidIconView.widthAnchor.constraint(equalToConstant: Constants.paidIconSize),
            paidIconView.heightAnchor.constraint(equalToConstant: Constants.paidIconSize),

            freeChevronView.widthAnchor.constraint(equalToConstant: Constants.chevronSize),
            freeChevronView.heightAnchor.constraint(equalToConstant: Constants.chevronSize),

            bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])

        upgradeLabel.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: UserText.aiChatHeaderUpgrade) { [weak self] _ in
                guard let self, self.isUpgradePlateVisible else { return false }
                self.upgradeTapped()
                return true
            }
        ]

        titleSpacingConstraints = [
            titleHolder.leadingAnchor.constraint(greaterThanOrEqualTo: leftStack.trailingAnchor, constant: Constants.titleEdgeSpacing),
            titleHolder.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -Constants.titleEdgeSpacing),
        ]

        applyState()
        updateButtonShadows()
    }

    private func makeIconButton(image: DesignSystemImage, accessibilityLabel: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        configureIconButton(button, image: image, accessibilityLabel: accessibilityLabel, action: action)
        return button
    }

    private func configureIconButton(_ button: UIButton, image: DesignSystemImage, accessibilityLabel: String, action: Selector) {
        button.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        button.automaticallyUpdatesConfiguration = false
        button.configurationUpdateHandler = nil
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: - Right pair

    private static let plusIcon = DesignSystemImages.Glyphs.Size24.add

    /// The single recipe for the right pill, used by the real pill and its stand-in so the two can't drift apart.
    private static func makeRightPairPill(holding items: [UIView], usesFloatingAIChrome: Bool) -> AIChatHeaderGlassPill {
        let pill = AIChatHeaderGlassPill(cornerRadius: Constants.buttonSize / 2, usesFloatingAIChrome: usesFloatingAIChrome)
        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.pillInnerIconSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.contentView.addSubview(stack)
        NSLayoutConstraint.activate(items.flatMap { [
            $0.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            $0.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
        ] } + [
            pill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            stack.topAnchor.constraint(equalTo: pill.topAnchor),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
        ])
        return pill
    }

    /// Centres the badge at its own size, so the bigger tap target doesn't stretch it.
    private static func placeTabBadge(_ badge: TabSwitcherStaticView, in container: UIView) {
        container.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: Constants.tabBadgeSize),
            badge.heightAnchor.constraint(equalToConstant: Constants.tabBadgeSize),
        ])
    }

    // MARK: - Right pair stand-in

    /// This header is shared by every tab, so it is part of the new tab growing in over the old one.
    /// When the Plus menu closes into a new tab, UIKit fades the button's glass back in (~0.5 s) and
    /// nothing in its API skips that, so the pill looks blurry on the growing tab. A fresh, menu-free copy
    /// covers the real pill until the new tab has opened. See `NewTabOpeningObserving`.
    private func coverRightPairWithStandIn() {
        let standIn = makeRightPairStandIn()
        let pillAlpha = rightPairPill.alpha
        UIView.performWithoutAnimation {
            addSubview(standIn)
            NSLayoutConstraint.activate([
                standIn.topAnchor.constraint(equalTo: rightPairPill.topAnchor),
                standIn.leadingAnchor.constraint(equalTo: rightPairPill.leadingAnchor),
                standIn.trailingAnchor.constraint(equalTo: rightPairPill.trailingAnchor),
                standIn.bottomAnchor.constraint(equalTo: rightPairPill.bottomAnchor),
            ])
            layoutIfNeeded()
            standIn.alpha = pillAlpha
            rightPairPill.alpha = 0
        }
        let restorePill = { [weak self, weak standIn] in
            standIn?.removeFromSuperview()
            self?.rightPairPill.alpha = pillAlpha
        }
        guard let newTabOpening else { return restorePill() }
        newTabOpening.afterNewTabOpens(restorePill)
    }

    private func makeRightPairStandIn() -> AIChatHeaderGlassPill {
        let pill = Self.makeRightPairPill(holding: [makePlusIconStandIn(), makeTabSwitcherStandIn()])
        pill.applyShadow(dimmed: state.isOnboardingLocked)
        pill.isUserInteractionEnabled = false
        return pill
    }

    private func makePlusIconStandIn() -> UIView {
        let icon = UIImageView(image: Self.plusIcon.withRenderingMode(.alwaysTemplate))
        icon.tintColor = newChatButton.tintColor
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        return icon
    }

    private func makeTabSwitcherStandIn() -> UIView {
        let holder = UIView()
        holder.tintColor = tabSwitcherButton.tintColor
        holder.translatesAutoresizingMaskIntoConstraints = false
        let badge = TabSwitcherStaticView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        tabIconState.apply(to: badge)
        Self.placeTabBadge(badge, in: holder)
        return holder
    }

    private func updateButtonShadows() {
        glassPills.forEach { $0.applyShadow(dimmed: state.isOnboardingLocked) }
    }

    @objc private func closeTapped() { delegate?.aiChatTabChatHeaderDidTapClose() }
    @objc private func chatListTapped() { delegate?.aiChatTabChatHeaderDidTapChatList() }
    @objc private func newChatTapped() { delegate?.aiChatTabChatHeaderDidTapNewChat() }
    @objc private func tabSwitcherTapped() { delegate?.aiChatTabChatHeaderDidTapTabSwitcher() }
    @objc private func upgradeTapped() {
        if isUpgradePlateVisible {
            delegate?.aiChatTabChatHeaderDidTapUpgrade()
        }
    }
}

/// Plain container that fades alpha while highlighted to give buttons-without-chrome a tactile press state.
private final class HighlightableContainerView: UIControl {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.alpha = self.isHighlighted ? 0.5 : 1.0
            }
        }
    }
}

/// Cancels the host control's tracking once the finger moves onto a sibling control, so a tap on one
/// icon in the shared pill can't fire when released over its neighbour. Observational only; with no
/// siblings it never cancels, leaving the control's taps, long-press, and menus normal.
private final class SiblingTouchGuard: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        cancelsTouchesInView = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let control = view as? UIControl,
              let touch = touches.first,
              let container = control.superview else { return }
        let location = touch.location(in: container)
        for case let sibling as UIControl in container.subviews
        where sibling !== control && sibling.isUserInteractionEnabled && sibling.isEnabled && !sibling.isHidden && sibling.frame.contains(location) {
            control.cancelTracking(with: event)
            return
        }
    }
}
