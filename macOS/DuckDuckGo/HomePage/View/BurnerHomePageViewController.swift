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
    private let subscriptionManager: any SubscriptionManager
    private let featureFlagger: FeatureFlagger

    var openSubscriptionPage: (() -> Void)?

    required init?(coder: NSCoder) {
        fatalError("BurnerHomePageViewController: Bad initializer")
    }

    init(appearancePreferences: AppearancePreferences? = nil,
         themeManager: ThemeManager? = nil,
         subscriptionManager: any SubscriptionManager,
         featureFlagger: FeatureFlagger,
         promoDelegate: FireWindowSubscriptionPromoDelegate?,
         dateProvider: @escaping () -> Date = Date.init) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.appearancePreferences = appearancePreferences ?? NSApp.delegateTyped.appearancePreferences
        self.themeManager = themeManager ?? NSApp.delegateTyped.themeManager
        self.subscriptionPromoViewModel = SubscriptionPromoViewModel(
            subscriptionManager: subscriptionManager,
            featureFlagger: featureFlagger,
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

    func createSnapshotView(promoState: TabPromoState, size: NSSize) -> NSView {
        let snapshotViewModel = SubscriptionPromoViewModel(
            subscriptionManager: subscriptionManager,
            featureFlagger: featureFlagger,
            pixelFiring: nil
        )
        snapshotViewModel.updateForTabPreview(promoState, isEligibleForFreeTrial: subscriptionPromoViewModel.isEligibleForFreeTrial)

        let rootView = BurnerHomePageView(promoViewModel: snapshotViewModel)
            .environmentObject(appearancePreferences)
            .environmentObject(themeManager)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let offscreenWindow = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        offscreenWindow.alphaValue = 0
        offscreenWindow.level = .init(-1)
        offscreenWindow.ignoresMouseEvents = true
        offscreenWindow.isExcludedFromWindowsMenu = true
        offscreenWindow.collectionBehavior = [.transient, .ignoresCycle]
        offscreenWindow.contentView = hostingView
        offscreenWindow.orderBack(nil)
        hostingView.layoutSubtreeIfNeeded()

        return hostingView
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
