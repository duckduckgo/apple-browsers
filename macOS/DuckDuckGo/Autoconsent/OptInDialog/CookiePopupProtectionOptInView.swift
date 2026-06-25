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

enum CookiePopupProtectionMode: CaseIterable, Identifiable {
    case rejectHideAccept
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .rejectHideAccept: return UserText.cookiePopupProtectionOptInModeOn
        case .off: return UserText.cookiePopupProtectionOptInModeOff
        }
    }
}

/// Centered opt-in card matching the Cookie Pop-up Protection design.
/// ponytail: visual-only — selection is local @State, `Done` just dismisses. No persistence yet.
struct CookiePopupProtectionOptInView: View {

    let onDone: () -> Void
    @State private var mode: CookiePopupProtectionMode = .rejectHideAccept

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
                Button(UserText.doneDialog, action: onDone)
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
            // ponytail: best-guess asset; swap for final cookie-with-check when imported.
            Image("CookieProtectionIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text(UserText.cookiePopupProtectionOptInTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.bottom, 8)

            Text(UserText.cookiePopupProtectionOptInBody)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            preferenceBox

            Text(UserText.cookiePopupProtectionOptInFooter)
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
            Text(UserText.cookiePopupProtectionOptInPreferenceTitle)
                .font(.system(size: 14))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .padding(.bottom, 2)

            Picker("", selection: $mode) {
                ForEach(CookiePopupProtectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                        .padding(.top, 8)
                }
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
/// ponytail: scrim is non-dismissing on purpose — it's an opt-in; only `Done` closes it.
struct CookiePopupProtectionOptInOverlayView: View {

    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // ponytail: absorb clicks on the backdrop so nothing behind reacts; non-dismissing on purpose.
                .onTapGesture {}
            CookiePopupProtectionOptInView(onDone: onDone)
        }
    }
}

#Preview {
    CookiePopupProtectionOptInOverlayView(onDone: {})
        .frame(width: 900, height: 760)
}
