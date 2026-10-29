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
import Foundation
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
        let model = NewTabPageCustomizationModel(persistor: persistor, pixelFiring: pixelFiring)

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
                                                 pixelFiring: pixelFiring)

        model.isKeyboardShownOnNewTab = false

        #expect(pixelFiring.actualFireCalls == [
            ExpectedFireCall(pixel: NewTabPageCustomizationPixel.keyboardToggled(enabled: false), frequency: .dailyAndCount)
        ])
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == ["enabled": "false"])
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

private struct MockNewTabPageCustomizationPersistor: NewTabPageCustomizationPersisting {
    var isFavoritesSectionVisible = true
    var isMessagesSectionVisible = true
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
