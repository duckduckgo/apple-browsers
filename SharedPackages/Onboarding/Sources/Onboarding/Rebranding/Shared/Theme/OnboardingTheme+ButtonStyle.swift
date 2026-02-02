//
//  OnboardingTheme+ButtonStyle.swift
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

/// Semantic identifiers for onboarding button styles.
public enum OnboardingButtonStyleID {
    /// Primary call-to-action button style.
    case primary
    /// Secondary call-to-action button style.
    case secondary
    /// List row button style.
    case list
}

/// Type-erased, equatable wrapper for onboarding button styles.
public struct OnboardingButtonStyle: Equatable {
    /// Semantic identifier used for equality and style selection.
    public let id: OnboardingButtonStyleID
    /// Type-erased SwiftUI button style implementation.
    public let style: AnyButtonStyle

    /// Creates an onboarding button style token.
    public init(id: OnboardingButtonStyleID, style: AnyButtonStyle) {
        self.id = id
        self.style = style
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Helpers

/// Type-erased adapter that stores any `ButtonStyle`.
public struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    public init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }

    public func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

// MARK: - Button Styles

// NOTE: Keep this style colocated with onboarding while rebranding is validated in this flow instead of DuckUI.
// This avoids exposing a partially adopted visual style to the rest of the app.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.onboardingTheme) private var onboardingTheme

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(onboardingTheme.typography.small)
            .foregroundColor(onboardingTheme.colorPalette.primaryButtonTextColor)
            .padding(.vertical)
            .padding(.horizontal, nil)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 40)
            .background(onboardingTheme.colorPalette.primaryButtonBackgroundColor)
            .cornerRadius(64.0)
    }

}
