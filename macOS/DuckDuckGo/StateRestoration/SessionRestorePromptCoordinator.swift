//
//  SessionRestorePromptCoordinator.swift
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

import Foundation
import BrowserServicesKit
import Combine
import PixelKit

protocol SessionRestorePromptCoordinating {
    /// Current state of the Session Restore prompt
    var state: SessionRestorePromptCoordinator.State { get }
    /// Publisher for the Session Restore prompt state
    var statePublisher: AnyPublisher<SessionRestorePromptCoordinator.State, Never> { get }
    func markUIReady()
    func showRestoreSessionPrompt(restoreAction: @escaping (Bool) -> Void)
    func applicationWillTerminate()
}

final class SessionRestorePromptCoordinator: SessionRestorePromptCoordinating {
    enum State {
        case initial
        case restoreNeeded((Bool) -> Void)
        case uiReady
        case promptShown
        case promptDismissed

        var isVisible: Bool {
            switch self {
            case .promptShown:
                return true
            default:
                return false
            }
        }
    }

    private let pixelFiring: PixelFiring?
    @Published private(set) var state: State = .initial
    var statePublisher: AnyPublisher<SessionRestorePromptCoordinator.State, Never> { $state.eraseToAnyPublisher() }

    init(pixelFiring: PixelFiring?) {
        self.pixelFiring = pixelFiring
    }

    func markUIReady() {
        switch state {
        case .initial:
            state = .uiReady
        case .restoreNeeded(let restoreAction):
            showPrompt(with: restoreAction)
        default:
            break
        }
    }

    func showRestoreSessionPrompt(restoreAction: @escaping (Bool) -> Void) {
        switch state {
        case .initial:
            state = .restoreNeeded(restoreAction)
        case .uiReady:
            showPrompt(with: restoreAction)
        default:
            break
        }
    }

    func applicationWillTerminate() {
        if case .promptShown = state {
            pixelFiring?.fire(SessionRestorePromptPixel.appTerminatedWhilePromptShowing)
        }
    }

    private func showPrompt(with restoreAction: @escaping (Bool) -> Void) {
        state = .promptShown
        let dismissPromptAction = { [weak self] restoreSession in
            self?.state = .promptDismissed
            if restoreSession {
                self?.pixelFiring?.fire(SessionRestorePromptPixel.promptDismissedWithRestore)
            } else {
                self?.pixelFiring?.fire(SessionRestorePromptPixel.promptDismissedWithoutRestore)
            }
            restoreAction(restoreSession)
        }
        NotificationCenter.default.post(name: .sessionRestorePromptShouldBeShown, object: dismissPromptAction)
        pixelFiring?.fire(SessionRestorePromptPixel.promptShown)
    }
}

extension Notification.Name {
    static let sessionRestorePromptShouldBeShown = Notification.Name("sessionRestorePromptShouldBeShown")
}
