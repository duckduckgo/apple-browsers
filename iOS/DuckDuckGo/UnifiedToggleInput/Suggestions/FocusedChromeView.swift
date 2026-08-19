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

/// The bar-pinned escape hatch shown above the focused suggestions in non-typing states.
struct FocusedChromeView: View {

    let hatchModel: EscapeHatchModel?
    /// Gap between the bar's edge and the first chrome element (Figma: 6 top bar, 16 bottom bar).
    let topInset: CGFloat

    var body: some View {
        if let hatchModel {
            EscapeHatchView(model: hatchModel)
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
        /// Kept in step with `SuggestionsListView`'s cell edge so the hatch aligns with the rows.
        static let horizontalMargin: CGFloat = 16
        static let bottomInset: CGFloat = 16
    }
}
