//
//  ColorPalette+BaseColors.swift
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

extension ColorPaletteDefinition {

    /// Proxy for retrieving base colors.
    ///
    /// It is necessary to create base colors via color palette definition,
    /// otherwise static usage in client code will end up immune to global palette changes.
    static func color(for baseColor: BaseColor) -> Color {
        switch baseColor {
        case .gray0: return Color.gray0
        case .gray10: return Color.gray10
        case .gray20: return Color.gray20
        case .gray30: return Color.gray30
        case .gray40: return Color.gray40
        case .gray50: return Color.gray50
        case .gray60: return Color.gray60
        case .gray70: return Color.gray70
        case .gray80: return Color.gray80
        case .gray85: return Color.gray85
        case .gray90: return Color.gray90
        case .gray100: return Color.gray100

        case .blue0: return Color.blue0
        case .blue10: return Color.blue10
        case .blue20: return Color.blue20
        case .blue30: return Color.blue30
        case .blue40: return Color.blue40
        case .blue50: return Color.blue50
        case .blue60: return Color.blue60
        case .blue70: return Color.blue70
        case .blue80: return Color.blue80
        case .blue90: return Color.blue90
        case .blue100: return Color.blue100

        case .red0: return Color.red0
        case .red10: return Color.red10
        case .red20: return Color.red20
        case .red30: return Color.red30
        case .red40: return Color.red40
        case .red50: return Color.red50
        case .red60: return Color.red60
        case .red70: return Color.red70
        case .red80: return Color.red80
        case .red90: return Color.red90
        case .red100: return Color.red100

        case .purple0: return Color.purple0
        case .purple10: return Color.purple10
        case .purple20: return Color.purple20
        case .purple30: return Color.purple30
        case .purple40: return Color.purple40
        case .purple50: return Color.purple50
        case .purple60: return Color.purple60
        case .purple70: return Color.purple70
        case .purple80: return Color.purple80
        case .purple90: return Color.purple90
        case .purple100: return Color.purple100

        case .yellow0: return Color.yellow0
        case .yellow10: return Color.yellow10
        case .yellow20: return Color.yellow20
        case .yellow30: return Color.yellow30
        case .yellow40: return Color.yellow40
        case .yellow50: return Color.yellow50
        case .yellow60: return Color.yellow60
        case .yellow70: return Color.yellow70
        case .yellow80: return Color.yellow80
        case .yellow90: return Color.yellow90
        case .yellow100: return Color.yellow100

        case .green0: return Color.green0
        case .green10: return Color.green10
        case .green20: return Color.green20
        case .green30: return Color.green30
        case .green40: return Color.green40
        case .green50: return Color.green50
        case .green60: return Color.green60
        case .green70: return Color.green70
        case .green80: return Color.green80
        case .green90: return Color.green90
        case .green100: return Color.green100

        }
    }
}
