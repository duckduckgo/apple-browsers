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

    private(set) var currentState: AppState

    /// Buffers the most recent action for the `Foreground` state. Cleared in foreground and background.
    /// Only the latest action is retained; any new action overwrites the previous one.
    /// Clearing in background prevents stale actions (e.g., open URLs) from persisting
    /// if the app is backgrounded before user authentication (iOS 18.0+).
    private(set) var actionToHandle: AppAction?

    private let terminatingStateFactory: TerminatingStateFactory

    init(initialState: AppState, terminatingStateFactory: TerminatingStateFactory = DefaultTerminatingStateFactory()) {
        self.currentState = initialState
        self.terminatingStateFactory = terminatingStateFactory
    }

    func handle(_ event: AppEvent) {
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
            do {
                currentState = try .launching(initializing.makeLaunchingState())
            } catch {
                currentState = .terminating(terminatingStateFactory.makeTerminatingState(error: error))
            }
        }
    }

    private func respond(to event: AppEvent, in launching: LaunchingHandling) {
        switch event {
        case .willConnectToWindow(let window):
            let connected = launching.makeConnectedState(window: window,
                                                         actionToHandle: actionToHandle)
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
            // This is now fixed for scenes and is always called after the scene connects.
            // However, we only transition to Foreground after didBecomeActive, since both events occur in sequence.
            // We may revisit this if any UI glitches appear, as some work could potentially happen earlier in willEnterForeground.
            break
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
        case .willConnectToWindow(let window):
            DailyPixel.fireDailyAndCount(pixel: .sceneDidDisconnectAndAttemptedToReconnect,
                                         withAdditionalParameters: [PixelParameters.osVersion: UIDevice.current.systemVersion])
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
        case .willConnectToWindow(let window):
            DailyPixel.fireDailyAndCount(pixel: .sceneDidDisconnectAndAttemptedToReconnect,
                                         withAdditionalParameters: [PixelParameters.osVersion: UIDevice.current.systemVersion])
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

    private func handleUnexpectedEvent(_ event: AppEvent, for state: AppState) {
        Logger.lifecycle.error("🔴 Unexpected [\(String(describing: event))] event while in [\(state.name))] state!")
        DailyPixel.fireDailyAndCount(pixel: .appDidTransitionToUnexpectedState,
                                     withAdditionalParameters: [PixelParameters.appState: state.name,
                                                                PixelParameters.appEvent: String(describing: event)])
    }

}
