//
//  OnboardingRebrandColor.swift
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

#if os(iOS)
import SwiftUI
import UIKit
import DesignResourcesKit

/// Colours specific to the 2026 rebranded onboarding flow.
/// These are different to their counterparts in the app-wide rebranded palette, so they're kept separate here.
/// Ideally these should be migrated over to their nearest match counterparts in the main palette.
///
public enum OnboardingRebrandColor {

    /// Dax speech-bubble background.
    public static let surfaceTertiary = dynamic(light: 0xFFFFFF, dark: 0x011D34)

    /// Bubble border (light) and step-progress border / unselected dots.
    public static let accentAltPrimary = dynamic(light: 0xCBEAFF, dark: 0x133E7C)

    /// Selection highlights.
    public static let accentAltGlowPrimary = Color(0xA1CFF7, opacity: 0.16)

    /// Background accent wash.
    public static let backgroundAccent = dynamic(light: 0x7295F6, dark: 0x8FABF9, opacity: 0.2)

    public static let bubbleBorder = dynamic(light: 0xCBEAFF, dark: 0x011D34)

    private static func dynamic(light: UInt32, dark: UInt32, opacity: Double = 1) -> Color {
        Color(uiColor: UIColor { traitCollection in
            let hex = traitCollection.userInterfaceStyle == .dark ? dark : light
            return UIColor(Color(hex, opacity: opacity))
        })
    }
}
#endif
