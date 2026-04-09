//
//  MobileCustomizationTests.swift
//  DuckDuckGo
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

import Foundation
import Testing
@testable import DuckDuckGo
@testable import Core
import PersistenceTestingUtils

@Suite("Mobile Customization Tests", .serialized)
final class MobileCustomizationTests {

    var canEditFavoriteFlag = false
    var canEditBookmarkFlag = false

    @Test("Validate expected pixels with parameters are sent")
    func pixels() {
        let keyValueStore = MockThrowingKeyValueStore()
        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false,
                                                postChangeNotification: { _ in },
                                                pixelFiring: PixelFiringMock.self)

        customization.fireToolbarCustomizationStartedPixel()
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.customizationToolbarStarted.name)

        customization.fireAddressBarCustomizationStartedPixel()
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.customizationAddressBarStarted.name)

        // So far two pixels fired
        #expect(PixelFiringMock.allPixelsFired.count == 2)

        // Check no pixel fired if the state is the same
        customization.fireToolbarCustomizationSelectedPixel(oldValue: MobileCustomization.toolbarDefault)
        #expect(PixelFiringMock.allPixelsFired.count == 2)

        customization.fireToolbarCustomizationSelectedPixel(oldValue: MobileCustomization.Button.home)
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.customizationToolbarSelected.name)
        #expect(PixelFiringMock.lastPixelInfo?.params?["selected"] == MobileCustomization.toolbarDefault.rawValue)

        customization.fireAddressBarCustomizationSelectedPixel(oldValue: MobileCustomization.Button.home)
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.customizationAddressBarSelected.name)
        #expect(PixelFiringMock.lastPixelInfo?.params?["selected"] == MobileCustomization.addressBarDefault.rawValue)
        #expect(PixelFiringMock.allPixelsFired.count == 4)

    }

    @Test("Validate initial state on phone when feature is enabled")
    func initialStateOnPhoneWhenFeatureIsEnabled() {
        let keyValueStore = MockThrowingKeyValueStore()
        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false) { _ in }

        #expect(customization.isEnabled)
        #expect(customization.hasFireButton)
        #expect(customization.state.isEnabled)
        #expect(customization.state.currentAddressBarButton == .share)
        #expect(customization.state.currentToolbarButton == .fire)
    }

    @Test("Validate initial state on ipad when feature is enabled")
    func initialStateOnPadWhenFeatureIsEnabled() {
        let keyValueStore = MockThrowingKeyValueStore()
        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: true) { _ in }

        #expect(!customization.isEnabled)
        #expect(customization.hasFireButton)
        #expect(!customization.state.isEnabled)
        #expect(customization.state.currentAddressBarButton == .share)
        #expect(customization.state.currentToolbarButton == .fire)
    }

    @Test("Validate when state is updated externally then notificaiton is posted")
    func whenStateIsUpdatedExternallyThenNotificationIsPosted() {

        var posted = false

        let keyValueStore = MockThrowingKeyValueStore()
        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false) { _ in
            posted = true
        }

        var state = customization.state
        state.currentAddressBarButton = .addEditBookmark
        customization.persist(state)

        #expect(posted)
    }

    @Test("Validate when state is updated externally then state is persisted")
    func whenStateIsUpdatedExternallyThenStateIsPersisted() {

        let keyValueStore = MockThrowingKeyValueStore()

        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false) { _ in }

        var state = customization.state
        state.currentAddressBarButton = .addEditBookmark
        state.currentToolbarButton = .home
        customization.persist(state)


        let customizationLoaded = MobileCustomization(keyValueStore: keyValueStore,
                                                      isPad: false) { _ in }

        let loadedState = customizationLoaded.state
        #expect(loadedState.currentToolbarButton == .home)
        #expect(loadedState.currentAddressBarButton == .addEditBookmark)

    }

    @Test("Validate alt icon provided for button when flags are set")
    func altIconProvidedForButtonWhenFlagsAreSet() {

        let keyValueStore = MockThrowingKeyValueStore()

        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false) { _ in }

        customization.delegate = self

        var state = customization.state
        state.currentAddressBarButton = .addEditBookmark
        state.currentToolbarButton = .home
        customization.persist(state)

        // Check the edit button
        #expect(customization.largeIconForButton(.addEditBookmark) == MobileCustomization.Button.addEditBookmark.largeIcon)

        canEditBookmarkFlag = true

        #expect(customization.largeIconForButton(.addEditBookmark) == MobileCustomization.Button.addEditBookmark.altLargeIcon)

        // Check the favorite button
        #expect(customization.largeIconForButton(.addEditFavorite) == MobileCustomization.Button.addEditFavorite.largeIcon)

        canEditFavoriteFlag = true

        #expect(customization.largeIconForButton(.addEditFavorite) == MobileCustomization.Button.addEditFavorite.altLargeIcon)

        // None should return nothing
        #expect(customization.largeIconForButton(.none) == nil)

        // Check some image is returned otehrs
        #expect(customization.largeIconForButton(.bookmarks) != nil)
        #expect(customization.largeIconForButton(.downloads) != nil)
        #expect(customization.largeIconForButton(.fire) != nil)
        #expect(customization.largeIconForButton(.home) != nil)
        #expect(customization.largeIconForButton(.newTab) != nil)
        #expect(customization.largeIconForButton(.passwords) != nil)
        #expect(customization.largeIconForButton(.share) != nil)
        #expect(customization.largeIconForButton(.vpn) != nil)
        #expect(customization.largeIconForButton(.zoom) != nil)
        #expect(customization.largeIconForButton(.duckAIVoice) != nil)

    }

    @Test("Validate defaults when invalid state persisted")
    func returnDefaultsWhenInvalidStatePersisted() {

        let keyValueStore = MockThrowingKeyValueStore()

        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false) { _ in }

        var state = customization.state
        state.currentAddressBarButton = .passwords
        state.currentToolbarButton = .zoom
        customization.persist(state)


        let customizationLoaded = MobileCustomization(keyValueStore: keyValueStore,
                                                      isPad: false) { _ in }

        let loadedState = customizationLoaded.state
        #expect(loadedState.currentToolbarButton == .fire)
        #expect(loadedState.currentAddressBarButton == .share)
    }

    // MARK: - Duck.ai Voice toolbar button FF gating

    @available(iOS 16, *)
    @Test("duckAIVoice not in toolbar options when voice shortcut FF is off", .timeLimit(.minutes(1)))
    func duckAIVoiceNotInToolbarOptionsWhenFFOff() {
        let keyValueStore = MockThrowingKeyValueStore()
        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false,
                                                postChangeNotification: { _ in },
                                                voiceShortcutFeature: MockVoiceShortcutFeature(available: false))

        #expect(!customization.toolbarButtonOptions.contains(.duckAIVoice))
    }

    @available(iOS 16, *)
    @Test("duckAIVoice in toolbar options when voice shortcut FF is on", .timeLimit(.minutes(1)))
    func duckAIVoiceInToolbarOptionsWhenFFOn() {
        let keyValueStore = MockThrowingKeyValueStore()
        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false,
                                                postChangeNotification: { _ in },
                                                voiceShortcutFeature: MockVoiceShortcutFeature(available: true))

        #expect(customization.toolbarButtonOptions.contains(.duckAIVoice))
    }

    @available(iOS 16, *)
    @Test("Saved duckAIVoice falls back to default when FF is off", .timeLimit(.minutes(1)))
    func savedDuckAIVoiceFallsBackWhenFFOff() {
        let keyValueStore = MockThrowingKeyValueStore()

        // Save duckAIVoice while FF is on
        let customizationOn = MobileCustomization(keyValueStore: keyValueStore,
                                                  isPad: false,
                                                  postChangeNotification: { _ in },
                                                  voiceShortcutFeature: MockVoiceShortcutFeature(available: true))
        var state = customizationOn.state
        state.currentToolbarButton = .duckAIVoice
        customizationOn.persist(state)
        #expect(customizationOn.state.currentToolbarButton == .duckAIVoice)

        // Load with FF off — should fall back to default
        let customizationOff = MobileCustomization(keyValueStore: keyValueStore,
                                                   isPad: false,
                                                   postChangeNotification: { _ in },
                                                   voiceShortcutFeature: MockVoiceShortcutFeature(available: false))
        #expect(customizationOff.state.currentToolbarButton == MobileCustomization.toolbarDefault)
    }

    @available(iOS 16, *)
    @Test("duckAIVoice has non-nil icons", .timeLimit(.minutes(1)))
    func duckAIVoiceHasIcons() {
        #expect(MobileCustomization.Button.duckAIVoice.largeIcon != nil)
        #expect(MobileCustomization.Button.duckAIVoice.smallIcon != nil)
    }

    deinit {
        PixelFiringMock.tearDown()
    }

}

// MARK: - Mocks

private struct MockVoiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding {
    let available: Bool
    var isAvailable: Bool { available }
}

extension MobileCustomizationTests: MobileCustomization.Delegate {

    func canEditBookmark() -> Bool {
        return canEditBookmarkFlag
    }

    func canEditFavorite() -> Bool {
        return canEditFavoriteFlag
    }

}
