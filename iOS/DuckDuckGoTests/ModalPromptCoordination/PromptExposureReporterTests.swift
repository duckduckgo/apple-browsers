//
//  PromptExposureReporterTests.swift
//  DuckDuckGoTests
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

import Foundation
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Prompt exposure reporter")
struct PromptExposureReporterTests {
    @MainActor
    private final class Context {
        let store = InMemoryThrowingKeyValueStore()
        let pixel = PixelKitMock()
        let installedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var installDate: Date?
        var now: Date
        var onboardingCompleted = true
        var backgroundDate: Date?
        var randomValue = 0.0
        var randomCalls = 0

        init() {
            installDate = installedAt
            now = installedAt
        }

        var storage: any ThrowingKeyedStoring<PromptExposureKeys> { store.throwingKeyedStoring() }
        var state: PromptExposureState? { get throws { try storage.value(for: \.state) } }
        var sessions: [ExpectedFireCall] { pixel.actualFireCalls.filter { $0.pixel.name == "prompt_session" } }
        var userWeeks: [ExpectedFireCall] { pixel.actualFireCalls.filter { $0.pixel.name == "prompt_user_week" } }

        func makeReporter() -> PromptExposureReporter {
            PromptExposureReporter(storage: storage, pixel: pixel, dateProvider: { self.now },
                                   installDateProvider: { self.installDate },
                                   onboardingCompletedProvider: { self.onboardingCompleted },
                                   lastBackgroundDateProvider: { self.backgroundDate },
                                   randomSource: {
                self.randomCalls += 1
                return self.randomValue
            })
        }

        func advance(days: Double) { now = installedAt.addingTimeInterval(days * 86_400) }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func ordinalsShareTheWeekAndRestartAfterRollover() throws {
        let context = Context()
        let reporter = context.makeReporter()
        context.advance(days: 7)
        reporter.reportPromptShown(.appRatingPrompt)
        reporter.reportPromptShown(.importPasswordsGoogle)
        context.advance(days: 14)
        reporter.reportPromptShown(.appRatingPrompt)

        #expect(context.pixel.actualFireCalls == [
            ExpectedFireCall(pixel: PromptExposurePixel.exposure(daysSinceInstall: "d7_13", nthInWeek: "1"), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.shown(daysSinceInstall: "d7_13", promptID: .appRatingPrompt), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.exposure(daysSinceInstall: "d7_13", nthInWeek: "2"), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.shown(daysSinceInstall: "d7_13", promptID: .importPasswordsGoogle), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.exposure(daysSinceInstall: "d14_20", nthInWeek: "1"), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.shown(daysSinceInstall: "d14_20", promptID: .appRatingPrompt), frequency: .standard)
        ])
        #expect(try context.state?.weekIndex == 2)
        #expect(try context.state?.nthInWeek == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func cardDeduplicationSurvivesReinitializationAndResetsAfterSkippedWeeks() throws {
        let context = Context()
        context.advance(days: 6.99)
        context.makeReporter().reportRemoteMessageCardShown(messageID: "card-a")
        context.makeReporter().reportRemoteMessageCardShown(messageID: "card-a")
        #expect(context.pixel.actualFireCalls.count == 2)
        #expect(try context.state?.reportedRemoteMessageIDs == ["card-a"])

        context.advance(days: 21)
        context.makeReporter().reportRemoteMessageCardShown(messageID: "card-a")
        #expect(context.pixel.actualFireCalls.count == 4)
        #expect(try context.state?.weekIndex == 3)
        #expect(try context.state?.nthInWeek == 1)
        context.makeReporter().reportRemoteMessageCardShown(messageID: "card-b")
        #expect(try context.state?.nthInWeek == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func clockMovingBackKeepsCountsDeduplicationAndUserWeek() throws {
        let context = Context()
        context.advance(days: 14)
        let reporter = context.makeReporter()
        reporter.appDidEnterForeground()
        reporter.reportRemoteMessageCardShown(messageID: "card")
        context.advance(days: 7)
        reporter.appDidEnterForeground()
        reporter.reportRemoteMessageCardShown(messageID: "card")
        reporter.reportPromptShown(.appRatingPrompt)

        #expect(try context.state?.weekIndex == 2)
        #expect(try context.state?.nthInWeek == 2)
        #expect(context.userWeeks.count == 1)
        #expect(context.pixel.actualFireCalls.count == 5)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unknownInstallDateDoesNotRecordOrFireAnything() throws {
        let context = Context()
        context.installDate = nil
        context.backgroundDate = context.now.addingTimeInterval(-60)
        let reporter = context.makeReporter()
        reporter.reportPromptShown(.appRatingPrompt)
        reporter.reportRemoteMessageCardShown(messageID: "card")
        reporter.recordCoordinatedPromptFinished(.modal)
        reporter.appDidEnterForeground()

        #expect(context.store.underlyingDict.isEmpty)
        #expect(context.pixel.actualFireCalls.isEmpty)
        #expect(context.randomCalls == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func exposuresAreNotGatedOnOnboarding() throws {
        let context = Context()
        context.onboardingCompleted = false
        let reporter = context.makeReporter()
        reporter.reportPromptShown(.appRatingPrompt)
        reporter.reportRemoteMessageCardShown(messageID: "card")
        #expect(context.pixel.actualFireCalls.map(\.pixel.name) == ["prompt_exposure", "prompt_shown", "prompt_exposure", "prompt_shown"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func userWeekWaitsForOnboardingAndFiresOncePerWeekAcrossLaunches() throws {
        let context = Context()
        context.onboardingCompleted = false
        context.makeReporter().appDidEnterForeground()
        #expect(context.userWeeks.isEmpty)
        context.onboardingCompleted = true
        context.makeReporter().appDidEnterForeground()
        context.makeReporter().appDidEnterForeground()
        context.advance(days: 7)
        context.makeReporter().appDidEnterForeground()
        #expect(context.userWeeks == [
            ExpectedFireCall(pixel: PromptExposurePixel.userWeek(daysSinceInstall: "d0_6"), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.userWeek(daysSinceInstall: "d7_13"), frequency: .standard)
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [59.0, 60, 61], [false, true])
    func sessionEndsAtSixtySecondsAndConsumesEachBackgroundOnce(timeAway: Double, promptShown: Bool) throws {
        let context = Context()
        let reporter = context.makeReporter()
        if promptShown { reporter.reportPromptShown(.appRatingPrompt) }
        context.backgroundDate = context.now
        context.now.addTimeInterval(timeAway)
        reporter.appDidEnterForeground()
        #expect(context.sessions.count == (timeAway >= 60 ? 1 : 0))
        #expect(try context.state?.sessionPromptShown == (timeAway < 60 && promptShown))
        if timeAway >= 60 {
            #expect(context.sessions.first?.pixel.parameters?["prompt_shown"] == String(promptShown))
        }

        context.now.addTimeInterval(120)
        context.makeReporter().appDidEnterForeground()
        #expect(context.sessions.count == (timeAway >= 60 ? 1 : 0))
        #expect(context.randomCalls == (timeAway >= 60 ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [0.049, 0.05, 0.99], [false, true])
    func endedSessionResetsEvenWhenSampledOutOrOnboardingIncomplete(randomValue: Double, onboardingComplete: Bool) throws {
        let context = Context()
        context.randomValue = randomValue
        context.onboardingCompleted = onboardingComplete
        let reporter = context.makeReporter()
        reporter.reportPromptShown(.appRatingPrompt)
        context.backgroundDate = context.now
        context.now.addTimeInterval(60)
        reporter.appDidEnterForeground()
        #expect(try context.state?.sessionPromptShown == false)
        #expect(context.sessions.count == (randomValue < 0.05 && onboardingComplete ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func coldLaunchReportsPreviousSessionInItsBackgroundWeekBeforeCurrentUserWeek() throws {
        let context = Context()
        context.advance(days: 6.99)
        context.makeReporter().reportPromptShown(.appRatingPrompt)
        context.backgroundDate = context.now
        context.advance(days: 8)
        context.makeReporter().appDidEnterForeground()
        #expect(Array(context.pixel.actualFireCalls.suffix(2)) == [
            ExpectedFireCall(pixel: PromptExposurePixel.session(daysSinceInstall: "d0_6", promptShown: true), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.userWeek(daysSinceInstall: "d7_13"), frequency: .standard)
        ])
        #expect(try context.state?.sessionPromptShown == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func reportBeforeForegroundEndsThePreviousSessionFirst() throws {
        let context = Context()
        context.backgroundDate = context.now
        context.now.addTimeInterval(60)
        let reporter = context.makeReporter()
        reporter.reportRemoteMessageCardShown(messageID: "card")
        reporter.appDidEnterForeground()
        #expect(context.pixel.actualFireCalls.first?.pixel.name == "prompt_session")
        #expect(context.sessions.map { $0.pixel.parameters?["prompt_shown"] } == ["false"])
        #expect(try context.state?.sessionPromptShown == true)

        context.backgroundDate = context.now
        context.now.addTimeInterval(60)
        reporter.appDidEnterForeground()
        #expect(context.sessions.map { $0.pixel.parameters?["prompt_shown"] } == ["false", "true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func reportShortlyAfterBackgroundingDoesNotHideTheTimeAway() throws {
        let context = Context()
        let reporter = context.makeReporter()
        context.backgroundDate = context.now
        context.now.addTimeInterval(1)
        reporter.reportPromptShown(.appRatingPrompt)
        context.now.addTimeInterval(120)
        reporter.appDidEnterForeground()
        #expect(context.sessions.map { $0.pixel.parameters?["prompt_shown"] } == ["true"])
        #expect(try context.state?.sessionPromptShown == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func duplicateCardDoesNotMarkANewSessionAsPrompted() throws {
        let context = Context()
        let reporter = context.makeReporter()
        reporter.reportRemoteMessageCardShown(messageID: "card")
        context.backgroundDate = context.now
        context.now.addTimeInterval(60)
        reporter.appDidEnterForeground()
        reporter.reportRemoteMessageCardShown(messageID: "card")
        #expect(try context.state?.sessionPromptShown == false)
        context.backgroundDate = context.now
        context.now.addTimeInterval(60)
        reporter.appDidEnterForeground()
        #expect(context.sessions.map { $0.pixel.parameters?["prompt_shown"] } == ["true", "false"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func gapUsesFinishTimeAndRestampsAfterClockMovesBack() throws {
        let context = Context()
        let reporter = context.makeReporter()
        reporter.recordCoordinatedPromptFinished(.modal)
        context.now.addTimeInterval(60)
        reporter.recordCoordinatedPromptFinished(.ntpCard)
        context.now.addTimeInterval(-30)
        reporter.recordCoordinatedPromptFinished(.modal)
        #expect(try context.state?.lastCoordinatedPromptFinishedAt == context.now)
        context.now.addTimeInterval(30)
        reporter.recordCoordinatedPromptFinished(.modal)
        #expect(context.pixel.actualFireCalls == [
            ExpectedFireCall(pixel: PromptExposurePixel.gap(daysSinceInstall: "d0_6", gapBucket: "first", promptType: .modal), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.gap(daysSinceInstall: "d0_6", gapBucket: "1_5m", promptType: .ntpCard), frequency: .standard),
            ExpectedFireCall(pixel: PromptExposurePixel.gap(daysSinceInstall: "d0_6", gapBucket: "lt_1m", promptType: .modal), frequency: .standard)
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func storageFailureDoesNotFireOrLoseTheFirstCardExposure(readFailure: Bool) throws {
        let context = Context()
        context.store.shouldThrowOnGet = readFailure
        context.store.shouldThrowOnSet = !readFailure
        let reporter = context.makeReporter()
        reporter.reportRemoteMessageCardShown(messageID: "card")
        #expect(context.pixel.actualFireCalls.isEmpty)
        context.store.shouldThrowOnGet = false
        context.store.shouldThrowOnSet = false
        #expect(try context.state == nil)
        reporter.reportRemoteMessageCardShown(messageID: "card")
        #expect(context.pixel.actualFireCalls.count == 2)
        #expect(try context.state?.nthInWeek == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func undecodableStateStartsFreshAndReportingContinues() throws {
        let context = Context()
        try context.store.set(Data("{}".utf8), forKey: "prompt-exposure-state")
        let reporter = context.makeReporter()
        reporter.reportPromptShown(.appRatingPrompt)
        reporter.reportPromptShown(.appRatingPrompt)
        #expect(context.pixel.actualFireCalls.count == 4)
        #expect(try context.state?.nthInWeek == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func resetClearsOnlyExposureState() throws {
        let context = Context()
        try context.store.set("kept", forKey: "unrelated-key")
        let reporter = context.makeReporter()
        reporter.reportRemoteMessageCardShown(messageID: "card")
        reporter.reset()
        #expect(try context.state == nil)
        #expect(try context.store.object(forKey: "unrelated-key") as? String == "kept")
        reporter.reportRemoteMessageCardShown(messageID: "card")
        #expect(try context.state?.nthInWeek == 1)
    }
}
