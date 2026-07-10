//
//  SubscriptionExpiredView.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit

struct SubscriptionExpiredView: View {
    enum Constants {
        static let backgroundCornerRadius = 16.0
        static let legacyBackgroundCornerRadius = 6.0
    }

    let subscribeButtonHandler: () -> Void
    let uninstallButtonHandler: () -> Void

    /// Captured at init so it stays stable for the view's lifetime.
    let isAppRebranded: Bool

    init(subscribeButtonHandler: @escaping () -> Void,
         uninstallButtonHandler: @escaping () -> Void,
         isAppRebranded: Bool = DesignSystemRebrand.isAppRebranded()) {
        self.subscribeButtonHandler = subscribeButtonHandler
        self.uninstallButtonHandler = uninstallButtonHandler
        self.isAppRebranded = isAppRebranded
    }

    private var cornerRadius: CGFloat {
        isAppRebranded ? Constants.backgroundCornerRadius : Constants.legacyBackgroundCornerRadius
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(UserText.networkProtectionSubscriptionExpiredTitle)
                .font(.system(size: 13).weight(.bold))
                .foregroundColor(Color(.defaultText))
                .multilineText()

            Text(UserText.networkProtectionSubscriptionExpiredSubtitle)
                .font(.system(size: 13))
                .foregroundColor(Color(.defaultText))
                .multilineText()

            Button(UserText.networkProtectionSubscriptionExpiredResubscribeButton, action: subscribeButtonHandler)
                .buttonStyle(DefaultActionButtonStyle(enabled: true))
                .padding(.top, 3)

            Divider()
                .padding(.top, 8)
                .padding(.bottom, 3)

            Button(UserText.networkProtectionSubscriptionExpiredUninstallButton, action: uninstallButtonHandler)
                .buttonStyle(TransparentActionButtonStyle(enabled: true))
                .foregroundColor(.accentColor)
                .padding(.top, 3)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .cornerRadius(8)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                .stroke(Color(.onboardingStepBorder), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                        .fill(Color(.onboardingStepBackground))
                )
        )
    }
}

struct SubscriptionExpiredView_Preview: PreviewProvider {
    static var previews: some View {
        SubscriptionExpiredView(subscribeButtonHandler: {}, uninstallButtonHandler: {})
    }
}
