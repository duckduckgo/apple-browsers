//
//  RedesignedNewTabPageCardBackground.swift
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

import DesignResourcesKit
import SwiftUI

/// Shared raised surface for controls on the redesigned New Tab Page.
struct RedesignedNewTabPageCardBackground: View {
    private let cornerRadius: CGFloat = Metrics.cornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(Color(designSystemColor: .surfaceSecondary))
            .overlay(shape.strokeBorder(Color(designSystemColor: .shadowPrimary), lineWidth: Metrics.borderWidth))
            .overlay(
                shape
                    .inset(by: Metrics.highlightInset)
                    .stroke(Color(designSystemColor: .highlightDecoration), lineWidth: Metrics.highlightWidth)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            )
            .shadow(color: Color(designSystemColor: .shadowSecondary), radius: Metrics.nearShadowRadius, y: Metrics.nearShadowOffset)
            .shadow(color: Color(designSystemColor: .shadowSecondary), radius: Metrics.farShadowRadius, y: Metrics.farShadowOffset)
    }
}

private enum Metrics {
    static let cornerRadius: CGFloat = 28
    static let borderWidth: CGFloat = 1
    static let highlightInset: CGFloat = 0.5
    static let highlightWidth: CGFloat = 1
    static let nearShadowRadius: CGFloat = 4
    static let nearShadowOffset: CGFloat = 2
    static let farShadowRadius: CGFloat = 16
    static let farShadowOffset: CGFloat = 8
}
