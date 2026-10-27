//
//  FireAnimationStateTests.swift
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

import Combine
import Common
import FoundationExtensions
import History
import FeatureFlags_macOS
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FireAnimationStateTests: XCTestCase {
    @MainActor
    func testLegacyAnimationFinishesExactlyOnce() {
        let fire = AnimationCountingFire()
        let model = FireViewModel(fire: fire)
        model.setAnimationPlaying(true, isFireWindow: false)
        model.setAnimationPlaying(true, isFireWindow: false)
        XCTAssertTrue(model.isAnimationPlaying)
        model.setAnimationPlaying(false, isFireWindow: false)
        model.setAnimationPlaying(false, isFireWindow: false)
        XCTAssertFalse(model.isAnimationPlaying)
        XCTAssertEqual(fire.starts, 1)
        XCTAssertEqual(fire.finishes, 1)
    }

    @MainActor
    func testLegacyAnimationOutlivesClosingSnapshot() {
        let fire = AnimationCountingFire()
        let model = FireViewModel(fire: fire)
        model.setAnimationPlaying(true, isFireWindow: false)
        model.setSnapshotAnimationPlaying(true, isFireWindow: true)
        model.setSnapshotAnimationPlaying(false, isFireWindow: true)
        XCTAssertTrue(model.isAnimationPlaying, "The tab animation still owns a pending burn completion")
        model.setAnimationPlaying(false, isFireWindow: false)
        XCTAssertFalse(model.isAnimationPlaying)
        XCTAssertEqual(fire.starts, 1)
        XCTAssertEqual(fire.finishes, 1, "Closing a snapshot must not consume the legacy completion")
    }

    @MainActor
    func testClosingSnapshotOutlivesLegacyAnimation() {
        let fire = AnimationCountingFire()
        let model = FireViewModel(fire: fire)
        model.setAnimationPlaying(true, isFireWindow: false)
        model.setSnapshotAnimationPlaying(true, isFireWindow: true)
        model.setAnimationPlaying(false, isFireWindow: false)
        XCTAssertTrue(model.isAnimationPlaying, "The Fire window snapshot is still playing")
        XCTAssertEqual(fire.finishes, 1)
        model.setSnapshotAnimationPlaying(false, isFireWindow: true)
        XCTAssertFalse(model.isAnimationPlaying)
        XCTAssertEqual(fire.starts, fire.finishes)
    }

    @MainActor
    func testSeveralClosingSnapshotsWaitForLastCompletion() {
        let fire = AnimationCountingFire()
        let model = FireViewModel(fire: fire)
        model.setSnapshotAnimationPlaying(true, isFireWindow: true)
        model.setSnapshotAnimationPlaying(true, isFireWindow: true)
        model.setSnapshotAnimationPlaying(false, isFireWindow: true)
        XCTAssertTrue(model.isAnimationPlaying)
        model.setSnapshotAnimationPlaying(false, isFireWindow: true)
        model.setSnapshotAnimationPlaying(false, isFireWindow: true)
        XCTAssertFalse(model.isAnimationPlaying)
        XCTAssertEqual(fire.starts, 0, "Closing private windows does not enter the data-clearing group")
        XCTAssertEqual(fire.finishes, 0)
    }

    @MainActor
    func testDataClearingSnapshotAndClosingSnapshotsFinishIndependently() {
        let fire = AnimationCountingFire()
        let model = FireViewModel(fire: fire)
        model.setSnapshotAnimationPlaying(true, isFireWindow: false)
        model.setSnapshotAnimationPlaying(true, isFireWindow: false)
        model.setSnapshotAnimationPlaying(true, isFireWindow: true)
        model.setSnapshotAnimationPlaying(false, isFireWindow: false)
        XCTAssertTrue(model.isAnimationPlaying)
        XCTAssertFalse(model.isDataClearingAnimationPlaying)
        XCTAssertEqual(fire.starts, 1)
        XCTAssertEqual(fire.finishes, 1)
        model.setSnapshotAnimationPlaying(false, isFireWindow: true)
        XCTAssertFalse(model.isAnimationPlaying)
    }

    @MainActor
    func testSnapshotPresentationCanOnlyBeClaimedOncePerBurn() {
        let fire = AnimationCountingFire()
        let model = FireViewModel(fire: fire)
        fire.burningData = .all
        XCTAssertTrue(model.claimSnapshotPresentation())
        XCTAssertFalse(model.claimSnapshotPresentation())
        fire.burningData = nil
        fire.burningData = .all
        XCTAssertTrue(model.claimSnapshotPresentation())
    }

    func testBundledFireHasCumulativeWipeEndingInAnEmptySnapshot() async throws {
        let loader = DefaultFireAnimationLoader()
        let loaded = await loader.load()
        let fire = try XCTUnwrap(loaded, "The bundled Lottie and its wipe must load successfully")
        XCTAssertEqual(DefaultFireAnimationLoader.assetName, "02_Fire_rebranded")
        XCTAssertGreaterThan(fire.burnFronts.count, 2)
        let width = try XCTUnwrap(fire.burnFronts.first?.count)
        XCTAssertGreaterThan(width, 1)
        XCTAssertTrue(try XCTUnwrap(fire.burnFronts.first).contains { $0 < 1 }, "Playback must start with unburned pixels")
        XCTAssertTrue(fire.burnFronts.dropLast().contains { $0.contains { $0 > 0 && $0 < 1 } }, "The asset must produce a partial wipe before completion")
        for (previous, next) in zip(fire.burnFronts, fire.burnFronts.dropFirst()) {
            XCTAssertEqual(next.count, width)
            XCTAssertTrue(zip(previous, next).allSatisfy { $0.0 <= $0.1 }, "Burned pixels must never reappear")
        }
        XCTAssertTrue(try XCTUnwrap(fire.burnFronts.last).allSatisfy { $0 == 1 }, "The final wipe removes the whole snapshot")
    }

    func testConcurrentAssetLoadsShareOnePreparedAnimation() async throws {
        let loader = DefaultFireAnimationLoader()
        async let firstLoad = loader.load()
        async let secondLoad = loader.load()
        let (firstResult, secondResult) = await (firstLoad, secondLoad)
        let first = try XCTUnwrap(firstResult)
        let second = try XCTUnwrap(secondResult)
        XCTAssertTrue(first.animation === second.animation)
        XCTAssertEqual(first.burnFronts, second.burnFronts)
        let cached = await loader.load()
        XCTAssertTrue(first.animation === cached?.animation)
    }

    @MainActor
    func testProgressMessageMatchesScopeAndDialogFlag() {
        let flagger = MockFeatureFlagger()
        for simplified in [false, true] {
            flagger.featuresStub[FeatureFlag.fireDialogSimplified.rawValue] = simplified
            for burn in [Fire.BurningData.all, .specificDomains([], closesTabs: true, scope: .allWindows)] {
                XCTAssertEqual(burn.deletingDataMessage(featureFlagger: flagger),
                               simplified ? UserText.fireDialogDeletingAllData : UserText.fireDialogDeletingData)
            }
            XCTAssertEqual(Fire.BurningData.specificDomains([], closesTabs: true, scope: .tab).deletingDataMessage(featureFlagger: flagger),
                           simplified ? UserText.fireDialogDeletingDataFromThisTab : UserText.fireDialogDeletingData)
            for scope: Fire.BurningScope in [.window, .visits, .none] {
                XCTAssertEqual(Fire.BurningData.specificDomains([], closesTabs: true, scope: scope).deletingDataMessage(featureFlagger: flagger),
                               UserText.fireDialogDeletingData)
            }
        }
    }
}

private final class AnimationCountingFire: FireProtocol {
    @Published var burningData: Fire.BurningData?
    let fireproofDomains: FireproofDomains = MockFireproofDomains()
    let visualizeFireAnimationDecider: VisualizeFireSettingsDecider = MockVisualizeFireAnimationDecider()
    var burningDataPublisher: AnyPublisher<Fire.BurningData?, Never> { $burningData.eraseToAnyPublisher() }
    private(set) var starts = 0
    private(set) var finishes = 0

    func fireAnimationDidStart() { starts += 1 }
    func fireAnimationDidFinish() { finishes += 1 }

    @MainActor
    func burnAll(isBurnOnExit: Bool, opening url: URL, includeCookiesAndSiteData: Bool, includeChatHistory: Bool,
                 isAutoClear: Bool, dataClearingWideEventService: DataClearingWideEventService?, completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected data clearing")
    }

    @MainActor
    func burnEntity(_ entity: Fire.BurningEntity, includingHistory: Bool, includeCookiesAndSiteData: Bool, includeChatHistory: Bool,
                    dataClearingWideEventService: DataClearingWideEventService?, completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected data clearing")
    }

    @MainActor
    func burnVisits(_ visits: [Visit], except fireproofDomains: DomainFireproofStatusProviding, isToday: Bool, closeWindows: Bool,
                    clearSiteData: Bool, clearChatHistory: Bool, urlToOpenIfWindowsAreClosed url: URL?,
                    dataClearingWideEventService: DataClearingWideEventService?, completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected data clearing")
    }

    @MainActor
    func burnChatHistory() async -> Result<Void, Error> {
        XCTFail("Unexpected data clearing")
        return .success(())
    }
}
