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

/// Shared spacing for rebranded sheet content, matching the Figma "Sheets Spacing" template:
/// the content block stacks its sections (icon, header, body) `contentSpacing` (24pt) apart with
/// `contentHorizontalPadding` (24pt) and `contentBottomPadding` (20pt) around it, and the header's
/// title and subtitle are `headerSpacing` (4pt) apart.
///
/// The button footer of a sheet uses `ButtonStackMetrics` (8pt between buttons, 24pt padding).
///
/// Values are encoded with `MetricBuilder` and resolve to the same number on every device and
/// orientation (iPhone, iPad, portrait, landscape).
public enum SheetMetrics {

    private static let contentSpacingMetric = MetricBuilder<CGFloat>(default: 24)
    private static let contentHorizontalPaddingMetric = MetricBuilder<CGFloat>(default: 24)
    private static let contentBottomPaddingMetric = MetricBuilder<CGFloat>(default: 20)
    private static let headerSpacingMetric = MetricBuilder<CGFloat>(default: 4)

    /// Vertical gap between the sheet content sections (icon, header, body): 24pt.
    @MainActor public static var contentSpacing: CGFloat { contentSpacingMetric.build() }

    /// Horizontal padding around the sheet content block: 24pt.
    @MainActor public static var contentHorizontalPadding: CGFloat { contentHorizontalPaddingMetric.build() }

    /// Bottom padding of the sheet content block: 20pt.
    @MainActor public static var contentBottomPadding: CGFloat { contentBottomPaddingMetric.build() }

    /// Gap between the header's title and subtitle: 4pt.
    @MainActor public static var headerSpacing: CGFloat { headerSpacingMetric.build() }
}
#endif
