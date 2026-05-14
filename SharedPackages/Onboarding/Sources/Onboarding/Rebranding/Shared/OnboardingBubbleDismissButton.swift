//
//  OnboardingBubbleDismissButton.swift
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
import DesignResourcesKitIcons

struct OnboardingBubbleDismissButton: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            #if os(iOS)
            Image(uiImage: DesignSystemImages.Glyphs.Size16.close)
            #elseif os(macOS)
            Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
            #endif
        }
        .buttonStyle(onboardingTheme.dismissButtonStyle.style)
    }
}

#if os(iOS)
#Preview("Onboarding Dismiss Button - Light") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingBubbleDismissButton(action: {})
            .padding()
            .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.light)
}

#Preview("Onboarding Dismiss Button - Dark") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingBubbleDismissButton(action: {})
            .padding()
            .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.dark)
}
#endif
