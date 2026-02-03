//
//  OnboardingTheme-iOS.swift
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

// MARK: - Factory Helpers

public extension OnboardingTheme {

    /// Rebranding 2026 default onboarding theme.
    static let iOSRebranding2026 = {
        let bubbleCornerRadius = 36.0
        let borderWidth = 1.5

        return OnboardingTheme(
            typography: .system,
            colorPalette: ColorPalette(
                bubbleBorder: Color(singleUseColor: .rebranding(.accentAltPrimary)),
                bubbleBackground: Color(singleUseColor: .rebranding(.surfaceTertiary)),
                bubbleShadow: Color.shade(0.03),
                textPrimary: Color(singleUseColor: .rebranding(.textPrimary)),
                textSecondary: Color(singleUseColor: .rebranding(.textSecondary)),
                primaryButtonBackgroundColor: Color(singleUseColor: .rebranding(.buttonsPrimaryDefault)),
                primaryButtonTextColor: Color(singleUseColor: .rebranding(.buttonsPrimaryText))
            ),
            bubbleMetrics: BubbleMetrics(
                contentInsets: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
                cornerRadius: bubbleCornerRadius,
                borderWidth: borderWidth,
                shadowRadius: 6.0,
                shadowPosition: CGPoint(x: 0, y: 7)
            ),
            linearTitleTextAlignment: .center,
            linearBodyTextAlignment: .center,
            contextualTitleTextAlignment: .leading,
            contextualBodyTextAlignment: .leading,
            primaryButtonStyle: OnboardingButtonStyle(
                id: .primary,
                style: AnyButtonStyle(OnboardingPrimaryButtonStyle())
            )
        )
    }()

}
#endif
