//
//  AddToDockMenuActionTests.swift
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

import FeatureFlags_macOS
@_spi(Testing) import PixelKit
import PrivacyConfig
import Testing

@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Add to Dock Menu Action Tests")
final class AddToDockMenuActionTests {

    private let dockCustomizer = DockCustomizerMock()
    private let featureFlagger = MockFeatureFlagger()
    private let videoPresenter = CapturingAddToDockVideoPresenter()
    private let pixelFiring = PixelKitMock()

    private func makeSUT() -> AddToDockMenuAction {
        AddToDockMenuAction(dockCustomization: dockCustomizer, featureFlagger: featureFlagger, videoPresenter: videoPresenter, pixelFiring: pixelFiring)
    }

    private func setAppStoreBuild(canShowVideo: Bool) {
        dockCustomizer.supportsAddingToDock = false
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = canShowVideo
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func dmgNotInDockCanShowMenuItem() {
        #expect(makeSUT().canShowMenuItem)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func dmgInDockCannotShowMenuItem() {
        dockCustomizer.dockStatus = true

        #expect(!makeSUT().canShowMenuItem)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreWithFlagOnCanShowMenuItem() {
        setAppStoreBuild(canShowVideo: true)

        #expect(makeSUT().canShowMenuItem)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreWithFlagOffCannotShowMenuItem() {
        setAppStoreBuild(canShowVideo: false)

        #expect(!makeSUT().canShowMenuItem)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreInDockCannotShowMenuItem() {
        setAppStoreBuild(canShowVideo: true)
        dockCustomizer.dockStatus = true

        #expect(!makeSUT().canShowMenuItem)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreFlagTurningOffHidesMenuItem() {
        setAppStoreBuild(canShowVideo: true)
        let sut = makeSUT()
        #expect(sut.canShowMenuItem)

        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = false

        #expect(!sut.canShowMenuItem)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreMainMenuPresentsVideoAndFiresClickPixel() {
        setAppStoreBuild(canShowVideo: true)

        makeSUT().perform(from: .mainMenu)

        #expect(videoPresenter.presentations == [.done])
        #expect(pixelFiring.actualFireCalls == [ExpectedFireCall(pixel: GeneralPixel.userAddedToDockFromMainMenu, frequency: .standard)])
        #expect(!dockCustomizer.isAddedToDock)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreMoreOptionsMenuPresentsVideoAndFiresClickPixel() {
        setAppStoreBuild(canShowVideo: true)

        makeSUT().perform(from: .moreOptionsMenu)

        #expect(videoPresenter.presentations == [.done])
        #expect(pixelFiring.actualFireCalls == [ExpectedFireCall(pixel: GeneralPixel.userAddedToDockFromMoreOptionsMenu, frequency: .dailyAndStandard)])
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreWhenVideoIsNotShownFiresNoClickPixel() {
        setAppStoreBuild(canShowVideo: true)
        videoPresenter.presentResult = false

        makeSUT().perform(from: .mainMenu)

        #expect(videoPresenter.presentations == [.done])
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func appStoreWithFlagOffDoesNothing() {
        setAppStoreBuild(canShowVideo: false)

        makeSUT().perform(from: .mainMenu)

        #expect(videoPresenter.presentations.isEmpty)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func dmgMainMenuAddsToDockAndFiresPixel() {
        makeSUT().perform(from: .mainMenu)

        #expect(dockCustomizer.isAddedToDock)
        #expect(videoPresenter.presentations.isEmpty)
        #expect(pixelFiring.actualFireCalls == [ExpectedFireCall(pixel: GeneralPixel.userAddedToDockFromMainMenu, frequency: .standard)])
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func dmgMoreOptionsMenuAddsToDockAndFiresPixel() {
        makeSUT().perform(from: .moreOptionsMenu)

        #expect(dockCustomizer.isAddedToDock)
        #expect(pixelFiring.actualFireCalls == [ExpectedFireCall(pixel: GeneralPixel.userAddedToDockFromMoreOptionsMenu, frequency: .dailyAndStandard)])
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func dmgAlreadyInDockFiresNoPixel() {
        dockCustomizer.dockStatus = true

        makeSUT().perform(from: .mainMenu)

        #expect(pixelFiring.actualFireCalls.isEmpty)
    }
}
