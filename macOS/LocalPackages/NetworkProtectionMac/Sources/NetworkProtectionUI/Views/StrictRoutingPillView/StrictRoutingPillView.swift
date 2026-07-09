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
import DesignResourcesKitIcons
import SwiftUI

/// A compact status pill shown under the VPN status header while the VPN is on. It reflects the current
/// Strict routing state — green when on, amber when off — and takes the user to the relevant VPN setting
/// when tapped.
struct StrictRoutingPillView: View {

    /// The current Strict routing state, used to pick the pill's label and colour.
    let isStrictRoutingOn: Bool

    /// Invoked when the user taps the pill, to take them to the Strict routing setting.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: isStrictRoutingOn ? 6 : 4) {
                Image(nsImage: DesignSystemImages.Color.Size24.lock)
                    .resizable()
                    .frame(width: 12, height: 12)

                Text(isStrictRoutingOn
                     ? UserText.networkProtectionStrictRoutingPillOn
                     : UserText.networkProtectionStrictRoutingPillOff)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(StrictRoutingPillButtonStyle(isStrictRoutingOn: isStrictRoutingOn))
    }
}

/// Renders the pill as a coloured capsule. The design treats this as a badge with no pressed state, so
/// pressing applies a simple dim as tap feedback.
private struct StrictRoutingPillButtonStyle: ButtonStyle {

    let isStrictRoutingOn: Bool

    private static let cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(textColor)
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Self.cornerRadius).fill(fillColor))
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var padding: EdgeInsets {
        isStrictRoutingOn
            ? EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10)
            : EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 8)
    }

    private var textColor: Color {
        isStrictRoutingOn ? .white : Color(designSystemColor: .vpnStrictRoutingInactiveText).opacity(0.9)
    }

    private var fillColor: Color {
        isStrictRoutingOn
            ? Color(designSystemColor: .vpnStrictRoutingActive)
            : Color(designSystemColor: .vpnStrictRoutingInactive)
    }
}
