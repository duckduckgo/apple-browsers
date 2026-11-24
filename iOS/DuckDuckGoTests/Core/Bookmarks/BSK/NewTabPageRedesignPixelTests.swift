//
//  NewTabPageRedesignPixelTests.swift
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

import Bookmarks
import Combine
import Core
import FeatureFlags_iOS
import Foundation
@_spi(Testing) import Persistence
import PrivacyConfig
import Testing
@testable import DuckDuckGo
@_spi(Testing) import PixelKit

@Suite("New Tab Page redesign pixels")
@MainActor
struct NewTabPageRedesignPixelTests {

    private let pixelFiring = PixelKitMock()

    @available(iOS 16, macOS 13, *)
    @Test("Favorites toggle reports the new value", .timeLimit(.minutes(1)), arguments: [false, true])
    func favoritesToggleReportsNewValue(enabled: Bool) {
        let persistor = MockNewTabPageCustomizationPersistor(isFavoritesSectionVisible: !enabled)
        let model = NewTabPageCustomizationModel(persistor: persistor, returnSettings: NewTabPageReturnSettings.makeForTests(), pixelFiring: pixelFiring)

        model.isFavoritesSectionVisible = enabled

        #expect(pixelFiring.actualFireCalls == [
            ExpectedFireCall(pixel: NewTabPageCustomizationPixel.favoritesToggled(enabled: enabled), frequency: .dailyAndCount)
        ])
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == ["enabled": String(enabled)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keyboard toggle reports the new value", .timeLimit(.minutes(1)))
    func keyboardToggleReportsNewValue() {
        var keyboardSettings = KeyboardSettings()
        let originalValue = keyboardSettings.onNewTab
        defer { keyboardSettings.onNewTab = originalValue }
        keyboardSettings.onNewTab = true
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 keyboardSettings: keyboardSettings,
                                                 returnSettings: NewTabPageReturnSettings.makeForTests(),
                                                 pixelFiring: pixelFiring)

        model.isKeyboardShownOnNewTab = false

        #expect(pixelFiring.actualFireCalls == [
            ExpectedFireCall(pixel: NewTabPageCustomizationPixel.keyboardToggled(enabled: false), frequency: .dailyAndCount)
        ])
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == ["enabled": "false"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Return to last tab toggle persists and reports the new value", .timeLimit(.minutes(1)), arguments: [false, true])
    func returnToLastTabToggleStoresAndReportsNewValue(enabled: Bool) throws {
        let keyValueStore = MockKeyValueFileStore()
        let returnSettings = NewTabPageReturnSettings.makeForTests(keyValueStore: keyValueStore)
        returnSettings.lastTabShortcutAdapter.setEnabled(!enabled)
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 returnSettings: returnSettings,
                                                 pixelFiring: pixelFiring)

        model.isReturnToLastTabEnabled = enabled

        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        #expect(try storage.lastTabShortcutEnabled == enabled)
        let expectedPixel: Pixel.Event = enabled ? .ntpAfterIdleLastTabShortcutSettingEnabled : .ntpAfterIdleLastTabShortcutSettingDisabled
        #expect(pixelFiring.actualFireCalls.map(\.pixel.name) == [expectedPixel.name])
    }

    @available(iOS 16, macOS 13, *)
    @Test("After inactivity option persists and reports the new value", .timeLimit(.minutes(1)))
    func afterInactivityOptionStoresAndReportsNewValue() throws {
        let keyValueStore = MockKeyValueFileStore()
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 returnSettings: .makeForTests(keyValueStore: keyValueStore),
                                                 pixelFiring: pixelFiring)

        model.afterInactivityOption = .lastUsedTab

        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        #expect(try storage.afterInactivityOption == AfterInactivityOption.lastUsedTab.rawValue)
        #expect(pixelFiring.actualFireCalls.map(\.pixel.name) == [Pixel.Event.ntpAfterIdleSettingChangedToLastUsedTab.name])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Idle interval persists and reports the new value", .timeLimit(.minutes(1)))
    func idleIntervalStoresAndReportsNewValue() throws {
        let keyValueStore = MockKeyValueFileStore()
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 returnSettings: .makeForTests(keyValueStore: keyValueStore),
                                                 pixelFiring: pixelFiring)

        model.afterInactivityIdleInterval = .fiveMinutes

        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        #expect(try storage.idleReturnIntervalSeconds == 300)
        #expect(pixelFiring.actualFireCalls.map(\.pixel.name) == [Pixel.Event.ntpAfterIdleSettingIdleIntervalChanged.name])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Choosing the shown idle interval again stores it", .timeLimit(.minutes(1)))
    func choosingShownIdleIntervalAgainStoresIt() throws {
        let keyValueStore = MockKeyValueFileStore()
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 returnSettings: .makeForTests(idleThresholdSeconds: 60, keyValueStore: keyValueStore),
                                                 pixelFiring: pixelFiring)

        model.afterInactivityIdleInterval = .oneMinute

        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        #expect(try storage.idleReturnIntervalSeconds == 60)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Choosing the shown after inactivity option again stores it", .timeLimit(.minutes(1)))
    func choosingShownAfterInactivityOptionAgainStoresIt() throws {
        let keyValueStore = MockKeyValueFileStore()
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 returnSettings: .makeForTests(keyValueStore: keyValueStore),
                                                 pixelFiring: pixelFiring)

        model.afterInactivityOption = .newTab

        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        #expect(try storage.afterInactivityOption == AfterInactivityOption.newTab.rawValue)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Idle return settings follow the idle return flag", .timeLimit(.minutes(1)), arguments: [false, true])
    func idleReturnSettingsFollowFlag(flagOn: Bool) {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: flagOn ? [.showNTPAfterIdleReturn] : [])
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 returnSettings: .makeForTests(featureFlagger: featureFlagger),
                                                 pixelFiring: pixelFiring)

        #expect(model.isIdleReturnSettingsVisible == flagOn)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unrecognised idle threshold shows the default interval", .timeLimit(.minutes(1)))
    func unrecognisedIdleThresholdShowsDefaultInterval() {
        let model = NewTabPageCustomizationModel(persistor: MockNewTabPageCustomizationPersistor(),
                                                 returnSettings: .makeForTests(idleThresholdSeconds: 123),
                                                 pixelFiring: pixelFiring)

        #expect(model.afterInactivityIdleInterval == .default)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Daily state reports whether favorites are visible", .timeLimit(.minutes(1)), arguments: [false, true])
    func dailyStateReportsFavoritesVisibility(favoritesVisible: Bool) {
        let persistor = MockNewTabPageCustomizationPersistor(isFavoritesSectionVisible: favoritesVisible)

        NewTabPageCustomizationStateReporter(persistor: persistor, pixelFiring: pixelFiring).fireDailyState()

        #expect(pixelFiring.actualFireCalls.map(\.pixel.name) == ["new-tab-page_redesign_state"])
        #expect(pixelFiring.actualFireCalls.first?.frequency == .daily)
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == ["favorites_visible": String(favoritesVisible)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Opening Add Favorite fires the opened pixel", .timeLimit(.minutes(1)))
    func openingAddFavoriteFiresOpenedPixel() {
        let model = AddFavoriteViewModel(bookmarks: MockAddFavoriteBookmarks(), pixelFiring: pixelFiring)

        model.reportOpening()

        #expect(pixelFiring.actualFireCalls == [ExpectedFireCall(pixel: AddFavoritePixel.opened, frequency: .dailyAndCount)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only a successful save fires the saved pixel", .timeLimit(.minutes(1)), arguments: [true, false])
    func onlySuccessfulSaveFiresSavedPixel(saveSucceeds: Bool) {
        let bookmarks = MockAddFavoriteBookmarks()
        bookmarks.saveSucceeds = saveSucceeds
        let model = AddFavoriteViewModel(bookmarks: bookmarks, pixelFiring: pixelFiring)
        model.urlText = "example.com"

        #expect(model.save() == saveSucceeds)

        let expectedCalls = saveSucceeds ? [ExpectedFireCall(pixel: AddFavoritePixel.saved, frequency: .dailyAndCount)] : []
        #expect(pixelFiring.actualFireCalls == expectedCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An invalid address fires no save pixel", .timeLimit(.minutes(1)))
    func invalidAddressFiresNoSavePixel() {
        let model = AddFavoriteViewModel(bookmarks: MockAddFavoriteBookmarks(), pixelFiring: pixelFiring)
        model.urlText = "   "

        #expect(!model.save())
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }
}

extension NewTabPageReturnSettings {

    static func makeForTests(idleThresholdSeconds: Int = AfterInactivityIdleInterval.default.seconds,
                             keyValueStore: MockKeyValueFileStore = MockKeyValueFileStore(),
                             featureFlagger: FeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.showNTPAfterIdleReturn])) -> NewTabPageReturnSettings {
        let eligibilityManager = MockIdleReturnEligibilityManager()
        eligibilityManager.idleThresholdSecondsResult = idleThresholdSeconds
        return NewTabPageReturnSettings(
            afterInactivityOptionAdapter: AfterInactivityOptionAdapter(initialOption: .newTab, keyValueStore: keyValueStore),
            lastTabShortcutAdapter: LastTabShortcutAdapter(keyValueStore: keyValueStore),
            idleReturnEligibilityManager: eligibilityManager,
            keyValueStore: keyValueStore,
            featureFlagger: featureFlagger)
    }
}

@Suite("New Tab Page theme")
@MainActor
struct NewTabPageThemeTests {

    private func makeStore(storedTheme: String? = nil) throws -> NewTabPageCustomizationStore {
        let suiteName = "NewTabPageThemeTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        if let storedTheme {
            userDefaults.set(storedTheme, forKey: "com_duckduckgo_ios_newTabPage_theme")
        }
        return NewTabPageCustomizationStore(keyValueStore: userDefaults)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Blue is used when no theme or an unknown theme is stored", .timeLimit(.minutes(1)), arguments: [nil, "removed-theme"])
    func fallsBackToDefaultTheme(storedTheme: String?) throws {
        #expect(try makeStore(storedTheme: storedTheme).theme == .blue)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The publisher emits the current theme, then every change", .timeLimit(.minutes(1)))
    func publisherEmitsCurrentThemeThenChanges() throws {
        var store = try makeStore()
        var received: [NewTabPageTheme] = []
        let cancellable = store.themePublisher.sink { received.append($0) }

        store.theme = .plain
        store.theme = .blue

        #expect(received == [.blue, .plain, .blue])
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("The model starts from the stored theme and writes changes through", .timeLimit(.minutes(1)))
    func modelWritesChangesThrough() {
        let persistor = ReferenceNewTabPageCustomizationPersistor(theme: .plain)
        let model = NewTabPageCustomizationModel(persistor: persistor, returnSettings: NewTabPageReturnSettings.makeForTests(), pixelFiring: nil)
        #expect(model.theme == .plain)

        model.theme = .blue

        #expect(persistor.theme == .blue)
    }
}

private final class ReferenceNewTabPageCustomizationPersistor: NewTabPageCustomizationPersisting {
    var isFavoritesSectionVisible = true
    var isMessagesSectionVisible = true
    var theme: NewTabPageTheme

    init(theme: NewTabPageTheme) {
        self.theme = theme
    }
}

private struct MockNewTabPageCustomizationPersistor: NewTabPageCustomizationPersisting {
    var isFavoritesSectionVisible = true
    var isMessagesSectionVisible = true
    var theme = NewTabPageTheme.default
}

private final class MockAddFavoriteBookmarks: MenuBookmarksInteracting {
    var favoritesDisplayMode: FavoritesDisplayMode = .displayNative(.mobile)
    var saveSucceeds = true

    func createOrToggleFavorite(title: String, url: URL) {}

    func saveFavorite(title: String?, urlString: String) -> Bool { saveSucceeds }

    func createBookmark(title: String, url: URL) {}

    func favorite(for url: URL) -> BookmarkEntity? { nil }

    func bookmark(for url: URL) -> BookmarkEntity? { nil }
}
