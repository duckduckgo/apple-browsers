//
//  ContactPreviewHelper.swift
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
import UIKit
import UIKitExtensions

/// Builds the native "Add to Contacts" card, shared by the link-tap and Downloads-list entry points.
enum ContactCardFactory {

    static func makeContactCard(for contact: CNContact,
                                delegate: CNContactViewControllerDelegate,
                                cancelTarget: Any,
                                cancelAction: Selector,
                                pixelFiring: PixelFiring.Type) -> UINavigationController {
        let contactViewController = CNContactViewController(forUnknownContact: contact)
        contactViewController.contactStore = CNContactStore()
        contactViewController.allowsActions = true
        contactViewController.delegate = delegate
        let cancelButton = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: cancelTarget,
            action: cancelAction
        )
        // Stable anchor for E2E tests: the system Contacts UI renders its content (name, fields) in
        // a remote view whose accessibility is only intermittently captured, but this nav-bar button
        // is app-owned and reliably exposed. Distinguishes the card from the browser omnibar's Cancel.
        cancelButton.accessibilityIdentifier = "contactPreviewCancelButton"
        contactViewController.navigationItem.leftBarButtonItem = cancelButton
        pixelFiring.fire(.vcardContactEditorPresented, withAdditionalParameters: [:])
        return UINavigationController(rootViewController: contactViewController)
    }
}

final class ContactCardCompletion {

    private let pixelFiring: PixelFiring.Type
    private var didComplete = false

    init(pixelFiring: PixelFiring.Type) {
        self.pixelFiring = pixelFiring
    }

    /// On the first call, fires the saved/cancelled pixel and returns `true` so the caller can run
    /// its dismissal + callbacks. Every later call returns `false`: the Cancel button, the delegate
    /// callback, and a swipe-dismiss can all arrive, but only the first one wins.
    func recordCompletion(saved: Bool) -> Bool {
        guard !didComplete else { return false }
        didComplete = true
        pixelFiring.fire(saved ? .vcardContactEditorSaved : .vcardContactEditorCancelled, withAdditionalParameters: [:])
        return true
    }
}

final class ContactPreviewHelper: NSObject, FilePreview {

    var onDismiss: (() -> Void)?

    var onSaved: (() -> Void)?

    var onParseFailure: (() -> Void)?

    private let filePath: URL
    private weak var viewController: UIViewController?
    private let pixelFiring: PixelFiring.Type
    private weak var presentedNavigationController: UINavigationController?
    private let completion: ContactCardCompletion

    required convenience init(_ filePath: URL, viewController: UIViewController) {
        self.init(filePath, viewController: viewController, pixelFiring: Pixel.self)
    }

    init(_ filePath: URL, viewController: UIViewController, pixelFiring: PixelFiring.Type) {
        self.filePath = filePath
        self.viewController = viewController
        self.pixelFiring = pixelFiring
        self.completion = ContactCardCompletion(pixelFiring: pixelFiring)
        super.init()
    }

    func preview() {
        // Read + deserialize off the main thread: a .vcf with an embedded photo can be large.
        DispatchQueue.global(qos: .userInitiated).async { [filePath, weak self] in
            let result = VCardFileReader.read(at: filePath)
            DispatchQueue.main.async {
                self?.handleParseResult(result)
            }
        }
    }

    private func handleParseResult(_ result: VCardFileReader.Result?) {
        guard let result else {
            pixelFiring.fire(.vcardContactFallbackParseFailure, withAdditionalParameters: [:])
            reportParseFailure()
            return
        }
        if result.wasTruncated {
            // Present the first contact and silently ignore the rest.
            pixelFiring.fire(.vcardContactMultipleContactsTruncated, withAdditionalParameters: [:])
        }
        presentContactCard(for: result.contact)
    }

    private func presentContactCard(for contact: CNContact) {
        guard let viewController else {
            onDismiss?()
            return
        }
        let presenter = viewController.topMostPresentedViewController() ?? viewController
        let navigationController = ContactCardFactory.makeContactCard(
            for: contact,
            delegate: self,
            cancelTarget: self,
            cancelAction: #selector(cancelButtonTapped),
            pixelFiring: pixelFiring
        )
        // Catch interactive (swipe-down) dismissal, which does NOT call CNContactViewControllerDelegate.
        navigationController.presentationController?.delegate = self
        presentedNavigationController = navigationController
        presenter.present(navigationController, animated: true)
    }

    @objc private func cancelButtonTapped() {
        complete(saved: false, alreadyDismissed: false)
    }

    /// Notifies the owner, dismissing the contact card first unless UIKit already dismissed it
    /// interactively (`alreadyDismissed`). The shared completion fires the saved/cancelled pixel and
    /// guards so the Cancel button, the delegate callback, and a swipe-dismiss can't run it twice.
    private func complete(saved: Bool, alreadyDismissed: Bool) {
        guard completion.recordCompletion(saved: saved) else { return }
        let reportSaved = onSaved
        let reportDismiss = onDismiss
        let finish = {
            if saved { reportSaved?() }
            reportDismiss?()
        }
        if !alreadyDismissed, let presentedNavigationController {
            presentedNavigationController.dismiss(animated: true, completion: finish)
        } else {
            finish()
        }
    }

    private func reportParseFailure() {
        onParseFailure?()
        onDismiss?()
    }
}

extension ContactPreviewHelper: CNContactViewControllerDelegate {

    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        // A non-nil contact means the user added it (Create New / Add to Existing); nil means cancelled.
        complete(saved: contact != nil, alreadyDismissed: false)
    }
}

extension ContactPreviewHelper: UIAdaptivePresentationControllerDelegate {

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Interactive swipe-down: UIKit has already dismissed the card and the contact-view delegate is
        // not called, so record it here (treated as a cancel, matching the Cancel button).
        complete(saved: false, alreadyDismissed: true)
    }
}
