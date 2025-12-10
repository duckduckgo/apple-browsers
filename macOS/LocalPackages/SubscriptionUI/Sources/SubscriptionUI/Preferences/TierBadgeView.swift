//
//  TierBadgeView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

struct TierBadgeView: View {
    enum Variant: String {
        case plus = "PLUS"
        case pro = "PRO"
    }

    let variant: Variant

    var body: some View {
        Text(variant.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .cornerRadius(12)
    }

    private var backgroundColor: Color {
        switch variant {
        case .plus:
            return Color(baseColor: .blue0)
        case .pro:
            return Color(baseColor: .yellow40)
        }
    }

    private var textColor: Color {
        switch variant {
        case .plus:
            return Color(baseColor: .blue90)
        case .pro:
            return Color(baseColor: .yellow100)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        TierBadgeView(variant: .plus)
        TierBadgeView(variant: .pro)
    }
    .padding()
}
