//
//  TabsBarCell.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents

class TabsBarCell: UICollectionViewCell {

    static let reuseIdentifier = "Tab"
    static let cornerRadius: CGFloat = 12

    private enum Constants {
        static let faviconCornerRadius: CGFloat = 4
        static let faviconSize: CGFloat = 16
        static let faviconContainerWidth: CGFloat = 24
        static let titleStackSpacing: CGFloat = 4
        static let titleLeadingInset: CGFloat = 12
        static let titleTrailingInset: CGFloat = 8
        static let titleCloseButtonTrailingOffset: CGFloat = 32
        static let bottomBackgroundHeightMultiplier: CGFloat = 0.75
        static let separatorInset: CGFloat = 16
        static let separatorWidth: CGFloat = 1
        static let labelFontSize: CGFloat = 15
    }

    private let label = FadeOutLabel()
    let removeButton = BrowserChromeButton(.tabSwitcher)
    private let faviconImage = UIImageView()
    private let topBackgroundView = UIView()
    private let bottomBackgroundView = UIView()
    private let separatorView = UIView()

    private let titleStackView = UIStackView()
    private let faviconContainerView = UIView()
    private var labelRemoveButtonConstraint: NSLayoutConstraint?
    
    var isPressed = false {
        didSet {
            setNeedsLayout()
        }
    }
    
    var onRemove: (() -> Void)?

    private weak var model: Tab?
    private var isFireModeEnabled = false

    private var hidesCloseButtonUntilHover = false
    private var isPointerHovering = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        setUpSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isPointerHovering = false
    }

    private func setUpSubviews() {
        clipsToBounds = true
        contentView.clipsToBounds = true

        topBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        topBackgroundView.layer.cornerRadius = Self.cornerRadius

        bottomBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        faviconContainerView.translatesAutoresizingMaskIntoConstraints = false

        faviconImage.translatesAutoresizingMaskIntoConstraints = false
        faviconImage.contentMode = .scaleAspectFit
        faviconImage.layer.cornerRadius = Constants.faviconCornerRadius
        faviconImage.layer.masksToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Constants.labelFontSize, weight: .semibold)
        label.lineBreakMode = .byCharWrapping
        label.accessibilityTraits = [.button, .staticText]

        titleStackView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.spacing = Constants.titleStackSpacing
        titleStackView.addArrangedSubview(faviconContainerView)
        titleStackView.addArrangedSubview(label)

        separatorView.translatesAutoresizingMaskIntoConstraints = false

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.type = .tabSwitcher
        removeButton.setImage(DesignSystemImages.Glyphs.Size16.close)
        removeButton.isPointerInteractionEnabled = true
        removeButton.contentHorizontalAlignment = .left
        removeButton.addTarget(self, action: #selector(onRemovePressed), for: .touchUpInside)

        faviconContainerView.addSubview(faviconImage)
        contentView.addSubview(topBackgroundView)
        contentView.addSubview(bottomBackgroundView)
        contentView.addSubview(titleStackView)
        contentView.addSubview(separatorView)
        contentView.addSubview(removeButton)
        contentView.addInteraction(UIPointerInteraction(delegate: self))
        contentView.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover)))

        let titleTrailingConstraint = contentView.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor,
                                                                            constant: Constants.titleTrailingInset)
        titleTrailingConstraint.priority = UILayoutPriority(999)

        labelRemoveButtonConstraint = removeButton.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor,
                                                                             constant: Constants.titleCloseButtonTrailingOffset)
        labelRemoveButtonConstraint?.isActive = false

        NSLayoutConstraint.activate([
            topBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            topBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topBackgroundView.heightAnchor.constraint(equalTo: contentView.heightAnchor),

            bottomBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBackgroundView.heightAnchor.constraint(equalTo: contentView.heightAnchor,
                                                         multiplier: Constants.bottomBackgroundHeightMultiplier),

            titleStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                    constant: Constants.titleLeadingInset),
            titleStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleStackView.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            titleTrailingConstraint,

            faviconContainerView.widthAnchor.constraint(equalToConstant: Constants.faviconContainerWidth),
            faviconImage.leadingAnchor.constraint(equalTo: faviconContainerView.leadingAnchor),
            faviconImage.trailingAnchor.constraint(equalTo: faviconContainerView.trailingAnchor,
                                                   constant: -Constants.titleTrailingInset),
            faviconImage.centerYAnchor.constraint(equalTo: faviconContainerView.centerYAnchor),
            faviconImage.widthAnchor.constraint(equalToConstant: Constants.faviconSize),
            faviconImage.heightAnchor.constraint(equalToConstant: Constants.faviconSize),

            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: Constants.separatorWidth),
            separatorView.heightAnchor.constraint(equalTo: contentView.heightAnchor,
                                                  constant: -Constants.separatorInset),

            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            removeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            removeButton.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            removeButton.widthAnchor.constraint(equalTo: removeButton.heightAnchor),
        ])
    }

    @objc private func onRemovePressed() {
        onRemove?()
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        let hovering = recognizer.state == .began || recognizer.state == .changed
        guard hovering != isPointerHovering else { return }
        isPointerHovering = hovering
        updateCloseButtonVisibility()
        UIView.animate(withDuration: 0.15) { self.contentView.layoutIfNeeded() }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if isPressed {
            layer.masksToBounds = false
            layer.shadowColor = UIColor.darkGray.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 0)
            layer.shadowOpacity = 0.2
            layer.shadowRadius = 5
        } else {
            layer.masksToBounds = true
            layer.shadowColor = nil
            layer.shadowRadius = 0
        }
        
    }

    func update(model: Tab,
                isCurrent: Bool,
                isNextCurrent: Bool,
                hidesInactiveCloseButton: Bool,
                isFireModeEnabled: Bool,
                withTheme theme: Theme) {
        accessibilityElements = [label, removeButton]

        self.model?.removeObserver(self)

        self.model = model
        self.isFireModeEnabled = isFireModeEnabled
        model.addObserver(self)

        label.primaryColor = theme.barTintColor
        applyCurrentStyle(isCurrent: isCurrent, isNextCurrent: isNextCurrent, hidesInactiveCloseButton: hidesInactiveCloseButton, withTheme: theme)

        applyModel(model)
    }

    func applyCurrentStyle(isCurrent: Bool, isNextCurrent: Bool, hidesInactiveCloseButton: Bool, withTheme theme: Theme) {
        if isCurrent {
            topBackgroundView.backgroundColor = theme.omniBarBackgroundColor
            bottomBackgroundView.backgroundColor = theme.omniBarBackgroundColor
        } else {
            topBackgroundView.backgroundColor = .clear
            bottomBackgroundView.backgroundColor = .clear
            separatorView.backgroundColor = theme.tabsBarSeparatorColor
        }
        separatorView.isHidden = isCurrent || isNextCurrent

        hidesCloseButtonUntilHover = hidesInactiveCloseButton && !isCurrent
        updateCloseButtonVisibility()
    }

    /// Shows the close button unless the strip is overflowing and this inactive tab isn't hovered by a pointer.
    private func updateCloseButtonVisibility() {
        let showsCloseButton = !hidesCloseButtonUntilHover || isPointerHovering
        removeButton.isHidden = !showsCloseButton
        labelRemoveButtonConstraint?.isActive = showsCloseButton
    }

    /// Configures the cell to render without a backing `Tab`.
    ///
    /// Used as a defensive fallback when the collection view requests a cell for an index that no
    /// longer exists in the tabs model (e.g. during a desync between the layout and the model). The
    /// cell is left visually empty and non-interactive; a subsequent refresh replaces it.
    func configurePlaceholder(withTheme theme: Theme) {
        self.model?.removeObserver(self)
        self.model = nil
        onRemove = nil

        label.primaryColor = theme.barTintColor
        label.text = nil
        label.accessibilityLabel = nil
        faviconImage.image = nil

        topBackgroundView.backgroundColor = .clear
        bottomBackgroundView.backgroundColor = .clear
        separatorView.backgroundColor = theme.tabsBarSeparatorColor

        labelRemoveButtonConstraint?.isActive = false
        separatorView.isHidden = true
        removeButton.isHidden = true
    }

    private func applyModel(_ model: Tab) {
        if model.link == nil {
            faviconImage.loadFavicon(forDomain: URL.ddg.host, usingCache: .tabs)
            updateEmptyTabLabel(for: model, label: label)
            removeButton.accessibilityLabel = closeButtonAccessibilityLabel(for: model)
        } else if model.isAITab {
            let aiChatTitle = UserText.omnibarFullAIChatModeDisplayTitle
            faviconImage.image = UIImage(resource: .duckAIDefault)
            if let conversationTitle = model.aiChatConversationTitle {
                label.text = "\(aiChatTitle) - \(conversationTitle)"
            } else {
                label.text = aiChatTitle
            }
            label.accessibilityLabel = UserText.openTab(withTitle: label.text ?? aiChatTitle, atAddress: "")
            removeButton.accessibilityLabel = UserText.closeTab(withTitle: label.text ?? aiChatTitle, atAddress: "")
        } else {
            faviconImage.loadFavicon(forDomain: model.link?.url.host, usingCache: .tabs)
            label.text = model.link?.displayTitle ?? model.link?.url.host?.droppingWwwPrefix()
            label.accessibilityLabel = UserText.openTab(withTitle: model.link?.displayTitle ?? "", atAddress: model.link?.url.host ?? "")
            removeButton.accessibilityLabel = UserText.closeTab(withTitle: model.link?.displayTitle ?? "", atAddress: model.link?.url.host ?? "")
        }

    }
    
    private func updateEmptyTabLabel(for tab: Tab, label: FadeOutLabel) {
        if isFireModeEnabled {
            label.text = tab.fireTab ? UserText.fireTabTitle : UserText.newTabTitle
            label.accessibilityLabel = tab.fireTab ? UserText.openNewFireTab : UserText.openNewTab
        } else {
            label.text = UserText.homeTabTitle
            label.accessibilityLabel = UserText.openHomeTab
        }
    }

    private func closeButtonAccessibilityLabel(for tab: Tab) -> String {
        if isFireModeEnabled {
            return tab.fireTab ? UserText.closeFireTab : UserText.closeNewTab
        }
        return UserText.closeHomeTab
    }
    
}

extension TabsBarCell: TabObserver {
    func didChange(tab: Tab) {
        guard tab != self.model else { return }
        applyModel(tab)
    }
}

extension TabsBarCell: UIPointerInteractionDelegate {
    
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        return .init(effect: .highlight(.init(view: contentView)))
    }

}
