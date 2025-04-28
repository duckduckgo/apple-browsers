//
//  PreferencesPurchaseSubscriptionModel.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Subscription
import struct Combine.AnyPublisher
import enum Combine.Publishers
import FeatureFlags
import BrowserServicesKit
import os.log

public final class PreferencesPurchaseSubscriptionModel: ObservableObject {

    @Published var subscriptionStorefrontRegion: SubscriptionRegion = .usa

    @Published var shouldShowVPN: Bool = false
    @Published var shouldShowDBP: Bool = false
    @Published var shouldShowITR: Bool = false

    var currentPurchasePlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }

    lazy var sheetModel = SubscriptionAccessViewModel(actionHandlers: sheetActionHandler,
                                                      purchasePlatform: subscriptionManager.currentEnvironment.purchasePlatform)

    var shouldDirectlyLaunchActivationFlow: Bool {
        subscriptionManager.currentEnvironment.purchasePlatform == .stripe
    }

    private let subscriptionManager: SubscriptionManager
    private var accountManager: AccountManager {
        subscriptionManager.accountManager
    }
    private let openURLHandler: (URL) -> Void
    public let userEventHandler: (PreferencesSubscriptionModel.UserEvent) -> Void
    private let sheetActionHandler: SubscriptionAccessActionHandlers

    private var fetchSubscriptionDetailsTask: Task<(), Never>?

    private var signInObserver: Any?
    private var signOutObserver: Any?
    private var entitlementsObserver: Any?
    private var subscriptionChangeObserver: Any?

    public init(openURLHandler: @escaping (URL) -> Void,
                userEventHandler: @escaping (PreferencesSubscriptionModel.UserEvent) -> Void,
                sheetActionHandler: SubscriptionAccessActionHandlers,
                subscriptionManager: SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
        self.openURLHandler = openURLHandler
        self.userEventHandler = userEventHandler
        self.sheetActionHandler = sheetActionHandler
        self.subscriptionStorefrontRegion = currentStorefrontRegion()
    }

    @MainActor
    func didAppear() {
        self.subscriptionStorefrontRegion = currentStorefrontRegion()
    }

    @MainActor
    func purchaseAction() {
        openURLHandler(subscriptionManager.url(for: .purchase))
    }

    @MainActor
    func openLearnMore() {
        let learnMoreURL = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/adding-email")!
        openURLHandler(learnMoreURL)
    }

    @MainActor
    func openFAQ() {
        openURLHandler(subscriptionManager.url(for: .faq))
    }

    @MainActor
    func openPrivacyPolicy() {
        openURLHandler(URL(string: "https://duckduckgo.com/pro/privacy-terms")!)
    }

    private func currentStorefrontRegion() -> SubscriptionRegion {
        var region: SubscriptionRegion?

        switch currentPurchasePlatform {
        case .appStore:
            if #available(macOS 12.0, *) {
                region = subscriptionManager.storePurchaseManager().currentStorefrontRegion
            }
        case .stripe:
            region = .usa
        }

        return region ?? .usa
    }

    @MainActor
    private func updateAvailableSubscriptionFeatures() async {
        let features = await subscriptionManager.currentSubscriptionFeatures()

        shouldShowVPN = features.contains(.networkProtection)
        shouldShowDBP = features.contains(.dataBrokerProtection)
        shouldShowITR = features.contains(.identityTheftRestoration) || features.contains(.identityTheftRestorationGlobal)
    }
}
