//
//  VPNPopoverPresenter.swift
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
import SwiftUI
import Foundation
import BrowserServicesKit
import PixelKit
import Subscription

/// This protocol is used to present the VPN upsell popover.
/// It is triggered from the VPN toolbar button if users are eligible for the upsell
protocol VPNUpsellPopoverPresenter {
    /// Toggles the popover visibility.
    /// If the popover is already shown, it will be dismissed.
    /// If the popover is not shown, it will be shown below the given view.
    func toggle(below view: NSView)
}

final class DefaultVPNUpsellPopoverPresenter: VPNUpsellPopoverPresenter, PopoverPresenter {

    private var popover: VPNUpsellPopover?
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let featureFlagger: FeatureFlagger
    private let vpnUpsellVisibilityManager: VPNUpsellVisibilityManager
    private let pixelHandler: (PrivacyProPixel) -> Void

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         featureFlagger: FeatureFlagger,
         vpnUpsellVisibilityManager: VPNUpsellVisibilityManager,
         pixelHandler: @escaping (PrivacyProPixel) -> Void = { PixelKit.fire($0) }) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.vpnUpsellVisibilityManager = vpnUpsellVisibilityManager
        self.pixelHandler = pixelHandler
    }

    var isShown: Bool {
        popover?.isShown ?? false
    }

    func toggle(below view: NSView) {
        if isShown {
            dismiss()
        } else {
            Task { @MainActor in
                show(below: view)
            }
        }
    }

    @MainActor
    func show(below view: NSView) {
        dismiss()

        let viewModel = VPNUpsellPopoverViewModel(
            subscriptionManager: subscriptionManager,
            featureFlagger: featureFlagger,
            vpnUpsellVisibilityManager: vpnUpsellVisibilityManager,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let swiftUIView = VPNUpsellPopoverView(viewModel: viewModel).fixedSize()
        let hostingController = NSHostingController(rootView: swiftUIView)

        // Force layout and set frame explicitly to ensure proper positioning
        hostingController.loadView()
        hostingController.view.layoutSubtreeIfNeeded()
        hostingController.view.frame = CGRect(origin: .zero, size: hostingController.view.intrinsicContentSize)

        let newPopover = VPNUpsellPopover(viewController: hostingController)
        self.popover = newPopover

        show(newPopover, positionedBelow: view)

        // Fire pixel when popover is shown
        pixelHandler(.privacyProToolbarButtonPopoverShown)
    }

    func dismiss() {
        guard let popover = popover, popover.isShown else { return }
        popover.close()
        self.popover = nil
    }
}
