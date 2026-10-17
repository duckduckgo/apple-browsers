//
//  LiquidGlassDesign.swift
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

import Common
import SwiftUI

public extension View {
    /// Clips the view to a pill (Capsule) shape when the Liquid Glass design is supported;
    /// otherwise applies a rounded-rectangle corner radius as a fallback.
    @ViewBuilder
    func liquidGlassPillShape(fallbackCornerRadius: CGFloat) -> some View {
        if AppVersion.isLiquidGlassSupported {
            clipShape(Capsule())
        } else {
            cornerRadius(fallbackCornerRadius)
        }
    }
}
