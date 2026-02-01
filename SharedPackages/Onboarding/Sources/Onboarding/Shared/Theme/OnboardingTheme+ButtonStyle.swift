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

public enum OnboardingButtonStyleID {
    case primary
    case secondary
    case list
}

public struct OnboardingButtonStyle: Equatable {
    let id: OnboardingButtonStyleID
    let style: AnyButtonStyle

    public init(id: OnboardingButtonStyleID, style: AnyButtonStyle) {
        self.id = id
        self.style = style
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

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
