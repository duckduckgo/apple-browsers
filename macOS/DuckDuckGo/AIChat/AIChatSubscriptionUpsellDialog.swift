//
//  AIChatSubscriptionUpsellDialog.swift
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

import AppKit
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKitIcons

/// Shown when the user taps a subscriber-only control (e.g. a locked reasoning effort) in the
/// duck.ai omnibar. Explains the upsell before routing to the subscription flow, rather than
/// navigating away immediately.
struct AIChatSubscriptionUpsellDialog: ModalView {
    @Environment(\.dismiss) private var dismiss

    /// The caller decides title, message, and button text based on the user's tier and StoreKit
    /// free-trial eligibility, since the dialog itself has no access to that state.
    var title: String = UserText.aiChatSubscriptionUpsellDialogTitle
    var message: String = UserText.aiChatSubscriptionUpsellDialogMessage
    var primaryButtonText: String = UserText.aiChatSubscriptionUpsellDialogUpgradeButton
    /// Hidden for an existing Plus subscriber — "activate a subscription bought elsewhere" doesn't
    /// apply to someone who already has one; they're upgrading it, not looking for it.
    var showsHaveSubscriptionButton: Bool = true
    var onSubscribe: (() -> Void)?
    var onHaveSubscription: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: DesignSystemImages.Color.Size96.duckAISubscription)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
            }

            VStack(spacing: 8) {
                Button {
                    onSubscribe?()
                    dismiss()
                } label: {
                    Text(primaryButtonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, pillShape: true))
                .keyboardShortcut(.defaultAction)

                if showsHaveSubscriptionButton {
                    Button {
                        onHaveSubscription?()
                        dismiss()
                    } label: {
                        Text(UserText.aiChatSubscriptionUpsellDialogHaveSubscriptionButton)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true))
                }

                Button {
                    dismiss()
                } label: {
                    Text(UserText.aiChatSubscriptionUpsellDialogNotNowButton)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true))
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 330)
    }
}
