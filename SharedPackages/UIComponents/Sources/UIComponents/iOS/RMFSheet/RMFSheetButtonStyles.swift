//
//  RMFSheetButtonStyles.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit

/// The full-width pill primary action of the RMF sheet (Figma `📱 Button`, Large / Primary).
public struct RMFSheetPrimaryButtonStyle: ButtonStyle {

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RMFSheetPillButton(
            configuration: configuration,
            foreground: Color(designSystemColor: .accentContentPrimary),
            background: Color(designSystemColor: .accentPrimary),
            pressedBackground: Color(designSystemColor: .accentTertiary)
        )
    }
}

/// The full-width pill secondary action of the RMF sheet (Figma `📱 Button`, Large / Secondary - Fill).
public struct RMFSheetSecondaryButtonStyle: ButtonStyle {

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RMFSheetPillButton(
            configuration: configuration,
            foreground: Color(designSystemColor: .textPrimary),
            background: Color(designSystemColor: .controlsFillPrimary),
            pressedBackground: Color(designSystemColor: .controlsFillSecondary)
        )
    }
}

enum RMFSheetButtonMetrics {
    static let minHeight: CGFloat = 50
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 13
}

private struct RMFSheetPillButton: View {
    let configuration: ButtonStyle.Configuration
    let foreground: Color
    let background: Color
    let pressedBackground: Color

    var body: some View {
        configuration.label
            .font(RMFSheetTypography.button)
            .foregroundColor(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, RMFSheetButtonMetrics.horizontalPadding)
            .padding(.vertical, RMFSheetButtonMetrics.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: RMFSheetButtonMetrics.minHeight)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? pressedBackground : background)
            )
            .contentShape(Capsule())
    }
}

#if DEBUG

#Preview("Buttons") {
    VStack(spacing: 8) {
        Button("Primary action") {}
            .buttonStyle(RMFSheetPrimaryButtonStyle())
        Button("Not now") {}
            .buttonStyle(RMFSheetSecondaryButtonStyle())
    }
    .padding(24)
}

#Preview("Buttons Dark") {
    VStack(spacing: 8) {
        Button("Primary action") {}
            .buttonStyle(RMFSheetPrimaryButtonStyle())
        Button("Not now") {}
            .buttonStyle(RMFSheetSecondaryButtonStyle())
    }
    .padding(24)
    .background(Color(designSystemColor: .surfaceTertiary))
    .preferredColorScheme(.dark)
}

#endif

#endif
