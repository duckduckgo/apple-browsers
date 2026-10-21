//
//  TierBadgeView.swift
//  DuckDuckGo
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

import SwiftUI
import DesignResourcesKit

struct TierBadgeView: View {
    enum Variant {
        case plus
        case pro

        var displayName: String {
            switch self {
            case .plus: return "PLUS"
            case .pro: return "PRO"
            }
        }

        var fontWeight: Font.Weight {
            switch self {
            case .plus: return .semibold
            case .pro: return .bold
            }
        }
    }

    let variant: Variant

    var body: some View {
        Text(variant.displayName)
            .font(.system(size: 13, weight: variant.fontWeight))
            .kerning(0.12)
            .foregroundColor(Color(designSystemColor: .textPrimary))
    }
}

#Preview {
    VStack(spacing: 16) {
        TierBadgeView(variant: .plus)
        TierBadgeView(variant: .pro)
    }
    .padding()
}
