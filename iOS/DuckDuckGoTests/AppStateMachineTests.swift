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

    var shouldThrowOnLaunching = false

    init() {}

    func makeLaunchingState() throws -> any LaunchingHandling {
        if shouldThrowOnLaunching {
            let underlying = NSError(domain: "com.example", code: 13, userInfo: nil)

            let diskFullError = NSError(
                domain: "com.example.wrapper",
                code: 1,
                userInfo: [NSUnderlyingErrorKey: underlying]
            )
            throw TerminationError.database(.other(diskFullError))
        } else {
            MockLaunching()
        }
    }

}

@MainActor
final class MockLaunching: LaunchingHandling {

    init() { }

    func makeBackgroundState() -> any BackgroundHandling {
        MockBackground()
    }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        MockForeground(actionToHandle: actionToHandle)
    }

    func makeConnectedState(window: UIWindow, actionToHandle: AppAction?) -> any ConnectedHandling {
        MockConnected(actionToHandle: actionToHandle, window: window)
    }

}

struct TestDependencies { }

@MainActor
final class MockConnected: ConnectedHandling {
    typealias Dependencies = TestDependencies

    var actionToHandle: AppAction?
    var window: UIWindow

    init(actionToHandle: AppAction?, window: UIWindow) {
        self.actionToHandle = actionToHandle
        self.window = window
    }

    func makeBackgroundState() -> any BackgroundHandling {
        MockBackground()
    }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        MockForeground(actionToHandle: actionToHandle)
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

    func makeConnectedState(window: UIWindow, actionToHandle: AppAction?) -> any ConnectedHandling {
        MockConnected(actionToHandle: actionToHandle, window: window)
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

    func makeConnectedState(window: UIWindow, actionToHandle: AppAction?) -> any ConnectedHandling {
        MockConnected(actionToHandle: actionToHandle, window: window)
    }

}

@MainActor
final class MockTerminating: TerminatingHandling {

    let error: Error
    var alertAndTerminateCalled: Bool = false

    init(error: Error) {
        self.error = error
    }
    
    func alertAndTerminate(window: UIWindow) {
        alertAndTerminateCalled = true
    }

}

@MainActor
final class MockTerminatingStateFactory: TerminatingStateFactory {

    func makeTerminatingState(error: Error) -> any TerminatingHandling {
        MockTerminating(error: error)
    }

}

@MainActor
@Suite("AppStateMachine launching origin transition tests", .serialized)
final class LaunchingTests {

    let stateMachine = AppStateMachine(initialState: .initializing(MockInitializing()), terminatingStateFactory: MockTerminatingStateFactory())

    @Test("didFinishLaunching should transition from Initializing to Launching")
    func transitionFromInitializingToLaunching() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.name == "launching")
    }

    @Test("willConnectTo should transition from Launching to Connected")
    func transitionFromLaunchingToConnected() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.willConnectToWindow(window: UIWindow()))
        #expect(stateMachine.currentState.name == "connected")
    }

    @Test("handle(_:) if current state is Launching should pass that action to Foreground and actionToHandle should be consumed afterwards")
    func handleAppAction() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.openURL(URL("www.duckduckgo.com")!))
        #expect(stateMachine.actionToHandle != nil)
        stateMachine.handle(.willConnectToWindow(window: UIWindow()))
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.actionToHandle == nil)

        #expect(stateMachine.currentState.name == "foreground")
        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.actionToHandle != nil)
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("willTerminate(with:) should transition from Launching to Terminating")
    func transitionFromLaunchingToTerminating() {
        if case .initializing(let initializing) = stateMachine.currentState,
           let mockInitializing = initializing as? MockInitializing {
            mockInitializing.shouldThrowOnLaunching = true
        }
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.name == "terminating")

        if case .terminating(let terminating) = stateMachine.currentState,
           let mockTerminating = terminating as? MockTerminating {
            #expect(mockTerminating.error is TerminationError)
            #expect(mockTerminating.alertAndTerminateCalled == false)
            stateMachine.handle(.willConnectToWindow(window: UIWindow()))
            #expect(mockTerminating.alertAndTerminateCalled == true)
        } else {
            Issue.record("Expected to transition to .terminating state")
        }
    }

    @Test("Incorrect transitions from Launching should not trigger state change")
    func incorrectTransitionsFromLaunching() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.name == "launching")

        stateMachine.handle(.willEnterForeground)
        #expect(stateMachine.currentState.name == "launching")

        stateMachine.handle(.willResignActive)
        #expect(stateMachine.currentState.name == "launching")

        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "launching")

        stateMachine.handle(.didEnterBackground)
        #expect(stateMachine.currentState.name == "launching")
    }

}

@MainActor
@Suite("AppStateMachine connected origin transition tests", .serialized)
final class ConnectedTests {

    let stateMachine = AppStateMachine(initialState: .connected(MockConnected(actionToHandle: nil, window: UIWindow())))

    @Test("didBecomeActive should transition from Connected to Foreground and call onTransition and didReturn")
    func transitionFromConnectedToForeground() {
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.eventLog == ["onTransition", "didReturn"])
            #expect(mockForeground.actionToHandle == nil)
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("didEnterBackground should transition from Launching to Background and call onTransition and didReturn")
    func transitionFromLaunchingToBackground() {
        stateMachine.handle(.didEnterBackground)
        #expect(stateMachine.currentState.name == "background")

        if case .background(let background) = stateMachine.currentState,
           let mockBackground = background as? MockBackground {
            #expect(mockBackground.eventLog == ["onTransition", "didReturn"])
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("handle(_:) if we transition to Background then actionToHandle should be consumed afterwards")
    func handleAppActionWhenTransitionsFromLaunchingToBackground() {
        stateMachine.handle(.openURL(URL("www.duckduckgo.com")!))
        #expect(stateMachine.actionToHandle != nil)
        stateMachine.handle(.didEnterBackground)
        #expect(stateMachine.actionToHandle == nil)
    }

    @Test("Incorrect transitions from Connected should not trigger state change")
    func incorrectTransitionsFromConnected() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.name == "connected")

        stateMachine.handle(.willEnterForeground)
        #expect(stateMachine.currentState.name == "connected")

        stateMachine.handle(.willConnectToWindow(window: UIWindow()))
        #expect(stateMachine.currentState.name == "connected")

        stateMachine.handle(.willResignActive)
        #expect(stateMachine.currentState.name == "connected")
    }

}

@MainActor
@Suite("AppStateMachine foreground origin transition tests", .serialized)
final class ForegroundTests {

    let stateMachine = AppStateMachine(initialState: .foreground(MockForeground(actionToHandle: nil)))

    @Test("didEnterBackground should transition from Foreground to Background and call onTransition and didReturn")
    func transitionFromForegroundToBackground() {
        stateMachine.handle(.willResignActive)
        #expect(stateMachine.currentState.name == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.eventLog == ["willLeave"])
        } else {
            Issue.record("Incorrect state")
        }

        stateMachine.handle(.didEnterBackground)
        #expect(stateMachine.currentState.name == "background")

        if case .background(let background) = stateMachine.currentState,
           let mockBackground = background as? MockBackground {
            #expect(mockBackground.eventLog == ["onTransition", "didReturn"])
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("willResignActive and didBecomeActive should call willLeave and didReturn on Foreground")
    func transitionFromForegroundToForeground() {
        stateMachine.handle(.willResignActive)
        #expect(stateMachine.currentState.name == "foreground")
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.eventLog == ["willLeave", "didReturn"])
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("handle(_:) if current state is Foreground should call handle(_:) on that state")
    func handleAppAction() {
        stateMachine.handle(.openURL(URL("www.duckduckgo.com")!))
        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.handleActionCalled)
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("Incorrect transitions from Foreground should not trigger state change")
    func incorrectTransitionsFromForeground() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.name == "foreground")

        stateMachine.handle(.willEnterForeground)
        #expect(stateMachine.currentState.name == "foreground")
    }

}

@MainActor
@Suite("AppStateMachine background origin transition tests", .serialized)
final class BackgroundTests {

    let stateMachine = AppStateMachine(initialState: .background(MockBackground()))

    @Test("didBecomeActive should transition from Background to Foreground and call onTransition and didReturn")
    func transitionFromBackgroundToForeground() {
        stateMachine.handle(.willEnterForeground)
        #expect(stateMachine.currentState.name == "background")

        if case .background(let background) = stateMachine.currentState,
           let mockBackground = background as? MockBackground {
            #expect(mockBackground.eventLog == ["willLeave"])
        } else {
            Issue.record("Incorrect state")
        }

        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.eventLog == ["onTransition", "didReturn"])
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("willEnterForeground and didEnterBackground should call willLeave and didReturn on Foreground")
    func transitionFromBackgroundToBackground() {
        stateMachine.handle(.willEnterForeground)
        #expect(stateMachine.currentState.name == "background")
        stateMachine.handle(.didEnterBackground)
        #expect(stateMachine.currentState.name == "background")

        if case .background(let background) = stateMachine.currentState,
           let mockBackground = background as? MockBackground {
            #expect(mockBackground.eventLog == ["willLeave", "didReturn"])
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("handle(_:) if current state is Background should pass that action to Foreground and be consumed afterwards")
    func handleAppAction() {
        stateMachine.handle(.openURL(URL("www.duckduckgo.com")!))
        #expect(stateMachine.actionToHandle != nil)
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.actionToHandle == nil)

        #expect(stateMachine.currentState.name == "foreground")
        if case .foreground(let foreground) = stateMachine.currentState,
           let mockForeground = foreground as? MockForeground {
            #expect(mockForeground.actionToHandle != nil)
        } else {
            Issue.record("Incorrect state")
        }
    }

    @Test("Incorrect transitions from Background should not trigger state change")
    func incorrectTransitionsFromBackground() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(stateMachine.currentState.name == "background")

        stateMachine.handle(.willResignActive)
        #expect(stateMachine.currentState.name == "background")
    }

}
