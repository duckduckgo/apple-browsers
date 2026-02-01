//
//  OnboardingTheme.swift
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
import DesignResourcesKit

// MARK: - OnboardingTheme

public struct OnboardingTheme: Equatable {
    let typography: Typography
    let colorPalette: ColorPalette
    let bubbleInsets: EdgeInsets
    let bubbleCornerRadius: CGFloat
    let bubbleShadowRadius: CGFloat
    let bubbleShadowPosition: CGPoint
    let linearTitleTextAlignment: TextAlignment
    let linearBodyTextAlignment: TextAlignment
    let contextualTitleTextAlignment: TextAlignment
    let contextualBodyTextAlignment: TextAlignment
    let primaryButtonStyle: OnboardingButtonStyle
}

public extension OnboardingTheme {

    static let rebranding2026 = OnboardingTheme(
        typography: .duckSans,
        colorPalette: ColorPalette(
            bubbleBorder: Color(singleUseColor: .rebranding(.textPrimary)),
            bubbleBackground: Color(singleUseColor: .rebranding(.surfaceTertiary)),
            bubbleShadow: Color.shade(0.03),
            textPrimary: Color(singleUseColor: .rebranding(.textPrimary)),
            textSecondary: Color(singleUseColor: .rebranding(.textSecondary)),
            primaryButtonBackgroundColor: Color(singleUseColor: .rebranding(.accentAltPrimary)),
            primaryButtonTextColor: Color(singleUseColor: .controlWidgetBackground)
        ),
        bubbleInsets: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
        bubbleCornerRadius: 36.0,
        bubbleShadowRadius: 6.0,
        bubbleShadowPosition: CGPoint(x: 0, y: 7),
        linearTitleTextAlignment: .center,
        linearBodyTextAlignment: .center,
        contextualTitleTextAlignment: .leading,
        contextualBodyTextAlignment: .leading,
        primaryButtonStyle: OnboardingButtonStyle(
            id: .primary,
            style: AnyButtonStyle(OnboardingPrimaryButtonStyle())
        )
    )

}
