//
//  VPNUpsellPopoverPresenter.swift
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
import Subscription

protocol VPNUpsellPopoverPresenter {
    func toggle(below view: NSView, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void)
}

final class DefaultVPNUpsellPopoverPresenter: VPNUpsellPopoverPresenter, PopoverPresenter {

    private var popover: VPNUpsellPopover?
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let featureFlagger: FeatureFlagger
    private let primaryCTAHandler: () -> Void

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge, featureFlagger: FeatureFlagger, primaryCTAHandler: @escaping () -> Void) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.primaryCTAHandler = primaryCTAHandler
    }

    var isShown: Bool {
        popover?.isShown ?? false
    }

    func toggle(below view: NSView, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        if isShown {
            dismiss()
        } else {
            show(below: view, onConfirm: onConfirm, onDismiss: onDismiss)
        }
    }

    func show(below view: NSView, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        dismiss()

        let viewModel = VPNUpsellPopoverViewModel(
            subscriptionManager: subscriptionManager,
            featureFlagger: featureFlagger,
            primaryButtonAction: { [weak self] in
                self?.primaryCTAHandler()
                onConfirm()
                self?.dismiss()
            },
            secondaryButtonAction: { [weak self] in
                onDismiss()
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
    }

    func dismiss() {
        guard let popover = popover, popover.isShown else { return }
        popover.close()
        self.popover = nil
    }
}
