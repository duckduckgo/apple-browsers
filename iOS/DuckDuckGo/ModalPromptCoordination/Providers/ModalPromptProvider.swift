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

/// How the coordination manager should treat a selected provider.
enum ModalPromptPresentationKind {
    /// The provider supplies a view controller to present. The manager starts the shared
    /// cooldown once it appears, and frees the promo slot when it is dismissed.
    case modal

    /// The provider holds the promo slot until an external event redeems or releases it.
    /// The manager presents nothing and starts no cooldown until redemption.
    ///
    /// Use this for a promo whose UI the app does not own, or whose trigger arrives later than
    /// the foreground checkpoint where providers are evaluated. A deferred provider expresses
    /// its whole eligibility in `isEligibleToPresent(isOnboardingComplete:)`, because
    /// `provideModalPrompt()` is never called for it.
    case deferred
}

/// A type that can provide a prompt to be presented to the centralised modal prompts coordination system.
/// Providers act as lightweight adapters between feature-specific modal prompt logic and the centralised `ModalPromptCoordinationManager`.
@MainActor
protocol ModalPromptProvider {
    /// Whether this provider presents a modal or holds the slot for a later event.
    ///
    /// Default: `.modal`.
    var presentationKind: ModalPromptPresentationKind { get }

    /// Per-provider onboarding gate. The manager calls this before evaluating `provideModalPrompt()`.
    ///
    /// Default: returns `isOnboardingComplete` — providers that need standard gating get it for free.
    /// Override to apply a softer or stricter check.
    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool

    /// Provides a `ModalPromptConfiguration` if the provider has a prompt that is eligible to present.
    /// - Returns: A configured `ModalPromptConfiguration` ready for presentation if it is eligible to present the modal. `nil` otherwise.
    func provideModalPrompt() -> ModalPromptConfiguration?

    /// Called after the modal has been successfully presented.
    /// Use this to update any feature-specific tracking or state.
    ///
    /// For a `.deferred` provider this is called at redemption, not when the slot is taken, so an
    /// attempt that is never redeemed does not consume the promo's eligibility.
    func didPresentModal()

    /// Called when a held `.deferred` slot is released without having been redeemed.
    ///
    /// Default: no-op.
    func didReleaseDeferredSlot()
}

extension ModalPromptProvider {

    var presentationKind: ModalPromptPresentationKind {
        .modal
    }

    /// Default implementation returns `isOnboardingComplete` — providers that need standard gating get it for free.
    /// Override to apply a softer or stricter check.
    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool {
        isOnboardingComplete
    }

    func didPresentModal() {}

    func didReleaseDeferredSlot() {}

}

/// A protocol for modal prompts that can be shown on-demand by the user.
/// (e.g., via modal prompt coordination) and can be re-accessed later by the user when needed.
@MainActor
protocol OnDemandModalPromptProvider {
    /// Indicates whether the prompt can be shown on-demand.
    /// - Returns: `true` if the prompt can be shown on-demand; `false` otherwise.
    var canShowPromptOnDemand: Bool { get }
}
