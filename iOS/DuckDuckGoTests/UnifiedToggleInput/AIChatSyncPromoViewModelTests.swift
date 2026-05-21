//
//  AIChatSyncPromoViewModelTests.swift
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
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("AI Chat Sync Promo View Model Tests", .serialized)
final class AIChatSyncPromoViewModelTests {

    init() {
        PixelFiringMock.tearDown()
    }

    deinit {
        PixelFiringMock.tearDown()
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func shouldShowPromo_whenQueryActive_returnsFalseWithoutAskingManager() {
        let manager = MockSyncPromoManager()
        manager.shouldPresentForTouchpoint[.aiChat] = true
        let viewModel = AIChatSyncPromoViewModel(syncPromoManager: manager)

        #expect(!viewModel.shouldShowPromo(isQueryActive: true, chatCount: 2))
        #expect(manager.shouldPresentRequests.isEmpty)
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func shouldShowPromo_whenQueryInactive_usesManagerWithChatCount() {
        let manager = MockSyncPromoManager()
        manager.shouldPresentForTouchpoint[.aiChat] = true
        let viewModel = AIChatSyncPromoViewModel(syncPromoManager: manager)

        #expect(viewModel.shouldShowPromo(isQueryActive: false, chatCount: 2))
        #expect(manager.shouldPresentRequests.count == 1)
        #expect(manager.shouldPresentRequests.first?.touchpoint == .aiChat)
        #expect(manager.shouldPresentRequests.first?.count == 2)
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func recordImpressionIfNeeded_whenVisibleAndPromoVisible_firesDisplayedPixelAndRecordsImpression() {
        let manager = MockSyncPromoManager()
        let viewModel = AIChatSyncPromoViewModel(syncPromoManager: manager, pixelFiring: PixelFiringMock.self)

        #expect(viewModel.recordImpressionIfNeeded(isVisibleContent: true, isPromoVisible: true))

        #expect(manager.recordedImpressions == [.aiChat])
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.syncPromoDisplayed.name)
        #expect(PixelFiringMock.lastParams == ["source": SyncPromoManager.Touchpoint.aiChat.rawValue])
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func recordImpressionIfNeeded_recordsOnlyOnce() {
        let manager = MockSyncPromoManager()
        let viewModel = AIChatSyncPromoViewModel(syncPromoManager: manager, pixelFiring: PixelFiringMock.self)

        #expect(viewModel.recordImpressionIfNeeded(isVisibleContent: true, isPromoVisible: true))
        #expect(!viewModel.recordImpressionIfNeeded(isVisibleContent: true, isPromoVisible: true))

        #expect(manager.recordedImpressions == [.aiChat])
        #expect(PixelFiringMock.allPixelsFired.compactMap(\.pixelName) == [Pixel.Event.syncPromoDisplayed.name])
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func recordImpressionIfNeeded_whenNotVisibleOrPromoHidden_doesNothing() {
        let manager = MockSyncPromoManager()
        let viewModel = AIChatSyncPromoViewModel(syncPromoManager: manager, pixelFiring: PixelFiringMock.self)

        #expect(!viewModel.recordImpressionIfNeeded(isVisibleContent: false, isPromoVisible: true))
        #expect(!viewModel.recordImpressionIfNeeded(isVisibleContent: true, isPromoVisible: false))

        #expect(manager.recordedImpressions.isEmpty)
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func handleCTATap_firesConfirmedPixelMarksPromoHandledAndRequestsSyncSetup() {
        let manager = MockSyncPromoManager()
        let viewModel = AIChatSyncPromoViewModel(syncPromoManager: manager, pixelFiring: PixelFiringMock.self)

        let action = viewModel.handleCTATap()

        #expect(action == .requestSyncSetup)
        #expect(manager.handledTouchpoints == [.aiChat])
        #expect(PixelFiringMock.allPixelsFired.count == 1)
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.syncPromoConfirmed.name)
        #expect(PixelFiringMock.lastParams == ["source": SyncPromoManager.Touchpoint.aiChat.rawValue])
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func handleCloseTap_dismissesPromoAsUserTapped() {
        let manager = MockSyncPromoManager()
        let viewModel = AIChatSyncPromoViewModel(syncPromoManager: manager)

        viewModel.handleCloseTap()

        #expect(manager.dismissedTouchpoints.count == 1)
        #expect(manager.dismissedTouchpoints.first?.0 == .aiChat)
        #expect(manager.dismissedTouchpoints.first?.1 == .userTapped)
    }
}

@MainActor
private final class MockSyncPromoManager: SyncPromoManaging {
    var shouldPresentForTouchpoint: [SyncPromoManager.Touchpoint: Bool] = [:]
    var shouldPresentRequests: [(touchpoint: SyncPromoManager.Touchpoint, count: Int)] = []
    var handledTouchpoints: [SyncPromoManager.Touchpoint] = []
    var recordedImpressions: [SyncPromoManager.Touchpoint] = []
    var dismissedTouchpoints: [(SyncPromoManager.Touchpoint, SyncPromoManager.DismissalReason)] = []

    func shouldPresentPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, count: Int) -> Bool {
        shouldPresentRequests.append((touchpoint, count))
        return shouldPresentForTouchpoint[touchpoint] ?? false
    }

    func markPromoHandledFor(_ touchpoint: SyncPromoManager.Touchpoint) {
        handledTouchpoints.append(touchpoint)
    }

    func recordImpressionFor(_ touchpoint: SyncPromoManager.Touchpoint) {
        recordedImpressions.append(touchpoint)
    }

    func dismissPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, reason: SyncPromoManager.DismissalReason) {
        dismissedTouchpoints.append((touchpoint, reason))
    }

    func resetPromos() {}
}
