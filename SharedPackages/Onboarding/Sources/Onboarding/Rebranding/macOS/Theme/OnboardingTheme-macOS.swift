//
//  OnboardingTheme-macOS.swift
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

#if os(macOS)
import SwiftUI
import DesignResourcesKit

public extension OnboardingTheme {

    // Temporary values. To Replace when working on macOS project.
    static let macOSRebranding2026 = {
        let bubbleCornerRadius = 36.0
        let borderWidth = 1.5

        return OnboardingTheme(
            typography: .system,
            colorPalette: ColorPalette(
                bubbleBorder: Color(designSystemColor: .accentAltPrimary),
                bubbleBackground: Color(designSystemColor: .surfaceTertiary),
                bubbleShadow: Color.shade(0.03),
                textPrimary: Color(designSystemColor: .textPrimary),
                textSecondary: Color(designSystemColor: .textSecondary),
                primaryButtonBackgroundColor: Color(designSystemColor: .buttonsPrimaryDefault),
                primaryButtonTextColor: Color(designSystemColor: .buttonsPrimaryText)
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
