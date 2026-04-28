//
//  SubscriptionPromoViewModel.swift
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

import Combine
import Common
import FeatureFlags
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import Subscription

protocol SubscriptionPromoPersisting {
    var fireTabVisitCount: Int { get set }
    var promoDismissedDate: Date? { get set }
    var promoDisplayCount: Int { get set }
    var promoDisplayWindowStart: Date? { get set }
}

struct SubscriptionPromoUserDefaultsPersistor: SubscriptionPromoPersisting {

    enum Key: String {
        case fireTabVisitCount = "subscription-promo.fire-tab-visit-count"
        case promoDismissedDate = "subscription-promo.dismissed-date"
        case promoDisplayCount = "subscription-promo.display-count"
        case promoDisplayWindowStart = "subscription-promo.display-window-start"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var fireTabVisitCount: Int {
        get { keyValueStore.object(forKey: Key.fireTabVisitCount.rawValue) as? Int ?? 0 }
        set { keyValueStore.set(newValue, forKey: Key.fireTabVisitCount.rawValue) }
    }

    var promoDismissedDate: Date? {
        get { keyValueStore.object(forKey: Key.promoDismissedDate.rawValue) as? Date }
        set {
            if let value = newValue {
                keyValueStore.set(value, forKey: Key.promoDismissedDate.rawValue)
            } else {
                keyValueStore.removeObject(forKey: Key.promoDismissedDate.rawValue)
            }
        }
    }

    var promoDisplayCount: Int {
        get { keyValueStore.object(forKey: Key.promoDisplayCount.rawValue) as? Int ?? 0 }
        set { keyValueStore.set(newValue, forKey: Key.promoDisplayCount.rawValue) }
    }

    var promoDisplayWindowStart: Date? {
        get { keyValueStore.object(forKey: Key.promoDisplayWindowStart.rawValue) as? Date }
        set {
            if let value = newValue {
                keyValueStore.set(value, forKey: Key.promoDisplayWindowStart.rawValue)
            } else {
                keyValueStore.removeObject(forKey: Key.promoDisplayWindowStart.rawValue)
            }
        }
    }
}

enum TabPromoState {
    case notEvaluated
    case evaluated(shouldShowPromo: Bool)
    case dismissed
}

enum SubscriptionPromoConstants {
    static let requiredVisitCount = 3
    static let dismissCooldownDays = 28
    static let maxDisplaysPerTimeWindow = 4
    static let displayWindowDays = 28
}

@MainActor
final class SubscriptionPromoViewModel: ObservableObject {

    private let subscriptionManager: any SubscriptionManager
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private var persistor: SubscriptionPromoPersisting
    private let locale: Locale
    private let dateProvider: () -> Date

    private let canUserPurchaseSubject = CurrentValueSubject<Bool, Never>(false)
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var shouldShowPromo: Bool = false {
        didSet {
            guard oldValue != shouldShowPromo else { return }
            promoDelegate?.updateVisibility(shouldShowPromo)
        }
    }
    @Published private(set) var isEligibleForFreeTrial: Bool = false

    private weak var promoDelegate: FireWindowSubscriptionPromoDelegate?

    var onButtonAction: (() -> Void)?
    var onPromoEvaluated: ((Bool) -> Void)?
    var onPromoDismissed: (() -> Void)?

    init(subscriptionManager: any SubscriptionManager,
         featureFlagger: FeatureFlagger,
         pixelFiring: PixelFiring? = PixelKit.shared,
         persistor: SubscriptionPromoPersisting? = nil,
         locale: Locale = .current,
         dateProvider: @escaping () -> Date = Date.init,
         promoDelegate: FireWindowSubscriptionPromoDelegate? = nil) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.persistor = persistor ?? SubscriptionPromoUserDefaultsPersistor(keyValueStore: UserDefaults.standard)
        self.locale = locale
        self.dateProvider = dateProvider
        self.promoDelegate = promoDelegate

        if featureFlagger.isFeatureOn(.subscriptionPromoFireWindow) {
            checkPurchaseEligibility()
        }
    }

    deinit {
        promoDelegate?.updateVisibility(false)
    }

    func updateForTab(_ state: TabPromoState) {
        switch state {
        case .dismissed:
            shouldShowPromo = false
        case .evaluated(let shouldShow):
            shouldShowPromo = shouldShow
            if shouldShow {
                pixelFiring?.fire(SubscriptionPromoPixel.promoViewed(isEligibleForFreeTrial: isEligibleForFreeTrial))
            }
        case .notEvaluated:
            guard canUserPurchaseSubject.value else { return }
            evaluatePromoVisibility()
        }
    }

    func dismiss() {
        pixelFiring?.fire(SubscriptionPromoPixel.promoDismissed(isEligibleForFreeTrial: isEligibleForFreeTrial))
        persistor.promoDismissedDate = dateProvider()
        shouldShowPromo = false
        onPromoDismissed?()
    }

    func onPromoButtonTapped() {
        pixelFiring?.fire(SubscriptionPromoPixel.promoCtaActioned(isEligibleForFreeTrial: isEligibleForFreeTrial))
        persistor.promoDismissedDate = dateProvider()
        onButtonAction?()
    }

    private func checkPurchaseEligibility() {
        switch subscriptionManager.currentEnvironment.purchasePlatform {
        case .appStore:
            canUserPurchaseSubject.send(subscriptionManager.hasAppStoreProductsAvailable)
            subscriptionManager.hasAppStoreProductsAvailablePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] canPurchase in
                    self?.canUserPurchaseSubject.send(canPurchase)
                }
                .store(in: &cancellables)
        case .stripe:
            canUserPurchaseSubject.send(true)
        }
    }

    /// Display conditions (feature flag and purchase eligibility are checked before evaluation in `updateForTab`):
    /// - en_US locale only
    /// - Non-subscriber only
    /// - Fire Tab visited >= 3 times
    /// - Not dismissed or CTA actioned within the 28-day cooldown (fallback when PromoQueue is off; PromoService handles this via `resultWhenHidden` when on)
    /// - Not shown more than 4 times in any given 28-day rolling window
    private func evaluatePromoVisibility() {
        var shouldShow = false
        defer {
            shouldShowPromo = shouldShow
            onPromoEvaluated?(shouldShow)
        }

        guard isENUSLocale else { return }
        guard !subscriptionManager.isSubscriptionPresent() else { return }
        guard persistor.fireTabVisitCount >= SubscriptionPromoConstants.requiredVisitCount else { return }
        guard !isDismissedWithinCooldown else { return }
        guard recordDisplayIfAllowed() else { return }

        isEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
        shouldShow = true

        pixelFiring?.fire(SubscriptionPromoPixel.promoDisplayed(isEligibleForFreeTrial: isEligibleForFreeTrial))
        pixelFiring?.fire(SubscriptionPromoPixel.promoViewed(isEligibleForFreeTrial: isEligibleForFreeTrial))
    }

    private var isENUSLocale: Bool {
        var languageCode: String?
        var regionCode: String?
        if #available(macOS 13, *) {
            languageCode = locale.language.languageCode?.identifier
            regionCode = locale.region?.identifier
        } else {
            languageCode = locale.languageCode
            regionCode = locale.regionCode
        }
        return languageCode == "en" && regionCode == "US"
    }

    /// Checks the rolling window display limit. If allowed, records the display and returns `true`.
    /// Returns `false` when the limit has been reached within the current window.
    private func recordDisplayIfAllowed() -> Bool {
        let now = dateProvider()
        if let windowStart = persistor.promoDisplayWindowStart {
            let daysSinceWindowStart = Calendar.current.numberOfDaysBetween(windowStart, and: now) ?? 0
            if daysSinceWindowStart >= SubscriptionPromoConstants.displayWindowDays {
                persistor.promoDisplayCount = 0
                persistor.promoDisplayWindowStart = now
            } else if persistor.promoDisplayCount >= SubscriptionPromoConstants.maxDisplaysPerTimeWindow {
                return false
            }
        } else {
            persistor.promoDisplayWindowStart = now
        }
        persistor.promoDisplayCount += 1
        return true
    }

    private var isDismissedWithinCooldown: Bool {
        guard let dismissedDate = persistor.promoDismissedDate else {
            return false
        }
        let daysSinceDismissal = Calendar.current.numberOfDaysBetween(dismissedDate, and: dateProvider()) ?? 0
        return daysSinceDismissal < SubscriptionPromoConstants.dismissCooldownDays
    }
}
