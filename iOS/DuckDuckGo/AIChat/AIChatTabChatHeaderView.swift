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
        /// Matches `TabSwitcherAnimatedButton.Constants.maxTextTabs` and `TabCountBadge.maxTextTabs`
        /// so the header overflow threshold stays in sync with the main toolbar tab counter.
        static let maxTextTabs = 100
    }

    weak var delegate: AIChatTabChatHeaderViewDelegate?

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

    private lazy var closeButtonPill: UIView = makePillContainer()
    private lazy var chatListButtonPill: UIView = makePillContainer()
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

    private lazy var tabSwitcherButton: UIButton = {
        let button = makeIconButton(
            image: DesignSystemImages.Glyphs.Size24.tabMobile,
            accessibilityLabel: UserText.tabSwitcherAccessibilityLabel,
            action: #selector(tabSwitcherTapped),
            includeChrome: false
        )
        button.addSubview(tabCountLabel)
        NSLayoutConstraint.activate([
            tabCountLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            tabCountLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 1),
        ])
        return button
    }()

    private lazy var tabCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = UIColor(designSystemColor: .icons)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()

    /// Updates the tab-counter glyph's displayed count. Call when the tab list changes.
    /// Mirrors the threshold used by `TabSwitcherStaticView` so the header and the main
    /// toolbar render the same overflow symbol when there are many tabs.
    func setTabCount(_ count: Int) {
        assert(count > 0, "Duck.ai chat header is only visible inside a tab, so tab count should be ≥ 1; got \(count)")
        guard count > 0 else {
            tabCountLabel.text = nil
            return
        }
        tabCountLabel.text = count >= Constants.maxTextTabs ? "∞" : "\(count)"
    }

    private lazy var newChatButton: UIButton = {
        // Selector is kept only to satisfy `makeIconButton`'s non-optional `action:` parameter;
        // `showsMenuAsPrimaryAction = true` means the menu opens on tap and the selector
        // never fires at runtime.
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
            title: UserText.aiChatHeaderNewChatTitle,
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
        let newFireTab = UIAction(
            title: UserText.aiChatHeaderNewFireTabTitle,
            image: DesignSystemImages.Glyphs.Size24.fireTabs
        ) { [weak self] _ in
            self?.delegate?.aiChatTabChatHeaderDidTapNewFireTab()
        }
        let inTabGroup = UIMenu(options: .displayInline, children: [newChat, newVoiceChat])
        let newTabGroup = UIMenu(options: .displayInline, children: [newTab, newFireTab])
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

    /// Wraps both `titleContainer` (free upgrade plate) and `paidTitleStack` (paid icon + title)
    /// so the entire title slot can be hidden via a single `isHidden` toggle on this wrapper
    /// (used during voice mode), leaving `configure(isSubscriptionActive:)` to swap just the
    /// two children inside.
    private lazy var titleHolder: UIView = {
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

    override init(frame: CGRect) {
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

    /// Hides the title and the chat-list button while a voice session is in progress for this tab.
    /// The close button stays visible so the user can always exit the tab.
    func setVoiceSessionActive(_ active: Bool) {
        state.isVoiceSessionActive = active
    }

    /// Locks or unlocks the header controls during the Duck.ai onboarding experiment path.
    /// When locked, the close, new-chat, upgrade, chats-list, and tab-switcher buttons are
    /// disabled until the fire step passes — the close button included because it would
    /// otherwise let users escape the onboarding flow via the NTP.
    func setOnboardingLocked(_ locked: Bool) {
        closeButton.isEnabled = !locked
        newChatButton.isEnabled = !locked
        chatListButton.isEnabled = !locked
        chatListButton.alpha = locked ? 0.5 : 1
        tabSwitcherButton.isEnabled = !locked
        titleContainer.isUserInteractionEnabled = !locked
        titleContainer.alpha = locked ? 0.5 : 1
    }

    private func applyState() {
        titleContainer.isHidden = state.isSubscriptionActive != false
        paidTitleStack.isHidden = state.isSubscriptionActive != true
        let voiceActive = state.isVoiceSessionActive
        titleHolder.isHidden = voiceActive
        // Hide the chat-list pill (and its button inside it) together so the surrounding
        // glass pill background also disappears during voice sessions.
        chatListButtonPill.isHidden = voiceActive
        chatListButton.isHidden = voiceActive
        titleSpacingConstraints.forEach { $0.isActive = !titleHolder.isHidden }
    }

    private lazy var bottomSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .lines)
        return view
    }()

    private func setupUI() {
        backgroundColor = UIColor(designSystemColor: .surface)
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
        if #available(iOS 26, *),
           let effectView = pill.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView {
            return effectView.contentView
        }
        return pill
    }

    private func makePillContainer() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Constants.buttonSize / 2
        if #available(iOS 26, *) {
            let effectView = makeGlassPillEffectView()
            view.addSubview(effectView)
            NSLayoutConstraint.activate([
                effectView.topAnchor.constraint(equalTo: view.topAnchor),
                effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        } else {
            view.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
        }
        applyGlassChromeShadow(to: view)
        return view
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
            guard let effectView = pill.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView else { continue }
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
