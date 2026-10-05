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
import os.log
import PixelKit
import Common

// MARK: - Presentation

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
        guard presented == nil else {
            guard let hosting = presented as? SubscriptionOnboardingPortraitHostingController<Content> else {
                assertionFailure("Already presenting a different Content type — use a separate coordinator instance")
                return
            }
            self.onDismiss = onDismiss
            hosting.rootView = content
            return
        }
        let target = presenter()
        guard target.presentedViewController == nil, target.viewIfLoaded?.window != nil else {
            Logger.subscription.error("Onboarding cover: \(String(describing: target), privacy: .public) is not in a state to present")
            assertionFailure("\(target) is not in a state to present — cannot present onboarding cover")
            PixelKit.fire(SubscriptionPixel.subscriptionOnboardingLaunchFailure(.notPresentable), frequency: .dailyAndCount)
            return
        }
        self.onDismiss = onDismiss
        let hosting = SubscriptionOnboardingPortraitHostingController(rootView: content)
        hosting.modalPresentationStyle = .overFullScreen
        hosting.view.backgroundColor = UIColor(designSystemColor: .background)
        presented = hosting
        target.present(hosting, animated: true) {
            // Force a fresh layout pass once presentation settles to avoid presented content laid out for stake bounds when presented.
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
        }
    }

    /// `beforeDismiss` runs before the cover's own dismiss animation (e.g. an unanimated pop underneath,
    /// invisible under the still-opaque cover).
    @MainActor
    func finish(beforeDismiss: () -> Void = {}) {
        dismissPresented(beforeDismiss: beforeDismiss, animated: true, notifyOnDismiss: true)
    }

    /// Safety net if the presenting screen is torn down while the cover is still up. Unanimated and silent,
    /// deliberately: there's nothing left to animate, and `onDismiss` may reference state tied to the
    /// presenting screen that's disappearing along with it.
    @MainActor
    func forceDismiss() {
        dismissPresented(animated: false, notifyOnDismiss: false)
    }

    /// Falls back to calling `onDismiss` directly if `presented` was already torn out of the hierarchy by
    /// something else (e.g. a caller dismissing the whole presentation stack itself before we get here).
    /// Only applies when `notifyOnDismiss` is true — `forceDismiss` opts out entirely.
    @MainActor
    private func dismissPresented(beforeDismiss: () -> Void = {}, animated: Bool, notifyOnDismiss: Bool) {
        guard let presented else { return }
        self.presented = nil
        beforeDismiss()
        let onDismiss = notifyOnDismiss ? onDismiss : nil
        self.onDismiss = nil
        guard let presenter = presented.presentingViewController else {
            onDismiss?()
            return
        }
        presenter.dismiss(animated: animated, completion: onDismiss)
    }
}

// MARK: - Hosting controller

/// Named subclass so `supportedInterfaceOrientations` can be a plain override
private final class SubscriptionOnboardingPortraitHostingController<Content: View>: UIHostingController<Content> {
    /// Portrait-locked on iPhone only. iPad defers to the default
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        DevicePlatform.isIpad ? super.supportedInterfaceOrientations : .portrait
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
