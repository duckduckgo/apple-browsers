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

protocol TabViewCellDelegate: AnyObject {

    func deleteTab(tab: Tab)

    func isCurrent(tab: Tab) -> Bool
    
}

final class TabViewCell: UICollectionViewCell {

    struct Constants {

        static let swipeToDeleteAlpha: CGFloat = 0.5

        static let borderRadius: CGFloat = 14.0

        static let cellCornerRadius: CGFloat = 12.0
        static let cellHeaderHeight: CGFloat = 36.0 + 4.0 // height + top padding
        static let cellLogoSize: CGFloat = 68.0

        static let previewCornerRadius: CGFloat = 8.0

        static let selectedBorderWidth: CGFloat = 2.0
        static let unselectedBorderWidth: CGFloat = 0.0
        static let previewPadding: CGFloat = 4.0
    }

    var removeThreshold: CGFloat {
        return frame.width / 3
    }

    weak var delegate: TabViewCellDelegate?
    weak var tab: Tab?

    var isCurrent = false
    var isDeleting = false
    var canDelete = false
    var isSelectionModeEnabled = false

    static let gridReuseIdentifier = "TabViewGridCell"
    static let listReuseIdentifier = "TabViewListCell"

    @IBOutlet weak var background: UIView!
    @IBOutlet weak var border: UIView!

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

    @IBOutlet weak var favicon: UIImageView!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var removeButton: EnlargedHitAreaButton!
    @IBOutlet weak var unread: UIImageView!
    @IBOutlet weak var selectionIndicator: UIImageView!

    // List view
    @IBOutlet weak var link: UILabel?

    // Grid view
    @IBOutlet weak var preview: UIImageView?

    weak var previewAspectRatio: NSLayoutConstraint?
    @IBOutlet var previewTopConstraint: NSLayoutConstraint?
    @IBOutlet var previewBottomConstraint: NSLayoutConstraint?
    @IBOutlet var previewTrailingConstraint: NSLayoutConstraint?

    /// Note that `backgroundView` and `selectedBackgroundView` are provided by UICollectionViewCell and we don't use them for legacy and design reasons, so ignore them.
    func setupSubviews() {
        layer.masksToBounds = false

        applyShadows()

        preview?.layer.cornerRadius = Constants.previewCornerRadius
        preview?.layer.masksToBounds = true

        backgroundColor = .clear
        
        background?.layer.cornerRadius = Constants.cellCornerRadius
        background?.backgroundColor = .clear

        border.layer.cornerRadius = Constants.borderRadius

        layer.cornerRadius = Constants.cellCornerRadius

        unread.tintColor = UIColor(designSystemColor: .accent)

        favicon.layer.cornerRadius = 4
        favicon.layer.masksToBounds = true

        removeButton.additionalHitTestSize = 4
    }

    private func applyShadows() {
        layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 12.0
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private func updatePreviewToDisplay(image: UIImage) {
        let imageAspectRatio = image.size.height / image.size.width
        let containerAspectRatio = (background.bounds.height - TabViewCell.Constants.cellHeaderHeight) / background.bounds.width

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

    private static var unreadImageAsset: UIImageAsset {

        func unreadImage(for style: UIUserInterfaceStyle) -> UIImage {
            let color = ThemeManager.shared.currentTheme.tabSwitcherCellBackgroundColor.resolvedColor(with: .init(userInterfaceStyle: style))
            let image = UIImage.stackedIconImage(withIconImage: UIImage(resource: .tabUnread),
                                                 borderWidth: 6.0,
                                                 foregroundColor: UIColor(designSystemColor: .accent),
                                                 borderColor: color)
            return image
        }

        let asset = UIImageAsset()

        asset.register(unreadImage(for: .dark), with: .init(userInterfaceStyle: .dark))
        asset.register(unreadImage(for: .light), with: .init(userInterfaceStyle: .light))

        return asset
    }

    static let logoImage: UIImage = {
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

    override func awakeFromNib() {
        super.awakeFromNib()
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

        case .cancelled:
            startCancelAnimation()
            canDelete = false

        default: break

        }
    }

    private func makeTranslucent() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = Constants.swipeToDeleteAlpha
        })
    }

    private func makeOpaque() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 1.0
        })
    }

    private func startRemoveAnimation() {
        self.isDeleting = true
        Pixel.fire(pixel: .tabSwitcherSwipeCloseTab)
        self.deleteTab()
        UIView.animate(withDuration: 0.2, animations: {
            self.transform = CGAffineTransform.identity.translatedBy(x: -self.frame.width, y: 0)
        }, completion: { _ in
            self.isHidden = true
        })
    }

    private func startCancelAnimation() {
        UIView.animate(withDuration: 0.2) {
            self.transform = .identity
        }
    }

    func refreshSelectionAppearance() {
        updateSelectionIndicator(selectionIndicator)
        updateCurrentTabBorder()
    }

    func closeTab() {
        guard let tab = tab else { return }
        self.delegate?.deleteTab(tab: tab)
    }

    @IBAction func deleteTab() {
        Pixel.fire(pixel: .tabSwitcherClickCloseTab)
        closeTab()
    }

    func updateSelectionIndicator(_ image: UIImageView) {
        if !isSelected {
            image.image = DesignSystemImages.Glyphs.Size24.shapeCircle
        } else {
            image.image = DesignSystemImages.Recolorable.Size24.check.applyPalleteColorsToSymbol(
                foreground: UIColor(designSystemColor: .accentContentPrimary),
                background: UIColor(designSystemColor: .accent),
            )
        }
    }

    func updateCurrentTabBorder() {
        let showBorder = isSelectionModeEnabled ? isSelected : isCurrent
        border.layer.borderColor = UIColor(designSystemColor: isSelectionModeEnabled ? .accent : .decorationTertiary).cgColor
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
                preview: UIImage?) {
        accessibilityElements = [ title as Any, removeButton as Any ]

        self.tab = tab
        self.isSelectionModeEnabled = isSelectionModeEnabled

        if !isDeleting {
            isHidden = false
        }
        isCurrent = delegate?.isCurrent(tab: tab) ?? false

        decorate()

        updateCurrentTabBorder()

        removeButton.setImage(DesignSystemImages.Glyphs.Size16.closeSolidAlt, for: .normal)
        if let link = tab.link {
            removeButton.accessibilityLabel = UserText.closeTab(withTitle: link.displayTitle, atAddress: link.url.host ?? "")
            title.accessibilityLabel = UserText.openTab(withTitle: link.displayTitle, atAddress: link.url.host ?? "")
            title.text = tab.link?.displayTitle
        }

        unread.isHidden = tab.viewed

        if tab.link == nil {
            updatePreviewToDisplayLogo()
            self.preview?.image = Self.logoImage
            self.preview?.contentMode = .center

            link?.text = UserText.homeTabSearchAndFavorites
            title.text = UserText.homeTabTitle
            favicon.image = UIImage(resource: .logo)
            unread.isHidden = true
            self.preview?.isHidden = !tab.viewed
            title.isHidden = !tab.viewed
            favicon.isHidden = !tab.viewed
            removeButton.isHidden = !tab.viewed

        } else {
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
        unread.image = Self.unreadImageAsset.image(with: .current)
        removeButton.tintColor = UIColor(designSystemColor: .icons)

        background.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        title.textColor = UIColor(designSystemColor: .textPrimary)

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

final class HitTestStackView: UIStackView {

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for subview in arrangedSubviews where subview.point(inside: point, with: event) {
            return true
        }
        return super.point(inside: point, with: event)
    }

}
