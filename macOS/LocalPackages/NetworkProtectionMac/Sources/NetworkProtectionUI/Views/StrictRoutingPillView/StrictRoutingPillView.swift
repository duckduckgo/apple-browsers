//
//  StrictRoutingPillView.swift
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
import VPNUI

/// A compact status pill shown under the VPN status header while the VPN is on. It reflects the current
/// Strict routing state — green when on, amber when off — and takes the user to the relevant VPN setting
/// when tapped.
struct StrictRoutingPillView: View {

    /// The current Strict routing state, used to pick the pill's label and colour.
    let isStrictRoutingOn: Bool

    /// Invoked when the user taps the pill, to take them to the Strict routing setting.
    let onTap: () -> Void

    /// Whether the pointer is over the pill. Per the Figma spec the pill shows its interaction colour on
    /// hover (desktop), so the fill is driven by this rather than by the press state alone.
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: isStrictRoutingOn ? 6 : 4) {
                (isStrictRoutingOn ? VPNUIImages.strictRoutingLockOn : VPNUIImages.strictRoutingLockOff)
                    .resizable()
                    .frame(width: 12, height: 12)

                Text(isStrictRoutingOn
                     ? UserText.networkProtectionStrictRoutingPillOn
                     : UserText.networkProtectionStrictRoutingPillOff)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(StrictRoutingPillButtonStyle(isStrictRoutingOn: isStrictRoutingOn, isHovering: isHovering))
        .onHover { isHovering = $0 }
        .help(isStrictRoutingOn
              ? UserText.networkProtectionStrictRoutingPillTooltipOn
              : UserText.networkProtectionStrictRoutingPillTooltipOff)
    }
}

/// Renders the pill as a coloured capsule. On hover or press it shows the state's interaction colour —
/// green60 when on, yellow-20 when off.
private struct StrictRoutingPillButtonStyle: ButtonStyle {

    let isStrictRoutingOn: Bool
    let isHovering: Bool

    private static let cornerRadius: CGFloat = 12
    private static let height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(textColor)
            .padding(padding)
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: Self.cornerRadius).fill(fillColor(interactive: isHovering || configuration.isPressed)))
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    private var padding: EdgeInsets {
        isStrictRoutingOn
            ? EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10)
            : EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 8)
    }

    private var textColor: Color {
        isStrictRoutingOn ? .white : Color(designSystemColor: .vpnStrictRoutingInactiveText).opacity(0.9)
    }

    private func fillColor(interactive: Bool) -> Color {
        if isStrictRoutingOn {
            return Color(designSystemColor: interactive ? .vpnStrictRoutingActivePressed : .vpnStrictRoutingActive)
        }
        return Color(designSystemColor: interactive ? .vpnStrictRoutingInactivePressed : .vpnStrictRoutingInactive)
    }
}
