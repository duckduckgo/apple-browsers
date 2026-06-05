//
//  SheetMetrics.swift
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

/// Spacing for rebranded sheet content, plus the sheet corner radius.
public enum SheetMetrics {

    private static let contentSpacingMetric = MetricBuilder<CGFloat>(default: 24)
    private static let contentHorizontalPaddingMetric = MetricBuilder<CGFloat>(default: 24)
    private static let contentBottomPaddingMetric = MetricBuilder<CGFloat>(default: 20)
    private static let headerSpacingMetric = MetricBuilder<CGFloat>(default: 4)
    private static let cornerRadiusMetric = MetricBuilder<CGFloat>(iPhone: 36, iPad: 38)

    /// Vertical gap between the content sections (icon, header, body).
    @MainActor public static var contentSpacing: CGFloat { contentSpacingMetric.build() }

    /// Horizontal padding around the content block.
    @MainActor public static var contentHorizontalPadding: CGFloat { contentHorizontalPaddingMetric.build() }

    /// Bottom padding of the content block.
    @MainActor public static var contentBottomPadding: CGFloat { contentBottomPaddingMetric.build() }

    /// Gap between the header's title and subtitle.
    @MainActor public static var headerSpacing: CGFloat { headerSpacingMetric.build() }

    /// Corner radius for a sheet's rounded corners.
    @MainActor public static var cornerRadius: CGFloat { cornerRadiusMetric.build() }
}
#endif
