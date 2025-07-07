//
//  SubscriptionAccessViewModel.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Subscription

public final class SubscriptionAccessViewModel {

    private var actionHandlers: SubscriptionAccessActionHandlers
    private let purchasePlatform: SubscriptionEnvironment.PurchasePlatform

    public var title = UserText.addSubscriptionModalTitle

    public var emailLabel = UserText.addViaEmailTitle
    public var emailDescription = UserText.addViaEmailDescription
    public var emailButtonTitle = UserText.addViaEmailButtonTitle

    public var appleAccountLabel = UserText.addViaAppleAccountTitle
    public var appleAccountDescription = UserText.addViaAppleAccountDescription
    public var appleAccountButtonTitle = UserText.addViaAppleAccountButtonTitle

    public var shouldShowRestorePurchase: Bool { purchasePlatform == .appStore }

    public init(actionHandlers: SubscriptionAccessActionHandlers,
                purchasePlatform: SubscriptionEnvironment.PurchasePlatform) {
        self.actionHandlers = actionHandlers
        self.purchasePlatform = purchasePlatform
    }

    public func handleEmailAction() {
        actionHandlers.openActivateViaEmailURL()
    }

    public func handleRestorePurchaseAction() {
        actionHandlers.restorePurchases()
    }
}

public final class SubscriptionAccessActionHandlers {
    var openActivateViaEmailURL: () -> Void
    var restorePurchases: () -> Void

    public init(openActivateViaEmailURL: @escaping () -> Void, restorePurchases: @escaping () -> Void) {
        self.openActivateViaEmailURL = openActivateViaEmailURL
        self.restorePurchases = restorePurchases
    }
}
