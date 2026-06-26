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

/// Cookie Pop-up Protection opt-in dialog (iOS counterpart of the macOS dialog).
/// ponytail: visual-only — selection is local state, `Confirm` just calls `onConfirm`. No persistence yet.
struct CookiePopupProtectionOptInView: View {

    let onConfirm: () -> Void

    @StateObject private var optionsModel: RadioButtonViewModel = {
        let items = [
            RadioButtonItem(text: UserText.cookiePopupProtectionOptInModeOn),
            RadioButtonItem(text: UserText.cookiePopupProtectionOptInModeOff)
        ]
        return RadioButtonViewModel(
            items: items,
            selectedItem: items.first,
            configuration: RadioButtonConfiguration(
                font: .system(size: 16),
                selectedTextColor: Color(designSystemColor: .textPrimary),
                unselectedTextColor: Color(designSystemColor: .textPrimary),
                unselectedCheckboxColor: Color(designSystemColor: .iconsSecondary),
                cornerRadius: 16,
                horizontalPadding: 20,
                verticalPadding: 16,
                checkboxSize: 28,
                buttonSpacing: 12
            )
        )
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(rebrandable: "Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                HStack(spacing: 8) {
                    BadgeView(text: UserText.cookiePopupProtectionOptInBadge)
                    Text(UserText.cookiePopupProtectionOptInHeader.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                .padding(.bottom, 28)

                innerCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
        // Don't scroll/bounce when the content already fits.
        .bounceBasedOnSizeIfAvailable()
    }

    private var innerCard: some View {
        VStack(spacing: 0) {
            // ponytail: placeholder — no cookie-with-check asset on iOS yet; swap for the final one when imported.
            Image(systemName: "circle.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .foregroundColor(Color(designSystemColor: .iconsSecondary))
                .padding(.top, 32)
                .padding(.bottom, 20)

            Text(UserText.cookiePopupProtectionOptInTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)

            Text(UserText.cookiePopupProtectionOptInBody)
                .font(.system(size: 16))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

            RadioButtonView(viewModel: optionsModel)

            Button(UserText.cookiePopupProtectionOptInConfirm, action: onConfirm)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 24)

            Text(UserText.cookiePopupProtectionOptInFooter)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
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
    CookiePopupProtectionOptInView(onConfirm: {})
}
