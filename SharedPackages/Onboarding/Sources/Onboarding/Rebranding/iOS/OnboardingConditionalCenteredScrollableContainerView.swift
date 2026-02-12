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
public struct OnboardingConditionalCenteredScrollableContainerView<Content: View>: View {
    @State private var containerHeight: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private let animationDuration: CGFloat
    private let content: Content

    /// Creates a conditional centered scrollable container.
    ///
    /// - Parameter content: A view builder that provides the content to be displayed within the container.
    public init(animationDuration: CGFloat = 0.3, @ViewBuilder content: () -> Content) {
        self.animationDuration = animationDuration
        self.content = content()
    }

    private var shouldCenterContent: Bool {
        hSizeClass == .regular
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                if shouldCenterContent {
                    Spacer(minLength: 0)
                }

                content

                if shouldCenterContent {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: shouldCenterContent ? containerHeight : nil)
            .animation(.easeInOut(duration: animationDuration), value: containerHeight)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        containerHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.height) { newHeight in
                        containerHeight = newHeight
                    }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
