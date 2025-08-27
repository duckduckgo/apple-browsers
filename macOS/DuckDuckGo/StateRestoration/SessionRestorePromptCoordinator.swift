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

protocol SessionRestorePromptCoordinating {
    func markUIReady()
    func showRestoreSessionPrompt(restoreAction: @escaping (Bool) -> Void)
}

final class SessionRestorePromptCoordinator: SessionRestorePromptCoordinating {
    private enum State {
        case initial
        case restoreNeeded((Bool) -> Void)
        case uiReady
        case promptShown
    }

    private let featureFlagger: FeatureFlagger
    private var state: State = .initial

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
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

    private func showPrompt(with restoreAction: @escaping (Bool) -> Void) {
        guard featureFlagger.isFeatureOn(.restoreSessionPrompt) else { return }
        state = .promptShown
        NotificationCenter.default.post(name: .sessionRestorePromptShouldBeShown, object: restoreAction)
    }
}

extension Notification.Name {
    static let sessionRestorePromptShouldBeShown = Notification.Name("sessionRestorePromptShouldBeShown")
}
