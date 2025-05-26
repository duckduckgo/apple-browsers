//
//  NewTabPageCustomizationProviderTests.swift
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

import AppKitExtensions
import Combine
import NewTabPage
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageCustomizationProviderTests: XCTestCase {
    var storageLocation: URL!
    var appearancePreferences: AppearancePreferences!
    var userBackgroundImagesManager: CapturingUserBackgroundImagesManager!
    var openFilePanelCalls: Int = 0
    private var customizationModel: NewTabPageCustomizationModel!
    private var provider: NewTabPageCustomizationProvider!

    @MainActor
    override func setUp() async throws {

        appearancePreferences = AppearancePreferences(persistor: MockAppearancePreferencesPersistor())
        storageLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        userBackgroundImagesManager = CapturingUserBackgroundImagesManager(storageLocation: storageLocation, maximumNumberOfImages: 4)
        openFilePanelCalls = 0

        customizationModel = NewTabPageCustomizationModel(
            appearancePreferences: appearancePreferences,
            userBackgroundImagesManager: userBackgroundImagesManager,
            sendPixel: { _ in },
            openFilePanel: {
                self.openFilePanelCalls += 1
                return nil
            },
            showAddImageFailedAlert: {},
            visualStyle: VisualStyle.legacy
        )

        provider = NewTabPageCustomizationProvider(customizationModel: customizationModel, appearancePreferences: appearancePreferences)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storageLocation)
    }

    func testThatCustomizerOpenerReturnsSettingsModelCustomizerOpener() {
        XCTAssertIdentical(provider.customizerOpener, customizationModel.customizerOpener)
    }

    func testThatBackgroundGetterReturnsSettingsModelBackground() throws {
        customizationModel.customBackground = .gradient(.gradient01)
        XCTAssertEqual(provider.background, .gradient("gradient01"))

        customizationModel.customBackground = .solidColor(.color02)
        XCTAssertEqual(provider.background, .solidColor("color02"))

        let hexColor = try XCTUnwrap(SolidColorBackground("#abcdef"))
        customizationModel.customBackground = .solidColor(hexColor)
        XCTAssertEqual(provider.background, .hexColor("#abcdef"))

        let userImage = UserBackgroundImage(fileName: "abc.jpg", colorScheme: .light)
        customizationModel.customBackground = .userImage(userImage)
        XCTAssertEqual(provider.background, .userImage(.init(userImage)))

        customizationModel.customBackground = nil
        XCTAssertEqual(provider.background, .default)
    }

    func testThatBackgroundSetterSetsCorrectBackgroundInSettingsModel() throws {
        provider.background = .gradient("gradient02.01")
        XCTAssertEqual(customizationModel.customBackground, .gradient(.gradient0201))

        provider.background = .solidColor("color02")
        XCTAssertEqual(customizationModel.customBackground, .solidColor(.color02))

        provider.background = .hexColor("#ABCDEF")
        let hexColor = try XCTUnwrap(SolidColorBackground("#abcdef"))
        XCTAssertEqual(customizationModel.customBackground, .solidColor(hexColor))

        let userImage = UserBackgroundImage(fileName: "abc.jpg", colorScheme: .light)
        provider.background = .userImage(.init(userImage))
        XCTAssertEqual(customizationModel.customBackground, .userImage(userImage))

        provider.background = .default
        XCTAssertEqual(customizationModel.customBackground, nil)
    }

    @MainActor
    func testThatCustomizerDataReturnsCorrectDataFromSettingsModelAndApperancePreferences() async throws {
        try await waitForAvailableUserBackgroundImages {
            userBackgroundImagesManager.availableImages = [
                .init(fileName: "1.jpg", colorScheme: .light),
                .init(fileName: "2.jpg", colorScheme: .dark)
            ]
        }

        // this sets lastPickedCustomColor
        customizationModel.customBackground = .solidColor(try XCTUnwrap(.init("#123abc")))
        customizationModel.customBackground = .solidColor(.color05)
        appearancePreferences.currentThemeName = .light

        XCTAssertEqual(
            provider.customizerData,
            .init(
                background: .solidColor("color05"),
                theme: .light,
                userColor: .init(hex: "#123abc"),
                userImages: userBackgroundImagesManager.availableImages.map(NewTabPageDataModel.UserImage.init),
                defaultStyles: .init(lightBackgroundColor: "#FAFAFA", darkBackgroundColor: "#333333")
            )
        )
    }

    func testThatBackgroundPublisherPublishesEvents() throws {
        var events: [NewTabPageDataModel.Background] = []
        let cancellable = provider.backgroundPublisher.sink { events.append($0) }

        customizationModel.customBackground = .gradient(.gradient04)
        customizationModel.customBackground = .solidColor(.color13)
        customizationModel.customBackground = .solidColor(.color13)
        customizationModel.customBackground = .solidColor(.color13)
        customizationModel.customBackground = .solidColor(.color13)
        customizationModel.customBackground = .solidColor(try XCTUnwrap(.init("#123abc")))
        customizationModel.customBackground = nil
        customizationModel.customBackground = .userImage(.init(fileName: "1.jpg", colorScheme: .light))

        cancellable.cancel()

        XCTAssertEqual(
            events,
            [
                .gradient("gradient04"),
                .solidColor("color13"),
                .hexColor("#123abc"),
                .default,
                .userImage(.init(.init(fileName: "1.jpg", colorScheme: .light)))
            ]
        )
    }

    func testThatThemeGetterReturnsAppearancePreferencesTheme() {
        appearancePreferences.currentThemeName = .dark
        XCTAssertEqual(provider.theme, .dark)
        appearancePreferences.currentThemeName = .light
        XCTAssertEqual(provider.theme, .light)
        appearancePreferences.currentThemeName = .systemDefault
        XCTAssertEqual(provider.theme, nil)
    }

    func testThatThemeSetterSetsAppearancePreferencesTheme() {
        provider.theme = .dark
        XCTAssertEqual(appearancePreferences.currentThemeName, .dark)
        provider.theme = .light
        XCTAssertEqual(appearancePreferences.currentThemeName, .light)
        provider.theme = nil
        XCTAssertEqual(appearancePreferences.currentThemeName, .systemDefault)
    }

    func testThatThemePublisherPublishesEvents() throws {
        var events: [NewTabPageDataModel.Theme?] = []
        let cancellable = provider.themePublisher.sink { events.append($0) }

        appearancePreferences.currentThemeName = .light
        appearancePreferences.currentThemeName = .dark
        appearancePreferences.currentThemeName = .dark
        appearancePreferences.currentThemeName = .dark
        appearancePreferences.currentThemeName = .dark
        appearancePreferences.currentThemeName = .systemDefault
        appearancePreferences.currentThemeName = .systemDefault
        appearancePreferences.currentThemeName = .light

        cancellable.cancel()

        XCTAssertEqual(events, [.light, .dark, nil, .light])
    }

    func testThatUserImagesPublisherPublishesEvents() async throws {
        var events: [[NewTabPageDataModel.UserImage]] = []
        let cancellable = provider.userImagesPublisher.sink { events.append($0) }

        let image1 = UserBackgroundImage(fileName: "1.jpg", colorScheme: .light)
        let image2 = UserBackgroundImage(fileName: "2.jpg", colorScheme: .dark)

        try await waitForAvailableUserBackgroundImages {
            userBackgroundImagesManager.availableImages = [image1]
        }
        try await waitForAvailableUserBackgroundImages {
            userBackgroundImagesManager.availableImages = [image1, image2]
        }
        try await waitForAvailableUserBackgroundImages(inverted: true) {
            userBackgroundImagesManager.availableImages = [image1, image2]
        }
        try await waitForAvailableUserBackgroundImages(inverted: true) {
            userBackgroundImagesManager.availableImages = [image1, image2]
        }
        try await waitForAvailableUserBackgroundImages {
            userBackgroundImagesManager.availableImages = []
        }
        try await waitForAvailableUserBackgroundImages {
            userBackgroundImagesManager.availableImages = [image2, image1]
        }

        cancellable.cancel()

        /// Slower machines may capture the initial empty array event.
        /// We're only interested in the correct sequence of events once images start being added.
        XCTAssertEqual(events.suffix(4), [
            [.init(image1)],
            [.init(image1), .init(image2)],
            [],
            [.init(image2), .init(image1)]
        ])
    }

    func testThatPresentUploadDialogCallsAddImage() async {
        await provider.presentUploadDialog()
        XCTAssertEqual(openFilePanelCalls, 1)
    }

    func testThatDeleteImageCallsImagesManager() async throws {
        try await waitForAvailableUserBackgroundImages {
            userBackgroundImagesManager.availableImages = [.init(fileName: "1.jpg", colorScheme: .light)]
        }
        await provider.deleteImage(with: "1.jpg")
        XCTAssertEqual(userBackgroundImagesManager.deleteImageCallCount, 1)
    }

    func testThatDeleteImageReturnsEarlyIfImageIsNotPresent() async {
        await provider.deleteImage(with: "aaaaaa.jpg")
        XCTAssertEqual(userBackgroundImagesManager.deleteImageCallCount, 0)
    }

    @MainActor
    func testThatShowContextMenuPresentsTheMenuForTheSpecifiedImageID() async throws {

        final class CapturingNewTabPageContextMenuPresenter: NewTabPageContextMenuPresenting {
            var window: NSWindow?
            func showContextMenu(_ menu: NSMenu) {
                showContextMenuCalls.append(menu)
            }
            var showContextMenuCalls: [NSMenu] = []
        }

        let contextMenuPresenter = CapturingNewTabPageContextMenuPresenter()
        await provider.showContextMenu(for: "abcd.jpg", using: contextMenuPresenter)

        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        let deleteBackgroundItem = try XCTUnwrap(menu.item(at: 0))
        let imageID = try XCTUnwrap(deleteBackgroundItem.representedObject as? String)
        XCTAssertEqual(imageID, "abcd.jpg")
    }

    // MARK: - Helpers

    /**
     * Sets up an expectation, then sets up Combine subscription for `settingsModel.$availableUserBackgroundImages` that fulfills
     * the expectation, then calls the provided `block` and waits for time specified by `duration` before cancelling the subscription.
     */
    @MainActor
    private func waitForAvailableUserBackgroundImages(for duration: TimeInterval = 1, inverted: Bool = false, _ block: @MainActor () async -> Void = {}) async throws {
        let expectation = self.expectation(description: "viewModelUpdate")
        expectation.isInverted = inverted
        let cancellable = customizationModel.$availableUserBackgroundImages.dropFirst().prefix(1).sink { _ in expectation.fulfill() }

        await block()

        await fulfillment(of: [expectation], timeout: duration)
        cancellable.cancel()
    }
}
