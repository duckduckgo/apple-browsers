//
//  DismissableSyncDeviceButtonModel.swift
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

import Combine
import Persistence
import AppKit
import DDGSync
import PixelKit

@MainActor
public final class DismissableSyncDeviceButtonModel: ObservableObject {
    enum DismissableSyncDevicePromoSource: CaseIterable {
        case bookmarksBar
        case bookmarkAdded

        var pixelSource: SyncDeviceButtonTouchpoint {
            switch self {
            case .bookmarksBar:
                return SyncDeviceButtonTouchpoint.bookmarksBar
            case .bookmarkAdded:
                return SyncDeviceButtonTouchpoint.bookmarkAdded
            }
        }

        @MainActor
        var promo: SyncDeviceButtonPromoPresenting {
            switch self {
            case .bookmarksBar:
                return NSApp.delegateTyped.bookmarksBarSyncPromoDelegate
            case .bookmarkAdded:
                return NSApp.delegateTyped.bookmarkAddedSyncPromoDelegate
            }
        }
    }

    @Published var shouldShowSyncButton: Bool = false

    private let source: DismissableSyncDevicePromoSource
    private let syncLauncher: SyncDeviceFlowLaunching?
    private let pixelFiring: PixelFiring?
    private let notificationCenter: NotificationCenter
    private let promo: SyncDeviceButtonPromoPresenting

    private var cancellables: Set<AnyCancellable> = []
    private var hasFiredImpressionPixel = false

    init(
        source: DismissableSyncDevicePromoSource,
        syncLauncher: SyncDeviceFlowLaunching?,
        pixelFiring: PixelFiring? = PixelKit.shared,
        notificationCenter: NotificationCenter = .default,
        promo: SyncDeviceButtonPromoPresenting? = nil
    ) {
        self.source = source
        self.syncLauncher = syncLauncher
        self.pixelFiring = pixelFiring
        self.notificationCenter = notificationCenter
        self.promo = promo ?? source.promo

        self.promo.isPromoActivePublisher
            .assign(to: &$shouldShowSyncButton)
    }

    func panelDidOpen() {
        // The bookmarks bar fires its own display pixel when its button appears; panels fire it here, once the panel is open.
        $shouldShowSyncButton
            .first { $0 }
            .sink { [weak self] _ in
                self?.syncButtonDidAppear()
            }
            .store(in: &cancellables)
        notificationCenter.post(name: .bookmarkPanelShown, object: nil)
    }

    func syncButtonSurfaceClosed() {
        promo.syncButtonSurfaceClosed()
    }

    func syncButtonDidAppear() {
        guard !hasFiredImpressionPixel else { return }
        hasFiredImpressionPixel = true
        pixelFiring?.fire(SyncPromoPixelKitEvent.syncPromoDisplayed, options: .parameters(["source": source.pixelSource.rawValue]))
    }

    func syncButtonAction() {
        promo.syncSetupStarted()
        syncLauncher?.startDeviceSyncFlow(source: source.pixelSource, completion: nil)
        pixelFiring?.fire(SyncPromoPixelKitEvent.syncPromoConfirmed, options: .parameters(["source": source.pixelSource.rawValue]))
    }

    func dismissSyncButtonAction() {
        shouldShowSyncButton = false
        promo.syncButtonDismissed()
        pixelFiring?.fire(SyncPromoPixelKitEvent.syncPromoDismissed, options: .parameters(["source": source.pixelSource.rawValue]))
    }

    static func resetAllState(from keyValueStore: KeyValueStoring) {
        let legacyKeys: [UserDefaultsKeys] = [
            .bookmarksBarSyncPromoDismissed,
            .bookmarksBarSyncPromoFirstPresentedDate,
            .bookmarkAddedSyncPromoDismissed,
            .bookmarkAddedSyncPromoPresentedCount
        ]
        legacyKeys.forEach { keyValueStore.removeObject(forKey: $0.rawValue) }
    }
}

extension DismissableSyncDeviceButtonModel {
    convenience init(source: DismissableSyncDevicePromoSource) {
        let syncLauncher: SyncDeviceFlowLaunching?
        if let syncService = NSApp.delegateTyped.syncService, let syncPausedStateManager = NSApp.delegateTyped.syncDataProviders?.syncErrorHandler {
            syncLauncher = DeviceSyncCoordinator(syncService: syncService, syncPausedStateManager: syncPausedStateManager)
        } else {
            syncLauncher = nil
        }
        self.init(source: source, syncLauncher: syncLauncher)
    }
}
