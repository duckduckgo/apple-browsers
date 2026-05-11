//
//  TabSwipeOverlayView.swift
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

/// Single overlay used to render a tab-swipe transition. Hosts full-screen `UIImage`
/// snapshots of each tab side-by-side in a horizontal scroll view; chrome and content move as
/// one unit because they're part of the same snapshot. Driven externally by the swipe gesture
/// — native paging/scrolling is disabled so the same overlay works for the legacy address-bar
/// pan and the UTI/AI-header external pans.
///
/// While the overlay is visible the real `MainViewController` children are hidden, so the user
/// is interacting with snapshots only during the swipe. On settle, the overlay hands the
/// destination index back to its caller, the real views are restored, and the overlay hides
/// itself.
final class TabSwipeOverlayView: UIView {

    private let scrollView = UIScrollView()
    private var pageImageViews: [UIImageView] = []
    private(set) var pageCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Pass-through user interaction so the underlying gesture recognizers (UTI pan, legacy
        // collection view pan) still receive touches when the overlay is on top.
        isUserInteractionEnabled = false
        // Opaque background so areas not covered by a page imageView — e.g. when the external
        // driver pans the contentOffset beyond contentSize at the trailing/leading edge —
        // don't reveal the live `MainViewController.view` underneath. Matches the design-
        // system panel tone used by the navigation bar / toolbar, which is what the legacy
        // non-UTI swipe shows when the user pans past the last tab.
        let chromeColor = UIColor(designSystemColor: .panel)
        backgroundColor = chromeColor

        scrollView.isPagingEnabled = false       // native paging would fight our offset writes
        scrollView.isScrollEnabled = false       // we drive contentOffset from the gesture
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = chromeColor
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Populate

    /// Replace the page contents. The overlay then has `snapshots.count` pages, each sized to
    /// `bounds`. Pages with a `nil` snapshot show a neutral background — the user briefly sees
    /// a blank page for tabs we don't have a cached snapshot for, which is preferable to
    /// reusing a stale snapshot from a different tab.
    func populate(snapshots: [UIImage?], currentIndex: Int) {
        pageImageViews.forEach { $0.removeFromSuperview() }
        pageImageViews = []
        pageCount = snapshots.count

        let width = bounds.width
        let height = bounds.height

        let chromeColor = UIColor(designSystemColor: .panel)
        for (idx, snapshot) in snapshots.enumerated() {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            // Pages without a snapshot (trailing "new tab" slot, uncached tabs) show the
            // chrome tone so they blend with the surrounding backdrop rather than flashing a
            // contrasting system colour.
            imageView.backgroundColor = chromeColor
            imageView.image = snapshot
            imageView.frame = CGRect(x: CGFloat(idx) * width, y: 0, width: width, height: height)
            scrollView.addSubview(imageView)
            pageImageViews.append(imageView)
        }

        scrollView.contentSize = CGSize(width: CGFloat(snapshots.count) * width, height: height)
        let initialX = CGFloat(currentIndex) * width
        scrollView.contentOffset = CGPoint(x: initialX, y: 0)
    }

    // MARK: - External drive

    /// Sets the overlay's scroll position directly. Caller clamps to valid range.
    func setContentOffsetX(_ x: CGFloat) {
        scrollView.contentOffset.x = x
    }

    /// Animates to the page nearest `targetIndex`. Reports back the settled index on
    /// completion so the caller can call `selectTab`. Always reports `targetIndex` unless the
    /// animation is cancelled by another offset write.
    func settle(toPage targetIndex: Int, duration: TimeInterval = 0.3, completion: @escaping (Int) -> Void) {
        let width = bounds.width
        let target = CGPoint(x: CGFloat(targetIndex) * width, y: 0)
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut, animations: {
            self.scrollView.contentOffset = target
        }, completion: { _ in
            completion(targetIndex)
        })
    }

    var currentPage: Int {
        guard bounds.width > 0 else { return 0 }
        return Int((scrollView.contentOffset.x / bounds.width).rounded())
    }

    var contentOffsetX: CGFloat { scrollView.contentOffset.x }

    var pageWidth: CGFloat { bounds.width }
}
