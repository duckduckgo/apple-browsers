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

    private static let narrowThreshold: CGFloat = 390
    private static let closeButtonSize: CGFloat = 26
    private static let closeButtonInset: CGFloat = 13

    let actionType: ActionType
    let promoCardWidth: CGFloat
    let onButtonTap: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var cardWidth: CGFloat = 0

    private var isNarrow: Bool {
        cardWidth < Self.narrowThreshold
    }

    var body: some View {
        promoCard
            .overlay(
                CloseButton(icon: .close, size: Self.closeButtonSize, backgroundColor: Color(designSystemColor: .surfaceSecondary), backgroundColorOnHover: Color(designSystemColor: .surfaceSecondary)) {
                    onClose()
                }
                .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 3, x: 0, y: 0)
                .offset(x: Self.closeButtonInset, y: -Self.closeButtonInset)
                .opacity(isHovering ? 1 : 0)
                .disabled(!isHovering)
                , alignment: .topTrailing
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var promoCard: some View {
        cardContent
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(width: promoCardWidth)
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        cardWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { newWidth in
                        cardWidth = newWidth
                    }
                }
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(designSystemColor: .surfaceSecondary))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.homeFavoritesGhost, lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private var cardContent: some View {
        if isNarrow {
            narrowLayout
        } else {
            wideLayout
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                iconView
                textContent
            }
            Spacer()
            actionButton
        }
    }

    private var narrowLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                iconView
                textContent
            }
            actionButton
        }
    }

    private var iconView: some View {
        Image(.burnerWindowHomepageSubscriptionPromo)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 64, height: 48)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(UserText.subscriptionPromoTitle)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Text(UserText.subscriptionPromoSubtitle)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }


    private var actionButton: some View {
        let isFreeTrial = actionType == .tryForFree
        return Button(action: onButtonTap) {
            Text(isFreeTrial ? UserText.subscriptionPromoTryForFree : UserText.subscriptionPromoLearnMore)
                .font(.system(size: 13))
                .foregroundColor(isFreeTrial ? Color(designSystemColor: .accentContentPrimary) : Color(designSystemColor: .textPrimary))
                .frame(maxWidth: isNarrow ? .infinity : nil)
                .padding(.vertical, 9.5)
                .padding(.horizontal, 12)
                .background(isFreeTrial ? Color(designSystemColor: .buttonsPrimaryDefault) : Color(designSystemColor: .controlsFillPrimary))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pointingHand.pop() }
        }
    }
}
