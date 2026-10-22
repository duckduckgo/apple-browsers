//
//  TabSwitcherCardView.swift
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

import UIKit
import DesignResourcesKit

/// The page as a card that morphs between filling the screen and sitting in its tab switcher cell.
/// Lays itself out in the coordinate space of the screen; add it to a full-screen superview.
final class TabSwitcherCardView: UIView {

    /// In a grid the page shrinks into the cell's preview; in a list it fades into the row as the card collapses to it.
    enum CellStyle {
        case grid
        case list

        static var current: CellStyle {
            DefaultTabSwitcherSettings().isGridViewEnabled ? .grid : .list
        }
    }

    let cellStyle: CellStyle

    private let shadow = UIView()
    private let card = UIView()
    private let contentClip = UIView()
    private let content: UIView
    private let border = UIView()
    private var header: UIView?
    private var face: UIView?
    private var dax: Dax?

    /// Dax travels as a layer of its own. `container` is Dax's circle; the cell's logo image has transparent
    /// padding, so it is laid out around the circle rather than filling it. `cover` hides Dax in the page snapshot.
    /// Dax's frames are set on each pose rather than left to autoresizing, whose rounding drifts over a drag.
    private struct Dax {
        let container: UIView
        let pageDax: UIView?
        let cellDax: UIImageView
        let cellImageCircle: CGRect
        let circleInScreen: CGRect
        let cover: UIView?
    }

    private let contentFrameInScreen: CGRect
    private let contentCropTop: CGFloat
    private let screenBounds: CGRect
    private let screenCornerRadius: CGFloat

    private(set) var cardFrame: CGRect = .zero

    /// - Parameters:
    ///   - content: A snapshot of the page, positioned at `contentFrameInScreen` when full screen.
    ///   - contentCropTop: How much of the snapshot's top the stored tab preview leaves out.
    init(content: UIView,
         contentFrameInScreen: CGRect,
         contentCropTop: CGFloat,
         screenBounds: CGRect,
         screenCornerRadius: CGFloat,
         screenBackgroundColor: UIColor,
         cellStyle: CellStyle = .current) {
        self.content = content
        self.cellStyle = cellStyle
        self.contentFrameInScreen = contentFrameInScreen
        self.contentCropTop = contentCropTop
        self.screenBounds = screenBounds
        self.screenCornerRadius = screenCornerRadius
        super.init(frame: screenBounds)

        isUserInteractionEnabled = false
        // Fading the card out must not reveal the solid surface the shadow is cast from.
        layer.allowsGroupOpacity = true

        shadow.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        shadow.layer.cornerCurve = .continuous
        shadow.layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        shadow.layer.shadowRadius = TabViewCell.Constants.shadowRadius
        shadow.layer.shadowOffset = TabViewCell.Constants.shadowOffset
        shadow.layer.shadowOpacity = 0
        addSubview(shadow)

        card.clipsToBounds = true
        card.layer.cornerCurve = .continuous
        card.backgroundColor = screenBackgroundColor
        addSubview(card)

        contentClip.clipsToBounds = true
        contentClip.layer.cornerCurve = .continuous
        card.addSubview(contentClip)
        contentClip.addSubview(content)

        border.backgroundColor = .clear
        border.layer.cornerCurve = .continuous
        border.layer.cornerRadius = TabViewCell.Constants.borderRadius
        border.alpha = 0
        addSubview(border)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The page at `frame`, a scaled-down copy of the whole screen.
    func applyScreenPose(cardFrame frame: CGRect) {
        let scale = screenBounds.width > 0 ? frame.width / screenBounds.width : 1
        let radius = screenCornerRadius * scale
        cardFrame = frame
        card.frame = frame
        card.layer.cornerRadius = radius
        shadow.frame = frame
        shadow.layer.cornerRadius = radius
        shadow.layer.shadowOpacity = 0
        shadow.alpha = 0
        contentClip.frame = card.bounds
        contentClip.layer.cornerRadius = radius
        content.frame = CGRect(x: (contentFrameInScreen.minX - screenBounds.minX) * scale,
                               y: (contentFrameInScreen.minY - screenBounds.minY) * scale,
                               width: contentFrameInScreen.width * scale,
                               height: contentFrameInScreen.height * scale)
        layOutBorder(around: frame)
        header?.alpha = 0
        if let dax {
            layOut(dax, circle: CGRect(x: (dax.circleInScreen.minX - screenBounds.minX) * scale,
                                       y: (dax.circleInScreen.minY - screenBounds.minY) * scale,
                                       width: dax.circleInScreen.width * scale,
                                       height: dax.circleInScreen.height * scale))
            dax.pageDax?.alpha = 1
            dax.cellDax.alpha = dax.pageDax == nil ? 1 : 0
            if cellStyle == .grid {
                contentClip.alpha = 1
            }
        }
    }

    /// The page exactly as `TabViewGridCell` draws it at `cellFrame`, or at a list row's size. A list row shows
    /// none of the page, so callers fade it with `setPage(visible:)`.
    func applyCellPose(cellFrame: CGRect) {
        let layout = cellStyle == .grid
            ? TabSwitcherSwipeUpGeometry.previewLayout(forCellSize: cellFrame.size,
                                                       contentSize: contentFrameInScreen.size,
                                                       contentCropTop: contentCropTop)
            : TabSwitcherSwipeUpGeometry.listPreviewLayout(forCellSize: cellFrame.size,
                                                           contentSize: contentFrameInScreen.size,
                                                           contentCropTop: contentCropTop)
        cardFrame = cellFrame
        card.frame = cellFrame
        card.layer.cornerRadius = TabViewCell.Constants.cellCornerRadius
        card.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)
        shadow.frame = cellFrame
        shadow.layer.cornerRadius = TabViewCell.Constants.cellCornerRadius
        shadow.layer.shadowOpacity = 1
        shadow.alpha = 1
        contentClip.frame = layout.clipFrame
        contentClip.layer.cornerRadius = cellStyle == .grid ? TabViewCell.Constants.previewCornerRadius : TabViewCell.Constants.cellCornerRadius
        content.frame = layout.contentFrame
        layOutBorder(around: cellFrame)
        if let dax {
            switch cellStyle {
            case .grid:
                let imageFrame = TabSwitcherSwipeUpGeometry.logoFrame(inPreviewClip: layout.clipFrame,
                                                                      logoSize: dax.cellDax.image?.size ?? .zero)
                layOut(dax, circle: Self.denormalize(dax.cellImageCircle, in: imageFrame))
            case .list:
                layOut(dax, circle: TabSwitcherSwipeUpGeometry.faviconFrame(inListCellOfSize: cellFrame.size))
            }
            dax.pageDax?.alpha = 0
            dax.cellDax.alpha = 1
            if cellStyle == .grid {
                contentClip.alpha = 0
            }
        }
    }

    /// Carries Dax on its own path between its circle on the page and the cell's logo, while the rest of the
    /// page fades, so it reads as one Dax travelling between the two. `pageDax` is Dax as the page draws it,
    /// when it can be captured; `pageBackground` is what the page draws behind it, to hide Dax in the page
    /// snapshot. Call before applying a pose.
    func installDax(circleInScreen: CGRect, pageDax: UIView?, pageBackground: UIImage?, cellImage: UIImage) {
        var cover: UIView?
        if let pageBackground {
            // The circle is drawn into the image, since a corner radius wouldn't shrink with the card.
            let size = circleInScreen.size
            let coverImage = UIGraphicsImageRenderer(size: size).image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
                pageBackground.draw(in: CGRect(origin: .zero, size: size))
            }
            let coverView = UIImageView(image: coverImage)
            content.addSubview(coverView)
            cover = coverView
        }

        let container = UIView()
        let cellDax = UIImageView(image: cellImage)
        container.addSubview(cellDax)
        if let pageDax {
            // An image mask, unlike a corner radius or shape layer, scales along with the spring.
            pageDax.mask = UIImageView(image: UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
                context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 100, height: 100))
            })
            container.addSubview(pageDax)
        }
        card.insertSubview(container, aboveSubview: contentClip)
        dax = Dax(container: container,
                  pageDax: pageDax,
                  cellDax: cellDax,
                  cellImageCircle: Self.visibleBounds(of: cellImage),
                  circleInScreen: circleInScreen,
                  cover: cover)
    }

    /// Places Dax at `circle`, in the card's coordinates, and its cover over the page snapshot's own Dax.
    /// Expects `content` to be in place already.
    private func layOut(_ dax: Dax, circle: CGRect) {
        let bounds = CGRect(origin: .zero, size: circle.size)
        dax.container.frame = circle
        dax.cellDax.frame = Self.imageFrame(around: bounds, circle: dax.cellImageCircle)
        dax.pageDax?.frame = bounds
        dax.pageDax?.mask?.frame = bounds
        if let cover = dax.cover {
            let scale = contentFrameInScreen.width > 0 ? content.frame.width / contentFrameInScreen.width : 1
            let circleInContent = dax.circleInScreen.offsetBy(dx: -contentFrameInScreen.minX, dy: -contentFrameInScreen.minY)
            // Slightly larger than the circle so its anti-aliased edge doesn't show around the travelling Dax.
            cover.frame = CGRect(x: circleInContent.minX * scale,
                                 y: circleInContent.minY * scale,
                                 width: circleInContent.width * scale,
                                 height: circleInContent.height * scale).insetBy(dx: -1, dy: -1)
        }
    }

    /// The opaque part of the image, as fractions of its size.
    private static func visibleBounds(of image: UIImage) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let side = 64
        var alpha = [UInt8](repeating: 0, count: side * side)
        // Drawn through a renderer because vector assets have no `cgImage` of their own.
        let rendered = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        let drawn: Bool = alpha.withUnsafeMutableBytes { buffer in
            guard let cgImage = rendered.cgImage,
                  let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return full }
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where alpha[y * side + x] > 16 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return full }
        let unit = 1 / CGFloat(side)
        return CGRect(x: CGFloat(minX) * unit, y: CGFloat(minY) * unit,
                      width: CGFloat(maxX - minX + 1) * unit, height: CGFloat(maxY - minY + 1) * unit)
    }

    private static func denormalize(_ unitRect: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + unitRect.minX * frame.width,
               y: frame.minY + unitRect.minY * frame.height,
               width: unitRect.width * frame.width,
               height: unitRect.height * frame.height)
    }

    /// The frame an image needs for its visible part, `circle`, to fill `bounds`.
    private static func imageFrame(around bounds: CGRect, circle: CGRect) -> CGRect {
        guard circle.width > 0, circle.height > 0 else { return bounds }
        let width = bounds.width / circle.width
        let height = bounds.height / circle.height
        return CGRect(x: bounds.minX - circle.minX * width, y: bounds.minY - circle.minY * height, width: width, height: height)
    }

    func setChrome(visible: Bool) {
        header?.alpha = visible ? 1 : 0
        border.alpha = visible ? 1 : 0
    }

    /// Fading the page along with the card's spring would leave it washed out for most of the way, so a list
    /// row's page fades on a schedule of its own.
    func setPage(visible: Bool) {
        contentClip.alpha = visible ? 1 : 0
    }

    func setBackgroundColor(_ color: UIColor) {
        card.backgroundColor = color
    }

    /// Copies the cell's header and selection outline. The header is drawn on the CPU rather than
    /// snapshotted: a snapshot that waits for screen updates stalls the render server mid-animation.
    func installChrome(from cell: TabViewCell, isVisible: Bool) {
        if cell is TabViewGridCell {
            cell.layoutIfNeeded()
            let headerHeight = TabViewGridCell.Constants.headerHeight
            let source = cell.background
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: source.bounds.width, height: headerHeight))
            let image = renderer.image { context in
                source.layer.render(in: context.cgContext)
            }
            let header = UIImageView(image: image)
            header.frame = CGRect(x: 0, y: 0, width: card.bounds.width, height: headerHeight)
            header.autoresizingMask = [.flexibleWidth]
            header.contentMode = .topLeft
            header.clipsToBounds = true
            card.addSubview(header)
            self.header = header
        }

        // A grid cell draws the new tab page as a logo, which the travelling Dax already stands in for.
        if dax == nil || cellStyle == .list {
            installFace(from: cell)
        }

        if !cell.border.isHidden, cell.border.layer.borderWidth > 0 {
            border.layer.borderColor = cell.border.layer.borderColor
            border.layer.borderWidth = cell.border.layer.borderWidth
        }
        setChrome(visible: isVisible)
    }

    /// The real cell's rendering, for content whose live snapshot doesn't match the cell (the new tab page
    /// is drawn as a logo, for one). Crossfading to it as the card lands avoids a pop at the hand-off.
    func setFace(visible: Bool) {
        face?.alpha = visible ? 1 : 0
    }

    private func installFace(from cell: TabViewCell) {
        let source = cell.background
        guard source.bounds.width > 0, source.bounds.height > 0 else { return }
        let image = UIGraphicsImageRenderer(bounds: source.bounds).image { context in
            source.layer.render(in: context.cgContext)
        }
        let face = UIImageView(image: image)
        face.frame = card.bounds
        face.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if cellStyle == .list {
            // Stretched to a growing card, the row's text would balloon before it fades.
            face.contentMode = .topLeft
            face.clipsToBounds = true
        }
        face.alpha = 0
        if let header {
            card.insertSubview(face, belowSubview: header)
        } else {
            card.addSubview(face)
        }
        self.face = face
    }

    private func layOutBorder(around frame: CGRect) {
        let outset = TabViewCell.Constants.borderOutset / 2
        border.frame = frame.insetBy(dx: -outset, dy: -outset)
    }
}
