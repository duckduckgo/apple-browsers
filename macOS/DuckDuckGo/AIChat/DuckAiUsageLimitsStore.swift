//
//  DuckAiUsageLimitsStore.swift
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
import AppKit
import Combine
import FeatureFlags_macOS
import os.log
import PixelKit
import PrivacyConfig

/// Owns the app-side flag gating so the shared logic stays flag-agnostic and call sites don't repeat it.
/// Mirrors `CustomizeResponsesStore`: cheap to build, one per surface with a burner-aware handler.
final class DuckAiUsageLimitsStore {

    private let storageHandler: DuckAiNativeStorageHandling?
    private let featureFlagger: FeatureFlagger

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.storageHandler = storageHandler
        self.featureFlagger = featureFlagger
    }

    /// `nil` means inactive (flag off, or no storage bridge), which differs from having nothing to show.
    func makeWarningViewModel(modelSuggester: DuckAiModelSuggesting,
                              isTrialEligible: @escaping () -> Bool,
                              isFireMode: @escaping () -> Bool) -> DuckAiUsageWarningViewModel? {
        DuckAiUsageWarningViewModelFactory.make(
            isFeatureEnabled: featureFlagger.isFeatureOn(.aiChatUsageWarnings),
            storage: storageHandler,
            dismissalStore: DuckAiUsageWarningDismissalStore(),
            modelSuggester: modelSuggester,
            isTrialEligible: isTrialEligible,
            isFireMode: isFireMode,
            storagePixelFiring: DuckAiNativeStoragePixelAdapter()
        )
    }

    /// `nil` when the feature is inactive, matching `makeWarningViewModel` — the notice shares the
    /// card, so it must not outlive the flag that gates it.
    func makeHighUsageNoticeSource(
        modelProvider: @escaping () -> (id: String?, shortName: String?)
    ) -> AIChatHighUsageNoticeSource? {
        guard featureFlagger.isFeatureOn(.aiChatUsageWarnings) else { return nil }

        return AIChatHighUsageNoticeSource(modelProvider: modelProvider)
    }

    /// Lets an open surface update instead of waiting for the next activation, and is what releases
    /// a message the user has already acted on.
    var snapshotUpdates: AnyPublisher<Void, Never>? {
        guard featureFlagger.isFeatureOn(.aiChatUsageWarnings),
              let observing = storageHandler as? DuckAiNativeEntriesObserving else { return nil }

        return observing.reservedEntryUpdatesPublisher
            .filter { $0 == .usageLimits }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// There is no API for the hand-off: web reads this entry on its next hydration and turns it into
    /// the bypass header itself. Burner surfaces carry an isolated handler, so a write can't leak.
    @discardableResult
    func write(_ entries: [DuckAiNativeStorageEntry]) -> Bool {
        guard featureFlagger.isFeatureOn(.aiChatUsageWarnings), let storageHandler else { return false }

        var didWriteAll = true
        for entry in entries {
            do {
                try storageHandler.putEntry(key: entry.key, value: entry.value)
                Logger.aiChat.debug("Duck.ai usage warning: wrote entry '\(entry.key, privacy: .public)'")
            } catch {
                didWriteAll = false
                Logger.aiChat.error("""
                    Duck.ai usage warning: failed to write entry '\(entry.key, privacy: .public)': \
                    \(error.localizedDescription, privacy: .public)
                    """)
                PixelKit.fire(DebugEvent(GeneralPixel.duckAiNativeStorageSettingsPutError, error: error),
                              frequency: .dailyAndStandard)
            }
        }
        return didWriteAll
    }
}

/// The "this model spends your allowance quickly" notice. Keyed off the selected model rather than
/// the allowance, so it sits beside the usage warnings instead of being one. AppKit twin of iOS's
/// `UTIFooterHighUsageNoticeSource`.
final class AIChatHighUsageNoticeSource {

    private let resolver: DuckAIHighUsageModelNoticeResolver
    private let dismissalStore: DuckAiHighUsageNoticeDismissalStoring
    /// Re-read per refresh, so switching models mid-session is picked up.
    private let modelProvider: () -> (id: String?, shortName: String?)

    private(set) var notice: DuckAiHighUsageModelNotice?

    init(dismissalStore: DuckAiHighUsageNoticeDismissalStoring = DuckAiHighUsageNoticeDismissalStore(),
         modelProvider: @escaping () -> (id: String?, shortName: String?)) {
        self.dismissalStore = dismissalStore
        self.resolver = DuckAIHighUsageModelNoticeResolver(dismissalStore: dismissalStore)
        self.modelProvider = modelProvider
    }

    func refresh() {
        let model = modelProvider()
        switch resolver.resolve(modelId: model.id, modelShortName: model.shortName) {
        case .notice(let notice):
            self.notice = notice
            Logger.aiChat.debug("Duck.ai high-usage notice: model=\(notice.modelId, privacy: .public)")
        case .none(let reason):
            notice = nil
            Logger.aiChat.debug("Duck.ai high-usage notice: none — reason=\(reason.rawValue, privacy: .public)")
        }
    }

    /// One-time per model: there is no reset window for it to expire against.
    func dismissCurrent() {
        guard let notice else { return }

        dismissalStore.setDismissed(modelId: notice.modelId)
        self.notice = nil
        Logger.aiChat.debug("Duck.ai high-usage notice dismissed: model=\(notice.modelId, privacy: .public)")
    }

    /// Teardown: drops the notice without recording a dismissal.
    func clear() {
        notice = nil
    }
}
