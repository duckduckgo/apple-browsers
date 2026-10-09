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
        static let separatorInset: CGFloat = 16
        static let separatorWidth: CGFloat = 1
        static let labelFontSize: CGFloat = 15
    }

    private let label = FadeOutLabel()
    let removeButton = BrowserChromeButton(.tabSwitcher)
    private let faviconImage = UIImageView()
    private let separatorView = UIView()
    private let leadingSeparatorView = UIView()
    private let pointerHighlightView = UIView()

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
    private var isCurrent = false
    private var isFireModeEnabled = false

    private var hidesCloseButtonUntilHover = false
    private var isPointerHovering = false
    private lazy var tabPointerInteraction = UIPointerInteraction(delegate: self)

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
        isCurrent = false
        contentView.isHidden = false
        leadingSeparatorView.isHidden = true
        leadingSeparatorView.alpha = 1
        separatorView.alpha = 1
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        // UIKit can raise a displaced tab during reordering; keep its background below the flare.
        layer.zPosition = isCurrent ? 2 : min(CGFloat(layoutAttributes.zIndex), 0)
        setNeedsLayout()
        tabPointerInteraction.invalidate()
        removeButton.interactions.compactMap { $0 as? UIPointerInteraction }.forEach { $0.invalidate() }
    }

    private func setUpSubviews() {
        clipsToBounds = true
        contentView.clipsToBounds = true

        contentView.layer.cornerRadius = Self.cornerRadius
        contentView.layer.cornerCurve = .circular
        pointerHighlightView.translatesAutoresizingMaskIntoConstraints = false
        pointerHighlightView.isUserInteractionEnabled = false

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
        leadingSeparatorView.translatesAutoresizingMaskIntoConstraints = false

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.type = .tabSwitcher
        removeButton.setImage(DesignSystemImages.Glyphs.Size16.close)
        removeButton.isPointerInteractionEnabled = true
        removeButton.pointerStyleProvider = { [weak self] button, _, _ in
            self?.pointerStyle(for: button)
        }
        removeButton.contentHorizontalAlignment = .left
        removeButton.addTarget(self, action: #selector(onRemovePressed), for: .touchUpInside)

        faviconContainerView.addSubview(faviconImage)
        contentView.addSubview(pointerHighlightView)
        contentView.addSubview(titleStackView)
        contentView.addSubview(separatorView)
        contentView.addSubview(leadingSeparatorView)
        contentView.addSubview(removeButton)
        contentView.addInteraction(tabPointerInteraction)
        contentView.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover)))

        let titleTrailingConstraint = contentView.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor,
                                                                            constant: Constants.titleTrailingInset)
        titleTrailingConstraint.priority = UILayoutPriority(999)

        labelRemoveButtonConstraint = removeButton.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor,
                                                                             constant: Constants.titleCloseButtonTrailingOffset)
        labelRemoveButtonConstraint?.isActive = false

        NSLayoutConstraint.activate([
            pointerHighlightView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pointerHighlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pointerHighlightView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pointerHighlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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

            leadingSeparatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            leadingSeparatorView.centerYAnchor.constraint(equalTo: separatorView.centerYAnchor),
            leadingSeparatorView.widthAnchor.constraint(equalTo: separatorView.widthAnchor),
            leadingSeparatorView.heightAnchor.constraint(equalTo: separatorView.heightAnchor),

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
        let hovering = (recognizer.state == .began || recognizer.state == .changed)
            && visiblePointerRect(in: contentView).contains(recognizer.location(in: contentView))
        guard hovering != isPointerHovering else { return }
        isPointerHovering = hovering
        updateCloseButtonVisibility()
        UIView.animate(withDuration: 0.15) { self.contentView.layoutIfNeeded() }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateSeparators()
        
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
        self.isCurrent = isCurrent
        layer.zPosition = isCurrent ? 2 : min(layer.zPosition, 0)
        // Edge tabs overlap; an opaque inactive tab keeps the covered title from showing through.
        backgroundColor = isCurrent ? .clear : theme.tabsBarBackgroundColor
        separatorView.backgroundColor = theme.tabsBarSeparatorColor
        separatorView.isHidden = isCurrent || isNextCurrent
        leadingSeparatorView.backgroundColor = theme.tabsBarSeparatorColor
        updateSeparators()

        hidesCloseButtonUntilHover = hidesInactiveCloseButton && !isCurrent
        updateCloseButtonVisibility()
    }

    private func updateSeparators() {
        leadingSeparatorView.alpha = 1
        separatorView.alpha = 1
        guard !isCurrent,
              let collectionView = superview as? UICollectionView,
              let indexPath = collectionView.indexPath(for: self) else {
            leadingSeparatorView.isHidden = true
            return
        }
        let previous = indexPath.item > 0
            ? collectionView.layoutAttributesForItem(at: IndexPath(item: indexPath.item - 1, section: indexPath.section)) : nil
        let next = indexPath.item + 1 < collectionView.numberOfItems(inSection: indexPath.section)
            ? collectionView.layoutAttributesForItem(at: IndexPath(item: indexPath.item + 1, section: indexPath.section)) : nil
        if let previous, CGFloat(previous.zIndex) > layer.zPosition {
            separatorView.alpha = separatorAlpha(forGap: frame.maxX - previous.frame.maxX)
        }
        if let next, CGFloat(next.zIndex) > layer.zPosition {
            leadingSeparatorView.alpha = separatorAlpha(forGap: next.frame.minX - frame.minX)
        }
        if let layout = collectionView.collectionViewLayout as? TabsBarCollectionViewLayout,
           let currentIndex = layout.currentIndex?(),
           let current = layout.layoutAttributesForItem(at: IndexPath(item: currentIndex, section: indexPath.section)),
           current.frame.minX <= frame.minX, frame.minX <= current.frame.maxX {
            leadingSeparatorView.isHidden = true
            return
        }
        let leading = collectionView.bounds.minX + collectionView.adjustedContentInset.left
        let isPinnedAtLeadingEdge = frame.minX == leading && leading > 0
        // A leading overlap covers the previous tab's trailing separator.
        let coversPreviousSeparator = previous.map {
            CGFloat($0.zIndex) < layer.zPosition && $0.frame.minX <= frame.minX && $0.frame.maxX > frame.minX
        } ?? false
        leadingSeparatorView.isHidden = !isPinnedAtLeadingEdge && !coversPreviousSeparator
    }

    private func separatorAlpha(forGap gap: CGFloat) -> CGFloat {
        guard bounds.width > 0 else { return 1 }
        // Ease the outer line away as the accordion closes its last half-tab of space.
        let fraction = min(max(gap / (bounds.width / 2), 0), 1)
        return fraction * fraction * (3 - 2 * fraction)
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
        backgroundColor = .clear
        self.model?.removeObserver(self)
        self.model = nil
        onRemove = nil

        label.primaryColor = theme.barTintColor
        label.text = nil
        label.accessibilityLabel = nil
        faviconImage.image = nil

        separatorView.backgroundColor = theme.tabsBarSeparatorColor

        labelRemoveButtonConstraint?.isActive = false
        separatorView.isHidden = true
        leadingSeparatorView.backgroundColor = nil
        leadingSeparatorView.isHidden = true
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

    func pointerInteraction(_ interaction: UIPointerInteraction,
                            regionFor request: UIPointerRegionRequest,
                            defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        guard let view = interaction.view else { return nil }
        let rect = visiblePointerRect(in: view)
        return rect.contains(request.location) ? UIPointerRegion(rect: rect) : nil
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        guard let view = interaction.view else { return nil }
        return pointerStyle(for: view)
    }

    private func pointerStyle(for view: UIView) -> UIPointerStyle? {
        let rect = visiblePointerRect(in: view)
        guard !rect.isEmpty else { return nil }
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: Self.cornerRadius)
        // UIKit can reposition the hover preview during reveal scrolling; keep tab content out of it.
        let preview = UITargetedPreview(view: view === contentView ? pointerHighlightView : view, parameters: parameters)
        return .init(effect: .hover(preview, prefersScaledContent: false))
    }

    func visiblePointerRect(in view: UIView) -> CGRect {
        guard let collectionView = superview as? UICollectionView else { return view.bounds }
        var rect = frame.intersection(collectionView.bounds.inset(by: collectionView.adjustedContentInset))
        // A pointer preview is drawn above the strip, so explicitly exclude overlapping tabs.
        for cell in collectionView.visibleCells where cell !== self && cell.layer.zPosition > layer.zPosition {
            let overlap = rect.intersection(cell.frame)
            guard !overlap.isEmpty else { continue }
            if overlap.minX <= rect.minX {
                rect = CGRect(x: overlap.maxX, y: rect.minY, width: rect.maxX - overlap.maxX, height: rect.height)
            } else {
                rect.size.width = overlap.minX - rect.minX
            }
        }
        guard !rect.isEmpty else { return .zero }
        return view.convert(rect, from: collectionView).intersection(view.bounds)
    }

}
