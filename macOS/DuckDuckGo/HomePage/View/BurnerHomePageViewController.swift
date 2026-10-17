//
//  BurnerHomePageViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import PrivacyConfig
import SwiftUI
import Subscription

@MainActor
final class BurnerHomePageViewController: NSViewController {

    let appearancePreferences: AppearancePreferences
    let themeManager: ThemeManager
    let subscriptionPromoViewModel: SubscriptionPromoViewModel

    var openSubscriptionPage: (() -> Void)?

    required init?(coder: NSCoder) {
        fatalError("BurnerHomePageViewController: Bad initializer")
    }

    init(appearancePreferences: AppearancePreferences? = nil,
         themeManager: ThemeManager? = nil,
         subscriptionManager: any SubscriptionManager,
         promoDelegate: FireWindowSubscriptionPromoDelegate?,
         dateProvider: @escaping () -> Date = Date.init) {
        self.appearancePreferences = appearancePreferences ?? NSApp.delegateTyped.appearancePreferences
        self.themeManager = themeManager ?? NSApp.delegateTyped.themeManager
        self.subscriptionPromoViewModel = SubscriptionPromoViewModel(
            subscriptionManager: subscriptionManager,
            dateProvider: dateProvider,
            promoDelegate: promoDelegate
        )

        super.init(nibName: nil, bundle: nil)

        self.subscriptionPromoViewModel.onButtonAction = { [weak self] in
            self?.openSubscriptionPage?()
        }
    }

    override func loadView() {
        let rootView = BurnerHomePageView(promoViewModel: subscriptionPromoViewModel)
            .environmentObject(appearancePreferences)
            .environmentObject(themeManager)

        self.view = NSHostingView(rootView: rootView)
    }

    func updatePromoState(for tab: Tab) {
        let tabPromo = tab.subscriptionPromo

        subscriptionPromoViewModel.onPromoEvaluated = { [weak tabPromo] shouldShow in
            tabPromo?.markEvaluated(shouldShowPromo: shouldShow)
        }
        subscriptionPromoViewModel.onPromoDismissed = { [weak tabPromo] in
            tabPromo?.markForceDismissed()
        }

        subscriptionPromoViewModel.updateForTab(tabPromo?.promoState ?? .notEvaluated)
    }

}
