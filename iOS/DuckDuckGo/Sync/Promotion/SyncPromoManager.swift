//
//  SyncPromoManager.swift
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

import Foundation
import Bookmarks
import PrivacyConfig
import Common
import FoundationExtensions
import Core
import Persistence
import DDGSync
import FeatureFlags_iOS
import PixelKit

protocol SyncPromoManaging {
    func shouldPresentPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, count: Int) -> Bool
    func designFor(_ touchpoint: SyncPromoManager.Touchpoint) -> SyncPromoManager.Design
    func markPromoHandledFor(_ touchpoint: SyncPromoManager.Touchpoint)
    func recordImpressionFor(_ touchpoint: SyncPromoManager.Touchpoint)
    func recordPromoConfirmedFor(_ touchpoint: SyncPromoManager.Touchpoint)
    func dismissPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, reason: SyncPromoManager.DismissalReason)
    func resetPromos()
}

extension SyncPromoManaging {
    func designFor(_ touchpoint: SyncPromoManager.Touchpoint) -> SyncPromoManager.Design {
        .standard
    }
}

enum SyncPromoStorageKeyNames: String, StorageKeyDescribing {
    case aiChatDismissed = "sync-promo-ai-chat-dismissed"
    case aiChatImpressions = "sync-promo-ai-chat-impressions"
    case syncedDevicesCount = "sync-promo-synced-devices-count"
    case setupPromoConfirmed = "sync-promo-setup-promo-confirmed"
    case bookmarksAnotherDeviceDismissed = "sync-promo-bookmarks-another-device-dismissed"
}

struct SyncPromoStorageKeys: StoringKeys {
    let aiChatDismissed = StorageKey<Date>(SyncPromoStorageKeyNames.aiChatDismissed)
    let aiChatImpressions = StorageKey<Int>(SyncPromoStorageKeyNames.aiChatImpressions)
    let syncedDevicesCount = StorageKey<Int>(SyncPromoStorageKeyNames.syncedDevicesCount)
    let setupPromoConfirmed = StorageKey<Date>(SyncPromoStorageKeyNames.setupPromoConfirmed)
    let bookmarksAnotherDeviceDismissed = StorageKey<Date>(SyncPromoStorageKeyNames.bookmarksAnotherDeviceDismissed)
}

final class SyncPromoManager: SyncPromoManaging {

    enum Touchpoint: String {
        case bookmarks
        case passwords
        case dataImport = "data_import"
        case aiChat = "ai_chat"
        case bookmarksAnotherDevice = "bookmarks_another_device"
    }

    enum DismissalReason: String {
        case userTapped = "user_tapped"
        case impressionCap = "impression_cap"
    }

    enum Design {
        case standard
        case redesigned
    }

    static let aiChatImpressionCap = 5
    static let redesignMinimumDaysSinceInstall = 3
    static let syncAnotherDeviceMinimumDaysSinceInstall = 7
    static let syncAnotherDeviceSetupPromoCooldown: TimeInterval = 24 * 60 * 60

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let storage: any KeyedStoring<SyncPromoStorageKeys>
    private let pixelFiring: (any PixelKitFiring)?
    private let installDateProvider: () -> Date?
    private let currentDateProvider: () -> Date

    @UserDefaultsWrapper(key: .syncPromoBookmarksDismissed, defaultValue: nil)
    private var syncPromoBookmarksDismissed: Date?

    @UserDefaultsWrapper(key: .syncPromoPasswordsDismissed, defaultValue: nil)
    private var syncPromoPasswordsDismissed: Date?

    @UserDefaultsWrapper(key: .syncPromoDataImportDismissed, defaultValue: nil)
    private var syncPromoDataImportDismissed: Date?

    private var syncPromoAIChatDismissed: Date? {
        get { storage.aiChatDismissed }
        set { storage.aiChatDismissed = newValue }
    }

    private var syncPromoAIChatImpressions: Int {
        get { storage.aiChatImpressions ?? 0 }
        set { storage.aiChatImpressions = newValue }
    }

    init(syncService: DDGSyncing,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         storage: (any KeyedStoring<SyncPromoStorageKeys>) = UserDefaults.app.keyedStoring(),
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         installDateProvider: @escaping () -> Date? = { StatisticsUserDefaults().installDate },
         currentDateProvider: @escaping () -> Date = Date.init) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.privacyConfigurationManager = privacyConfigurationManager
        self.storage = storage
        self.pixelFiring = pixelFiring
        self.installDateProvider = installDateProvider
        self.currentDateProvider = currentDateProvider
    }

    func shouldPresentPromoFor(_ touchpoint: Touchpoint, count: Int) -> Bool {
        switch touchpoint {
        case .bookmarks:
            if featureFlagger.isFeatureOn(.syncPromotionBookmarks),
               syncService.authState == .inactive,
               featureFlagger.isFeatureOn(.sync),
               syncPromoBookmarksDismissed == nil,
               count > 0 {
                return true
            }
        case .passwords:
            if featureFlagger.isFeatureOn(.syncPromotionPasswords),
               syncService.authState == .inactive,
               featureFlagger.isFeatureOn(.sync),
               syncPromoPasswordsDismissed == nil,
               count > 0 {
                return true
            }
        case .dataImport:
            if featureFlagger.isFeatureOn(.dataImportSummarySyncPromotion),
               syncService.authState == .inactive,
               syncPromoDataImportDismissed == nil,
               count > 0 {
                return true
            }
        case .aiChat:
            if syncService.authState == .inactive,
               featureFlagger.isFeatureOn(.sync),
               featureFlagger.isFeatureOn(.aiChatSync),
               privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .duckAiChatHistory),
               syncPromoAIChatDismissed == nil,
               syncPromoAIChatImpressions < Self.aiChatImpressionCap,
               count > 0 {
                return true
            }
        case .bookmarksAnotherDevice:
            if canRefreshSyncedDevicesCount,
               featureFlagger.isFeatureOn(.sync),
               let daysSinceInstall,
               daysSinceInstall > Self.syncAnotherDeviceMinimumDaysSinceInstall,
               let syncedDevicesCount = storage.syncedDevicesCount,
               syncedDevicesCount < 2,
               isSetupPromoCooldownOver,
               count > 0 {
                return true
            }
        }

        return false
    }

    func refreshSyncedDevicesCount() async {
        guard canRefreshSyncedDevicesCount,
              let devices = try? await syncService.fetchDevices() else {
            return
        }
        storage.syncedDevicesCount = devices.count
    }

    private var canRefreshSyncedDevicesCount: Bool {
        featureFlagger.isFeatureOn(.syncPromotionSyncAnotherDevice)
        && syncService.authState != .inactive
        && storage.bookmarksAnotherDeviceDismissed == nil
    }

    private var isSetupPromoCooldownOver: Bool {
        guard let setupPromoConfirmed = storage.setupPromoConfirmed else {
            return true
        }
        return currentDateProvider().timeIntervalSince(setupPromoConfirmed) >= Self.syncAnotherDeviceSetupPromoCooldown
    }

    private var daysSinceInstall: Int? {
        guard let installDate = installDateProvider() else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: installDate, to: currentDateProvider()).day
    }

    func designFor(_ touchpoint: Touchpoint) -> Design {
        switch touchpoint {
        case .bookmarks, .passwords:
            guard featureFlagger.isFeatureOn(.syncPromotionRedesign),
                  let daysSinceInstall,
                  daysSinceInstall > Self.redesignMinimumDaysSinceInstall else {
                return .standard
            }
            return .redesigned
        case .dataImport, .aiChat, .bookmarksAnotherDevice:
            return .standard
        }
    }

    func markPromoHandledFor(_ touchpoint: Touchpoint) {
        switch touchpoint {
        case .bookmarks:
            syncPromoBookmarksDismissed = Date()
        case .passwords:
            syncPromoPasswordsDismissed = Date()
        case .dataImport:
            syncPromoDataImportDismissed = Date()
        case .aiChat:
            syncPromoAIChatDismissed = Date()
        case .bookmarksAnotherDevice:
            storage.bookmarksAnotherDeviceDismissed = Date()
        }
    }

    func recordImpressionFor(_ touchpoint: Touchpoint) {
        switch touchpoint {
        case .bookmarks, .passwords, .dataImport, .bookmarksAnotherDevice:
            break
        case .aiChat:
            syncPromoAIChatImpressions += 1
            if syncPromoAIChatImpressions >= Self.aiChatImpressionCap {
                dismissPromoFor(.aiChat, reason: .impressionCap)
            }
        }
    }

    func recordPromoConfirmedFor(_ touchpoint: Touchpoint) {
        switch touchpoint {
        case .bookmarks, .passwords:
            storage.setupPromoConfirmed = currentDateProvider()
        case .dataImport, .aiChat, .bookmarksAnotherDevice:
            break
        }
    }

    func dismissPromoFor(_ touchpoint: Touchpoint, reason: DismissalReason) {
        markPromoHandledFor(touchpoint)

        pixelFiring?.fire(Pixel.Event.syncPromoDismissed,
                          options: .parameters(["source": touchpoint.rawValue, "reason": reason.rawValue]))
    }

    func resetPromos() {
        syncPromoBookmarksDismissed = nil
        syncPromoPasswordsDismissed = nil
        syncPromoDataImportDismissed = nil
        syncPromoAIChatDismissed = nil
        syncPromoAIChatImpressions = 0
        storage.bookmarksAnotherDeviceDismissed = nil
        storage.setupPromoConfirmed = nil
    }
}
