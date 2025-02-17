//
//  AppStateMachineTests.swift
//  DuckDuckGo
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

import UIKit
import Testing
@testable import DuckDuckGo

@MainActor
final class MockInitializing: InitializingHandling {

    required init() {}

    func makeLaunchingState() -> any LaunchingHandling {
        MockLaunching()
    }

}

@MainActor
final class MockLaunching: LaunchingHandling {

    required init() {}

    func makeBackgroundState() -> any BackgroundHandling {
        MockBackground()
    }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        MockForeground(actionToHandle: actionToHandle)
    }

    func makeTerminatingState(terminationReason: UIApplication.TerminationReason) -> any TerminatingHandling {
        MockTerminating(terminationReason: terminationReason, application: UIApplication.shared)
    }

}

@MainActor
final class MockForeground: ForegroundHandling {

    private(set) var eventLog: [String] = []
    var actionToHandle: AppAction?

    var onTransitionCalled: Bool { eventLog.contains("onTransition") }
    var willLeaveCalled: Bool { eventLog.contains("willLeave") }
    var didReturnCalled: Bool { eventLog.contains("didReturn") }
    var handleActionCalled: Bool { eventLog.contains("handleAction") }

    func onTransition() { eventLog.append("onTransition") }
    func willLeave() { eventLog.append("willLeave") }
    func didReturn() { eventLog.append("didReturn") }
    func handle(_ action: AppAction) { eventLog.append("handleAction") }

    init(actionToHandle: AppAction?) {
        self.actionToHandle = actionToHandle
    }

    func makeBackgroundState() -> any BackgroundHandling {
        MockBackground()
    }

    func makeTerminatingState(terminationReason: UIApplication.TerminationReason) -> any TerminatingHandling {
        MockTerminating(terminationReason: terminationReason, application: UIApplication.shared)
    }

}

@MainActor
final class MockBackground: BackgroundHandling {

    private(set) var eventLog: [String] = []

    var onTransitionCalled: Bool { eventLog.contains("onTransition") }
    var willLeaveCalled: Bool { eventLog.contains("willLeave") }
    var didReturnCalled: Bool { eventLog.contains("didReturn") }

    func onTransition() { eventLog.append("onTransition") }
    func willLeave() { eventLog.append("willLeave") }
    func didReturn() { eventLog.append("didReturn") }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        MockForeground(actionToHandle: actionToHandle)
    }

    func makeTerminatingState() -> any TerminatingHandling {
        MockTerminating()
    }

}

@MainActor
final class MockTerminating: TerminatingHandling {

    init() {}
    init(terminationReason: UIApplication.TerminationReason, application: UIApplication) {}

}

@MainActor
@Suite("AppStateMachine transition tests", .serialized)
final class AppStateMachineTests {

    let stateMachine = AppStateMachine(initialState: .initializing(MockInitializing()))

    @Test("Initial state should be Initializing")
    func testInitialState() {
        #expect(stateMachine.currentState.rawValue == "initializing")
    }

    // MARK: - Launching

    @Test("Transition from Initializing to Launching")
    func testTransitionFromInitializingToLaunching() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.rawValue == "launching")
    }

    @Test("Transition from Launching to Foreground")
    func testTransitionFromLaunchingToForeground() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.rawValue == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.eventLog == ["onTransition", "didReturn"])
            #expect(mockForeground.actionToHandle == nil)
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("Transition from Launching to Foreground with launch action")
    func testTransitionFromLaunchingToForegroundWithLaunchAction() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.openURL(URL("www.duckduckgo.com")!))
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.actionToHandle == nil)
        #expect(stateMachine.currentState.rawValue == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.eventLog == ["onTransition", "didReturn"])
            #expect(mockForeground.actionToHandle != nil)
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("Transition from Launching to Background")
    func testTransitionFromLaunchingToBackground() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.didEnterBackground)
        #expect(stateMachine.currentState.rawValue == "background")

        if case .background(let background) = stateMachine.currentState,
           let mockBackground = background as? MockBackground {
            #expect(mockBackground.eventLog == ["onTransition", "didReturn"])
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("Transition from Launching to Terminating")
    func testTransitionFromLaunchingToTerminating() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.willTerminate(.insufficientDiskSpace))
        #expect(stateMachine.currentState.rawValue == "terminating")
    }

    @Test("Incorrect transitions from Launching")
    func testIncorrectTransitionsFromLaunching() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.rawValue == "launching")

        stateMachine.handle(.willEnterForeground)
        #expect(stateMachine.currentState.rawValue == "launching")

        stateMachine.handle(.willResignActive)
        #expect(stateMachine.currentState.rawValue == "launching")
    }

    // MARK: - Foreground



}
