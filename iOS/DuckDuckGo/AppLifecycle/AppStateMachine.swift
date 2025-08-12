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

}

enum AppAction {

    case openURL(URL)
    case handleShortcutItem(UIApplicationShortcutItem)

}

enum AppState {

    case initializing(InitializingHandling)
    case launching(LaunchingHandling)
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

}

@MainActor
protocol BackgroundHandling {

    func onTransition()
    func willLeave()
    func didReturn()

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling

}

@MainActor
protocol TerminatingHandling {

    init(error: Error, application: UIApplication)

}

@MainActor
final class AppStateMachine {

    private(set) var currentState: AppState

    /// Buffers the most recent action for the `Foreground` state. Cleared in foreground and background.
    /// Only the latest action is retained; any new action overwrites the previous one.
    /// Clearing in background prevents stale actions (e.g., open URLs) from persisting
    /// if the app is backgrounded before user authentication (iOS 18.0+).
    private(set) var actionToHandle: AppAction?

    init(initialState: AppState) {
        self.currentState = initialState
    }

    func handle(_ event: AppEvent) {
        switch currentState {
        case .initializing(let initializing):
            respond(to: event, in: initializing)
        case .launching(let launching):
            respond(to: event, in: launching)
        case .foreground(let foreground):
            respond(to: event, in: foreground)
        case .background(let background):
            respond(to: event, in: background)
        case .terminating, .simulated:
            break
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
                currentState = .terminating(Terminating(error: error))
            }
        }
    }

    private func respond(to event: AppEvent, in launching: LaunchingHandling) {
        switch event {
        case .didBecomeActive:
            let foreground = launching.makeForegroundState(actionToHandle: actionToHandle)
            foreground.onTransition()
            foreground.didReturn()
            actionToHandle = nil
            currentState = .foreground(foreground)
        case .didEnterBackground:
            let background = launching.makeBackgroundState()
            background.onTransition()
            background.didReturn()
            actionToHandle = nil
            currentState = .background(background)
        case .willEnterForeground:
            // This event *shouldn’t* happen in the Launching state, but apparently, it does in some cases:
            // https://developer.apple.com/forums/thread/769924
            // We don’t support this transition and instead stay in Launching.
            // From here, we can move to Foreground or Background, where resuming/suspension is handled properly.
            break
        default:
            handleUnexpectedEvent(event, for: .launching(launching))
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
        default:
            handleUnexpectedEvent(event, for: .background(background))
        }
    }

    private func handleUnexpectedEvent(_ event: AppEvent, for state: AppState) {
        Logger.lifecycle.error("🔴 Unexpected [\(String(describing: event))] event while in [\(state.name))] state!")
        DailyPixel.fireDailyAndCount(pixel: .appDidTransitionToUnexpectedState,
                                     withAdditionalParameters: [PixelParameters.appState: state.name,
                                                                PixelParameters.appEvent: String(describing: event)])
    }

}
