//
//  ButtonStackMetrics.swift
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

/// Shared spacing for rebranded button stacks, matching the Figma "Buttons" component:
/// stacked buttons sit `containerPadding` (24pt) away from their container on every side and
/// are `interButtonSpacing` (8pt) apart from each other.
///
/// The values are encoded with `MetricBuilder` and resolve to the same number on every device
/// and orientation (iPhone, iPad, portrait, landscape).
public enum ButtonStackMetrics {

    private static let interButtonSpacingMetric = MetricBuilder<CGFloat>(default: 8)
    private static let containerPaddingMetric = MetricBuilder<CGFloat>(default: 24)

    /// Vertical gap between stacked buttons (8pt).
    @MainActor public static var interButtonSpacing: CGFloat {
        interButtonSpacingMetric.build()
    }

    /// Padding between a button stack (or a single full-width button) and its container edges (24pt).
    @MainActor public static var containerPadding: CGFloat {
        containerPaddingMetric.build()
    }
}
#endif
