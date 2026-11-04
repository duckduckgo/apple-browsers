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

        @objc func tick(_ link: CADisplayLink) {
            target?.trackToCurrentTabCell(elapsedTime: link.targetTimestamp - link.timestamp)
        }
    }

    private let view = TabFlaredBackgroundView()
    private weak var collectionView: UICollectionView?
    private let currentIndex: () -> Int?
    private let fillColor: () -> UIColor
    private let rampWidth: CGFloat

    // Tab lifted for a context-menu preview, or nil.
    private var previewedTabIndex: Int?

    /// Additional fade applied before strip clipping.
    var hideAlpha: CGFloat = 1 {
        didSet {
            guard hideAlpha != oldValue else { return }
            applyAlpha()
        }
    }

    private var isReordering = false
    private weak var reorderingCurrentCell: UICollectionViewCell?
    private var reorderTrackingDisplayLink: CADisplayLink?
    private var lastContentOffset: CGPoint?
    private var onReorderTick: ((TimeInterval) -> Void)?
    private var lastPinnedIndex: Int?
    private var lastPinnedEdge: CGFloat = 0
    private var dragContentOffset: CGFloat?
    private var lastViewportWidth: CGFloat = 0
    private var lastItemWidth: CGFloat = 0
    private weak var bouncingCell: UICollectionViewCell?

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
        view.layer.zPosition = 1
        collectionView.insertSubview(view, at: 0)
    }

    deinit {
        stopReorderTracking()
    }

    /// Positions the flare over the current tab.
    func update(animated: Bool = false) {
        // The display link owns the frame during a reorder.
        guard !isReordering else { return }
        guard let collectionView,
              let index = currentIndex() else {
            stopEdgeBounce()
            view.isHidden = true
            return
        }
        // Reordering can temporarily remove layout attributes without removing the selected tab.
        guard let layout = collectionView.collectionViewLayout as? TabsBarCollectionViewLayout,
              let restingFrame = layout.frameForCurrentTabAtRest() else { return }
        updateDragOffset(index: index, frame: restingFrame)
        guard let attributes = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }
        updateFrame(attributes.frame, animated: animated)
        view.fillColor = fillColor()
        view.isHidden = false
        applyAlpha()
        collectionView.sendSubviewToBack(view)
    }

    func beginScrolling(at point: CGPoint?) {
        guard let collectionView, let layout = collectionView.collectionViewLayout as? TabsBarCollectionViewLayout else { return }
        let cell = currentIndex().flatMap { collectionView.cellForItem(at: IndexPath(item: $0, section: 0)) }
        let visibleFrame = (cell?.layer.presentation()?.frame ?? cell?.frame ?? .zero)
            .intersection(collectionView.bounds.inset(by: collectionView.adjustedContentInset))
        let grabbedCurrentTab = !visibleFrame.isEmpty && (point.map { visibleFrame.contains($0) } ?? false)
        // Catch an in-flight return at its visible position when the user grabs the strip again.
        let offset = grabbedCurrentTab
            ? bouncingCell.map { ($0.layer.presentation()?.position.x ?? $0.layer.position.x) - $0.layer.position.x } ?? 0 : 0
        stopEdgeBounce()
        layout.currentTabDragOffset = offset
        dragContentOffset = grabbedCurrentTab ? collectionView.contentOffset.x : nil
        collectionView.layoutIfNeeded()
        update()
    }

    func endScrolling() {
        dragContentOffset = nil
        guard let collectionView, let layout = collectionView.collectionViewLayout as? TabsBarCollectionViewLayout,
              layout.currentTabDragOffset != 0, let index = currentIndex(), let frame = layout.frameForCurrentTabAtRest() else { return }
        let offset = (layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame.minX ?? frame.minX) - frame.minX
        let positions = collectionView.visibleCells.map { ($0, collectionView.indexPath(for: $0), $0.frame.minX) }
        layout.currentTabDragOffset = 0
        collectionView.layoutIfNeeded()
        update()
        bouncingCell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
        // Return the inner accordion with the selected tab so resetting the layout cannot leave a gap.
        for (cell, indexPath, position) in positions where collectionView.indexPath(for: cell) == indexPath {
            animateDragReturn(layer: cell.layer, from: position - cell.frame.minX)
        }
        animateDragReturn(layer: view.layer, from: offset)
    }

    private func updateDragOffset(index: Int, frame: CGRect) {
        guard let collectionView,
              let layout = collectionView.collectionViewLayout as? TabsBarCollectionViewLayout,
              let original = layout.unpinnedFrameForItem(at: IndexPath(item: index, section: 0)) else { return }
        let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        let viewportWidth = viewport.width
        let edge: CGFloat = original.minX < frame.minX ? 1 : (original.minX > frame.minX ? -1 : 0)
        let sameTabAndWidth = lastPinnedIndex == index && lastViewportWidth == viewportWidth && lastItemWidth == frame.width
        if !sameTabAndWidth || edge != lastPinnedEdge || UIAccessibility.isReduceMotionEnabled {
            stopEdgeBounce()
            layout.currentTabDragOffset = 0
        }
        lastPinnedIndex = index
        lastPinnedEdge = edge
        lastViewportWidth = viewportWidth
        lastItemWidth = frame.width
        let distance = max(0, edge > 0 ? frame.minX - viewport.minX : viewport.maxX - frame.maxX)
        let hasOuterNeighbor = edge > 0 ? index > 0 : index < collectionView.numberOfItems(inSection: 0) - 1

        if let previousOffset = dragContentOffset {
            dragContentOffset = collectionView.contentOffset.x
            if sameTabAndWidth, edge != 0, hasOuterNeighbor, !UIAccessibility.isReduceMotionEnabled {
                // Only resist travel after reaching the edge; reversing the finger immediately unwinds it.
                let travel = min(edge * (collectionView.contentOffset.x - previousOffset), edge * (frame.minX - original.minX))
                let displacement = min(distance, max(0, -edge * layout.currentTabDragOffset + travel * 0.5))
                layout.currentTabDragOffset = -edge * displacement
            }
            collectionView.layoutIfNeeded()
        }
    }

    private func animateDragReturn(layer: CALayer, from offset: CGFloat) {
        guard offset != 0, !UIAccessibility.isReduceMotionEnabled else { return }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.isAdditive = true
        animation.fromValue = offset
        animation.toValue = 0
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.duration = 0.2
        layer.add(animation, forKey: "edgeBounce")
    }

    private func stopEdgeBounce() {
        bouncingCell?.layer.removeAnimation(forKey: "edgeBounce")
        bouncingCell = nil
        collectionView?.visibleCells.forEach { $0.layer.removeAnimation(forKey: "edgeBounce") }
        view.layer.removeAnimation(forKey: "edgeBounce")
    }

    private func cancelScrolling() {
        dragContentOffset = nil
        stopEdgeBounce()
        (collectionView?.collectionViewLayout as? TabsBarCollectionViewLayout)?.currentTabDragOffset = 0
        collectionView?.layoutIfNeeded()
        update()
    }

    /// Fades the flare out while the current tab is lifted for its preview.
    func beginPreview(forRow row: Int?, animator: UIContextMenuInteractionAnimating?) {
        cancelScrolling()
        guard row == currentIndex() else { return }
        previewedTabIndex = currentIndex()
        animator?.addAnimations { self.view.alpha = 0 }
    }

    /// Restores the flare after a preview.
    func endPreview() {
        guard previewedTabIndex != nil else { return }
        previewedTabIndex = nil
        applyAlpha()
    }

    func beginReorder(onTick: ((TimeInterval) -> Void)? = nil) {
        cancelScrolling()
        reorderingCurrentCell = currentIndex().flatMap { collectionView?.cellForItem(at: IndexPath(item: $0, section: 0)) }
        // A long-press preview can convert into a drag without firing its dismiss callback.
        previewedTabIndex = nil
        isReordering = true
        onReorderTick = onTick
        applyAlpha()
        startReorderTracking()
    }

    func endReorder() {
        stopReorderTracking()
        onReorderTick = nil
        isReordering = false
        reorderingCurrentCell = nil
        collectionView?.layoutIfNeeded()
        update(animated: true)
    }

    // Preview hiding takes precedence over scroll hiding.
    private func applyAlpha() {
        guard let previewedTabIndex, previewedTabIndex == currentIndex() else {
            view.alpha = hideAlpha
            return
        }
        view.alpha = 0
    }

    private func startReorderTracking() {
        stopReorderTracking()
        let link = CADisplayLink(target: WeakDisplayLinkProxy(target: self), selector: #selector(WeakDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        reorderTrackingDisplayLink = link
    }

    private func stopReorderTracking() {
        reorderTrackingDisplayLink?.invalidate()
        reorderTrackingDisplayLink = nil
    }

    /// Animates between insertion slots instead of copying the placeholder's jumps.
    private func trackToCurrentTabCell(elapsedTime: TimeInterval) {
        guard let collectionView else {
            endReorder()
            return
        }
        // Stop if the drag ended without `dragSessionDidEnd`, so the link can't run on forever.
        guard collectionView.hasActiveDrag else {
            endReorder()
            return
        }
        onReorderTick?(elapsedTime)
        // Model indices change before UIKit finishes moving the cells.
        guard let cell = reorderingCurrentCell else { return }
        updateFrame(cell.frame, animated: true)
    }

    private func updateFrame(_ cellFrame: CGRect, animated: Bool) {
        let frame = cellFrame.insetBy(dx: -rampWidth, dy: 0)
        let contentOffset = collectionView?.contentOffset
        // Scrolling already moves the flare; only animate changes between insertion slots.
        let shouldAnimate = animated && contentOffset == lastContentOffset && !UIAccessibility.isReduceMotionEnabled
        lastContentOffset = contentOffset
        guard view.frame != frame else { return }
        let position = view.layer.presentation()?.position ?? view.layer.position
        view.layer.removeAnimation(forKey: "reorder")
        view.frame = frame
        guard shouldAnimate else { return }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = position
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(animation, forKey: "reorder")
    }
}
