//
//  RebrandedOnboardingAddressBarPositionPicker.swift
//  DuckDuckGo
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
import Onboarding

extension OnboardingRebranding.OnboardingView {

    struct OnboardingAddressBarPositionPicker: View {
        @StateObject private var viewModel = OnboardingAddressBarPositionPickerViewModel()

        var body: some View {
            VStack(spacing: AddressBarPositionPickerMetrics.itemSpacing) {
                ForEach(viewModel.items, id: \.type) { item in
                    AddressBarPositionButton(
                        icon: item.icon,
                        title: Self.strippingFontAttributes(from: item.title),
                        message: item.message,
                        isSelected: item.isSelected,
                        action: {
                            viewModel.setAddressBar(position: item.type)
                        }
                    )
                }
            }
        }

        /// Strips UIKit font attributes from the attributed string so that
        /// the SwiftUI `.font()` modifier on the `Text` view takes effect,
        /// while preserving color attributes from the shared view model.
        private static func strippingFontAttributes(from source: NSAttributedString) -> AttributedString {
            let mutable = NSMutableAttributedString(attributedString: source)
            mutable.removeAttribute(.font, range: NSRange(location: 0, length: mutable.length))
            return AttributedString(mutable)
        }
    }

}

private enum AddressBarPositionPickerMetrics {
    static let itemSpacing: CGFloat = 16.0
    static let iconSpacing: CGFloat = 12.0
    static let textSpacing: CGFloat = 0
    static let cornerRadius: CGFloat = 16.0
    static let borderWidth: CGFloat = 1.0
    static let minHeight: CGFloat = 63.0
    static let borderLightColor = Color.black.opacity(0.18)
    static let borderDarkColor = Color.white.opacity(0.18)

    static let accentColor = Color(singleUseColor: .rebranding(.accentPrimary))
}

extension OnboardingRebranding.OnboardingView.OnboardingAddressBarPositionPicker {

    struct AddressBarPositionButton: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.onboardingTheme) private var onboardingTheme

        let icon: ImageResource
        let title: AttributedString
        let message: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: AddressBarPositionPickerMetrics.iconSpacing) {
                    Image(icon)

                    VStack(alignment: .leading, spacing: AddressBarPositionPickerMetrics.textSpacing) {
                        Text(title)
                            .font(onboardingTheme.typography.row)
                        Text(message)
                            .font(onboardingTheme.typography.rowDetails)
                            .foregroundColor(onboardingTheme.colorPalette.textSecondary)
                    }

                    Spacer()

                    OnboardingRebranding.RadioIndicator(isSelected: isSelected, accentColor: AddressBarPositionPickerMetrics.accentColor)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AddressBarPositionPickerMetrics.cornerRadius)
                    .stroke(borderColor, lineWidth: AddressBarPositionPickerMetrics.borderWidth)
            }
            .buttonStyle(AddressBarPositionButtonStyle(isSelected: isSelected))
        }

        private var borderColor: Color {
            if isSelected {
                AddressBarPositionPickerMetrics.accentColor
            } else {
                colorScheme == .light ? AddressBarPositionPickerMetrics.borderLightColor : AddressBarPositionPickerMetrics.borderDarkColor
            }
        }

    }

}

private struct AddressBarPositionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: AddressBarPositionPickerMetrics.minHeight)
            .background(backgroundColor(isSelected: isSelected, isPressed: configuration.isPressed))
            .cornerRadius(AddressBarPositionPickerMetrics.cornerRadius)
            .contentShape(Rectangle())
    }

    private func backgroundColor(isSelected: Bool, isPressed: Bool) -> Color {
        if isSelected {
            return Color(singleUseColor: .rebranding(.accentAltGlowPrimary))
        } else if isPressed {
            return Color(designSystemColor: .buttonsGhostPressedFill)
        } else {
            return .clear
        }
    }
}
