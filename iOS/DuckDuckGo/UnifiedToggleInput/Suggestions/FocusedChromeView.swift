//
//  FocusedChromeView.swift
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

import SwiftUI

/// The bar-pinned chrome shown above the focused suggestions in non-typing states: the escape hatch
/// plus the optional Duck.ai sync-promo. The container pins this to the bar (so it rides the bar's
/// animation in the same layout pass) and reserves its reported height for the content below it.
/// Owns the chrome's own spacing/margins so they live in one place.
struct FocusedChromeView: View {

    let hatchModel: EscapeHatchModel?
    let syncPromo: AnyView?
    /// Gap between the bar's edge and the first chrome element (Figma: 6 top bar, 16 bottom bar).
    let topInset: CGFloat
    /// Reports the chrome's laid-out height so the container can inset the content below it. 0 when empty.
    let onHeightChange: (CGFloat) -> Void

    private var hasContent: Bool { hatchModel != nil || syncPromo != nil }

    var body: some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.height) { onHeightChange($0) }
                        .onAppear { onHeightChange(proxy.size.height) }
                }
            )
    }

    @ViewBuilder
    private var content: some View {
        if hasContent {
            VStack(spacing: Metrics.interCardSpacing) {
                if let hatchModel {
                    EscapeHatchView(model: hatchModel)
                }
                if let syncPromo {
                    syncPromo
                }
            }
            .padding(.horizontal, Metrics.horizontalMargin)
            .padding(.top, topInset)
            .padding(.bottom, Metrics.bottomInset)
            .frame(maxWidth: .infinity)
            // Opaque page background directly behind the hatch so scroll-behind content hides under it
            // — but only here, so content still visibly scrolls behind the bar itself.
            .background(Color(designSystemColor: .background))
        } else {
            Color.clear.frame(height: 0)
        }
    }

    enum Metrics {
        static let horizontalMargin: CGFloat = 24
        static let bottomInset: CGFloat = 16
        static let interCardSpacing: CGFloat = 20
    }
}
