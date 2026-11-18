//
//  DBPOptOutEmailComposer.swift
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

import MessageUI
import DataBrokerProtectionCore

public protocol DBPOptOutEmailComposing {
    @MainActor var canSendMail: Bool { get }
    @MainActor func compose(_ email: DBPUIOpenOptOutEmailRequest) async -> MFMailComposeResult
}

final class DBPOptOutEmailComposer: NSObject, DBPOptOutEmailComposing {

    private weak var presentingViewController: UIViewController?
    private weak var composeViewController: MFMailComposeViewController?
    var pendingCompose: CheckedContinuation<MFMailComposeResult, Never>?

    init(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
    }

    deinit {
        // Mail holds its delegate weakly, so the dashboard would otherwise wait forever for a result.
        pendingCompose?.resume(returning: .cancelled)
    }

    @MainActor var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// Closing the dashboard also closes Mail without a delegate callback, so the request resolves as not sent here.
    @MainActor
    func presenterDidDisappear() {
        guard pendingCompose != nil, composeViewController?.presentingViewController == nil else { return }
        let continuation = pendingCompose
        pendingCompose = nil
        continuation?.resume(returning: .cancelled)
    }

    @MainActor
    func compose(_ email: DBPUIOpenOptOutEmailRequest) async -> MFMailComposeResult {
        guard pendingCompose == nil, canSendMail, let presentingViewController = readyPresentingViewController else {
            return .failed
        }

        let composeViewController = MFMailComposeViewController()
        composeViewController.mailComposeDelegate = self
        composeViewController.isModalInPresentation = true
        composeViewController.setToRecipients([email.to])
        composeViewController.setSubject(email.subject)
        composeViewController.setMessageBody(email.body, isHTML: false)

        return await withCheckedContinuation { continuation in
            pendingCompose = continuation
            self.composeViewController = composeViewController
            presentingViewController.present(composeViewController, animated: true)
        }
    }
}

private extension DBPOptOutEmailComposer {
    @MainActor
    var readyPresentingViewController: UIViewController? {
        guard let presentingViewController,
              presentingViewController.viewIfLoaded?.window != nil,
              !presentingViewController.isBeingDismissed,
              presentingViewController.presentedViewController == nil else {
            return nil
        }
        return presentingViewController
    }
}

extension DBPOptOutEmailComposer: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        let continuation = pendingCompose
        pendingCompose = nil
        controller.dismiss(animated: true) {
            continuation?.resume(returning: result)
        }
    }
}
