//
//  ThemeName.swift
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

import Foundation
import DesignResourcesKit

enum ThemeName: String, CaseIterable {
    case `default`
    case coolGray
    case desert
    case green
    case orange
    case rose
    case slateBlue
    case violet
}

extension ThemeName {

    static var allCasesSorted: [ThemeName] {
        [
            .default, .coolGray, .slateBlue, .green, .violet, .rose, .orange, .desert
        ]
    }

    var designColorPalette: DesignResourcesKit.ColorPalette {
        switch self {
        case .default:
            .default
        case .coolGray:
            .coolGray
        case .desert:
            .desert
        case .green:
            .green
        case .orange:
            .orange
        case .rose:
            .rose
        case .slateBlue:
            .slateBlue
        case .violet:
            .violet
        }
    }
}
