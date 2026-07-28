//
//  TabFlareBackgroundController.swift
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

/// Draws the active tab's flared background and keeps it in place through the current tab's
/// context-menu preview and reorder drag.
final class TabFlareBackgroundController {

    private final class WeakDisplayLinkProxy {
        weak var target: TabFlareBackgroundController?

        init(target: TabFlareBackgroundController) {
            self.target = target
        }

        @objc func tick() {
            target?.trackToCurrentTabCell()
        }
    }

    private let view = TabFlaredBackgroundView()
    private weak var collectionView: UICollectionView?
    private let currentIndex: () -> Int?
    private let fillColor: () -> UIColor
    private let rampWidth: CGFloat

    // Tab lifted for a context-menu preview, or nil.
    private var previewedTabIndex: Int?

    private var isReordering = false
    private var reorderTrackingDisplayLink: CADisplayLink?

    init(collectionView: UICollectionView,
         topCornerRadius: CGFloat,
         rampSize: CGSize,
         currentIndex: @escaping () -> Int?,
         fillColor: @escaping () -> UIColor) {
        self.collectionView = collectionView
        self.currentIndex = currentIndex
        self.fillColor = fillColor
        self.rampWidth = rampSize.width
        view.topCornerRadius = topCornerRadius
        view.rampSize = rampSize
        view.isHidden = true
        collectionView.insertSubview(view, at: 0)
    }

    deinit {
        stopReorderTracking()
    }

    /// Positions the flare over the current tab.
    func update() {
        // The display link owns the frame during a reorder.
        guard !isReordering else { return }
        guard let collectionView,
              let index = currentIndex(),
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else {
            view.isHidden = true
            return
        }
        view.frame = attributes.frame.insetBy(dx: -rampWidth, dy: 0)
        view.fillColor = fillColor()
        view.isHidden = false
        view.alpha = (previewedTabIndex == index) ? 0 : 1
        collectionView.sendSubviewToBack(view)
    }

    /// Fades the flare out while the current tab is lifted for its preview.
    func beginPreview(forRow row: Int?, animator: UIContextMenuInteractionAnimating?) {
        guard row == currentIndex() else { return }
        previewedTabIndex = currentIndex()
        animator?.addAnimations { self.view.alpha = 0 }
    }

    /// Restores the flare after a preview.
    func endPreview() {
        guard previewedTabIndex != nil else { return }
        previewedTabIndex = nil
        view.alpha = 1
    }

    func beginReorder() {
        // A long-press preview can convert into a drag without firing its dismiss callback.
        previewedTabIndex = nil
        isReordering = true
        view.alpha = 1
        startReorderTracking()
    }

    func endReorder() {
        stopReorderTracking()
        isReordering = false
        update()
    }

    private func startReorderTracking() {
        stopReorderTracking()
        let link = CADisplayLink(target: WeakDisplayLinkProxy(target: self), selector: #selector(WeakDisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        reorderTrackingDisplayLink = link
    }

    private func stopReorderTracking() {
        reorderTrackingDisplayLink?.invalidate()
        reorderTrackingDisplayLink = nil
    }

    /// Follows the current tab cell's live frame during a reorder.
    private func trackToCurrentTabCell() {
        guard let collectionView else {
            endReorder()
            return
        }
        // Stop if the drag ended without `dragSessionDidEnd`, so the link can't run on forever.
        guard collectionView.hasActiveDrag else {
            endReorder()
            return
        }
        guard let index = currentIndex(),
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) else { return }
        let cellFrame = cell.layer.presentation()?.frame ?? cell.frame
        view.frame = cellFrame.insetBy(dx: -rampWidth, dy: 0)
    }
}
