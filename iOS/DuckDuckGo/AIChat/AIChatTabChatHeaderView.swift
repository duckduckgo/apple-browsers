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
import UIKit

protocol AIChatTabChatHeaderViewDelegate: AnyObject {
    func aiChatTabChatHeaderDidTapChatList()
    func aiChatTabChatHeaderDidTapUpgrade()
    func aiChatTabChatHeaderDidTapClose()
    func aiChatTabChatHeaderDidTapNewChat()
    func aiChatTabChatHeaderDidTapNewVoiceChat()
    func aiChatTabChatHeaderDidTapNewTab()
    func aiChatTabChatHeaderDidTapNewSearch()
    func aiChatTabChatHeaderDidTapNewFireTab()
    func aiChatTabChatHeaderDidTapTabSwitcher()
}

final class AIChatTabChatHeaderView: UIView {

    private enum Constants {
        static let headerHeight: CGFloat = 60
        static let buttonSize: CGFloat = 48
        static let horizontalPadding: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let titleEdgeSpacing: CGFloat = 12
        static let titleHorizontalPadding: CGFloat = 12
        static let titleVerticalPadding: CGFloat = 2
        static let chevronSize: CGFloat = 12
        static let chevronSpacing: CGFloat = 4
        static let pillInnerHorizontalPadding: CGFloat = 6
        static let pillInnerIconSpacing: CGFloat = 20
        static let pillButtonSize: CGFloat = 36
        static let paidIconSize: CGFloat = 16
        static let paidIconTitleSpacing: CGFloat = 6
    }

    weak var delegate: AIChatTabChatHeaderViewDelegate?

    private let isFireModeEnabled: Bool

    private struct ViewState: Equatable {
        /// `nil` until the first subscription-state check resolves, so we can render a blank
        /// title slot rather than flashing "Free Plan" before flipping to "Duck.ai".
        var isSubscriptionActive: Bool?
        var isVoiceSessionActive: Bool = false
    }

    private var state = ViewState() {
        didSet {
            guard state != oldValue else { return }
            applyState()
        }
    }

    private lazy var closeButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.close,
        accessibilityLabel: UserText.aiChatHeaderCloseTabAccessibilityLabel,
        action: #selector(closeTapped),
        includeChrome: false
    )

    private lazy var chatListButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.chats,
        accessibilityLabel: UserText.aiChatHeaderRecentChatsAccessibilityLabel,
        action: #selector(chatListTapped),
        includeChrome: false
    )

    lazy var closeButtonPill: UIView = makePillContainer()
    lazy var chatListButtonPill: UIView = makePillContainer()
    private lazy var rightPairPill: UIView = makePillContainer()

    private var titleSpacingConstraints: [NSLayoutConstraint] = []

    private lazy var rightPairStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [newChatButton, tabSwitcherButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.pillInnerIconSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

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
        button.addSubview(tabSwitcherView)
        NSLayoutConstraint.activate([
            tabSwitcherView.topAnchor.constraint(equalTo: button.topAnchor),
            tabSwitcherView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            tabSwitcherView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            tabSwitcherView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        // Capsule-clip the button so the adjacent Plus menu dismissal can't flash a rectangle highlight.
        button.layer.cornerRadius = Constants.pillButtonSize / 2
        button.clipsToBounds = true
        return button
    }()

    /// Pushes the tab-icon state from `refreshTabIcon` into the header's renderer in one call,
    /// keeping the count, unread-dot, and fire-mode tint in lock-step with the toolbar button.
    func setTabIconState(count: Int, hasUnread: Bool, isFireMode: Bool) {
        tabSwitcherView.updateCount(count)
        tabSwitcherView.hasUnread = hasUnread
        tabSwitcherView.isFireMode = isFireMode
    }

    private lazy var newChatButton: UIButton = {
        // Selector only satisfies `makeIconButton`'s non-optional `action:` — `showsMenuAsPrimaryAction = true` means the menu opens on tap and the selector never fires.
        let button = makeIconButton(
            image: DesignSystemImages.Glyphs.Size24.add,
            accessibilityLabel: UserText.aiChatHeaderPlusMenuAccessibilityLabel,
            action: #selector(newChatTapped),
            includeChrome: false
        )
        button.menu = makeNewChatPlusMenu()
        button.showsMenuAsPrimaryAction = true
        // Clip the button itself to the pill shape — without this, UIKit's transient
        // highlight on menu dismiss renders as a rectangle against the surrounding pill.
        button.layer.cornerRadius = Constants.pillButtonSize / 2
        button.clipsToBounds = true
        return button
    }()

    private func makeNewChatPlusMenu() -> UIMenu {
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
        let inTabGroup = UIMenu(options: .displayInline, children: [newChat, newVoiceChat])
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

    init(isFireModeEnabled: Bool) {
        self.isFireModeEnabled = isFireModeEnabled
        super.init(frame: .zero)
        setupUI()
    }

    override init(frame: CGRect) {
        self.isFireModeEnabled = false
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateGlassPillEffects()
            updateButtonShadows()
        }
    }

    func configure(isSubscriptionActive: Bool) {
        state.isSubscriptionActive = isSubscriptionActive
    }

    /// Hide title, chat-list pill, and close button during voice — voice owns its own dismiss UI.
    func setVoiceSessionActive(_ active: Bool) {
        state.isVoiceSessionActive = active
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
    }

    private func applyState() {
        titleContainer.isHidden = state.isSubscriptionActive != false
        paidTitleStack.isHidden = state.isSubscriptionActive != true
        let voiceActive = state.isVoiceSessionActive
        titleHolder.isHidden = voiceActive
        // Hide each pill (and its button inside it) together so the surrounding glass pill
        // background also disappears during voice sessions. Voice mode owns its own dismiss UI.
        chatListButtonPill.isHidden = voiceActive
        chatListButton.isHidden = voiceActive
        closeButtonPill.isHidden = voiceActive
        closeButton.isHidden = voiceActive
        titleSpacingConstraints.forEach { $0.isActive = !titleHolder.isHidden }
    }

    private lazy var bottomSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .lines)
        return view
    }()

    private func setupUI() {
        backgroundColor = UIColor(designSystemColor: .surfaceCanvas)
        addSubview(leftStack)
        addSubview(rightStack)
        addSubview(titleHolder)
        titleHolder.addSubview(paidTitleStack)
        titleHolder.addSubview(titleContainer)
        addSubview(bottomSeparator)

        leftStack.addArrangedSubview(closeButtonPill)
        leftStack.addArrangedSubview(chatListButtonPill)
        pillContentSuperview(for: closeButtonPill).addSubview(closeButton)
        pillContentSuperview(for: chatListButtonPill).addSubview(chatListButton)
        rightStack.addArrangedSubview(rightPairPill)
        pillContentSuperview(for: rightPairPill).addSubview(rightPairStack)

        for control in [closeButton, chatListButton, newChatButton, tabSwitcherButton] as [UIControl] {
            control.addGestureRecognizer(StrictBoundsTouchObserver())
        }

        titleContainer.addSubview(freeTitleStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.headerHeight),

            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleHolder.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleHolder.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleContainer.topAnchor.constraint(equalTo: titleHolder.topAnchor),
            titleContainer.leadingAnchor.constraint(equalTo: titleHolder.leadingAnchor),
            titleContainer.trailingAnchor.constraint(equalTo: titleHolder.trailingAnchor),
            titleContainer.bottomAnchor.constraint(equalTo: titleHolder.bottomAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            chatListButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            chatListButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            newChatButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            newChatButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            tabSwitcherButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            tabSwitcherButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            closeButtonPill.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            closeButtonPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            closeButton.centerXAnchor.constraint(equalTo: closeButtonPill.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: closeButtonPill.centerYAnchor),

            chatListButtonPill.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            chatListButtonPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            chatListButton.centerXAnchor.constraint(equalTo: chatListButtonPill.centerXAnchor),
            chatListButton.centerYAnchor.constraint(equalTo: chatListButtonPill.centerYAnchor),

            rightPairPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            rightPairStack.leadingAnchor.constraint(equalTo: rightPairPill.leadingAnchor, constant: Constants.pillInnerHorizontalPadding),
            rightPairStack.trailingAnchor.constraint(equalTo: rightPairPill.trailingAnchor, constant: -Constants.pillInnerHorizontalPadding),
            rightPairStack.topAnchor.constraint(equalTo: rightPairPill.topAnchor),
            rightPairStack.bottomAnchor.constraint(equalTo: rightPairPill.bottomAnchor),

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
                self?.upgradeTapped()
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

    private func makeIconButton(image: DesignSystemImage, accessibilityLabel: String, action: Selector, includeChrome: Bool = true) -> UIButton {
        let image = image.withRenderingMode(.alwaysTemplate)
        let button: UIButton
        if includeChrome, #available(iOS 26, *) {
            var config = UIButton.Configuration.prominentClearGlass()
            config.image = image
            config.cornerStyle = .capsule
            button = UIButton(configuration: config)
        } else if includeChrome {
            button = makeIconButtonLegacy(image: image)
        } else {
            button = UIButton(type: .system)
            button.setImage(image, for: .normal)
            button.automaticallyUpdatesConfiguration = false
            button.configurationUpdateHandler = nil
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        if includeChrome {
            applyGlassChromeShadow(to: button)
        }
        return button
    }

    private func makeIconButtonLegacy(image: DesignSystemImage) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
        button.layer.cornerRadius = Constants.buttonSize / 2
        return button
    }

    private func pillContentSuperview(for pill: UIView) -> UIView {
        // Pill is the shadow host; first subview is the clip host that holds the visual chrome.
        let clipHost = pill.subviews.first(where: { $0.accessibilityIdentifier == Self.pillClipHostIdentifier }) ?? pill
        if #available(iOS 26, *),
           let effectView = clipHost.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView {
            return effectView.contentView
        }
        return clipHost
    }

    private static let pillClipHostIdentifier = "aiChatHeader.pillClipHost"

    /// Two-view pill: outer `shadowHost` (drop shadow, no clip) wrapping inner `clipHost` (rounded, clipped).
    /// The split contains menu-dismiss rendering inside the clip host while letting the shadow render outside — one layer can't do both.
    private func makePillContainer() -> UIView {
        let shadowHost = UIView()
        shadowHost.translatesAutoresizingMaskIntoConstraints = false

        let clipHost = UIView()
        clipHost.translatesAutoresizingMaskIntoConstraints = false
        clipHost.accessibilityIdentifier = Self.pillClipHostIdentifier
        clipHost.layer.cornerRadius = Constants.buttonSize / 2
        clipHost.clipsToBounds = true

        shadowHost.addSubview(clipHost)
        NSLayoutConstraint.activate([
            clipHost.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            clipHost.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            clipHost.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            clipHost.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),
        ])

        if #available(iOS 26, *) {
            let effectView = makeGlassPillEffectView()
            clipHost.addSubview(effectView)
            NSLayoutConstraint.activate([
                effectView.topAnchor.constraint(equalTo: clipHost.topAnchor),
                effectView.leadingAnchor.constraint(equalTo: clipHost.leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: clipHost.trailingAnchor),
                effectView.bottomAnchor.constraint(equalTo: clipHost.bottomAnchor),
            ])
        } else {
            clipHost.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
        }

        // Shadow on the outer host so it renders outside the capsule bounds. Corner radius is
        // mirrored here too so the shadow itself follows the capsule shape.
        shadowHost.layer.cornerRadius = Constants.buttonSize / 2
        applyGlassChromeShadow(to: shadowHost)
        return shadowHost
    }

    @available(iOS 26, *)
    private func makeGlassPillEffectView() -> UIVisualEffectView {
        let effectView = UIVisualEffectView(effect: makeGlassPillEffect())
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = Constants.buttonSize / 2
        effectView.clipsToBounds = true
        return effectView
    }

    @available(iOS 26, *)
    private func makeGlassPillEffect() -> UIGlassEffect {
        let glassStyle: UIGlassEffect.Style = traitCollection.userInterfaceStyle == .dark ? .clear : .regular
        let effect = UIGlassEffect(style: glassStyle)
        effect.isInteractive = true
        return effect
    }

    private func updateGlassPillEffects() {
        guard #available(iOS 26, *) else { return }

        for pill in [closeButtonPill, chatListButtonPill, rightPairPill] {
            // Pill is the shadow host; the effect view lives inside the clip host one level in.
            let clipHost = pill.subviews.first(where: { $0.accessibilityIdentifier == Self.pillClipHostIdentifier })
            let searchRoot = clipHost ?? pill
            guard let effectView = searchRoot.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView else { continue }
            effectView.effect = makeGlassPillEffect()
        }
    }

    private func updateButtonShadows() {
        let chromedViews: [UIView] = [closeButtonPill, chatListButtonPill, rightPairPill]
        for view in chromedViews {
            applyGlassChromeShadow(to: view)
        }
    }

    private func applyGlassChromeShadow(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.16
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.layer.shadowRadius = 16
        view.layer.borderWidth = 0
        view.layer.borderColor = nil
        view.clipsToBounds = false
    }

    @objc private func closeTapped() { delegate?.aiChatTabChatHeaderDidTapClose() }
    @objc private func chatListTapped() { delegate?.aiChatTabChatHeaderDidTapChatList() }
    @objc private func newChatTapped() { delegate?.aiChatTabChatHeaderDidTapNewChat() }
    @objc private func tabSwitcherTapped() { delegate?.aiChatTabChatHeaderDidTapTabSwitcher() }
    @objc private func upgradeTapped() {
        if state.isSubscriptionActive == false {
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

/// Cancels the host UIControl's touch follow-through the moment the touch leaves the visible
/// bounds. UIControl tolerates ~70pt of slack by default — fine for an isolated button, but
/// inside our shared glass pill it lets the originally-tapped icon fire when the finger is
/// released over a sibling icon. The flags below keep the recognizer purely observational so
/// the control's own taps, long-press, and menus still flow normally.
private final class StrictBoundsTouchObserver: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        cancelsTouchesInView = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let control = view as? UIControl, let touch = touches.first else { return }
        if !control.bounds.contains(touch.location(in: control)) {
            control.cancelTracking(with: event)
        }
    }
}
