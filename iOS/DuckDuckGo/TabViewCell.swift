//
//  TabViewCell.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

protocol TabViewCellDelegate: AnyObject {

    func deleteTab(tab: Tab)

    func isCurrent(tab: Tab) -> Bool

    func tabViewCellDidBeginSwipe(_ cell: TabViewCell)
    func tabViewCellDidEndSwipe(_ cell: TabViewCell)
}

class TabViewCell: UICollectionViewCell {

    enum Constants {

        static let swipeToDeleteAlpha: CGFloat = 0.5

        static let borderRadius: CGFloat = 14.0

        static let cellCornerRadius: CGFloat = 12.0
        static let cellHeaderHeight: CGFloat = 36.0 + 4.0 // height + top padding
        static let cellLogoSize: CGFloat = 68.0

        static let previewCornerRadius: CGFloat = 8

        static let selectedBorderWidth: CGFloat = 2.0
        static let unselectedBorderWidth: CGFloat = 0.0
        static let previewPadding: CGFloat = 4.0

        static let removeButtonTextSpacingRegular: CGFloat = -12
        static let removeButtonTextSpacingHighlighted: CGFloat = 2

        static let faviconCornerRadius: CGFloat = 4
        static let cardBorderWidth: CGFloat = 2
        static let borderOutset: CGFloat = 4
        static let selectionIndicatorSize: CGFloat = 24

        static let shadowRadius: CGFloat = 12
        static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
        static let unreadBorderWidth: CGFloat = 6

        static let swipeAnimationDuration: TimeInterval = 0.2
        static let highlightAnimationDuration: TimeInterval = 0.15
    }

    var removeThreshold: CGFloat {
        return frame.width / 3
    }

    weak var delegate: TabViewCellDelegate?
    weak var tab: Tab?
    private var isFireModeEnabled: Bool = false

    var isCurrent = false
    var isDeleting = false
    var canDelete = false
    var isSelectionModeEnabled = false
    
    var isFireTab: Bool {
        tab?.fireTab ?? false
    }

    let background = RoundedRectangleView()
    let border = UIView()

    override func dragStateDidChange(_ dragState: UICollectionViewCell.DragState) {
        super.dragStateDidChange(dragState)
        
        switch dragState {
        case .none:
            selectionIndicator.isHidden = !isSelectionModeEnabled
            border.isHidden = false
            refreshSelectionAppearance()

        case .lifting, .dragging:
            selectionIndicator.isHidden = true
            border.isHidden = true
            border.layer.borderWidth = 0.0

        default: break
        }

        setNeedsLayout()
        setNeedsDisplay()
    }

    let favicon = UIImageView()
    let title = FadeOutLabel()
    let removeButton = BrowserChromeButton(.tabSwitcher)
    let unread = UIImageView()
    let selectionIndicator = UIImageView()

    // List view
    var link: FadeOutLabel?

    // Grid view
    var preview: UIImageView?

    /// Container for the Duck.ai rich tab grid card content (text/image/voice/empty).
    var richCardContainer: DuckAIGridCardView?

    /// File-ref token guarding the in-flight thumbnail load.
    private var currentThumbnailFileRef: String?
    private var thumbnailLoadTask: Task<Void, Never>?

    weak var previewAspectRatio: NSLayoutConstraint?
    var previewTopConstraint: NSLayoutConstraint?
    var previewBottomConstraint: NSLayoutConstraint?
    var previewTrailingConstraint: NSLayoutConstraint?

    let buttonContainer = UIView()
    var textButtonSpacing: NSLayoutConstraint?

    /// Note that `backgroundView` and `selectedBackgroundView` are provided by UICollectionViewCell and we don't use them for legacy and design reasons, so ignore them.
    func setupSubviews() {
        layer.masksToBounds = false

        applyShadows()

        preview?.layer.cornerRadius = Constants.previewCornerRadius
        preview?.layer.masksToBounds = true
        preview?.layer.cornerCurve = .continuous

        backgroundColor = .clear

        background.layer.cornerCurve = .continuous
        background.backgroundColor = .clear

        border.layer.cornerRadius = Constants.borderRadius
        border.layer.cornerCurve = .continuous

        layer.cornerRadius = Constants.cellCornerRadius
        layer.cornerCurve = .continuous

        favicon.layer.cornerRadius = Constants.faviconCornerRadius
        favicon.layer.cornerCurve = .continuous
        favicon.layer.masksToBounds = true
        favicon.image = DesignSystemImages.Glyphs.Size24.globe

        removeButton.addTarget(self, action: #selector(removeButtonValueChange), for: .allTouchEvents)
    }

    @objc private func removeButtonValueChange() {
        // When highlighted, set larger spacing between text and close button
        // to adjust for the highlight area, otherwise set text as close to the
        // icon as possible.

        let spacing = removeButton.isHighlighted ? Constants.removeButtonTextSpacingHighlighted : Constants.removeButtonTextSpacingRegular

        layoutIfNeeded()
        textButtonSpacing?.constant = spacing
        
        UIView.animate(withDuration: Constants.highlightAnimationDuration,
                       delay: 0.0,
                       options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.layoutIfNeeded()
        }
    }

    private func applyShadows() {
        layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = Constants.shadowRadius
        layer.shadowOffset = Constants.shadowOffset
    }

    private func updatePreviewToDisplay(image: UIImage) {
        let imageAspectRatio = image.size.width > 0 ? image.size.height / image.size.width : 1.0
        let containerAspectRatio = background.bounds.width > 0 ? (background.bounds.height - TabViewCell.Constants.cellHeaderHeight) / background.bounds.width : 1.0

        let strechContainerVerically = containerAspectRatio < imageAspectRatio

        if let constraint = previewAspectRatio {
            preview?.removeConstraint(constraint)
        }

        previewBottomConstraint?.isActive = !strechContainerVerically
        previewBottomConstraint?.constant = 0
        previewTrailingConstraint?.isActive = strechContainerVerically

        if let preview {
            previewAspectRatio = preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: imageAspectRatio)
            previewAspectRatio?.isActive = true
        }
    }

    private func updatePreviewToDisplayLogo() {
        if let constraint = previewAspectRatio {
            preview?.removeConstraint(constraint)
            previewAspectRatio = nil
        }

        previewBottomConstraint?.isActive = true
        previewBottomConstraint?.constant = Constants.previewPadding * 2
        previewTrailingConstraint?.isActive = true
    }

    private static func unreadImageAsset(accentColor: UIColor) -> UIImageAsset {

        func unreadImage(for style: UIUserInterfaceStyle) -> UIImage {
            let color = ThemeManager.shared.currentTheme.tabSwitcherCellBackgroundColor.resolvedColor(with: .init(userInterfaceStyle: style))
            let image = UIImage.stackedIconImage(withIconImage: UIImage(resource: .tabUnread),
                                                 borderWidth: Constants.unreadBorderWidth,
                                                 foregroundColor: accentColor,
                                                 borderColor: color)
            return image
        }

        let asset = UIImageAsset()

        asset.register(unreadImage(for: .dark), with: .init(userInterfaceStyle: .dark))
        asset.register(unreadImage(for: .light), with: .init(userInterfaceStyle: .light))

        return asset
    }

    private static let regularLogoImage: UIImage = {
        let image = UIImage(resource: .logo)
        let renderFormat = UIGraphicsImageRendererFormat.default()
        renderFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: Constants.cellLogoSize,
                                                            height: Constants.cellLogoSize),
                                               format: renderFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0,
                                  y: 0,
                                  width: Constants.cellLogoSize,
                                  height: Constants.cellLogoSize))
        }
    }()

    static func logoImage(for tab: Tab?) -> UIImage {
        if let tab, tab.fireTab {
            return DesignSystemImages.Color.Size96.fireTab
        } else {
            return regularLogoImage
        }
    }

    var logoImage: UIImage {
        Self.logoImage(for: tab)
    }
    
    var accentColor: UIColor {
        isFireTab ? UIColor(singleUseColor: .fireModeAccent) : UIColor(designSystemColor: .accent)
    }

    // MARK: - Programmatic Layout

    /// Creates all shared views and constrains background+border to contentView.
    /// Subclasses override, call super, then arrange the pre-created views
    /// (favicon, title, unread, selectionIndicator, removeButton) into their specific layout.
    func setupLayout() {
        background.translatesAutoresizingMaskIntoConstraints = false
        background.cornerRadius = Constants.cellCornerRadius
        background.borderWidth = Constants.cardBorderWidth
        background.borderColor = .clear
        contentView.addSubview(background)

        border.translatesAutoresizingMaskIntoConstraints = false
        border.isUserInteractionEnabled = false
        contentView.addSubview(border)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            border.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            border.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            border.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: Constants.borderOutset),
            border.heightAnchor.constraint(equalTo: contentView.heightAnchor, constant: Constants.borderOutset),
        ])

        favicon.translatesAutoresizingMaskIntoConstraints = false
        favicon.contentMode = .scaleAspectFit

        title.translatesAutoresizingMaskIntoConstraints = false
        title.lineBreakMode = .byClipping
        title.adjustsFontForContentSizeCategory = true
        title.isAccessibilityElement = true
        title.accessibilityTraits = [.button, .staticText]

        unread.translatesAutoresizingMaskIntoConstraints = false
        unread.contentMode = .scaleToFill
        unread.image = UIImage(resource: .tabUnread)
        unread.isUserInteractionEnabled = false
        unread.accessibilityLabel = UserText.tabCellUnreadAccessibility
        unread.isAccessibilityElement = false

        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.contentMode = .center
        selectionIndicator.clipsToBounds = true

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.accessibilityLabel = UserText.tabCellCloseButtonAccessibility
        removeButton.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        removeButton.addTarget(self, action: #selector(deleteTab), for: .touchUpInside)

        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.setContentHuggingPriority(.defaultHigh + 250, for: .horizontal)
        buttonContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        buttonContainer.addSubview(selectionIndicator)
        buttonContainer.addSubview(removeButton)

        NSLayoutConstraint.activate([
            selectionIndicator.widthAnchor.constraint(equalToConstant: Constants.selectionIndicatorSize),
            selectionIndicator.heightAnchor.constraint(equalToConstant: Constants.selectionIndicatorSize),
            selectionIndicator.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            selectionIndicator.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
        ])
    }

    func finalizeSetup() {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(recognizer:)))
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
        setupSubviews()
    }

    var startX: CGFloat = 0
    @objc func handleSwipe(recognizer: UIGestureRecognizer) {
        let currentLocation = recognizer.location(in: nil)
        let diff = startX - currentLocation.x

        switch recognizer.state {

        case .began:
            startX = currentLocation.x
            delegate?.tabViewCellDidBeginSwipe(self)

        case .changed:
            let offset = max(0, startX - currentLocation.x)
            transform = CGAffineTransform.identity.translatedBy(x: -offset, y: 0)
            if diff > removeThreshold {
                if !canDelete {
                    makeTranslucent()
                    UIImpactFeedbackGenerator().impactOccurred()
                }
                canDelete = true
            } else {
                if canDelete {
                    makeOpaque()
                }
                canDelete = false
            }

        case .ended:
            if canDelete {
                startRemoveAnimation()
            } else {
                startCancelAnimation()
            }
            canDelete = false
            delegate?.tabViewCellDidEndSwipe(self)

        case .cancelled:
            startCancelAnimation()
            canDelete = false
            delegate?.tabViewCellDidEndSwipe(self)

        default: break

        }
    }

    private func makeTranslucent() {
        UIView.animate(withDuration: Constants.swipeAnimationDuration, animations: {
            self.alpha = Constants.swipeToDeleteAlpha
        })
    }

    private func makeOpaque() {
        UIView.animate(withDuration: Constants.swipeAnimationDuration, animations: {
            self.alpha = 1.0
        })
    }

    private func startRemoveAnimation() {
        self.isDeleting = true
        Pixel.fire(pixel: .tabSwitcherSwipeCloseTab, withAdditionalParameters: [
            PixelParameters.browsingMode: isFireTab ? BrowsingMode.fire.pixelParamValue : BrowsingMode.normal.pixelParamValue
        ])
        self.deleteTab()
        UIView.animate(withDuration: Constants.swipeAnimationDuration, animations: {
            self.transform = CGAffineTransform.identity.translatedBy(x: -self.frame.width, y: 0)
        }, completion: { _ in
            self.isHidden = true
        })
    }

    private func startCancelAnimation() {
        UIView.animate(withDuration: Constants.swipeAnimationDuration) {
            self.transform = .identity
        }
    }

    func refreshSelectionAppearance() {
        updateSelectionIndicator(selectionIndicator)
        updateCurrentTabBorder()
    }

    func closeTab() {
        guard let tab = tab else { return }
        fireTabCloseSegmentationPixel()
        self.delegate?.deleteTab(tab: tab)
    }

    @objc func deleteTab() {
        Pixel.fire(pixel: .tabSwitcherClickCloseTab, withAdditionalParameters: [
            PixelParameters.browsingMode: isFireTab ? BrowsingMode.fire.pixelParamValue : BrowsingMode.normal.pixelParamValue
        ])
        closeTab()
    }

    private func fireTabCloseSegmentationPixel() {
        guard let tab else { return }
        if tab.isAITab {
            DailyPixel.fireDailyAndCount(pixel: .tabManagerCloseAITab)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .tabManagerCloseWebTab)
        }
    }

    func updateSelectionIndicator(_ image: UIImageView) {
        if !isSelected {
            image.image = DesignSystemImages.Glyphs.Size24.shapeCircle
        } else {
            image.image = DesignSystemImages.Recolorable.Size24.check.applyPalleteColorsToSymbol(
                foreground: UIColor(designSystemColor: .accentContentPrimary),
                background: accentColor,
            )
        }
    }

    func updateCurrentTabBorder() {
        var borderColor: UIColor {
            if isFireTab {
                return UIColor(singleUseColor: .fireModeAccent)
            }
            return isSelectionModeEnabled ? UIColor(designSystemColor: .accent) : UIColor(designSystemColor: .decorationTertiary)
        }
        let showBorder = isSelectionModeEnabled ? isSelected : isCurrent
        border.layer.borderColor = borderColor.cgColor
        border.layer.borderWidth = showBorder ? Constants.selectedBorderWidth : Constants.unselectedBorderWidth
    }

    func updateUIForSelectionMode(_ removeButton: UIButton, _ selectionIndicator: UIImageView) {

        if isSelectionModeEnabled {
            removeButton.isHidden = true
            selectionIndicator.isHidden = false
            updateSelectionIndicator(selectionIndicator)
        } else {
            selectionIndicator.isHidden = true
        }
    }

    func update(withTab tab: Tab,
                isSelectionModeEnabled: Bool,
                preview: UIImage?,
                isFireModeEnabled: Bool,
                duckAIGridItem: DuckAIGridItem? = nil,
                thumbnailLoader: DuckAIThumbnailLoading? = nil) {
        self.tab = tab
        self.isSelectionModeEnabled = isSelectionModeEnabled
        self.isFireModeEnabled = isFireModeEnabled

        if !isDeleting {
            isHidden = false
        }
        isCurrent = delegate?.isCurrent(tab: tab) ?? false

        decorate()

        updateCurrentTabBorder()

        if let link = tab.link {
            removeButton.accessibilityLabel = UserText.closeTab(withTitle: link.displayTitle, atAddress: link.url.host ?? "")
            title.accessibilityLabel = UserText.openTab(withTitle: link.displayTitle, atAddress: link.url.host ?? "")
            title.text = tab.link?.displayTitle
        }

        unread.isHidden = tab.viewed

        // Reset rich-card / preview visibility on every reuse; cancel any in-flight
        // thumbnail load and clear the cached image so the next item starts clean.
        richCardContainer?.isHidden = true
        self.preview?.isHidden = false
        cancelThumbnailLoad()
        richCardContainer?.setThumbnail(nil)

        if tab.isAITab {
            let aiChatTitle = UserText.omnibarFullAIChatModeDisplayTitle
            let conversationTitle = tab.aiChatConversationTitle
            let isListMode = link != nil
            // When the rich card is rendered, the conversation title lives inside the
            // card body, so the cell header always reads "Duck.ai" — same as list mode.
            let showsRichCard = duckAIGridItem != nil
            let displayTitle = (isListMode || showsRichCard) ? aiChatTitle : (conversationTitle ?? aiChatTitle)
            removeButton.accessibilityLabel = UserText.closeTab(withTitle: conversationTitle ?? aiChatTitle, atAddress: "")
            title.accessibilityLabel = UserText.openTab(withTitle: conversationTitle ?? aiChatTitle, atAddress: "")
            title.text = displayTitle
            favicon.image = UIImage(resource: .duckAIDefault)

            if let conversationTitle, isListMode {
                link?.isHidden = false
                link?.text = conversationTitle
            } else {
                link?.isHidden = true
            }

            if let item = duckAIGridItem {
                richCardContainer?.configure(with: item)
                richCardContainer?.isHidden = false
                self.preview?.isHidden = true
                startThumbnailLoadIfNeeded(for: item, loader: thumbnailLoader)
            } else if let preview = preview {
                self.updatePreviewToDisplay(image: preview)
                self.preview?.contentMode = .scaleAspectFill
                self.preview?.image = preview
            } else {
                self.preview?.image = nil
            }

            removeButton.isHidden = false

        } else if tab.link == nil {
            updatePreviewToDisplayLogo()
            self.preview?.image = logoImage
            self.preview?.contentMode = .center

            updateEmptyTabLabel(for: tab)
            link?.isHidden = false
            link?.text = UserText.homeTabSearchAndFavorites
            favicon.image = UIImage(resource: .logo)
            unread.isHidden = true
            self.preview?.isHidden = !tab.viewed
            title.isHidden = !tab.viewed
            favicon.isHidden = !tab.viewed
            removeButton.isHidden = !tab.viewed

        } else {
            link?.isHidden = false
            link?.text = tab.link?.url.absoluteString ?? ""

            // Duck Player videos
            if let url = tab.link?.url, url.isDuckPlayer {
                favicon.image = UIImage(resource: .duckPlayerURLIcon)
            } else {
                favicon.loadFavicon(forDomain: tab.link?.url.host, usingCache: .tabs)
            }

            if let preview = preview {
                self.updatePreviewToDisplay(image: preview)
                self.preview?.contentMode = .scaleAspectFill
                self.preview?.image = preview
            } else {
                self.preview?.image = nil
            }

            removeButton.isHidden = false

        }

        updateUIForSelectionMode(removeButton, selectionIndicator)

        // Include the rich card between the header title and close button so VoiceOver
        // reads the conversation title/snippet that lives inside the card body.
        if let richCard = richCardContainer, !richCard.isHidden {
            accessibilityElements = [title as Any, richCard as Any, removeButton as Any]
        } else {
            accessibilityElements = [title as Any, removeButton as Any]
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        cancelThumbnailLoad()
        richCardContainer?.setThumbnail(nil)
    }

    private func cancelThumbnailLoad() {
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        currentThumbnailFileRef = nil
    }

    private func startThumbnailLoadIfNeeded(for item: DuckAIGridItem,
                                            loader: DuckAIThumbnailLoading?) {
        guard case .image(_, let fileRef) = item, let loader else { return }
        currentThumbnailFileRef = fileRef
        thumbnailLoadTask = Task { @MainActor [weak self, weak loader] in
            guard let loader else { return }
            let image = await loader.loadImage(fileRef: fileRef)
            // Drop the result on cell reuse / item change. Identity check is on the
            // file ref token, not just `Task.isCancelled`, so we also discard stale
            // loads when a new image item replaced this one without a full reuse.
            guard let self,
                  !Task.isCancelled,
                  self.currentThumbnailFileRef == fileRef else { return }
            self.richCardContainer?.setThumbnail(image)
        }
    }

    private func updateEmptyTabLabel(for tab: Tab) {
        if isFireModeEnabled {
            title.text = tab.fireTab ? UserText.fireTabTitle : UserText.newTabTitle
            title.accessibilityLabel = tab.fireTab ? UserText.openNewFireTab : UserText.openNewTab
        } else {
            title.text = UserText.homeTabTitle
            title.accessibilityLabel = UserText.openHomeTab
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            decorate()
            refreshSelectionAppearance()
        }
    }

    private func decorate() {
        border.layer.borderColor = UIColor(designSystemColor: .textPrimary).cgColor
        unread.image = Self.unreadImageAsset(accentColor: accentColor).image(with: .current)
        removeButton.tintColor = UIColor(designSystemColor: .icons)

        background.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        title.primaryColor = UIColor(designSystemColor: .textPrimary)
        link?.primaryColor = UIColor(designSystemColor: .textSecondary)

        background.superview?.backgroundColor = .clear
    }
}

extension TabViewCell: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.y) < abs(velocity.x)
    }

}

// MARK: - HitTestStackView

final class HitTestStackView: UIStackView {

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for subview in arrangedSubviews where subview.point(inside: point, with: event) {
            return true
        }
        return super.point(inside: point, with: event)
    }

}
