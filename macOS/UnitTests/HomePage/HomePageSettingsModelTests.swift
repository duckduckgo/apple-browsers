//
//  HomePageSettingsModelTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser
import Foundation
import PixelKit
import SwiftUI
import XCTest

final class NewTabPageCustomizationModelTests: XCTestCase {

    fileprivate var model: NewTabPageCustomizationModel!
    var storageLocation: URL!
    var appearancePreferences: AppearancePreferences!
    var userBackgroundImagesManager: CapturingUserBackgroundImagesManager!
    var sendPixelEvents: [PixelKitEvent] = []
    var openFilePanel: () -> URL? = { return "file:///sample.jpg".url! }
    var openFilePanelCallCount = 0
    var showImageFailedAlertCallCount = 0
    var imageURL: URL?

    override func setUp() async throws {
        sendPixelEvents = []

        storageLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        appearancePreferences = .init(persistor: AppearancePreferencesPersistorMock(), privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger())
        userBackgroundImagesManager = CapturingUserBackgroundImagesManager(storageLocation: storageLocation, maximumNumberOfImages: 4)

        UserDefaultsWrapper<Any>.sharedDefaults.removeObject(forKey: UserDefaultsWrapper<Any>.Key.homePageLastPickedCustomColor.rawValue)

        model = NewTabPageCustomizationModel(
            appearancePreferences: appearancePreferences,
            userBackgroundImagesManager: userBackgroundImagesManager,
            sendPixel: { [weak self] in self?.sendPixelEvents.append($0) },
            openFilePanel: { [weak self] in
                self?.openFilePanelCallCount += 1
                return self?.openFilePanel()
            },
            showAddImageFailedAlert: { [weak self] in self?.showImageFailedAlertCallCount += 1 },
            visualStyle: VisualStyle.legacy
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storageLocation)
        appearancePreferences = nil
        model = nil
        sendPixelEvents = []
        userBackgroundImagesManager = nil
    }

    func testThatCustomBackgroundIsNilByDefault() {
        XCTAssertNil(model.customBackground)
    }

    func testWhenCustomBackgroundIsUpdatedThenPixelIsSent() {
        model.customBackground = .solidColor(.color01)
        model.customBackground = .gradient(.gradient01)
        model.customBackground = .userImage(.init(fileName: "abc", colorScheme: .light))
        model.customBackground = nil

        XCTAssertEqual(sendPixelEvents.map(\.name), [
            NewTabBackgroundPixel.newTabBackgroundSelectedSolidColor.name,
            NewTabBackgroundPixel.newTabBackgroundSelectedGradient.name,
            NewTabBackgroundPixel.newTabBackgroundSelectedUserImage.name,
            NewTabBackgroundPixel.newTabBackgroundReset.name
        ])
    }

    func testThatCustomBackgroundIsPersistedToAppearancePreferences() {
        model.customBackground = .solidColor(.color01)
        XCTAssertEqual(appearancePreferences.homePageCustomBackground, CustomBackground.solidColor(.color01))
        model.customBackground = .gradient(.gradient01)
        XCTAssertEqual(appearancePreferences.homePageCustomBackground, CustomBackground.gradient(.gradient01))
        let userImage = UserBackgroundImage(fileName: "abc", colorScheme: .light)
        model.customBackground = .userImage(userImage)
        XCTAssertEqual(appearancePreferences.homePageCustomBackground, CustomBackground.userImage(userImage))
        model.customBackground = nil
        XCTAssertNil(appearancePreferences.homePageCustomBackground)
    }

    func testWhenUserImageIsSelectedThenItsTimestampIsUpdated() {
        let userImage = UserBackgroundImage(fileName: "abc", colorScheme: .light)
        var updateSelectedTimestampForUserBackgroundImageArguments: [UserBackgroundImage] = []

        userBackgroundImagesManager.updateSelectedTimestampForUserBackgroundImage = { image in
            updateSelectedTimestampForUserBackgroundImageArguments.append(image)
        }
        model.customBackground = .userImage(userImage)

        XCTAssertEqual(userBackgroundImagesManager.updateSelectedTimestampForUserBackgroundImageCallCount, 1)
        XCTAssertEqual(updateSelectedTimestampForUserBackgroundImageArguments, [userImage])
    }

    func testAddImageWhenImageIsNotSelectedThenReturnsEarly() async {
        openFilePanel = { nil }
        await model.addNewImage()
        XCTAssertEqual(userBackgroundImagesManager.addImageWithURLCallCount, 0)
        XCTAssertTrue(sendPixelEvents.isEmpty)
        XCTAssertEqual(showImageFailedAlertCallCount, 0)
    }

    func testAddImageWhenImageIsAddedThenCustomBackgroundIsUpdated() async {
        await model.addNewImage()
        XCTAssertEqual(userBackgroundImagesManager.addImageWithURLCallCount, 1)
        XCTAssertEqual(model.customBackground, .userImage(.init(fileName: "sample.jpg", colorScheme: .light)))
        XCTAssertEqual(sendPixelEvents.map(\.name), [
            NewTabBackgroundPixel.newTabBackgroundSelectedUserImage.name
        ])
        XCTAssertEqual(showImageFailedAlertCallCount, 0)
    }

    func testAddImageWhenImageAddingFailsThenAlertIsShown() async {
        struct TestError: Error {}
        userBackgroundImagesManager.addImageWithURL = { _ in
            throw TestError()
        }

        let originalCustomBackground = model.customBackground
        await model.addNewImage()

        XCTAssertEqual(userBackgroundImagesManager.addImageWithURLCallCount, 1)
        XCTAssertEqual(model.customBackground, originalCustomBackground)
        XCTAssertEqual(sendPixelEvents.map(\.name), [
            NewTabBackgroundPixel.newTabBackgroundAddImageError.name
        ])
        XCTAssertEqual(showImageFailedAlertCallCount, 1)
    }
}
