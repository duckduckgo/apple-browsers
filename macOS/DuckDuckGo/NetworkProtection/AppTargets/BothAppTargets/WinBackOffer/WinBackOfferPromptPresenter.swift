//
//  WinBackOfferPromptPresenter.swift
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

import AppKit
import Subscription

protocol WinBackOfferPromptPresenting {
    func tryToShowPrompt(in window: NSWindow?)
}

final class WinBackOfferPromptPresenter: WinBackOfferPromptPresenting {
    private let visibilityManager: WinBackOfferVisibilityManaging

    init(visibilityManager: WinBackOfferVisibilityManaging) {
        self.visibilityManager = visibilityManager
    }

    func tryToShowPrompt(in window: NSWindow?) {
        guard visibilityManager.shouldShowLaunchMessage else { return }
        visibilityManager.setLaunchMessagePresented(true)
        showPrompt(in: window)
    }

    private func showPrompt(in window: NSWindow?) {
        let viewModel = WinBackOfferPromptViewModel(
            confirmAction: { [weak self] in
                self?.handleSeeOffer()
            }
        )

        Task { @MainActor in
            let view = WinBackOfferPromptView(viewModel: viewModel)
            view.show(in: window)
        }
    }

    private func handleSeeOffer() {
        // Open landing page
    }
}
