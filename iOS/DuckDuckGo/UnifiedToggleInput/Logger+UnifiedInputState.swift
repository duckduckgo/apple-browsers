//
//  Logger+UnifiedInputState.swift
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

import Foundation
import os.log
import UIKit

extension Logger {
    static let unifiedInputState = Logger(subsystem: "UnifiedInputState", category: "PerTab")
    static let duckAIUsageWarnings = Logger(subsystem: "UsageWarnings", category: "UTIFooter")

    @MainActor
    static func logEscapeHatchScrollViews(in view: UIView, event: String) {
        func visit(_ view: UIView, ancestorAlpha: CGFloat, ancestorHidden: Bool) {
            let alpha = ancestorAlpha * view.alpha
            let hidden = ancestorHidden || view.isHidden
            if let scrollView = view as? UIScrollView {
                let identity = String(describing: ObjectIdentifier(scrollView))
                let frame = String(describing: scrollView.convert(scrollView.bounds, to: nil))
                let offset = String(describing: scrollView.contentOffset)
                let size = String(describing: scrollView.contentSize)
                let insets = String(describing: scrollView.adjustedContentInset)
                let rawInsets = String(describing: scrollView.contentInset)
                let safeArea = String(describing: scrollView.safeAreaInsets)
                let translation = String(describing: scrollView.panGestureRecognizer.translation(in: scrollView))
                unifiedInputState.debug("[EHScrollDiag] event=\(event, privacy: .public) scroll=\(identity, privacy: .public) class=\(String(describing: type(of: scrollView)), privacy: .public) frame=\(frame, privacy: .public) offset=\(offset, privacy: .public) size=\(size, privacy: .public) adjusted=\(insets, privacy: .public) raw=\(rawInsets, privacy: .public) scrollSafeArea=\(safeArea, privacy: .public) alpha=\(alpha, privacy: .public) hidden=\(hidden, privacy: .public) dragging=\(scrollView.isDragging, privacy: .public) tracking=\(scrollView.isTracking, privacy: .public) enabled=\(scrollView.isScrollEnabled, privacy: .public) alwaysBounceVertical=\(scrollView.alwaysBounceVertical, privacy: .public) decelerating=\(scrollView.isDecelerating, privacy: .public) pan=\(scrollView.panGestureRecognizer.state.rawValue, privacy: .public) translation=\(translation, privacy: .public)")
            }
            view.subviews.forEach { visit($0, ancestorAlpha: alpha, ancestorHidden: hidden) }
        }
        visit(view, ancestorAlpha: 1, ancestorHidden: false)
    }
}
