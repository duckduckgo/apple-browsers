//
//  TabsBarView.swift
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

final class TabsBarView: UIView {

    let collectionView: UICollectionView
    let buttonsStack = UIStackView()
    let buttonsBackground = UIView()

    private var collectionViewLeading: NSLayoutConstraint?

    /// Leading tab margin, expanded when window controls share the row.
    var firstTabLeadingMargin: CGFloat = TabsBarViewController.Constants.firstTabLeadingMargin {
        didSet {
            collectionViewLeading?.constant = Self.collectionViewLeadingConstant(for: firstTabLeadingMargin)
        }
    }

    // Offset by one ramp width so content inset can preserve the tab margin without clipping the flare.
    private static func collectionViewLeadingConstant(for firstTabLeadingMargin: CGFloat) -> CGFloat {
        firstTabLeadingMargin - TabsBarViewController.Constants.tabRampSize.width
    }

    override init(frame: CGRect) {
        let layout = TabsBarCollectionViewLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(frame: frame)

        setUpSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isDirectionalLockEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false

        buttonsBackground.translatesAutoresizingMaskIntoConstraints = false

        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.axis = .horizontal
        buttonsStack.setContentHuggingPriority(.required, for: .horizontal)
        buttonsStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(collectionView)
        addSubview(buttonsBackground)
        addSubview(buttonsStack)

        let collectionViewLeading = collectionView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Self.collectionViewLeadingConstant(for: firstTabLeadingMargin))
        self.collectionViewLeading = collectionViewLeading

        NSLayoutConstraint.activate([
            collectionViewLeading,
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            buttonsBackground.leadingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            buttonsBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonsBackground.topAnchor.constraint(equalTo: topAnchor),
            buttonsBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            buttonsStack.leadingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: TabsBarViewController.Constants.leadingInset),
            buttonsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TabsBarViewController.Constants.leadingInset),
            buttonsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonsStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            buttonsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

/// Overlaps tabs at the strip's edges, keeping the selected tab above the stack.
final class TabsBarCollectionViewLayout: UICollectionViewFlowLayout {

    var currentIndex: (() -> Int?)?

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        true
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // The outgoing tab remains exposed until its neighbor finishes folding over it.
        let expandedRect = rect.insetBy(dx: -itemSize.width / 2, dy: 0)
        guard let originalAttributes = super.layoutAttributesForElements(in: expandedRect) else { return nil }
        let attributes = originalAttributes.compactMap { layoutAttributesForItem(at: $0.indexPath) }
        guard let collectionView,
              let index = currentIndex?(),
              index < collectionView.numberOfItems(inSection: 0),
              !attributes.contains(where: { $0.indexPath.item == index }),
              let current = layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else {
            return attributes
        }
        // Include the selected tab even when its original position is outside the visible rect.
        return attributes + [current]
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attributes = super.layoutAttributesForItem(at: indexPath)?.copy() as? UICollectionViewLayoutAttributes,
              let collectionView else {
            return super.layoutAttributesForItem(at: indexPath)
        }
        let leading = collectionView.bounds.minX + collectionView.adjustedContentInset.left
        let trailing = max(leading, collectionView.bounds.maxX - collectionView.adjustedContentInset.right - attributes.frame.width)
        let isCurrent = indexPath.item == currentIndex?()
        // Tabs nearer the middle cover the edge tabs. The flare (1) and selected tab (2) stay above them.
        let middle = (leading + trailing + attributes.frame.width) / 2
        attributes.zIndex = isCurrent ? 2 : -Int(abs(attributes.center.x - middle))
        let foldRange = min(attributes.frame.width / 2, (trailing - leading) / 2)
        var origin = attributes.frame.minX
        if !isCurrent, foldRange > 0 {
            if indexPath.item > 0, origin < leading + foldRange {
                origin = leading + foldedDistance(origin - leading, range: foldRange)
            } else if indexPath.item < collectionView.numberOfItems(inSection: indexPath.section) - 1, origin > trailing - foldRange {
                origin = trailing - foldedDistance(trailing - origin, range: foldRange)
            }
        }
        attributes.frame.origin.x = min(max(origin, leading), trailing)
        return attributes
    }

    private func foldedDistance(_ distance: CGFloat, range: CGFloat) -> CGFloat {
        // Start easing the next tab when the outer tab is halfway covered.
        let remaining = max(0, distance + range)
        return remaining * remaining / (4 * range)
    }

    func unpinnedFrameForItem(at indexPath: IndexPath) -> CGRect? {
        super.layoutAttributesForItem(at: indexPath)?.frame
    }

    func frameForRevealingItem(at indexPath: IndexPath) -> CGRect? {
        guard let collectionView, let frame = unpinnedFrameForItem(at: indexPath) else { return nil }
        let visibleWidth = collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right
        let current = currentIndex?()
        let pinnedWidth = current != nil && current != indexPath.item ? min(frame.width, max(0, visibleWidth - frame.width)) : 0
        // Leave a glimpse of neighboring tabs without squeezing the selected tab on narrow strips.
        let peek = min(frame.width / 2, max(0, (visibleWidth - frame.width - pinnedWidth) / 2))
        var revealFrame = frame.insetBy(dx: -peek, dy: 0)
        // A pinned current tab covers the neighbor hint unless its width is also reserved.
        if let current, current < indexPath.item {
            revealFrame.origin.x -= pinnedWidth
        }
        revealFrame.size.width += pinnedWidth
        return revealFrame.intersection(CGRect(origin: .zero, size: collectionView.contentSize))
    }
}
