//
//  FreemiumDBPFeature.swift
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
import BrowserServicesKit
import Subscription
import Freemium
import Combine
import OSLog

/// Constants for UserDefaults keys used by the Freemium DBP feature.
enum FreemiumDBPFeatureKeys {
    /// Overrides the privacy configuration to manually enable or disable the Freemium DBP feature.
    static let featureFlagOverride = "freemium.dbp.feature.flag.override"

    /// Overrides the App Store storefront check to simulate USA region eligibility.
    static let usaStorefrontOverride = "freemium.dbp.storefront.override"
}

/// Defines the behavior for the Freemium Data Broker Protection (DBP) feature, which allows non-subscribers
/// to access a limited version of DBP.
protocol FreemiumDBPFeature {

    /// A boolean indicating if the Freemium DBP feature is available, considering privacy config, auth status, and storefront.
    var isAvailable: Bool { get }

    /// Publishes updates to `isAvailable` when dependencies like privacy config or subscription status change.
    var isAvailablePublisher: AnyPublisher<Bool, Never> { get }

    /// Subscribes to dependency updates (privacy config, subscription status) to refresh feature availability.
    func subscribeToDependencyUpdates()
}

/// Default implementation of `FreemiumDBPFeature`.
///
/// This class manages the Freemium Personal Information Removal (DBP) feature availability based on:
/// 1. **Feature Flag**: Must be enabled in privacy configuration.
/// 2. **Authentication Status**: User must not be a subscriber.
/// 3. **StoreFront Restrictions**: User must be in the USA App Store storefront.
/// 4. **Purchase Capability**: User must be able to make purchases.
///
/// It also handles automatic offboarding of users if the feature becomes unavailable.
final class DefaultFreemiumDBPFeature: FreemiumDBPFeature {

    /// A boolean indicating if the Freemium DBP feature is currently available.
    /// This property aggregates all eligibility criteria.
    var isAvailable: Bool {
        isEligible && freemiumDBPUserStateManager.didActivate
    }

    /// Publishes `true` when feature availability changes.
    var isAvailablePublisher: AnyPublisher<Bool, Never> {
        isAvailableSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    /// Manages privacy configurations for the app, including feature flags.
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    /// Manages user subscriptions and authentication state.
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge

    /// Manages the user's state within the Freemium DBP system.
    private var freemiumDBPUserStateManager: FreemiumDBPUserStateManager

    /// Notification center for observing system and app-specific notifications.
    private let notificationCenter: NotificationCenter

    /// Handles disabling and cleanup of DBP data when offboarding users.
    private lazy var featureDisabler: DataBrokerProtectionFeatureDisabling = DataBrokerProtectionFeatureDisabler()

    /// UserDefaults instance for storing feature-specific preferences and overrides.
    private var userDefaults: UserDefaults

    /// Subject for publishing availability changes to subscribers.
    private let isAvailableSubject = PassthroughSubject<Bool, Never>()

    /// Stores Combine cancellables for automatic cleanup on deallocation.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initializes the Freemium DBP feature manager.
    ///
    /// - Parameters:
    ///   - privacyConfigurationManager: Manages privacy configurations for the app.
    ///   - subscriptionManager: Manages subscriptions for the user. Supports both V1 and V2 bridge.
    ///   - freemiumDBPUserStateManager: Manages the user state for Freemium DBP.
    ///   - notificationCenter: Observes notifications, defaulting to `.default`.
    ///   - featureDisabler: Optional feature disabler. If not provided, the default `DataBrokerProtectionFeatureDisabler` is used lazily.
    ///   - userDefaults: UserDefaults instance for storing preferences, defaulting to `.dbp`.
    init(privacyConfigurationManager: PrivacyConfigurationManaging,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         freemiumDBPUserStateManager: FreemiumDBPUserStateManager,
         notificationCenter: NotificationCenter = .default,
         featureDisabler: DataBrokerProtectionFeatureDisabling? = nil,
         userDefaults: UserDefaults = UserDefaults.dbp) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.subscriptionManager = subscriptionManager
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults

        // Use the provided feature disabler if available, otherwise initialize lazily.
        // This allows for dependency injection in tests.
        if let featureDisabler = featureDisabler {
            self.featureDisabler = featureDisabler
        }
    }

    // MARK: - Public Methods

    /// Subscribes to privacy config, subscription, and purchase capability updates to refresh availability.
    func subscribeToDependencyUpdates() {
        // Subscribe to privacy configuration updates
        privacyConfigurationManager.updatesPublisher
            .sink { [weak self] in
                guard let self = self else { return }

                Logger.freemiumDBP.debug("[Freemium DBP] Privacy Config Updated. Feature Availability = \(self.isAvailable)")
                self.isAvailableSubject.send(self.isAvailable)

                // Check if user should be offboarded due to configuration changes
                self.offBoardIfNecessary()
            }
            .store(in: &cancellables)

        // Subscribe to notifications about subscription changes
        notificationCenter.publisher(for: .subscriptionDidChange)
            .sink { [weak self] _ in
                guard let self = self else { return }

                Logger.freemiumDBP.debug("[Freemium DBP] Subscription Updated. Feature Availability = \(self.isAvailable)")
                self.isAvailableSubject.send(self.isAvailable)
            }
            .store(in: &cancellables)

        // Subscribe to available product updates for App Store Environment
        if subscriptionManager.currentEnvironment.purchasePlatform == .appStore {
            subscriptionManager.canPurchasePublisher
                .sink { [weak self] canPurchase in
                    guard let self = self else { return }

                    // Calculate availability manually for App Store to include purchase capability
                    // This provides more granular control over the availability calculation
                    // compared to the general isAvailable property
                    let featureEnabled = isFeatureFlagEnabled
                    let notCurrentUser = isNotACurrentUser
                    let storeFrontIsUSA = isUSAAppStorefront
                    let didActivate = freemiumDBPUserStateManager.didActivate
                    let available = featureEnabled && notCurrentUser && storeFrontIsUSA && canPurchase && didActivate
                    Logger.freemiumDBP.debug("[Freemium DBP] Subscription Updated. Feature Availability = \(available)")

                    self.isAvailableSubject.send(available)
                }
                .store(in: &cancellables)
        }
    }
}

/// Private extension containing eligibility logic and helper methods.
private extension DefaultFreemiumDBPFeature {

    // MARK: - Freemium Eligibility Logic

    /// Determines overall eligibility by combining feature flag, auth status, storefront, and purchase capability.
    var isEligible: Bool {
        isFeatureFlagEnabled && isNotACurrentUser && isUSAAppStorefront && canPurchaseSubscription
    }

    /// Checks if the feature flag is enabled in privacy config, with support for a debug override.
    var isFeatureFlagEnabled: Bool {
        if let featureFlagOverride {
            return featureFlagOverride
        }
        return privacyConfigurationManager.freemiumIsEnabled
    }

    /// Checks if the user is not a subscriber. Freemium is only for non-subscribed users.
    var isNotACurrentUser: Bool {
        !subscriptionManager.isUserAuthenticated
    }

    /// Checks for USA App Store storefront. Required for App Store builds, with a debug override.
    /// On macOS versions prior to 12.0, defaults to `false`.
    var isUSAAppStorefront: Bool {
        if let storefrontOverride {
            return storefrontOverride
        }
        guard subscriptionManager.platformIsAppStore else { return true }

        // Default to false for older macOS versions as a conservative approach
        var isUSStoreFront = false
        if #available(macOS 12.0, *) {
            // Check both subscription manager types for compatibility
            if let subscriptionManagerV1 = subscriptionManager as? SubscriptionManager {
                isUSStoreFront = subscriptionManagerV1.storePurchaseManager().currentStorefrontRegion == .usa
            } else if let subscriptionManagerV2 = subscriptionManager as? SubscriptionManagerV2 {
                isUSStoreFront = subscriptionManagerV2.storePurchaseManager().currentStorefrontRegion == .usa
            }
        }
        return isUSStoreFront
    }

    /// Checks if the user can make purchases. Always true for Stripe, based on `canPurchase` for App Store.
    var canPurchaseSubscription: Bool {
        subscriptionManager.isPotentialPurchaser
    }

    // MARK: - Offboarding Logic

    /// Determines if a user who has activated Freemium DBP should be offboarded.
    ///
    /// Offboarding occurs if the feature is disabled remotely for a non-subscribed, eligible user.
    /// This requires the user to have:
    /// - Activated the feature previously.
    /// - Not become a subscriber.
    /// - Remained in an eligible region with purchase capability.
    var shouldDisableAndDelete: Bool {
        guard freemiumDBPUserStateManager.didActivate else { return false }

        return !isFeatureFlagEnabled && isNotACurrentUser && isUSAAppStorefront && canPurchaseSubscription
    }

    /// Offboards a user by resetting state and deleting data if `shouldDisableAndDelete` is true.
    /// This is triggered automatically on privacy configuration updates.
    func offBoardIfNecessary() {
        if shouldDisableAndDelete {
            Logger.freemiumDBP.debug("[Freemium DBP] Feature Disabled: Offboarding")
            freemiumDBPUserStateManager.resetAllState()
            featureDisabler.disableAndDelete()
        }
    }

    // MARK: - Override Logic for Debugging

    /// Debug override for the feature flag from UserDefaults.
    var featureFlagOverride: Bool? {
        userDefaults.value(forKey: FreemiumDBPFeatureKeys.featureFlagOverride) as? Bool
    }

    /// Debug override for the storefront check from UserDefaults.
    var storefrontOverride: Bool? {
        userDefaults.value(forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride) as? Bool
    }
}

/// Extension to provide a computed property for checking if the Freemium DBP subfeature is enabled.
private extension PrivacyConfigurationManaging {
    /// `true` if the Freemium DBP subfeature is enabled in the privacy configuration.
    var freemiumIsEnabled: Bool {
        privacyConfig.isSubfeatureEnabled(DBPSubfeature.freemium)
    }
}

/// Extension to provide computed properties for subscription manager platform and purchase logic.
private extension SubscriptionAuthV1toV2Bridge {

    /// `true` if the subscription platform is App Store.
    var platformIsAppStore: Bool {
        currentEnvironment.purchasePlatform == .appStore
    }

    /// `true` if the user is a potential purchaser.
    ///
    /// The logic varies by platform:
    /// - **App Store**: Returns the actual `canPurchase` capability.
    /// - **Stripe**: Always returns `true`.
    var isPotentialPurchaser: Bool {
        let platform = currentEnvironment.purchasePlatform
        switch platform {
        case .appStore:
            return canPurchase
        case .stripe:
            return true
        }
    }
}
