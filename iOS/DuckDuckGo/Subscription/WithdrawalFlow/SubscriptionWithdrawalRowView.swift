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
import Subscription

struct SubscriptionWithdrawalRowView: View {

    @ObservedObject var flow: SubscriptionWithdrawalFlowModel
    let subscription: DuckDuckGoSubscription?
    let onWithdrawn: (SubscriptionWithdrawalConfirmation) -> Void

    @State private var isShowingConfirmation = false

    var body: some View {
        if let offer = flow.offer(for: subscription) {
            SettingsCellView(label: UserText.subscriptionWithdrawFromContract,
                             subtitle: offer.eligibleUntil.map { UserText.subscriptionWithdrawFromContractSubtitle(eligibleUntil: $0) },
                             action: {
                                 flow.withdrawTapped()
                                 isShowingConfirmation = true
                             },
                             disclosureIndicator: true,
                             isButton: true)
            .alert(isPresented: $isShowingConfirmation) {
                confirmationAlert(offer: offer)
            }
            .background(
                Color.clear
                    .alert(isPresented: $flow.isShowingError) {
                        errorAlert
                    }
            )
        }
    }

    private func confirmationAlert(offer: SubscriptionWithdrawalOffer) -> Alert {
        Alert(
            title: Text(UserText.subscriptionWithdrawConfirmTitle),
            message: Text(flow.confirmationMessage(for: offer)),
            primaryButton: .destructive(Text(UserText.subscriptionWithdrawConfirmButton)) {
                Task {
                    guard let confirmation = await flow.withdraw() else { return }
                    onWithdrawn(confirmation)
                }
            },
            secondaryButton: .cancel(Text(UserText.subscriptionWithdrawKeepButton)) {
                flow.keepTapped()
            }
        )
    }

    private var errorAlert: Alert {
        Alert(
            title: Text(UserText.subscriptionBackendErrorTitle),
            message: Text(UserText.subscriptionWithdrawErrorMessage),
            primaryButton: .default(Text(UserText.subscriptionWithdrawErrorButton)) {
                flow.openHelpPage()
            },
            secondaryButton: .cancel(Text(UserText.actionOK))
        )
    }
}
