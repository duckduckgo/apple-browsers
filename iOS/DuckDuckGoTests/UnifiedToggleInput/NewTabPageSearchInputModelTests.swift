//
//  NewTabPageSearchInputModelTests.swift
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class NewTabPageSearchInputModelTests: XCTestCase {

    func testDisablingAIChatRemovesControlsAndReturnsToSearchOnExistingInput() async {
        let notifications = NotificationCenter()
        var settings = NewTabPageSearchInputModel.Settings(
            isModeToggleShown: true, isAIChatEnabled: true, isVoiceSearchEnabled: true, defaultTextEntryMode: .aiChat)
        let model = NewTabPageSearchInputModel(notificationCenter: notifications, readSettings: { settings })
        XCTAssertEqual(model.textEntryMode, .aiChat)

        settings.isAIChatEnabled = false
        settings.isModeToggleShown = false
        await post(.aiChatSettingsChanged, to: notifications)

        XCTAssertFalse(model.settings.isModeToggleShown)
        XCTAssertFalse(model.settings.isAIChatEnabled)
        XCTAssertEqual(model.textEntryMode, .search)
    }

    func testEnablingToggleAndChangingDefaultModeUpdatesExistingInput() async {
        let notifications = NotificationCenter()
        var settings = NewTabPageSearchInputModel.Settings(
            isModeToggleShown: false, isAIChatEnabled: true, isVoiceSearchEnabled: false, defaultTextEntryMode: .aiChat)
        let model = NewTabPageSearchInputModel(notificationCenter: notifications, readSettings: { settings })
        XCTAssertEqual(model.textEntryMode, .search)

        settings.isModeToggleShown = true
        await post(.aiChatSettingsChanged, to: notifications)
        XCTAssertTrue(model.settings.isModeToggleShown)
        XCTAssertEqual(model.textEntryMode, .aiChat)

        settings.defaultTextEntryMode = .search
        await post(.aiChatSettingsChanged, to: notifications)
        XCTAssertEqual(model.textEntryMode, .search)
    }

    func testVoiceAvailabilityChangesPreserveSelectedMode() async {
        let notifications = NotificationCenter()
        var settings = NewTabPageSearchInputModel.Settings(
            isModeToggleShown: true, isAIChatEnabled: true, isVoiceSearchEnabled: true, defaultTextEntryMode: .search)
        let model = NewTabPageSearchInputModel(notificationCenter: notifications, readSettings: { settings })
        model.textEntryMode = .aiChat

        for enabled in [false, true] {
            settings.isVoiceSearchEnabled = enabled
            await post(.speechRecognizerDidChangeAvailability, to: notifications)
            XCTAssertEqual(model.settings.isVoiceSearchEnabled, enabled)
            XCTAssertEqual(model.textEntryMode, .aiChat)
        }
    }

    func testNotificationSubscriptionsDoNotRetainInput() {
        let notifications = NotificationCenter()
        var model: NewTabPageSearchInputModel? = NewTabPageSearchInputModel(notificationCenter: notifications, readSettings: {
            .init(isModeToggleShown: false, isAIChatEnabled: false, isVoiceSearchEnabled: false, defaultTextEntryMode: .search)
        })
        weak var weakModel = model
        model = nil
        XCTAssertNil(weakModel)
    }

    private func post(_ name: Notification.Name, to notifications: NotificationCenter) async {
        notifications.post(name: name, object: nil)
        // Drain the main queue after the model's notification delivery.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
