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
import DesignResourcesKitIcons
@_spi(Testing) import Persistence
import VPN
import VPNTestUtils

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

        var state = customization.state
        state.currentToolbarButton = .zoom
        state.currentAddressBarButton = .passwords
        customization.persist(state)

        customization.fireToolbarCustomizationSelectedPixel(oldValue: MobileCustomization.toolbarDefault)
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.customizationToolbarSelected.name)
        #expect(PixelFiringMock.lastPixelInfo?.params?["selected"] == MobileCustomization.Button.zoom.rawValue)

        customization.fireAddressBarCustomizationSelectedPixel(oldValue: MobileCustomization.addressBarDefault)
        #expect(PixelFiringMock.lastPixelInfo?.pixelName == Pixel.Event.customizationAddressBarSelected.name)
        #expect(PixelFiringMock.lastPixelInfo?.params?["selected"] == MobileCustomization.Button.passwords.rawValue)
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
        state.currentAddressBarButton = .passwords
        state.currentToolbarButton = .zoom
        customization.persist(state)


        let customizationLoaded = MobileCustomization(keyValueStore: keyValueStore,
                                                      isPad: false) { _ in }

        let loadedState = customizationLoaded.state
        #expect(loadedState.currentToolbarButton == .zoom)
        #expect(loadedState.currentAddressBarButton == .passwords)

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

    @available(iOS 16, *)
    @Test("Validate all requested options are available on both surfaces", .timeLimit(.minutes(1)))
    func requestedOptionsAvailableOnBothSurfaces() {
        let customization = MobileCustomization(keyValueStore: MockThrowingKeyValueStore(),
                                                isPad: false) { _ in }

        #expect(customization.addressBarButtonOptions.contains(.bookmarks))
        #expect(customization.addressBarButtonOptions.contains(.downloads))
        #expect(customization.addressBarButtonOptions.contains(.home))
        #expect(customization.addressBarButtonOptions.contains(.newTab))
        #expect(customization.addressBarButtonOptions.contains(.passwords))
        #expect(customization.toolbarButtonOptions.contains(.addEditBookmark))
        #expect(customization.toolbarButtonOptions.contains(.addEditFavorite))
        #expect(customization.toolbarButtonOptions.contains(.zoom))
    }

    @available(iOS 16, *)
    @Test("Validate webpage context requirements", .timeLimit(.minutes(1)))
    func webpageContextRequirements() {
        #expect(MobileCustomization.Button.share.requiresWebPage)
        #expect(MobileCustomization.Button.addEditBookmark.requiresWebPage)
        #expect(MobileCustomization.Button.addEditFavorite.requiresWebPage)
        #expect(MobileCustomization.Button.zoom.requiresWebPage)
        #expect(!MobileCustomization.Button.bookmarks.requiresWebPage)
        #expect(!MobileCustomization.Button.downloads.requiresWebPage)
        #expect(!MobileCustomization.Button.home.requiresWebPage)
        #expect(!MobileCustomization.Button.newTab.requiresWebPage)
        #expect(!MobileCustomization.Button.passwords.requiresWebPage)
    }

    @available(iOS 16, *)
    @Test("Validate VPN icon reflects connection status", .timeLimit(.minutes(1)))
    func vpnIconReflectsConnectionStatus() {
        let connectionStatusObserver = MockConnectionStatusObserver()
        let customization = MobileCustomization(
            keyValueStore: MockThrowingKeyValueStore(),
            isPad: false,
            postChangeNotification: { _ in },
            connectionStatusObserver: connectionStatusObserver)

        #expect(customization.largeIconForButton(.vpn) == DesignSystemImages.Glyphs.Size24.vpnUnlocked)
        #expect(customization.smallIconForButton(.vpn) == DesignSystemImages.Glyphs.Size16.vpnOff)

        connectionStatusObserver.subject.send(.connected(connectedDate: Date()))

        #expect(customization.largeIconForButton(.vpn) == DesignSystemImages.Glyphs.Size24.vpn)
        #expect(customization.smallIconForButton(.vpn) == DesignSystemImages.Glyphs.Size16.vpnOn)
    }

    // MARK: - Duck.ai Voice toolbar button

    @available(iOS 16, *)
    @Test("duckAIVoice in toolbar options by default", .timeLimit(.minutes(1)))
    func duckAIVoiceInToolbarOptionsByDefault() {
        let keyValueStore = MockThrowingKeyValueStore()
        let customization = MobileCustomization(keyValueStore: keyValueStore,
                                                isPad: false,
                                                postChangeNotification: { _ in })

        #expect(customization.toolbarButtonOptions.contains(.duckAIVoice))
    }

    @available(iOS 16, *)
    @Test("Duck.ai options are hidden and selections fall back when Duck.ai is disabled", .timeLimit(.minutes(1)))
    func duckAIOptionsHiddenWhenDuckAIIsDisabled() {
        var isDuckAIEnabled = true
        let customization = MobileCustomization(
            keyValueStore: MockThrowingKeyValueStore(),
            isPad: false,
            postChangeNotification: { _ in },
            isDuckAIEnabled: { isDuckAIEnabled })

        var state = customization.state
        state.currentToolbarButton = .duckAIVoice
        state.currentAddressBarButton = .duckAIVoice
        customization.persist(state)

        isDuckAIEnabled = false
        customization.refreshAvailability()

        #expect(!customization.toolbarButtonOptions.contains(.duckAIVoice))
        #expect(!customization.addressBarButtonOptions.contains(.duckAIVoice))
        #expect(customization.state.currentToolbarButton == MobileCustomization.toolbarDefault)
        #expect(customization.state.currentAddressBarButton == MobileCustomization.addressBarDefault)
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

extension MobileCustomizationTests: MobileCustomization.Delegate {

    func canEditBookmark() -> Bool {
        return canEditBookmarkFlag
    }

    func canEditFavorite() -> Bool {
        return canEditFavoriteFlag
    }

}
