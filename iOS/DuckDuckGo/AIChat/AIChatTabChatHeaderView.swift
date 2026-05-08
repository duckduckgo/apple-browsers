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
    func aiChatTabChatHeaderDidTapNewChat()
    func aiChatTabChatHeaderDidTapUpgrade()
    func aiChatTabChatHeaderDidTapAppMenu()
    func aiChatTabChatHeaderDidTapBack()
    func aiChatTabChatHeaderDidTapForward()
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
    }

    weak var delegate: AIChatTabChatHeaderViewDelegate?

    private var isSubscriptionActive: Bool = false
    private var isVoiceModeActive: Bool = false
    private var isNavigationVisible: Bool = false
    private var isNavigationPairVisible: Bool = false

    private lazy var backButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.arrowLeft,
        accessibilityLabel: UserText.keyCommandBrowserBack,
        action: #selector(backTapped),
        includeChrome: false
    )

    private lazy var forwardButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.arrowRight,
        accessibilityLabel: UserText.keyCommandBrowserForward,
        action: #selector(forwardTapped),
        includeChrome: false
    )

    private lazy var navBackButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.arrowLeft,
        accessibilityLabel: UserText.keyCommandBrowserBack,
        action: #selector(backTapped),
        includeChrome: false
    )

    private lazy var navForwardButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.arrowRight,
        accessibilityLabel: UserText.keyCommandBrowserForward,
        action: #selector(forwardTapped),
        includeChrome: false
    )

    private lazy var chatListButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.chats,
        accessibilityLabel: UserText.aiChatHeaderRecentChatsAccessibilityLabel,
        action: #selector(chatListTapped),
        includeChrome: false
    )

    private lazy var newChatButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.compose,
        accessibilityLabel: UserText.aiChatHeaderNewChatAccessibilityLabel,
        action: #selector(newChatTapped),
        includeChrome: false
    )

    private lazy var appMenuButton: UIButton = makeIconButton(
        image: DesignSystemImages.Glyphs.Size24.menuHamburger,
        accessibilityLabel: UserText.menuButtonHint,
        action: #selector(appMenuTapped),
        includeChrome: false
    )

    private lazy var leftPairPill: UIView = makePillContainer()
    private lazy var backPill: UIView = makePillContainer()
    private lazy var forwardPill: UIView = makePillContainer()
    private lazy var navPairPill: UIView = makePillContainer()
    private lazy var rightPairPill: UIView = makePillContainer()

    private lazy var leftPairStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [chatListButton, newChatButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.pillInnerIconSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var navPairStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [navBackButton, navForwardButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.pillInnerIconSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var rightPairStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [tabSwitcherButton, appMenuButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.pillInnerIconSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let tabSwitcherButton: TabSwitcherStaticButton = {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        // The default `tabSwitcherDefault()` config uses `UIButton.Configuration.gray()` which
        // paints an always-visible gray pill behind the inner `TabSwitcherStaticView`. Inside
        // our grouped glass pill we want a transparent button so it matches the other plain icons.
        button.automaticallyUpdatesConfiguration = false
        button.configurationUpdateHandler = nil
        button.configuration = .plain()
        return button
    }()

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

    private lazy var freeTitleStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [freePlanLabel, upgradeLabel])
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
        self.isSubscriptionActive = isSubscriptionActive
        updateTitleVisibility()
    }

    func setNavAvailable(canGoBack: Bool, canGoForward: Bool) {
        let showsNavPair = canGoBack && canGoForward
        let showsStandaloneBack = canGoBack && !canGoForward
        let showsStandaloneForward = canGoForward && !canGoBack
        isNavigationVisible = canGoBack || canGoForward
        isNavigationPairVisible = showsNavPair

        backPill.isHidden = !showsStandaloneBack
        forwardPill.isHidden = !showsStandaloneForward
        navPairPill.isHidden = !showsNavPair
        updateLeftChatControlsVisibility()
        updateTitleVisibility()
    }

    /// Both back+forward arrows in the left pill crowd the row, so the title is dropped in that
    /// state regardless of plan. Otherwise `isSubscriptionActive` picks between the free upgrade
    /// plate (`titleContainer`) and the paid `Duck.ai` nav-style label.
    private func updateTitleVisibility() {
        if isNavigationPairVisible {
            titleContainer.isHidden = true
            titleLabel.isHidden = true
        } else {
            titleContainer.isHidden = isSubscriptionActive
            titleLabel.isHidden = !isSubscriptionActive
        }
    }

    /// Hides the chats / new-chat pill in voice mode (back/forward stay so the user can exit).
    func setVoiceModeActive(_ active: Bool) {
        guard isVoiceModeActive != active else { return }
        isVoiceModeActive = active
        updateLeftChatControlsVisibility()
    }

    private func updateLeftChatControlsVisibility() {
        leftPairPill.isHidden = isVoiceModeActive
        // Compose / new-chat is suppressed when nav arrows are visible — the row gets cluttered.
        newChatButton.isHidden = isNavigationVisible
    }

    private lazy var bottomSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .lines)
        return view
    }()

    private func setupUI() {
        backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        addSubview(leftStack)
        addSubview(rightStack)
        addSubview(titleContainer)
        addSubview(titleLabel)
        addSubview(bottomSeparator)

        leftStack.addArrangedSubview(backPill)
        leftStack.addArrangedSubview(forwardPill)
        leftStack.addArrangedSubview(navPairPill)
        leftStack.addArrangedSubview(leftPairPill)
        pillContentSuperview(for: backPill).addSubview(backButton)
        pillContentSuperview(for: forwardPill).addSubview(forwardButton)
        pillContentSuperview(for: navPairPill).addSubview(navPairStack)
        pillContentSuperview(for: leftPairPill).addSubview(leftPairStack)
        backPill.isHidden = true
        forwardPill.isHidden = true
        navPairPill.isHidden = true
        rightStack.addArrangedSubview(rightPairPill)
        pillContentSuperview(for: rightPairPill).addSubview(rightPairStack)

        for control in [backButton, forwardButton, chatListButton, newChatButton, navBackButton, navForwardButton, tabSwitcherButton, appMenuButton] as [UIControl] {
            control.addGestureRecognizer(StrictBoundsTouchObserver())
        }

        titleContainer.addSubview(freeTitleStack)
        titleContainer.addSubview(freeChevronView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.headerHeight),

            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leftStack.trailingAnchor, constant: Constants.titleEdgeSpacing),
            titleContainer.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -Constants.titleEdgeSpacing),

            backPill.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            backPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            backButton.centerXAnchor.constraint(equalTo: backPill.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backPill.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            backButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            forwardPill.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            forwardPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            forwardButton.centerXAnchor.constraint(equalTo: forwardPill.centerXAnchor),
            forwardButton.centerYAnchor.constraint(equalTo: forwardPill.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            forwardButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            navBackButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            navBackButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            navForwardButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            navForwardButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            chatListButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            chatListButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            newChatButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            newChatButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            appMenuButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            appMenuButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            tabSwitcherButton.widthAnchor.constraint(equalToConstant: Constants.pillButtonSize),
            tabSwitcherButton.heightAnchor.constraint(equalToConstant: Constants.pillButtonSize),

            leftPairPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            leftPairStack.leadingAnchor.constraint(equalTo: leftPairPill.leadingAnchor, constant: Constants.pillInnerHorizontalPadding),
            leftPairStack.trailingAnchor.constraint(equalTo: leftPairPill.trailingAnchor, constant: -Constants.pillInnerHorizontalPadding),
            leftPairStack.topAnchor.constraint(equalTo: leftPairPill.topAnchor),
            leftPairStack.bottomAnchor.constraint(equalTo: leftPairPill.bottomAnchor),

            navPairPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            navPairStack.leadingAnchor.constraint(equalTo: navPairPill.leadingAnchor, constant: Constants.pillInnerHorizontalPadding),
            navPairStack.trailingAnchor.constraint(equalTo: navPairPill.trailingAnchor, constant: -Constants.pillInnerHorizontalPadding),
            navPairStack.topAnchor.constraint(equalTo: navPairPill.topAnchor),
            navPairStack.bottomAnchor.constraint(equalTo: navPairPill.bottomAnchor),

            rightPairPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            rightPairStack.leadingAnchor.constraint(equalTo: rightPairPill.leadingAnchor, constant: Constants.pillInnerHorizontalPadding),
            rightPairStack.trailingAnchor.constraint(equalTo: rightPairPill.trailingAnchor, constant: -Constants.pillInnerHorizontalPadding),
            rightPairStack.topAnchor.constraint(equalTo: rightPairPill.topAnchor),
            rightPairStack.bottomAnchor.constraint(equalTo: rightPairPill.bottomAnchor),

            freeTitleStack.topAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.topAnchor),
            freeTitleStack.leadingAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.leadingAnchor),
            freeTitleStack.trailingAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.trailingAnchor),
            freeTitleStack.bottomAnchor.constraint(equalTo: titleContainer.layoutMarginsGuide.bottomAnchor),

            // Same center as `titleContainer` so the visual position is identical when the
            // subscription state flips between paid (label) and free (container).
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftStack.trailingAnchor, constant: Constants.titleEdgeSpacing),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -Constants.titleEdgeSpacing),

            freeChevronView.leadingAnchor.constraint(equalTo: freePlanLabel.trailingAnchor, constant: Constants.chevronSpacing),
            freeChevronView.centerYAnchor.constraint(equalTo: freePlanLabel.centerYAnchor),
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

        configure(isSubscriptionActive: false)
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

        for pill in [backPill, forwardPill, navPairPill, leftPairPill, rightPairPill] {
            guard let effectView = pill.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView else { continue }
            effectView.effect = makeGlassPillEffect()
        }
    }

    private func updateButtonShadows() {
        let chromedViews: [UIView] = [backPill, forwardPill, navPairPill, leftPairPill, rightPairPill]
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

    @objc private func backTapped() { delegate?.aiChatTabChatHeaderDidTapBack() }
    @objc private func forwardTapped() { delegate?.aiChatTabChatHeaderDidTapForward() }
    @objc private func chatListTapped() { delegate?.aiChatTabChatHeaderDidTapChatList() }
    @objc private func newChatTapped() { delegate?.aiChatTabChatHeaderDidTapNewChat() }
    @objc private func appMenuTapped() { delegate?.aiChatTabChatHeaderDidTapAppMenu() }
    @objc private func upgradeTapped() {
        if !isSubscriptionActive {
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
