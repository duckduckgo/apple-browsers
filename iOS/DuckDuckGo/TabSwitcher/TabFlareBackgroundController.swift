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
    private var reorderTrackingDisplayLink: CADisplayLink?
    private var lastContentOffset: CGPoint?
    private var onReorderTick: ((TimeInterval) -> Void)?
    private var lastPinnedIndex: Int?
    private var lastPinnedEdge: CGFloat = 0
    private var isStartingDeceleration = false
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
    func update(animated: Bool = false, scrollVelocity: CGFloat = 0) {
        // The display link owns the frame during a reorder.
        guard !isReordering else { return }
        guard let collectionView,
              let index = currentIndex(),
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else {
            stopEdgeBounce()
            view.isHidden = true
            return
        }
        updateFrame(attributes.frame, animated: animated)
        view.fillColor = fillColor()
        view.isHidden = false
        applyAlpha()
        collectionView.sendSubviewToBack(view)
        updateEdgeBounce(index: index, frame: attributes.frame, velocity: scrollVelocity)
    }

    func beginScrolling() {
        stopEdgeBounce()
        isStartingDeceleration = false
    }

    func beginDecelerating() {
        isStartingDeceleration = true
    }

    private func updateEdgeBounce(index: Int, frame: CGRect, velocity: CGFloat) {
        guard let collectionView,
              let layout = collectionView.collectionViewLayout as? TabsBarCollectionViewLayout,
              let original = layout.unpinnedFrameForItem(at: IndexPath(item: index, section: 0)) else { return }
        let viewport = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        let viewportWidth = viewport.width
        let edge: CGFloat = original.minX < frame.minX ? 1 : (original.minX > frame.minX ? -1 : 0)
        let sameTabAndWidth = lastPinnedIndex == index && lastViewportWidth == viewportWidth && lastItemWidth == frame.width
        let enteredEdge = edge != 0 && (edge != lastPinnedEdge || isStartingDeceleration)
        // A stationary layout refresh must not consume the first momentum sample after release.
        if velocity != 0 || !sameTabAndWidth { isStartingDeceleration = false }
        if !sameTabAndWidth || edge != lastPinnedEdge || UIAccessibility.isReduceMotionEnabled
            || bouncingCell?.layer.animation(forKey: "edgeBounce") == nil {
            stopEdgeBounce()
        }
        lastPinnedIndex = index
        lastPinnedEdge = edge
        lastViewportWidth = viewportWidth
        lastItemWidth = frame.width
        let impactSpeed = velocity * edge
        // Briefly cover the outer hint, then return to its half-tab resting position.
        let distance = max(0, edge > 0 ? frame.minX - viewport.minX : viewport.maxX - frame.maxX)
        let hasOuterNeighbor = edge > 0 ? index > 0 : index < collectionView.numberOfItems(inSection: 0) - 1
        // Gentle arrivals (under 250 points/second) and movement away from an edge have no impact.
        guard impactSpeed > 250, sameTabAndWidth, enteredEdge, hasOuterNeighbor, distance > 0, !UIAccessibility.isReduceMotionEnabled,
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) else { return }
        bouncingCell = cell
        let offset = -edge * distance
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.isAdditive = true
        animation.values = [0, offset, 0]
        animation.keyTimes = [0, 0.25, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        animation.duration = 0.4
        let start = CACurrentMediaTime()
        for layer in [cell.layer, view.layer] {
            animation.beginTime = layer.convertTime(start, from: nil)
            layer.add(animation, forKey: "edgeBounce")
        }
    }

    private func stopEdgeBounce() {
        bouncingCell?.layer.removeAnimation(forKey: "edgeBounce")
        bouncingCell = nil
        view.layer.removeAnimation(forKey: "edgeBounce")
    }

    /// Fades the flare out while the current tab is lifted for its preview.
    func beginPreview(forRow row: Int?, animator: UIContextMenuInteractionAnimating?) {
        stopEdgeBounce()
        isStartingDeceleration = false
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
        stopEdgeBounce()
        isStartingDeceleration = false
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
        guard let index = currentIndex(),
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) else { return }
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
