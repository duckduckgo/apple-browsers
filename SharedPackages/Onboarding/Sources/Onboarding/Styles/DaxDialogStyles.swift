//
//  DaxDialogStyles.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public enum OnboardingStyles {}

public extension OnboardingStyles {

    struct ListButtonStyle: ButtonStyle {
        @Environment(\.colorScheme) private var colorScheme

#if os(macOS)
        public static let defaultMaxHeight = 32.0
#else
        public static let defaultMaxHeight = 40.0
#endif
        private let maxHeight: CGFloat
        private var maxWidth: CGFloat? = .infinity

#if os(macOS)
        private let fontSize = 12.0
#else
        private let fontSize = 15.0
#endif

        @State private var isHovered = false

        public init(maxWidth: CGFloat? = .infinity, maxHeight: CGFloat = Self.defaultMaxHeight) {
            self.maxWidth = maxWidth
            self.maxHeight = maxHeight
        }

        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: fontSize, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .foregroundColor(foregroundColor(isPressed: configuration.isPressed, isHovered: isHovered))
                .padding()
                .frame(minWidth: 0, maxWidth: maxWidth, maxHeight: maxHeight)
                .background(backgroundColor(isPressed: configuration.isPressed, isHovered: isHovered))
                .cornerRadius(12)
                .contentShape(Rectangle()) // Makes whole button area tappable, when there's no background
                .onHover { hovering in
                    #if os(macOS)
                    self.isHovered = hovering
                    #endif
                }
        }

        private func foregroundColor(isPressed: Bool, isHovered: Bool) -> Color {
            switch (colorScheme, isPressed, isHovered) {
            case (.light, false, false):
                return .lightRestBlue
            case (.dark, false, false):
                return .darkRestBlue
            case (.light, false, true):
                return .lightHoverBlue
            case (.dark, false, true):
                return .darkHoverBlue
            case (.light, true, _):
                return .lightPressedBlue
            case (.dark, true, _):
                return .darkPressedBlue
            case (_, _, _):
                return .lightRestBlue
            }
        }

        private func backgroundColor(isPressed: Bool, isHovered: Bool) -> Color {
            switch (colorScheme, isPressed, isHovered) {
            case (.light, false, false):
                return .shade(0.01)
            case (.dark, false, false):
                return .tint(0.03)
            case (.light, false, true):
                return .shade(0.03)
            case (.dark, false, true):
                return .tint(0.06)
            case (.light, true, _):
                return .shade(0.06)
            case (.dark, true, _):
                return .tint(0.06)
            case (_, _, _):
                return .clear
            }
        }
    }

}

extension Color {
    static let lightRestBlue = Color(baseColor: .blue50)
    static let darkRestBlue = Color(baseColor: .blue30)
    static let lightHoverBlue = Color(baseColor: .blue60)
    static let darkHoverBlue = Color(baseColor: .blue20)
    static let lightPressedBlue = Color(baseColor: .blue70)
    static let darkPressedBlue = Color(baseColor: .blue10)
}
