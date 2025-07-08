//
//  NewTabPageShownPixelSenderTests.swift
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

import Combine
import NewTabPage
import PersistenceTestingUtils
import PixelKit
import PrivacyStats
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class MockNewTabPageProtectionsReportVisibleFeedProvider: NewTabPageProtectionsReportVisibleFeedProviding {
    var visibleFeed: NewTabPageDataModel.Feed?
}

final class NewTabPageShownPixelSenderTests: XCTestCase {

    var appearancePreferences: AppearancePreferences!
    var visibleFeedProvider: MockNewTabPageProtectionsReportVisibleFeedProvider!
    var customizationModel: NewTabPageCustomizationModel!
    var handler: NewTabPageShownPixelSender!
    var keyValueStore: MockKeyValueStore!
    var firePixelCalls: [PixelKitEvent] = []

    override func setUp() async throws {
        try await super.setUp()

        firePixelCalls.removeAll()

        let appearancePreferencesPersistor = AppearancePreferencesPersistorMock()
        appearancePreferences = AppearancePreferences(
            persistor: appearancePreferencesPersistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        visibleFeedProvider = MockNewTabPageProtectionsReportVisibleFeedProvider()

        customizationModel = NewTabPageCustomizationModel(
            appearancePreferences: appearancePreferences,
            userBackgroundImagesManager: nil,
            sendPixel: { _ in },
            openFilePanel: { nil },
            showAddImageFailedAlert: {},
            visualStyle: VisualStyle.legacy
        )

        handler = NewTabPageShownPixelSender(
            appearancePreferences: appearancePreferences,
            protectionsReportVisibleFeedProvider: visibleFeedProvider,
            customizationModel: customizationModel,
            fireDailyPixel: { self.firePixelCalls.append($0) }
        )
    }

    override func tearDown() {
        appearancePreferences = nil
        customizationModel = nil
        firePixelCalls = []
        handler = nil
        visibleFeedProvider = nil
    }

    func testWhenFirePixelIsCalledThenPixelIsSent() {
        handler.firePixel()
        XCTAssertEqual(firePixelCalls.count, 1)
    }

    func testWhenFavoritesIsVisibleThenPixelSetsTrueForFavorites() throws {
        appearancePreferences.isFavoriteVisible = true

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(favorites: true, _, _):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }

    func testWhenFavoritesIsNotVisibleThenPixelSetsFalseForFavorites() throws {
        appearancePreferences.isFavoriteVisible = false

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(favorites: false, _, _):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }

    func testWhenProtectionsReportDisplaysPrivacyStatsThenPixelSetsBlockedTrackingAttemptsForProtections() throws {
        appearancePreferences.isProtectionsReportVisible = true
        visibleFeedProvider.visibleFeed = .privacyStats

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(_, protections: .blockedTrackingAttempts, _):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }

    func testWhenProtectionsReportDisplaysRecentActivityThenPixelSetsRecentActivityForProtections() throws {
        appearancePreferences.isProtectionsReportVisible = true
        visibleFeedProvider.visibleFeed = .activity

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(_, protections: .recentActivity, _):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }

    func testWhenProtectionsReportIsCollapsedThenPixelSetsCollapsedForProtections() throws {
        appearancePreferences.isProtectionsReportVisible = true
        visibleFeedProvider.visibleFeed = nil

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(_, protections: .collapsed, _):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }

    func testWhenProtectionsReportIsNotVisibleThenPixelSetsHiddenForProtectionsReport() throws {
        appearancePreferences.isProtectionsReportVisible = false

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(_, protections: .hidden, _):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }

    func testWhenBackgroundIsCustomThenPixelSetsTrueForCustomBackground() throws {
        customizationModel.customBackground = .gradient(.gradient02)

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(_, _, customBackground: true):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }

    func testWhenBackgroundIsDefaultThenPixelSetsFalseForCustomBackground() throws {
        customizationModel.customBackground = nil

        handler.firePixel()
        let pixel = try XCTUnwrap(firePixelCalls.first as? NewTabPagePixel)

        switch pixel {
        case .newTabPageShown(_, _, customBackground: false):
            break
        default:
            XCTFail("Unexpected pixel value: \(pixel)")
        }
    }
}
