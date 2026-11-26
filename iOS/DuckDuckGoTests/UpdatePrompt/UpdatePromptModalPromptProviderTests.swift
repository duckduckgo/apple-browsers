//
//  UpdatePromptModalPromptProviderTests.swift
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

import Core
import Foundation
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Update prompt provider")
final class UpdatePromptModalPromptProviderTests {

    private let releaseDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let storage: any ThrowingKeyedStoring<UpdatePromptKeys> = InMemoryThrowingKeyValueStore().throwingKeyedStoring()
    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.updatePrompt])
    private let pixelFiring = PixelKitMock()
    private var openedURLs: [URL] = []
    private var now: Date

    init() {
        now = releaseDate.addingTimeInterval(3 * 24 * 60 * 60)
    }

    private func makeProvider() -> UpdatePromptModalPromptProvider {
        UpdatePromptModalPromptProvider(storage: storage,
                                        featureFlagger: featureFlagger,
                                        installedVersion: "7.240.0",
                                        osVersion: "18.0",
                                        pixelFiring: pixelFiring,
                                        openURL: { [unowned self] in openedURLs.append($0) },
                                        now: { [unowned self] in now })
    }

    private func cacheNewerRelease() throws {
        try storage.set(AppStoreRelease(version: "7.241.0", releaseDate: releaseDate, minimumOSVersion: "16.0"),
                        for: \.latestRelease)
    }

    private func pixelNames() -> [String] {
        pixelFiring.actualFireCalls.map { "\($0.pixel.name) step=\($0.pixel.parameters?["step"] ?? "-")" }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ineligible while the flag is off", .timeLimit(.minutes(1)))
    func flagOff() {
        featureFlagger.enabledFeatureFlags = []
        #expect(!makeProvider().isEligibleToPresent(isOnboardingComplete: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Eligible with the flag on once onboarding is done", .timeLimit(.minutes(1)))
    func flagOn() {
        let provider = makeProvider()
        #expect(provider.isEligibleToPresent(isOnboardingComplete: true))
        #expect(!provider.isEligibleToPresent(isOnboardingComplete: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nothing to show without a cached release", .timeLimit(.minutes(1)))
    func noRelease() {
        #expect(makeProvider().provideModalPrompt() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Shows once presented, then waits for the next reminder", .timeLimit(.minutes(1)))
    func showsAndRecords() throws {
        try cacheNewerRelease()
        let provider = makeProvider()

        let configuration = try #require(provider.provideModalPrompt())
        #expect(configuration.exposureID == .updatePrompt)
        #expect(configuration.viewController.modalPresentationStyle == .overFullScreen)

        provider.didPresentModal()
        #expect(pixelNames() == ["update-prompt_shown step=1"])
        #expect(provider.provideModalPrompt() == nil)

        now = releaseDate.addingTimeInterval(8 * 24 * 60 * 60)
        #expect(provider.provideModalPrompt() != nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Stays due when it was never presented", .timeLimit(.minutes(1)))
    func notPresented() throws {
        try cacheNewerRelease()
        let provider = makeProvider()
        #expect(provider.provideModalPrompt() != nil)

        let nextLaunch = makeProvider()
        #expect(nextLaunch.provideModalPrompt() != nil)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Update opens the App Store", .timeLimit(.minutes(1)))
    func update() throws {
        try cacheNewerRelease()
        let configuration = try #require(makeProvider().provideModalPrompt())
        let controller = try #require(configuration.viewController as? UpdatePromptHostingController)

        controller.rootView.onUpdate()

        #expect(openedURLs == [URL.appStore])
        #expect(pixelNames() == ["update-prompt_update-tapped step=1"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Not Now closes without opening anything", .timeLimit(.minutes(1)))
    func notNow() throws {
        try cacheNewerRelease()
        let configuration = try #require(makeProvider().provideModalPrompt())
        let controller = try #require(configuration.viewController as? UpdatePromptHostingController)

        controller.rootView.onNotNow()

        #expect(openedURLs.isEmpty)
        #expect(pixelNames() == ["update-prompt_dismissed step=1"])
    }
}
