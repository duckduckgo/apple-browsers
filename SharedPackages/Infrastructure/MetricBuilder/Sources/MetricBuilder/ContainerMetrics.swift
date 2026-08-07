//
//  ContainerMetrics.swift
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

/// Corner radius for rebranded container surfaces (cards, popups, panels). Sheets use `SheetMetrics.cornerRadius`.
public enum ContainerMetrics {

    private static let cornerRadiusMetric = MetricBuilder<CGFloat>(default: 26)
    private static let closeButtonPaddingMetric = MetricBuilder<CGFloat>(default: 16)

    /// Corner radius for a container surface.
    @MainActor public static var cornerRadius: CGFloat {
        cornerRadiusMetric.build()
    }

    /// Inset of the close button from a container's top-trailing corner.
    @MainActor public static var closeButtonPadding: CGFloat {
        closeButtonPaddingMetric.build()
    }
}
#endif
