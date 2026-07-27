//
//  ManualColorTokens.swift
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

/// Colours the app uses that Figma's palette doesn't define.
///
/// They are the same in every palette and theme, so they live here once rather than being repeated
/// in each one. Most are candidates for either a real Figma token or a direct palette reference —
/// this file should shrink over time.
enum ManualColorTokens {

    // MARK: - Alert

    static var alertGreen: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Green.green40, darkColor: RebrandingColor.Green.green40)
    }
    static var alertYellow: DynamicColor { DynamicColor(lightColor: .alertYellow, darkColor: .alertYellow) }

    // MARK: - VPN

    static var vpnGreen: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Green.green20, darkColor: RebrandingColor.Green.green70)
    }
    static var vpnGreenPressed: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Green.green30, darkColor: RebrandingColor.Green.green80)
    }
    static var vpnGreenForeground: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Lilypad.lilypad90, darkColor: RebrandingColor.Lilypad.lilypad10)
    }
    static var vpnGreenForegroundPressed: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Lilypad.lilypad100, darkColor: RebrandingColor.Lilypad.lilypad0)
    }
    static var vpnYellow: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Pollen.pollen30, darkColor: RebrandingColor.Pollen.pollen70)
    }
    static var vpnYellowPressed: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Pollen.pollen40, darkColor: RebrandingColor.Pollen.pollen80)
    }
    static var vpnYellowForeground: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Pollen.pollen80, darkColor: RebrandingColor.Pollen.pollen20)
    }
    static var vpnYellowForegroundPressed: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Pollen.pollen90, darkColor: RebrandingColor.Pollen.pollen10)
    }

    // MARK: - Shield

    static var shieldPrivacy: DynamicColor {
        DynamicColor(lightColor: RebrandingColor.Lilypad.lilypad70, darkColor: RebrandingColor.Lilypad.lilypad50)
    }

    // MARK: - Buttons

    static var buttonsWhite: DynamicColor { DynamicColor(lightColor: .white, darkColor: .black) }

    static var buttonsPrimaryDefault: DynamicColor { DynamicColor(lightColor: .blue50, darkColor: .blue30) }
    static var buttonsPrimaryPressed: DynamicColor { DynamicColor(lightColor: .blue70, darkColor: .blue50) }
    static var buttonsPrimaryDisabled: DynamicColor { DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18)) }
    static var buttonsPrimaryText: DynamicColor { DynamicColor(lightColor: .white, darkColor: .shade(0.84)) }
    static var buttonsPrimaryTextDisabled: DynamicColor { DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36)) }

    static var buttonsSecondaryFillDefault: DynamicColor { DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18)) }
    static var buttonsSecondaryFillPressed: DynamicColor { DynamicColor(lightColor: .shade(0.18), darkColor: .tint(0.3)) }
    static var buttonsSecondaryFillDisabled: DynamicColor { DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18)) }
    static var buttonsSecondaryFillText: DynamicColor { DynamicColor(lightColor: .shade(0.84), darkColor: .white) }
    static var buttonsSecondaryFillTextDisabled: DynamicColor { DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36)) }

    // MARK: - System

    static var lines: DynamicColor {
        DynamicColor(lightHex: 0x1F1F1F, lightOpacity: 0.09, darkHex: 0xF9F9F9, darkOpacity: 0.12)
    }

    /// The spinner always used the default palette's colours, even under a theme.
    static var spinnerStart: DynamicColor {
        DynamicColor(lightHex: 0x000000, lightOpacity: 0.42, darkHex: 0xFFFFFF, darkOpacity: 0.6)
    }
    static var spinnerFinal: DynamicColor { DynamicColor(lightColor: .green60, darkColor: .green30) }

    // MARK: - Text

    static var textSuccess: DynamicColor { DynamicColor(lightColor: .green60, darkColor: .green30) }
    static var textLink: DynamicColor { DynamicColor(lightHex: 0x3969EF, darkHex: 0x7295F6) }

    // MARK: - Permission Center

    static var permissionCenterBackground: DynamicColor {
        DynamicColor(lightColor: .white, darkColor: Color(0x333333))
    }
    static var permissionCenterContainerBackground: DynamicColor {
        DynamicColor(lightColor: Color(0x000000).opacity(0.03), darkColor: Color(0xFFFFFF).opacity(0.06))
    }
    static var permissionWarningBackground: DynamicColor {
        DynamicColor(lightColor: Color(0xFFF0C2), darkColor: Color(0xC18010).opacity(0.16))
    }
    static var permissionReloadButtonBackground: DynamicColor {
        DynamicColor(lightColor: .white, darkColor: Color(0x857A6E))
    }
    static var permissionReloadButtonText: DynamicColor {
        DynamicColor(lightColor: Color(0x333333), darkColor: Color(0xE8E8E8))
    }
}
