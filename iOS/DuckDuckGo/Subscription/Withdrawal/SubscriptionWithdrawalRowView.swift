//
//  SubscriptionWithdrawalRowView.swift
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
import DesignResourcesKit
import Subscription

struct SubscriptionWithdrawalRowView: View {

    @ObservedObject var withdrawal: SubscriptionWithdrawalModel
    let subscription: DuckDuckGoSubscription?
    let onWithdrawn: (SubscriptionWithdrawalConfirmation) async -> Void

    @State private var isShowingConfirmation = false

    var body: some View {
        if let offer = withdrawal.offer(for: subscription) {
            SettingsCustomCell(content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.subscriptionWithdrawFromContract)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .accentPrimary))
                    if let eligibleUntil = offer.eligibleUntil {
                        Text(UserText.subscriptionWithdrawFromContractSubtitle(eligibleUntil: eligibleUntil))
                            .daxFootnoteRegular()
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                }
            },
                               action: {
                                   withdrawal.withdrawTapped()
                                   isShowingConfirmation = true
                               },
                               disclosureIndicator: true,
                               isButton: true)
            .alert(isPresented: $isShowingConfirmation) {
                confirmationAlert(offer: offer)
            }
            .onChange(of: isShowingConfirmation) { isShowing in
                if isShowing {
                    withdrawal.confirmationShown()
                }
            }
            .background(
                Color.clear
                    .alert(isPresented: $withdrawal.isShowingError) {
                        errorAlert
                    }
            )
        }
    }

    private func confirmationAlert(offer: SubscriptionWithdrawalOffer) -> Alert {
        Alert(
            title: Text(UserText.subscriptionWithdrawConfirmTitle),
            message: Text(withdrawal.confirmationMessage(for: offer)),
            primaryButton: .destructive(Text(UserText.subscriptionWithdrawConfirmButton)) {
                Task {
                    guard let confirmation = await withdrawal.withdraw() else { return }
                    await onWithdrawn(confirmation)
                }
            },
            secondaryButton: .cancel(Text(UserText.subscriptionWithdrawKeepButton)) {
                withdrawal.keepTapped()
            }
        )
    }

    private var errorAlert: Alert {
        Alert(
            title: Text(UserText.subscriptionBackendErrorTitle),
            message: Text(UserText.subscriptionWithdrawErrorMessage),
            primaryButton: .default(Text(UserText.subscriptionWithdrawErrorButton)) {
                withdrawal.openHelpPage()
            },
            secondaryButton: .cancel(Text(UserText.actionOK))
        )
    }
}
