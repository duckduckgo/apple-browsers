//
//  RebrandedOnboardingStyles+DialogSize.swift
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
import MetricBuilder

extension OnboardingRebranding.OnboardingStyles {

    struct DialogSizeStyle: ViewModifier {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        private let metricBuilder: MetricBuilder<CGFloat?>

        init(maxWidthPhoneLandscape: CGFloat?, maxWidthPad: CGFloat?) {
            metricBuilder = MetricBuilder<CGFloat?>(default: nil).iPad(maxWidthPad).iPhone(landscape: maxWidthPhoneLandscape)
        }

        public func body(content: Content) -> some View {
            content
                .frame(maxWidth: metricBuilder.build(v: verticalSizeClass, h: horizontalSizeClass))
        }

    }

}

public extension View {

    /// Applies a maximum width constraint to dialog content based on device type and orientation.
    ///
    /// This modifier constrains the dialog width on specific device configurations while allowing
    /// full width on iPhone portrait. It's designed to optimize dialog presentation across different
    /// screen sizes and orientations.
    ///
    /// - Parameters:
    ///   - iPhoneLandscape: Optional maximum width for iPhone in landscape orientation.
    ///                      When `nil`, the dialog uses full available width. Default is `nil`.
    ///   - iPad: Optional maximum width for iPad (all orientations).
    ///           When `nil`, the dialog uses full available width. Default is `nil`.
    ///
    /// - Returns: A view with the maximum width constraint applied.
    ///
    /// - Note: iPhone portrait orientation always uses full available width regardless of parameters.
    func applyMaxDialogWidth(iPhoneLandscape: CGFloat? = nil, iPad: CGFloat? = nil) -> some View {
        modifier(OnboardingRebranding.OnboardingStyles.DialogSizeStyle(maxWidthPhoneLandscape: iPhoneLandscape, maxWidthPad: iPad))
    }

}
#endif
