//
//  SubscriptionPromoModalPromptProvider.swift
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

import Foundation

final class SubscriptionPromoModalPromptProvider: ModalPromptProvider {
    private let presenter: SubscriptionPromoPresenting
    private let coordinator: SubscriptionPromoCoordinating

    init(presenter: SubscriptionPromoPresenting, coordinator: SubscriptionPromoCoordinating) {
        self.presenter = presenter
        self.coordinator = coordinator
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        guard coordinator.shouldPresentLaunchPrompt() else { return nil }
        let prompt = presenter.makeSubscriptionPromoPrompt()
        return ModalPromptConfiguration(viewController: prompt, animated: true)
    }

    func didPresentModal() {
        coordinator.markLaunchPromptPresented()
    }
}
