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
    func makeWarningViewModel(surface: DuckAiUsageWarningSurface,
                              modelSuggester: DuckAiModelSuggesting,
                              isTrialEligible: @escaping () -> Bool,
                              isFireMode: @escaping () -> Bool) -> DuckAiUsageWarningViewModel? {
        DuckAiUsageWarningViewModelFactory.make(
            isFeatureEnabled: featureFlagger.isFeatureOn(.aiChatUsageWarnings),
            storage: storageHandler,
            dismissalStore: DuckAiUsageWarningDismissalStore(),
            modelSuggester: modelSuggester,
            isTrialEligible: isTrialEligible,
            isFireMode: isFireMode,
            storagePixelFiring: DuckAiNativeStoragePixelAdapter(),
            usagePixelFiring: DuckAiUsageWarningPixelAdapter(surface: surface)
        )
    }

    /// Emits when the `usageLimits` entry changes, whoever wrote it — the web app publishing a new
    /// snapshot, or a debug seed. Lets an open surface update instead of waiting for the next
    /// activation, and is what releases a message the user has already acted on.
    var snapshotUpdates: AnyPublisher<Void, Never>? {
        guard featureFlagger.isFeatureOn(.aiChatUsageWarnings),
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
    /// Same gate as the view model, so no flag and no bridge means no write. On a burner surface the
    /// handler is the isolated or null one, so a write can't leak into the regular session — and the
    /// view model refuses to warn in fire mode anyway, which makes the CTA unreachable there.
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

/// The native input surface a usage-limit message appeared on. Not in the AIChat module: the module
/// has no view of which surfaces this app has.
enum DuckAiUsageWarningSurface: String {
    case addressBar = "address-bar"
    case promptBar = "prompt-bar"
    case newTabPageOmnibar = "ntp-omnibar"

    init(promptSurface: DuckAIPromptSurface) {
        switch promptSurface {
        case .addressBar: self = .addressBar
        case .promptBar: self = .promptBar
        }
    }
}

struct DuckAiUsageWarningPixelAdapter: DuckAiUsageWarningPixelFiring {

    private let surface: DuckAiUsageWarningSurface

    init(surface: DuckAiUsageWarningSurface) {
        self.surface = surface
    }

    func fire(_ event: DuckAiUsageWarningEvent) {
        switch event {
        case .noticeShown(let noticeID, let window):
            PixelKit.fire(AIChatPixel.aiChatUsageMessageShown(notice: noticeID.rawValue,
                                                              window: window.rawValue,
                                                              surface: surface.rawValue),
                          frequency: .dailyAndCount,
                          includeAppVersionParameter: true)
        case .ctaTapped(let ctaID, let noticeID):
            PixelKit.fire(AIChatPixel.aiChatUsageMessageCtaClicked(notice: noticeID.rawValue,
                                                                   cta: ctaID.rawValue,
                                                                   surface: surface.rawValue),
                          frequency: .dailyAndCount,
                          includeAppVersionParameter: true)
        case .noticeDismissed(let noticeID):
            PixelKit.fire(AIChatPixel.aiChatUsageMessageDismissed(notice: noticeID.rawValue,
                                                                  surface: surface.rawValue),
                          frequency: .dailyAndCount,
                          includeAppVersionParameter: true)
        }
    }
}
