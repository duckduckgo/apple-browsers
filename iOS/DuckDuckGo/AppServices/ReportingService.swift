//
//  ReportingService.swift
//  DuckDuckGo
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

import Foundation
import Core
import WidgetKit
import BrowserServicesKit
import AttributedMetric
import PixelKit
import Subscription
import Combine
import AIChat
import SetDefaultBrowserCore
import ContentBlocking
import os.log

/// Reporting service for various metrics:
/// - AttributedMetric: https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053
final class ReportingService {

    let marketplaceAdPostbackManager = MarketplaceAdPostbackManager()
    let onboardingPixelReporter = OnboardingPixelReporter()
    let subscriptionDataReporter: SubscriptionDataReporting
    let featureFlagging: FeatureFlagger
    let attributedMetricManager: AttributedMetricManager
    
    private var cancellables = Set<AnyCancellable>()
    let privacyConfigurationManager: PrivacyConfigurationManaging
    let productSurfaceTelemetry: ProductSurfaceTelemetry

    var syncService: SyncService? {
        didSet {
            guard let syncService else { return }
            subscriptionDataReporter.injectSyncService(syncService.sync)
        }
    }

    init(fireproofing: Fireproofing,
         featureFlagging: FeatureFlagger,
         userDefaults: UserDefaults,
         pixelKit: PixelKit?,
         appDependencies: DependencyProvider,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         productSurfaceTelemetry: ProductSurfaceTelemetry) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.featureFlagging = featureFlagging
        self.subscriptionDataReporter = SubscriptionDataReporter(fireproofing: fireproofing)

        // AttributedMetric initialisation
        let errorHandler = AttributedMetricErrorHandler(pixelKit: pixelKit)
        let attributedMetricDataStorage = AttributedMetricDataStorage(userDefaults: userDefaults, errorHandler: errorHandler)
        let settingsProvider = DefaultAttributedMetricSettingsProvider(privacyConfig: privacyConfigurationManager.privacyConfig)
        let subscriptionStateProvider = DefaultSubscriptionStateProvider(subscriptionManager: appDependencies.subscriptionAuthV1toV2Bridge)
        let defaultBrowserProvider = AttributedMetricDefaultBrowserProvider()
        self.attributedMetricManager = AttributedMetricManager(pixelKit: pixelKit,
                                                               dataStoring: attributedMetricDataStorage,
                                                               featureFlagger: featureFlagging,
                                                               originProvider: nil,
                                                               defaultBrowserProviding: defaultBrowserProvider,
                                                               subscriptionStateProvider: subscriptionStateProvider,
                                                               settingsProvider: settingsProvider)
        self.productSurfaceTelemetry = productSurfaceTelemetry
        addNotificationsObserver()
    }

    private func addNotificationsObserver() {
        NotificationCenter.default.addObserver(forName: .didFetchConfigurationOnForeground,
                                               object: nil,
                                               queue: .main) { _ in
            self.sendAppLaunchPostback(marketplaceAdPostbackManager: self.marketplaceAdPostbackManager)
        }
        NotificationCenter.default.addObserver(forName: .didLoadStatisticsOnForeground,
                                               object: nil,
                                               queue: .main) { _ in
            self.onStatisticsLoaded()
        }

        // Register for standard notifications or specific ones coming from frameworks like Subscription and relaunch them to AttributedMetric

        // App start
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: attributedMetricManager.workQueue)
            .sink { [weak self] _ in
                self?.attributedMetricManager.process(trigger: .appDidStart)
            }
            .store(in: &cancellables)

        // Search

        NotificationCenter.default.publisher(for: .userDidPerformDDGSearch)
            .receive(on: attributedMetricManager.workQueue)
            .sink { [weak self] _ in
                self?.attributedMetricManager.process(trigger: .userDidSearch)
            }
            .store(in: &cancellables)

        // AD click

        NotificationCenter.default.publisher(for: .userDidSelectDDGAD)
            .receive(on: attributedMetricManager.workQueue)
            .sink { [weak self] _ in
                self?.attributedMetricManager.process(trigger: .userDidSelectAD)
            }
            .store(in: &cancellables)

        // New AI chat message sent

        NotificationCenter.default.publisher(for: .aiChatUserDidSubmitPrompt)
            .receive(on: attributedMetricManager.workQueue)
            .sink { [weak self] _ in
                self?.attributedMetricManager.process(trigger: .userDidDuckAIChat)
            }
            .store(in: &cancellables)

        // User purchased subscription

        NotificationCenter.default.publisher(for: .userDidPurchaseSubscription)
            .receive(on: attributedMetricManager.workQueue)
            .sink { [weak self] _ in
                self?.attributedMetricManager.process(trigger: .userDidSubscribe)
            }
            .store(in: &cancellables)

        // Device sync

        NotificationCenter.default.publisher(for: .syncDevicesUpdate)
            .receive(on: attributedMetricManager.workQueue)
            .sink { [weak self] notification in
                guard let deviceCount = notification.userInfo?[AttributedMetricNotificationParameter.syncCount.rawValue] as? Int else {
                    assertionFailure("Missing \(AttributedMetricNotificationParameter.syncCount.rawValue)")
                    return
                }
                self?.attributedMetricManager.process(trigger: .userDidSync(devicesCount: deviceCount))
            }
            .store(in: &cancellables)
    }

    private func sendAppLaunchPostback(marketplaceAdPostbackManager: MarketplaceAdPostbackManaging) {
        // Attribution support
        if privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .marketplaceAdPostback) {
            marketplaceAdPostbackManager.sendAppLaunchPostback()
        }
    }

    private func onStatisticsLoaded() {
        Pixel.fire(pixel: .appLaunch, includedParameters: [.appVersion, .atb])
        reportWidgetUsage()
        productSurfaceTelemetry.dailyActiveUser()
        onboardingPixelReporter.fireEnqueuedPixelsIfNeeded()
        reportUserNotificationAuthStatus()
    }

    func setupStorageForMarketPlacePostback() {
        marketplaceAdPostbackManager.updateReturningUserValue()
    }

    // MARK: - Resume

    func resume() {
        Task {
            await subscriptionDataReporter.saveWidgetAdded()
        }
        reportFailedCompilationsPixelIfNeeded()
        AppDependencyProvider.shared.persistentPixel.sendQueuedPixels { _ in }
    }

    // MARK: - Suspend

    func suspend() {
        subscriptionDataReporter.saveApplicationLastSessionEnded()
    }

}

// MARK: - Pixels

private extension ReportingService {
    
    func reportWidgetUsage() {
        guard featureFlagging.isFeatureOn(.widgetReporting) else { return }
        WidgetCenter.shared.getCurrentConfigurations { result in
            switch result {
            case .success(let widgetInfo):
                if widgetInfo.count > 0 {
                    let enabledWidgets = widgetInfo.map {
                        "\($0.id.kind)-\($0.family.debugDescription)"
                    }.joined(separator: ",")

                    // This is all over kill but the feature is disabled so only the device(s) in a bad state will send this.
                    let featureState = self.privacyConfigurationManager.privacyConfig.stateFor(iOSBrowserConfigSubfeature.widgetReporting)
                    let isInternalUser = self.privacyConfigurationManager.internalUserDecider.isInternalUser
                    let embeddedEtag = (self.privacyConfigurationManager as? PrivacyConfigurationManager)?.embeddedConfigData.etag ?? "none"
                    let fetchedEtag = (self.privacyConfigurationManager as? PrivacyConfigurationManager)?.fetchedConfigData?.etag ?? "none"
                    let currentEtag = self.privacyConfigurationManager.privacyConfig.identifier

                    DailyPixel.fireDaily(.widgetReport, withAdditionalParameters: [
                        "enabled_widgets": enabledWidgets,
                        "privacy_config_embedded_etag": embeddedEtag,
                        "privacy_config_fetched_etag": fetchedEtag,
                        "current_etag": currentEtag,
                        "is_internal": "\(isInternalUser)",
                        "feature_state_enabled": "\(featureState == .enabled)"
                    ])
                }

            case .failure(let error):
                DailyPixel.fire(pixel: .widgetReportFailure, error: error)
            }
        }
    }
    
    func reportUserNotificationAuthStatus() {
        Task.detached(priority: .utility) {
            let status = await UNUserNotificationCenter.current().authorizationStatus()
            // We only care about authorized or denined at the moment for provisional notification
            guard status == .authorized || status == .denied else { return }
            DailyPixel.fire(pixel: .userNotificationAuthorizationStatusDaily, withAdditionalParameters: [
                "status": status.stringValue
            ])
        }
    }
    
    func reportFailedCompilationsPixelIfNeeded() {
        let store = FailedCompilationsStore()
        if store.hasAnyFailures {
            DailyPixel.fire(pixel: .compilationFailed, withAdditionalParameters: store.summary) { error in
                guard error != nil else { return }
                store.cleanup()
            }
        }
    }
}

struct DefaultAttributedMetricSettingsProvider: AttributedMetricSettingsProviding {
    let privacyConfig: PrivacyConfiguration

    var bucketsSettings: [String: Any] {
        privacyConfig.settings(for: .attributedMetrics)
    }

    var originSendList: [String] {
        guard let originSettingString = privacyConfig.settings(for: AttributedMetricsSubfeature.sendOriginParam),
              let settingsData = originSettingString.data(using: .utf8),
              let settings = try? JSONDecoder().decode(OriginSettings.self, from: settingsData) else {
            Logger.attributedMetric.error("Failed to decode origin settings, returning empty list")
            return []
        }
        return settings.originCampaignSubstrings
    }
}

struct AttributedMetricDefaultBrowserProvider: AttributedMetricDefaultBrowserProviding {

    let defaultBrowserManager = DefaultBrowserManager(defaultBrowserInfoStore: DefaultBrowserInfoStore(),
                                                      defaultBrowserEventMapper: DefaultBrowserPromptManagerDebugPixelHandler(), defaultBrowserChecker: SystemCheckDefaultBrowserService(application: UIApplication.shared))

    var isDefaultBrowser: Bool {
        let result = defaultBrowserManager.defaultBrowserInfo()
        switch result {
        case .failure(let error):
            switch error {
            case .notSupportedOnCurrentOSVersion:
                return false
            case .unknownError:
                return false
            case .rateLimitReached(let updatedStoredInfo):
                return updatedStoredInfo?.isDefaultBrowser ?? false
            }
        case .success(newInfo: let newInfo):
            return newInfo.isDefaultBrowser
        }
    }
}

struct DefaultSubscriptionStateProvider: SubscriptionStateProviding {

    let subscriptionManager: SubscriptionAuthV1toV2Bridge

    func isFreeTrial() async -> Bool {
        (try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).hasActiveTrialOffer) ?? false
    }
    
    var isActive: Bool {
        subscriptionManager.isUserAuthenticated
    }
}
