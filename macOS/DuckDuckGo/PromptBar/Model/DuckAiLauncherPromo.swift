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

import AIChat
import AppKit
import Combine
import FeatureFlags_macOS
import Foundation
import NewTabPage
import Persistence
import PixelKit
import PrivacyConfig

extension Notification.Name {
    static let duckAiLauncherPromoOutcomeDidChange = Notification.Name("duckAiLauncherPromoOutcomeDidChange")
}

enum DuckAiLauncherPromoOutcome: String {
    case triedNow = "tried_now"
    case closed
    case ignored
}

enum DuckAiLauncherPromoSurface: String {
    case newTab = "new_tab"
    case addressBar = "address_bar"
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

final class DuckAiLauncherPromo {

    private static let outcomeKey = "duckai.launcher-promo.outcome"

    private let featureFlagger: FeatureFlagger
    private let preferences: PromptBarPreferences
    private let keyValueStore: ThrowingKeyValueStoring
    private let surface: DuckAiLauncherPromoSurface
    private let firePixel: (PromptBarPixel) -> Void
    @Published private var chatCount = 0
    private var chatsCancellable: AnyCancellable?

    init(featureFlagger: FeatureFlagger,
         preferences: PromptBarPreferences,
         chatCountPublisher: AnyPublisher<Int, Never>,
         keyValueStore: ThrowingKeyValueStoring,
         surface: DuckAiLauncherPromoSurface,
         firePixel: @escaping (PromptBarPixel) -> Void = { PixelKit.fire($0, frequency: .dailyAndCount, includeAppVersionParameter: true) }) {
        self.featureFlagger = featureFlagger
        self.preferences = preferences
        self.keyValueStore = keyValueStore
        self.surface = surface
        self.firePixel = firePixel

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
        Self.storedOutcome(in: keyValueStore)
    }

    static func storedOutcome(in keyValueStore: ThrowingKeyValueStoring) -> DuckAiLauncherPromoOutcome? {
        ((try? keyValueStore.object(forKey: outcomeKey)) as? String).flatMap(DuckAiLauncherPromoOutcome.init(rawValue:))
    }

    func shown() {
        firePixel(.promoShown(surface: surface))
    }

    func presentation() -> NewTabPageDataModel.OmnibarLauncherPromo? {
        guard isEligible else { return nil }
        let secondaryText = preferences.isMenuBarIconVisible
            ? UserText.duckAiLauncherPromoAddKeyboardShortcut
            : UserText.duckAiLauncherPromoAddToMenuBar
        return .init(message: UserText.duckAiLauncherPromoMessage,
                     secondaryText: " • " + secondaryText,
                     ctaLabel: UserText.duckAiLauncherPromoTryNow,
                     dismissible: true)
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            preferences.$isKeyboardShortcutEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isMenuBarIconVisible.map { _ in () }.eraseToAnyPublisher(),
            $chatCount.map { _ in () }.eraseToAnyPublisher(),
            featureFlagger.updatesPublisher,
            NotificationCenter.default.publisher(for: .duckAiLauncherPromoOutcomeDidChange).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .compactMap { [weak self] in self.map { $0.presentation() } }
        .removeDuplicates()
        .dropFirst()
        .map { _ in () }
        .eraseToAnyPublisher()
    }

    func tryNow() {
        preferences.isKeyboardShortcutEnabled = true
        preferences.isMenuBarIconVisible = true
        preferences.pendingMenuBarTip = true
        record(.triedNow)
    }

    func dismiss() {
        record(.closed)
    }

    func ignore() {
        record(.ignored)
    }

    private func record(_ outcome: DuckAiLauncherPromoOutcome) {
        try? keyValueStore.set(outcome.rawValue, forKey: Self.outcomeKey)
        switch outcome {
        case .triedNow: firePixel(.promoTryNow(surface: surface))
        case .closed: firePixel(.promoClosed(surface: surface))
        case .ignored: firePixel(.promoIgnored(surface: surface))
        }
        NotificationCenter.default.post(name: .duckAiLauncherPromoOutcomeDidChange, object: nil)
    }

    static func resetOutcome(in keyValueStore: ThrowingKeyValueStoring) {
        try? keyValueStore.removeObject(forKey: outcomeKey)
        NotificationCenter.default.post(name: .duckAiLauncherPromoOutcomeDidChange, object: nil)
    }
}

extension DuckAiLauncherPromo {

    @MainActor
    convenience init(featureFlagger: FeatureFlagger, keyValueStore: ThrowingKeyValueStoring, surface: DuckAiLauncherPromoSurface) {
        let chatCountPublisher = (NSApp.delegateTyped.duckAiNativeStorageHandler as? DuckAiNativeChatsObserving)?.chatsPublisher()
            .map(\.count)
            .replaceError(with: 0)
            .eraseToAnyPublisher() ?? Just(0).eraseToAnyPublisher()
        self.init(featureFlagger: featureFlagger,
                  preferences: NSApp.delegateTyped.promptBarPreferences,
                  chatCountPublisher: chatCountPublisher,
                  keyValueStore: keyValueStore,
                  surface: surface)
    }
}
