//
//  OnboardingScrollIfNeededModifier.swift
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

#if os(iOS)
import SwiftUI
import UIKit

/// Disables scrolling on a `ScrollView` when its content fits within the visible bounds.
///
/// Uses a lightweight UIKit observer to compare the scroll view's `contentSize`
/// against its `bounds`. When content fits, scrolling is disabled; when it overflows,
/// scrolling is re-enabled. Also sets `alwaysBounceVertical` to `false`.
///
/// Apply directly to a `ScrollView`:
/// ```swift
/// ScrollView(.vertical, showsIndicators: false) {
///     content
/// }
/// .scrollIfNeeded()
/// ```
struct OnboardingScrollIfNeededModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
            .background(
                ScrollViewScrollObserver()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            )
    }
}

// MARK: - UIKit Observer

private struct ScrollViewScrollObserver: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.startObserving(from: uiView)
        }
    }

    final class Coordinator {
        private var contentSizeObservation: NSKeyValueObservation?
        private var boundsObservation: NSKeyValueObservation?
        private weak var observedScrollView: UIScrollView?

        func startObserving(from view: UIView) {
            guard let scrollView = Self.findScrollView(from: view),
                  scrollView !== observedScrollView else {
                return
            }

            observedScrollView = scrollView
            scrollView.alwaysBounceVertical = false

            contentSizeObservation = scrollView.observe(\.contentSize, options: [.new, .initial]) { sv, _ in
                DispatchQueue.main.async { Self.updateScrollState(of: sv) }
            }
            boundsObservation = scrollView.observe(\.bounds, options: [.new]) { sv, _ in
                DispatchQueue.main.async { Self.updateScrollState(of: sv) }
            }
        }

        private static func updateScrollState(of scrollView: UIScrollView) {
            let scrollNeeded = scrollView.contentSize.height > scrollView.bounds.height
            if scrollView.isScrollEnabled != scrollNeeded {
                scrollView.isScrollEnabled = scrollNeeded
            }
        }

        /// The `.background()` modifier places the observer near the `UIScrollView`
        /// that SwiftUI creates. The scroll view may be nested inside intermediate
        /// hosting views, so we search each sibling's subtree rather than only
        /// checking direct siblings.
        private static func findScrollView(from view: UIView) -> UIScrollView? {
            var current: UIView? = view
            while let v = current {
                if let scrollView = v as? UIScrollView { return scrollView }
                if let parent = v.superview {
                    for sibling in parent.subviews where sibling !== v {
                        if let scrollView = firstScrollView(in: sibling) { return scrollView }
                    }
                }
                current = v.superview
            }
            return nil
        }

        private static func firstScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView { return scrollView }
            for subview in view.subviews {
                if let scrollView = firstScrollView(in: subview) { return scrollView }
            }
            return nil
        }
    }
}

// MARK: - View Extension

public extension View {

    /// Disables scrolling when the content fits within the scroll view's bounds.
    func scrollIfNeeded() -> some View {
        modifier(OnboardingScrollIfNeededModifier())
    }
}
#endif
