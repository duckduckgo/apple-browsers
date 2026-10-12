//
//  AppStateMachine.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Core
import PixelKit

enum AppEvent {

    case didFinishLaunching(isTesting: Bool)
    case didBecomeActive
    case didEnterBackground
    case willResignActive
    case willEnterForeground
    case willConnectToWindow(window: UIWindow)

}

enum AppAction {

    case openURL(URL)
    case handleShortcutItem(UIApplicationShortcutItem)
    case handleUserActivity(NSUserActivity)

}

enum AppState {

    case initializing(InitializingHandling)
    case launching(LaunchingHandling)
    case connected(any ConnectedHandling)
    case foreground(ForegroundHandling)
    case background(BackgroundHandling)
    case terminating(TerminatingHandling)
    case simulated(Simulated)

    var name: String {
        switch self {
        case .initializing:
            return "initializing"
        case .launching:
            return "launching"
        case .connected:
            return "connected"
        case .foreground:
            return "foreground"
        case .background:
            return "background"
        case .terminating:
            return "terminating"
        case .simulated:
            return "simulated"
        }
    }

}

@MainActor
protocol InitializingHandling {

    init()

    func makeLaunchingState() throws -> any LaunchingHandling

}

@MainActor
protocol LaunchingHandling {

    init() throws

    func makeConnectedState(window: UIWindow, actionToHandle: AppAction?) -> any ConnectedHandling

}

@MainActor
protocol ConnectedHandling {

    associatedtype Dependencies
    func makeBackgroundState() -> any BackgroundHandling
    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling

}

@MainActor
protocol ForegroundHandling {

    func onTransition()
    func willLeave()
    func didReturn()
    func handle(_ action: AppAction)

    func makeBackgroundState() -> any BackgroundHandling
    func makeConnectedState(window: UIWindow, actionToHandle: AppAction?) -> any ConnectedHandling

}

@MainActor
protocol BackgroundHandling {

    func onTransition()
    func willLeave()
    func didReturn()

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling
    func makeConnectedState(window: UIWindow, actionToHandle: AppAction?) -> any ConnectedHandling

}

@MainActor
protocol TerminatingHandling {

    init(error: Error)
    func alertAndTerminate(window: UIWindow)

}

@MainActor
protocol TerminatingStateFactory {

    func makeTerminatingState(error: Error) -> any TerminatingHandling

}

@MainActor
struct DefaultTerminatingStateFactory: TerminatingStateFactory {

    // swiftlint:disable:next unneeded_synthesized_initializer
    nonisolated init() {}

    func makeTerminatingState(error: Error) -> any TerminatingHandling {
        Terminating(error: error)
    }

}

@MainActor
final class AppStateMachine {

    private(set) var currentState: AppState {
        didSet {
            switch currentState {
            case .foreground, .background: launchBreadcrumb.clear()
            default: break
            }
        }
    }

    /// Buffers the most recent action for the `Foreground` state. Cleared in foreground and background.
    /// Only the latest action is retained; any new action overwrites the previous one.
    /// Clearing in background prevents stale actions (e.g., open URLs) from persisting
    /// if the app is backgrounded before user authentication (iOS 18.0+).
    private(set) var actionToHandle: AppAction?

    /// Identity of the last window passed via `willConnectToWindow`, used to detect whether
    /// consecutive scene connections reuse the same window or receive a new one.
    private var lastConnectedWindowIdentifier: ObjectIdentifier?

    private let terminatingStateFactory: TerminatingStateFactory
    private let launchBreadcrumb: LaunchBreadcrumb

    init(initialState: AppState,
         terminatingStateFactory: TerminatingStateFactory = DefaultTerminatingStateFactory(),
         launchBreadcrumb: LaunchBreadcrumb = LaunchBreadcrumb()) {
        self.currentState = initialState
        self.terminatingStateFactory = terminatingStateFactory
        self.launchBreadcrumb = launchBreadcrumb
    }

    func handle(_ event: AppEvent) {
        // Before dispatching, so a window dropped in `initializing` or `launching` still counts.
        if case .willConnectToWindow = event {
            launchBreadcrumb.markSceneConnected()
        }
        switch currentState {
        case .initializing(let initializing):
            respond(to: event, in: initializing)
        case .launching(let launching):
            respond(to: event, in: launching)
        case .connected(let connected):
            respond(to: event, in: connected)
        case .foreground(let foreground):
            respond(to: event, in: foreground)
        case .background(let background):
            respond(to: event, in: background)
        case .terminating(let terminating):
            respond(to: event, in: terminating)
        case .simulated(let simulated):
            respond(to: event, in: simulated)
        }
    }

    func handle(_ action: AppAction) {
        if case .foreground(let foregroundHandling) = currentState {
            foregroundHandling.handle(action)
        } else {
            actionToHandle = action
        }
    }

    private func respond(to event: AppEvent, in initializing: InitializingHandling) {
        guard case .didFinishLaunching(let isTesting) = event else { return handleUnexpectedEvent(event, for: .initializing(initializing)) }
        if isTesting {
            currentState = .simulated(Simulated())
        } else {
            launchBreadcrumb.startLaunch()
            do {
                let launching = try initializing.makeLaunchingState()
                launchBreadcrumb.mark(.launched)
                currentState = .launching(launching)
            } catch {
                launchBreadcrumb.mark(.terminating)
                currentState = .terminating(terminatingStateFactory.makeTerminatingState(error: error))
            }
        }
    }

    private func respond(to event: AppEvent, in launching: LaunchingHandling) {
        switch event {
        case .willConnectToWindow(let window):
            storeWindowIdentifier(window)
            launchBreadcrumb.mark(.windowConnected)
            let connected = launching.makeConnectedState(window: window, actionToHandle: actionToHandle)
            launchBreadcrumb.mark(.uiAttached)
            currentState = .connected(connected)
        default:
            handleUnexpectedEvent(event, for: .launching(launching))
        }
    }

    private func respond(to event: AppEvent, in connected: any ConnectedHandling) {
        switch event {
        case .didBecomeActive:
            let foreground = connected.makeForegroundState(actionToHandle: actionToHandle)
            foreground.onTransition()
            foreground.didReturn()
            actionToHandle = nil
            currentState = .foreground(foreground)
        case .didEnterBackground:
            let background = connected.makeBackgroundState()
            background.onTransition()
            background.didReturn()
            actionToHandle = nil
            currentState = .background(background)
        case .willEnterForeground:
            // This has been fixed on Apple side for scenes and is always called after the scene connects.
            // However, we only transition to Foreground after didBecomeActive, since both events occur in sequence.
            // We may revisit this if any UI glitches appear, as some work could potentially happen earlier in willEnterForeground.
            break
        case .willConnectToWindow(let window):
            let windowChanged = lastConnectedWindowIdentifier != ObjectIdentifier(window)
            storeWindowIdentifier(window)
            PixelKit.fire(Pixel.Event.sceneWillConnectToWindowCalledInConnectedState,
                          frequency: .dailyAndCount,
                          options: .parameters([PixelParameters.windowChanged: String(windowChanged)]))
        default:
            handleUnexpectedEvent(event, for: .connected(connected))
        }
    }

    private func respond(to event: AppEvent, in foreground: ForegroundHandling) {
        switch event {
        case .didBecomeActive:
            foreground.didReturn()
        case .didEnterBackground:
            let background = foreground.makeBackgroundState()
            background.onTransition()
            background.didReturn()
            currentState = .background(background)
        case .willResignActive:
            foreground.willLeave()
        case .willConnectToWindow(let window): // Please remove once we stop supporting iOS 16
            storeWindowIdentifier(window)
            currentState = .connected(foreground.makeConnectedState(window: window, actionToHandle: actionToHandle))
        default:
            handleUnexpectedEvent(event, for: .foreground(foreground))
        }
    }

    private func respond(to event: AppEvent, in background: BackgroundHandling) {
        switch event {
        case .didBecomeActive:
            let foreground = background.makeForegroundState(actionToHandle: actionToHandle)
            foreground.onTransition()
            foreground.didReturn()
            actionToHandle = nil
            currentState = .foreground(foreground)
        case .didEnterBackground:
            background.didReturn()
            actionToHandle = nil
        case .willEnterForeground:
            background.willLeave()
        case .willConnectToWindow(let window): // Please remove once we stop supporting iOS 16
            storeWindowIdentifier(window)
            currentState = .connected(background.makeConnectedState(window: window, actionToHandle: actionToHandle))
        default:
            handleUnexpectedEvent(event, for: .background(background))
        }
    }

    private func respond(to event: AppEvent, in simulated: Simulated) {
        if case .willConnectToWindow(let window) = event {
            simulated.configure(window)
        }
    }

    private func respond(to event: AppEvent, in terminating: TerminatingHandling) {
        if case .willConnectToWindow(let window) = event {
            terminating.alertAndTerminate(window: window)
        }
    }

    private func storeWindowIdentifier(_ window: UIWindow) {
        lastConnectedWindowIdentifier = ObjectIdentifier(window)
    }

    private func handleUnexpectedEvent(_ event: AppEvent, for state: AppState) {
        Logger.lifecycle.error("🔴 Unexpected [\(String(describing: event))] event while in [\(state.name))] state!")
        PixelKit.fire(Pixel.Event.appDidTransitionToUnexpectedState,
                      frequency: .dailyAndCount,
                      options: .parameters([PixelParameters.appState: state.name,
                                                                PixelParameters.appEvent: String(describing: event)]))
    }

}

enum LaunchBreadcrumbPixel: PixelKit.Event {

    case previousLaunchIncomplete(breadcrumb: [String: String])

    var name: String { "app-lifecycle_previous-launch-incomplete" }

    var parameters: [String: String]? {
        switch self {
        case .previousLaunchIncomplete(let breadcrumb): return breadcrumb
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
    var namePrefix: PixelKitNamePrefix { .none }

}

/// The last launch step reached, kept until the app reaches Foreground or Background. One left over at the next launch
/// means that launch never finished, e.g. a black screen the user had to force quit, a hang, or a kill during launch.
struct LaunchBreadcrumb {

    /// Launch steps in the order they run. `Launching.init` marks the steps between `launchingStarted` and `launched`.
    enum Step: String {
        case launchingStarted = "launching-started"
        case keyValueStore = "key-value-store"
        case persistentStores = "persistent-stores"
        case sync
        case contentBlocking = "content-blocking"
        case mainCoordinator = "main-coordinator"
        case launched
        case windowConnected = "window-connected"
        case uiAttached = "ui-attached"
        case terminating
    }

    static let key = "com.duckduckgo.app-lifecycle.launch-breadcrumb"
    static let pendingReportKey = "com.duckduckgo.app-lifecycle.launch-breadcrumb.pending-report"
    static let sceneConnectedKey = "com.duckduckgo.app-lifecycle.launch-breadcrumb.scene-connected"

    private let store: UserDefaults
    private let pixelFiring: () -> (any PixelKitFiring)?

    init(store: UserDefaults = .standard,
         pixelFiring: @escaping () -> (any PixelKitFiring)? = { PixelKit.shared }) {
        self.store = store
        self.pixelFiring = pixelFiring
    }

    var current: [String: String]? {
        store.dictionary(forKey: Self.key) as? [String: String]
    }

    var pendingReport: [String: String]? {
        store.dictionary(forKey: Self.pendingReportKey) as? [String: String]
    }

    var sceneConnected: Bool {
        store.bool(forKey: Self.sceneConnectedKey)
    }

    /// Starts a new launch. A breadcrumb left by the previous launch is kept for `reportIncompleteLaunch()`, so it
    /// survives even if this launch hangs or crashes before reporting it.
    ///
    /// A background launch (fetch, `BGTask`) finishes launching without a scene and is later killed while suspended.
    /// That is not a failure, so a breadcrumb at `launched` without a scene is dropped. With a scene, the same
    /// breadcrumb means the window was never attached, e.g. the black screen after a dropped `willConnectToWindow`.
    func startLaunch() {
        if let current, current["step"] != Step.launched.rawValue || sceneConnected {
            store.set(current, forKey: Self.pendingReportKey)
        }
        store.removeObject(forKey: Self.sceneConnectedKey)
        mark(.launchingStarted)
    }

    func markSceneConnected() {
        store.set(true, forKey: Self.sceneConnectedKey)
    }

    func mark(_ step: Step) {
        store.set(["step": step.rawValue], forKey: Self.key)
    }

    func clear() {
        store.removeObject(forKey: Self.key)
        store.removeObject(forKey: Self.sceneConnectedKey)
    }

    /// Reports a launch that never finished. Called as early as PixelKit allows, so a launch that fails every time
    /// still reports the one before it.
    func reportIncompleteLaunch() {
        guard let pendingReport else { return }
        store.removeObject(forKey: Self.pendingReportKey)
        pixelFiring()?.fire(LaunchBreadcrumbPixel.previousLaunchIncomplete(breadcrumb: pendingReport), frequency: .dailyAndCount)
    }

}
