//
//  ContactCardView.swift
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

import Contacts
import ContactsUI
import Core
import SwiftUI
import UIKit

/// Presents the native "Add to Contacts" card for a parsed vCard contact from the Downloads list.
struct ContactCardView: UIViewControllerRepresentable {

    let contact: CNContact
    let onSaved: () -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        ContactCardFactory.makeContactCard(
            for: contact,
            delegate: context.coordinator,
            cancelTarget: context.coordinator,
            cancelAction: #selector(Coordinator.cancelButtonTapped),
            pixelFiring: context.coordinator.pixelFiring
        )
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    static func dismantleUIViewController(_ controller: UINavigationController, coordinator: Coordinator) {
        // Catches swipe-dismiss, which doesn't route through the Cancel button or the delegate.
        // Guarded by didComplete, so it's a no-op if the user already cancelled or added the contact.
        coordinator.complete(saved: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSaved: onSaved, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let pixelFiring: PixelFiring.Type
        private let onSaved: () -> Void
        private let onDismiss: () -> Void
        private let completion: ContactCardCompletion

        init(onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void, pixelFiring: PixelFiring.Type = Pixel.self) {
            self.onSaved = onSaved
            self.onDismiss = onDismiss
            self.pixelFiring = pixelFiring
            self.completion = ContactCardCompletion(pixelFiring: pixelFiring)
        }

        @objc func cancelButtonTapped() {
            complete(saved: false)
        }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            complete(saved: contact != nil)
        }

        /// The shared completion fires the saved/cancelled pixel and guards so the delegate callback,
        /// the Cancel button, and a swipe-dismiss can't run this more than once.
        func complete(saved: Bool) {
            guard completion.recordCompletion(saved: saved) else { return }
            if saved { onSaved() }
            onDismiss()
        }
    }
}
