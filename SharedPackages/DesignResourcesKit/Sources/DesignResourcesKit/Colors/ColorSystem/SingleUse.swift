//
//  SingleUse.swift
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
import SwiftUI

// Only add colors here which are NOT in the standard Color System.
// Keep `xHEXVAL` naming convention for custom colors to distinguish them from the Color System. Add comment with usage place(s).
extension Color {

    // Used in URL bar background light mode
    static let xEAEAEA = Color(0xEAEAEA)

    // Used in Experimental Backdrop light mode
    static let x1D2229 = Color(0x1D2229)

    // Used in Backdrop light mode
    static let x1E1E1E = Color(0x1E1E1E)

    // Used in Surface for dark mode
    static let x2F2F2F = Color(0x2F2F2F)

    // Used in Experimental Surface for dark mode
    static let x3A4047 = Color(0x3A4047)

    // Control widget background
    static let x818387 = Color(0x818387)

    // UnifiedFeedback fields background
    static let x1C1C1E = Color(0x1C1C1E)
}
