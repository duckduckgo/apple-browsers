//
//  CookiePopupProtectionOptInView.swift
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
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons

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

enum CookiePopupProtectionOptInOption: CaseIterable, Identifiable {
    /// Top option — enable Cookie Pop-up Protection with the most-private handling.
    case optIn
    /// Bottom option — keep the current setting.
    case keepCurrent
    var id: Self { self }
}

/// Centered opt-in card matching the Cookie Pop-up Protection design.
/// `Confirm` reports the selected option via `onConfirm`; the presenter applies the setting.
struct CookiePopupProtectionOptInView: View {

    let variant: CookiePopupProtectionOptInVariant
    let onConfirm: (CookiePopupProtectionOptInOption) -> Void
    @State private var selectedOption: CookiePopupProtectionOptInOption = .optIn

    /// Footer with "Settings" and "Cookie Pop-Up Protection" rendered bold, and the "\n" in the string
    /// preserved as an explicit line break (default markdown parsing would collapse it into a space).
    private var footerText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: UserText.cookiePopupProtectionOptInFooter, options: options))
            ?? AttributedString(UserText.cookiePopupProtectionOptInFooter)
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar

            VStack(spacing: 24) {
                headerSection
                optionsBox
                    .padding(.horizontal, 8)
                footerRow
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(width: 403)
        .background(Color(designSystemColor: .surfaceSecondary))
        .cornerRadius(32)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    /// macOS-style titlebar: logo pinned left, NEW badge + header centered, hairline separator below.
    private var titlebar: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Image("OnboardingDax")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text(UserText.cookiePopupProtectionOptInBadge.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(designSystemColor: .alertYellow))
                        .foregroundColor(.black)
                        .cornerRadius(8)
                    Text(UserText.cookiePopupProtectionOptInHeader.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 16)

            Rectangle()
                .fill(Color(.blackWhite10))
                .frame(height: 1)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Color.Size96.cookieCheckFeature)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 72)

            Text(variant.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

            Text(variant.message)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }

    private var optionsBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            radioRow(.optIn, title: variant.primaryOptionTitle)
            radioRow(.keepCurrent, title: variant.secondaryOptionTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(designSystemColor: .surfacePrimary))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.blackWhite10), lineWidth: 1)
        )
    }

    /// Footer copy on the left, Confirm button hugging the right — a single row.
    private var footerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(footerText)
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onConfirm(selectedOption)
            } label: {
                Text(UserText.cookiePopupProtectionOptInConfirm)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Color(designSystemColor: .accentPrimary), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // Custom radio rows: the native radioGroup Picker gives no control over inter-option spacing.
    private func radioRow(_ option: CookiePopupProtectionOptInOption, title: String) -> some View {
        Button {
            selectedOption = option
        } label: {
            HStack(spacing: 10) {
                radioIndicator(isSelected: selectedOption == option)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func radioIndicator(isSelected: Bool) -> some View {
        if isSelected {
            ZStack {
                Circle().fill(Color(designSystemColor: .accentPrimary))
                Circle().fill(.white).frame(width: 6, height: 6)
            }
            .frame(width: 16, height: 16)
        } else {
            Circle()
                .strokeBorder(Color(designSystemColor: .iconsSecondary), lineWidth: 1.5)
                .frame(width: 16, height: 16)
        }
    }
}

/// Dimming scrim + centered card. This is what gets hosted over the tab.
/// scrim is non-dismissing on purpose — it's an opt-in; only `Confirm` closes it.
struct CookiePopupProtectionOptInOverlayView: View {

    let variant: CookiePopupProtectionOptInVariant
    let onConfirm: (CookiePopupProtectionOptInOption) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // absorb clicks on the backdrop so nothing behind reacts; non-dismissing on purpose.
                .onTapGesture {}
            CookiePopupProtectionOptInView(variant: variant, onConfirm: onConfirm)
        }
    }
}

#Preview {
    CookiePopupProtectionOptInOverlayView(variant: .whenDisabled, onConfirm: { _ in })
        .frame(width: 900, height: 760)
}
