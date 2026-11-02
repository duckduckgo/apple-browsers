//
//  SubscriptionWithdrawnView.swift
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
import DesignResourcesKitIcons

struct SubscriptionWithdrawnView: View {

    let confirmation: SubscriptionWithdrawalConfirmation

    var body: some View {
        List {
            Section {
                SubscriptionSettingsHeaderView(state: .withdrawn)
            }
            .listRowBackground(Color.clear)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, -20)
            .padding(.vertical, -10)

            Section(footer: Text(UserText.subscriptionWithdrawnRefundInfo(refundAmount: confirmation.refundAmount))) {
                HStack(spacing: 12) {
                    Image(uiImage: DesignSystemImages.Color.Size24.check)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(UserText.subscriptionWithdrawnInfo(withdrawalDate: confirmation.withdrawalDate))
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                }
            }
        }
        .padding(.top, -20)
        .navigationTitle(UserText.settingsPProManageSubscription)
        .applyInsetGroupedListStyle()
    }
}
