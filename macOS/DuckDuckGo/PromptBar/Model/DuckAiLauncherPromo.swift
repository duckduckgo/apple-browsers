//
//  DuckAiLauncherPromo.swift
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

import Combine
import FeatureFlags_macOS
import Foundation
import NewTabPage
import Persistence
import PrivacyConfig

extension Notification.Name {
    static let duckAiLauncherPromoDismissalsDidReset = Notification.Name("duckAiLauncherPromoDismissalsDidReset")
}

/// How the user settled the promo. Kept so a later change can treat each group differently.
enum DuckAiLauncherPromoOutcome: String {
    case triedNow = "tried_now"
    /// The close button.
    case closed
    /// A prompt sent while the promo was on screen.
    case ignored
}

enum DuckAiLauncherPromoEligibility {

    static let minimumChatCount = 3

    static func isEligible(isFeatureOn: Bool,
                           isShortcutEnabled: Bool,
                           isMenuBarIconVisible: Bool,
                           chatCount: Int,
                           outcome: DuckAiLauncherPromoOutcome?) -> Bool {
        isFeatureOn && !(isShortcutEnabled && isMenuBarIconVisible) && chatCount >= minimumChatCount && outcome == nil
    }
}

/// Promotes the Duck.ai launcher (the Prompt Bar) on the New Tab Page. The page renders whatever
/// `presentation()` returns, so eligibility, copy and the CTA all live here. Main thread only.
final class DuckAiLauncherPromo {

    private static let outcomeKey = "duckai.launcher-promo.outcome"
    private static let outcomeDateKey = "duckai.launcher-promo.outcome-date"

    private let featureFlagger: FeatureFlagger
    private let preferences: PromptBarPreferences
    private let keyValueStore: ThrowingKeyValueStoring
    private let openSettings: @MainActor () -> Void
    private let dismissalSubject = PassthroughSubject<Void, Never>()
    @Published private var chatCount = 0
    private var chatsCancellable: AnyCancellable?

    init(featureFlagger: FeatureFlagger,
         preferences: PromptBarPreferences,
         chatCountPublisher: AnyPublisher<Int, Never>,
         keyValueStore: ThrowingKeyValueStoring,
         openSettings: @escaping @MainActor () -> Void) {
        self.featureFlagger = featureFlagger
        self.preferences = preferences
        self.keyValueStore = keyValueStore
        self.openSettings = openSettings

        chatsCancellable = chatCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.chatCount = $0 }
    }

    var isEligible: Bool {
        DuckAiLauncherPromoEligibility.isEligible(isFeatureOn: featureFlagger.isFeatureOn(.aiChatLauncherPromo),
                                                  isShortcutEnabled: preferences.isKeyboardShortcutEnabled,
                                                  isMenuBarIconVisible: preferences.isMenuBarIconVisible,
                                                  chatCount: chatCount,
                                                  outcome: outcome)
    }

    var outcome: DuckAiLauncherPromoOutcome? {
        ((try? keyValueStore.object(forKey: Self.outcomeKey)) as? String).flatMap(DuckAiLauncherPromoOutcome.init(rawValue:))
    }

    var outcomeDate: Date? {
        (try? keyValueStore.object(forKey: Self.outcomeDateKey)) as? Date
    }

    func presentation() -> NewTabPageDataModel.OmnibarLauncherPromo? {
        guard isEligible else { return nil }
        // Names the missing entry point; the menu bar icon when both are off.
        let secondaryText = preferences.isMenuBarIconVisible
            ? UserText.duckAiLauncherPromoAddKeyboardShortcut
            : UserText.duckAiLauncherPromoAddToMenuBar
        return .init(message: UserText.duckAiLauncherPromoMessage,
                     secondaryText: " • " + secondaryText,
                     ctaLabel: UserText.duckAiLauncherPromoTryNow,
                     dismissible: true)
    }

    /// `@Published` emits before the value lands, so reads hop to the next run loop.
    var changesPublisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            preferences.$isKeyboardShortcutEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isMenuBarIconVisible.map { _ in () }.eraseToAnyPublisher(),
            $chatCount.map { _ in () }.eraseToAnyPublisher(),
            featureFlagger.updatesPublisher,
            dismissalSubject.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: .duckAiLauncherPromoDismissalsDidReset).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .compactMap { [weak self] in self.map { $0.presentation() } }
        .removeDuplicates()
        .dropFirst()
        .map { _ in () }
        .eraseToAnyPublisher()
    }

    /// Turns on whichever entry point is off, then shows Settings so the user knows where to turn it off.
    @MainActor
    func tryNow() {
        preferences.isKeyboardShortcutEnabled = true
        preferences.isMenuBarIconVisible = true
        record(.triedNow)
        openSettings()
    }

    func dismiss() {
        record(.closed)
    }

    func ignore() {
        record(.ignored)
    }

    /// Any outcome ends the promo: it shows once.
    private func record(_ outcome: DuckAiLauncherPromoOutcome) {
        try? keyValueStore.set(outcome.rawValue, forKey: Self.outcomeKey)
        try? keyValueStore.set(Date(), forKey: Self.outcomeDateKey)
        dismissalSubject.send()
    }

    /// Debug only. Posts so open New Tab Pages re-read it: a new tab reuses the window's page, which never asks again.
    static func resetOutcome(in keyValueStore: ThrowingKeyValueStoring) {
        try? keyValueStore.removeObject(forKey: outcomeKey)
        try? keyValueStore.removeObject(forKey: outcomeDateKey)
        NotificationCenter.default.post(name: .duckAiLauncherPromoDismissalsDidReset, object: nil)
    }
}
