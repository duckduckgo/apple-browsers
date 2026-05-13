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
        isUserInteractionEnabled = false
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
            // Skip non-adjacent pages: a single swipe can't reach them
            guard let snapshot else { continue }
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
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
}
