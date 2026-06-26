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
    /// Shown when Cookie Pop-up Protection is already enabled.
    case handleMore
    /// Shown when Cookie Pop-up Protection is off.
    case handleAndHide

    var title: String {
        switch self {
        case .handleMore: return UserText.cookiePopupProtectionOptInEnabledTitle
        case .handleAndHide: return UserText.cookiePopupProtectionOptInDisabledTitle
        }
    }

    var message: String {
        switch self {
        case .handleMore: return UserText.cookiePopupProtectionOptInEnabledBody
        case .handleAndHide: return UserText.cookiePopupProtectionOptInDisabledBody
        }
    }

    var primaryOptionTitle: String {
        switch self {
        case .handleMore: return UserText.cookiePopupProtectionOptInEnabledPrimaryOption
        case .handleAndHide: return UserText.cookiePopupProtectionOptInDisabledPrimaryOption
        }
    }

    var secondaryOptionTitle: String {
        switch self {
        case .handleMore: return UserText.cookiePopupProtectionOptInEnabledSecondaryOption
        case .handleAndHide: return UserText.cookiePopupProtectionOptInDisabledSecondaryOption
        }
    }
}

private enum CookiePopupProtectionOptInOption: CaseIterable, Identifiable {
    case primary
    case secondary
    var id: Self { self }
}

/// Centered opt-in card matching the Cookie Pop-up Protection design.
/// ponytail: visual-only — selection is local @State, `Confirm` just dismisses. No persistence yet.
struct CookiePopupProtectionOptInView: View {

    let variant: CookiePopupProtectionOptInVariant
    let onConfirm: () -> Void
    @State private var selectedOption: CookiePopupProtectionOptInOption = .primary

    /// Footer with the "Settings > Cookie Pop-Up Protection" span rendered bold (via markdown in the string).
    private var footerText: AttributedString {
        (try? AttributedString(markdown: UserText.cookiePopupProtectionOptInFooter))
            ?? AttributedString(UserText.cookiePopupProtectionOptInFooter)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ponytail: best-guess asset; swap for final circular logo when imported.
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .padding(.top, 28)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                Text(UserText.cookiePopupProtectionOptInBadge.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(designSystemColor: .alertYellow))
                    .foregroundColor(.black)
                    .cornerRadius(6)
                Text(UserText.cookiePopupProtectionOptInHeader.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .padding(.bottom, 20)

            innerCard
                .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button(UserText.cookiePopupProtectionOptInConfirm, action: onConfirm)
                    .buttonStyle(DefaultActionButtonStyle(enabled: true))
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 460)
        .background(Color(designSystemColor: .surfaceSecondary))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    private var innerCard: some View {
        VStack(spacing: 0) {
            Image(nsImage: DesignSystemImages.Color.Size96.cookieCheckFeature)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text(variant.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.bottom, 8)

            Text(variant.message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            preferenceBox

            Text(footerText)
                .font(.system(size: 13))
                .multilineTextAlignment(.leading)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .background(Color(designSystemColor: .surfaceCanvas))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.blackWhite10), lineWidth: 1)
        )
    }

    private var preferenceBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $selectedOption) {
                Text(variant.primaryOptionTitle).tag(CookiePopupProtectionOptInOption.primary)
                Text(variant.secondaryOptionTitle).tag(CookiePopupProtectionOptInOption.secondary)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(designSystemColor: .surfaceSecondary))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.blackWhite10), lineWidth: 1)
        )
    }
}

/// Dimming scrim + centered card. This is what gets hosted over the tab.
/// ponytail: scrim is non-dismissing on purpose — it's an opt-in; only `Confirm` closes it.
struct CookiePopupProtectionOptInOverlayView: View {

    let variant: CookiePopupProtectionOptInVariant
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // ponytail: absorb clicks on the backdrop so nothing behind reacts; non-dismissing on purpose.
                .onTapGesture {}
            CookiePopupProtectionOptInView(variant: variant, onConfirm: onConfirm)
        }
    }
}

#Preview {
    CookiePopupProtectionOptInOverlayView(variant: .handleAndHide, onConfirm: {})
        .frame(width: 900, height: 760)
}
