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
@_spi(Testing) import PixelKit

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

extension LaunchBreadcrumb {

    /// Keeps state machine tests out of the test host's `UserDefaults.standard` and away from real pixels.
    static var testing: LaunchBreadcrumb {
        LaunchBreadcrumb(store: UserDefaults(suiteName: "AppStateMachineTests")!, pixelFiring: { nil })
    }

}

@MainActor
@Suite("AppStateMachine launching origin transition tests", .serialized)
final class LaunchingTests {

    let stateMachine = AppStateMachine(initialState: .initializing(MockInitializing()),
                                       terminatingStateFactory: MockTerminatingStateFactory(),
                                       launchBreadcrumb: .testing)

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

    let stateMachine = AppStateMachine(initialState: .connected(MockConnected(actionToHandle: nil, window: UIWindow())), launchBreadcrumb: .testing)

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

    let stateMachine = AppStateMachine(initialState: .foreground(MockForeground(actionToHandle: nil)), launchBreadcrumb: .testing)

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

    let stateMachine = AppStateMachine(initialState: .background(MockBackground()), launchBreadcrumb: .testing)

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

@MainActor
@Suite("Scene lifecycle pixels")
final class SceneLifecycleInstrumentationTests {

    private final class StubAppUIViewController: UIViewController {}

    let pixelKit = PixelKitMock()
    lazy var instrumentation = SceneLifecycleInstrumentation(pixelFiring: pixelKit, isAppUI: { $0 is StubAppUIViewController })

    @available(iOS 16, macOS 13, *)
    @Test("Becoming active with no app UI in any window fires the pixel", .timeLimit(.minutes(1)))
    func activeWithoutAppUIFires() {
        // A reconnected scene only has the new window that nothing has attached the UI to.
        instrumentation.sceneDidBecomeActive(windows: [UIWindow()])

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SceneLifecyclePixel.activeWithoutMainUI, frequency: .daily)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Becoming active with app UI only in a hidden window fires the pixel", .timeLimit(.minutes(1)))
    func activeWithAppUIOnlyInHiddenWindowFires() {
        let hiddenWindow = UIWindow()
        hiddenWindow.rootViewController = StubAppUIViewController()
        hiddenWindow.isHidden = true

        instrumentation.sceneDidBecomeActive(windows: [hiddenWindow, UIWindow()])

        #expect(pixelKit.actualFireCalls.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Becoming active with app UI in a visible window does not fire the pixel", .timeLimit(.minutes(1)))
    func activeWithAppUIDoesNotFire() {
        // e.g. the authentication overlay is visible while it hides the main window.
        let hiddenMainWindow = UIWindow()
        hiddenMainWindow.rootViewController = UIViewController()
        hiddenMainWindow.isHidden = true
        let overlayWindow = UIWindow()
        overlayWindow.rootViewController = StubAppUIViewController()
        overlayWindow.isHidden = false

        instrumentation.sceneDidBecomeActive(windows: [hiddenMainWindow, overlayWindow, UIWindow()])

        #expect(pixelKit.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Main UI and its overlays count as app UI by default", .timeLimit(.minutes(1)))
    func defaultAppUIIncludesOverlays() {
        let pixelKit = PixelKitMock()
        let instrumentation = SceneLifecycleInstrumentation(pixelFiring: pixelKit)
        let window = UIWindow()
        window.rootViewController = AuthenticationViewController()
        window.isHidden = false

        instrumentation.sceneDidBecomeActive(windows: [window])

        #expect(pixelKit.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Scene disconnect fires with the current app state", .timeLimit(.minutes(1)))
    func sceneDidDisconnectFiresWithState() {
        let stateMachine = AppStateMachine(initialState: .connected(MockConnected(actionToHandle: nil, window: UIWindow())), launchBreadcrumb: .testing)
        instrumentation.sceneDidDisconnect(in: stateMachine.currentState)
        stateMachine.handle(.didBecomeActive)
        instrumentation.sceneDidDisconnect(in: stateMachine.currentState)
        stateMachine.handle(.didEnterBackground)
        instrumentation.sceneDidDisconnect(in: stateMachine.currentState)

        #expect(pixelKit.actualFireCalls == ["connected", "foreground", "background"].map {
            ExpectedFireCall(pixel: SceneLifecyclePixel.sceneDidDisconnect(appState: $0), frequency: .dailyAndCount)
        })
    }

}

@MainActor
@Suite("Launch breadcrumb", .serialized)
final class LaunchBreadcrumbTests {

    let suiteName = "LaunchBreadcrumbTests-\(UUID().uuidString)"
    let pixelKit = PixelKitMock()
    let initializing = MockInitializing()
    lazy var store = UserDefaults(suiteName: suiteName)!
    lazy var launchBreadcrumb = LaunchBreadcrumb(store: store, pixelFiring: { [pixelKit] in pixelKit })
    lazy var stateMachine = AppStateMachine(initialState: .initializing(initializing),
                                            terminatingStateFactory: MockTerminatingStateFactory(),
                                            launchBreadcrumb: launchBreadcrumb)

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A launch that reaches Foreground leaves no breadcrumb and fires nothing", .timeLimit(.minutes(1)))
    func completedLaunchClearsBreadcrumb() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(launchBreadcrumb.current == ["step": "launched"])
        stateMachine.handle(.willConnectToWindow(window: UIWindow()))
        #expect(launchBreadcrumb.current == ["step": "ui-attached"])
        stateMachine.handle(.didBecomeActive)

        #expect(launchBreadcrumb.current == nil)
        #expect(pixelKit.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A launch that reaches Background leaves no breadcrumb", .timeLimit(.minutes(1)))
    func backgroundLaunchClearsBreadcrumb() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.willConnectToWindow(window: UIWindow()))
        stateMachine.handle(.didEnterBackground)

        #expect(launchBreadcrumb.current == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Starting a launch keeps the previous launch's breadcrumb for reporting", .timeLimit(.minutes(1)))
    func startingLaunchKeepsPreviousBreadcrumb() {
        let previous = ["step": "persistent-stores"]
        store.set(previous, forKey: LaunchBreadcrumb.key)

        stateMachine.handle(.didFinishLaunching(isTesting: false))

        #expect(launchBreadcrumb.pendingReport == previous)
        #expect(launchBreadcrumb.current?["step"] == "launched")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A launch that terminates is marked as terminating and keeps the previous breadcrumb", .timeLimit(.minutes(1)))
    func terminatingLaunch() {
        let previous = ["step": "main-coordinator"]
        store.set(previous, forKey: LaunchBreadcrumb.key)
        initializing.shouldThrowOnLaunching = true

        stateMachine.handle(.didFinishLaunching(isTesting: false))

        #expect(launchBreadcrumb.pendingReport == previous)
        #expect(launchBreadcrumb.current?["step"] == "terminating")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every launch in a crash loop reports the launch before it", .timeLimit(.minutes(1)))
    func crashLoopReportsEachLaunch() {
        // Each iteration is a launch that reports, then crashes while loading the persistent stores.
        for _ in 0..<3 {
            launchBreadcrumb.startLaunch()
            launchBreadcrumb.reportIncompleteLaunch()
            launchBreadcrumb.mark(.persistentStores)
        }

        let crashed = ["step": "persistent-stores"]
        #expect(pixelKit.actualFireCalls.map(\.pixel.parameters) == [crashed, crashed])
        #expect(pixelKit.actualFireCalls.allSatisfy { $0.frequency == .dailyAndCount })
        #expect(launchBreadcrumb.pendingReport == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A background launch that never connects a scene is not reported", .timeLimit(.minutes(1)))
    func backgroundLaunchWithoutSceneIsNotReported() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        #expect(launchBreadcrumb.current?["step"] == "launched")

        // iOS kills the suspended app; the next launch starts.
        launchBreadcrumb.startLaunch()
        launchBreadcrumb.reportIncompleteLaunch()

        #expect(launchBreadcrumb.pendingReport == nil)
        #expect(pixelKit.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A launch whose window was never attached is reported", .timeLimit(.minutes(1)))
    func launchWithSceneButNoUIIsReported() {
        // The window arrives while Launching is still being made, is dropped, and launch ends at `launched`.
        launchBreadcrumb.startLaunch()
        launchBreadcrumb.markSceneConnected()
        launchBreadcrumb.mark(.launched)

        launchBreadcrumb.startLaunch()
        launchBreadcrumb.reportIncompleteLaunch()

        #expect(pixelKit.actualFireCalls.map(\.pixel.parameters) == [["step": "launched"]])
        #expect(launchBreadcrumb.sceneConnected == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A window dropped before launch finishes still counts as a connected scene", .timeLimit(.minutes(1)))
    func droppedWindowMarksSceneConnected() {
        stateMachine.handle(.willConnectToWindow(window: UIWindow()))

        #expect(stateMachine.currentState.name == "initializing")
        #expect(launchBreadcrumb.sceneConnected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nothing is reported after a launch that finished", .timeLimit(.minutes(1)))
    func nothingReportedAfterCompletedLaunch() {
        stateMachine.handle(.didFinishLaunching(isTesting: false))
        stateMachine.handle(.willConnectToWindow(window: UIWindow()))
        stateMachine.handle(.didBecomeActive)

        launchBreadcrumb.startLaunch()
        launchBreadcrumb.reportIncompleteLaunch()

        #expect(pixelKit.actualFireCalls.isEmpty)
    }

}

@MainActor
@Suite("Critical alert pixel")
final class CriticalAlertPixelTests {

    let pixelKit = PixelKitMock()

    @available(iOS 16, macOS 13, *)
    @Test("Showing the alert for a full disk fires the pixel with the disk space reason", .timeLimit(.minutes(1)))
    func diskFullAlertFiresPixel() {
        let diskFull = NSError(domain: NSCocoaErrorDomain, code: 1,
                               userInfo: [NSUnderlyingErrorKey: NSError(domain: "NSSQLiteErrorDomain", code: 13)])

        Terminating(error: TerminationError.historyDatabase(diskFull), pixelFiring: pixelKit).alertAndTerminate(window: UIWindow())

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: CriticalAlertPixel.shown(reason: .insufficientDiskSpace),
                                                              frequency: .dailyAndCount)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Showing the alert for other errors fires the pixel with the unrecoverable state reason", .timeLimit(.minutes(1)))
    func unrecoverableStateAlertFiresPixel() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 1)

        Terminating(error: TerminationError.historyDatabase(error), pixelFiring: pixelKit).alertAndTerminate(window: UIWindow())

        #expect(pixelKit.actualFireCalls.map(\.pixel.parameters) == [["reason": "unrecoverable-state"]])
    }

}
