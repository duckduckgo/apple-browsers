//
//  CookiePopupProtectionOptInModalPromptProvider.swift
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

import Persistence
import SwiftUI
import UIKit

/// Persisted "already shown on launch" flag for the Cookie Pop-up Protection opt-in dialog.
/// ponytail: the modal prompt queue tracks no per-prompt history, so we keep our own one-shot flag.
struct CookiePopupProtectionOptInPromptStore {
    private static let hasShownLaunchPromptKey = "com.duckduckgo.cookiePopupProtection.optIn.hasShownLaunchPrompt"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var hasShownLaunchPrompt: Bool {
        get { (try? keyValueStore.object(forKey: Self.hasShownLaunchPromptKey)) as? Bool ?? false }
        nonmutating set { try? keyValueStore.set(newValue, forKey: Self.hasShownLaunchPromptKey) }
    }
}

/// Shows the Cookie Pop-up Protection opt-in dialog on app launch via the modal prompt queue.
/// ponytail: always eligible until shown once — real conditions come later.
final class CookiePopupProtectionOptInModalPromptProvider: ModalPromptProvider {

    private let store: CookiePopupProtectionOptInPromptStore

    init(store: CookiePopupProtectionOptInPromptStore) {
        self.store = store
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        guard !store.hasShownLaunchPrompt else { return nil }
        return ModalPromptConfiguration(viewController: Self.makeViewController())
    }

    func didPresentModal() {
        store.hasShownLaunchPrompt = true
    }

    /// Builds the opt-in dialog hosting controller, configured to dismiss itself on Confirm.
    /// Shared with the debug menu's manual presentation.
    @MainActor
    static func makeViewController() -> UIViewController {
        let variant: CookiePopupProtectionOptInVariant = AppUserDefaults().autoconsentEnabled ? .whenEnabled : .whenDisabled
        weak var controller: UIViewController?
        let hostingController = UIHostingController(rootView: CookiePopupProtectionOptInView(variant: variant, onConfirm: {
            controller?.dismiss(animated: true)
        }))
        controller = hostingController
        // Block swipe-to-dismiss — the dialog can only be dismissed via its own controls.
        hostingController.isModalInPresentation = true
        // iPad: present as a fixed-size form sheet instead of a full-height page sheet.
        if UIDevice.current.userInterfaceIdiom == .pad {
            hostingController.modalPresentationStyle = .formSheet
            hostingController.preferredContentSize = CGSize(width: 480, height: 744)
        }
        return hostingController
    }
}
