//
//  AIChatSyncPromoViewModel.swift
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

import Core

/// Reports whether a coordinated launch modal (subscription reinstaller promo, default-browser
/// prompt, What's New, etc.) was presented earlier in the current session. The Duck.ai sync promo
/// uses this to yield so the two don't appear back-to-back in the same session. See Asana 1216108902675922.
@MainActor
protocol RecentModalPromptStatusProviding {
    var wasModalPromptRecentlyPresented: Bool { get }
}

@MainActor
final class AIChatSyncPromoViewModel {

    enum Action: Equatable {
        case requestSyncSetup
    }

    private let syncPromoManager: SyncPromoManaging
    private let recentModalPromptStatusProvider: RecentModalPromptStatusProviding?
    private let pixelFiring: any PixelFiring.Type
    private var impressionRecorded = false

    init(syncPromoManager: SyncPromoManaging,
         recentModalPromptStatusProvider: RecentModalPromptStatusProviding? = nil,
         pixelFiring: any PixelFiring.Type = Pixel.self) {
        self.syncPromoManager = syncPromoManager
        self.recentModalPromptStatusProvider = recentModalPromptStatusProvider
        self.pixelFiring = pixelFiring
    }

    func shouldShowPromo(isQueryActive: Bool, chatCount: Int) -> Bool {
        guard !isQueryActive else { return false }
        // Yield to a launch modal shown within the coordination cooldown window so we don't stack
        // two promos back-to-back in the same session (e.g. the subscription reinstaller sheet).
        guard recentModalPromptStatusProvider?.wasModalPromptRecentlyPresented != true else { return false }
        return syncPromoManager.shouldPresentPromoFor(.aiChat, count: chatCount)
    }

    @discardableResult
    func recordImpressionIfNeeded(isVisibleContent: Bool, isPromoVisible: Bool) -> Bool {
        guard isVisibleContent,
              isPromoVisible,
              !impressionRecorded else { return false }

        impressionRecorded = true
        pixelFiring.fire(.syncPromoDisplayed, withAdditionalParameters: pixelParameters)
        syncPromoManager.recordImpressionFor(.aiChat)
        return true
    }

    func handleCTATap() -> Action {
        pixelFiring.fire(.syncPromoConfirmed, withAdditionalParameters: pixelParameters)
        syncPromoManager.markPromoHandledFor(.aiChat)
        return .requestSyncSetup
    }

    func handleCloseTap() {
        syncPromoManager.dismissPromoFor(.aiChat, reason: .userTapped)
    }

    private var pixelParameters: [String: String] {
        ["source": SyncPromoManager.Touchpoint.aiChat.rawValue]
    }
}
