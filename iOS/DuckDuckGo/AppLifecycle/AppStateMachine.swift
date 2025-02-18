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
    case willTerminate(UIApplication.TerminationReason)

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

    var rawValue: String {
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

    func makeLaunchingState() -> any LaunchingHandling

}

@MainActor
protocol LaunchingHandling {

    init()

    func makeBackgroundState() -> any BackgroundHandling
    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling
    func makeTerminatingState(terminationReason: UIApplication.TerminationReason) -> any TerminatingHandling

}

@MainActor
protocol ForegroundHandling {

    func onTransition()
    func willLeave()
    func didReturn()
    func handle(_ action: AppAction)

    func makeBackgroundState() -> any BackgroundHandling
    func makeTerminatingState(terminationReason: UIApplication.TerminationReason) -> any TerminatingHandling

}

@MainActor
protocol BackgroundHandling {

    func onTransition()
    func willLeave()
    func didReturn()

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling
    func makeTerminatingState() -> any TerminatingHandling


}

@MainActor
protocol TerminatingHandling {

    init()
    init(terminationReason: UIApplication.TerminationReason, application: UIApplication)

}

@MainActor
final class AppStateMachine {

    private(set) var currentState: AppState
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
        currentState = isTesting ? .simulated(Simulated()) : .launching(initializing.makeLaunchingState())
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
            currentState = .background(background)
        case .willEnterForeground:
            // This event *shouldn’t* happen in the Launching state, but apparently, it does in some cases:
            // https://developer.apple.com/forums/thread/769924
            // We don’t support this transition and instead stay in Launching.
            // From here, we can move to Foreground or Background, where resuming/suspension is handled properly.
            break
        case .willTerminate(let terminationReason):
            let terminating = launching.makeTerminatingState(terminationReason: terminationReason)
            currentState = .terminating(terminating)
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
        case .willTerminate(let terminationReason):
            let terminating = foreground.makeTerminatingState(terminationReason: terminationReason)
            currentState = .terminating(terminating)
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
        case .willEnterForeground:
            background.willLeave()
        case .willTerminate:
            let terminating = background.makeTerminatingState()
            currentState = .terminating(terminating)
        default:
            handleUnexpectedEvent(event, for: .background(background))
        }
    }

    private func handleUnexpectedEvent(_ event: AppEvent, for state: AppState) {
        Logger.lifecycle.error("🔴 Unexpected [\(String(describing: event))] event while in [\(state.rawValue))] state!")
        DailyPixel.fireDailyAndCount(pixel: .appDidTransitionToUnexpectedState,
                                     withAdditionalParameters: [PixelParameters.appState: state.rawValue,
                                                                PixelParameters.appEvent: String(describing: event)])
    }

}
