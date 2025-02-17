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
    case terminating(Terminating)
    case simulated(Simulated)

}

@MainActor
protocol InitializingHandling {

    init()

    func makeLaunchingState() -> LaunchingHandling

}

@MainActor
protocol LaunchingHandling {

    init()

    func makeBackgroundState() -> BackgroundHandling
    func makeForegroundState(actionToHandle: AppAction?) -> ForegroundHandling
}

@MainActor
protocol ForegroundHandling {

    func onTransition()
    func willLeave()
    func didReturn()
    func handle(_ action: AppAction)

    func makeBackgroundState() -> BackgroundHandling

}

@MainActor
protocol BackgroundHandling {

    func onTransition()
    func willLeave()
    func didReturn()

    func makeForegroundState(actionToHandle: AppAction?) -> ForegroundHandling

}

@MainActor
final class AppStateMachine {

    private(set) var currentState: AppState = .initializing(Initializing())
    private var actionToHandle: AppAction?

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

    private func respond(to event: AppEvent, in initializing: InitializingHandling) {
        guard case .didFinishLaunching(let isTesting) = event else { return handleUnexpectedEvent(event) }
        currentState = isTesting ? .simulated(Simulated()) : .launching(initializing.makeLaunchingState())
    }

    private func respond(to event: AppEvent, in launching: LaunchingHandling) {
        switch event {
        case .didBecomeActive:
            let foreground = launching.makeForegroundState(actionToHandle: actionToHandle)
            foreground.onTransition()
            actionToHandle = nil
            currentState = .foreground(foreground)
        case .didEnterBackground:
            let background = launching.makeBackgroundState()
            background.onTransition()
            currentState = .background(background)
        case .willEnterForeground:
            // This event *shouldn’t* happen in the Launching state, but apparently, it does in some cases:
            // https://developer.apple.com/forums/thread/769924
            // We don’t support this transition and instead stay in Launching.
            // From here, we can move to Foreground or Background, where resuming/suspension is handled properly.
            break
        case .willTerminate(let terminationReason):
            currentState = .terminating(Terminating(terminationReason: terminationReason))
        default:
            handleUnexpectedEvent(event)
        }
    }

    private func respond(to event: AppEvent, in foreground: ForegroundHandling) {
        switch event {
        case .didBecomeActive:
            foreground.didReturn()
        case .didEnterBackground:
            let background = foreground.makeBackgroundState()
            background.onTransition()
            currentState = .background(background)
        case .willResignActive:
            foreground.willLeave()
        case .willTerminate(let terminationReason):
            currentState = .terminating(Terminating(terminationReason: terminationReason))
        default:
            handleUnexpectedEvent(event)
        }
    }

    private func respond(to event: AppEvent, in background: BackgroundHandling) {
        switch event {
        case .didBecomeActive:
            let foreground = background.makeForegroundState(actionToHandle: actionToHandle)
            foreground.onTransition()
            actionToHandle = nil
            currentState = .foreground(foreground)
        case .didEnterBackground:
            background.didReturn()
        case .willEnterForeground:
            background.willLeave()
        case .willTerminate(let terminationReason):
            currentState = .terminating(Terminating(terminationReason: terminationReason))
        default:
            handleUnexpectedEvent(event)
        }
    }

    func handle(_ action: AppAction) {
        if let foreground = currentState as? ForegroundHandling {
            foreground.handle(action)
        } else {
            actionToHandle = action
        }
    }

    func handleUnexpectedEvent(_ event: AppEvent) {
        Logger.lifecycle.error("🔴 Unexpected [\(String(describing: event))] event while in [\(type(of: self))] state!")
        DailyPixel.fireDailyAndCount(pixel: .appDidTransitionToUnexpectedState,
                                     withAdditionalParameters: [PixelParameters.appState: String(describing: type(of: self)),
                                                                PixelParameters.appEvent: String(describing: event)])
    }

}
