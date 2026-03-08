//
//  NTPAfterIdleInstrumentationTests.swift
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

import Foundation
import Testing
import Core
@testable import DuckDuckGo

@Suite("NTP After Idle Instrumentation")
struct NTPAfterIdleInstrumentationTests {

    private final class PixelCollector {
        var firedPixelNames: [String] = []
    }

    private func makeSUT(eligible: Bool = true) -> (DefaultNTPAfterIdleInstrumentation, PixelCollector) {
        let eligibility = MockIdleReturnEligibilityManager()
        eligibility.isEligibleForNTPAfterIdleResult = eligible
        let collector = PixelCollector()
        let sut = DefaultNTPAfterIdleInstrumentation(
            eligibilityManager: eligibility,
            firePixel: { collector.firedPixelNames.append($0.name) })
        return (sut, collector)
    }

    // MARK: - Eligibility gating

    @Test("When not eligible then ntpShown fires no pixel")
    func whenNotEligibleThenNtpShownFiresNothing() {
        let (sut, collector) = makeSUT(eligible: false)
        sut.ntpShown(afterIdle: true)
        sut.ntpShown(afterIdle: false)
        #expect(collector.firedPixelNames.isEmpty)
    }

    @Test("When not eligible then returnToPageTapped fires no pixel")
    func whenNotEligibleThenReturnToPageTappedFiresNothing() {
        let (sut, collector) = makeSUT(eligible: false)
        sut.returnToPageTapped(afterIdle: true)
        sut.returnToPageTapped(afterIdle: false)
        #expect(collector.firedPixelNames.isEmpty)
    }

    @Test("When not eligible then barUsedFromNTP fires no pixel")
    func whenNotEligibleThenBarUsedFiresNothing() {
        let (sut, collector) = makeSUT(eligible: false)
        sut.barUsedFromNTP(afterIdle: true)
        sut.barUsedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames.isEmpty)
    }

    @Test("When not eligible then toggleUsedFromNTP fires no pixel")
    func whenNotEligibleThenToggleUsedFiresNothing() {
        let (sut, collector) = makeSUT(eligible: false)
        sut.toggleUsedFromNTP(afterIdle: true)
        sut.toggleUsedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames.isEmpty)
    }

    @Test("When not eligible then backButtonUsedFromNTP fires no pixel")
    func whenNotEligibleThenBackButtonFiresNothing() {
        let (sut, collector) = makeSUT(eligible: false)
        sut.backButtonUsedFromNTP(afterIdle: true)
        sut.backButtonUsedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames.isEmpty)
    }

    @Test("When not eligible then appBackgroundedFromNTP fires no pixel")
    func whenNotEligibleThenAppBackgroundedFiresNothing() {
        let (sut, collector) = makeSUT(eligible: false)
        sut.appBackgroundedFromNTP(afterIdle: true)
        sut.appBackgroundedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames.isEmpty)
    }

    @Test("When not eligible then tabSwitcherSelectedFromNTP fires no pixel")
    func whenNotEligibleThenTabSwitcherFiresNothing() {
        let (sut, collector) = makeSUT(eligible: false)
        sut.tabSwitcherSelectedFromNTP(afterIdle: true)
        sut.tabSwitcherSelectedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames.isEmpty)
    }

    // MARK: - ntpShown

    @Test("When NTP shown after idle then fires after_idle pixel")
    func whenNtpShownAfterIdleThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.ntpShown(afterIdle: true)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleNTPShownAfterIdle.name])
    }

    @Test("When NTP shown user initiated then fires user_initiated pixel")
    func whenNtpShownUserInitiatedThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.ntpShown(afterIdle: false)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleNTPShownUserInitiated.name])
    }

    // MARK: - returnToPageTapped

    @Test("When return to page tapped after idle then fires after_idle pixel")
    func whenReturnToPageTappedAfterIdleThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.returnToPageTapped(afterIdle: true)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleReturnToPageTappedAfterIdle.name])
    }

    @Test("When return to page tapped user initiated then fires user_initiated pixel")
    func whenReturnToPageTappedUserInitiatedThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.returnToPageTapped(afterIdle: false)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleReturnToPageTappedUserInitiated.name])
    }

    // MARK: - barUsedFromNTP

    @Test("When bar used from NTP after idle then fires after_idle pixel")
    func whenBarUsedAfterIdleThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.barUsedFromNTP(afterIdle: true)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleBarUsedAfterIdle.name])
    }

    @Test("When bar used from NTP user initiated then fires user_initiated pixel")
    func whenBarUsedUserInitiatedThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.barUsedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleBarUsedUserInitiated.name])
    }

    // MARK: - toggleUsedFromNTP

    @Test("When toggle used from NTP after idle then fires after_idle pixel")
    func whenToggleUsedAfterIdleThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.toggleUsedFromNTP(afterIdle: true)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleToggleUsedAfterIdle.name])
    }

    @Test("When toggle used from NTP user initiated then fires user_initiated pixel")
    func whenToggleUsedUserInitiatedThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.toggleUsedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleToggleUsedUserInitiated.name])
    }

    // MARK: - backButtonUsedFromNTP

    @Test("When back button used from NTP after idle then fires after_idle pixel")
    func whenBackButtonAfterIdleThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.backButtonUsedFromNTP(afterIdle: true)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleBackButtonUsedAfterIdle.name])
    }

    @Test("When back button used from NTP user initiated then fires user_initiated pixel")
    func whenBackButtonUserInitiatedThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.backButtonUsedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleBackButtonUsedUserInitiated.name])
    }

    // MARK: - appBackgroundedFromNTP

    @Test("When app backgrounded from NTP after idle then fires after_idle pixel")
    func whenAppBackgroundedAfterIdleThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.appBackgroundedFromNTP(afterIdle: true)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleAppBackgroundedAfterIdle.name])
    }

    @Test("When app backgrounded from NTP user initiated then fires user_initiated pixel")
    func whenAppBackgroundedUserInitiatedThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.appBackgroundedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleAppBackgroundedUserInitiated.name])
    }

    // MARK: - tabSwitcherSelectedFromNTP

    @Test("When tab switcher selected from NTP after idle then fires after_idle pixel")
    func whenTabSwitcherAfterIdleThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.tabSwitcherSelectedFromNTP(afterIdle: true)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleTabSwitcherSelectedAfterIdle.name])
    }

    @Test("When tab switcher selected from NTP user initiated then fires user_initiated pixel")
    func whenTabSwitcherUserInitiatedThenFiresCorrectPixel() {
        let (sut, collector) = makeSUT()
        sut.tabSwitcherSelectedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames == [Pixel.Event.ntpAfterIdleTabSwitcherSelectedUserInitiated.name])
    }

    // MARK: - Multiple calls accumulate

    @Test("When multiple methods called then all pixels are recorded")
    func whenMultipleMethodsCalledThenAllPixelsRecorded() {
        let (sut, collector) = makeSUT()
        sut.ntpShown(afterIdle: true)
        sut.barUsedFromNTP(afterIdle: true)
        sut.toggleUsedFromNTP(afterIdle: false)
        #expect(collector.firedPixelNames.count == 3)
        #expect(collector.firedPixelNames[0] == Pixel.Event.ntpAfterIdleNTPShownAfterIdle.name)
        #expect(collector.firedPixelNames[1] == Pixel.Event.ntpAfterIdleBarUsedAfterIdle.name)
        #expect(collector.firedPixelNames[2] == Pixel.Event.ntpAfterIdleToggleUsedUserInitiated.name)
    }
}
