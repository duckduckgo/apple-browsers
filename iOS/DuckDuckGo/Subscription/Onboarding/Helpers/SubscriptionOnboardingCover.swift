//
//  SubscriptionOnboardingCover.swift
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

import SwiftUI
import UIKit
import DesignResourcesKit

// MARK: - Presentation

/// Owns the presented cover; also serves as its own anchor view controller for
/// `SubscriptionOnboardingPresenter` below. Held via `@State` by the presenting SwiftUI view.
final class SubscriptionOnboardingViewCoordinator: UIViewController {
    private var presented: UIViewController?
    private var onDismiss: (() -> Void)?

    /// Presents `content`, locked to portrait, from `presenter()`. Calling again while already presenting
    /// the same content type just refreshes it in place; a different caller should use its own coordinator.
    /// `presenter` is only invoked when actually presenting for the first time.
    @MainActor
    func present<Content: View>(_ content: Content, from presenter: () -> UIViewController, onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        guard presented == nil else {
            guard let hosting = presented as? SubscriptionOnboardingPortraitHostingController<Content> else {
                assertionFailure("Already presenting a different Content type — use a separate coordinator instance")
                return
            }
            hosting.rootView = content
            return
        }
        let hosting = SubscriptionOnboardingPortraitHostingController(rootView: content)
        hosting.modalPresentationStyle = .overFullScreen
        hosting.view.backgroundColor = UIColor(designSystemColor: .background)
        presented = hosting
        presenter().present(hosting, animated: true)
    }

    /// `beforeDismiss` runs before the cover's own dismiss animation (e.g. an unanimated pop underneath,
    /// invisible under the still-opaque cover). Must null `presented` first, or a dismantle triggered by
    /// `beforeDismiss` would kill the cover abruptly instead of no-op'ing.
    @MainActor
    func finish(beforeDismiss: () -> Void = {}) {
        guard let presented else { return }
        self.presented = nil
        beforeDismiss()
        let onDismiss = onDismiss
        self.onDismiss = nil
        presented.dismiss(animated: true, completion: onDismiss)
    }

    /// Safety net if the presenting screen is torn down while the cover is still up.
    @MainActor
    func forceDismiss() {
        guard let presented else { return }
        self.presented = nil
        onDismiss = nil
        presented.dismiss(animated: false)
    }
}

extension View {
    /// `.fullScreenCover` replacement, presenting into `SubscriptionOnboardingPortraitHostingController` instead
    /// of SwiftUI's own hosting controller. Dismiss via `viewCoordinator.finish(...)`, not `item = nil`.
    func subscriptionOnboardingCover<Item: Identifiable, CoverContent: View>(
        item: Binding<Item?>,
        viewCoordinator: SubscriptionOnboardingViewCoordinator,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> CoverContent
    ) -> some View {
        background(SubscriptionOnboardingPresenter(item: item, viewCoordinator: viewCoordinator, onDismiss: onDismiss, content: content))
    }
}

// MARK: - Hosting controller

/// Named subclass so `supportedInterfaceOrientations` can be a plain override
private final class SubscriptionOnboardingPortraitHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
}

private struct SubscriptionOnboardingPresenter<Item: Identifiable, CoverContent: View>: UIViewControllerRepresentable {
    let item: Binding<Item?>
    let viewCoordinator: SubscriptionOnboardingViewCoordinator
    let onDismiss: (() -> Void)?
    let content: (Item) -> CoverContent

    func makeUIViewController(context: Context) -> SubscriptionOnboardingViewCoordinator { viewCoordinator }

    func updateUIViewController(_ viewCoordinator: SubscriptionOnboardingViewCoordinator, context: Context) {
        guard let item = item.wrappedValue else { return }
        viewCoordinator.present(content(item), from: {
            var target: UIViewController = viewCoordinator
            while let next = target.parent { target = next }
            return target
        }, onDismiss: onDismiss)
    }

    static func dismantleUIViewController(_ viewCoordinator: SubscriptionOnboardingViewCoordinator, coordinator: ()) {
        viewCoordinator.forceDismiss()
    }
}
