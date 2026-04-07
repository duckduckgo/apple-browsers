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
import PreferencesUI_macOS

struct SubscriptionPromoView: View {

    enum ActionType {
        case tryForFree
        case learnMore
    }

    private static let narrowThreshold: CGFloat = 300

    let actionType: ActionType
    let onButtonTap: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var cardWidth: CGFloat = 0

    private var isNarrow: Bool {
        cardWidth < Self.narrowThreshold
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
                .padding(16)

            if isHovering {
                CloseButton(icon: .close, size: 16) {
                    onClose()
                }
                .padding(6)
            }
        }
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
        .background(Color.homeFavoritesBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.homeFavoritesGhost, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
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
        HStack(spacing: 12) {
            iconView
            textContent
            Spacer()
            actionButton
        }
    }

    private var narrowLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                iconView
                textContent
            }
            actionButton
                .frame(maxWidth: .infinity)
        }
    }

    private var iconView: some View {
        Image(.globeMulticolor16)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(UserText.subscriptionPromoTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text(UserText.subscriptionPromoSubtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch actionType {
        case .tryForFree:
            Button(action: onButtonTap) {
                Text(UserText.subscriptionPromoTryForFree)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        case .learnMore:
            Button(action: onButtonTap) {
                Text(UserText.subscriptionPromoLearnMore)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
