//
//  SimplifiedSyncStyle.swift
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

enum SimplifiedSyncStyle {
    static let screenBackground = Color(baseColor: .gray90)
    static let instructionText = Color(baseColor: .gray30)
    static let primaryActionBackground = Color(baseColor: .blue20)
    static let subduedPanelBackground = Color.white.opacity(0.09)

    // Using this instead of a design system color, because the associated design system color
    // is semi-opaque and doesn't give us the correct appearance when we layer up the
    // various elements of the QR code panel.
    static let qrCodeBackground = Color(red: 0.92, green: 0.92, blue: 0.92)
}
