//
//  CookiePopupProtectionOptInView.swift
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
import DuckUI
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents

enum CookiePopupProtectionOptInVariant {
    case whenEnabled
    case whenDisabled

    var title: String {
        switch self {
        case .whenEnabled: return UserText.cookiePopupProtectionOptInEnabledTitle
        case .whenDisabled: return UserText.cookiePopupProtectionOptInDisabledTitle
        }
    }

    var message: String {
        switch self {
        case .whenEnabled: return UserText.cookiePopupProtectionOptInEnabledBody
        case .whenDisabled: return UserText.cookiePopupProtectionOptInDisabledBody
        }
    }

    var primaryOptionTitle: String {
        switch self {
        case .whenEnabled: return UserText.cookiePopupProtectionOptInEnabledPrimaryOption
        case .whenDisabled: return UserText.cookiePopupProtectionOptInDisabledPrimaryOption
        }
    }

    var secondaryOptionTitle: String {
        switch self {
        case .whenEnabled: return UserText.cookiePopupProtectionOptInEnabledSecondaryOption
        case .whenDisabled: return UserText.cookiePopupProtectionOptInDisabledSecondaryOption
        }
    }
}

enum CookiePopupProtectionOptInOption: Hashable {
    /// Top option — enable Cookie Pop-up Protection with the most-private handling.
    case optIn
    /// Bottom option — keep the current setting.
    case keepCurrent
}

/// Cookie Pop-up Protection opt-in dialog (iOS counterpart of the macOS dialog).
/// `Confirm` reports the selected option via `onConfirm`; the presenter applies the setting.
struct CookiePopupProtectionOptInView: View {

    private let variant: CookiePopupProtectionOptInVariant
    private let onConfirm: (CookiePopupProtectionOptInOption) -> Void
    @StateObject private var optionsModel: RadioButtonViewModel

    init(variant: CookiePopupProtectionOptInVariant, onConfirm: @escaping (CookiePopupProtectionOptInOption) -> Void) {
        self.variant = variant
        self.onConfirm = onConfirm
        let items = [
            RadioButtonItem(text: variant.primaryOptionTitle, value: CookiePopupProtectionOptInOption.optIn),
            RadioButtonItem(text: variant.secondaryOptionTitle, value: CookiePopupProtectionOptInOption.keepCurrent)
        ]
        _optionsModel = StateObject(wrappedValue: RadioButtonViewModel(
            items: items,
            selectedItem: items.first,
            configuration: RadioButtonConfiguration(
                font: .system(size: 16),
                selectedTextColor: Color(designSystemColor: .textPrimary),
                unselectedTextColor: Color(designSystemColor: .textPrimary),
                unselectedCheckboxColor: Color(designSystemColor: .iconsSecondary),
                cornerRadius: 16,
                horizontalPadding: 16,
                verticalPadding: 16,
                checkboxSize: 28,
                buttonSpacing: 12
            )
        ))
    }

    /// Footer with "Settings" and "Cookie Pop-Up Protection" rendered bold, and the "\n" in the string
    /// preserved as an explicit line break (default markdown parsing would collapse it into a space).
    private var footerText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: UserText.cookiePopupProtectionOptInFooter, options: options))
            ?? AttributedString(UserText.cookiePopupProtectionOptInFooter)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Decorative wave anchored to the bottom — it does not scroll. The flexible-width box keeps the
            // oversized asset from stretching the layout; the image fills + center-crops within it, so wider
            // screens (iPad) reveal more of it.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .overlay {
                    Image("dialog-bottom-wave-background")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()

            // The panel scrolls over the fixed wave when it doesn't fit; bottom inset keeps it clear of the wave.
            ScrollView {
                VStack(spacing: 0) {
                    Image(rebrandable: "Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .padding(.top, 24)
                        .padding(.bottom, 12)

                    HStack(spacing: 8) {
                        BadgeView(text: UserText.cookiePopupProtectionOptInBadge)
                        Text(verbatim: "DuckDuckGo".uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.6)
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                    .padding(.bottom, 28)

                    innerCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .bounceBasedOnSizeIfAvailable()
        }
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
    }

    private var innerCard: some View {
        VStack(spacing: 0) {
            Image(uiImage: DesignSystemImages.Color.Size96.cookieCheckFeature)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .padding(.top, 32)
                .padding(.bottom, 20)

            Text(variant.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 16)

            Text(variant.message)
                .font(.system(size: 18))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 24)

            RadioButtonView(viewModel: optionsModel)

            Button(UserText.cookiePopupProtectionOptInConfirm) {
                let selectedOption = optionsModel.selectedItem?.value as? CookiePopupProtectionOptInOption ?? .optIn
                onConfirm(selectedOption)
            }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 24)

            Text(footerText)
                .font(.system(size: 14))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(designSystemColor: .backgroundSheets))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(designSystemColor: .accentPrimary).opacity(0.3), lineWidth: 1)
        )
    }
}

private extension View {
    @ViewBuilder
    func bounceBasedOnSizeIfAvailable() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

#Preview {
    CookiePopupProtectionOptInView(variant: .whenDisabled, onConfirm: { _ in })
}
