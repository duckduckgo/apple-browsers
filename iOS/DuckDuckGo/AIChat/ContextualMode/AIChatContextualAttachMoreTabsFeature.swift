//
//  AIChatContextualAttachMoreTabsFeature.swift
//  DuckDuckGo
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

import AIChat
import Common
import FeatureFlags_iOS
import Foundation
import Persistence
import PrivacyConfig

enum AIChatContextualAttachMoreTabsState: Equatable {
    case unavailable
    case available(maximumTabAttachmentCount: Int)
}

protocol AIChatContextualAttachMoreTabsFeatureProviding {
    var state: AIChatContextualAttachMoreTabsState { get }
    func isDrawerPromoAvailable(isCurrentDisplay: Bool) -> Bool
    func recordDrawerPromoDisplay()
    func dismissDrawerPromo()
    func recordTabAttachment()
}

struct AIChatContextualAttachMoreTabsFeature: AIChatContextualAttachMoreTabsFeatureProviding {
    private let featureFlagger: any FeatureFlagger
    private let aiChatSettings: AIChatSettingsProvider
    private let devicePlatform: DevicePlatformProviding.Type
    private let promotionStore: UTIMultiTabPromotionDisplayStoring

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self,
         promotionStore: UTIMultiTabPromotionDisplayStoring = UTIMultiTabPromotionDisplayStore()) {
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.devicePlatform = devicePlatform
        self.promotionStore = promotionStore
    }

    func isDrawerPromoAvailable(isCurrentDisplay: Bool) -> Bool {
        guard case .available = state else { return false }
        return promotionStore.isAvailable(startDate: aiChatSettings.aiChatAttachMoreTabsPromotionStartDate,
                                          isCurrentDisplay: isCurrentDisplay)
    }

    func recordDrawerPromoDisplay() {
        promotionStore.recordDisplay()
    }

    func dismissDrawerPromo() {
        promotionStore.dismiss()
    }

    func recordTabAttachment() {
        guard case .available = state else { return }
        promotionStore.recordTabAttachment()
    }

#if DEBUG || ALPHA
    static func resetDrawerPromoForDebugging(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        UTIMultiTabPromotionDisplayStore(keyValueStore: keyValueStore).resetForDebugging()
    }
#endif

    var state: AIChatContextualAttachMoreTabsState {
        guard devicePlatform.isIphone,
              featureFlagger.isFeatureOn(.aiChatContextualAttachMoreTabs) else {
            return .unavailable
        }

        return .available(maximumTabAttachmentCount: aiChatSettings.aiChatAttachMoreTabsLimit)
    }
}
