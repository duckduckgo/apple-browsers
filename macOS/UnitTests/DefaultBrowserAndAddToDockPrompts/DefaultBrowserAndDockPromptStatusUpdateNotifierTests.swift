//
//  DefaultBrowserAndDockPromptStatusUpdateNotifierTests.swift
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

import Testing
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptStatusUpdateNotifierTests {
    private var defaultBrowserProviderMock: DefaultBrowserProviderMock!
    private var dockCustomizerMock: DockCustomizerMock!
    private var timerFactoryMock: MockTimerFactory!
    private var cancellables: Set<AnyCancellable>

    init() {
        defaultBrowserProviderMock = DefaultBrowserProviderMock()
        dockCustomizerMock = DockCustomizerMock()
        timerFactoryMock = MockTimerFactory()
        cancellables = []
    }

    @Test("Check Timer Is Created When Start Notifying")
    func whenStartNotifyingThenPublishStatusInfo() throws {
        // GIVEN
        var numberOfEvents = 0
        var capturedStatusInfo: DefaultBrowserAndDockPromptStatusInfo?
        let sut = DefaultBrowserAndDockPromptStatusUpdateNotifier(
            dockCustomizer: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            timerFactory: timerFactoryMock
        )
        sut.statusPublisher
            .sink { info in
                capturedStatusInfo = info
                numberOfEvents += 1
            }
            .store(in: &cancellables)
        dockCustomizerMock.dockStatus = true
        defaultBrowserProviderMock.isDefault = true

        // WHEN
        sut.startNotifyingStatus(interval: 1.0)

        let timer = try #require(timerFactoryMock.createdTimer)
        timer.fire()

        // THEN
        #expect(capturedStatusInfo?.isDefaultBrowser == true)
        #expect(capturedStatusInfo?.isAddedToDock == true)
        #expect(numberOfEvents == 1)
        #expect(timer.timeInterval == 1.0)
    }

    @Test("Check Timer Is Invalidated When Stop Notifying")
    func whenStopNotifyingThenInvalidateTimer() throws {
        // GIVEN
        var numberOfEvents = 0
        var capturedStatusInfo: DefaultBrowserAndDockPromptStatusInfo?
        let sut = DefaultBrowserAndDockPromptStatusUpdateNotifier(
            dockCustomizer: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            timerFactory: timerFactoryMock
        )
        sut.statusPublisher
            .sink { info in
                capturedStatusInfo = info
                numberOfEvents += 1
            }
            .store(in: &cancellables)
        dockCustomizerMock.dockStatus = true
        defaultBrowserProviderMock.isDefault = true

        // WHEN
        sut.startNotifyingStatus(interval: 1.0)

        let timerMock = try #require(timerFactoryMock.createdTimer)
        timerMock.fire()
        sut.stopNotifyingStatus()

        // THEN
        #expect(capturedStatusInfo?.isDefaultBrowser == true)
        #expect(capturedStatusInfo?.isAddedToDock == true)
        #expect(timerMock.didCallInvalidate)
    }

    @Test("Check Duplicate Values Are Not Received")
    func whenStopNotifyingThenPublishStatusInfo() throws {

        // Multiple repeated #expect macros slow down the type checking and Xcode throws a warning.
        func assert(isAddedToDock: Bool, isDefaultBrowser: Bool, numberOfEventsReceived: Int) {
            #expect(capturedStatusInfo?.isAddedToDock == isAddedToDock)
            #expect(capturedStatusInfo?.isDefaultBrowser == isDefaultBrowser)
            #expect(numberOfEvents == numberOfEventsReceived)
        }

        // GIVEN
        var numberOfEvents = 0
        var capturedStatusInfo: DefaultBrowserAndDockPromptStatusInfo?
        let sut = DefaultBrowserAndDockPromptStatusUpdateNotifier(
            dockCustomizer: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            timerFactory: timerFactoryMock
        )
        sut.statusPublisher
            .sink { info in
                capturedStatusInfo = info
                numberOfEvents += 1
            }
            .store(in: &cancellables)

        dockCustomizerMock.dockStatus = false
        defaultBrowserProviderMock.isDefault = true

        // WHEN
        sut.startNotifyingStatus(interval: 1.0)
        let timerMock = try #require(timerFactoryMock.createdTimer)
        timerMock.fire()
        timerMock.fire()
        timerMock.fire()

        // THEN
        assert(isAddedToDock: false, isDefaultBrowser: true, numberOfEventsReceived: 1)

        // WHEN
        dockCustomizerMock.dockStatus = true
        timerMock.fire()

        // THEN
        assert(isAddedToDock: true, isDefaultBrowser: true, numberOfEventsReceived: 2)
    }
}
