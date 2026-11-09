//
//  SparkleUpdateControllerPromptStageTests.swift
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
import FeatureFlags_macOS
import Foundation
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
import Sparkle
import Testing
@_spi(Testing) import WideEvent

@testable import SparkleAppUpdater

@MainActor
@Suite("SparkleUpdateController prompt stages")
final class SparkleUpdateControllerPromptStageTests {

    private let featureFlagger = MockFeatureFlagger()
    private let notificationPresenter = MockNotificationPresenter()
    private let store = InMemoryThrowingKeyValueStore()
    private let item = SUAppcastItem.empty()
    private let wideEvent = WideEventMock()

    init() {
        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = true
    }

    private func makeController() -> SparkleUpdateController {
        SparkleUpdateController(internalUserDecider: MockInternalUserDecider(isInternalUser: false),
                                featureFlagger: featureFlagger,
                                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                manualUpdateRemovalHandler: ManualUpdateRemovalHandler(settings: store.throwingKeyedStoring(), featureFlagger: featureFlagger),
                                pixelFiring: nil,
                                notificationPresenter: notificationPresenter,
                                keyValueStore: store,
                                applicationUpdateDetector: ApplicationUpdateDetector(settings: store.throwingKeyedStoring()),
                                allowCustomUpdateFeed: false,
                                isAutoUpdatePaused: { true },
                                wideEvent: wideEvent,
                                isOnboardingFinished: { true })
    }

    private func updater(for controller: SparkleUpdateController) -> SPUUpdater {
        SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: controller.userDriver, delegate: nil)
    }

    private func findUpdate(_ controller: SparkleUpdateController) {
        controller.updater(updater(for: controller), didFindValidUpdate: item)
    }

    private func findNoUpdate(_ controller: SparkleUpdateController, latestItem: SUAppcastItem?) {
        let userInfo: [String: Any] = latestItem.map { [SPULatestAppcastItemFoundKey: $0] } ?? [:]
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue), userInfo: userInfo)
        controller.updaterDidNotFindUpdate(updater(for: controller), error: error)
    }

    private func finishDownload(_ controller: SparkleUpdateController) {
        _ = controller.updater(updater(for: controller), willInstallUpdateOnQuit: item, immediateInstallationBlock: {})
    }

    private func startInstalling(_ controller: SparkleUpdateController) {
        controller.updater(updater(for: controller), willExtractUpdate: item)
    }

    private func failUpdate(_ controller: SparkleUpdateController) {
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationError.rawValue))
        controller.updater(updater(for: controller), didFinishUpdateCycleFor: .updates, error: error)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Finding an update starts the prompt clock, and a check that finds none clears it, with or without a latest appcast item", .timeLimit(.minutes(1)), arguments: [true, false])
    func checkResultsDriveThePromptClock(hasLatestItem: Bool) throws {
        let controller = makeController()
        let tracker = try #require(controller.updatePromptStageTracker)

        findUpdate(controller)
        #expect(tracker.stage == .available)
        #expect(tracker.clockStartDate != nil)

        findNoUpdate(controller, latestItem: hasLatestItem ? item : nil)
        #expect(tracker.stage == .none)
        #expect(tracker.clockStartDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The prompt clock survives a relaunch", .timeLimit(.minutes(1)))
    func promptClockSurvivesRelaunch() throws {
        let firstLaunch = makeController()
        findUpdate(firstLaunch)
        let clockStartDate = try #require(firstLaunch.updatePromptStageTracker?.clockStartDate)

        let relaunchedTracker = try #require(makeController().updatePromptStageTracker)

        #expect(relaunchedTracker.clockStartDate == clockStartDate)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Changing the flag re-evaluates the prompt stage without waiting for the next check", .timeLimit(.minutes(1)))
    func flagChangesReevaluateThePromptStage() throws {
        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = false
        let controller = makeController()
        let tracker = try #require(controller.updatePromptStageTracker)
        findUpdate(controller)
        #expect(tracker.stage == .none)
        #expect(tracker.clockStartDate == nil)

        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = true
        featureFlagger.triggerUpdate()
        #expect(tracker.stage == .available)
        #expect(tracker.clockStartDate != nil)

        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = false
        featureFlagger.triggerUpdate()
        #expect(tracker.stage == .none)
        #expect(tracker.clockStartDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off while an update waits for its first prompt starts the notification delay", .timeLimit(.minutes(1)))
    func flagOffStartsNotificationDelay() {
        let controller = makeController()
        findUpdate(controller)
        finishDownload(controller)
        #expect(controller.pendingNotificationTask == nil)

        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = false
        featureFlagger.triggerUpdate()

        #expect(controller.pendingNotificationTask != nil)
        #expect(!controller.needsNotificationDot)
        #expect(!controller.mustShowUpdateIndicators, "the menu item waits for the delay too")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off after the first prompt keeps the indicators without scheduling them again", .timeLimit(.minutes(1)))
    func flagOffKeepsShownIndicators() throws {
        let controller = makeController()
        findUpdate(controller)
        finishDownload(controller)
        try #require(controller.updatePromptStageTracker).moveClock(to: .firstPrompt)
        #expect(controller.mustShowUpdateIndicators)

        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = false
        featureFlagger.triggerUpdate()

        #expect(controller.mustShowUpdateIndicators)
        #expect(controller.needsNotificationDot)
        #expect(controller.pendingNotificationTask == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag on cancels the notification delay until the first prompt", .timeLimit(.minutes(1)))
    func flagOnCancelsNotificationDelay() {
        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = false
        let controller = makeController()
        findUpdate(controller)
        finishDownload(controller)
        #expect(controller.pendingNotificationTask != nil)

        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = true
        featureFlagger.triggerUpdate()

        #expect(controller.pendingNotificationTask == nil)
        #expect(!controller.needsNotificationDot)
        #expect(controller.mustShowUpdateIndicators)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A downloaded update shows the menu item from day 0 and the dot only at the first prompt, with no popover", .timeLimit(.minutes(1)))
    func indicatorsFollowThePromptStage() throws {
        let controller = makeController()
        let tracker = try #require(controller.updatePromptStageTracker)
        var shownStages: [UpdatePromptStage] = []
        let cancellable = controller.pendingUpdatePromptStagePublisher.sink { shownStages.append($0) }
        findUpdate(controller)

        tracker.moveClock(to: .firstPrompt)
        #expect(!controller.mustShowUpdateIndicators, "waits for the download")
        #expect(!controller.needsNotificationDot, "waits for the download")
        #expect(controller.pendingUpdatePromptStage == .none, "waits for the download")

        tracker.resetClock()
        finishDownload(controller)
        #expect(controller.mustShowUpdateIndicators)
        #expect(!controller.needsNotificationDot)
        #expect(controller.pendingUpdatePromptStage == .available)

        tracker.moveClock(to: .firstPrompt)
        #expect(controller.needsNotificationDot)
        #expect(controller.pendingUpdatePromptStage == .firstPrompt)

        tracker.moveClock(to: .secondPrompt)
        #expect(!controller.needsNotificationDot, "the toolbar button takes over from the dot")
        #expect(controller.mustShowUpdateIndicators)
        #expect(controller.pendingUpdatePromptStage == .secondPrompt)

        #expect(shownStages == [.none, .available, .firstPrompt, .secondPrompt])
        #expect(notificationPresenter.shownUpdateTypes.isEmpty)
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Manual updates follow the prompt stages too, with no popover", .timeLimit(.minutes(1)))
    func manualUpdatesFollowThePromptStage() throws {
        let controller = makeController()
        controller.areAutomaticUpdatesEnabled = false
        findUpdate(controller)
        finishDownload(controller)

        try #require(controller.updatePromptStageTracker).moveClock(to: .firstPrompt)

        #expect(controller.needsNotificationDot)
        #expect(notificationPresenter.shownUpdateTypes.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The prompts hide while the update runs and come back if it fails, until a check finds the app up to date", .timeLimit(.minutes(1)))
    func promptsComeBackAfterAFailure() throws {
        let controller = makeController()
        findUpdate(controller)
        finishDownload(controller)
        try #require(controller.updatePromptStageTracker).moveClock(to: .secondPrompt)

        startInstalling(controller)
        #expect(controller.pendingUpdatePromptStage == .none)

        failUpdate(controller)
        #expect(controller.pendingUpdatePromptStage == .secondPrompt)

        findNoUpdate(controller, latestItem: item)
        #expect(controller.pendingUpdatePromptStage == .none)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Updating from a prompt after a failure starts a new update", .timeLimit(.minutes(1)))
    func updatingAfterFailureRetries() throws {
        let controller = makeController()
        findUpdate(controller)
        finishDownload(controller)
        startInstalling(controller)
        failUpdate(controller)
        wideEvent.started.removeAll()

        controller.runUpdate()

        let flow = try #require(wideEvent.started.last as? UpdateWideEventData)
        #expect(flow.initiationType == .manual)
    }
}
