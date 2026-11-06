//
//  AutofillPromptKeyboardHandler.swift
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

import UIKit

@MainActor
final class AutofillPromptKeyboardHandler: NSObject {

    private let notificationCenter: NotificationCenter
    private let firstResponderProvider: @MainActor () -> UIResponder?
    private weak var promptViewController: UIViewController?
    private weak var webView: UIView?

    init(notificationCenter: NotificationCenter = .default,
         firstResponderProvider: @escaping @MainActor () -> UIResponder? = { UIResponder.currentFirstResponder() }) {
        self.notificationCenter = notificationCenter
        self.firstResponderProvider = firstResponderProvider
        super.init()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func startObserving(for promptViewController: UIViewController, webView: UIView) {
        self.promptViewController = promptViewController
        self.webView = webView
        // Avoid duplicate registrations if another prompt opens before the previous one is cleaned up.
        stopObserving()
        notificationCenter.addObserver(self,
                                       selector: #selector(keyboardWillShow),
                                       name: UIResponder.keyboardWillShowNotification,
                                       object: nil)
    }

    func stopObserving() {
        notificationCenter.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let promptViewController,
              promptViewController.presentingViewController != nil else {
            // Stop observing after dismissal without interrupting the keyboard the user just opened.
            stopObserving()
            return
        }

        guard let webView,
              webView.window?.isKeyWindow == true,
              let firstResponder = firstResponderProvider(),
              firstResponder.isInViewHierarchy(of: webView) else {
            return
        }

        webView.endEditing(true)
        webView.resignFirstResponder()
    }
}
