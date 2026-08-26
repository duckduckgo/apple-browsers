//
//  DuckAiUsageLimitsStore.swift
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
import Combine
import Core
import FeatureFlags_iOS
import Foundation
import os.log
import PixelKit
import PrivacyConfig

/// Owns the app-side flag gating so the shared decision logic stays flag-agnostic, and builds the
/// view model that drives the footer. Mirrors macOS's file of the same name.
struct DuckAiUsageLimitsStore {

#if DEBUG || ALPHA
    @MainActor static var debugOverride: DuckAiUsageSnapshot?
#endif

    private let storageHandler: DuckAiNativeStorageHandling?
    private let storageProvider: DuckAiUsageSnapshotProviding?
    private let featureFlagger: FeatureFlagger
    private let dismissalStore: DuckAiUsageWarningDismissalStoring

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         dismissalStore: DuckAiUsageWarningDismissalStoring = DuckAiUsageWarningDismissalStore(),
         dateProvider: @escaping () -> Date = Date.init) {
        self.storageHandler = storageHandler
        self.storageProvider = storageHandler.map {
            DuckAiUsageSnapshotProvider(storage: $0,
                                        pixelFiring: DuckAiNativeStoragePixelAdapter(),
                                        dateProvider: dateProvider)
        }
        self.featureFlagger = featureFlagger
        self.dismissalStore = dismissalStore
    }

    /// `nil` means inactive (flag off, or no storage bridge), which differs from having nothing to show.
    func makeWarningViewModel(surfaceProvider: @escaping () -> UnifiedToggleInputPixelSurface,
                              modelSuggester: DuckAiModelSuggesting,
                              isTrialEligible: @escaping () -> Bool,
                              isFireMode: @escaping () -> Bool) -> DuckAiUsageWarningViewModel? {
        guard featureFlagger.isFeatureOn(.utiDuckAIWarnings) else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] inactive: utiDuckAIWarnings flag is off")
            return nil
        }
        guard let limitsProvider = makeLimitsProvider() else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] inactive: no native-storage bridge")
            return nil
        }
        return DuckAiUsageWarningViewModel(
            snapshotProvider: limitsProvider,
            dismissalStore: dismissalStore,
            modelSuggester: modelSuggester,
            pixelFiring: DuckAiUsageWarningPixelAdapter(surfaceProvider: surfaceProvider),
            isTrialEligible: isTrialEligible,
            isFireMode: isFireMode
        )
    }

    /// Emits when the `usageLimits` entry changes, whoever wrote it — the web app publishing a new
    /// snapshot, or a debug seed. Lets an open input update instead of waiting for the next
    /// activation, and is what releases a message the user has already acted on.
    var snapshotUpdates: AnyPublisher<Void, Never>? {
        guard featureFlagger.isFeatureOn(.utiDuckAIWarnings),
              let observing = storageHandler as? DuckAiNativeEntriesObserving else { return nil }

        return observing.reservedEntryUpdatesPublisher
            .filter { $0 == .usageLimits }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Records the hand-off that lets the user keep chatting on another window's allowance. Web owns
    /// both the key and the value, so this writes what it sent and nothing else: there is no API for
    /// this, and the web app turns the entry into its bypass request header on its next hydration.
    ///
    /// Same gate as the view model, so no flag and no bridge means no write. On a fire tab the handler
    /// is the isolated one, and the view model refuses to warn there anyway.
    @discardableResult
    func write(_ entries: [DuckAiNativeStorageEntry]) -> Bool {
        guard featureFlagger.isFeatureOn(.utiDuckAIWarnings), let storageHandler else { return false }

        var didWriteAll = true
        for entry in entries {
            do {
                try storageHandler.putEntry(key: entry.key, value: entry.value)
                Logger.duckAIUsageWarnings.debug("[UsageWarnings] wrote entry '\(entry.key, privacy: .public)'")
            } catch {
                didWriteAll = false
                Logger.duckAIUsageWarnings.error("""
                    [UsageWarnings] failed to write entry '\(entry.key, privacy: .public)': \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
        return didWriteAll
    }

    private func makeLimitsProvider() -> DuckAiUsageSnapshotProviding? {
#if DEBUG || ALPHA
        // Wrapped rather than replaced, so "no storage bridge" still reads as inactive here exactly
        // as it does in Release.
        return storageProvider.map { DebugOverridableUsageLimitsProvider(wrapped: $0) }
#else
        return storageProvider
#endif
    }
}

#if DEBUG || ALPHA
/// Lets the AI Chat debug menu drive the real decision path from a hand-seeded snapshot.
private struct DebugOverridableUsageLimitsProvider: DuckAiUsageSnapshotProviding {

    let wrapped: DuckAiUsageSnapshotProviding

    func currentSnapshot() -> DuckAiUsageSnapshot {
        if let override = MainActor.assumeIsolated({ DuckAiUsageLimitsStore.debugOverride }) {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] using debug override snapshot")
            return override
        }
        return wrapped.currentSnapshot()
    }
}
#endif

/// The `surface` param is resolved per fire: one coordinator serves the omnibar, the Duck.ai tab and
/// the contextual sheet, and which of those is on screen changes while it lives.
struct DuckAiUsageWarningPixelAdapter: DuckAiUsageWarningPixelFiring {

    private let surfaceProvider: () -> UnifiedToggleInputPixelSurface

    init(surfaceProvider: @escaping () -> UnifiedToggleInputPixelSurface) {
        self.surfaceProvider = surfaceProvider
    }

    func fire(_ event: DuckAiUsageWarningEvent) {
        let surface = surfaceProvider().rawValue
        switch event {
        case .noticeShown(let noticeID, let window):
            PixelKit.fire(DuckAiUsageWarningPixel.messageShown(notice: noticeID.rawValue,
                                                               window: window.rawValue,
                                                               surface: surface),
                          frequency: .dailyAndCount)
        case .ctaTapped(let ctaID, let noticeID):
            PixelKit.fire(DuckAiUsageWarningPixel.messageCtaClicked(notice: noticeID.rawValue,
                                                                    cta: ctaID.rawValue,
                                                                    surface: surface),
                          frequency: .dailyAndCount)
        case .noticeDismissed(let noticeID):
            PixelKit.fire(DuckAiUsageWarningPixel.messageDismissed(notice: noticeID.rawValue, surface: surface),
                          frequency: .dailyAndCount)
        }
    }
}

/// `notice` and `cta` are the web app's own ids, so these line up with the web banner's numbers for
/// the same message. No percentage: the notice id and window already say which message this was.
enum DuckAiUsageWarningPixel: PixelKit.Event {

    /// One per notice per reset period per surface, not one per input activation.
    case messageShown(notice: String, window: String, surface: String)
    case messageCtaClicked(notice: String, cta: String, surface: String)
    case messageDismissed(notice: String, surface: String)

    var name: String {
        switch self {
        case .messageShown: "m_aichat_usage_message_shown"
        case .messageCtaClicked: "m_aichat_usage_message_cta_clicked"
        case .messageDismissed: "m_aichat_usage_message_dismissed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .messageShown(let notice, let window, let surface):
            ["notice": notice, "window": window, "surface": surface]
        case .messageCtaClicked(let notice, let cta, let surface):
            ["notice": notice, "cta": cta, "surface": surface]
        case .messageDismissed(let notice, let surface):
            ["notice": notice, "surface": surface]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }

    var namePrefix: PixelKitNamePrefix { .none }
}
