//
//  AIChatImageAttachmentThumbnailView.swift
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

import AppKit
import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons

/// A square thumbnail view that displays an attached image with a remove button overlay.
final class AIChatImageAttachmentThumbnailView: NSView {

    private enum Constants {
        static let thumbnailSize: CGFloat = 50
        static let cornerRadius: CGFloat = 12
        static let borderWidth: CGFloat = 2
        static let removeButtonSize: CGFloat = 20
        static let removeButtonInset: CGFloat = 4
        /// How far the remove button extends beyond the thumbnail edge.
        static let removeButtonOverflow: CGFloat = 8
        static let shadowRadius: CGFloat = 4
        static let shadowOpacity: Float = 0.3
        static let shadowOffset = CGSize(width: 0, height: -2)

        // Remove button colors (defined in Assets.xcassets)
        static let removeButtonBackgroundColorName = "AIChatRemoveButtonBackgroundColor"
        static let removeButtonIconColorName = "AIChatRemoveButtonIconColor"
    }

    /// Total height of the view including the remove button overflow.
    static let totalHeight: CGFloat = Constants.thumbnailSize + Constants.removeButtonOverflow

    let attachmentId: UUID
    var onRemove: ((UUID) -> Void)?
    private let imageContainerView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.cornerRadius = Constants.cornerRadius
        view.layer?.borderWidth = Constants.borderWidth
        return view
    }()

    private let shadowBackingView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.shadow = NSShadow()
        view.layer?.cornerRadius = Constants.cornerRadius
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowRadius = Constants.shadowRadius
        view.layer?.shadowOpacity = Constants.shadowOpacity
        view.layer?.shadowOffset = Constants.shadowOffset
        view.layer?.masksToBounds = false
        return view
    }()

    private let imageLayer: CALayer = {
        let layer = CALayer()
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        return layer
    }()

    private let removeButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.title = ""
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(UserText.aiChatRemoveAttachmentButtonAccessibility)
        return button
    }()

    init(attachment: AIChatImageAttachment) {
        self.attachmentId = attachment.id
        super.init(frame: .zero)
        setImage(attachment.image)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: Constants.thumbnailSize + Constants.removeButtonOverflow,
            height: Constants.thumbnailSize + Constants.removeButtonOverflow
        )
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        configureRemoveButtonImage()
        imageContainerView.layer?.addSublayer(imageLayer)
        addSubview(shadowBackingView)
        addSubview(imageContainerView)
        addSubview(removeButton)

        removeButton.wantsLayer = true
        removeButton.layer?.cornerRadius = Constants.removeButtonSize / 2
        removeButton.layer?.borderWidth = 2
        removeButton.layer?.masksToBounds = true
        removeButton.toolTip = UserText.aiChatRemoveAttachmentButtonTooltip

        NSLayoutConstraint.activate([
            shadowBackingView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            shadowBackingView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            shadowBackingView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            shadowBackingView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            imageContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageContainerView.widthAnchor.constraint(equalToConstant: Constants.thumbnailSize),
            imageContainerView.heightAnchor.constraint(equalToConstant: Constants.thumbnailSize),

            removeButton.centerXAnchor.constraint(equalTo: imageContainerView.trailingAnchor, constant: -Constants.removeButtonInset),
            removeButton.centerYAnchor.constraint(equalTo: imageContainerView.topAnchor, constant: Constants.removeButtonInset),
            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),

            widthAnchor.constraint(equalToConstant: Constants.thumbnailSize + Constants.removeButtonOverflow),
            heightAnchor.constraint(equalToConstant: Constants.thumbnailSize + Constants.removeButtonOverflow),
        ])

        updateAppearance()
    }

    override func layout() {
        super.layout()
        imageLayer.frame = imageContainerView.bounds
    }

    // MARK: - Hit Testing & Mouse Events

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always return self to capture all mouse events.
        // NSButton cannot be returned here because MouseBlockingBackgroundView
        // manually forwards events, which conflicts with NSButton's modal tracking.
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func mouseUp(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(locationInView) else { return }

        if removeButton.frame.contains(locationInView) {
            onRemove?(attachmentId)
        }
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // MARK: - Image

    private func setImage(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageLayer.contents = image
            return
        }
        imageLayer.contents = cgImage
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    /// Updates the displayed image. Used when replacing placeholder with loaded image.
    func updateImage(_ image: NSImage) {
        setImage(image)
    }

    private func configureRemoveButtonImage() {
        removeButton.image = DesignSystemImages.Glyphs.Size16.clearSolid
        removeButton.imageScaling = .scaleNone
    }

    // MARK: - Appearance

    private func updateAppearance() {
        NSAppearance.withAppAppearance {
            let surfaceColor = NSColor(designSystemColor: .surfacePrimary)
            let removeButtonBackgroundColor = NSColor(named: Constants.removeButtonBackgroundColorName) ?? .white
            let removeButtonIconColor = NSColor(named: Constants.removeButtonIconColorName) ?? .black

            imageContainerView.layer?.borderColor = surfaceColor.cgColor
            shadowBackingView.layer?.backgroundColor = surfaceColor.cgColor
            removeButton.layer?.backgroundColor = removeButtonBackgroundColor.cgColor
            removeButton.layer?.borderColor = removeButtonBackgroundColor.cgColor
            removeButton.contentTintColor = removeButtonIconColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}
