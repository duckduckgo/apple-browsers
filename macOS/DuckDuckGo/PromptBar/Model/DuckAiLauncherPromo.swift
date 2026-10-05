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

typealias DuckAiLauncherPromoKind = NewTabPageDataModel.OmnibarLauncherPromoKind

extension Notification.Name {
    static let duckAiLauncherPromoDismissalsDidReset = Notification.Name("duckAiLauncherPromoDismissalsDidReset")
}

enum DuckAiLauncherPromoEligibility {

    static let minimumChatCount = 3

    /// The promo and the nudge are drawers, dismissed separately; the hint is a placeholder and never dismissed.
    static func kind(isFeatureOn: Bool,
                     isShortcutEnabled: Bool,
                     isMenuBarIconVisible: Bool,
                     chatCount: Int,
                     dismissedKinds: Set<DuckAiLauncherPromoKind>) -> DuckAiLauncherPromoKind? {
        guard isFeatureOn else { return nil }
        if isShortcutEnabled { return .shortcutHint }
        if isMenuBarIconVisible { return dismissedKinds.contains(.shortcutNudge) ? nil : .shortcutNudge }
        guard chatCount >= minimumChatCount, !dismissedKinds.contains(.promo) else { return nil }
        return .promo
    }
}

/// Promotes the Duck.ai launcher (the Prompt Bar) on the New Tab Page. The page renders whatever
/// `presentation()` returns, so eligibility, copy and the CTA all live here. Main thread only.
final class DuckAiLauncherPromo {

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

    var kind: DuckAiLauncherPromoKind? {
        DuckAiLauncherPromoEligibility.kind(isFeatureOn: featureFlagger.isFeatureOn(.aiChatLauncherPromo),
                                            isShortcutEnabled: preferences.isKeyboardShortcutEnabled,
                                            isMenuBarIconVisible: preferences.isMenuBarIconVisible,
                                            chatCount: chatCount,
                                            dismissedKinds: dismissedKinds)
    }

    func presentation() -> NewTabPageDataModel.OmnibarLauncherPromo? {
        guard let kind else { return nil }
        let shortcut = preferences.keyboardShortcut.promoDisplayString
        switch kind {
        case .promo:
            return .init(kind: kind, message: UserText.duckAiLauncherPromoMessage,
                         secondaryText: " • " + UserText.duckAiLauncherPromoSecondaryText,
                         ctaLabel: UserText.duckAiLauncherPromoTryNow, dismissible: true)
        case .shortcutHint:
            return .init(kind: kind, placeholder: String(format: UserText.duckAiLauncherShortcutHintPlaceholder, shortcut))
        case .shortcutNudge:
            return .init(kind: kind, message: UserText.duckAiLauncherShortcutNudgeMessage, shortcut: shortcut,
                         ctaLabel: UserText.duckAiLauncherShortcutNudgeTurnOn, dismissible: true)
        }
    }

    /// `@Published` emits before the value lands, so reads hop to the next run loop.
    var changesPublisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            preferences.$isKeyboardShortcutEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isMenuBarIconVisible.map { _ in () }.eraseToAnyPublisher(),
            preferences.$keyboardShortcut.map { _ in () }.eraseToAnyPublisher(),
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

    /// The drawer is shown once: a prompt sent while it was on screen counts as a dismissal.
    func ignore(kind: DuckAiLauncherPromoKind) {
        dismiss(kind: kind)
    }

    /// Both CTAs end with the shortcut on, then show Settings so the user knows where to turn it off.
    @MainActor
    func selectCta(kind: DuckAiLauncherPromoKind) {
        switch kind {
        case .promo:
            preferences.isKeyboardShortcutEnabled = true
            preferences.isMenuBarIconVisible = true
        case .shortcutNudge:
            preferences.isKeyboardShortcutEnabled = true
        case .shortcutHint:
            return
        }
        openSettings()
    }

    func dismiss(kind: DuckAiLauncherPromoKind) {
        try? keyValueStore.set(true, forKey: Self.dismissedKey(kind))
        dismissalSubject.send()
    }

    /// Debug only. Posts so open New Tab Pages re-read it: a new tab reuses the window's page, which never asks again.
    static func resetDismissals(in keyValueStore: ThrowingKeyValueStoring) {
        for kind in [DuckAiLauncherPromoKind.promo, .shortcutNudge] {
            try? keyValueStore.removeObject(forKey: dismissedKey(kind))
        }
        NotificationCenter.default.post(name: .duckAiLauncherPromoDismissalsDidReset, object: nil)
    }

    private var dismissedKinds: Set<DuckAiLauncherPromoKind> {
        Set([DuckAiLauncherPromoKind.promo, .shortcutNudge].filter {
            (try? keyValueStore.object(forKey: Self.dismissedKey($0))) as? Bool == true
        })
    }

    private static func dismissedKey(_ kind: DuckAiLauncherPromoKind) -> String {
        "duckai.launcher-promo.dismissed.\(kind.rawValue)"
    }
}

private extension PromptBarShortcut {
    /// "⌥ Space": the modifiers stay together, the key stands apart.
    var promoDisplayString: String {
        modifierSymbols.joined() + " " + keyDisplayString
    }
}
