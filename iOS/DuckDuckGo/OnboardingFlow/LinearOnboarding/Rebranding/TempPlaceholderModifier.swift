//
//  TempPlaceholderModifier.swift
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

/// Overlays a small yellow "Temp" badge on any view.
///
/// Use this modifier to flag any SwiftUI View as temporary when the content will be replaced with final assets in a later milestone.
/// ```swift
/// LottieView(lottieFile: "some-old-asset")
///     .tempPlaceholder()
/// ```
private struct TempPlaceholderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .opacity(0.4)
            .overlay(alignment: .center) {
                Text(verbatim: "Temp")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        Capsule()
                            .fill(Color.yellow)
                    )
                    .padding(4)
            }
    }
}

extension View {
    /// Marks this view with a yellow "Temp" badge.
    func tempPlaceholder() -> some View {
        modifier(TempPlaceholderModifier())
    }
}
