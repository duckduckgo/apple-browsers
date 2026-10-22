//
//  TabSwitcherSwipeUpGeometry.swift
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

/// Where the page card sits while the user drags the bottom address bar upwards, measured from Safari on
/// iOS 26 frame by frame. The card stays centred horizontally and keeps the screen's proportions; its
/// bottom edge rises a little faster than the finger at first, then resists as the card nears its smallest.
enum TabSwitcherSwipeUpGeometry {

    /// Finger travel and card lift as fractions of the screen height, and the card's scale.
    private static let curve: [(travel: CGFloat, lift: CGFloat, scale: CGFloat)] = [
        (0, 0, 1),
        (0.014, 0, 1),
        (0.029, 0.020, 0.969),
        (0.057, 0.053, 0.923),
        (0.086, 0.090, 0.871),
        (0.114, 0.130, 0.813),
        (0.143, 0.164, 0.761),
        (0.172, 0.201, 0.710),
        (0.200, 0.236, 0.658),
        (0.229, 0.256, 0.632),
        (0.257, 0.276, 0.609),
        (0.286, 0.293, 0.592),
        (0.315, 0.310, 0.572),
        (0.343, 0.326, 0.560),
        (0.372, 0.341, 0.542),
        (0.400, 0.354, 0.532),
        (0.429, 0.368, 0.522),
        (0.450, 0.376, 0.512),
    ]
    private static let liftPerTravelBeyondCurve: CGFloat = 0.42
    private static let scalePerTravelBeyondCurve: CGFloat = -0.49
    static let minimumScale: CGFloat = 0.3

    static func pose(forTravel travel: CGFloat, screenHeight: CGFloat) -> (lift: CGFloat, scale: CGFloat) {
        guard screenHeight > 0 else { return (0, 1) }
        let normalizedTravel = max(0, travel / screenHeight)
        if let last = curve.last, normalizedTravel > last.travel {
            let beyond = normalizedTravel - last.travel
            return ((last.lift + beyond * liftPerTravelBeyondCurve) * screenHeight,
                    max(minimumScale, last.scale + beyond * scalePerTravelBeyondCurve))
        }
        for (lower, upper) in zip(curve, curve.dropFirst()) where normalizedTravel <= upper.travel {
            let progress = (normalizedTravel - lower.travel) / (upper.travel - lower.travel)
            let lift = lower.lift + (upper.lift - lower.lift) * progress
            let scale = lower.scale + (upper.scale - lower.scale) * progress
            return (lift * screenHeight, scale)
        }
        return (0, 1)
    }

    static func cardFrame(forTravel travel: CGFloat, in screenBounds: CGRect) -> CGRect {
        let pose = pose(forTravel: travel, screenHeight: screenBounds.height)
        let size = CGSize(width: screenBounds.width * pose.scale, height: screenBounds.height * pose.scale)
        return CGRect(x: screenBounds.midX - size.width / 2,
                      y: screenBounds.maxY - pose.lift - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// Mirrors `TabViewGridCell`: a header, then the preview clipped to an inset rounded rect with the
    /// page pinned to its top edge at full width.
    /// `contentCropTop` is how much of the snapshot's top the stored preview leaves out (the web view's top inset).
    static func previewLayout(forCellSize cellSize: CGSize,
                              contentSize: CGSize,
                              contentCropTop: CGFloat) -> (clipFrame: CGRect, contentFrame: CGRect) {
        let inset = TabViewGridCell.Constants.previewHorizontalInset / 2
        let top = TabViewGridCell.Constants.headerHeight
        let clipFrame = CGRect(x: inset,
                               y: top,
                               width: max(0, cellSize.width - inset * 2),
                               height: max(0, cellSize.height - top - TabViewGridCell.Constants.previewBottomPadding))
        let scale = contentSize.width > 0 ? clipFrame.width / contentSize.width : 1
        let contentFrame = CGRect(x: 0,
                                  y: -contentCropTop * scale,
                                  width: clipFrame.width,
                                  height: contentSize.height * scale)
        return (clipFrame, contentFrame)
    }

    /// A list row has no preview: the page keeps its width, pinned to the row's top edge, while it fades out.
    static func listPreviewLayout(forCellSize cellSize: CGSize,
                                  contentSize: CGSize,
                                  contentCropTop: CGFloat) -> (clipFrame: CGRect, contentFrame: CGRect) {
        let scale = contentSize.width > 0 ? cellSize.width / contentSize.width : 1
        let contentFrame = CGRect(x: 0,
                                  y: -contentCropTop * scale,
                                  width: cellSize.width,
                                  height: contentSize.height * scale)
        return (CGRect(origin: .zero, size: cellSize), contentFrame)
    }

    /// Where `TabViewListCell` draws the favicon.
    static func faviconFrame(inListCellOfSize cellSize: CGSize) -> CGRect {
        let size = TabViewListCell.Constants.faviconSize
        return CGRect(x: TabViewListCell.Constants.leadingPadding, y: (cellSize.height - size) / 2, width: size, height: size)
    }

    /// Where a cell showing the new tab logo draws it, matching `TabViewCell.updatePreviewToDisplayLogo()`.
    static func logoFrame(inPreviewClip clipFrame: CGRect, logoSize: CGSize) -> CGRect {
        let center = CGPoint(x: clipFrame.midX,
                             y: clipFrame.minY + (clipFrame.height - TabViewCell.Constants.previewPadding * 2) / 2)
        return CGRect(x: center.x - logoSize.width / 2,
                      y: center.y - logoSize.height / 2,
                      width: logoSize.width,
                      height: logoSize.height)
    }

    static func shouldCommit(travel: CGFloat, velocity: CGFloat) -> Bool {
        if velocity < -300 { return true }
        if velocity > 300 { return false }
        return travel > 70
    }
}

/// Where the current tab's cell landed the last time the tab switcher was laid out, so the card can head
/// for it before the tab switcher has been built. The card moves on to the real cell once it is laid out.
enum TabSwitcherCellFrameCache {

    private struct Key: Hashable {
        let row: Int
        let screenWidth: CGFloat
        let isGrid: Bool
    }

    private static var frames: [Key: CGRect] = [:]

    /// The cell's last known frame, else roughly where a fresh grid or list would put it.
    static func frame(forRow row: Int, in screen: CGRect, isGrid: Bool) -> CGRect {
        if let frame = frames[Key(row: row, screenWidth: screen.width, isGrid: isGrid)] {
            return frame
        }

        let spacing = TabSwitcherGridLayoutGeometry.spacing
        let size: CGSize
        let columns: Int
        if isGrid {
            size = CGSize(width: floor(TabSwitcherGridLayoutGeometry.columnWidth(for: screen.width)),
                          height: TabSwitcherViewController.Constants.cellMaxHeight)
            columns = max(1, Int((screen.width - spacing) / (size.width + spacing)))
        } else {
            size = CGSize(width: min(TabSwitcherPageViewController.Constants.listCellMaxWidth, screen.width - spacing * 2),
                          height: TabSwitcherPageViewController.Constants.listCellHeight)
            columns = 1
        }
        // Below the tab switcher's title bar.
        let top: CGFloat = 138
        let unclampedY = top + CGFloat(row / columns) * (size.height + spacing)
        // The tab switcher scrolls the current tab into the middle, so far rows never land off screen.
        let y = min(unclampedY, max(top, screen.height / 2 - size.height / 2))
        let x = isGrid ? spacing + CGFloat(row % columns) * (size.width + spacing) : screen.midX - size.width / 2
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func store(_ frame: CGRect, row: Int, in tabSwitcher: TabSwitcherViewController) {
        store(frame,
              row: row,
              screenWidth: tabSwitcher.view.window?.bounds.width ?? tabSwitcher.view.bounds.width,
              isGrid: DefaultTabSwitcherSettings().isGridViewEnabled)
    }

    static func store(_ frame: CGRect, row: Int, screenWidth: CGFloat, isGrid: Bool) {
        frames[Key(row: row, screenWidth: screenWidth, isGrid: isGrid)] = frame
    }
}
