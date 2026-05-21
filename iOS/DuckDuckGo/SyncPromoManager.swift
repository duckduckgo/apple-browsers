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
import Core
import Persistence
import DDGSync

protocol SyncPromoManaging {
    func shouldPresentPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, count: Int) -> Bool
    func markPromoHandledFor(_ touchpoint: SyncPromoManager.Touchpoint)
    func recordImpressionFor(_ touchpoint: SyncPromoManager.Touchpoint)
    func dismissPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, reason: SyncPromoManager.DismissalReason)
    func resetPromos()
}

enum SyncPromoStorageKeyNames: String, StorageKeyDescribing {
    case aiChatDismissed = "sync-promo-ai-chat-dismissed"
    case aiChatImpressions = "sync-promo-ai-chat-impressions"
}

struct SyncPromoStorageKeys: StoringKeys {
    let aiChatDismissed = StorageKey<Date>(SyncPromoStorageKeyNames.aiChatDismissed)
    let aiChatImpressions = StorageKey<Int>(SyncPromoStorageKeyNames.aiChatImpressions)
}

final class SyncPromoManager: SyncPromoManaging {

    enum Touchpoint: String {
        case bookmarks
        case passwords
        case dataImport = "data_import"
        case aiChat = "ai_chat"
    }

    enum DismissalReason: String {
        case userTapped = "user_tapped"
        case impressionCap = "impression_cap"
    }

    static let aiChatImpressionCap = 3

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let storage: any KeyedStoring<SyncPromoStorageKeys>
    private let pixelFiring: any PixelFiring.Type

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
         pixelFiring: any PixelFiring.Type = Pixel.self) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.privacyConfigurationManager = privacyConfigurationManager
        self.storage = storage
        self.pixelFiring = pixelFiring
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
               featureFlagger.isFeatureOn(.aiChatSyncPromo),
               privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .duckAiChatHistory),
               syncPromoAIChatDismissed == nil,
               syncPromoAIChatImpressions < Self.aiChatImpressionCap,
               count > 0 {
                return true
            }
        }

        return false
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
        }
    }

    func recordImpressionFor(_ touchpoint: Touchpoint) {
        switch touchpoint {
        case .bookmarks, .passwords, .dataImport:
            break
        case .aiChat:
            syncPromoAIChatImpressions += 1
            if syncPromoAIChatImpressions >= Self.aiChatImpressionCap {
                dismissPromoFor(.aiChat, reason: .impressionCap)
            }
        }
    }

    func dismissPromoFor(_ touchpoint: Touchpoint, reason: DismissalReason) {
        markPromoHandledFor(touchpoint)

        pixelFiring.fire(.syncPromoDismissed,
                         withAdditionalParameters: ["source": touchpoint.rawValue, "reason": reason.rawValue])
    }

    func resetPromos() {
        syncPromoBookmarksDismissed = nil
        syncPromoPasswordsDismissed = nil
        syncPromoDataImportDismissed = nil
        syncPromoAIChatDismissed = nil
        syncPromoAIChatImpressions = 0
    }
}
