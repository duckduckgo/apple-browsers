//
//  SubscriptionTransactionErrorAlert.swift
//  DuckDuckGo
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

import SwiftUI

/// Shared error presentation for subscription flows (purchase flow and cancel-downgrade).
/// Maps transaction errors to alert content and builds consistent alerts.
enum SubscriptionTransactionErrorAlert {

    /// Alert variant; same as SubscriptionFlowView's SubscriptionErrorMessage.
    enum MessageType {
        case activeSubscription
        case appStore
        case backend
        case general
    }

    /// Whether to show an alert and which message type. Returns nil when no alert should be shown (e.g. user cancelled).
    /// Intentionally does not show alerts for missingEntitlements, failedToSetSubscription, or subscriptionExpired
    /// (may resolve later or are not actionable via a generic error dialog).
    static func displayContent(for error: SubscriptionPurchaseError?) -> MessageType? {
        guard let error = error else { return nil }
        switch error {
        case .cancelledByUser:
            return nil
        case .hasActiveSubscription:
            return .activeSubscription
        case .failedToRestorePastPurchase, .purchaseFailed, .purchasePendingTransaction:
            return .appStore
        case .failedToGetSubscriptionOptions, .generalError:
            return .backend
        case .missingEntitlements, .failedToSetSubscription, .subscriptionExpired:
            return nil
        }
    }

    /// Builds the Alert for the given message type. Caller provides dismiss and optional restore actions.
    static func alert(
        for messageType: MessageType,
        onDismiss: @escaping () -> Void,
        onRestore: (() -> Void)? = nil
    ) -> Alert {
        switch messageType {
        case .activeSubscription:
            return Alert(
                title: Text(UserText.subscriptionFoundTitle),
                message: Text(UserText.subscriptionFoundText),
                primaryButton: .cancel(Text(UserText.subscriptionFoundCancel), action: onDismiss),
                secondaryButton: .default(Text(UserText.subscriptionFoundRestore), action: onRestore ?? onDismiss)
            )
        case .appStore:
            return Alert(
                title: Text(UserText.subscriptionAppStoreErrorTitle),
                message: Text(UserText.subscriptionAppStoreErrorMessage),
                dismissButton: .cancel(Text(UserText.actionOK), action: onDismiss)
            )
        case .backend, .general:
            return Alert(
                title: Text(UserText.subscriptionBackendErrorTitle),
                message: Text(UserText.subscriptionBackendErrorMessage),
                dismissButton: .cancel(Text(UserText.subscriptionBackendErrorButton), action: onDismiss)
            )
        }
    }
}
