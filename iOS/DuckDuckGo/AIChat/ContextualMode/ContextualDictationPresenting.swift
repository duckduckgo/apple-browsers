//
//  ContextualDictationPresenting.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

/// A surface showing the contextual input hosts dictation for it: the modal presents over whatever is on
/// screen, and the transcript goes back to the input rather than to the surface.
@MainActor
protocol ContextualDictationPresenting: UIViewController, VoiceSearchViewControllerDelegate {
    func applyDictatedQuery(_ query: String)
}

extension ContextualDictationPresenting {

    func presentVoiceSearch() {
        let voiceSearchController = VoiceSearchViewController(preferredTarget: .AIChat, hideToggle: true)
        voiceSearchController.delegate = self
        voiceSearchController.modalTransitionStyle = .crossDissolve
        voiceSearchController.modalPresentationStyle = .overFullScreen
        present(voiceSearchController, animated: true)
    }

    func voiceSearchViewController(_ viewController: VoiceSearchViewController, didFinishQuery query: String?, target: VoiceSearchTarget) {
        viewController.dismiss(animated: true)
        guard let query, !query.isEmpty else { return }
        applyDictatedQuery(query)
    }
}
