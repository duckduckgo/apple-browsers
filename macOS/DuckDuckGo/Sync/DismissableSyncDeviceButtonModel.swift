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
import FeatureFlags
import BrowserServicesKit
import PixelKit

@MainActor
public final class DismissableSyncDeviceButtonModel: ObservableObject {
    enum DismissableSyncDevicePromoSource: CaseIterable {
        case bookmarksBar
        case bookmarkAdded

        var wasDismissedKey: String {
            switch self {
            case .bookmarksBar:
                return "com.duckduckgo.bookmarksBarSyncPromoDismissed"
            case .bookmarkAdded:
                return "com.duckduckgo.bookmarkAddedSyncPromoDismissed"
            }
        }

        var promoWasPresentedCountKey: String? {
            switch self {
            case .bookmarksBar:
                return nil
            case .bookmarkAdded:
                return "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount"
            }
        }

        var promoFirstPresentedDateKey: String? {
            switch self {
            case .bookmarksBar:
                return "com.duckduckgo.bookmarkFirstPresentedCount"
            case .bookmarkAdded:
                return nil
            }
        }

        var promoMaxPresentationCount: Int {
            switch self {
            case .bookmarksBar:
                return .max
            case .bookmarkAdded:
                return 5
            }
        }

        var promoMaxPresentationDays: Int {
            switch self {
            case .bookmarksBar:
                return 7
            case .bookmarkAdded:
                return .max
            }
        }

        var pixelSource: SyncDeviceButtonTouchpoint {
            switch self {
            case .bookmarksBar:
                return SyncDeviceButtonTouchpoint.bookmarksBar
            case .bookmarkAdded:
                return SyncDeviceButtonTouchpoint.bookmarkAdded
            }
        }
    }

    @Published var shouldShowSyncButton: Bool = false

    private var authState: SyncAuthState = .initializing {
        didSet {
            guard
                case .inactive = authState,
                !wasDimissed,
                !wasPresentationCountLimitReached,
                !hasPromoDateExpired else {
                shouldShowSyncButton = false
                return
            }
            shouldShowSyncButton = true
        }
    }

    private let source: DismissableSyncDevicePromoSource
    private let keyValueStore: KeyValueStoring
    private let syncLauncher: SyncDeviceFlowLaunching?
    private let featureFlagger: FeatureFlagger

    private var cancellables: Set<AnyCancellable> = []
    private var hasFiredImpressionPixel = false

    private var wasDimissed: Bool {
        guard let wasDismissed = keyValueStore.object(forKey: source.wasDismissedKey) as? Bool else {
            return false
        }
        return wasDismissed
    }

    private var wasPresentationCountLimitReached: Bool {
        guard let key = source.promoWasPresentedCountKey else {
            return false
        }
        let count = keyValueStore.object(forKey: key) as? Int ?? 0
        guard count < source.promoMaxPresentationCount else {
            return true
        }
        return false
    }

    private var hasPromoDateExpired: Bool {
        guard let key = source.promoFirstPresentedDateKey else {
            return false
        }
        guard let firstSeenDate = keyValueStore.object(forKey: key) as? Date else {
            return false
        }

        return !firstSeenDate.isLessThan(daysAgo: source.promoMaxPresentationDays)
    }

    init(
        source: DismissableSyncDevicePromoSource,
        keyValueStore: KeyValueStoring,
        authStatePublisher: AnyPublisher<SyncAuthState, Never>,
        initialAuthState: SyncAuthState,
        syncLauncher: SyncDeviceFlowLaunching?,
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger
    ) {
        self.source = source
        self.keyValueStore = keyValueStore
        self.syncLauncher = syncLauncher
        self.featureFlagger = featureFlagger
        self.authState = initialAuthState
        authStatePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.authState, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    func viewDidLoad() {
        guard
            featureFlagger.isNewSyncEntryPointsFeatureOn,
            syncLauncher != nil,
            case .inactive = authState,
            !wasDimissed,
            !incrementPresentationCountLimitReturningLimitReached(),
            !setFirstSeenDateReturningHasExpired()
        else {
            shouldShowSyncButton = false
            return
        }
        if !hasFiredImpressionPixel {
            PixelKit.fire(SyncPromoPixelKitEvent.syncPromoDisplayed.withoutMacPrefix, withAdditionalParameters: ["source": source.pixelSource.rawValue])
            hasFiredImpressionPixel = true
        }
        shouldShowSyncButton = true
    }

    func syncButtonAction() {
        syncLauncher?.startDeviceSyncFlow(source: source.pixelSource, completion: nil)
        PixelKit.fire(SyncPromoPixelKitEvent.syncPromoConfirmed.withoutMacPrefix, withAdditionalParameters: ["source": source.pixelSource.rawValue])
    }

    func dismissSyncButtonAction() {
        shouldShowSyncButton = false
        keyValueStore.set(true, forKey: source.wasDismissedKey)
        PixelKit.fire(SyncPromoPixelKitEvent.syncPromoDismissed.withoutMacPrefix, withAdditionalParameters: ["source": source.pixelSource.rawValue])
    }

    static func resetAllState(from keyValueStore: KeyValueStoring) {
        for source in DismissableSyncDevicePromoSource.allCases {
            keyValueStore.removeObject(forKey: source.wasDismissedKey)
            if let dateKey = source.promoFirstPresentedDateKey {
                keyValueStore.removeObject(forKey: dateKey)
            }
            if let countKey = source.promoWasPresentedCountKey {
                keyValueStore.removeObject(forKey: countKey)
            }
        }
    }

    private func incrementPresentationCountLimitReturningLimitReached() -> Bool {
        guard let key = source.promoWasPresentedCountKey else {
            return false
        }
        let count = keyValueStore.object(forKey: key) as? Int ?? 0
        guard count < source.promoMaxPresentationCount else {
            return true
        }
        keyValueStore.set(count + 1, forKey: key)
        return false
    }

    private func setFirstSeenDateReturningHasExpired() -> Bool {
        guard let key = source.promoFirstPresentedDateKey else {
            return false
        }
        guard let firstSeenDate = keyValueStore.object(forKey: key) as? Date else {
            keyValueStore.set(Date(), forKey: key)
            return false
        }

        return !firstSeenDate.isLessThan(daysAgo: source.promoMaxPresentationDays)
    }
}

extension DismissableSyncDeviceButtonModel {
    convenience init(source: DismissableSyncDevicePromoSource, keyValueStore: KeyValueStoring) {
        let authStatePublisher: AnyPublisher<SyncAuthState, Never>
        let syncLauncher: SyncDeviceFlowLaunching?
        let initialAuthState: SyncAuthState
        if let syncService = NSApp.delegateTyped.syncService, let syncPausedStateManager = NSApp.delegateTyped.syncDataProviders?.syncErrorHandler {
            authStatePublisher = syncService.authStatePublisher
            syncLauncher = DeviceSyncCoordinator(syncService: syncService, syncPausedStateManager: syncPausedStateManager)
            initialAuthState = syncService.authState
        } else {
            authStatePublisher = Just<SyncAuthState>(.initializing).eraseToAnyPublisher()
            syncLauncher = nil
            initialAuthState = .initializing
        }
        self.init(source: source, keyValueStore: keyValueStore, authStatePublisher: authStatePublisher, initialAuthState: initialAuthState, syncLauncher: syncLauncher)
    }
}

fileprivate extension FeatureFlagger {
    var isNewSyncEntryPointsFeatureOn: Bool {
        isFeatureOn(.newSyncEntryPoints) && isFeatureOn(.refactorOfSyncPreferences)
    }
}
