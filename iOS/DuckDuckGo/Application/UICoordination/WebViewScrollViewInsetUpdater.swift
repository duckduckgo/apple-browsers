//
//  WebViewScrollViewInsetUpdater.swift
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

enum WebViewScrollViewInsetUpdater {

    // WebKit's resting offset and adjusted inset can differ by floating-point rounding.
    private static let topPositionTolerance: CGFloat = 0.001

    struct AdjustmentBehavior {
        let contentInsetAdjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior
        let automaticallyAdjustsScrollIndicatorInsets: Bool
    }

    static func beginManaging(_ scrollView: UIScrollView) -> AdjustmentBehavior {
        let behavior = AdjustmentBehavior(
            contentInsetAdjustmentBehavior: scrollView.contentInsetAdjustmentBehavior,
            automaticallyAdjustsScrollIndicatorInsets: scrollView.automaticallyAdjustsScrollIndicatorInsets
        )
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        return behavior
    }

    static func endManaging(_ scrollView: UIScrollView, restoring behavior: AdjustmentBehavior) {
        scrollView.contentInsetAdjustmentBehavior = behavior.contentInsetAdjustmentBehavior
        scrollView.automaticallyAdjustsScrollIndicatorInsets = behavior.automaticallyAdjustsScrollIndicatorInsets
    }

    static func shouldDeferDuringTopBounce(_ scrollView: UIScrollView) -> Bool {
        (scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating)
            && scrollView.contentOffset.y + scrollView.adjustedContentInset.top <= topPositionTolerance
    }

    static func update(_ scrollView: UIScrollView, insets: UIEdgeInsets, isFloatingUIEnabled: Bool = false, animated: Bool = false) {
        if scrollView.contentInset != insets {
            let isPinnedToTop = isFloatingUIEnabled
                ? scrollView.contentOffset.y + scrollView.adjustedContentInset.top <= topPositionTolerance
                : scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
            scrollView.contentInset = insets
            if isPinnedToTop {
                if isFloatingUIEnabled {
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -insets.top), animated: animated)
                } else {
                    scrollView.contentOffset.y = -insets.top
                }
            }
        }

        updateScrollIndicatorInsets(scrollView, insets: insets)
    }

    static func updateScrollIndicatorInsets(_ scrollView: UIScrollView, insets: UIEdgeInsets) {
        if scrollView.verticalScrollIndicatorInsets != insets {
            scrollView.verticalScrollIndicatorInsets = insets
        }
        if scrollView.horizontalScrollIndicatorInsets != insets {
            scrollView.horizontalScrollIndicatorInsets = insets
        }
    }

    static func shouldUpdateDuringChromeTransition(barsVisibilityPercent: CGFloat,
                                                   hasAppliedInsets: Bool) -> Bool {
        !hasAppliedInsets || barsVisibilityPercent <= 0 || barsVisibilityPercent >= 1
    }
}
