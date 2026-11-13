//
//  AppStoreUpdateCompletionPixelTests.swift
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

import AppUpdaterShared
import AppUpdaterTestHelpers
import Foundation
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import Testing

@testable import AppStoreAppUpdater

@MainActor
@Suite("App Store update completion pixel")
struct AppStoreUpdateCompletionPixelTests {

    private let pixelKit = PixelKitMock()
    private let attribution = UpdatePromptAttribution(settings: InMemoryThrowingKeyValueStore().throwingKeyedStoring())

    private func makeController() -> AppStoreUpdateController {
        AppStoreUpdateController(pixelFiring: pixelKit, notificationPresenter: MockNotificationPresenter())
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fires the success pixel with the clicked surface after an update", .timeLimit(.minutes(1)))
    func firesSuccessPixelAfterUpdate() {
        attribution.recordClick(on: .toolbarButton)

        makeController().reportCompletedUpdate(status: .updated, promptAttribution: attribution)

        #expect(pixelKit.actualFireCalls.count == 1)
        let call = pixelKit.actualFireCalls.first
        #expect(call?.pixel.name == "m_mac_update_application_success")
        #expect(call?.frequency == .dailyAndCount)
        #expect(call?.pixel.parameters?["promptSurface"] == "toolbar-button")
        #expect(call?.pixel.parameters?["sourceVersion"] == "unknown")
        #expect(call?.pixel.parameters?["initiationType"] == "unknown")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports none when no prompt was clicked", .timeLimit(.minutes(1)))
    func reportsNoneWithoutClick() {
        makeController().reportCompletedUpdate(status: .updated, promptAttribution: attribution)

        #expect(pixelKit.actualFireCalls.first?.pixel.parameters?["promptSurface"] == "none")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fires nothing and keeps the click when the app wasn't updated", .timeLimit(.minutes(1)),
          arguments: [AppUpdateStatus.noChange, .downgraded])
    func firesNothingWithoutUpdate(status: AppUpdateStatus) {
        attribution.recordClick(on: .menuRow)

        makeController().reportCompletedUpdate(status: status, promptAttribution: attribution)

        #expect(pixelKit.actualFireCalls.isEmpty)
        #expect(attribution.consumePromptSurface() == "menu-row")
    }
}
