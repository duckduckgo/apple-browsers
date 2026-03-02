//
//  OnboardingConditionalCenteredScrollableContainerView.swift
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

/// A scrollable container that conditionally centers its content vertically based on device type.
///
/// On iPad (regular horizontal size class), content is centered vertically using spacers and expands
/// to fill the available height. On iPhone (compact horizontal size class), content is positioned at
/// the top without centering.
///
/// Scrolling is automatically disabled when the content fits within the available viewport.
/// This ensures that buttons inside the content receive immediate touch events (avoiding
/// the `UIScrollView.delaysContentTouches` delay that prevents pressed states from showing).
public struct OnboardingConditionalCenteredScrollableContainerView<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0

    private let content: Content

    /// Creates a conditional centered scrollable container.
    ///
    /// - Parameter content: A view builder that provides the content to be displayed within the container.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shouldCenterContent: Bool {
        hSizeClass == .regular
    }

    /// Scroll is disabled when the content fits inside the scroll view's viewport.
    /// This removes `UIScrollView`'s gesture-recognition delay so that button pressed
    /// states are visible immediately.
    private var isScrollDisabled: Bool {
        contentHeight > 0 && contentHeight <= scrollViewHeight
    }

    public var body: some View {
        // Keep content in the same structural position by using conditional spacers
        // instead of conditional container structure
        VStack(spacing: 0) {
            if shouldCenterContent {
                Spacer(minLength: 0)
            }

            ScrollView(.vertical, showsIndicators: false) {
                content
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ScrollContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ScrollViewHeightKey.self, value: proxy.size.height)
                }
            )
            // Only apply fixedSize when centering to make ScrollView size to content
            .fixedSize(horizontal: false, vertical: shouldCenterContent)
            .scrollDisabledIfAvailable(isScrollDisabled)

            if shouldCenterContent {
                Spacer(minLength: 0)
            }
        }
        .onPreferenceChange(ScrollContentHeightKey.self) { height in
            contentHeight = height
        }
        .onPreferenceChange(ScrollViewHeightKey.self) { height in
            scrollViewHeight = height
        }
    }
}

// MARK: - Preference Keys

private struct ScrollContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScrollViewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Scroll Disable Helper

private extension View {
    @ViewBuilder
    func scrollDisabledIfAvailable(_ disabled: Bool) -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDisabled(disabled)
        } else {
            self
        }
    }
}
#endif
