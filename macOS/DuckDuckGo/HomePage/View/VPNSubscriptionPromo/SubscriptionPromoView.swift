//
//  SubscriptionPromoView.swift
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
import PreferencesUI_macOS

struct SubscriptionPromoView: View {

    enum ActionType {
        case tryForFree
        case learnMore
    }

    let actionType: ActionType
    let promoCardWidth: CGFloat
    let onButtonTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        promoCard
    }

    private var promoCard: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
                .padding(.vertical, 14)
                .padding(.leading, 8)
                .padding(.trailing, 32)

            CloseButton(icon: .close, size: 16, backgroundColorOnHover: Color(designSystemColor: .controlsFillSecondary)) {
                onClose()
            }
            .padding(6)
        }
        .frame(width: promoCardWidth)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(designSystemColor: .toneTintPrimary))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1)
                )
        )
    }

    private var cardContent: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                iconView
                textContent
            }
            Spacer()
            actionButton
        }
    }

    private var iconView: some View {
        Image(.burnerWindowHomepageSubscriptionPromo)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: UserText.subscriptionPromoTitle)
                .font(.headline)
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Text(verbatim: UserText.subscriptionPromoSubtitle)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if actionType == .tryForFree {
            Button(action: onButtonTap) { Text(verbatim: UserText.subscriptionPromoTryForFree) }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, stateColors: .themedActionButton))
        } else {
            Button(action: onButtonTap) { Text(verbatim: UserText.subscriptionPromoLearnMore) }
                .buttonStyle(DismissActionButtonStyle())
        }
    }
}
