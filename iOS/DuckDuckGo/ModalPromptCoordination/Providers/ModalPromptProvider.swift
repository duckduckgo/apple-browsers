//
//  ModalPromptProvider.swift
//  DuckDuckGo
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

import UIKit

/// Represent the Configuration for presenting a modal prompt.
struct ModalPromptConfiguration {
    /// The view controller to present.
    /// The provider is responsible for configuring the view controller's presentation properties
    /// (modalPresentationStyle, modalTransitionStyle, isModalInPresentation) before returning it.
    let viewController: UIViewController
    /// Whether the presentation should be animated or not. The default value of this property is `true`.
    let animated: Bool

    init(
        viewController: UIViewController,
        animated: Bool = true
    ) {
        self.viewController = viewController
        self.animated = animated
    }
}

/// A type that can provide a prompt to be presented to the centralised modal prompts coordination system.
/// Providers act as lightweight adapters between feature-specific modal prompt logic and the centralised `ModalPromptCoordinationManager`.
@MainActor
protocol ModalPromptProvider {
    /// Provides a `ModalPromptConfiguration` if the provider has a prompt that is eligible to present.
    /// - Returns: A configured `ModalPromptConfiguration` ready for presentation if it is eligible to present the modal. `nil` otherwise.
    func provideModalPrompt() -> ModalPromptConfiguration?

    /// Called after the modal has been successfully presented.
    /// Use this to update any feature-specific tracking or state.
    func didPresentModal()
}

extension ModalPromptProvider {

    func didPresentModal() {}

}
